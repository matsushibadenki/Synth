// Concatenate after Rev3Parameters, EffectsGraph, EffectsDSP and ProphetCore.
// Offline AU tests; no output device. Private state access stays in the same file.
extension ProphetLikeAudioUnit {
    fileprivate func checkVelocityTargets(_ note:Int,_ expected:Float) {
        let active=voices.filter { $0.active && $0.held }
        precondition(!active.isEmpty)
        precondition(active.allSatisfy { $0.note==note && abs($0.velocity-expected)<0.000001 })
    }
    fileprivate func checkVelocityRamp() {
        precondition(voices.filter { $0.active && $0.held }.allSatisfy { $0.velocityGain>$0.velocity },"Reused gain must ramp rather than jump")
    }
}
private final class VelocityProbe {
    let params=SharedSynthParameters(),fx=SharedEffects(),unit:ProphetLikeAudioUnit
    let buffer:AVAudioPCMBuffer,render:AUInternalRenderBlock
    var flags=AudioUnitRenderActionFlags(),time=AudioTimeStamp()
    init(_ rate:Double,_ unison:Bool) throws {
        params.set {
            $0.unisonMode=unison;$0.oscALevel=0.35;$0.oscBLevel=0;$0.noiseLevel=0
            $0.filterEnvAmount=0;$0.cutoffNorm=0.8;$0.resonance=0
            $0.envBAttack=0.001;$0.envBDecay=0.001;$0.envBSustain=1;$0.releaseEnabled=false
            $0.masterVolume=0.5
        }
        ProphetLikeAudioUnit.sharedParameters=params;ProphetLikeAudioUnit.sharedEffects=fx
        unit=try ProphetLikeAudioUnit(componentDescription:AudioComponentDescription(componentType:kAudioUnitType_Generator,
            componentSubType:0x50723535,componentManufacturer:0x53796E74,componentFlags:0,componentFlagsMask:0))
        try unit.outputBusses[0].setFormat(AVAudioFormat(standardFormatWithSampleRate:rate,channels:2)!)
        try unit.allocateRenderResources()
        buffer=AVAudioPCMBuffer(pcmFormat:unit.outputBusses[0].format,frameCapacity:256)!
        render=unit.internalRenderBlock;time.mFlags = .sampleTimeValid
    }
    deinit { unit.deallocateRenderResources() }
    func samples(_ blocks:Int=40,frames:UInt32=256)->[Float] {
        var result=[Float]()
        for _ in 0..<blocks {
            precondition(render(&flags,&time,frames,0,buffer.mutableAudioBufferList,nil,nil)==noErr)
            for i in 0..<Int(frames) {
                let value=buffer.floatChannelData![0][i]
                precondition(value.isFinite && abs(value)<=1)
                result.append(value)
            }
            time.mSampleTime += Double(frames)
        }
        return result
    }
}
func checkVelocity() throws {
    func rms(_ x:[Float])->Double { sqrt(x.reduce(0.0) { $0+Double($1)*Double($1) }/Double(x.count)) }
    for rate in [44100.0,48000.0,96000.0] {
        for unison in [false,true] {
            var levels=[Double]()
            for velocity in [Float(1)/127,Float(32)/127,Float(64)/127,1] {
                let probe=try VelocityProbe(rate,unison)
                probe.unit.noteOn(60,velocity:velocity)
                levels.append(rms(probe.samples()))
                probe.unit.noteOn(60,velocity:0)
                precondition(rms(Array(probe.samples(60).suffix(256)))<0.00001,"Velocity zero must release")
            }
            for i in 0..<3 { precondition(levels[i]>0 && levels[i]<levels[i+1]) }
            precondition(abs(levels[1]/levels[3]-32.0/127)<0.0001)
            precondition(abs(levels[2]/levels[3]-64.0/127)<0.0001)
            print("Velocity \(Int(rate)) Hz / unison \(unison): MIDI 1/32/64/127 monotonic, linear dry gain and zero release passed")
        }
    }
    let probe=try VelocityProbe(48000,true)
    let soft:Float=32.0/127
    probe.unit.noteOn(60,velocity:soft);_=probe.samples(2)
    probe.unit.noteOn(48,velocity:1);_=probe.samples(2);probe.unit.checkVelocityTargets(48,1)
    probe.unit.noteOff(48);_=probe.samples(1,frames:1)
    probe.unit.checkVelocityTargets(60,soft);probe.unit.checkVelocityRamp()
    probe.unit.noteOn(60,velocity:0.5);_=probe.samples(2);probe.unit.checkVelocityTargets(60,0.5)
    probe.params.set { $0.unisonMode=false };_=probe.samples(2)
    probe.unit.checkVelocityTargets(60,0.5)
    probe.params.set { $0.unisonMode=true };_=probe.samples(2)
    probe.unit.checkVelocityTargets(60,0.5)
    probe.unit.noteOn(60,velocity:Float.nan);probe.unit.noteOn(60,velocity:Float.infinity)
    _=probe.samples(2);probe.unit.checkVelocityTargets(60,0.5)
    probe.unit.noteOn(48,velocity:2);_=probe.samples(2);probe.unit.checkVelocityTargets(48,1)
    // Sixth voice steals an active slot and must retain its new velocity.
    let poly=try VelocityProbe(48000,false)
    for note in 60...65 { poly.unit.noteOn(note,velocity:Float(note-59)/6);_=poly.samples(2) }
    for note in 60...65 { poly.unit.noteOff(note) }
    precondition(rms(Array(poly.samples(60).suffix(256)))<0.00001)
    print("Velocity unison priority/fallback/retrigger/mode changes, gain ramp, invalid/clamped input and voice stealing passed")
}
try checkVelocity()
