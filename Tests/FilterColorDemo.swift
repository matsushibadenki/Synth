// Concatenate after audio sources and Rev3Regression.swift. Folder argument required.
func writeFilterColorDemo(folder: String) throws {
    var p=SynthParameters()
    p.cutoffNorm=0.68; p.filterEnvAmount=0.15; p.resonance=0.25
    p.envAAttack=0.03; p.envADecay=0.35; p.envASustain=0.3
    p.envBAttack=0.025; p.envBDecay=0.4; p.envBSustain=0.7; p.envBRelease=0.25
    p.oscBLevel=0; p.oscALevel=0.5
    let probe=try AudioProbe(p)
    var samples=[Float]()
    // Single saw, two oscillators at higher mixer level, resonant sweep.
    for section in 0..<3 {
        probe.parameters.set {
            $0.oscALevel=section == 0 ? 0.5:1
            $0.oscBLevel=section == 0 ? 0:1
            $0.resonance=section == 2 ? 0.8:0.25
        }
        for note in [48,55,60] { probe.unit.noteOn(note,velocity:1) }
        for block in 0..<300 {
            if section == 2 { probe.parameters.set { $0.cutoffNorm=0.3+Float(block)/300*0.5 } }
            samples += probe.samples(1)
        }
        for note in [48,55,60] { probe.unit.noteOff(note) }
        samples += probe.samples(90)
    }
    // One constant gain for the whole clip; never normalize individual notes.
    let level=sqrt(samples.reduce(Double(0)) { $0+Double($1*$1) }/Double(samples.count))
    let gain=Float(min(0.12/max(1e-9,level),0.95/Double(samples.map { abs($0) }.max() ?? 1)))
    let format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:1)!
    let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:AVAudioFrameCount(samples.count))!
    buffer.frameLength=buffer.frameCapacity
    for i in samples.indices { buffer.floatChannelData![0][i]=samples[i]*gain }
    let url=URL(fileURLWithPath:folder).appendingPathComponent("filter-color.wav")
    let file=try AVAudioFile(forWriting:url,settings:format.settings)
    try file.write(from:buffer)
    print("Dry filter demo: \(url.path), \(Double(samples.count)/48000)s, overall RMS \(level), constant gain \(gain)")
}
if CommandLine.arguments.count == 2 { try writeFilterColorDemo(folder:CommandLine.arguments[1]) }
