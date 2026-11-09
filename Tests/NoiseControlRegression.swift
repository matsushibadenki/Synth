// Concatenate after the audio sources and Rev3Regression.swift.
extension ProphetLikeAudioUnit {
    fileprivate var noiseMixProbe: Float { smoothedWheelMix }
}
func checkNoiseControl() throws {
    for rate: Double in [44100,48000,96000] {
        for sync in [false,true] {
            var p=SynthParameters()
            p.oscSync=sync; p.oscAPulse=true; p.oscBPulse=true
            p.polyModOscB=1; p.polyModToFreqA=true; p.polyModToPWA=true
            p.lfoToOscA=false; p.lfoToPWA=true; p.lfoToPWB=true
            p.modWheel=1; p.wheelSourceMix=0
            let probe=try AudioProbe(p)
            probe.unit.deallocateRenderResources()
            try probe.unit.outputBusses[0].setFormat(AVAudioFormat(standardFormatWithSampleRate:rate,channels:2)!)
            try probe.unit.allocateRenderResources()
            let buffer=AVAudioPCMBuffer(pcmFormat:probe.unit.outputBusses[0].format,frameCapacity:256)!
            func render() {
                precondition(probe.render(&probe.flags,&probe.time,256,0,buffer.mutableAudioBufferList,nil,nil)==noErr)
                probe.time.mSampleTime += 256
                for channel in 0..<2 {
                    for frame in 0..<256 {
                        let value=buffer.floatChannelData![channel][frame]
                        precondition(value.isFinite && abs(value)<=1,"Noise modulation must remain bounded")
                    }
                }
            }
            probe.unit.noteOn(84,velocity:1); render()
            probe.parameters.set { $0.wheelSourceMix=1 }
            render()
            let expected=1-expf(-256/(Float(rate)*0.004))
            precondition(abs(probe.unit.noiseMixProbe-expected)<0.00001,"Noise/LFO blend must use the 4ms time constant")
            for block in 0..<160 {
                if block%20 == 0 {
                    probe.parameters.set {
                        $0.wheelSourceMix=block%40 == 0 ? 0:1
                        $0.oscAPulseWidth=block%40 == 0 ? 0.01:0.99
                        $0.noiseLevel=0.3
                    }
                }
                render()
                precondition((0...1).contains(probe.unit.noiseMixProbe))
            }
            probe.parameters.set { $0.releaseEnabled=false }
            probe.unit.noteOff(84)
            for _ in 0..<40 { render() }
            precondition((0..<256).allSatisfy { abs(buffer.floatChannelData![0][$0])<0.00001 },"Noise routing must not leave a stuck voice")
        }
    }
    var p=SynthParameters(); p.wheelSourceMix=1
    let initial=try AudioProbe(p); _=initial.samples(1)
    precondition(initial.unit.noiseMixProbe == 1,"Initial noise programs must not fade from an unrelated source")
    let restored=Rev3Program(p).applying(to:SynthParameters())!
    precondition(restored.wheelSourceMix == 1 && Rev3Program(p).pots.count == 24)
    print("Noise control: three rates, Sync on/off, deep PWM, blend timing, startup, release and schema passed")
}
try checkNoiseControl()
