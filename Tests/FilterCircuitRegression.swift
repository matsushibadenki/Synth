// Concatenate after Rev3Parameters, EffectsGraph, EffectsDSP and ProphetCore.
// This checks the circuit equations and acoustic behavior, not solver steps.
extension CurtisFilter {
    fileprivate var circuitCapacitors: SIMD4<Float> { state }
}
func checkCircuitResidual() {
    var normal: Float=0, extreme: Float=0
    for sr: Float in [88200,192000,384000] {
        for cutoffRatio: Float in [0.0003,0.01,0.1,0.4] {
            for resonance: Float in [0,0.7,1,1.2] {
                var filter=CurtisFilter()
                let k=min(4.5,resonance*4.4)
                for n in 0..<2048 {
                    let ratio=cutoffRatio*(n%257<100 ? 0.1:1)
                    let cutoff=max(5,sr*ratio),g=tanf(.pi*cutoff/sr)
                    let input:Float=n%513 == 0 ? 8 : 2*sinf(Float(n)*0.09)
                    let before=filter.circuitCapacitors
                    let output=filter.process(input,cutoff:cutoff,resonance:resonance,sampleRate:sr)
                    precondition(output.isFinite && abs(output)<4,"Circuit must remain bounded during overload and high resonance")
                    let y=(before+filter.circuitCapacitors)*0.5
                    let v=SIMD4(AnalogSignalPath.mixer(input)-k*y.w,y.x,y.y,y.z)-y
                    let current=v/(1+1.96*v*v).squareRoot()
                    let r=y-before-g*current
                    let error=max(max(abs(r.x),abs(r.y)),max(abs(r.z),abs(r.w)))
                    if cutoffRatio<=0.1 { normal=max(normal,error) } else { extreme=max(extreme,error) }
                }
            }
        }
    }
    print("OTA/capacitor equation residual: audio band \(normal), extreme cutoff \(extreme)")
    precondition(normal<0.00001 && extreme<0.001,"Trapezoidal circuit solve must converge under modulation and overload")
}
func circuitGain(sr:Float,frequency:Float,cutoff:Float,resonance:Float,amplitude:Float)->Float {
    var filter=CurtisFilter(),energy:Double=0
    for n in 0..<Int(sr*0.3) {
        let input=amplitude*sinf(2 * .pi*frequency*Float(n)/sr)
        let out=filter.process(input,cutoff:cutoff,resonance:resonance,sampleRate:sr)
        if n>=Int(sr*0.1) { energy += Double(out*out) }
    }
    return Float(sqrt(energy/Double(sr*0.2))*sqrt(2))/amplitude
}
func checkCircuitResponse() {
    var gains=[Float]()
    for sr:Float in [192000,384000,768000] {
        let low=circuitGain(sr:sr,frequency:20,cutoff:1000,resonance:0,amplitude:0.001)
        let resonant=circuitGain(sr:sr,frequency:20,cutoff:1000,resonance:0.7,amplitude:0.001)
        let slope=20*log10f(circuitGain(sr:sr,frequency:4000,cutoff:1000,resonance:0,amplitude:0.001)/circuitGain(sr:sr,frequency:2000,cutoff:1000,resonance:0,amplitude:0.001))
        precondition(abs(low-0.65)<0.005)
        precondition(abs(resonant/low-1/(1+0.7*4.4))<0.005,"Feedback must retain natural bass loss")
        precondition(slope < -21 && slope > -24)
        gains.append(circuitGain(sr:sr,frequency:500,cutoff:1200,resonance:0.7,amplitude:1.4))
        print("Circuit \(sr) Hz: low gain \(low), bass ratio \(resonant/low), slope \(slope), driven gain \(gains.last!)")
    }
    precondition(gains.max()!/gains.min()!<1.01,"Driven circuit response must converge with sample rate")
    let quiet=circuitGain(sr:192000,frequency:100,cutoff:1000,resonance:0,amplitude:0.001)
    let hot=circuitGain(sr:192000,frequency:100,cutoff:1000,resonance:0,amplitude:4)
    precondition(hot<quiet*0.8 && hot>quiet*0.2)
    precondition(AnalogSignalPath.mixer(0)==0)
    var previous:Float = -2
    for n in -10000...10000 {
        let value=AnalogSignalPath.mixer(Float(n)*0.01)
        precondition(value>=previous && abs(value)<1.5)
        previous=value
    }
    print("Biased input: zero idle output, monotonic overload, driven gain \(hot)/\(quiet) passed")
}
checkCircuitResidual()
checkCircuitResponse()
