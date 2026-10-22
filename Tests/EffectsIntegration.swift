import AVFoundation
import AudioToolbox

@main struct EffectsIntegration {
    static func main() throws {
        let parameters=SharedSynthParameters(), shared=SharedEffects()
        ProphetLikeAudioUnit.sharedParameters=parameters; ProphetLikeAudioUnit.sharedEffects=shared
        let unit=try ProphetLikeAudioUnit(componentDescription:AudioComponentDescription(componentType:kAudioUnitType_Generator,componentSubType:0x50723535,componentManufacturer:0x53796E74,componentFlags:0,componentFlagsMask:0))
        try unit.allocateRenderResources()
        defer { unit.deallocateRenderResources() }
        let buffer=AVAudioPCMBuffer(pcmFormat:unit.outputBusses[0].format,frameCapacity:256)!
        let render=unit.internalRenderBlock
        var flags=AudioUnitRenderActionFlags(), timestamp=AudioTimeStamp()
        func block() throws -> SIMD2<Float> {
            precondition(render(&flags,&timestamp,256,0,buffer.mutableAudioBufferList,nil,nil) == noErr)
            var energy=SIMD2<Float>.zero
            for i in 0..<256 {
                let l=buffer.floatChannelData![0][i], r=buffer.floatChannelData![1][i]
                precondition(l.isFinite && r.isFinite)
                energy += SIMD2(l*l,r*r)
            }
            timestamp.mSampleTime += 256
            return energy
        }
        unit.noteOn(60,velocity:1)
        var dry: Float=0
        for _ in 0..<40 { dry += try block().x }
        precondition(dry>0.01,"AU generates sound")
        var document=FXDocument.initial
        document.nodes[2].settings.enabled=true
        document.nodes[2].settings.values[4]=1
        shared.set(try document.configuration())
        var difference: Float=0
        for _ in 0..<200 {
            _=try block()
            for i in 0..<256 { difference += abs(buffer.floatChannelData![0][i]-buffer.floatChannelData![1][i]) }
        }
        precondition(difference>0.01,"Effects graph must process the AU output into stereo")
        parameters.set { $0.masterVolume=0 }
        let muted=try block()
        precondition(muted == .zero,"Master volume must mute effect tails and loops")
        parameters.set { $0.masterVolume=1 }
        document.edges=[]; shared.set(try document.configuration())
        for _ in 0..<5 { _=try block() }
        let disconnected=try block()
        precondition(disconnected == .zero,"Disconnecting OUT must silence the AU")
        print("AU effects integration: routed stereo / post-FX master mute / output disconnect passed")
    }
}
