// Opt in only: --run-muted-output --frames 64|128 --seconds 12 --report path.
// Temporarily sets the default output device to 96 kHz and restores its prior rate/buffer.
// Compile with the four DSP sources, -O and -parse-as-library.
import AVFoundation
import AudioToolbox
import Darwin
import CoreAudio
import Dispatch

private func seconds(_ clock: clockid_t) -> Double {
    var t=timespec();precondition(clock_gettime(clock,&t)==0)
    return Double(t.tv_sec)+Double(t.tv_nsec)*1e-9
}
private struct Point {
    var frames: UInt32=0
    var wall=0.0,cpu=0.0,sampleTime=0.0
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
        $0.masterVolume=0
        $0.expression.enabled=true;$0.expression.ladder=0.6
        $0.expression.oscillatorColor=0.5;$0.expression.mixerDrive=0.5;$0.expression.pan=0
        $0.envBRelease=8;$0.envARelease=8
        $0.oscSync=true;$0.oscAPulse=true;$0.oscBPulse=true
        $0.polyModOscB=0.7;$0.polyModToFreqA=true;$0.polyModToFilter=true;$0.polyModToPWA=true
        $0.resonance=1
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
    try unit.allocateRenderResources()
    for note in 48..<56 { unit.noteOn(note,velocity:0.8) }
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
private func readProperty<T>(_ device:AudioObjectID,_ selector:AudioObjectPropertySelector,_ value:inout T) throws {
    var address=AudioObjectPropertyAddress(mSelector:selector,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
    var size=UInt32(MemoryLayout<T>.size)
    let status=AudioObjectGetPropertyData(device,&address,0,nil,&size,&value)
    if status != noErr { throw NSError(domain:NSOSStatusErrorDomain,code:Int(status)) }
}
private func writeProperty<T>(_ device:AudioObjectID,_ selector:AudioObjectPropertySelector,_ value:T) throws {
    var address=AudioObjectPropertyAddress(mSelector:selector,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
    var copy=value
    let status=AudioObjectSetPropertyData(device,&address,0,nil,UInt32(MemoryLayout<T>.size),&copy)
    if status != noErr { throw NSError(domain:NSOSStatusErrorDomain,code:Int(status)) }
}
@main private struct ExtendedOutputDeadlineProbe {
    static func main() throws {
        guard CommandLine.arguments.contains("--run-muted-output") else { print("Opt-in: --run-muted-output [--seconds 30] [--report path]");return }
        func argument(_ key:String)->String? {
            guard let i=CommandLine.arguments.firstIndex(of:key),i+1<CommandLine.arguments.count else { return nil }
            return CommandLine.arguments[i+1]
        }
        setbuf(stdout,nil)
        let duration=min(120,max(5,Double(argument("--seconds") ?? "30") ?? 30))
        let path=argument("--report") ?? "/tmp/synth-matched-deadline.json"
        let requestedFrames=UInt32(argument("--frames") ?? "64") ?? 64
        guard [64,128].contains(requestedFrames) else { throw NSError(domain:"Probe",code:1) }
        var deviceID=AudioDeviceID(0),oldFrames:UInt32=0,oldRate:Double=0
        try readProperty(AudioObjectID(kAudioObjectSystemObject),kAudioHardwarePropertyDefaultOutputDevice,&deviceID)
        try readProperty(deviceID,kAudioDevicePropertyBufferFrameSize,&oldFrames)
        try readProperty(deviceID,kAudioDevicePropertyNominalSampleRate,&oldRate)
        defer {
            do {
                try writeProperty(deviceID,kAudioDevicePropertyNominalSampleRate,oldRate)
                try writeProperty(deviceID,kAudioDevicePropertyBufferFrameSize,oldFrames)
                print("Restored device rate \(oldRate), frames \(oldFrames)")
            } catch { print("DEVICE RESTORE FAILED: \(error)") }
        }
        try writeProperty(deviceID,kAudioDevicePropertyNominalSampleRate,96000.0)
        try writeProperty(deviceID,kAudioDevicePropertyBufferFrameSize,requestedFrames)
        Thread.sleep(forTimeInterval:0.3)
        var actualFrames:UInt32=0
        try readProperty(deviceID,kAudioDevicePropertyBufferFrameSize,&actualFrames)
        let engine=AVAudioEngine(),rate=engine.outputNode.inputFormat(forBus:0).sampleRate
        guard actualFrames==requestedFrames,abs(rate-96000)<1 else { throw NSError(domain:"Probe device format mismatch",code:2) }
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
                    capture.points[capture.count]=Point(frames:frames,wall:wall,cpu:cpu,sampleTime:timestamp.pointee.mSampleTime)
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
        Thread.sleep(forTimeInterval:duration*0.5)
        for note in 48..<56 { unit.noteOff(note) }
        let completed=capture.done.wait(timeout:.now()+duration+15) == .success
        engine.stop();unit.deallocateRenderResources()
        guard completed && !capture.overflow && capture.status==noErr else { throw NSError(domain:"Probe render failed",code:Int(capture.status)) }
        let device=Array(capture.points.prefix(capture.count))
        let measured=Array(device.dropFirst(20))
        let gaps=zip(measured,measured.dropFirst()).filter { abs($1.sampleTime-$0.sampleTime-Double($0.frames))>0.5 }.count
        let report:[String:Any]=["sample_rate":rate,"requested_frames":requestedFrames,"requested_seconds":duration,"muted":true,
            "device":summary(device,rate:rate,qos:capture.qos),"timestamp_gaps":gaps,
            "scope":"Extended eight voices, eight-second releases, Sync/Poly-Mod, high resonance, ladder and all FX. Note-off halfway through capture. Measures core callback, excluding downstream mixer/driver. Muted DSP/FX still run; no audible-dropout claim. Device rate and buffer restored on completion/errors."]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:path))
        print("Report: \(path)")
    }
}
