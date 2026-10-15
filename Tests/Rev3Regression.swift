// Concatenate before AudioRegression.swift, after Rev3Parameters + ProphetCore.
func checkSchema() {
    precondition(Rev3.knobs.filter(\.programmable).count == 24)
    precondition(Rev3.switches.count == 22)
    precondition(Rev3.sections.flatMap(\.knobs).sorted() == Array(0..<26))
    precondition(Rev3.sections.flatMap(\.switches).sorted() == Array(0..<22))
    var state=SynthParameters()
    for item in Rev3.knobs { state[keyPath:item.key]=item.range.upperBound }
    for item in Rev3.switches { state[keyPath:item.key]=true }
    let saved=Rev3Program(state)
    let data=try! JSONEncoder().encode(saved)
    let restored=try! JSONDecoder().decode(Rev3Program.self,from:data)
    var live=SynthParameters()
    live.masterVolume=0.31; live.masterTuneSemitones = -0.2; live.modWheel=0.4; live.pitchWheel = -0.7; live.referenceA440=true
    let result=restored.applying(to:live)!
    precondition(Rev3Program(result) == saved)
    precondition(result.masterVolume == live.masterVolume && result.masterTuneSemitones == live.masterTuneSemitones)
    precondition(result.modWheel == live.modWheel && result.pitchWheel == live.pitchWheel && result.referenceA440)
    var broken=saved; broken.pots["drive"]=1
    precondition(broken.applying(to:live) == nil,"Reject extra voice parameters")
    broken=saved; broken.pots.removeValue(forKey:"glideTime")
    precondition(broken.applying(to:live) == nil,"Reject incomplete programs")
    for item in Rev3.knobs {
        precondition(abs(item.value(0)-item.range.lowerBound)<0.0001)
        precondition(abs(item.value(1)-item.range.upperBound)<0.0001)
    }
    let old=try! JSONSerialization.data(withJSONObject:["cutoff":0.4,"oscAWave":2,"oscBWave":1,"oscBFine":-40,"envAR":40,"drive":0.9])
    let migration=Rev3Program.migratingLegacy(old)!.applying(to:live)!
    precondition(migration.oscAPulse && !migration.oscASaw && migration.oscBTriangle)
    precondition(migration.oscBFineCents == 0 && migration.envARelease == 30)
    precondition(migration.masterVolume == live.masterVolume)
    print("Rev3 schema: exactly 24 pots + 22 switches; recall preserves performance controls")
}

