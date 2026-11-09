// Opt-in macOS stress harness. Existing production views/renderers; muted AU.
// Compile Rev3Parameters, EffectsGraph, EffectsDSP, ProphetCore, MetalPanelRenderer,
// InstrumentChrome, InstrumentPanel, MasterVolumeControl and this file with swiftc -O.
import SwiftUI
import AppKit
import MetalKit
import AVFoundation
import AudioToolbox
import Darwin

private func stressClock(_ kind: clockid_t = CLOCK_UPTIME_RAW) -> Double {
    var t=timespec(); clock_gettime(kind,&t)
    return Double(t.tv_sec)+Double(t.tv_nsec)*1e-9
}
private func stressProcessCPU() -> Double {
    var r=rusage(); getrusage(RUSAGE_SELF,&r)
    return Double(r.ru_utime.tv_sec+r.ru_stime.tv_sec)+Double(r.ru_utime.tv_usec+r.ru_stime.tv_usec)*1e-6
}
private struct AudioObservation {
    var start=0.0,wall=0.0,cpu=0.0,budget=0.0,intervalRatio=0.0,timelineGap=0.0
    var frames: UInt32=0
}
private final class StressTiming {
    let done=DispatchSemaphore(value:0)
    var points: [AudioObservation]
    var count=0,warmup=0,frames: UInt64=0,frozen=false,overflow=false
    var lastStart=0.0,lastBudget=0.0,lastSample: Float64?,lastFrames: UInt32=0
    var error: OSStatus=0,qos: UInt32=0
    let target: UInt64
    init(rate: Double,seconds: Double) {
        target=UInt64(rate*seconds)
        points=Array(repeating:AudioObservation(),count:Int(ceil(rate*seconds/32))+1024)
    }
}
private struct GPUObservation { var start: Double, end: Double, updateCPU: Double }
private final class GPULoad {
    let queue=DispatchQueue(label:"synth.test.gpu",qos:.userInitiated)
    let renderer: MetalPanelRenderer
    let layout=PanelLayout(columns:3)
    var timer: DispatchSourceTimer?
    var points=[GPUObservation](), error: String?
    var values=Array(repeating:0.5,count:28), switches=Array(repeating:false,count:22)
    init(seconds: Double) throws {
        guard let device=MTLCreateSystemDefaultDevice() else { throw NSError(domain:"GPUProbe",code:1) }
        renderer=try MetalPanelRenderer(device:device)
        points.reserveCapacity(Int(seconds*30)+512)
        try queue.sync {
            renderer.update(layout:layout,values:values,activeNotes:[],switches:switches)
            _=try renderer.preview(width:960,height:Int(960/CGFloat(layout.aspect)))
        }
    }
    func start() {
        let timer=DispatchSource.makeTimerSource(queue:queue);self.timer=timer
        timer.schedule(deadline:.now(),repeating:1.0/30,leeway:.milliseconds(1))
        timer.setEventHandler { [self] in
          autoreleasepool {
            let frame=points.count,start=stressClock(),cpuStart=stressClock(CLOCK_THREAD_CPUTIME_ID)
            values[12]=(sin(Double(frame)*0.07)+1)/2
            values[5]=(sin(Double(frame)*0.11)+1)/2;values[27]=values[12]
            switches[0]=(frame/30)%2 == 0
            renderer.update(layout:layout,values:values,activeNotes:frame%30<15 ? [60,64,67]:[],switches:switches)
            let updateCPU=stressClock(CLOCK_THREAD_CPUTIME_ID)-cpuStart
            do {
                _=try renderer.preview(width:960,height:Int(960/CGFloat(layout.aspect)))
                points.append(GPUObservation(start:start,end:stressClock(),updateCPU:updateCPU))
            } catch { self.error=String(describing:error);timer.cancel() }
          }
        }
        timer.resume()
    }
    func stop() { timer?.cancel();queue.sync { timer?.setEventHandler {};timer=nil } }
}
@MainActor private final class ProbeUIState: ObservableObject {
    @Published var parameters=SynthParameters()
    var tick=0
    var controls: [PanelControl] {
        Rev3.knobs.map { item in
            PanelControl(label:item.label,title:instrumentText(item.names[0],item.names[1],item.names[2]),
                value:Binding(get:{Double(self.parameters[keyPath:item.key])},set:{self.parameters[keyPath:item.key]=Float($0)}),
                range:Double(item.range.lowerBound)...Double(item.range.upperBound),logarithmic:item.curve == 1,quantized:item.curve == 2)
        }+[
            PanelControl(label:"PITCH",title:"PITCH",value:.constant(0),range:-1...1),
            PanelControl(label:"MOD",title:"MOD",value:Binding(get:{Double(self.parameters.modWheel)},set:{self.parameters.modWheel=Float($0)}),range:0...1)
        ]
    }
    var switches: [PanelSwitch] {
        Rev3.switches.map { item in
            PanelSwitch(label:item.label,title:instrumentText(item.names[0],item.names[1],item.names[2]),
                value:Binding(get:{self.parameters[keyPath:item.key]},set:{self.parameters[keyPath:item.key]=$0}))
        }
    }
}
@MainActor private struct ProbePanel: View {
    @ObservedObject var state: ProbeUIState
    var body: some View {
        ScrollView {
            VStack(spacing:8) {
                HStack {
                    Text("SYNTH/05").font(InstrumentFinish.wordmark)
                    Spacer(minLength:8)
                    MasterVolumeControl(controls:state.controls,switches:state.switches.map { $0.value.wrappedValue },scale:36,horizontal:true,changed:{})
                }
                MetalInstrumentSurface(layout:PanelLayout(columns:2,keyboardOnly:true),values:state.controls.map(\.normalized),
                    activeNotes:state.tick%60<30 ? [60,64,67]:[],switches:state.switches.map { $0.value.wrappedValue },unavailable:.constant(false))
                    .aspectRatio(CGFloat(PanelLayout(columns:2,keyboardOnly:true).aspect),contentMode:.fit)
                InstrumentPanel(controls:state.controls,switches:state.switches,enabled:false,changed:{})
            }.foregroundStyle(InstrumentFinish.ink).padding(.horizontal,16).padding(.vertical,12)
        }.background(InstrumentFinish.backdrop).preferredColorScheme(.dark)
    }
}
@main private struct UIGPUDeadlineProbe {
    @MainActor static func main() throws {
        guard CommandLine.arguments.contains("--run-muted-output") else {
            print("Opt-in: --run-muted-output --seconds 120 [--ui-gpu] [--fx-routing] --report /tmp/report.json");return
        }
        func argument(_ key: String) -> String? {
            guard let i=CommandLine.arguments.firstIndex(of:key),i+1<CommandLine.arguments.count else { return nil }
            return CommandLine.arguments[i+1]
        }
        let seconds=min(600,max(5,Double(argument("--seconds") ?? "120") ?? 120))
        let loaded=CommandLine.arguments.contains("--ui-gpu")
        let routing=CommandLine.arguments.contains("--fx-routing")
        let reportPath=argument("--report") ?? "/tmp/synth-ui-gpu-deadline.json"
        setbuf(stdout,nil)
        let application=NSApplication.shared
        application.setActivationPolicy(.accessory)
        application.finishLaunching()
        let state=ProbeUIState()
        var window: NSWindow?
        if loaded {
            let w=NSWindow(contentRect:NSRect(x:60,y:60,width:1100,height:850),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
            w.title=instrumentText("Muted load probe · SYNTH/05","無音負荷試験 · SYNTH/05","静音负载测试 · SYNTH/05")
            w.isReleasedWhenClosed=false;w.contentView=NSHostingView(rootView:ProbePanel(state:state))
            w.orderFrontRegardless();w.displayIfNeeded();window=w
        }
        let gpu=loaded ? try GPULoad(seconds:seconds):nil
        let engine=AVAudioEngine(),rate=engine.outputNode.inputFormat(forBus:0).sampleRate
        guard rate>0 else { throw NSError(domain:"OutputProbe",code:1) }
        let format=AVAudioFormat(standardFormatWithSampleRate:rate,channels:2)!
        let params=SharedSynthParameters(),effects=SharedEffects()
        params.set {
            $0.masterVolume=0;$0.unisonMode=true;$0.oscSync=true;$0.resonance=1
            $0.oscAPulse=true;$0.oscBPulse=true;$0.oscBTriangle=true
            $0.polyModOscB=0.7;$0.polyModToFreqA=true;$0.polyModToFilter=true;$0.polyModToPWA=true
            $0.lfoToPWA=true;$0.lfoToPWB=true;$0.modWheel=1;$0.wheelSourceMix=1
        }
        state.parameters=params.snapshot()
        var document=FXDocument.initial
        for i in 1...6 { document.nodes[i].settings.enabled=true }
        document.nodes[EffectKind.studio.rawValue].settings.mode=2
        effects.set(try document.configuration())
        // Compile and validate routing plans before starting audio. No graph building in render.
        var bypass=document
        for i in 1...6 { bypass.nodes[i].settings.enabled=false }
        var reordered=document
        let chain=[0,6,5,4,3,2,1,8]
        reordered.edges=zip(chain,chain.dropFirst()).map { FXEdge(from:$0,to:$1,port:"in") }
        let routingPlans=try [document,bypass,reordered].map { try $0.configuration() }
        ProphetLikeAudioUnit.sharedParameters=params;ProphetLikeAudioUnit.sharedEffects=effects
        let unit=try ProphetLikeAudioUnit(componentDescription:AudioComponentDescription(componentType:kAudioUnitType_Generator,
            componentSubType:0x50723535,componentManufacturer:0x53796E74,componentFlags:0,componentFlagsMask:0))
        try unit.outputBusses[0].setFormat(format);try unit.allocateRenderResources()
        defer { unit.deallocateRenderResources() }
        unit.noteOn(60,velocity:1)
        let render=unit.internalRenderBlock,timing=StressTiming(rate:rate,seconds:seconds)
        let source=AVAudioSourceNode(format:format) { silent,timestamp,frames,buffers in
            var flags=AudioUnitRenderActionFlags(),time=timestamp.pointee
            let start=stressClock(),cpuStart=stressClock(CLOCK_THREAD_CPUTIME_ID)
            let status=render(&flags,&time,frames,0,buffers,nil,nil)
            let cpu=stressClock(CLOCK_THREAD_CPUTIME_ID)-cpuStart,wall=stressClock()-start
            silent.pointee=false
            if !timing.frozen {
                if status != noErr { timing.error=status }
                let valid=time.mFlags.contains(.sampleTimeValid)
                let gap=valid ? timing.lastSample.map { time.mSampleTime-$0-Double(timing.lastFrames) } ?? 0:0
                let ratio=timing.lastBudget>0 ? (start-timing.lastStart)/timing.lastBudget:1
                timing.lastStart=start;timing.lastBudget=Double(frames)/rate
                timing.lastSample=valid ? time.mSampleTime:nil;timing.lastFrames=frames
                if timing.warmup<20 { timing.warmup += 1 }
                else if timing.count<timing.points.count {
                    timing.points[timing.count]=AudioObservation(start:start,wall:wall,cpu:cpu,budget:Double(frames)/rate,
                        intervalRatio:ratio,timelineGap:gap,frames:frames)
                    timing.count += 1;timing.frames += UInt64(frames);timing.qos=qos_class_self().rawValue
                } else { timing.overflow=true }
                if timing.frames>=timing.target || timing.overflow {
                    timing.frozen=true;timing.done.signal()
                }
            }
            return status
        }
        engine.attach(source);engine.connect(source,to:engine.mainMixerNode,format:format)
        var ticks=0,visibleTicks=0,resizes=0,routeChanges=0,tickMax=0.0
        let sizes=[NSSize(width:1100,height:850),NSSize(width:740,height:850),NSSize(width:390,height:850)]
        let controlTimer=Timer(timeInterval:1.0/60,repeats:true) { _ in
          MainActor.assumeIsolated {
            let start=stressClock();ticks += 1
            if routing && ticks%120 == 0 {
                routeChanges += 1;effects.set(routingPlans[routeChanges%routingPlans.count])
            }
            let n=Double(ticks)
            let cutoff=Float(0.45+0.3*sin(n*0.012)),width=Float(0.5+0.45*sin(n*0.017)),mix=Float((sin(n*0.008)+1)/2)
            params.set { $0.cutoffNorm=cutoff;$0.oscAPulseWidth=width;$0.wheelSourceMix=mix;$0.masterVolume=0 }
            if loaded {
                var p=state.parameters;p.cutoffNorm=cutoff;p.oscAPulseWidth=width;p.wheelSourceMix=mix
                state.tick=ticks;state.parameters=p
                if ticks%240 == 0 { window?.setContentSize(sizes[(ticks/240)%3]);resizes += 1 }
                if window?.occlusionState.contains(.visible) == true { visibleTicks += 1 }
            }
            tickMax=max(tickMax,stressClock()-start)
          }
        }
        controlTimer.tolerance=0.001;RunLoop.main.add(controlTimer,forMode:.common)
        engine.prepare();gpu?.start()
        let begin=stressClock(),cpuBegin=stressProcessCPU()
        try engine.start()
        var completed=false,nextProgress=begin+15
        while stressClock()-begin<seconds+30 {
            if timing.done.wait(timeout:.now()) == .success { completed=true;break }
            autoreleasepool {
                if let event=application.nextEvent(matching:.any,until:Date(timeIntervalSinceNow:0.01),inMode:.default,dequeue:true) {
                    application.sendEvent(event)
                }
                application.updateWindows()
            }
            if stressClock()>=nextProgress {
                print(String(format:"Probe %@: %.0f / %.0f s; control ticks %d",loaded ? "UI+GPU":"baseline",stressClock()-begin,seconds,ticks))
                nextProgress += 15
            }
        }
        controlTimer.invalidate();engine.stop();gpu?.stop();window?.close()
        let elapsed=stressClock()-begin,processCPU=stressProcessCPU()-cpuBegin
        guard completed && !timing.overflow else { throw NSError(domain:"OutputProbe",code:2,userInfo:[NSLocalizedDescriptionKey:"Incomplete measurement or telemetry capacity exceeded"]) }
        let points=Array(timing.points.prefix(timing.count)),gpuPoints=gpu?.points ?? []
        func percentile(_ values:[Double],_ fraction:Double)->Double {
            let sorted=values.sorted();guard !sorted.isEmpty else { return 0 };return sorted[min(sorted.count-1,Int(Double(sorted.count-1)*fraction))]
        }
        let wallOverruns=points.filter { $0.wall>$0.budget },cpuOverruns=points.filter { $0.cpu>$0.budget }
        let nonCPUOverruns=wallOverruns.filter { $0.cpu<=$0.budget }
        let timelineGaps=points.filter { abs($0.timelineGap)>0.5 }
        let intervalOutliers=points.filter { $0.intervalRatio>1.25 }
        let worstIntervals=points.sorted { $0.intervalRatio>$1.intervalRatio }.prefix(16).map { p -> [String:Any] in
            ["time_s":p.start-begin,"interval_ratio":p.intervalRatio,"wall_ms":p.wall*1000,"cpu_ms":p.cpu*1000,
             "budget_ms":p.budget*1000,"timeline_gap_frames":p.timelineGap]
        }
        let worst=points.sorted { $0.wall>$1.wall }.prefix(16).map { p -> [String:Any] in
            ["time_s":p.start-begin,"wall_ms":p.wall*1000,"cpu_ms":p.cpu*1000,"budget_ms":p.budget*1000,
             "interval_ratio":p.intervalRatio,"gpu_overlap_count":gpuPoints.filter { $0.start<=p.start+p.wall && $0.end>=p.start }.count]
        }
        let report:[String:Any]=[
            "profile":loaded ? "existing SwiftUI views + 30fps offscreen Metal preview":"audio + 60Hz control changes",
            "requested_seconds":seconds,"elapsed_seconds":elapsed,"sample_rate":rate,"timed_callbacks":points.count,
            "measured_audio_seconds":Double(timing.frames)/rate,"qos_code":timing.qos,"muted":true,"render_status":Int(timing.error),
            "wall_overruns":wallOverruns.count,"cpu_overruns":cpuOverruns.count,"non_cpu_wall_overruns":nonCPUOverruns.count,
            "sample_timeline_discontinuities":timelineGaps.count,"callback_interval_gt_1_25":intervalOutliers.count,
            "callback_interval_p99":percentile(points.map(\.intervalRatio),0.99),"callback_interval_max":points.map(\.intervalRatio).max() ?? 0,
            "wall_p95_ms":percentile(points.map(\.wall),0.95)*1000,"wall_p99_ms":percentile(points.map(\.wall),0.99)*1000,
            "wall_max_ms":points.map(\.wall).max()! * 1000,"cpu_max_ms":points.map(\.cpu).max()! * 1000,
            "minimum_budget_ms":points.map(\.budget).min()! * 1000,"process_cpu_seconds":processCPU,
            "fx_routing_enabled":routing,"fx_route_changes":routeChanges,"control_ticks":ticks,"ui_visible_ticks":visibleTicks,"window_resizes":resizes,"control_tick_max_ms":tickMax*1000,
            "gpu_completed_previews":gpuPoints.count,"gpu_error":gpu?.error as Any? ?? NSNull(),
            "gpu_update_cpu_p95_ms":percentile(gpuPoints.map(\.updateCPU),0.95)*1000,
            "gpu_preview_wall_p95_ms":percentile(gpuPoints.map { $0.end-$0.start },0.95)*1000,
            "worst_callbacks":worst,"worst_callback_intervals":worstIntervals,
            "scope":"AU kernel timing and timestamp continuity; interval outliers are not driver underrun counts. Excludes downstream mixer/driver costs. Metal preview includes texture allocation/readback."
        ]
        let data=try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])
        try data.write(to:URL(fileURLWithPath:reportPath))
        print("Completed: \(points.count) callbacks, wall overruns \(wallOverruns.count), CPU overruns \(cpuOverruns.count), timeline gaps \(timelineGaps.count), GPU previews \(gpuPoints.count) → \(reportPath)")
        if routing { precondition(routeChanges>=2,"FX routing transitions were not exercised") }
        if loaded { precondition(visibleTicks>0 && gpuPoints.count>10 && gpu?.error == nil,"UI/GPU load was not exercised") }
        precondition(timing.error == noErr,"Audio render failed")
    }
}
