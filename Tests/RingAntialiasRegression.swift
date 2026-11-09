import Foundation

@main struct RingAntialiasRegression {
    static func amplitude(_ signal: [Float],_ frequency: Double) -> Double {
        var real=0.0,imaginary=0.0
        for (i,value) in signal.enumerated() {
            let angle=2 * Double.pi*frequency*Double(i)
            real += Double(value)*cos(angle); imaginary += Double(value)*sin(angle)
        }
        return 2*hypot(real,imaginary)/Double(signal.count)
    }
    static func main() {
        for rate: Float in [44100,48000,96000] {
            for driven in [false,true] {
                let processor=FXRingOversampler()
                let inputFrequency: Float=driven ? 0.17:0.42
                let carrierFrequency: Float=driven ? 0.06:0.16
                let alias: Double=driven ? 0.43:0.42
                let drive: Float=driven ? 8:1, level: Float=driven ? 0.8:0.1
                var phase: Float=0, oldPhase: Float=0
                var actual=[Float](), reference=[Float]()
                for i in 0..<18000 {
                    let input=sinf(2 * .pi*inputFrequency*Float(i))*level
                    let output=processor.process(SIMD2(input,0),carrier:&phase,step:carrierFrequency,drive:drive)
                    oldPhase += carrierFrequency; oldPhase -= floorf(oldPhase)
                    let old=tanhf(input*drive)/tanhf(drive)*sinf(oldPhase*2 * .pi)
                    precondition(output.x.isFinite && output.y == 0,"Stereo separation / bounded output")
                    if i>=2000 { actual.append(output.x); reference.append(old) }
                }
                let oldAlias=amplitude(reference,alias), newAlias=amplitude(actual,alias)
                let improvement=20*log10(oldAlias/max(1e-12,newAlias))
                precondition(improvement>20,"Alias rejection must improve by at least 20dB")
                precondition(amplitude(actual,Double(inputFrequency-carrierFrequency))>0.02,"Keep the musical sideband")
                print(String(format:"%.0f Hz %@: alias reduction %.1f dB",rate,driven ? "drive":"carrier",improvement))
            }
        }
        let impulse=FXRingOversampler()
        var phase: Float=0.25, peak: Float=0, peakIndex=0
        for i in 0..<100 {
            let sample=impulse.process(SIMD2(repeating:i == 0 ? 0.0001:0),carrier:&phase,step:0,drive:1)
            if abs(sample.x)>peak { peak=abs(sample.x); peakIndex=i }
            precondition(abs(impulse.alignedDry.x-(i == FXRingOversampler.latency ? 0.0001:0))<1e-8)
        }
        precondition(peakIndex == FXRingOversampler.latency,"Dry and wet impulse peaks must align")
        var settings=FXSettings(.ring)
        settings.enabled=true; settings.values[4]=0
        let ring=FXProcessor(kind:.ring,sampleRate:48000)
        ring.configure(settings)
        for i in 0..<12000 {
            let input=SIMD2<Float>(sinf(Float(i)*0.03)*0.3,cosf(Float(i)*0.07)*0.2)
            let output=ring.process(input)
            if i>10000 {
                let aligned=SIMD2<Float>(sinf(Float(i-24)*0.03)*0.3,cosf(Float(i-24)*0.07)*0.2)
                precondition(abs(output.x-aligned.x)<0.0001 && abs(output.y-aligned.y)<0.0001,"Engaged dry path latency / stereo")
            }
        }
        settings.enabled=false; ring.configure(settings)
        for _ in 0..<12000 { _=ring.process(SIMD2(0.2,-0.3)) }
        precondition(ring.process(SIMD2(0.17,-0.27)) == SIMD2(0.17,-0.27),"Bypass must return to exact undelayed samples")
        print("Ring AA: spectral rejection, wanted sideband, channel separation and 24-sample alignment passed")
    }
}
