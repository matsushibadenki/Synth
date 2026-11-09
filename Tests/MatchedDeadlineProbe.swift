// swiftc -O Rev3Parameters.swift EffectsGraph.swift EffectsDSP.swift ProphetCore.swift
// Tests/MatchedDeadlineProbe.swift -o /tmp/synth-matched-deadline
// Opt in: --run-muted-output [--seconds 30] [--report /tmp/matched.json]
// Records actual device frame lengths, then replays them from fresh identical AU state.
import AVFoundation
import AudioToolbox
import Darwin
import Dispatch

private func seconds(_ clock: clockid_t) -> Double {
    var t=timespec();precondition(clock_gettime(clock,&t)==0)
    return Double(t.tv_sec)+Double(t.tv_nsec)*1e-9
}
private struct Point {
    var frames: UInt32=0
    var wall=0.0,cpu=0.0
}
private final class Capture {
    let done=DispatchSemaphore(value:0)
    var points: [Point]
    var count=0,total: UInt64=0,frozen=false,overflow=false
    var status: OSStatus=0,qos: UInt32=0
    let target: UInt64
    init(rate: Double,duration: Double) {
        target=UInt64(rate*duration)
        points=Array(repeating:Point(),count:Int(ceil(rate*duration/16))+2048)
    }
}
private func makeUnit(rate: Double) throws -> ProphetLikeAudioUnit {
    let params=SharedSynthParameters(),fx=SharedEffects()
    params.set {
        $0.masterVolume=0;$0.unisonMode=true;$0.oscSync=true;$0.resonance=1
        $0.oscAPulse=true;$0.oscBPulse=true;$0.oscBTriangle=true
        $0.polyModOscB=0.7;$0.polyModToFreqA=true;$0.polyModToFilter=true;$0.polyModToPWA=true
        $0.lfoToPWA=true;$0.lfoToPWB=true;$0.modWheel=1;$0.wheelSourceMix=1
    }
    var document=FXDocument.initial
    for i in 1...6 { document.nodes[i].settings.enabled=true }
    document.nodes[EffectKind.studio.rawValue].settings.mode=2
    fx.set(try document.configuration())
    ProphetLikeAudioUnit.sharedParameters=params;ProphetLikeAudioUnit.sharedEffects=fx
    let unit=try ProphetLikeAudioUnit(componentDescription:AudioComponentDescription(
        componentType:kAudioUnitType_Generator,componentSubType:0x50723535,
        componentManufacturer:0x53796E74,componentFlags:0,componentFlagsMask:0))
    try unit.outputBusses[0].setFormat(AVAudioFormat(standardFormatWithSampleRate:rate,channels:2)!)
    try unit.allocateRenderResources();unit.noteOn(60,velocity:1)
    return unit
}
private func summary(_ all: [Point],rate: Double,qos: UInt32) -> [String:Any] {
    let points=Array(all.dropFirst(20));precondition(!points.isEmpty)
    func percentile(_ values:[Double],_ fraction:Double)->Double {
        let sorted=values.sorted();return sorted[Int(Double(sorted.count-1)*fraction)]*1000
    }
    let over=points.filter { $0.wall>Double($0.frames)/rate }
    return ["callbacks":points.count,"qos_code":qos,
        "wall_overruns":over.count,"cpu_overruns":points.filter { $0.cpu>Double($0.frames)/rate }.count,
        "non_cpu_wall_overruns":over.filter { $0.cpu<=Double($0.frames)/rate }.count,
        "wall_p95_ms":percentile(points.map(\.wall),0.95),"wall_max_ms":points.map(\.wall).max()!*1000,
        "cpu_p95_ms":percentile(points.map(\.cpu),0.95),"cpu_max_ms":points.map(\.cpu).max()!*1000,
        "minimum_budget_ms":Double(points.map(\.frames).min()!)/rate*1000,
        "frame_histogram":Dictionary(grouping:points,by:{String($0.frames)}).mapValues(\.count)]
}
private func replay(_ frames:[UInt32],rate:Double,interactive:Bool) throws -> (points:[Point],qos:UInt32) {
    let original=qos_class_self()
    let requested=interactive ? QOS_CLASS_USER_INTERACTIVE:QOS_CLASS_DEFAULT
    precondition(pthread_set_qos_class_self_np(requested,0)==0)
    let actual=qos_class_self().rawValue
    precondition(actual==requested.rawValue)
    defer { precondition(pthread_set_qos_class_self_np(original,0)==0) }
    let unit=try makeUnit(rate:rate);defer { unit.deallocateRenderResources() }
    let buffer=AVAudioPCMBuffer(pcmFormat:unit.outputBusses[0].format,frameCapacity:frames.max()!)!
    let render=unit.internalRenderBlock
    var flags=AudioUnitRenderActionFlags(),time=AudioTimeStamp()
    time.mFlags = .sampleTimeValid
    var points=[Point]();points.reserveCapacity(frames.count)
    for frames in frames {
        let start=seconds(CLOCK_UPTIME_RAW),cpuStart=seconds(CLOCK_THREAD_CPUTIME_ID)
        let status=render(&flags,&time,frames,0,buffer.mutableAudioBufferList,nil,nil)
        let cpu=seconds(CLOCK_THREAD_CPUTIME_ID)-cpuStart,wall=seconds(CLOCK_UPTIME_RAW)-start
        precondition(status==noErr)
        points.append(Point(frames:frames,wall:wall,cpu:cpu));time.mSampleTime += Double(frames)
        // Muted output must remain finite and silent in both channels.
        for channel in 0..<2 { for i in 0..<Int(frames) { precondition(buffer.floatChannelData![channel][i]==0) } }
    }
    return (points,actual)
}
@main private struct MatchedDeadlineProbe {
    static func main() throws {
        guard CommandLine.arguments.contains("--run-muted-output") else { print("Opt-in: --run-muted-output [--seconds 30] [--report path]");return }
        func argument(_ key:String)->String? {
            guard let i=CommandLine.arguments.firstIndex(of:key),i+1<CommandLine.arguments.count else { return nil }
            return CommandLine.arguments[i+1]
        }
        setbuf(stdout,nil)
        let duration=min(120,max(5,Double(argument("--seconds") ?? "30") ?? 30))
        let path=argument("--report") ?? "/tmp/synth-matched-deadline.json"
        let engine=AVAudioEngine(),rate=engine.outputNode.inputFormat(forBus:0).sampleRate
        precondition(rate>0)
        let unit=try makeUnit(rate:rate),capture=Capture(rate:rate,duration:duration)
        let render=unit.internalRenderBlock
        let source=AVAudioSourceNode(format:unit.outputBusses[0].format) { silent,timestamp,frames,buffers in
            var flags=AudioUnitRenderActionFlags(),time=timestamp.pointee
            let start=seconds(CLOCK_UPTIME_RAW),cpuStart=seconds(CLOCK_THREAD_CPUTIME_ID)
            let status=render(&flags,&time,frames,0,buffers,nil,nil)
            let cpu=seconds(CLOCK_THREAD_CPUTIME_ID)-cpuStart,wall=seconds(CLOCK_UPTIME_RAW)-start
            silent.pointee=true
            if !capture.frozen {
                capture.status=status == noErr ? capture.status:status
                if capture.count<capture.points.count {
                    capture.points[capture.count]=Point(frames:frames,wall:wall,cpu:cpu)
                    capture.count += 1;capture.total += UInt64(frames);capture.qos=qos_class_self().rawValue
                } else { capture.overflow=true }
                if capture.total>=capture.target || capture.overflow {
                    capture.frozen=true;capture.done.signal()
                }
            }
            return status
        }
        engine.attach(source);engine.connect(source,to:engine.mainMixerNode,format:unit.outputBusses[0].format)
        engine.prepare();try engine.start()
        print("Capturing muted output: \(Int(rate)) Hz, \(duration) seconds")
        let completed=capture.done.wait(timeout:.now()+duration+15) == .success
        engine.stop();unit.deallocateRenderResources()
        precondition(completed && !capture.overflow && capture.status==noErr)
        let device=Array(capture.points.prefix(capture.count)),frames=device.map(\.frames)
        var runs:[[String:Any]]=[]
        // Alternate replay order; all builds must finish before starting this probe.
        for interactive in [false,true,true,false] {
            let replayed=try replay(frames,rate:rate,interactive:interactive)
            var run=summary(replayed.points,rate:rate,qos:replayed.qos)
            run["profile"]=interactive ? "offline-interactive":"offline-default";runs.append(run)
            print("Replay \(run["profile"]!): wall \(run["wall_overruns"]!), CPU \(run["cpu_overruns"]!)")
        }
        let report:[String:Any]=["sample_rate":rate,"requested_seconds":duration,"muted":true,
            "device":summary(device,rate:rate,qos:capture.qos),"replays":runs,"frame_sequence":frames,
            "scope":"Fixed identical patch and FX, fresh AU per run, exact device frame sequence including 20 warmup callbacks. Offline is unpaced. QoS changes only the diagnostic thread and is restored. Device timing excludes downstream mixer/driver; no audible dropout claim. Master zero still runs the DSP/FX path."]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:path))
        print("Report: \(path)")
    }
}
