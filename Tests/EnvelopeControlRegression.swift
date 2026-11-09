// Concatenate after audio sources and Rev3Regression.swift.
extension ProphetLikeAudioUnit {
    fileprivate var probePoly: SIMD2<Float> { smoothedPolyMod }
    fileprivate var probeAttack: Float { voices[0].ampCoefficients.attack }
    fileprivate var probeAttackTarget: Float { voices[0].ampCoefficientTarget.attack }
}
func checkEnvelopeControls() throws {
    setbuf(stdout,nil)
    for sr: Float in [44100,48000,96000,352800,384000] {
        for seconds: Float in [0.001,0.02,1,30] {
            let c=EnvelopeCoefficients(attack:seconds,decay:0.1,sustain:0.4,release:0.2,sr:sr)
            var env=AnalogEnvelope(); env.trigger()
            var frames=0
            while env.stage == .attack && frames<Int(sr*seconds*1.1)+2 { env.advance(gate:true,coefficients:c); frames += 1 }
            if seconds == 30 { print("30s attack at \(Int(sr))Hz: \(Float(frames)/sr)s") }
            precondition(abs(Float(frames)/sr-seconds)<max(2/sr,seconds*0.001),"Attack times must retain their seconds mapping")
            let before=env.level
            env.trigger(); precondition(env.level == before,"Retrigger preserves voltage")
        }
        var env=AnalogEnvelope()
        env.trigger()
        let c=EnvelopeCoefficients(attack:0.001,decay:0.1,sustain:0.7,release:30,sr:sr)
        for _ in 0..<Int(sr*0.1) { env.advance(gate:true,coefficients:c) }
        let start=env.level
        for _ in 0..<Int(sr*30) { env.advance(gate:false,coefficients:c) }
        let ratio=env.level/start
        precondition(abs(ratio-0.0001)<0.0000002,"30s release must retain its -80dB time mapping")
        var decay=AnalogEnvelope(); decay.trigger()
        let dc=EnvelopeCoefficients(attack:0.001,decay:30,sustain:0.4,release:0.1,sr:sr)
        while decay.stage == .attack { decay.advance(gate:true,coefficients:dc) }
        for _ in 0..<Int(sr*30) { decay.advance(gate:true,coefficients:dc) }
        precondition(abs(decay.level-0.406)<0.00001,"30s decay must reach 1% residual above sustain")
    }
    let probe=try AudioProbe(SynthParameters())
    _=probe.samples(1)
    let old=probe.unit.probeAttack
    probe.parameters.set { $0.envBAttack=10; $0.polyModFilterEnv=1; $0.polyModOscB=0.5 }
    _=probe.samples(1)
    let position=1-expf(-256/(48000*0.004))
    precondition(abs(probe.unit.probePoly.x-position)<0.00001)
    precondition(abs(probe.unit.probePoly.y-position*0.5)<0.00001)
    let current=probe.unit.probeAttack,target=probe.unit.probeAttackTarget
    precondition(current>target && current<old,"ADSR edits approach, rather than jump to, their target")
    _=probe.samples(30)
    precondition(abs(probe.unit.probeAttack-target)<0.000001 && abs(probe.unit.probePoly.x-1)<0.0001)
    probe.parameters.set { $0.envBRelease=30; $0.releaseEnabled=false }
    probe.unit.noteOn(60,velocity:1); _=probe.samples(10)
    probe.unit.noteOff(60); _=probe.samples(40)
    precondition(rms(probe.samples(1))<0.00001,"Release off must retain its fast note-off")
    func blockResponse(_ frames: UInt32) throws -> SIMD2<Float> {
        let p=try AudioProbe(SynthParameters())
        func renderBlock() {
            precondition(p.render(&p.flags,&p.time,frames,0,p.buffer.mutableAudioBufferList,nil,nil)==noErr)
            p.time.mSampleTime += Double(frames)
        }
        for _ in 0..<(512/Int(frames)) { renderBlock() }
        p.parameters.set { $0.polyModOscB=1; $0.envBAttack=10 }
        for _ in 0..<(512/Int(frames)) { renderBlock() }
        return SIMD2(p.unit.probePoly.y,p.unit.probeAttack)
    }
    let shortBlocks=try blockResponse(64),longBlocks=try blockResponse(256)
    precondition(shortBlocks == longBlocks,"Smoothing duration must not depend on render block size")
    var initial=SynthParameters(); initial.polyModFilterEnv=1; initial.envBAttack=10
    let startup=try AudioProbe(initial); _=startup.samples(1)
    precondition(startup.unit.probePoly.x == 1 && startup.unit.probeAttack == startup.unit.probeAttackTarget,"Initial programs must not ramp from unrelated defaults")
    // Check that the original knob maps and 46-item program schema are intact.
    for knob in Rev3.knobs where knob.id.hasPrefix("env") || knob.id.hasPrefix("polyMod") {
        for position in [0.0,0.25,0.5,0.75,1.0] {
            var p=SynthParameters(); p[keyPath:knob.key]=knob.value(position)
            precondition(abs(knob.normalized(p)-position)<0.00001)
        }
    }
    precondition(Rev3Program(SynthParameters()).pots.count == 24)
    print("Envelope/Poly-Mod controls: attack mapping, 30s release, retrigger, 4ms edits, fast release and schema passed")
}
try checkEnvelopeControls()
