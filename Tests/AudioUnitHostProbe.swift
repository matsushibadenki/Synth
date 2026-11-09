// Compile separately with swiftc -O -parse-as-library; requires the built AUv3 to be registered.
// Real out-of-process AUv3 hosting, without starting an audio output device.
import AVFoundation
import CoreAudioKit
import AppKit

@main struct AudioUnitHostProbe {
    @MainActor static func main() throws {
        let app=NSApplication.shared;app.setActivationPolicy(.accessory);app.finishLaunching()
        func wait(_ condition:()->Bool) {
            let deadline=Date().addingTimeInterval(25)
            while !condition() && Date()<deadline { RunLoop.main.run(until:Date().addingTimeInterval(0.01)) }
            precondition(condition(),"AUv3 host callback timed out")
        }
        let desc=AudioComponentDescription(componentType:kAudioUnitType_MusicDevice,componentSubType:0x53303561,
            componentManufacturer:0x53793035,componentFlags:0,componentFlagsMask:0)
        var result:AVAudioUnit?,error:Error?,finished=false
        AVAudioUnit.instantiate(with:desc,options:.loadOutOfProcess) { unit,failure in
            DispatchQueue.main.async { result=unit;error=failure;finished=true }
        }
        wait { finished };if let error { throw error };let unit=result!.auAudioUnit
        precondition(unit.parameterTree?.allParameters.count==50)
        var vc:NSViewController?,viewFinished=false
        unit.requestViewController { controller in
            DispatchQueue.main.async { vc=controller;viewFinished=true }
        }
        wait { viewFinished };precondition(vc != nil,"Registered AUv3 must supply its custom view")
        let window=NSWindow(contentRect:NSRect(x:40,y:40,width:1100,height:850),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false;window.title="SYNTH/05 · AUv3 host test (no audio output)"
        window.contentViewController=vc;window.setContentSize(NSSize(width:1100,height:850));window.orderFrontRegardless()
        RunLoop.main.run(until:Date().addingTimeInterval(0.5))
        let old=unit.fullState!
        unit.parameterTree!.parameter(withAddress:12)!.value=0.71
        let state=unit.fullState!;unit.fullState=old;unit.fullState=state
        try unit.outputBusses[0].setFormat(AVAudioFormat(standardFormatWithSampleRate:48000,channels:2)!)
        unit.maximumFramesToRender=512;try unit.allocateRenderResources()
        defer { unit.deallocateRenderResources();window.close() }
        let buffer=AVAudioPCMBuffer(pcmFormat:unit.outputBusses[0].format,frameCapacity:512)!
        var flags=AudioUnitRenderActionFlags(),time=AudioTimeStamp();time.mFlags = .sampleTimeValid
        let bytes:[UInt8]=[0x90,60,64]
        bytes.withUnsafeBufferPointer { unit.scheduleMIDIEventBlock!(AUEventSampleTimeImmediate,0,3,$0.baseAddress!) }
        let render=unit.renderBlock
        var peak:Float=0
        for _ in 0..<20 {
            precondition(render(&flags,&time,512,0,buffer.mutableAudioBufferList,nil)==noErr)
            for i in 0..<512 {
                let x=buffer.floatChannelData![0][i];precondition(x.isFinite);peak=max(peak,abs(x))
            }
            time.mSampleTime += 512
        }
        precondition(peak>0.001)
        print("Out-of-process AUv3: 50 parameters, custom UI, state roundtrip and host MIDI/velocity rendering passed; no output device started")
        if CommandLine.arguments.contains("--hold-ui") {
            RunLoop.main.run(until:Date().addingTimeInterval(120))
        }
    }
}
