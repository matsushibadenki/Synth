// Concatenate after the audio sources. Test behavior, not hardware identity.
func checkFilterColor() {
    setbuf(stdout,nil)
    func probe(_ sr: Float,_ frequency: Float,_ level: Float,_ resonance: Float) -> (Float,Float) {
        var filter=CurtisFilter(),energy: Double=0,peak: Float=0
        let count=Int(sr*0.1)
        for i in 0..<count {
            let output=filter.process(level*sinf(2 * .pi*frequency*Float(i)/sr),cutoff:1000,resonance:resonance,sampleRate:sr)
            precondition(output.isFinite && abs(output)<4)
            if i>count/2 { energy += Double(output*output); peak=max(peak,abs(output)) }
        }
        return (Float(sqrt(energy/Double(count/2))),peak)
    }
    for sr: Float in [176400,192000,352800,384000] {
        let low=probe(sr,100,0.01,0).0
        let high=probe(sr,4000,0.01,0).0
        precondition(high<low*0.02,"Four-pole high-band rejection")
        let gentle=probe(sr,900,0.01,0.3).0
        let resonant=probe(sr,900,0.01,0.8).0
        precondition(resonant>gentle*1.5,"Resonance must raise the cutoff-region peak")
        let bass0=probe(sr,100,0.01,0).0
        let bass1=probe(sr,100,0.01,0.8).0
        precondition(bass1<bass0,"Preserve resonance-related bass loss; no hidden loudness compensation")
        let soft=probe(sr,100,0.02,0).0/0.02
        let loud=probe(sr,100,2,0).0/2
        precondition(loud<soft*0.9 && loud>soft*0.3,"Input overload must compress smoothly, not mute")
        var selfOsc=CurtisFilter(),tail: Double=0
        for i in 0..<Int(sr) {
            let sample=selfOsc.process(i == 0 ? 0.01:0,cutoff:1000,resonance:1,sampleRate:sr)
            precondition(sample.isFinite && abs(sample)<2)
            if i>Int(sr/2) { tail += Double(sample*sample) }
        }
        precondition(tail>1,"Bounded self oscillation must survive")
        print("Filter \(Int(sr))Hz: resonance peak, bass loss, overload, self-oscillation passed; normalized gain \(soft) → \(loud)")
    }
    func thirdHarmonic(_ level: Float,_ stage: (Float)->Float) -> Double {
        var fundamental=0.0,third=0.0
        for i in 0..<12288 {
            let phase=2 * Double.pi*Double(i)/96
            let value=Double(stage(level*Float(sin(phase))))
            fundamental += value*sin(phase); third += value*sin(3*phase)
        }
        return abs(third/fundamental)
    }
    let small=thirdHarmonic(0.02,AnalogSignalPath.mixer)
    let overloaded=thirdHarmonic(2,AnalogSignalPath.mixer)
    let fullVCA=thirdHarmonic(3) { AnalogSignalPath.amplifier($0,envelope:1,gain:1) }
    let quietVCA=thirdHarmonic(3) { AnalogSignalPath.amplifier($0,envelope:0.1,gain:1) }
    precondition(small<0.0001 && overloaded>0.01 && overloaded>small*100,"Overload must add harmonics while preserving low-level transparency")
    precondition(quietVCA<fullVCA*0.1,"VCA harmonics must recede with its envelope")
    print("H3/fundamental mixer: \(small) → \(overloaded); VCA full \(fullVCA), quiet \(quietVCA)")
    for sr: Float in [176400,192000,352800,384000] {
        var filter=CurtisFilter(),seed: UInt32=7
        for i in 0..<20000 {
            seed=1664525 &* seed &+ 1013904223
            let random=Float(seed>>8)/16777215
            let sample=filter.process((random-0.5)*10,cutoff:20+random*sr*0.39,
                resonance:Float(i%120)/100,sampleRate:sr)
            precondition(sample.isFinite && abs(sample)<4,"Extreme cutoff/resonance/input must remain bounded")
        }
    }
    for input: Float in [0,0.01,0.5,1,4] {
        let full=AnalogSignalPath.amplifier(input,envelope:1,gain:1)
        let quiet=AnalogSignalPath.amplifier(input,envelope:0.1,gain:1)
        precondition(full.isFinite && quiet.isFinite)
        if input>0.1 { precondition(quiet>full*0.1,"Quiet VCA must recover small-signal headroom") }
        precondition(AnalogSignalPath.amplifier(input,envelope:0,gain:1) == 0)
        precondition(abs(AnalogSignalPath.mixer(input)+AnalogSignalPath.mixer(-input))<1e-6,"No artificial DC bias")
    }
    print("Analog gain staging: envelope-dependent saturation and zero-gate silence passed")
}
checkFilterColor()
