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

    func trySnapshot() -> SynthParameters? {
        guard lock.try() else { return nil }
        defer { lock.unlock() }
        return raw
    }
}

private struct HeldMIDIKeys {
    private var lower: UInt64 = 0
    private var upper: UInt64 = 0
    func contains(_ note: Int) -> Bool {
        let bit = UInt64(1) << (note & 63)
        return (note < 64 ? lower : upper) & bit != 0
    }
    mutating func insert(_ note: Int) {
        if note < 64 { lower |= UInt64(1) << note }
        else { upper |= UInt64(1) << (note-64) }
    }
    mutating func remove(_ note: Int) {
        if note < 64 { lower &= ~(UInt64(1) << note) }
        else { upper &= ~(UInt64(1) << (note-64)) }
    }
    mutating func removeAll() { lower = 0; upper = 0 }
    func min() -> Int? {
        if lower != 0 { return lower.trailingZeroBitCount }
        if upper != 0 { return upper.trailingZeroBitCount+64 }
        return nil
    }
}

private struct PendingNoteEvent {
    var note = 0
    var on = false
}

// Component values below are restrained behavioral approximations, not measured
// tolerances of a particular instrument. No additional patch controls are introduced.
private struct AnalogWander {
    private var random: UInt32
    private var start: Float = 0
    private var end: Float = 0
    private var position: Double = 0
    private var duration: Double = 1
    let minimumDuration: Double
    let durationRange: Double
    private(set) var value: Float = 0

    init(seed: UInt32, minimum: Double, range: Double) {
        random = seed; minimumDuration = minimum; durationRange = range
        start = next(); end = next()
        duration = minimum + Double((next()+1)*0.5)*range
        value = start
    }
    private mutating func next() -> Float {
        random = 1664525 &* random &+ 1013904223
        return Float(random >> 8) / 8388607.5 - 1
    }
    mutating func advance(seconds: Double) -> Float {
        position += seconds
        while position >= duration {
            position -= duration; start = end; end = next()
            duration = minimumDuration + Double((next()+1)*0.5)*durationRange
        }
        let t = Float(position/duration)
        // Quintic interpolation has zero slope and curvature at segment boundaries.
        let blend = t*t*t*(t*(t*6-15)+10)
        value = start + (end-start)*blend
        return value
    }
}

private struct VoiceCard {
    let pitchA: Float, pitchB: Float, scaleA: Float, scaleB: Float
    let filterOctaves: Float, resonanceGain: Float, amplifierGain: Float
    let pulseA: Float, pulseB: Float
    let filterTimes: SIMD3<Float>, amplifierTimes: SIMD3<Float>
    let filterSustain: Float, amplifierSustain: Float
    var fastA: AnalogWander, slowA: AnalogWander
    var fastB: AnalogWander, slowB: AnalogWander
    var thermal: AnalogWander
    private(set) var rawA: Float = 0, rawB: Float = 0
    private(set) var centsA: Float = 0, centsB: Float = 0
    private(set) var filterDrift: Float = 0
    private var tuneA: Float = 0, tuneB: Float = 0
    private var targetTuneA: Float = 0, targetTuneB: Float = 0

