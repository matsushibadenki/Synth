// swiftc -O audio sources + MIDIInputState + HostedSynthAudioUnit + this file.
// Does not start a device, register a plugin or send external MIDI.
import AVFoundation
import AudioToolbox

private func check(_ value:@autoclosure ()->Bool,_ message:String="",line:UInt=#line) {
    if !value() { fputs("FAIL line \(line): \(message)\n",stderr);exit(1) }
}
private let description=AudioComponentDescription(componentType:kAudioUnitType_MusicDevice,componentSubType:0x53303561,
    componentManufacturer:0x53793035,componentFlags:0,componentFlagsMask:0)
private final class AUProbe {
    let unit:HostedSynthAudioUnit,buffer:AVAudioPCMBuffer,render:AUInternalRenderBlock
    var flags=AudioUnitRenderActionFlags(),time=AudioTimeStamp()
    init(_ rate:Double=48000) throws {
        unit=try HostedSynthAudioUnit(componentDescription:description)
        unit.maximumFramesToRender=512
        try unit.outputBusses[0].setFormat(AVAudioFormat(standardFormatWithSampleRate:rate,channels:2)!)
        unit.parameterStorage.set { $0.releaseEnabled=false;$0.envBAttack=0.001;$0.envBSustain=1;$0.oscBLevel=0 }
        try unit.allocateRenderResources()
        buffer=AVAudioPCMBuffer(pcmFormat:unit.outputBusses[0].format,frameCapacity:512)!
        render=unit.internalRenderBlock;time.mFlags = .sampleTimeValid
    }
    deinit { unit.deallocateRenderResources() }
    func samples(_ frames:UInt32=256,events:UnsafePointer<AURenderEvent>?=nil)->[Float] {
        check(render(&flags,&time,frames,0,buffer.mutableAudioBufferList,events,nil)==noErr)
        time.mSampleTime += Double(frames)
        return (0..<Int(frames)).map { i in
            let x=buffer.floatChannelData![0][i];check(x.isFinite && abs(x)<=1);return x
        }
    }
}
private func midiEvent(_ time:Int64,_ status:UInt8,_ a:UInt8,_ b:UInt8)->AURenderEvent {
    AURenderEvent(MIDI:AUMIDIEvent(next:nil,eventSampleTime:time,eventType:.MIDI,reserved:0,length:3,cable:0,data:(status,a,b)))
}
@main struct AudioUnitRegression {
    static func main() throws {
        let a=try AUProbe(),b=try AUProbe()
        check(a.unit.parameterTree!.allParameters.count==50)
        check(a.unit.scheduleMIDIEventBlock != nil,"Host MIDI scheduler must exist for aumu")
        a.unit.parameterTree!.parameter(withAddress:12)!.value=0.7
        check(a.unit.parameterStorage.snapshot().cutoffNorm==0.7)
        check(b.unit.parameterStorage.snapshot().cutoffNorm != 0.7,"Instances must not share a patch")
        a.unit.parameterStorage.set { $0.expression.enabled=true;$0.expression.ladder=0.75 }
        var doc=FXDocument.initial;doc.nodes[1].settings.enabled=true
        a.unit.effectStorage.set(try doc.configuration(),document:doc)
        let state=a.unit.fullState!
        b.unit.fullState=state
        check(b.unit.parameterStorage.snapshot().expression.ladder==0.75)
        check(b.unit.effectStorage.documentSnapshot()==doc)
        b.unit.parameterTree!.parameter(withAddress:12)!.value=0.2
        check(a.unit.parameterStorage.snapshot().cutoffNorm==0.7)
        let original=b.unit.parameterStorage.snapshot()
        b.unit.fullState=["synth05.version":1,"synth05.parameters":Data([0])]
        check(b.unit.parameterStorage.snapshot()==original,"Invalid state must be rejected without partial edits")
        for rate in [44100.0,48000.0,96000.0] {
            let p=try AUProbe(rate)
            var on=midiEvent(128,0x90,60,127)
            let first=withUnsafePointer(to:&on) { p.samples(events:$0) }
            check(first.prefix(128).allSatisfy { $0==0 },"No sound before scheduled note offset")
            check(first.suffix(128).contains { abs($0)>0.00001 })
            var off=midiEvent(256,0x90,60,0)
            _=withUnsafePointer(to:&off) { p.samples(events:$0) }
            var tail=[Float]()
            for _ in 0..<30 { tail=p.samples() }
            check(tail.allSatisfy { abs($0)<0.00001 })
            // Host may ask the unit to supply output storage.
            let nilBuffers=AudioBufferList.allocate(maximumBuffers:2)
            defer { nilBuffers.unsafeMutablePointer.deallocate() }
            for c in 0..<2 { nilBuffers[c]=AudioBuffer(mNumberChannels:1,mDataByteSize:256*4,mData:nil) }
            check(p.render(&p.flags,&p.time,256,0,nilBuffers.unsafeMutablePointer,nil,nil)==noErr)
            check(nilBuffers[0].mData != nil && nilBuffers[1].mData != nil)
            print("AU host render \(Int(rate)) Hz: scheduled offset, velocity-zero release, nil output buffers passed")
        }
        let p=try AUProbe()
        var event=AURenderEvent(parameter:AUParameterEvent(next:nil,eventSampleTime:64,eventType:.parameter,
            reserved:(0,0,0),rampDurationSampleFrames:0,parameterAddress:12,value:0.81))
        _=withUnsafePointer(to:&event) { p.samples(events:$0) }
        check(p.unit.parameterStorage.snapshot().cutoffNorm==0.81)
        check(p.unit.parameterTree!.implementorValueProvider(p.unit.parameterTree!.parameter(withAddress:12)!)==0.81)
        let uiBaseline=p.unit.parameterStorage.snapshot()
        var uiEdit=uiBaseline;uiEdit.resonance=0.6
        p.unit.parameterStorage.set { $0.cutoffNorm=0.5 }
        p.unit.applyUIParameters(uiEdit,previousUI:uiBaseline)
        check(p.unit.parameterStorage.snapshot().cutoffNorm==0.5,"A UI knob edit must preserve newer automation on another knob")
        check(p.unit.parameterStorage.snapshot().resonance==0.6)
        // Public host scheduling API, rather than calling the instrument's note queue.
        let publicUnit=try AUProbe()
        let bytes:[UInt8]=[0x90,64,127]
        bytes.withUnsafeBufferPointer { publicUnit.unit.scheduleMIDIEventBlock!(AUEventSampleTimeImmediate,0,3,$0.baseAddress!) }
        publicUnit.unit.scheduleParameterBlock(AUEventSampleTimeImmediate,0,12,0.73)
        let publicRender=publicUnit.unit.renderBlock
        check(publicRender(&publicUnit.flags,&publicUnit.time,256,0,publicUnit.buffer.mutableAudioBufferList,nil)==noErr)
        check(publicUnit.unit.parameterStorage.snapshot().cutoffNorm==0.73)
        check((0..<256).contains { abs(publicUnit.buffer.floatChannelData![0][$0])>0.00001 })
        // End-of-block events affect the next block, without writing beyond buffers.
        let end=try AUProbe();var endOn=midiEvent(256,0x90,67,127)
        let silent=withUnsafePointer(to:&endOn) { end.samples(events:$0) }
        check(silent.allSatisfy { $0==0 } && end.samples().contains { abs($0)>0.00001 })
        end.unit.deallocateRenderResources();try end.unit.allocateRenderResources()
        check(end.samples().allSatisfy { $0==0 },"Reallocation must not leave held voices from the old render lifetime")
        let reset=try AUProbe()
        var delayDoc=FXDocument.initial;delayDoc.nodes[3].settings.enabled=true
        reset.unit.effectStorage.set(try delayDoc.configuration(),document:delayDoc)
        var resetOn=midiEvent(0,0x90,60,127)
        _=withUnsafePointer(to:&resetOn) { reset.samples(events:$0) }
        for _ in 0..<80 { _=reset.samples() }
        reset.unit.reset()
        for _ in 0..<120 { check(reset.samples().allSatisfy { $0==0 },"Host reset must clear held notes and FX tails") }
        print("AU parameters, instance isolation, patch/FX state, invalid-state rejection, automation and public MIDI scheduling passed")
    }
}
