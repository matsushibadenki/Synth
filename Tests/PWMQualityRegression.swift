// Concatenate after the audio sources and ModulationQualityRegression.swift.
func pwmProbe(_ factor: Int,improved: Bool,sync: Bool=false,depth: Double=0.42) -> [Float] {
    var phase=0.0,master=0.0,previousWidth: Float?
    var syncOsc=SyncEdgeOscillator(),decimator=VoiceDecimator(factor:factor),result=[Float]()
    for frame in 0..<1024 {
        for sub in 0..<factor {
            let time=Double(frame)+Double(sub)/Double(factor)
            let width=Float(min(0.99,max(0.01,0.5+depth*sin(2 * Double.pi*31*time/128))))
            let widthStep=width-(previousWidth ?? width); previousWidth=width
            let step=(sync ? 29.0:9.0)/128/Double(factor),start=phase
            phase += step; master += 3.0/128/Double(factor)
            var fraction: Double?
            if sync && master>=1 { fraction=(master-1)/(3.0/128/Double(factor)); phase=step*fraction! }
            master -= floor(master); phase -= floor(phase)
            let sample: Float
            if sync {
                sample=syncOsc.sample(start:start,step:step,resetFraction:fraction,width:width,saw:false,pulse:true,widthStep:improved ? widthStep:0)
            } else {
                sample=PWMPulse.sample(phase:Float(phase),width:width,step:Float(step),widthStep:improved ? widthStep:0)
            }
            decimator.push(sample)
        }
        let output=decimator.output()
        if frame>=768 { result.append(output) }
    }
    return result
}
func checkPWMQuality() {
    for sync in [false,true] {
        let reference=qualitySpectrum(pwmProbe(64,improved:true,sync:sync))
        let old=spectrumError(qualitySpectrum(pwmProbe(8,improved:false,sync:sync)),reference)
        let new=spectrumError(qualitySpectrum(pwmProbe(8,improved:true,sync:sync)),reference)
        print("PWM sync=\(sync): old spectral error \(old), corrected \(new), reduction \((1-new/old)*100)%")
        precondition(new<old*0.9,"Moving-edge correction must improve deep PWM against a higher-rate reference")
    }
    func oldPulse(_ phase: Float,_ width: Float,_ step: Float) -> Float {
        let pw=min(0.99,max(0.01,width)),shifted=(phase-pw+1).truncatingRemainder(dividingBy:1)
        return (phase<pw ? 1:-1)+PWMPulse.blep(phase,step)-PWMPulse.blep(shifted,step)
    }
    for width: Float in [0.01,0.1,0.5,0.9,0.99] {
        for i in 0..<1000 {
            let phase=Float(i)/1000
            precondition(PWMPulse.sample(phase:phase,width:width,step:0.03,widthStep:0) == oldPulse(phase,width,0.03),"Static pulse must remain sample-identical")
            for movement: Float in [-0.98,-0.1,0,0.03,0.1,0.98] {
                let output=PWMPulse.sample(phase:phase,width:width,step:0.03,widthStep:movement)
                precondition(output.isFinite && abs(output)<=3,"Reverse/stationary/clamped edge must remain bounded")
            }
        }
    }
    print("PWM: forward/reversing edges, static identity and bounded extreme widths passed")
}
checkPWMQuality()


extension ProphetLikeAudioUnit {
    fileprivate var pwmHistoryCleared: Bool { voices.allSatisfy { $0.previousWidthA == nil && $0.previousWidthB == nil } }
}
func checkPWMRender() throws {
    for rate: Double in [44100,48000,96000] {
        for sync in [false,true] {
            var p=SynthParameters()
            p.oscSync=sync; p.oscAPulse=true; p.oscBPulse=true
            p.polyModOscB=1; p.polyModToPWA=true
            p.lfoToOscA=false; p.lfoToPWB=true; p.lfoRateHz=20; p.modWheel=1
            let probe=try AudioProbe(p)
            probe.unit.deallocateRenderResources()
            try probe.unit.outputBusses[0].setFormat(AVAudioFormat(standardFormatWithSampleRate:rate,channels:2)!)
            try probe.unit.allocateRenderResources()
            precondition(probe.unit.pwmHistoryCleared,"Rate changes must clear stale width differences")
            let buffer=AVAudioPCMBuffer(pcmFormat:probe.unit.outputBusses[0].format,frameCapacity:256)!
            probe.unit.noteOn(84,velocity:1)
            var energy: Float=0
            for block in 0..<120 {
                if block%20 == 0 { probe.parameters.set { $0.oscAPulseWidth=block%40 == 0 ? 0.01:0.99 } }
                precondition(probe.render(&probe.flags,&probe.time,256,0,buffer.mutableAudioBufferList,nil,nil)==noErr)
                for i in 0..<256 {
                    let left=buffer.floatChannelData![0][i],right=buffer.floatChannelData![1][i]
                    precondition(left.isFinite && right.isFinite && abs(left)<=1 && left == right)
                    energy += left*left
                }
                probe.time.mSampleTime += 256
            }
            precondition(energy>0.01,"Combined PWM routes must reach the actual AU output")
        }
    }
    print("PWM AU: three rates, Poly-Mod A + wheel B, Sync on/off, width extremes and rate reset passed")
}
try checkPWMRender()