    init(index: Int) {
        var seed = UInt32(index+1) &* 0x9E3779B9
        func next() -> Float {
            seed = 1664525 &* seed &+ 1013904223
            return Float(seed >> 8) / 8388607.5 - 1
        }
        pitchA = next()*0.10; pitchB = next()*0.10
        scaleA = next()*0.025; scaleB = next()*0.025
        filterOctaves = next()*0.035; resonanceGain = 1+next()*0.012
        amplifierGain = 1+next()*0.014
        pulseA = next()*0.0018; pulseB = next()*0.0018
        filterTimes = SIMD3(1+next()*0.045,1+next()*0.045,1+next()*0.045)
        amplifierTimes = SIMD3(1+next()*0.045,1+next()*0.045,1+next()*0.045)
        filterSustain = next()*0.008; amplifierSustain = next()*0.008
        fastA = AnalogWander(seed:seed &+ 11,minimum:3,range:4)
        slowA = AnalogWander(seed:seed &+ 29,minimum:7,range:12)
        fastB = AnalogWander(seed:seed &+ 67,minimum:3.5,range:4)
        slowB = AnalogWander(seed:seed &+ 101,minimum:8,range:13)
        thermal = AnalogWander(seed:seed &+ 151,minimum:11,range:19)
        advance(seconds:0,tuneCoefficient:0)
    }
    mutating func advance(seconds: Double, tuneCoefficient: Float) {
        let heat = thermal.advance(seconds:seconds)
        // Keep independent VCO motion subtle: relative pitch wander produces
        // audible amplitude beating when equal-level waves are mixed. Most
        // temperature motion is shared within a card, without locking phases.
        rawA = pitchA + 0.04*fastA.advance(seconds:seconds) + 0.08*slowA.advance(seconds:seconds) + heat*0.45
        rawB = pitchB + 0.04*fastB.advance(seconds:seconds) + 0.08*slowB.advance(seconds:seconds) + heat*0.45
        tuneA += (targetTuneA-tuneA)*tuneCoefficient
        tuneB += (targetTuneB-tuneB)*tuneCoefficient
        centsA = rawA-tuneA; centsB = rawB-tuneB
        filterDrift = heat*0.006
    }
    mutating func tune() {
        // Capture current temperature bias; do not restart the random trajectories
        // or oscillator phases. Slewing the correction avoids an instantaneous jump.
        targetTuneA = rawA; targetTuneB = rawB
    }
}

private struct EnvelopeCoefficients {
    var attack: Float, decay: Float, release: Float, sustain: Float, sustainSlew: Float
    init(attack: Float, decay: Float, sustain: Float, release: Float, sr: Float) {
        self.attack = -expm1f(-1.466337 / max(1,attack*sr))
        self.decay = -expm1f(-4.60517 / max(1,decay*sr))
        self.release = -expm1f(-9.21034 / max(1,release*sr))
        self.sustain = min(1,max(0,sustain))
        sustainSlew = -expm1f(-1/(0.005*sr))
    }
}

private struct AnalogEnvelope {
    enum Stage { case attack, decay, sustain, release }
    var stage: Stage = .release
    var level: Float = 0
    mutating func trigger() { stage = .attack } // Charge from the current capacitor level.
    mutating func advance(gate: Bool, attack: Float, decay: Float, sustain: Float, release: Float, sr: Float) {
        advance(gate:gate,coefficients:EnvelopeCoefficients(attack:attack,decay:decay,sustain:sustain,release:release,sr:sr))
    }
    mutating func advance(gate: Bool, coefficients c: EnvelopeCoefficients) {
        if !gate { stage = .release }
        switch stage {
        case .attack:
            level += (1.3-level)*c.attack
            if level >= 1 { level = 1; stage = .decay }
        case .decay:
            level += (c.sustain-level)*c.decay
            if abs(level-c.sustain) < 0.0001 { level = c.sustain; stage = .sustain }
        case .sustain: level += (c.sustain-level)*c.sustainSlew
        case .release:
            level -= level*c.release
            if level < 0.00001 { level = 0 }
        }
    }
}

private struct CurtisFilter {
    private var state = SIMD4<Float>.zero
    mutating func process(_ input: Float, cutoff: Float, resonance: Float, sampleRate: Float) -> Float {
        let g = tanf(.pi*min(sampleRate*0.4,max(5,cutoff))/sampleRate)
        let G = g/(1+g), G2 = G*G
        let G3 = G2*G, G4 = G2*G2
        let feedback = (G3*state.x+G2*state.y+G*state.z+state.w)/(1+g)
        let k = min(4.5,max(0,resonance)*4.4)
        let drive = tanhf(input*0.6)/0.6*0.65
        let color: Float = 0.9
        var u = (drive-k*feedback)/(1+k*G4)
        // Solve the saturating feedback equation, rather than saturating the
        // result of a linear solve (which changes resonance with sample rate).
        for _ in 0..<3 {
            let t = tanhf(color*(drive-k*(G4*u+feedback)))
            u -= (u-t/color)/(1+k*G4*(1-t*t))
        }
        for i in 0..<4 {
            let delta = (u-state[i])*G
            u = state[i]+delta
            state[i] = u+delta
        }
        return u
    }
}