final class AudioProbe {
    let parameters=SharedSynthParameters()
    let unit: ProphetLikeAudioUnit
    let buffer: AVAudioPCMBuffer
    let render: AUInternalRenderBlock
    var flags=AudioUnitRenderActionFlags()
    var time=AudioTimeStamp()
    init(_ p: SynthParameters) throws {
        parameters.set { $0=p }
        ProphetLikeAudioUnit.sharedParameters=parameters
        unit=try ProphetLikeAudioUnit(componentDescription:AudioComponentDescription(componentType:kAudioUnitType_Generator,componentSubType:0x50723535,componentManufacturer:0x53796E74,componentFlags:0,componentFlagsMask:0))
        try unit.allocateRenderResources()
        buffer=AVAudioPCMBuffer(pcmFormat:unit.outputBusses[0].format,frameCapacity:256)!
        render=unit.internalRenderBlock
        time.mFlags = .sampleTimeValid
    }
    deinit { unit.deallocateRenderResources() }
    func samples(_ blocks: Int=40) -> [Float] {
        var result=[Float]()
        for _ in 0..<blocks {
            precondition(render(&flags,&time,256,0,buffer.mutableAudioBufferList,nil,nil)==noErr)
            let left=buffer.floatChannelData![0],right=buffer.floatChannelData![1]
            for index in 0..<256 {
                precondition(left[index].isFinite && abs(left[index])<=1)
                precondition(left[index]==right[index],"Original output must be mono")
                result.append(left[index])
            }
            time.mSampleTime+=256
        }
        return result
    }
}
func rms(_ values: [Float]) -> Float { sqrt(values.reduce(0) { $0+$1*$1 }/Float(values.count)) }
func checkRev3Behavior() throws {
    var p=SynthParameters()
    p.oscBLevel=0; p.filterEnvAmount=0; p.cutoffNorm=0.8; p.resonance=0
    p.envBAttack=0.001; p.envBDecay=0.001; p.envBSustain=1
    let a=try AudioProbe(p), b=try AudioProbe(p)
    a.unit.noteOn(60,velocity:0.1); b.unit.noteOn(60,velocity:1)
    precondition(a.samples()==b.samples(),"Rev3 keyboard is not velocity sensitive")
    p.oscASaw=false
    let silent=try AudioProbe(p); silent.unit.noteOn(60,velocity:1)
    precondition(rms(silent.samples())<0.00001,"No oscillator shapes means silence")
    p.oscAPulse=true
    let pulse=try AudioProbe(p); pulse.unit.noteOn(60,velocity:1)
    let pulseAudio=pulse.samples()
    p.oscASaw=true
    let combined=try AudioProbe(p); combined.unit.noteOn(60,velocity:1)
    precondition(rms(pulseAudio)>0.001 && combined.samples() != pulseAudio,"Shape switches must sum independently")

    p.unisonMode=true; p.oscAPulse=false
    let low=try AudioProbe(p), high=try AudioProbe(p)
    low.unit.noteOn(48,velocity:1); high.unit.noteOn(48,velocity:1)
    precondition(low.samples()==high.samples())
    high.unit.noteOn(72,velocity:1)
    precondition(low.samples()==high.samples(),"Unison must ignore a higher held note")
    high.unit.noteOff(72)
    precondition(low.samples()==high.samples(),"Releasing a higher key must not close the gate")
    low.unit.noteOn(36,velocity:1); high.unit.noteOn(36,velocity:1)
    precondition(low.samples()==high.samples())
    low.unit.noteOff(36); high.unit.noteOff(36)
    precondition(rms(low.samples())>0.001 && rms(high.samples())>0.001,"Lowest-note release must return to held note")

    p.unisonMode=false; p.envBRelease=2; p.releaseEnabled=false
    let short=try AudioProbe(p); short.unit.noteOn(60,velocity:1); _=short.samples()
    short.unit.noteOff(60)
    precondition(rms(Array(short.samples().suffix(256)))<0.00001,"Release off bypasses the release time")
    p.releaseEnabled=true
    let long=try AudioProbe(p); long.unit.noteOn(60,velocity:1); _=long.samples(); long.unit.noteOff(60)
    precondition(rms(Array(long.samples().suffix(256)))>0.001,"Release on uses envelope time")

    p.modWheel=1; p.lfoToOscA=false; p.lfoToPWA=true; p.oscASaw=false; p.oscAPulse=true
    p.wheelSourceMix=1; p.lfoSaw=false; p.lfoTriangle=false; p.lfoSquare=false
    let pink=try AudioProbe(p); pink.unit.noteOn(60,velocity:1)
    let noiseMod=pink.samples()
    p.modWheel=0
    let noMod=try AudioProbe(p); noMod.unit.noteOn(60,velocity:1)
    precondition(noiseMod != noMod.samples(),"Wheel noise must work with all LFO waves off")
    p.polyModFilterEnv=0.8; p.polyModToPWA=true
    let polyPW=try AudioProbe(p); polyPW.unit.noteOn(60,velocity:1)
    p.polyModToPWA=false
    let noPoly=try AudioProbe(p); noPoly.unit.noteOn(60,velocity:1)
    precondition(polyPW.samples() != noPoly.samples(),"Poly-Mod pulse-width destination must work")
    p.referenceA440=true
    let reference=try AudioProbe(p)
    precondition(rms(reference.samples())>0.01,"A-440 must play without held keys")
    reference.parameters.set { $0.masterVolume=0 }
    precondition(rms(reference.samples())==0,"Volume must mute reference tone")
    print("Rev3 behavior: wave sums, velocity independence, low-note priority, release, noise/PWM routes and A-440 passed")
}
