// Concatenate after the audio sources and ModulationQualityRegression.swift.
// A repeatable sample-and-hold width source tracks residual error without
// filtering the noise source or claiming that desired noise is an alias.
func heldNoisePWM(_ factor: Int,sync: Bool,local: Bool = false) -> [Float] {
    var seed: UInt32=0x13579BDF,widths=[Float]()
    for _ in 0..<64 {
        seed=1664525 &* seed &+ 1013904223
        widths.append(0.01+Float(seed>>8)/16777215*0.98)
    }
    var phase=0.0,master=0.0,prior: Float?
    var osc=SyncEdgeOscillator(),decimator=VoiceDecimator(factor:factor),result=[Float]()
    for frame in 0..<1024 {
        for _ in 0..<factor {
            let width=widths[(frame/2)%widths.count],widthStep=width-(prior ?? width)
            prior=width
            let step=(sync ? 29.0:9.0)/128/Double(factor),start=phase
            phase += step; master += 3.0/128/Double(factor)
            var fraction: Double?
            if sync && master>=1 { fraction=(master-1)/(3.0/128/Double(factor)); phase=step*fraction! }
            phase -= floor(phase); master -= floor(master)
            let value: Float
            if local {
                value=osc.sample(start:start,step:step,resetFraction:fraction,width:width,saw:false,pulse:true,widthStep:widthStep,widthJump:true)
            } else {
                value=sync ? osc.sample(start:start,step:step,resetFraction:fraction,width:width,saw:false,pulse:true,widthStep:widthStep)
                    : PWMPulse.sample(phase:Float(phase),width:width,step:Float(step),widthStep:widthStep)
            }
            precondition(value.isFinite && abs(value)<=4)
            decimator.push(value)
        }
        let value=decimator.output()
        if frame>=768 { result.append(value) }
    }
    return result
}
func checkHeldNoisePWM() {
    for sync in [false,true] {
        let source=heldNoisePWM(8,sync:sync)
        precondition(source == heldNoisePWM(8,sync:sync),"Held-noise probes must be repeatable")
        let reference=qualitySpectrum(heldNoisePWM(64,sync:sync))
        let error8=spectrumError(qualitySpectrum(source),reference)
        let error16=spectrumError(qualitySpectrum(heldNoisePWM(16,sync:sync)),reference)
        let error32=spectrumError(qualitySpectrum(heldNoisePWM(32,sync:sync)),reference)
        precondition(error8.isFinite && error8>0 && error32<error8,"Record a real residual and verify higher-rate convergence")
        precondition(source.reduce(Float(0)) { $0+$1*$1 }>0.01,"Noise PWM must not silently mute")
        print("Held-noise PWM sync=\(sync): squared spectral error 8x=\(error8), 16x=\(error16), 32x=\(error32), reference 64x")
    }
}
checkHeldNoisePWM()

func checkLocalNoisePWM() {
    for sync in [false,true] {
        let reference=qualitySpectrum(heldNoisePWM(64,sync:sync,local:true))
        let old=spectrumError(qualitySpectrum(heldNoisePWM(8,sync:sync)),reference)
        let local=spectrumError(qualitySpectrum(heldNoisePWM(8,sync:sync,local:true)),reference)
        precondition(local<old*0.1,"Held-width event correction must improve the fixed discontinuous-width probe")
        print("Local held PWM sync=\(sync): old \(old), local \(local), error reduction \((1-local/old)*100)%")
    }
    var history=SyncEdgeOscillator()
    for i in 0..<1000 {
        let output=PWMPulse.heldCorrection(phase:Double(i%100)*2 * .pi/100,step:0.01,baselineStep:0.01,
            width:i%2 == 0 ? 0.01:0.99,widthStep:i%2 == 0 ? -0.98:0.98,mix:0.5,history:&history)
        precondition(output.isFinite && abs(output)<=3)
    }
}
checkLocalNoisePWM()

func checkHeldPulseReuse() {
    var uncached=SyncEdgeOscillator(),cached=SyncEdgeOscillator(),seed: UInt32=91
    var previousWidth: Float=0.5
    for i in 0..<10000 {
        seed=1664525 &* seed &+ 1013904223
        let phase=Double(seed>>8)/16777216*2 * .pi
        seed=1664525 &* seed &+ 1013904223
        let step=Float(seed>>8)/16777216*0.45
        seed=1664525 &* seed &+ 1013904223
        let width=0.01+Float(seed>>8)/16777215*0.98,delta=width-previousWidth
        previousWidth=width
        let mix=Float(i%101)/100
        let original=PWMPulse.sample(phase:Float(phase)/(2 * .pi),width:width,step:step,widthStep:delta)
        let expected=PWMPulse.heldCorrection(phase:phase,step:step,baselineStep:step,width:width,widthStep:delta,mix:mix,history:&uncached)
        let actual=PWMPulse.heldCorrection(phase:phase,step:step,baselineStep:step,width:width,widthStep:delta,mix:mix,history:&cached,originalPulse:original)
        precondition(expected.bitPattern == actual.bitPattern,"Pulse reuse must preserve exact correction output")
    }
    print("Held pulse reuse: 10,000 corrections matched exactly")
}
checkHeldPulseReuse()