// Entire oscillator/modulation/filter/VCA path runs oversampled. A windowed-sinc
// FIR removes ultrasonic energy BEFORE returning to the host's sample rate.
private struct VoiceDecimator {
    let factor: Int
    private let coefficients: [Float]
    private var history: [Float]
    private var cursor = 0
    init(factor: Int) {
        self.factor = factor
        let count = factor == 1 ? 1 : factor*64+1
        let center = (count-1)/2
        let cutoff = 0.45/Double(factor)
        var taps = [Float](repeating:0,count:count)
        for i in 0..<count {
            let x = Double(i-center)
            let sinc = x == 0 ? 2*cutoff : sin(2*Double.pi*cutoff*x)/(Double.pi*x)
            let angle = 2*Double.pi*Double(i)/Double(max(1,count-1))
            let window = 0.42-0.5*cos(angle)+0.08*cos(2*angle)
            taps[i] = Float(sinc*window)
        }
        if factor == 1 { taps[0] = 1 }
        let sum = taps.reduce(0,+)
        coefficients = taps.map { $0/sum }
        history = [Float](repeating:0,count:count*2)
    }
    mutating func push(_ input: Float) {
        history[cursor] = input; history[cursor+coefficients.count] = input
        cursor += 1
        if cursor == coefficients.count { cursor = 0 }
    }
    func output() -> Float {
        let count = coefficients.count, half = count/2
        var result = coefficients[half]*history[cursor+half]
        for i in 0..<half {
            result += coefficients[i]*(history[cursor+i]+history[cursor+count-1-i])
        }
        return result
    }
}

private struct PitchGlide {
    // A Double capacitor voltage prevents slow glides from stalling at Float
    // precision when evaluated at 192 kHz (especially in the upper octaves).
    private var voltage: Double = log2(261.63)
    private var lastTarget: Float = 0
    private var destination: Double = 0
    mutating func reset(_ hz: Float) { voltage = log2(Double(hz)) }
    mutating func advance(target: Float, coefficient: Double, enabled: Bool) -> Float {
        if target != lastTarget { lastTarget = target; destination = log2(Double(target)) }
        guard enabled else { voltage = destination; return target }
        voltage += (destination-voltage)*coefficient
        return Float(exp2(voltage))
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
    var glide = PitchGlide()
    var phaseA: Double
    var phaseB: Double
    var card: VoiceCard
    var filterEnvelope = AnalogEnvelope()
    var ampEnvelope = AnalogEnvelope()
    var filterCoefficients = EnvelopeCoefficients(attack:0.01,decay:0.1,sustain:0.8,release:0.1,sr:192000)
    var ampCoefficients = EnvelopeCoefficients(attack:0.01,decay:0.1,sustain:0.8,release:0.1,sr:192000)
    var filter = CurtisFilter()
    var dcInput: Float = 0, dcOutput: Float = 0
    init(index: Int) {
        card = VoiceCard(index:index)
        // Independent power-on phases; note gates never reset them.
        phaseA = Double(index+1)*0.75487766*2 * .pi
        phaseA.formTruncatingRemainder(dividingBy:2 * .pi)
        phaseB = Double(index+1)*0.56984029*2 * .pi
        phaseB.formTruncatingRemainder(dividingBy:2 * .pi)
    }
}

final class ProphetLikeAudioUnit: AUAudioUnit {
    static var sharedParameters = SharedSynthParameters()
    static var sharedEffects = SharedEffects()
    private let effects: SharedEffects
    private var effectsDSP = EffectsRackDSP(sampleRate:48_000)

