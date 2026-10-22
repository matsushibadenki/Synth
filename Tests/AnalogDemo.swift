// Offline demo / 离线试听 / オフライン試聴: brass → bass → sync → Poly-Mod bell.
// Concatenate after Rev3Parameters, EffectsGraph, EffectsDSP, ProphetCore and
// Rev3Regression. Pass an output .wav path; it also writes a .sync.wav probe.
func writeWave(_ samples:[Float], path:String) throws {
    let format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:1)!
    let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:AVAudioFrameCount(samples.count))!
    buffer.frameLength=buffer.frameCapacity
    for i in samples.indices { buffer.floatChannelData![0][i]=samples[i] }
    let file=try AVAudioFile(forWriting:URL(fileURLWithPath:path),settings:format.settings)
    try file.write(from:buffer)
}
precondition(CommandLine.arguments.count == 2,"Pass an output WAV path")
let outputPath=CommandLine.arguments[1]
var audio=[Float]()
var p=SynthParameters()
p.oscBFineCents=3; p.cutoffNorm=0.34; p.resonance=0.25
p.envAAttack=0.025; p.envADecay=0.7; p.envASustain=0.25; p.filterEnvAmount=0.4
p.envBAttack=0.03; p.envBRelease=0.8
let pad=try AudioProbe(p)
for note in [48,55,58,62,65] { pad.unit.noteOn(note,velocity:1) }
audio += pad.samples(700)
for note in [48,55,58,62,65] { pad.unit.noteOff(note) }
audio += pad.samples(250)
p.unisonMode=true; p.cutoffNorm=0.27; p.resonance=0.4
p.envAAttack=0.001; p.envADecay=0.23; p.envASustain=0; p.filterEnvAmount=0.5
p.envBAttack=0.001; p.envBDecay=0.25; p.envBSustain=0.7; p.envBRelease=0.13
let bass=try AudioProbe(p)
for note in [36,36,43,39,36,48] {
    bass.unit.noteOn(note,velocity:1); audio += bass.samples(65)
    bass.unit.noteOff(note); audio += bass.samples(25)
}
audio += bass.samples(80)
p=SynthParameters(); p.oscSync=true; p.oscAFrequency=43; p.oscBLevel=0
p.polyModFilterEnv=0.45; p.polyModToFreqA=true
p.envAAttack=0.001; p.envADecay=0.5; p.envASustain=0.05
p.cutoffNorm=0.75; p.resonance=0.28; p.filterEnvAmount=0
p.envBAttack=0.005; p.envBRelease=0.2
let sync=try AudioProbe(p)
for note in [60,62,67,65] {
    sync.unit.noteOn(note,velocity:1); audio += sync.samples(100)
    sync.unit.noteOff(note); audio += sync.samples(45)
}
p=SynthParameters(); p.oscBSaw=false; p.oscBTriangle=true; p.oscBLevel=0
p.oscBFrequency=43; p.oscBFineCents=0; p.polyModOscB=0.2; p.polyModToFreqA=true
p.cutoffNorm=0.8; p.resonance=0.1; p.filterEnvAmount=0
p.envBAttack=0.001; p.envBDecay=0.8; p.envBSustain=0; p.envBRelease=1
let bell=try AudioProbe(p)
for note in [60,67,72] {
    bell.unit.noteOn(note,velocity:1); audio += bell.samples(150)
    bell.unit.noteOff(note); audio += bell.samples(100)
}
audio += bell.samples(150)
try writeWave(audio,path:outputPath)
// Fixed sustained sync probe for a spectral alias comparison, FX bypassed.
p=SynthParameters(); p.oscSync=true; p.oscBLevel=0; p.oscBFineCents=0
p.oscAFrequency=47; p.cutoffNorm=1; p.filterEnvAmount=0; p.filterKeyboardTrack=false; p.resonance=0
p.envBAttack=0.001; p.envBDecay=0.001; p.envBSustain=1
let spectral=try AudioProbe(p); spectral.unit.noteOn(91,velocity:1)
_=spectral.samples(100)
try writeWave(spectral.samples(600),path:outputPath+".sync.wav")
print("Rendered \(Double(audio.count)/48000)s dry demo, peak \(audio.map { abs($0) }.max()!)")
