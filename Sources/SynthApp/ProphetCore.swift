import AVFoundation
import AudioToolbox
import Foundation

final class SharedSynthParameters {
    private var raw = SynthParameters()
    private let lock = NSLock()

    func set(_ edit: (inout SynthParameters) -> Void) {
        lock.lock()
        edit(&raw)
        lock.unlock()
    }

    func snapshot() -> SynthParameters {
        lock.lock()
        defer { lock.unlock() }
        return raw
    }
}

private struct AnalogEnvelope {
    enum Stage { case attack, decay, sustain, release }
    var stage: Stage = .release
    var level: Float = 0

    mutating func trigger() { stage = .attack }

    mutating func advance(gate: Bool, attack: Float, decay: Float, sustain: Float, release: Float, sr: Float) {
        if !gate { stage = .release }
        let target = min(1, max(0, sustain))
        switch stage {
        case .attack:
            // An exponential charge towards a voltage above the trigger threshold.
            level += (1.3 - level) * (1 - expf(-1.466337 / max(1, attack * sr)))
            if level >= 1 { level = 1; stage = .decay }
        case .decay:
            level += (target - level) * (1 - expf(-4.60517 / max(1, decay * sr)))
            if abs(level - target) < 0.0001 { level = target; stage = .sustain }
        case .sustain:
            level += (target - level) * (1 - expf(-1 / (0.005 * sr)))
        case .release:
            level *= expf(-9.21034 / max(1, release * sr))
            if level < 0.00001 { level = 0 }
        }
    }
}

private struct VoiceState {
    var note: Int = 60
    var active = false
    var held = false
    var age: UInt64 = 0
    var velocity: Float = 0.85

    var targetHz: Float = 261.63
    var glideHz: Float = 261.63

    var phaseA: Float = 0
    var phaseB: Float = 0

    var filterEnvelope = AnalogEnvelope()
    var ampEnvelope = AnalogEnvelope()

    var y1: Float = 0
    var y2: Float = 0
    var y3: Float = 0
    var y4: Float = 0

    var filterOutput: Float = 0

    var driftA: Float = 0
    var driftB: Float = 0
}

final class ProphetLikeAudioUnit: AUAudioUnit {
    static var sharedParameters = SharedSynthParameters()

    private let outputBus: AUAudioUnitBus
    private var outputBusArray: AUAudioUnitBusArray!
    private var inputBusArray: AUAudioUnitBusArray!
    private let params: SharedSynthParameters

    private var sampleRateF: Float = 48_000
    private var voices = Array(repeating: VoiceState(), count: 5)
    private var ageCounter: UInt64 = 0
    private var rrCursor: Int = 0

    private var lastAutoTuneTrigger: UInt32 = 0
    private var lfoPhase: Float = 0
    private var pink = SIMD3<Float>(repeating: 0)
    private var referencePhase: Float = 0
    private var heldKeys = Set<Int>()
    private var lastUnison = false
    private let eventLock = NSLock()
    private var pendingEvents = [(Int, Bool)]()
    private var rngState: UInt32 = 0x1234ABCD

