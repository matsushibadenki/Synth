// Concatenate after Rev3Parameters, EffectsGraph, EffectsDSP, ProphetCore and
// Rev3Regression; compile with -O. Offline tests never start an audio device.
func checkAnalogCards() {
    var startup=VoiceCard(index:0)
    precondition(abs(startup.rawPitch)>0.00001)
    startup.tune()
    startup.advance(seconds:0,tuneCoefficient:1)
    precondition(abs(startup.cents)<0.00001,"Tune must work before the first rendered sample")
    var cards = (0..<5).map { VoiceCard(index:$0) }
    var tracks = [[Float]](repeating:[],count:5)
    var largestStep: Float = 0
    for frame in 0..<30000 {
        for i in cards.indices {
            let before = cards[i].cents
            cards[i].advance(seconds:0.001,tuneCoefficient:1-expf(-1/60))
            if frame > 0 { largestStep = max(largestStep,abs(before-cards[i].cents)) }
            precondition(abs(cards[i].cents)<0.68)
            if frame%10 == 0 { tracks[i].append(cards[i].cents) }
        }
    }
    precondition(largestStep<0.015,"Wander must have no discontinuous random steps")
    for i in cards.indices {
        let mean=tracks[i].reduce(0,+)/Float(tracks[i].count)
        let spread=rms(tracks[i].map { $0-mean })
        precondition(spread>0.02 && spread<0.5,"Slow thermal motion should remain subtle but nonzero")
        for j in 0..<i { precondition(tracks[i] != tracks[j],"Cards must not share a trajectory") }
        let original=cards[i].rawPitch
        cards[i].tune()
        for _ in 0..<1000 { cards[i].advance(seconds:0,tuneCoefficient:0.02) }
        precondition(abs(cards[i].cents)<0.00002)
        precondition(cards[i].rawPitch == original,"Tune must not reset temperature or random state")
        for _ in 0..<5000 { cards[i].advance(seconds:0.001,tuneCoefficient:0.02) }
        precondition(abs(cards[i].cents)>0.01,"Wander must continue after tuning")
    }
    var slow=VoiceCard(index:2), fast=VoiceCard(index:2)
    for frame in 0..<15000 {
        slow.advance(seconds:0.001,tuneCoefficient:0)
        for _ in 0..<48 { fast.advance(seconds:1/48000,tuneCoefficient:0) }
        if frame%100 == 0 {
            precondition(abs(slow.rawPitch-fast.rawPitch)<0.00001,"Drift is measured in seconds, not samples")
        }
    }
    print("Analog cards: five independent bounded trajectories, smooth drift, sample-rate invariance and Tune passed")
}

func checkAnalogEnvelopes() {
    var attacks=[Int]()
    for index in 0..<5 {
        let card=VoiceCard(index:index)
        var env=AnalogEnvelope()
        let c=EnvelopeCoefficients(attack:0.05*card.amplifierTimes.x,decay:0.1,sustain:0.5,release:0.2,sr:48000)
        env.trigger()
        var samples=0
        while env.stage == .attack && samples<4800 { env.advance(gate:true,coefficients:c); samples += 1 }
        precondition((2250...2550).contains(samples))
        attacks.append(samples)
        for _ in 0..<10000 { env.advance(gate:true,coefficients:c) }
        let before=env.level
        env.trigger()
        precondition(env.level == before,"Retrigger must preserve capacitor voltage")
        env.advance(gate:true,coefficients:c)
        precondition(env.level>before)
    }
    precondition(Set(attacks).count>3,"Component tolerance must change envelope timing")
    print("Envelope attack samples at 48 kHz: \(attacks); continuous retrigger passed")
}

