// Concatenate this file after SynthEngine.swift (private access stays in-file),
// then compile with other production sources except SynthApp/SynthEngine.
// Offline AU only: no output device or MIDI endpoint is started.
import Foundation
extension SynthEngine {
    @MainActor fileprivate func checkMIDIOwnership() throws {
        sharedParams.set { $0.releaseEnabled=false }
        let unit=try ProphetLikeAudioUnit(componentDescription:componentDescription)
        try unit.outputBusses[0].setFormat(AVAudioFormat(standardFormatWithSampleRate:48000,channels:2)!)
        try unit.allocateRenderResources();defer { unit.deallocateRenderResources();audioUnit=nil;isRunning=false }
        audioUnit=unit;isRunning=true
        let buffer=AVAudioPCMBuffer(pcmFormat:unit.outputBusses[0].format,frameCapacity:256)!
        let render=unit.internalRenderBlock
        var flags=AudioUnitRenderActionFlags(),time=AudioTimeStamp()
        func tail(_ blocks:Int)->Float {
            for _ in 0..<blocks {
                precondition(render(&flags,&time,256,0,buffer.mutableAudioBufferList,nil,nil)==noErr)
                time.mSampleTime += 256
            }
            return (0..<256).reduce(Float(0)) { max($0,abs(buffer.floatChannelData![0][$1])) }
        }
        receiveMIDI(.on(60,1));midiNote=72
        precondition(heldNotes.isEmpty,"Changing current key must not create local ownership of a MIDI-only note")
        playNote(60);releaseNote(60)
        precondition(gateOn && tail(30)>0.001,"Local release must preserve MIDI note")
        receiveMIDI(.off(60));precondition(!gateOn && tail(60)<0.00001)
        playNote(64);receiveMIDI(.on(64,1));receiveMIDI(.off(64))
        precondition(gateOn && tail(30)>0.001,"MIDI release must preserve local note")
        releaseNote(64);precondition(!gateOn && tail(60)<0.00001)
        receiveMIDI(.pitch(-1));receiveMIDI(.mod(1))
        precondition(sharedParams.snapshot().pitchWheel == -1 && sharedParams.snapshot().modWheel == 1)
        precondition(midiControlEvent == .mod(1))
        receiveMIDI(.on(67,1));playNote(69);noteOffCurrent()
        precondition(!gateOn && tail(60)<0.00001)
        receiveMIDI(.on(71,1));stop()
        precondition(!gateOn && midiNotes.isEmpty && heldNotes.isEmpty && audioUnit==nil)
        print("MIDI engine: local/MIDI overlapping ownership, offline releases and wheel publication passed")
    }
}
@main struct MIDIEngineRegression {
    @MainActor static func main() throws { try SynthEngine().checkMIDIOwnership() }
}