    private let outputBus: AUAudioUnitBus
    private var outputBusArray: AUAudioUnitBusArray!
    private var inputBusArray: AUAudioUnitBusArray!
    private let params: SharedSynthParameters
    private var renderParameters = SynthParameters()

    private var sampleRateF: Float = 48_000
    private var voices = (0..<5).map { VoiceState(index:$0) }
    private var oversampling = 4
    private var decimator = VoiceDecimator(factor:4)
    private var smoothedControls = SIMD8<Float>.zero
    private var controlsInitialized = false
    private var ageCounter: UInt64 = 0
    private var rrCursor: Int = 0

    private var lastAutoTuneTrigger: UInt32 = 0
    private var lfoPhase: Double = 0
    private var pink = SIMD3<Float>(repeating: 0)
    private var referencePhase: Float = 0
    private var heldKeys = HeldMIDIKeys()
    private var lastUnison = false
    private let eventLock = NSLock()
    // UI writes under the mutex. Audio only attempts the lock and otherwise
    // continues with the previous state; event storage never grows in render.
    private var pendingEvents = [PendingNoteEvent](repeating:PendingNoteEvent(),count:256)
    private var renderEvents = [PendingNoteEvent](repeating:PendingNoteEvent(),count:256)
    private var pendingEventCount = 0
    private var pendingEventOverflow = false
    private var rngState: UInt32 = 0x1234ABCD

    override init(componentDescription: AudioComponentDescription, options: AudioComponentInstantiationOptions = []) throws {
        self.params = Self.sharedParameters
        self.effects = Self.sharedEffects
        outputBus = try AUAudioUnitBus(format: AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!)
        try super.init(componentDescription: componentDescription, options: options)
        outputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
        inputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [])
    }

    override var outputBusses: AUAudioUnitBusArray { outputBusArray }
    override var inputBusses: AUAudioUnitBusArray { inputBusArray }
    override var latency: TimeInterval { oversampling > 1 ? 32/Double(sampleRateF) : 0 }

    override func allocateRenderResources() throws {
        try super.allocateRenderResources()
        sampleRateF = Float(outputBus.format.sampleRate)
        renderParameters = params.snapshot()
        effectsDSP = EffectsRackDSP(sampleRate:sampleRateF)
        oversampling = sampleRateF <= 48000 ? 4 : (sampleRateF <= 96000 ? 2 : 1)
        decimator = VoiceDecimator(factor:oversampling)
        controlsInitialized = false
    }