func checkCurtisResponse() {
    for sr: Float in [176400,192000] {
        func gain(_ frequency: Float) -> Float {
            var filter=CurtisFilter(), energy: Float=0
            for n in 0..<Int(sr*0.15) {
                let sample=0.01*sinf(2 * .pi*frequency*Float(n)/sr)
                let out=filter.process(sample,cutoff:1000,resonance:0,sampleRate:sr)
                if n>=Int(sr*0.05) { energy += out*out }
            }
            return sqrtf(energy/(sr*0.1))
        }
        let slope=20*log10f(gain(4000)/gain(2000))
        precondition(slope < -19 && slope > -26,"Four-pole rolloff must approach 24 dB/octave")
        var filter=CurtisFilter(), energy: Float=0, peak: Float=0
        for n in 0..<Int(sr*2) {
            let out=filter.process(n==0 ? 0.01 : 0,cutoff:1000,resonance:1,sampleRate:sr)
            precondition(out.isFinite)
            peak=max(peak,abs(out))
            if n>=Int(sr) { energy += out*out }
        }
        precondition(peak<2 && sqrtf(energy/sr)>0.01,"Resonance must sustain bounded self oscillation without an oscillator")
        print("Curtis response: \(Int(sr)) Hz internal, slope \(slope) dB/oct; self-oscillation RMS \(sqrtf(energy/sr))")
    }
}

func checkDecimation() {
    for factor in [2,4] {
        func gain(_ hostFrequency: Double) -> Double {
            var filter=VoiceDecimator(factor:factor), energy: Double=0
            for frame in 0..<4096 {
                for sub in 0..<factor {
                    let t=Double(frame*factor+sub)/Double(factor)
                    filter.push(Float(sin(2*Double.pi*hostFrequency*t)))
                }
                let output=Double(filter.output())
                if frame>=512 { energy += output*output }
            }
            return sqrt(energy/3584)*sqrt(2)
        }
        let pass=gain(0.1), stop=gain(0.6)
        precondition(abs(pass-1)<0.002,"Decimation must preserve audible gain")
        precondition(stop<0.001,"Ultrasonic energy must be removed before downsampling")
        var impulse=VoiceDecimator(factor:factor), output=[Float]()
        for n in 0..<80 {
            for sub in 0..<factor { impulse.push(n==0 && sub==0 ? 1 : 0) }
            output.append(impulse.output())
        }
        let peak=output.indices.max { abs(output[$0])<abs(output[$1]) }!
        precondition((31...32).contains(peak),"Report the FIR latency correctly")
        print("\(factor)x FIR: pass \(20*log10(pass)) dB, ultrasonic rejection \(20*log10(stop)) dB")
    }
}

// Only compiled into this test executable. Inspect actual AU state, not a second
// oscillator implementation, to guard the silent-voice/free-running behavior.
extension ProphetLikeAudioUnit {
    fileprivate var probeLFOPhase: Double { lfoPhase }
    fileprivate var probePhases: [Float] { voices.map { Float($0.phaseA) } }
}
func checkFreeRunningAndPerformance() throws {
    var p=SynthParameters()
    p.lfoRateHz=0.04
    p.oscSync=true; p.polyModToFreqA=true; p.polyModToFilter=true; p.polyModOscB=0.8
    p.oscAPulse=true; p.oscBTriangle=true; p.oscBPulse=true; p.resonance=1
    let probe=try AudioProbe(p)
    let first=probe.unit.probePhases
    _=probe.samples(5)
    let second=probe.unit.probePhases
    let expectedLFO=2*Double.pi*Double(p.lfoRateHz)*Double(5*256)/48000
    precondition(abs(probe.unit.probeLFOPhase-expectedLFO)<1e-10,"Slow LFO phase must not accumulate Float rounding error")
    precondition(zip(first,second).allSatisfy { $0 != $1 },"All ten VCOs keep running with closed gates")
    precondition(Set(second).count==5,"Power-on phases must be independent")
    for note in [36,48,60,72,96] { probe.unit.noteOn(note,velocity:1) }
    _=probe.samples(10)
    func cpuTime() -> Double {
        var t=timespec()
        precondition(clock_gettime(CLOCK_THREAD_CPUTIME_ID,&t)==0)
        return Double(t.tv_sec)+Double(t.tv_nsec)/1e9
    }
    let cpuStart=cpuTime()
    let start=Date.timeIntervalSinceReferenceDate
    let result=probe.samples(200)
    let elapsed=Date.timeIntervalSinceReferenceDate-start
    let cpuElapsed=cpuTime()-cpuStart
    let duration=Double(result.count)/48000
    precondition(rms(result)>0.001)
    print("Five-voice sync + Poly-Mod + resonance: \(cpuElapsed/duration*100)% render-thread CPU, \(elapsed/duration*100)% wall-time budget (offline, optimized, current Mac)")
}

