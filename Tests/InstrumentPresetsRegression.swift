// Concatenate after Rev3Parameters, EffectsGraph, EffectsDSP, ProphetCore and
// Rev3Regression. Compile with -O. Optional argument: folder for dry WAV demos.
func checkInstrumentPresets() throws {
    var current=SynthParameters()
    current.masterVolume=0.37; current.masterTuneSemitones=0.2
    current.modWheel=0.8; current.pitchWheel=0.7; current.referenceA440=true
    current.autoTuneTrigger=9
    for preset in InstrumentPreset.allCases {
        let restored=try JSONDecoder().decode(Rev3Program.self,from:JSONEncoder().encode(preset.program))
        precondition(restored == preset.program)
        let p=preset.applying(to:current)
        precondition(p.masterVolume == current.masterVolume && p.masterTuneSemitones == current.masterTuneSemitones)
        precondition(p.modWheel == 0 && p.pitchWheel == 0 && !p.referenceA440 && p.autoTuneTrigger == 9)
        precondition(p.oscBFineCents == 0 && p.noiseLevel == 0 && !p.unisonMode)
        precondition(preset.program.pots.count == 24 && preset.program.switches.count == 22)
    }
    let piano=try AudioProbe(InstrumentPreset.piano.applying(to:SynthParameters()))
    piano.unit.noteOn(60,velocity:1)
    let attack=rms(piano.samples(12))
    _=piano.samples(400)
    let decay=rms(piano.samples(30))
    precondition(attack>0.001 && decay<attack*0.04,"Piano must have an audible attack and decay to near silence while held")
    piano.unit.noteOff(60); _=piano.samples(150)
    precondition(rms(piano.samples(15))<0.00001)

    let violin=try AudioProbe(InstrumentPreset.violin.applying(to:SynthParameters()))
    violin.unit.noteOn(69,velocity:1)
    let start=rms(violin.samples(3))
    _=violin.samples(150)
    var levels=[Float]()
    for _ in 0..<100 { levels.append(rms(violin.samples(15))) }
    let sustain=levels.reduce(0,+)/Float(levels.count)
    let sorted=levels.sorted(), span=20*log10f(sorted[95]/sorted[5])
    precondition(sustain>0.001 && start<sustain*0.25,"Violin must swell into a sustained tone")
    precondition(span<0.2,"Reference violin must sustain without incidental amplitude swells")
    violin.unit.noteOff(69); _=violin.samples(150)
    precondition(rms(violin.samples(15))<0.00001,"Violin must release cleanly")
    print("Instrument presets: schema/recall/performance offsets, piano decay, violin swell/stability/release passed")
    print("Piano attack \(attack), held decay \(decay); violin sustained span \(span) dB")
}
func writePresetDemo(_ preset: InstrumentPreset, folder: String) throws {
    let probe=try AudioProbe(preset.applying(to:SynthParameters()))
    var audio=[Float]()
    if preset == .piano {
        for note in [48,60,64,67,72] {
            probe.unit.noteOn(note,velocity:1); audio += probe.samples(220)
            probe.unit.noteOff(note); audio += probe.samples(45)
        }
        for note in [48,55,60,64,67] { probe.unit.noteOn(note,velocity:1) }
        audio += probe.samples(550)
        for note in [48,55,60,64,67] { probe.unit.noteOff(note) }
    } else {
        for note in [60,64,67] {
            probe.unit.noteOn(note,velocity:1); audio += probe.samples(240)
            probe.unit.noteOff(note); audio += probe.samples(70)
        }
        probe.unit.noteOn(69,velocity:1); audio += probe.samples(1500)
        probe.unit.noteOff(69)
    }
    audio += probe.samples(150)
    let format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:1)!
    let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:AVAudioFrameCount(audio.count))!
    buffer.frameLength=buffer.frameCapacity
    for i in audio.indices { buffer.floatChannelData![0][i]=audio[i] }
    let url=URL(fileURLWithPath:folder).appendingPathComponent("\(preset.rawValue)-preset.wav")
    let file=try AVAudioFile(forWriting:url,settings:format.settings)
    try file.write(from:buffer)
    print("Dry \(preset.rawValue) demo: \(Double(audio.count)/48000) seconds at \(url.path)")
}
checkSchema()
try checkInstrumentPresets()
if CommandLine.arguments.count == 2 {
    for preset in InstrumentPreset.allCases { try writePresetDemo(preset,folder:CommandLine.arguments[1]) }
}