    override var internalRenderBlock: AUInternalRenderBlock {
        return { [weak self] _, _, frameCount, _, outputData, _, _ in
            guard let self else { return noErr }
            if let latest = self.params.trySnapshot() { self.renderParameters = latest }
            let p = self.renderParameters
            if let configuration=self.effects.trySnapshot() { self.effectsDSP.prepare(configuration) }
            var eventCount = 0
            var eventOverflow = false
            if self.eventLock.try() {
                eventOverflow = self.pendingEventOverflow
                if !eventOverflow {
                    eventCount = self.pendingEventCount
                    for index in 0..<eventCount { self.renderEvents[index] = self.pendingEvents[index] }
                }
                self.pendingEventCount = 0
                self.pendingEventOverflow = false
                self.eventLock.unlock()
            }
            if eventOverflow {
                // Never strand a held note if a producer floods the bounded queue.
                self.heldKeys.removeAll()
                for index in self.voices.indices { self.voices[index].held = false }
            }
            if p.unisonMode != self.lastUnison {
                self.lastUnison = p.unisonMode
                for i in self.voices.indices { self.voices[i].held = false }
                let notes = self.heldKeys
                self.heldKeys.removeAll()
                for note in 0..<128 where notes.contains(note) { self.handleNoteOn(note, velocity: 1, parameters:p) }
            }
            for index in 0..<eventCount {
                let event = self.renderEvents[index]
                if event.on { self.handleNoteOn(event.note, velocity: 1, parameters:p) }
                else { self.handleNoteOff(event.note, parameters:p) }
            }

            if p.autoTuneTrigger != self.lastAutoTuneTrigger {
                self.lastAutoTuneTrigger = p.autoTuneTrigger
                for i in self.voices.indices {
                    self.voices[i].card.tune()
                }
            }

            let hostRate = self.sampleRateF
            let sr = hostRate*Float(self.oversampling)
            let controlTarget = SIMD8(p.cutoffNorm,p.resonance,p.oscALevel,p.oscBLevel,p.noiseLevel,p.oscAPulseWidth,p.oscBPulseWidth,p.filterEnvAmount)
            if !self.controlsInitialized { self.smoothedControls = controlTarget; self.controlsInitialized = true }
            let controlSlew = -expm1f(-1/(hostRate*0.004))
            let tuneSlew = -expm1f(-1/(hostRate*0.06))
            let dcPole = expf(-2 * .pi*5/sr)
            let noiseGain = sqrtf(sr/48000)
            let pinkPoles = SIMD3(powf(0.99765,48000/sr),powf(0.963,48000/sr),powf(0.57,48000/sr))
            let pinkGains = SIMD3<Float>(0.099046,0.2965164,1.0526913)*(1-pinkPoles)/(1-SIMD3<Float>(0.99765,0.963,0.57))
            let ratioA = powf(2,(p.oscAFrequency.rounded()-24)/12)
            let ratioB = powf(2,(p.oscBFrequency.rounded()-24)/12)
            let globalTune = p.masterTuneSemitones+p.pitchWheel*7
            let tuningRatio = powf(2,globalTune/12)
            let glideCoefficient = -expm1(-1/(Double(sr)*Double(max(0.001,p.glideTime))))
            for vi in self.voices.indices {
                let card = self.voices[vi].card
                self.voices[vi].filterCoefficients = EnvelopeCoefficients(
                    attack:p.envAAttack*card.filterTimes.x,decay:p.envADecay*card.filterTimes.y,
                    sustain:p.envASustain+card.filterSustain*p.envASustain*(1-p.envASustain),
                    release:p.releaseEnabled ? p.envARelease*card.filterTimes.z : 0.005,sr:sr)
                self.voices[vi].ampCoefficients = EnvelopeCoefficients(
                    attack:p.envBAttack*card.amplifierTimes.x,decay:p.envBDecay*card.amplifierTimes.y,
                    sustain:p.envBSustain+card.amplifierSustain*p.envBSustain*(1-p.envBSustain),
                    release:p.releaseEnabled ? p.envBRelease*card.amplifierTimes.z : 0.005,sr:sr)
            }
            let lfoStep = (2.0 * Double.pi * Double(max(0.04, min(20, p.lfoRateHz)))) / Double(sr)

            let buffers = UnsafeMutableAudioBufferListPointer(outputData)
            guard buffers.count >= 2 else { return noErr }
            guard let left = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            guard let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }

            self.voices.withUnsafeMutableBufferPointer { voiceBuffer in
                for i in 0..<Int(frameCount) {
                    self.smoothedControls += (controlTarget-self.smoothedControls)*controlSlew
                    let controls = self.smoothedControls
                    for vi in voiceBuffer.indices {
                        voiceBuffer[vi].card.advance(seconds:1/Double(hostRate),tuneCoefficient:tuneSlew)
                    }
                    for _ in 0..<self.oversampling {
                        self.lfoPhase += lfoStep
                        if self.lfoPhase > 2.0 * .pi {
                            self.lfoPhase -= 2.0 * .pi
                        }
                        let lfo = (p.lfoSaw ? self.evalLFO(phase: Float(self.lfoPhase), waveform: 1) : 0)
                            + (p.lfoTriangle ? self.evalLFO(phase: Float(self.lfoPhase), waveform: 0) : 0)
                            + (p.lfoSquare ? self.evalLFO(phase: Float(self.lfoPhase), waveform: 2) : 0)
                        let white = self.randBipolar()*noiseGain
                        // Three-pole pinking filter. The mixer retains the white source.
                        self.pink = self.pink*pinkPoles + SIMD3(repeating:white)*pinkGains
                        let pinkNoise = (self.pink.x + self.pink.y + self.pink.z + white * 0.1848) * 0.2
                        let wheel = (lfo * (1-p.wheelSourceMix) + pinkNoise * p.wheelSourceMix) * p.modWheel

                        var outL: Float = 0

                        for vi in voiceBuffer.indices {
                            voiceBuffer[vi].filterEnvelope.advance(gate:voiceBuffer[vi].held,coefficients:voiceBuffer[vi].filterCoefficients)
                            voiceBuffer[vi].ampEnvelope.advance(gate:voiceBuffer[vi].held,coefficients:voiceBuffer[vi].ampCoefficients)
                            if !voiceBuffer[vi].held && voiceBuffer[vi].ampEnvelope.level == 0 { voiceBuffer[vi].active = false }
                            let glideTarget = voiceBuffer[vi].targetHz*tuningRatio
                            voiceBuffer[vi].glideHz = voiceBuffer[vi].glide.advance(target:glideTarget,coefficient:glideCoefficient,
                                enabled:p.unisonMode && p.glideTime > 0)
                            let card = voiceBuffer[vi].card
                            let pitchOctaves = log2f(voiceBuffer[vi].glideHz/261.6256)
                            let trackB = p.oscBKeyboardTrack ? voiceBuffer[vi].glideHz : 261.6256*tuningRatio
                            let baseB = p.oscBLowFreqMode ? 0.4 * powf(75, p.oscBFrequency/48) * (trackB/261.6256) : trackB * ratioB
                            var hzB = baseB * powf(2, (p.oscBFineCents+card.centsB+card.scaleB*log2f(max(0.01,baseB)/261.6256))/1200)
                            if p.lfoToOscB { hzB *= powf(2, wheel*2) }
                            let pwB = controls[6]+card.pulseB + (p.lfoToPWB ? wheel*0.49 : 0)
                            let sourceB = self.oscillator(phase:voiceBuffer[vi].phaseB, saw:p.oscBSaw, triangle:p.oscBTriangle, pulse:p.oscBPulse, width:pwB, step:min(0.45,hzB/sr))
                            let poly = p.polyModFilterEnv*voiceBuffer[vi].filterEnvelope.level + p.polyModOscB*sourceB
                            var hzA = voiceBuffer[vi].glideHz * ratioA * powf(2,(card.centsA+card.scaleA*(pitchOctaves+(p.oscAFrequency-24)/12))/1200)
                            if p.polyModToFreqA { hzA *= powf(2,poly*4) }
                            if p.lfoToOscA { hzA *= powf(2,wheel*2) }

                            hzA = min(sr * 0.45, max(0.01, hzA))
                            hzB = min(sr * 0.45, max(0.01, hzB))
                            voiceBuffer[vi].phaseA += (2.0 * .pi * Double(hzA)) / Double(sr)
                            voiceBuffer[vi].phaseB += (2.0 * .pi * Double(hzB)) / Double(sr)
                            // B is the master; preserve the fractional time since its wrap.
                            if p.oscSync && voiceBuffer[vi].phaseB >= 2.0 * .pi {
                                let fraction = (voiceBuffer[vi].phaseB - 2.0 * .pi) / (2.0 * .pi * Double(hzB) / Double(sr))
                                voiceBuffer[vi].phaseA = fraction * (2.0 * .pi * Double(hzA) / Double(sr))
                            }
                            voiceBuffer[vi].phaseA.formTruncatingRemainder(dividingBy: 2.0 * .pi)
                            voiceBuffer[vi].phaseB.formTruncatingRemainder(dividingBy: 2.0 * .pi)

                            let pwA = controls[5]+card.pulseA + (p.lfoToPWA ? wheel*0.49 : 0) + (p.polyModToPWA ? poly*0.49 : 0)
                            let oscA = self.oscillator(phase:voiceBuffer[vi].phaseA, saw:p.oscASaw, triangle:false, pulse:p.oscAPulse, width:pwA, step:hzA/sr)
                            let oscB = self.oscillator(phase:voiceBuffer[vi].phaseB, saw:p.oscBSaw, triangle:p.oscBTriangle, pulse:p.oscBPulse, width:pwB, step:hzB/sr)
                            let mix = oscA*controls[2] + oscB*controls[3] + white*controls[4]
                            let kbTrack = p.filterKeyboardTrack ? log2f(max(0.001,voiceBuffer[vi].glideHz/261.6256))/log2f(1000) : 0
                            let wheelFilter = p.lfoToFilter ? wheel*0.5 : 0
                            let envFilter = controls[7]*voiceBuffer[vi].filterEnvelope.level + (p.polyModToFilter ? poly*0.5 : 0)
                            var cutoffNorm = controls[0] + kbTrack + wheelFilter + envFilter + (card.filterOctaves+card.filterDrift)/log2f(1000)
                            cutoffNorm = min(0.99, max(0.001, cutoffNorm))
                            let cutoffHz = 20.0 * powf(1000.0, cutoffNorm)
                            let filtered = voiceBuffer[vi].filter.process(mix+white*0.0000001,cutoff:cutoffHz,
                                resonance:controls[1]*card.resonanceGain,sampleRate:sr)
                            // AC coupling removes pulse-width DC before the final VCA.
                            let coupled = filtered-voiceBuffer[vi].dcInput+dcPole*voiceBuffer[vi].dcOutput
                            voiceBuffer[vi].dcInput = filtered; voiceBuffer[vi].dcOutput = coupled
                            let voiceOut = tanhf(coupled*0.35)/0.35*voiceBuffer[vi].ampEnvelope.level*card.amplifierGain
                            outL += voiceOut
                        }
                        self.decimator.push(outL*0.18)
                    }
                    var mono = self.decimator.output()
                    self.referencePhase += 2 * .pi * 440 / hostRate
                    self.referencePhase.formTruncatingRemainder(dividingBy: 2 * .pi)
                    if p.referenceA440 {
                        let reference = sinf(self.referencePhase)*0.35
                        mono += reference*0.18
                    }

                    let processed=self.effectsDSP.process(SIMD2(repeating:mono))
                    let volume=min(1,max(0,p.masterVolume))
                    left[i]=processed.x*volume
                    right[i]=processed.y*volume
                }
            }
            self.effects.reportLoop(state:self.effectsDSP.loopState,seconds:self.effectsDSP.loopSeconds)
            return noErr
        }
    }

    // UI events are consumed on the render thread; the UI never mutates voices.
    func noteOn(_ midi: Int, velocity: Float) { enqueue(midi, on: true) }
    func noteOff(_ midi: Int) { enqueue(midi, on: false) }
    private func enqueue(_ midi: Int, on: Bool) {
        guard (0...127).contains(midi) else { return }
        eventLock.lock()
        if pendingEventCount < pendingEvents.count && !pendingEventOverflow {
            pendingEvents[pendingEventCount] = PendingNoteEvent(note:midi,on:on)
            pendingEventCount += 1
        } else { pendingEventOverflow = true }
        eventLock.unlock()
    }

    private func handleNoteOn(_ midi: Int, velocity: Float, parameters p: SynthParameters) {
        let previousLowest = heldKeys.min()
        heldKeys.insert(midi)
        let hz = 440.0 * powf(2.0, Float(midi - 69) / 12.0)
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
        if !wasActive { voices[idx].glideHz = hz; voices[idx].glide.reset(hz) }
    }

    private func handleNoteOff(_ midi: Int, parameters p: SynthParameters) {
        let previousLowest = heldKeys.min()
        heldKeys.remove(midi)
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

    private func oscillator(phase: Double, saw: Bool, triangle: Bool, pulse: Bool, width: Float, step: Float) -> Float {
        let phase = Float(phase)
        return (saw ? evalOsc(phase:phase,waveform:0,pulseWidth:width,step:step) : 0)
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
            if !wasActive { voices[i].glideHz = voices[i].targetHz; voices[i].glide.reset(hz) }
        }
    }
}
