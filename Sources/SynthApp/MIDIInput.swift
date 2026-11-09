import CoreMIDI
import Foundation

/// CoreMIDI callbacks copy packet bytes before returning. Parsing, connection
/// changes and performance ownership are serialized on the main actor, never render.
@MainActor final class MIDIInput {
    var action: ((MIDIAction)->Void)?
    var status: ((Int,OSStatus?)->Void)?
    private var client=MIDIClientRef(),port=MIDIPortRef(),destination=MIDIEndpointRef()
    private var sources=[MIDIEndpointRef:Int](),decoders=[Int:MIDIByteDecoder]()
    private var performance=MIDIPerformanceState()
    private var generation=0,nextToken=1

    func start() {
        guard client==0 else { return }
        generation += 1;let session=generation
        var error=MIDIClientCreateWithBlock("SYNTH/05" as CFString,&client) { [weak self] notification in
            let id=notification.pointee.messageID
            if id == .msgObjectAdded || id == .msgObjectRemoved || id == .msgSetupChanged {
                DispatchQueue.main.async { [weak self] in
                    guard let self,self.generation==session,self.client != 0 else { return }
                    self.refresh()
                }
            }
        }
        guard error==noErr else { fail(error);return }
        error=MIDIInputPortCreateWithBlock(client,"SYNTH/05 Input" as CFString,&port) { [weak self] list,ref in
            let token=Int(bitPattern:ref),bytes=Self.copyPackets(list)
            DispatchQueue.main.async { [weak self] in self?.receive(bytes,token:token,session:session) }
        }
        guard error==noErr else { fail(error);return }
        error=MIDIDestinationCreateWithBlock(client,"SYNTH/05" as CFString,&destination) { [weak self] list,_ in
            let bytes=Self.copyPackets(list)
            DispatchQueue.main.async { [weak self] in self?.receive(bytes,token:0,session:session) }
        }
        guard error==noErr else { fail(error);return }
        refresh()
    }
    func stop() {
        generation += 1 // Invalidates packets queued by the previous port/session.
        sources.removeAll();decoders.removeAll();resetPerformance()
        if port != 0 { MIDIPortDispose(port);port=0 }
        if destination != 0 { MIDIEndpointDispose(destination);destination=0 }
        if client != 0 { MIDIClientDispose(client);client=0 }
        status?(0,nil)
    }
    func resetPerformance() { for event in performance.reset() { action?(event) } }
    private func fail(_ code:OSStatus) { stop();status?(0,code) }
    private func refresh() {
        let available=Set((0..<MIDIGetNumberOfSources()).map { MIDIGetSource($0) }.filter { $0 != 0 })
        for endpoint in Array(sources.keys) where !available.contains(endpoint) {
            guard let token=sources.removeValue(forKey:endpoint) else { continue }
            MIDIPortDisconnectSource(port,endpoint);decoders.removeValue(forKey:token)
            for event in performance.disconnect(token) { action?(event) }
        }
        var error:OSStatus?
        for endpoint in available.sorted() where sources[endpoint]==nil {
            let token=nextToken;nextToken += 1
            let result=MIDIPortConnectSource(port,endpoint,UnsafeMutableRawPointer(bitPattern:token))
            if result==noErr { sources[endpoint]=token } else { error=result }
        }
        status?(sources.count,error)
    }
    private func receive(_ bytes:[UInt8],token:Int,session:Int) {
        guard session==generation,client != 0,token==0 || sources.values.contains(token) else { return }
        var decoder=decoders[token] ?? MIDIByteDecoder()
        for byte in bytes {
            if let message=decoder.consume(byte) {
                for event in performance.consume(message,source:token) { action?(event) }
            }
        }
        decoders[token]=decoder
    }
    nonisolated private static func copyPackets(_ list:UnsafePointer<MIDIPacketList>) -> [UInt8] {
        var bytes=[UInt8]()
        // Traverse the original variable-length list, never a copied packet tuple.
        var packet=UnsafeRawPointer(list).advanced(by:MemoryLayout<MIDIPacketList>.offset(of:\.packet)!).assumingMemoryBound(to:MIDIPacket.self)
        for _ in 0..<list.pointee.numPackets {
            let data=UnsafeRawPointer(packet).advanced(by:MemoryLayout<MIDIPacket>.offset(of:\.data)!).assumingMemoryBound(to:UInt8.self)
            bytes.append(contentsOf:UnsafeBufferPointer(start:data,count:Int(packet.pointee.length)))
            packet=UnsafePointer(MIDIPacketNext(packet))
        }
        return bytes
    }
    deinit {
        if port != 0 { MIDIPortDispose(port) }
        if destination != 0 { MIDIEndpointDispose(destination) }
        if client != 0 { MIDIClientDispose(client) }
    }
}
