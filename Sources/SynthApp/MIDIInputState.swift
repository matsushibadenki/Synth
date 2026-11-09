import Foundation

/// MIDI 1.0 byte stream; state persists across packets, independently per source.
struct MIDIByteDecoder {
    private var status: UInt8=0,first: UInt8?,systemRemaining=0,sysex=false
    mutating func consume(_ byte: UInt8) -> MIDIMessage? {
        if byte>=0xF8 { return nil } // Realtime bytes never disturb running status.
        if byte>=0x80 {
            first=nil
            if byte>=0xF0 {
                status=0;sysex=byte==0xF0
                systemRemaining=byte==0xF2 ? 2:([0xF1,0xF3].contains(byte) ? 1:0)
            } else { status=byte;sysex=false;systemRemaining=0 }
            return nil
        }
        if sysex { return nil }
        if systemRemaining>0 { systemRemaining -= 1;return nil }
        guard status>=0x80 else { return nil }
        let kind=status & 0xF0,channel=Int(status & 15)
        if kind==0xC0 || kind==0xD0 { return nil } // Consume unsupported one-byte messages.
        guard let a=first else { first=byte;return nil }
        first=nil
        switch kind {
        case 0x80:return .off(channel,Int(a))
        case 0x90:return byte==0 ? .off(channel,Int(a)):.on(channel,Int(a),byte)
        case 0xB0:return .cc(channel,Int(a),byte)
        case 0xE0:return .pitch(channel,Int(a) | Int(byte)<<7)
        default:return nil
        }
    }
}
enum MIDIMessage: Equatable {
    case on(Int,Int,UInt8),off(Int,Int),cc(Int,Int,UInt8),pitch(Int,Int)
    var channel: Int {
        switch self { case let .on(c,_,_),let .off(c,_),let .cc(c,_,_),let .pitch(c,_):return c }
    }
}
enum MIDIAction: Equatable {
    case on(Int,Float),off(Int),pitch(Float),mod(Float)
}
struct MIDIPerformanceState {
    private struct Lane: Hashable { var source:Int,channel:Int }
    private struct Keys { var down=Set<Int>(),sustained=Set<Int>(),pedal=false
        var sounding:Set<Int> { down.union(sustained) }
    }
    private var lanes=[Lane:Keys]()
    private var pitchOwner:Lane?,modOwner:Lane?
    var sounding:Set<Int> { lanes.values.reduce(into:Set<Int>()) { $0.formUnion($1.sounding) } }
    mutating func consume(_ message:MIDIMessage,source:Int) -> [MIDIAction] {
        let lane=Lane(source:source,channel:message.channel),before=sounding
        var keys=lanes[lane] ?? Keys(),actions=[MIDIAction]()
        switch message {
        case let .on(_,note,velocity):
            if !before.contains(note) || keys.sounding.contains(note) { actions.append(.on(note,Float(velocity)/127)) }
            keys.down.insert(note);keys.sustained.remove(note)
        case let .off(_,note):
            if keys.down.remove(note) != nil && keys.pedal { keys.sustained.insert(note) }
        case let .pitch(_,value):
            pitchOwner=lane;actions.append(.pitch(value<8192 ? Float(value-8192)/8192:Float(value-8192)/8191))
        case let .cc(_,controller,value):
            switch controller {
            case 1:modOwner=lane;actions.append(.mod(Float(value)/127))
            case 64:keys.pedal=value>=64;if !keys.pedal { keys.sustained.removeAll() }
            case 120:keys=Keys() // Clear sustain and release this channel's notes.
            case 123:
                if keys.pedal { keys.sustained.formUnion(keys.down) }
                keys.down.removeAll()
            case 121:
                keys.pedal=false;keys.sustained.removeAll()
                if pitchOwner==lane { pitchOwner=nil;actions.append(.pitch(0)) }
                if modOwner==lane { modOwner=nil;actions.append(.mod(0)) }
            default:break
            }
        }
        // Keep only lanes with held notes or pedal; controller ownership is separate.
        if keys.sounding.isEmpty && !keys.pedal { lanes.removeValue(forKey:lane) } else { lanes[lane]=keys }
        actions += before.subtracting(sounding).sorted().map { .off($0) }
        return actions
    }
    mutating func disconnect(_ source:Int) -> [MIDIAction] {
        let before=sounding
        lanes=lanes.filter { $0.key.source != source }
        var result=before.subtracting(sounding).sorted().map { MIDIAction.off($0) }
        if pitchOwner?.source==source { pitchOwner=nil;result.append(.pitch(0)) }
        if modOwner?.source==source { modOwner=nil;result.append(.mod(0)) }
        return result
    }
    mutating func reset() -> [MIDIAction] {
        var result=sounding.sorted().map { MIDIAction.off($0) }
        if pitchOwner != nil { result.append(.pitch(0)) }
        if modOwner != nil { result.append(.mod(0)) }
        self=Self();return result
    }
}
