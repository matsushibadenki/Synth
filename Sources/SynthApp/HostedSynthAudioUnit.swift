import AVFoundation
import AudioToolbox
import CoreMIDI

/// Stable AU addresses: knobs 0...25, switches 100...121, wheels 200/201.
/// Address order is independent from parameter-tree grouping and saved programs.
enum SynthAUControls {
    static let addresses:[AUParameterAddress] = (0..<26).map { UInt64($0) }+(100..<122).map { UInt64($0) }+[200,201]
    static func index(_ address:AUParameterAddress)->Int? {
        if address<26 { return Int(address) }
        if (100..<122).contains(address) { return Int(address)-100+26 }
        if address==200 || address==201 { return Int(address)-200+48 }
        return nil
    }
    static func read(_ address:AUParameterAddress,_ p:SynthParameters)->Float {
        if address<26 { return p[keyPath:Rev3.knobs[Int(address)].key] }
        if (100..<122).contains(address) { return p[keyPath:Rev3.switches[Int(address)-100].key] ? 1:0 }
        return address==200 ? p.pitchWheel:p.modWheel
    }
    static func write(_ address:AUParameterAddress,_ value:Float,_ p:inout SynthParameters) {
        guard value.isFinite else { return }
        if address<26 { let k=Rev3.knobs[Int(address)];p[keyPath:k.key]=k.clamped(value) }
        else if (100..<122).contains(address) { p[keyPath:Rev3.switches[Int(address)-100].key]=value>=0.5 }
        else if address==200 { p.pitchWheel=min(1,max(-1,value)) }
        else if address==201 { p.modWheel=min(1,max(0,value)) }
    }
}

final class HostedSynthAudioUnit: ProphetLikeAudioUnit {
    private var tree:AUParameterTree!
    private var scratch:AVAudioPCMBuffer?
    private let segment=AudioBufferList.allocate(maximumBuffers:2)
    private var current=SynthParameters(),dirty:UInt64=0
    private var decoder=MIDIByteDecoder()
    // 16 channels x 128 keys, and per-key aggregate ownership. Fixed before render.
    private var keys=[UInt8](repeating:0,count:2048),counts=[UInt8](repeating:0,count:128)
    private var pedals=[Bool](repeating:false,count:16)
    override init(componentDescription:AudioComponentDescription,options:AudioComponentInstantiationOptions = []) throws {
        try super.init(componentDescription:componentDescription,options:options,
                       parameters:SharedSynthParameters(),effects:SharedEffects())
        _ = SynthAUControls.addresses // Initialize metadata outside render.
        let flags:AudioUnitParameterOptions=[.flag_IsReadable,.flag_IsWritable]
        var children=[AUParameterNode]()
        for (i,k) in Rev3.knobs.enumerated() {
            children.append(AUParameterTree.createParameter(withIdentifier:k.id,name:k.names[0],address:UInt64(i),
                min:k.range.lowerBound,max:k.range.upperBound,unit:.generic,unitName:nil,flags:flags,valueStrings:nil,dependentParameters:nil))
        }
        for (i,k) in Rev3.switches.enumerated() {
            children.append(AUParameterTree.createParameter(withIdentifier:k.id,name:k.names[0],address:UInt64(100+i),
                min:0,max:1,unit:.boolean,unitName:nil,flags:flags,valueStrings:nil,dependentParameters:nil))
        }
        for (id,name,address,minimum) in [("pitchWheel","Pitch wheel",200,-1 as Float),("modWheel","Modulation wheel",201,0)] {
            children.append(AUParameterTree.createParameter(withIdentifier:id,name:name,address:UInt64(address),min:minimum,max:1,
                unit:.generic,unitName:nil,flags:flags,valueStrings:nil,dependentParameters:nil))
        }
        tree=AUParameterTree.createTree(withChildren:children)
        tree.implementorValueObserver = { [weak self] parameter,value in
            self?.parameterStorage.set { SynthAUControls.write(parameter.address,value,&$0) }
        }
        tree.implementorValueProvider = { [weak self] parameter in
            guard let self else { return 0 }
            return SynthAUControls.read(parameter.address,self.parameterStorage.snapshot())
        }
    }
    deinit { segment.unsafeMutablePointer.deallocate() }
    override var parameterTree:AUParameterTree? { get { tree } set {} }
    override var virtualMIDICableCount:Int { 1 }
    override var channelCapabilities:[NSNumber]? { [0,2] }
    override var tailTime:TimeInterval {
        let p=parameterStorage.snapshot()
        let release=p.releaseEnabled ? Double(p.envBRelease)*1.2:0.01
        return max(release,effectStorage.documentSnapshot().nodes.contains { (1...6).contains($0.id) && $0.settings.enabled } ? 60:0)
    }