func checkPitchGlide() {
    for sr in [48000.0,192000.0] {
        var glide=PitchGlide()
        glide.reset(880)
        var hz: Float=880
        let coefficient = -expm1(-1/(sr*0.3))
        for _ in 0..<Int(sr*3) { hz=glide.advance(target:3520,coefficient:coefficient,enabled:true) }
        precondition(abs(1200*log2f(hz/3520))<0.2,"Slow CV glide must converge at oversampled rates")
    }
    print("Log-pitch glide converges within 0.2 cent at 48/192 kHz")
}

// Measure both rapid changes and slow level drift, not just adjacent windows.
func checkSustainBeating() throws {
    func measure(_ p: SynthParameters, note: Int) throws -> (spread: Float, step: Float) {
        let probe=try AudioProbe(p)
        probe.unit.noteOn(note,velocity:1)
        _=probe.samples(200)
        var levels=[Float]()
        for _ in 0..<100 { levels.append(20*log10f(max(0.0000001,rms(probe.samples(15))))) }
        let sorted=levels.sorted()
        let step=zip(levels,levels.dropFirst()).map { abs($0-$1) }.max()!
        return (sorted[95]-sorted[5],step)
    }
    var p=SynthParameters()
    precondition(p.oscBFineCents == 0)
    for note in [48,72,84] {
        let result=try measure(p,note:note)
        precondition(result.spread<0.25,"Neutral Fine must also avoid slow amplitude swells")
        precondition(result.step<0.35,"Neutral Fine must avoid rapid amplitude pumping")
        print("Dry sustain MIDI \(note): 5–95% RMS span \(result.spread) dB, max 80 ms change \(result.step) dB")
    }
    p.oscBLevel=0
    let single=try measure(p,note:72)
    precondition(single.spread<0.1,"An isolated oscillator must not acquire unintended tremolo")
    p.oscBLevel=0.7; p.oscBFineCents=5
    let data=try JSONEncoder().encode(Rev3Program(p))
    let recalled=try JSONDecoder().decode(Rev3Program.self,from:data).applying(to:SynthParameters())!
    precondition(recalled.oscBFineCents == 5,"Saved intentional detune must survive the default change")
    let detuned=try measure(recalled,note:72)
    precondition(detuned.spread>3 && detuned.step>0.3,"Fine must still create natural beating; do not flatten with AGC or phase locking")
    print("Dry sustain: single VCO span \(single.spread) dB; saved Fine=5 span \(detuned.spread) dB")
}

extension ProphetLikeAudioUnit {
    // Test-only selection exercises every production card/phase identity through
    // the actual render path without sustaining other notes in the mix.
    fileprivate func selectSustainCard(_ index: Int) { voices[0] = VoiceState(index:index) }
    fileprivate var sustainPhaseDifference: Double { voices[0].phaseA-voices[0].phaseB }
}

func checkLongSustain() throws {
    for (card,note) in [(0,48),(0,72),(0,84),(1,72),(2,72),(3,72),(4,72)] {
        let probe=try AudioProbe(SynthParameters())
        probe.unit.selectSustainCard(card)
        // Idle time must not accumulate a hidden A/B detune before playing.
        _=probe.samples(200)
        probe.unit.noteOn(note,velocity:1)
        _=probe.samples(375)
        let phase=probe.unit.sustainPhaseDifference
        var levels=[Float]()
        for window in 0..<375 {
            if window == 187 { probe.parameters.set { $0.autoTuneTrigger &+= 1 } }
            levels.append(20*log10f(max(1e-8,rms(probe.samples(15)))))
        }
        let sorted=levels.sorted()
        let span=sorted[356]-sorted[18], fullSpan=sorted.last!-sorted.first!
        precondition(span<0.25 && fullSpan<0.4,"Fine=0 must stay stable over 30 seconds, including Tune")
        let phaseChange=probe.unit.sustainPhaseDifference-phase
        precondition(abs(sin(phaseChange))<1e-7 && cos(phaseChange)>0.999999,
                     "Incidental drift/Tune must not change relative phase for equal-frequency VCOs")
        print("30 s sustain card \(card+1), MIDI \(note): P5–95 \(span) dB, full span \(fullSpan) dB")
    }
}

checkPitchGlide()
checkAnalogCards()
checkAnalogEnvelopes()
checkCurtisResponse()
checkDecimation()
try checkFreeRunningAndPerformance()
try checkSustainBeating()
try checkLongSustain()
print("Analog regression checks passed")
