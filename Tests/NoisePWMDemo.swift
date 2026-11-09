// Concatenate after audio sources and Rev3Regression.swift; output file argument.
func writeNoisePWMDemo(_ path: String) throws {
    var p=SynthParameters()
    p.oscASaw=false; p.oscAPulse=true; p.oscBSaw=false; p.oscBPulse=true
    p.oscALevel=0.65; p.oscBLevel=0.3; p.oscBFineCents=3
    p.modWheel=0.85; p.wheelSourceMix=1; p.lfoToOscA=false
    p.lfoToPWA=true; p.lfoToPWB=true; p.polyModOscB=0.2; p.polyModToPWA=true
    p.cutoffNorm=0.72; p.resonance=0.2; p.filterEnvAmount=0.1
    p.envBAttack=0.05; p.envBRelease=0.2
    let probe=try AudioProbe(p)
    var audio=[Float]()
    for note in [48,60,72] {
        probe.unit.noteOn(note,velocity:1); audio += probe.samples(120)
        probe.unit.noteOff(note); audio += probe.samples(30)
    }
    probe.parameters.set { $0.oscSync=true }
    for note in [48,55,60] { probe.unit.noteOn(note,velocity:1) }
    audio += probe.samples(300)
    for note in [48,55,60] { probe.unit.noteOff(note) }
    audio += probe.samples(60)
    let rms=sqrt(audio.reduce(Double(0)) { $0+Double($1*$1) }/Double(audio.count))
    let peak=Double(audio.map { abs($0) }.max() ?? 1)
    let gain=Float(min(0.1/max(1e-9,rms),0.95/max(1e-9,peak)))
    let format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:1)!
    let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:AVAudioFrameCount(audio.count))!
    buffer.frameLength=buffer.frameCapacity
    for i in audio.indices { buffer.floatChannelData![0][i]=audio[i]*gain }
    let file=try AVAudioFile(forWriting:URL(fileURLWithPath:path),settings:format.settings)
    try file.write(from:buffer)
    print("Noise PWM demo: \(path), \(Double(audio.count)/48000)s, RMS \(rms), constant gain \(gain)")
}
if CommandLine.arguments.count == 2 { try writeNoisePWMDemo(CommandLine.arguments[1]) }
