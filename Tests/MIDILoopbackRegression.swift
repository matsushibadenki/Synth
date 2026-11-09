// swiftc -O Sources/SynthApp/MIDIInputState.swift Sources/SynthApp/MIDIInput.swift Tests/MIDILoopbackRegression.swift -o /tmp/synth-midi-loopback
// No audio engine is started. CoreMIDI virtual endpoints exist only during this test.
import CoreMIDI
import Foundation
@main struct MIDILoopbackRegression {
    @MainActor static func main() {
        func pump(until condition:()->Bool) {
            let end=Date().addingTimeInterval(3)
            while !condition() && Date()<end { RunLoop.main.run(until:Date().addingTimeInterval(0.01)) }
            precondition(condition(),"Timed out waiting for CoreMIDI")
        }
        var client=MIDIClientRef(),source=MIDIEndpointRef(),out=MIDIPortRef()
        precondition(MIDIClientCreateWithBlock("SYNTH05 MIDI Test" as CFString,&client,nil)==noErr)
        defer { MIDIClientDispose(client) }
        precondition(MIDISourceCreate(client,"SYNTH05 Test Source" as CFString,&source)==noErr)
        defer { if source != 0 { MIDIEndpointDispose(source) } }
        let input=MIDIInput();var actions=[MIDIAction](),count=0,error:OSStatus?
        input.action={actions.append($0)};input.status={count=$0;error=$1}
        input.start();defer { input.stop() }
        precondition(error==nil && count>=1)
        func send(_ packets:[[UInt8]],destination:MIDIEndpointRef?=nil) {
            let storage=UnsafeMutableRawPointer.allocate(byteCount:4096,alignment:16)
            defer { storage.deallocate() }
            let list=storage.bindMemory(to:MIDIPacketList.self,capacity:1)
            var packet=MIDIPacketListInit(list)
            for bytes in packets {
                packet=bytes.withUnsafeBufferPointer { MIDIPacketListAdd(list,4096,packet,0,$0.count,$0.baseAddress!) }
            }
            let status=destination.map { MIDISend(out,$0,list) } ?? MIDIReceived(source,list)
            precondition(status==noErr)
        }
        send([[0x90,60],[127,0xF8,0xB0,64,127],[0x80,60,0]])
        pump { actions.contains(.on(60,1)) }
        precondition(!actions.contains(.off(60)),"Sustain spans packet boundaries")
        send([[0xB0,64,0]])
        pump { actions.contains(.off(60)) }
        actions.removeAll()
        // A packet longer than MIDIPacket.data's inline 256-byte tuple followed
        // by another packet catches accidental traversal of copied packet values.
        send([[0xF0]+Array(repeating:UInt8(1),count:300)+[0xF7],[0x90,62,127,0x80,62,0]])
        pump { actions.contains(.off(62)) };precondition(actions.contains(.on(62,1)))
        actions.removeAll();send([[0x90,64,127]])
        pump { actions.contains(.on(64,1)) }
        precondition(MIDIEndpointDispose(source)==noErr);source=0
        pump { actions.contains(.off(64)) }
        let previousCount=count
        precondition(MIDISourceCreate(client,"SYNTH05 Hotplug Source" as CFString,&source)==noErr)
        pump { count>previousCount }
        actions.removeAll();send([[0xE0,127,127,0xB0,1,127]])
        pump { actions.contains(.pitch(1)) && actions.contains(.mod(1)) }
        var destination=MIDIEndpointRef()
        for index in 0..<MIDIGetNumberOfDestinations() {
            let endpoint=MIDIGetDestination(index);var name:Unmanaged<CFString>?
            if MIDIObjectGetStringProperty(endpoint,kMIDIPropertyName,&name)==noErr,
               let name=name?.takeRetainedValue(),name as String=="SYNTH/05" { destination=endpoint;break }
        }
        precondition(destination != 0)
        precondition(MIDIOutputPortCreate(client,"SYNTH05 Test Out" as CFString,&out)==noErr)
        defer { MIDIPortDispose(out) }
        actions.removeAll();send([[0x91,67,127,0x81,67,0]],destination:destination)
        pump { actions.contains(.off(67)) };precondition(actions.contains(.on(67,1)))
        input.stop();actions.removeAll();send([[0x90,70,127]])
        RunLoop.main.run(until:Date().addingTimeInterval(0.1));precondition(actions.isEmpty)
        input.start();pump { count>=1 };precondition(error==nil)
        actions.removeAll();send([[70,127]])
        RunLoop.main.run(until:Date().addingTimeInterval(0.1));precondition(actions.isEmpty,"Restart must clear running status")
        send([[0x90,70,127]]);pump { actions.contains(.on(70,1)) }
        input.resetPerformance();precondition(actions.contains(.off(70)))
        print("CoreMIDI loopback: multi/long packets, virtual destination, hotplug, disconnect release, controllers, stop/restart passed (no audio)")
    }
}
