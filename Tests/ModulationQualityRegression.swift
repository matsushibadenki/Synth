// Concatenate after the audio sources; offline quality probes, no audio device.
func qualitySpectrum(_ samples: [Float]) -> [Double] {
    let count=samples.count
    return (0...count/2).map { bin in
        var re=0.0,im=0.0
        for i in samples.indices {
            let angle=2 * Double.pi*Double(bin*i)/Double(count)
            re += Double(samples[i])*cos(angle); im += Double(samples[i])*sin(angle)
        }
        return hypot(re,im)/Double(count)
    }
}
func spectrumError(_ a: [Double],_ b: [Double]) -> Double {
    zip(a,b).reduce(0) { $0+pow($1.0-$1.1,2) }
}
func syncProbe(_ factor: Int,corrected: Bool,saw: Bool=true,pulse: Bool=false) -> [Float] {
    var phaseA=0.0,phaseB=0.0,oscillator=SyncEdgeOscillator(),decimator=VoiceDecimator(factor:factor)
    var result=[Float]()
    for frame in 0..<1024 {
        for _ in 0..<factor {
            let stepA=29.0/128/Double(factor),stepB=3.0/128/Double(factor),start=phaseA
            phaseA += stepA; phaseB += stepB
            var fraction: Double?
            if phaseB>=1 { fraction=(phaseB-1)/stepB; phaseA=stepA*fraction!; phaseB -= 1 }
            phaseA -= floor(phaseA)
            let raw=(saw ? Float(phaseA*2-1):0)+(pulse ? (phaseA<0.37 ? Float(1):Float(-1)):0)
            let value=oscillator.sample(start:start,step:stepA,resetFraction:fraction,width:0.37,saw:saw,pulse:pulse)
            decimator.push(corrected ? value:raw)
        }
        let output=decimator.output()
        if frame>=768 { result.append(output) }
    }
    return result
}
func polyProbe(_ factor: Int) -> [Float] {
    var phase=0.0,decimator=VoiceDecimator(factor:factor),result=[Float]()
    for frame in 0..<1024 {
        for sub in 0..<factor {
            let time=(Double(frame)+Double(sub)/Double(factor))
            let mod=sin(2 * Double.pi*11*time/128)
            phase += 0.04*pow(2,mod*4)/Double(factor)
            phase -= floor(phase)
            decimator.push(Float(2*phase-1))
        }
        let output=decimator.output()
        if frame>=768 { result.append(output) }
    }
    return result
}
func checkModulationQuality() {
    setbuf(stdout,nil)
    let reference=qualitySpectrum(syncProbe(64,corrected:false))
    let raw=spectrumError(qualitySpectrum(syncProbe(4,corrected:false)),reference)
    let corrected=spectrumError(qualitySpectrum(syncProbe(4,corrected:true)),reference)
    print("Sync spectral error raw \(raw), corrected \(corrected)")
    precondition(corrected<raw*0.8,"Fractional sync edge correction must improve the reference error")
    for saw in [false,true] {
        let ref=qualitySpectrum(syncProbe(64,corrected:false,saw:saw,pulse:true))
        let old=spectrumError(qualitySpectrum(syncProbe(4,corrected:false,saw:saw,pulse:true)),ref)
        let new=spectrumError(qualitySpectrum(syncProbe(4,corrected:true,saw:saw,pulse:true)),ref)
        print("Sync pulse / saw=\(saw): raw \(old), corrected \(new)")
        precondition(new<old*0.8,"Sync pulse and combined waves must improve")
    }
    let lineConstant=FXStereoLine(capacity:100)
    for _ in 0..<200 { lineConstant.write(SIMD2(0.2,-0.4)) }
    for speed: Float in [0.5,1,1.25,2,5,12,30,48] {
        for fraction: Float in [0,0.1,0.5,0.99] {
            let sample=lineConstant.readBandlimited(30+fraction,speed:speed)
            precondition(abs(sample.x-0.2)<0.00001 && abs(sample.y+0.4)<0.00001,"Kernel phase/bank interpolation must retain DC")
        }
    }
    let polyReference=qualitySpectrum(polyProbe(64))
    let old=spectrumError(qualitySpectrum(polyProbe(4)),polyReference)
    let new=spectrumError(qualitySpectrum(polyProbe(8)),polyReference)
    print("Poly-Mod rate probe spectral error 4x \(old), 8x \(new)")
    precondition(new<old*0.8,"Higher internal rate must improve deep exponential modulation")
    for sr: Float in [44100,48000,96000] {
        let line=FXStereoLine(capacity:32768)
        // A constant 2x read rate makes alias and wanted bins unambiguous.
        for i in 0..<32768 { line.write(SIMD2(sinf(2 * .pi*0.4*Float(i)),sinf(2 * .pi*0.05*Float(i)))) }
        var original=[Float](),improved=[Float](),pass=[Float]()
        for i in 0..<7000 {
            line.write(SIMD2(sinf(2 * .pi*0.4*Float(i+32768)),sinf(2 * .pi*0.05*Float(i+32768))))
            let delay=Float(16000-i)
            let old=line.read(delay),new=line.readBandlimited(delay,speed:2)
            if i>=6000 { original.append(old.x); improved.append(new.x); pass.append(new.y) }
        }
        func rms(_ x:[Float])->Double { sqrt(x.reduce(0) { $0+Double($1*$1) }/Double(x.count)) }
        let reduction=20*log10(rms(original)/rms(improved))
        print("Delay \(sr) Hz normalized 2x: alias reduction \(reduction) dB")
        precondition(reduction>30 && rms(pass)>0.6,"Reject compressed high band, retain low band")
    }
}
checkModulationQuality()
