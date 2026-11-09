// Opt-in hardware diagnostic. The synth master is zero; no test sound is emitted.
// Concatenate after the production audio sources, then pass --run-muted-output.
import Dispatch
import Darwin

private final class DeviceTiming {
    let done=DispatchSemaphore(value:0)
    var iteration=0, frozen=false, error: OSStatus=0
    var wall=[Double](repeating:0,count:256), cpu=[Double](repeating:0,count:256)
    var budget=[Double](repeating:0,count:256)
    var qos: UInt32=0
}
private func probeSeconds(_ clock: clockid_t) -> Double {
    var time=timespec(); clock_gettime(clock,&time)
    return Double(time.tv_sec)+Double(time.tv_nsec)*1e-9
}
func runMutedDeviceProbe() throws {
    let engine=AVAudioEngine()
    let rate=engine.outputNode.inputFormat(forBus:0).sampleRate
    guard rate>0 else { throw NSError(domain:"DeviceProbe",code:1,userInfo:[NSLocalizedDescriptionKey:"No audio output sample rate"]) }
    let format=AVAudioFormat(standardFormatWithSampleRate:rate,channels:2)!
    let parameters=SharedSynthParameters(),effects=SharedEffects()
    parameters.set {
        $0.masterVolume=0; $0.unisonMode=true; $0.oscSync=true; $0.resonance=1
        $0.oscAPulse=true; $0.oscBPulse=true; $0.oscBTriangle=true
        $0.polyModOscB=0.7; $0.polyModToFreqA=true; $0.polyModToFilter=true; $0.polyModToPWA=true
        $0.lfoToPWB=true; $0.modWheel=1; $0.wheelSourceMix=1
    }
    var document=FXDocument.initial
    for i in 1...6 { document.nodes[i].settings.enabled=true }
    document.nodes[EffectKind.studio.rawValue].settings.mode=2
    effects.set(try document.configuration())
    ProphetLikeAudioUnit.sharedParameters=parameters; ProphetLikeAudioUnit.sharedEffects=effects
    let unit=try ProphetLikeAudioUnit(componentDescription:AudioComponentDescription(componentType:kAudioUnitType_Generator,
        componentSubType:0x50723535,componentManufacturer:0x53796E74,componentFlags:0,componentFlagsMask:0))
    try unit.outputBusses[0].setFormat(format)
    try unit.allocateRenderResources()
    defer { unit.deallocateRenderResources() }
    unit.noteOn(60,velocity:1)
    let render=unit.internalRenderBlock,timing=DeviceTiming()
    let source=AVAudioSourceNode(format:format) { silent,timestamp,frames,buffers in
        var flags=AudioUnitRenderActionFlags(),time=timestamp.pointee
        let start=probeSeconds(CLOCK_UPTIME_RAW),cpuStart=probeSeconds(CLOCK_THREAD_CPUTIME_ID)
        let status=render(&flags,&time,frames,0,buffers,nil,nil)
        let spent=probeSeconds(CLOCK_THREAD_CPUTIME_ID)-cpuStart,elapsed=probeSeconds(CLOCK_UPTIME_RAW)-start
        silent.pointee=false
        if !timing.frozen {
            if status != noErr { timing.error=status }
            if timing.iteration>=20 {
                let index=timing.iteration-20
                timing.wall[index]=elapsed; timing.cpu[index]=spent
                timing.budget[index]=Double(frames)/rate
                timing.qos=qos_class_self().rawValue
            }
            timing.iteration += 1
            if timing.iteration==276 { timing.frozen=true; timing.done.signal() }
        }
        return status
    }
    engine.attach(source); engine.connect(source,to:engine.mainMixerNode,format:format)
    engine.prepare(); try engine.start()
    let completed=timing.done.wait(timeout:.now()+15) == .success
    engine.stop()
    guard completed else { throw NSError(domain:"DeviceProbe",code:2,userInfo:[NSLocalizedDescriptionKey:"Audio callbacks did not complete"]) }
    guard timing.error == noErr else { throw NSError(domain:NSOSStatusErrorDomain,code:Int(timing.error)) }
    let wallOverruns=zip(timing.wall,timing.budget).filter { $0.0>$0.1 }.count
    let cpuOverruns=zip(timing.cpu,timing.budget).filter { $0.0>$0.1 }.count
    print("Muted output-device probe: \(Int(rate)) Hz, QoS \(timing.qos), wall overruns \(wallOverruns)/256, CPU overruns \(cpuOverruns)/256")
    print(String(format:"Max wall %.3f ms; max CPU %.3f ms; min budget %.3f ms",(timing.wall.max() ?? 0)*1000,(timing.cpu.max() ?? 0)*1000,(timing.budget.min() ?? 0)*1000))
}
if CommandLine.arguments.contains("--run-muted-output") { try runMutedDeviceProbe() }
else { print("Device probe is opt-in: --run-muted-output (synth master stays zero)") }