    /// Called by the existing UI, outside render, so host automation observers see edits.
    func applyUIParameters(_ value:SynthParameters,previousUI:SynthParameters? = nil) {
        let previous=previousUI ?? parameterStorage.snapshot()
        parameterStorage.set { latest in
            for address in SynthAUControls.addresses where SynthAUControls.read(address,previous) != SynthAUControls.read(address,value) {
                SynthAUControls.write(address,SynthAUControls.read(address,value),&latest)
            }
            if previous.expression != value.expression { latest.expression=value.expression }
            if previous.referenceA440 != value.referenceA440 { latest.referenceA440=value.referenceA440 }
            if previous.autoTuneTrigger != value.autoTuneTrigger { latest.autoTuneTrigger &+= 1 }
        }
        for address in SynthAUControls.addresses where SynthAUControls.read(address,previous) != SynthAUControls.read(address,value) {
            tree.parameter(withAddress:address)?.setValue(SynthAUControls.read(address,value),originator:nil)
        }
    }
    override var fullState:[String:Any]? {
        get {
            var p=parameterStorage.snapshot();p.autoTuneTrigger=0;p.referenceA440=false
            guard let parameters=try? JSONEncoder().encode(p),let effects=try? JSONEncoder().encode(effectStorage.documentSnapshot()) else { return nil }
            var state=super.fullState ?? [:]
            state["synth05.version"]=1;state["synth05.parameters"]=parameters;state["synth05.effects"]=effects
            return state
        }
        set {
            guard let state=newValue,state["synth05.version"] as? Int==1,
                  let data=state["synth05.parameters"] as? Data,var p=try? JSONDecoder().decode(SynthParameters.self,from:data),
                  let fxData=state["synth05.effects"] as? Data,var doc=try? JSONDecoder().decode(FXDocument.self,from:fxData) else { return }
            // Decode and validate everything before publishing any part of the state.
            for k in Rev3.knobs { p[keyPath:k.key]=k.clamped(p[keyPath:k.key]) }
            p.pitchWheel=ExpressionParameters.unit((p.pitchWheel+1)/2)*2-1;p.modWheel=ExpressionParameters.unit(p.modWheel)
            p.autoTuneTrigger=0;p.referenceA440=false
            for i in doc.nodes.indices { doc.nodes[i].settings.loopSerial=0;doc.nodes[i].settings.loopAction=0 }
            guard let config=try? doc.configuration() else { return }
            willChangeValue(forKey:"allParameterValues")
            parameterStorage.set { $0=p };effectStorage.set(config,document:doc)
            didChangeValue(forKey:"allParameterValues")
        }
    }
    override var fullStateForDocument:[String:Any]? { get { fullState } set { fullState=newValue } }
    override func allocateRenderResources() throws {
        let format=outputBusses[0].format
        guard format.channelCount==2,format.commonFormat == .pcmFormatFloat32,!format.isInterleaved,
              maximumFramesToRender>0,maximumFramesToRender<=65536 else {
            throw NSError(domain:NSOSStatusErrorDomain,code:Int(kAudioUnitErr_FormatNotSupported))
        }
        try super.allocateRenderResources()
        resetHostPerformance()
        scratch=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:maximumFramesToRender)!
        current=parameterStorage.snapshot();dirty=0;decoder=MIDIByteDecoder()
        for i in keys.indices { keys[i]=0 };for i in counts.indices { counts[i]=0 };for i in pedals.indices { pedals[i]=false }
    }
    override func reset() {
        super.reset()
        resetHostPerformance(clearQueue:false)
        for i in keys.indices { keys[i]=0 };for i in counts.indices { counts[i]=0 };for i in pedals.indices { pedals[i]=false }
        decoder=MIDIByteDecoder()
    }
    override func deallocateRenderResources() { scratch=nil;super.deallocateRenderResources() }
    private func copyPending(into p:inout SynthParameters) {
        for (i,address) in SynthAUControls.addresses.enumerated() where dirty & (UInt64(1)<<i) != 0 {
            SynthAUControls.write(address,SynthAUControls.read(address,current),&p)
        }
    }
    private func edit(_ address:AUParameterAddress,_ value:Float) {
        guard let i=SynthAUControls.index(address),value.isFinite else { return }
        SynthAUControls.write(address,value,&current);dirty |= UInt64(1)<<i
    }
    private func release(_ channel:Int,_ note:Int,force:Bool=false) {
        let i=channel*128+note
        guard keys[i] != 0 else { return }
        if !force && pedals[channel] { keys[i]=2;return }
        keys[i]=0;counts[note] -= 1
        if counts[note]==0 { hostNoteOff(note,parameters:current) }
    }
    private func midi(_ message:MIDIMessage) {
        switch message {
        case let .on(channel,note,velocity):
            let i=channel*128+note,existing=keys[i] != 0
            if !existing { counts[note] += 1 };keys[i]=1
            if existing || counts[note]==1 { hostNoteOn(note,velocity:Float(velocity)/127,parameters:current) }
        case let .off(channel,note):if keys[channel*128+note]==1 { release(channel,note) }
        case let .pitch(_,value):edit(200,value<8192 ? Float(value-8192)/8192:Float(value-8192)/8191)
        case let .cc(channel,control,value):
            switch control {
            case 1:edit(201,Float(value)/127)
            case 64:
                pedals[channel]=value>=64
                if !pedals[channel] { for note in 0..<128 where keys[channel*128+note]==2 { release(channel,note,force:true) } }
            case 120:pedals[channel]=false;for note in 0..<128 { release(channel,note,force:true) }
            case 123:for note in 0..<128 where keys[channel*128+note]==1 { release(channel,note) }
            case 121:
                pedals[channel]=false;for note in 0..<128 where keys[channel*128+note]==2 { release(channel,note,force:true) }
                edit(200,0);edit(201,0)
            default:break
            }
        }
    }
    private func event(_ event:UnsafePointer<AURenderEvent>) {
        switch event.pointee.head.eventType {
        case .MIDI:
            let m=event.pointee.MIDI
            guard m.cable==0,m.length<=3 else { return }
            var data=m.data
            withUnsafeBytes(of:&data) { bytes in
                for i in 0..<Int(m.length) { if let message=decoder.consume(bytes[i]) { midi(message) } }
            }
        case .parameter,.parameterRamp:edit(event.pointee.parameter.parameterAddress,event.pointee.parameter.value)
        default:break
        }
    }
    override var internalRenderBlock:AUInternalRenderBlock {
        let core=super.internalRenderBlock
        return { [weak self] flags,timestamp,frames,bus,output,events,_ in
            guard let self,let scratch=self.scratch else { return kAudioUnitErr_Uninitialized }
            guard bus==0 else { return kAudioUnitErr_InvalidElement }
            guard frames<=self.maximumFramesToRender else { return kAudioUnitErr_TooManyFramesToProcess }
            let buffers=UnsafeMutableAudioBufferListPointer(output)
            guard buffers.count==2 else { return kAudioUnitErr_FormatNotSupported }
            for c in 0..<2 {
                if buffers[c].mData==nil { buffers[c].mData=UnsafeMutableRawPointer(scratch.floatChannelData![c]) }
                buffers[c].mDataByteSize=frames*4;buffers[c].mNumberChannels=1
            }
            if var latest=self.parameterStorage.trySnapshot() { self.copyPending(into:&latest);self.current=latest }
            var cursor=events,offset:UInt32=0
            let start=Int64(timestamp.pointee.mSampleTime)
            while offset<frames || cursor != nil {
                let next:UInt32
                if let event=cursor {
                    let time=event.pointee.head.eventSampleTime
                    next=time==AUEventSampleTimeImmediate ? offset:UInt32(max(Int64(offset),min(Int64(frames),time-start)))
                } else { next=frames }
                if next>offset {
                    for c in 0..<2 { self.segment[c]=AudioBuffer(mNumberChannels:1,mDataByteSize:(next-offset)*4,
                        mData:buffers[c].mData!.advanced(by:Int(offset)*4)) }
                    var time=timestamp.pointee;time.mSampleTime += Double(offset)
                    self.renderParameterOverride=self.current
                    let status=core(flags,&time,next-offset,0,self.segment.unsafeMutablePointer,nil,nil)
                    if status != noErr { self.renderParameterOverride=nil;return status }
                    offset=next
                }
                if let event=cursor { self.event(event);cursor=event.pointee.head.next.map { UnsafePointer($0) } }
                else { break }
            }
            self.renderParameterOverride=nil
            if self.dirty != 0,self.parameterStorage.trySet({ self.copyPending(into:&$0) }) { self.dirty=0 }
            return noErr
        }
    }
}
