// Run with Rev3Parameters.swift and ProphetCore.swift concatenated before this file (see README).
// Direct AU rendering exercises DSP without requiring an audio output device.
func checkEnvelope() {
    for sr: Float in [44100, 48000, 96000] {
        var envelope = AnalogEnvelope()
        envelope.trigger()
        for _ in 0..<Int(sr) {
            envelope.advance(gate: true, attack: 0.01, decay: 0.1, sustain: 0.35, release: 0.1, sr: sr)
        }
        precondition(abs(envelope.level - 0.35) < 0.001, "ADSR must remain at sustain")
        envelope.trigger()
        for _ in 0..<Int(sr * 0.02) {
            envelope.advance(gate: true, attack: 0.01, decay: 0.1, sustain: 0.35, release: 0.1, sr: sr)
        }
        precondition(envelope.level > 0.35, "Retrigger must restart attack")
        for _ in 0..<Int(sr * 0.2) {
            envelope.advance(gate: false, attack: 0.01, decay: 0.1, sustain: 0.35, release: 0.1, sr: sr)
        }
        precondition(envelope.level == 0, "Release must reach silence")
    }
}

func checkRender() throws {
    let parameters = SharedSynthParameters()
    ProphetLikeAudioUnit.sharedParameters = parameters
    let unit = try ProphetLikeAudioUnit(componentDescription: AudioComponentDescription(
        componentType: kAudioUnitType_Generator, componentSubType: 0x50723535,
        componentManufacturer: 0x53796E74, componentFlags: 0, componentFlagsMask: 0))
    for sr in [44100.0, 48000.0, 96000.0] {
        try unit.outputBusses[0].setFormat(AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2)!)
        try unit.allocateRenderResources()
        let buffer = AVAudioPCMBuffer(pcmFormat: unit.outputBusses[0].format, frameCapacity: 256)!
        let render = unit.internalRenderBlock
        var flags = AudioUnitRenderActionFlags()
        var timestamp = AudioTimeStamp()
        timestamp.mFlags = .sampleTimeValid
        var peak: Float = 0
        for unison in [false, true] {
            for resonance: Float in [0, 0.5, 1] {
                parameters.set {
                    $0.unisonMode = unison; $0.resonance = resonance
                    $0.oscSync = true; $0.polyModOscB = 0.7; $0.polyModToFreqA = true; $0.polyModToPWA = true; $0.polyModToFilter = true
                    $0.lfoToPWA = true; $0.oscAPulse = true; $0.modWheel = 0.5
                }
                for note in [36, 48, 60, 72, 96] { unit.noteOn(note, velocity: 0.85) }
                for block in 0..<200 {
                    parameters.set { $0.cutoffNorm = Float(block) / 199 }
                    let status = render(&flags, &timestamp, 256, 0, buffer.mutableAudioBufferList, nil, nil)
                    precondition(status == noErr)
                    for channel in 0..<2 {
                        for i in 0..<256 {
                            let value = buffer.floatChannelData![channel][i]
                            precondition(value.isFinite && abs(value) <= 1, "Invalid output")
                            peak = max(peak, abs(value))
                        }
                    }
                    timestamp.mSampleTime += 256
                }
                parameters.set { $0.masterVolume = 0 }
                precondition(render(&flags, &timestamp, 256, 0, buffer.mutableAudioBufferList, nil, nil) == noErr)
                for channel in 0..<2 {
                    precondition((0..<256).allSatisfy { buffer.floatChannelData![channel][$0] == 0 }, "Master output must mute both channels")
                }
                parameters.set { $0.masterVolume = 1 }
                for note in [36, 48, 60, 72, 96] { unit.noteOff(note) }
            }
        }
        precondition(peak > 0.001, "Synth must produce audio")
        for _ in 0..<Int(sr / 256 * 2) {
            precondition(render(&flags, &timestamp, 256, 0, buffer.mutableAudioBufferList, nil, nil) == noErr)
        }
        precondition((0..<256).allSatisfy { abs(buffer.floatChannelData![0][$0]) < 0.0001 }, "Release must silence output")
        unit.deallocateRenderResources()
        print("Render passed: \(Int(sr)) Hz, peak \(peak)")
    }
}
checkSchema()
try checkRev3Behavior()
checkEnvelope()
try checkRender()
print("Audio regression checks passed")
