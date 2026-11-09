// Offline before/after comparison harness. Run against both source snapshots.
// The recorded sample fingerprints intentionally depend on the DSP revision.
func renderFingerprints() throws {
    for variant in 0..<12 {
        if CommandLine.arguments.contains("--noise-free") && [0,3,6].contains(variant) { continue }
        var p=SynthParameters()
        p.oscSync=variant%2 == 1
        p.oscAPulse=true; p.oscBPulse=true; p.oscBTriangle=true
        p.polyModToFreqA=variant>=2; p.polyModOscB=0.8
        p.polyModToPWA=variant>=2; p.polyModToFilter=variant>=2
        p.lfoToPWA=true; p.lfoToPWB=true; p.lfoToOscA=false
        p.modWheel=1; p.wheelSourceMix=variant%3 == 0 ? 1:0
        p.resonance=variant>=4 ? 1:0.3
        p.expression.enabled=variant>=6
        p.expression.ladder=variant == 7 ? 1:0
        if variant == 9 { p.wheelSourceMix=1; p.modWheel=0 }
        if variant == 10 { p.wheelSourceMix=1; p.lfoToPWA=false; p.lfoToPWB=false }
        if variant == 11 { p.wheelSourceMix=1; p.oscAPulse=false; p.oscBPulse=false }
        let probe=try AudioProbe(p)
        var hash: UInt64=14695981039346656037
        func collect(_ blocks: Int) {
            for block in 0..<blocks {
                if CommandLine.arguments.contains("--blend-sweep") && block%5 == 0 {
                    probe.parameters.set { $0.wheelSourceMix=Float((block/5)%5)*0.25 }
                }
                precondition(probe.render(&probe.flags,&probe.time,256,0,probe.buffer.mutableAudioBufferList,nil,nil)==noErr)
                for channel in 0..<2 {
                    for frame in 0..<256 {
                        let value=probe.buffer.floatChannelData![channel][frame]
                        precondition(value.isFinite && abs(value)<=1)
                        hash=(hash ^ UInt64(value.bitPattern)) &* 1099511628211
                    }
                }
                probe.time.mSampleTime += 256
            }
        }
        collect(3) // Closed gates still run their filters and oscillator phases.
        for note in [48,55,60,64,67] { probe.unit.noteOn(note,velocity:1) }
        collect(30)
        probe.parameters.set { $0.cutoffNorm=0.8; $0.modWheel=variant == 9 ? 0:0.4; $0.envBRelease=0.05 }
        collect(20)
        for note in [48,55,60,64,67] { probe.unit.noteOff(note) }
        collect(50)
        print("render \(variant): \(hash)")
    }
}
try renderFingerprints()