    override init(componentDescription: AudioComponentDescription, options: AudioComponentInstantiationOptions = []) throws {
        self.params = Self.sharedParameters
        outputBus = try AUAudioUnitBus(format: AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!)
        try super.init(componentDescription: componentDescription, options: options)
        outputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
        inputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [])
    }

    override var outputBusses: AUAudioUnitBusArray { outputBusArray }
    override var inputBusses: AUAudioUnitBusArray { inputBusArray }

    override func allocateRenderResources() throws {
        try super.allocateRenderResources()
        sampleRateF = Float(outputBus.format.sampleRate)
    }

    override var internalRenderBlock: AUInternalRenderBlock {
        return { [weak self] _, _, frameCount, _, outputData, _, _ in
            guard let self else { return noErr }
            let p = self.params.snapshot()
            self.eventLock.lock()
            let events = self.pendingEvents
            self.pendingEvents.removeAll(keepingCapacity: true)
            self.eventLock.unlock()
            if p.unisonMode != self.lastUnison {
                self.lastUnison = p.unisonMode
                for i in self.voices.indices { self.voices[i].held = false }
                let notes = self.heldKeys.sorted()
                self.heldKeys.removeAll()
                for note in notes { self.handleNoteOn(note, velocity: 1) }
            }
            for (note, on) in events {
                if on { self.handleNoteOn(note, velocity: 1) } else { self.handleNoteOff(note) }
            }

            if p.autoTuneTrigger != self.lastAutoTuneTrigger {
                self.lastAutoTuneTrigger = p.autoTuneTrigger
                for i in self.voices.indices {
                    self.voices[i].driftA = 0
                    self.voices[i].driftB = 0
                }
            }

            let sr = self.sampleRateF
            let lfoStep = (2.0 * Float.pi * max(0.04, min(20, p.lfoRateHz))) / sr

            let buffers = UnsafeMutableAudioBufferListPointer(outputData)
            guard buffers.count >= 2 else { return noErr }
            guard let left = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            guard let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }

            for i in 0..<Int(frameCount) {
                self.lfoPhase += lfoStep
                if self.lfoPhase > 2.0 * .pi {
                    self.lfoPhase -= 2.0 * .pi
                }
                let lfo = (p.lfoSaw ? self.evalLFO(phase: self.lfoPhase, waveform: 1) : 0)
                    + (p.lfoTriangle ? self.evalLFO(phase: self.lfoPhase, waveform: 0) : 0)
                    + (p.lfoSquare ? self.evalLFO(phase: self.lfoPhase, waveform: 2) : 0)
                let white = self.randBipolar()
                // Three-pole pinking filter. The mixer retains the white source.
                self.pink.x = 0.99765 * self.pink.x + white * 0.099046
                self.pink.y = 0.963 * self.pink.y + white * 0.2965164
                self.pink.z = 0.57 * self.pink.z + white * 1.0526913
                let pinkNoise = (self.pink.x + self.pink.y + self.pink.z + white * 0.1848) * 0.2
                let wheel = (lfo * (1-p.wheelSourceMix) + pinkNoise * p.wheelSourceMix) * p.modWheel

                var outL: Float = 0
                var outR: Float = 0

                for vi in self.voices.indices {
                    if !self.voices[vi].active { continue }

                    self.voices[vi].filterEnvelope.advance(gate: self.voices[vi].held, attack: p.envAAttack, decay: p.envADecay, sustain: p.envASustain, release: p.releaseEnabled ? p.envARelease : 0.005, sr: sr)
                    self.voices[vi].ampEnvelope.advance(gate: self.voices[vi].held, attack: p.envBAttack, decay: p.envBDecay, sustain: p.envBSustain, release: p.releaseEnabled ? p.envBRelease : 0.005, sr: sr)

                    if !self.voices[vi].held && self.voices[vi].ampEnvelope.level < 0.0001 {
                        self.voices[vi].active = false
                        continue
                    }

                    let globalTune = p.masterTuneSemitones + (p.pitchWheel * 7)
                    let glideTarget = self.voices[vi].targetHz * powf(2.0, globalTune / 12.0)
                    if p.unisonMode && p.glideTime > 0 {
                        let glideCoeff = min(1.0, (1.0 / sr) / max(0.001, p.glideTime))
                        self.voices[vi].glideHz += (glideTarget - self.voices[vi].glideHz) * glideCoeff
                    } else {
                        self.voices[vi].glideHz = glideTarget
                    }

                    // Slow wander plus repeatable voice-card offsets, expressed in cents.
                    let driftCoeff = 1 - expf(-1 / (sr * 0.8))
                    self.voices[vi].driftA += driftCoeff * (self.randBipolar() * 120 - self.voices[vi].driftA)
                    self.voices[vi].driftB += driftCoeff * (self.randBipolar() * 120 - self.voices[vi].driftB)
                    let cardOffset = sinf(Float(vi + 1) * 2.39996) * 5 * 0.15

                    let ratioA = powf(2, (p.oscAFrequency.rounded()-24)/12)
                    let ratioB = powf(2, (p.oscBFrequency.rounded()-24)/12)
                    let trackB = p.oscBKeyboardTrack ? self.voices[vi].glideHz : 261.6256 * powf(2,globalTune/12)
                    let baseB = p.oscBLowFreqMode ? 0.4 * powf(75, p.oscBFrequency/48) * (trackB/261.6256) : trackB * ratioB
                    var hzB = baseB * powf(2, (p.oscBFineCents - cardOffset*0.7 + self.voices[vi].driftB*0.15)/1200)
                    if p.lfoToOscB { hzB *= powf(2, wheel*2) }
                    let pwB = p.oscBPulseWidth + (p.lfoToPWB ? wheel*0.49 : 0)
                    let sourceB = self.oscillator(phase:self.voices[vi].phaseB, saw:p.oscBSaw, triangle:p.oscBTriangle, pulse:p.oscBPulse, width:pwB, step:min(0.45,hzB/sr))
                    let poly = p.polyModFilterEnv*self.voices[vi].filterEnvelope.level + p.polyModOscB*sourceB
                    var hzA = self.voices[vi].glideHz * ratioA * powf(2,(cardOffset+self.voices[vi].driftA*0.15)/1200)
                    if p.polyModToFreqA { hzA *= powf(2,poly*4) }
                    if p.lfoToOscA { hzA *= powf(2,wheel*2) }

                    hzA = min(sr * 0.45, max(0.01, hzA))
                    hzB = min(sr * 0.45, max(0.01, hzB))
                    self.voices[vi].phaseA += (2.0 * .pi * hzA) / sr
                    self.voices[vi].phaseB += (2.0 * .pi * hzB) / sr
                    // B is the master; preserve the fractional time since its wrap.
                    if p.oscSync && self.voices[vi].phaseB >= 2.0 * .pi {
                        let fraction = (self.voices[vi].phaseB - 2.0 * .pi) / (2.0 * .pi * hzB / sr)
                        self.voices[vi].phaseA = fraction * (2.0 * .pi * hzA / sr)
                    }
                    self.voices[vi].phaseA.formTruncatingRemainder(dividingBy: 2.0 * .pi)
                    self.voices[vi].phaseB.formTruncatingRemainder(dividingBy: 2.0 * .pi)

                    let pwA = p.oscAPulseWidth + (p.lfoToPWA ? wheel*0.49 : 0) + (p.polyModToPWA ? poly*0.49 : 0)
                    let oscA = self.oscillator(phase:self.voices[vi].phaseA, saw:p.oscASaw, triangle:false, pulse:p.oscAPulse, width:pwA, step:hzA/sr)
                    let oscB = self.oscillator(phase:self.voices[vi].phaseB, saw:p.oscBSaw, triangle:p.oscBTriangle, pulse:p.oscBPulse, width:pwB, step:hzB/sr)
                    let mix = oscA*p.oscALevel + oscB*p.oscBLevel + white*p.noiseLevel
                    let kbTrack = p.filterKeyboardTrack ? log2f(max(0.001,self.voices[vi].glideHz/261.6256))/log2f(1000) : 0
                    let wheelFilter = p.lfoToFilter ? wheel*0.5 : 0
                    let envFilter = p.filterEnvAmount*self.voices[vi].filterEnvelope.level + (p.polyModToFilter ? poly*0.5 : 0)
                    var cutoffNorm = p.cutoffNorm + kbTrack + wheelFilter + envFilter
                    cutoffNorm = min(0.99, max(0.001, cutoffNorm))
                    let cutoffHz = 20.0 * powf(1000.0, cutoffNorm)
                    // Two substeps of a topology-preserving four-pole low-pass.
                    // Solve the instantaneous feedback loop before updating the integrators.
                    let g = tanf(.pi * min(cutoffHz, sr * 0.4) / (sr * 2))
                    let G = g / (1 + g)
                    let G2 = G * G
                    let G3 = G2 * G
                    let G4 = G2 * G2
                    let k = min(4.4, max(0, p.resonance) * (4 / 0.7))
                    let color: Float = 0.95 // Fixed Rev3-style CEM response.
                    for _ in 0..<2 {
                        let feedback = (G3 * self.voices[vi].y1 + G2 * self.voices[vi].y2
                            + G * self.voices[vi].y3 + self.voices[vi].y4) / (1 + g)
                        let input = (tanhf((mix + white*0.0000001) * 0.65 * color) / color - k * feedback) / (1 + k * G4)
                        let saturated = tanhf(input * color) / color
                        let a = self.filterPole(saturated, state: &self.voices[vi].y1, gain: G)
                        let b = self.filterPole(a, state: &self.voices[vi].y2, gain: G)
                        let c = self.filterPole(b, state: &self.voices[vi].y3, gain: G)
                        self.voices[vi].filterOutput = self.filterPole(c, state: &self.voices[vi].y4, gain: G)
                    }

                    let voiceOut = tanhf(self.voices[vi].filterOutput) * self.voices[vi].ampEnvelope.level
                    outL += voiceOut
                    outR += voiceOut // Original mono output, duplicated for the host.
                }
                self.referencePhase += 2 * .pi * 440 / sr
                self.referencePhase.formTruncatingRemainder(dividingBy: 2 * .pi)
                if p.referenceA440 {
                    let reference = sinf(self.referencePhase)*0.35
                    outL += reference; outR += reference
                }

                left[i] = outL * 0.18 * min(1, max(0, p.masterVolume))
                right[i] = outR * 0.18 * min(1, max(0, p.masterVolume))
            }
            return noErr
        }
    }

    // UI events are consumed on the render thread; the UI never mutates voices.
    func noteOn(_ midi: Int, velocity: Float) { enqueue(midi, on: true) }
    func noteOff(_ midi: Int) { enqueue(midi, on: false) }
    private func enqueue(_ midi: Int, on: Bool) {
        guard (0...127).contains(midi) else { return }
        eventLock.lock()
        pendingEvents.append((midi,on))
        eventLock.unlock()
    }

    private func handleNoteOn(_ midi: Int, velocity: Float) {
        let previousLowest = heldKeys.min()
        heldKeys.insert(midi)
        let hz = 440.0 * powf(2.0, Float(midi - 69) / 12.0)
        let p = params.snapshot()
        if p.unisonMode {
            guard let lowest = heldKeys.min(), lowest != previousLowest else { return }
            noteOnUnison(midi: lowest, hz: 440*powf(2,Float(lowest-69)/12), velocity: 1)
            return
        }

        ageCounter &+= 1

        var slot: Int? = nil
        for offset in 0..<voices.count {
            let idx = (rrCursor + offset) % voices.count
            if !voices[idx].active {
                slot = idx
                rrCursor = (idx + 1) % voices.count
                break
            }
        }
        if slot == nil { slot = voices.indices.min { voices[$0].age < voices[$1].age } }
        guard let idx = slot else { return }
        let wasActive = voices[idx].active

        voices[idx].note = midi
        voices[idx].active = true
        voices[idx].held = true
        voices[idx].filterEnvelope.trigger()
        voices[idx].ampEnvelope.trigger()
        voices[idx].age = ageCounter
        voices[idx].velocity = min(1.0, max(0.0, velocity))
        voices[idx].targetHz = hz
        if !wasActive { voices[idx].glideHz = hz }
    }

    private func handleNoteOff(_ midi: Int) {
        let previousLowest = heldKeys.min()
        heldKeys.remove(midi)
        let p = params.snapshot()
        if p.unisonMode {
            if let lowest = heldKeys.min() {
                if lowest != previousLowest { noteOnUnison(midi: lowest, hz: 440*powf(2,Float(lowest-69)/12), velocity: 1) }
            } else {
                for i in voices.indices where voices[i].active { voices[i].held = false }
            }
            return
        }
        for i in voices.indices where voices[i].active && voices[i].note == midi {
            voices[i].held = false
        }
    }

    private func oscillator(phase: Float, saw: Bool, triangle: Bool, pulse: Bool, width: Float, step: Float) -> Float {
        (saw ? evalOsc(phase:phase,waveform:0,pulseWidth:width,step:step) : 0)
        + (triangle ? evalOsc(phase:phase,waveform:1,pulseWidth:width,step:step) : 0)
        + (pulse ? evalOsc(phase:phase,waveform:2,pulseWidth:width,step:step) : 0)
    }

    private func evalOsc(phase: Float, waveform: Int, pulseWidth: Float, step: Float) -> Float {
        switch waveform {
        case 1:
            let n = phase / (2.0 * .pi)
            return n < 0.5 ? ((n * 4.0) - 1.0) : (3.0 - (n * 4.0))
        case 2:
            let pw = min(0.99, max(0.01, pulseWidth))
            let t = phase / (2.0 * .pi)
            let shifted = (t - pw + 1).truncatingRemainder(dividingBy: 1)
            return (t < pw ? 1 : -1) + polyBLEP(t, step) - polyBLEP(shifted, step)
        default:
            return (phase / .pi) - 1.0 - polyBLEP(phase / (2 * .pi), step)
        }
    }

    private func evalLFO(phase: Float, waveform: Int) -> Float {
        switch waveform {
        case 1: return ((phase / (2.0 * .pi)) * 2.0) - 1.0
        case 2: return phase < .pi ? 1.0 : -1.0
        default:
            let n = phase / (2.0 * .pi)
            return n < 0.5 ? ((n * 4.0) - 1.0) : (3.0 - (n * 4.0))
        }
    }

    private func polyBLEP(_ phase: Float, _ step: Float) -> Float {
        guard step > 0 else { return 0 }
        if phase < step {
            let t = phase / step
            return 2 * t - t * t - 1
        }
        if phase > 1 - step {
            let t = (phase - 1) / step
            return t * t + 2 * t + 1
        }
        return 0
    }

    private func filterPole(_ input: Float, state: inout Float, gain: Float) -> Float {
        let delta = (input - state) * gain
        let output = state + delta
        state = output + delta
        return output
    }

    private func randBipolar() -> Float {
        rngState = 1664525 &* rngState &+ 1013904223
        let u = Float(rngState & 0x00FFFFFF) / Float(0x00FFFFFF)
        return (u * 2.0) - 1.0
    }

    private func noteOnUnison(midi: Int, hz: Float, velocity: Float) {
        for i in voices.indices {
            ageCounter &+= 1
            let wasActive = voices[i].active
            voices[i].note = midi
            voices[i].active = true
            voices[i].held = true
            voices[i].filterEnvelope.trigger()
            voices[i].ampEnvelope.trigger()
            voices[i].age = ageCounter
            voices[i].velocity = min(1.0, max(0.0, velocity))
            voices[i].targetHz = hz
            if !wasActive { voices[i].glideHz = voices[i].targetHz }
        }
    }
}
