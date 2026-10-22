import Foundation

@main struct EffectsRegression {
    static func main() throws {
        try graphTests()
        for sr: Float in [44_100,48_000,96_000] { try audioTests(sr) }
        try looperTests()
        try ringSpectrumTest()
        print("Effects: graph / modes / impulse tails / stereo / feedback / looper / serialization passed")
    }
    static func check(_ value: @autoclosure () -> Bool,_ message: String) {
        if !value() { fputs("FAIL: \(message)\n",stderr); exit(1) }
    }
    static func graphTests() throws {
        let initial=FXDocument.initial
        var editor=try FXEditor(initial)
        let serial=try initial.configuration()
        check(serial.steps.map(\.id) == [1,2,3,4,5,6,8],"Specified initial order")
        do { try editor.execute(.connect(FXEdge(from:6,to:1,port:"in"))); preconditionFailure("Occupied accepted") } catch FXGraphError.occupied { }
        check(editor.document == initial,"Invalid edit must be atomic")
        do {
            try editor.execute(.batch([.disconnect("0:out>1:in"),.connect(FXEdge(from:6,to:1,port:"in"))]))
            preconditionFailure("Cycle accepted")
        } catch FXGraphError.cycle { }
        check(editor.document == initial,"Invalid batch rollback")
        do { try editor.execute(.connect(FXEdge(from:8,to:7,port:"a"))); preconditionFailure("Output source accepted") } catch FXGraphError.port { }
        try editor.execute(.move(2,55,66)); editor.undo(); check(editor.document == initial,"Undo")
        editor.redo(); check(editor.document.nodes[2].x == 55,"Redo")
        let data=try JSONEncoder().encode(editor.document)
        let decoded=try JSONDecoder().decode(FXDocument.self,from:data)
        check(decoded == editor.document,"Document roundtrip")
        try decoded.validate()
        var malformed=initial; malformed.nodes[2].settings.values[0] = .nan
        check((try? malformed.validate()) == nil,"Non-finite property rejected")
        var disconnected=initial; disconnected.edges=[]
        let rack=EffectsRackDSP(sampleRate:48_000); rack.prepare(try disconnected.configuration())
        check(rack.process(SIMD2(0.5,0.5)) == .zero,"Disconnected output is silent")
        var parallel=initial
        parallel.edges=[.init(from:0,to:7,port:"a"),.init(from:0,to:7,port:"b"),.init(from:7,to:8,port:"in")]
        rack.prepare(try parallel.configuration())
        for _ in 0..<600 { _=rack.process(SIMD2(0.2,0.4)) }
        let value=rack.process(SIMD2(0.2,0.4))
        check(abs(value.x-0.2)<0.00001 && abs(value.y-0.4)<0.00001,"Parallel A/B gain")
        print("UNGE port: atomic batch / type-direction / cardinality / cycle / history / persistence / parallel passed")
    }
    static func isolated(_ kind: EffectKind,_ settings: FXSettings) throws -> FXRenderConfiguration {
        var doc=FXDocument.initial
        doc.nodes[kind.rawValue].settings=settings
        doc.edges=[.init(from:0,to:kind.rawValue,port:"in"),.init(from:kind.rawValue,to:8,port:"in")]
        return try doc.configuration()
    }
    static func audioTests(_ sr: Float) throws {
        let dry=EffectsRackDSP(sampleRate:sr); dry.prepare(try FXDocument.initial.configuration())
        for i in 0..<1000 {
            let input=SIMD2<Float>(sinf(Float(i)*0.1)*0.3,cosf(Float(i)*0.1)*0.2)
            check(dry.process(input) == input,"All bypass must preserve samples")
        }
        let start=Date()
        for kind in EffectKind.allCases where (1...6).contains(kind.rawValue) {
            var fingerprints=[Double]()
            for mode in kind.modes.indices where !(kind == .pedal && mode == 3) {
                var state=FXSettings(kind); state.enabled=true; state.mode=mode; state.values[4]=1
                if kind == .ring { state.values[0]=0.9 }
                let rack=EffectsRackDSP(sampleRate:sr); rack.prepare(try isolated(kind,state))
                var energy: Double=0, tail: Double=0, stereo: Double=0, fingerprint: Double=0
                let count=Int(sr*1.2)
                for i in 0..<count {
                    let signal: Float=kind == .ring ? (i < Int(sr*0.4) ? sinf(Float(i)*2 * .pi*440/sr)*0.25:0):(i == 0 ? 0.5:0)
                    let value=rack.process(SIMD2(repeating:signal))
                    check(value.x.isFinite && value.y.isFinite && abs(value.x)<=1 && abs(value.y)<=1,"Stable bounded output")
                    energy += Double(value.x*value.x+value.y*value.y)
                    if i > Int(sr*((kind == .dimension || (kind == .studio && mode < 2)) ? 0.001:0.05)) { tail += Double(value.x*value.x+value.y*value.y) }
                    stereo += Double(abs(value.x-value.y))
                    fingerprint += Double(value.x)*sin(Double(i)*0.017)+Double(value.y)*cos(Double(i)*0.031)
                }
                check(energy > 0.0000001,"Nonzero effect: \(kind) mode \(mode)")
                if kind != .ring { check(tail > 0.00000001,"Delayed tail \(kind) \(mode)") }
                if kind == .sky || (kind == .time && mode == 3) { check(stereo > 0.0001,"Stereo decorrelation") }
                fingerprints.append(fingerprint)
            }
            for i in fingerprints.indices.dropFirst() { check(abs(fingerprints[i]-fingerprints[i-1])>0.0000001,"Modes must differ: \(kind)") }
        }
        // Worst feedback and long-tail processing on the complete chain.
        var document=FXDocument.initial
        for i in 1...6 { document.nodes[i].settings.enabled=true; document.nodes[i].settings.values=Array(repeating:1,count:5) }
        let full=EffectsRackDSP(sampleRate:sr); full.prepare(try document.configuration())
        for i in 0..<Int(sr*2) {
            let sample=full.process(i<100 ? SIMD2(repeating:0.7):.zero)
            check(sample.x.isFinite && sample.y.isFinite,"Maximum feedback chain")
        }
        print("FX DSP \(Int(sr))Hz: all modes and feedback passed (\(String(format:"%.2f",Date().timeIntervalSince(start)))s)")
    }
    static func ringSpectrumTest() throws {
        let sr: Float=48_000, rack=EffectsRackDSP(sampleRate:48_000)
        var state=FXSettings(.ring); state.enabled=true; state.mode=2
        state.values=[logf(300/30)/logf(4000/30),0,0,0,1]
        rack.prepare(try isolated(.ring,state))
        var sine=SIMD3<Double>.zero, cosine=SIMD3<Double>.zero
        for i in 0..<52800 {
            let value=rack.process(SIMD2(repeating:sinf(Float(i)*2 * .pi*440/sr)*0.25)).x
            if i >= 4800 {
                for (bin,hz) in [140.0,740.0,440.0].enumerated() {
                    let phase=Double(i)*2 * Double.pi*hz/Double(sr)
                    sine[bin] += Double(value)*sin(phase); cosine[bin] += Double(value)*cos(phase)
                }
            }
        }
        let magnitude=sine*sine+cosine*cosine
        check(magnitude[0]>100 && magnitude[1]>100 && magnitude[2]<min(magnitude[0],magnitude[1])*0.001,"Ring modulator must create 440±300 Hz sidebands and suppress the input fundamental")
    }
    static func looperTests() throws {
        let sr: Float=48_000, rack=EffectsRackDSP(sampleRate:48_000)
        var state=FXSettings(.pedal); state.enabled=true; state.mode=3; state.values[4]=1
        state.loopSerial=1; state.loopAction=1
        rack.prepare(try isolated(.pedal,state))
        for i in 0..<4800 { _=rack.process(SIMD2(repeating:sinf(Float(i)*0.07)*0.2)) }
        check(rack.loopState == 1 && abs(rack.loopSeconds-0.1)<0.0001,"Loop recording")
        state.loopSerial += 1; rack.prepare(try isolated(.pedal,state))
        var energy: Float=0
        for _ in 0..<4800 { energy += abs(rack.process(.zero).x) }
        check(rack.loopState == 2 && energy>1,"Loop playback")
        state.loopSerial += 1; rack.prepare(try isolated(.pedal,state)); check(rack.loopState == 3,"Overdub")
        state.reverse=true; state.halfSpeed=true; rack.prepare(try isolated(.pedal,state))
        for _ in 0..<Int(sr) { check(rack.process(SIMD2(repeating:0.1)).x.isFinite,"Reverse half-speed loop") }
        state.loopSerial += 1; state.loopAction=2; rack.prepare(try isolated(.pedal,state)); check(rack.loopState == 4,"Stop loop")
        state.loopSerial += 1; state.loopAction=3; rack.prepare(try isolated(.pedal,state)); check(rack.loopState == 0 && rack.loopSeconds == 0,"Clear loop")
    }
}
