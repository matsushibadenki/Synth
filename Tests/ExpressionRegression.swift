// Concatenate after Rev3Regression.swift and the audio sources.
func checkExpression() throws {
    for sr: Double in [44100,48000,96000] {
        var p=SynthParameters()
        p.expression.enabled=true
        p.expression.sub=1; p.expression.motion=1; p.expression.pan=1; p.expression.rate=8
        p.expression.ladder=1; p.expression.drive=1; p.expression.feedback=1
        let probe=try AudioProbe(p)
        probe.unit.deallocateRenderResources()
        try probe.unit.outputBusses[0].setFormat(AVAudioFormat(standardFormatWithSampleRate:sr,channels:2)!)
        try probe.unit.allocateRenderResources()
        let buffer=AVAudioPCMBuffer(pcmFormat:probe.unit.outputBusses[0].format,frameCapacity:256)!
        probe.unit.noteOn(48,velocity:1)
        var difference: Float=0
        for block in 0..<160 {
            if block < 80 { probe.parameters.set { $0.expression.slope=Float((block/20)%4)/3 } }
            if block == 80 { probe.parameters.set { $0.expression.enabled=false } }
            precondition(probe.render(&probe.flags,&probe.time,256,0,buffer.mutableAudioBufferList,nil,nil)==noErr)
            for i in 0..<256 {
                let l=buffer.floatChannelData![0][i],r=buffer.floatChannelData![1][i]
                precondition(l.isFinite && r.isFinite && abs(l)<1 && abs(r)<1)
                if block < 80 { difference += abs(l-r) }
                if block == 159 { precondition(abs(l-r)<0.000001,"Classic must return to mono after smoothing") }
            }
            probe.time.mSampleTime += 256
        }
        precondition(difference>0.01,"Auto pan must produce stereo motion")
    }
    var p=SynthParameters(); p.expression.enabled=true
    let saved=Rev3Program(p)
    precondition(saved.pots.count==24 && saved.switches.count==22)
    precondition(saved.applying(to:p)!.expression==p.expression)
    var invalid=ExpressionParameters(); invalid.sub = .nan; invalid.rate = .infinity
    precondition(invalid.amounts == .zero && invalid.rateHz.isFinite)
    print("Expression: three sample rates, stereo motion, classic bypass, schema isolation passed")
}
func checkLadder() throws {
    let legacy=Data(#"{"enabled":true,"sub":0.2,"motion":0.1,"rate":0.5,"pan":0.4}"#.utf8)
    let migrated=try JSONDecoder().decode(ExpressionParameters.self,from:legacy)
    precondition(migrated.enabled && migrated.sub == 0.2 && migrated.ladder == 0 && migrated.slope == 1)
    let roundtrip=try JSONDecoder().decode(ExpressionParameters.self,from:JSONEncoder().encode(migrated))
    precondition(roundtrip == migrated)
    for sr: Float in [44100,48000,96000] {
        var energies=[Float]()
        for pole in 0..<4 {
            var filter=LadderColorFilter(),energy: Float=0
            for i in 0..<Int(sr/4) {
                let sample=filter.process(sinf(2 * .pi * 5000 * Float(i)/(sr*4))*0.2,cutoff:700,
                    resonance:0,drive:0,feedback:0,slope:Float(pole)/3,sampleRate:sr*4)
                if i > 1000 { energy += sample*sample }
            }
            energies.append(energy)
            for i in 0..<20000 {
                let sample=filter.process(i < 10000 ? 2 : 0,cutoff:Float(i%1000)*20+20,
                    resonance:1,drive:1,feedback:1,slope:Float(pole)/3,sampleRate:sr*4)
                precondition(sample.isFinite && abs(sample)<=1)
            }
        }
        for i in 1..<4 { precondition(energies[i]<energies[i-1],"Steeper slope must attenuate high frequencies") }
    }
    func audio(_ p: SynthParameters) throws -> [Float] {
        let probe=try AudioProbe(p)
        probe.unit.noteOn(48,velocity:1)
        return probe.samples(20)
    }
    var classic=SynthParameters()
    let original=try audio(classic)
    classic.expression.ladder=1; classic.expression.drive=1; classic.expression.feedback=1
    let bypassed=try audio(classic)
    precondition(original == bypassed,"SYNTH/05 must bypass all color controls exactly")
    classic.expression.enabled=true; classic.expression.sub=0; classic.expression.motion=0; classic.expression.pan=0
    let colored=try audio(classic)
    precondition(zip(original,colored).reduce(Float(0)) { $0+abs($1.0-$1.1) }>0.1,"Ladder color must reach the audio output")
    print("Ladder: slopes, maximum resonance/drive/feedback stability and legacy settings migration passed")
}
try checkLadder()
try checkExpression()
