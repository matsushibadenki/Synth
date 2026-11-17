// Concatenate the DSP sources, Rev3Regression.swift, then this file; compile with -O.
import Darwin

extension ProphetLikeAudioUnit {
    fileprivate var soundingKeys: Set<Int> {
        Set(voices.filter { $0.active && $0.held }.map(\.note))
    }

    fileprivate var activeVoiceCount: Int { voices.filter(\.active).count }
    fileprivate var heldVoiceCount: Int { voices.filter(\.held).count }
}

private func checkPolyphony() throws {
    var patch = SynthParameters()
    patch.expression.pan = 0
    let probe = try AudioProbe(patch)
    for note in 48..<56 { probe.unit.noteOn(note, velocity: 1) }
    _ = probe.samples(1)
    precondition(probe.unit.soundingKeys == Set(51..<56))
    for note in 48..<56 { probe.unit.noteOff(note) }
    _ = probe.samples(80)
    probe.parameters.set { $0.expression.enabled = true }
    for note in 48..<56 { probe.unit.noteOn(note, velocity: 1) }
    _ = probe.samples(1)
    precondition(probe.unit.soundingKeys == Set(48..<56))
    probe.parameters.set { $0.expression.enabled = false }
    _ = probe.samples(4)
    precondition(probe.unit.heldVoiceCount == 5 && probe.unit.activeVoiceCount == 5)
    probe.parameters.set { $0.expression.enabled = true; $0.unisonMode = true }
    _ = probe.samples(1)
    precondition(probe.unit.heldVoiceCount == 8 && probe.unit.soundingKeys == [48])
}

private func checkStress(rate: Double, frames: UInt32) throws {
    let disableLadder = CommandLine.arguments.contains("--without-ladder")
    let disableFX = CommandLine.arguments.contains("--without-fx")
    let params = SharedSynthParameters(), effects = SharedEffects()
    params.set {
        $0.expression.enabled = true
        $0.expression.ladder = disableLadder ? 0 : 0.6
        $0.expression.oscillatorColor = 0.5
        $0.expression.mixerDrive = 0.5
        $0.expression.pan = 0
        $0.envBRelease = 8
        $0.envARelease = 8
        $0.oscSync = true
        $0.oscAPulse = true
        $0.oscBPulse = true
        $0.polyModOscB = 0.7
        $0.polyModToFreqA = true
        $0.polyModToFilter = true
        $0.polyModToPWA = true
        $0.resonance = 1
    }
    var document = FXDocument.initial
    for kind in [EffectKind.dimension, .sky, .time, .pedal, .ring, .studio] {
        document.nodes[kind.rawValue].settings.enabled = !disableFX
    }
    document.nodes[EffectKind.studio.rawValue].settings.mode = 2
    effects.set(try document.configuration())
    let description = AudioComponentDescription(componentType: kAudioUnitType_Generator,
        componentSubType: 0x50723535, componentManufacturer: 0x53796E74, componentFlags: 0, componentFlagsMask: 0)
    let unit = try ProphetLikeAudioUnit(componentDescription: description, options: [], parameters: params, effects: effects)
    let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
    try unit.outputBusses[0].setFormat(format)
    try unit.allocateRenderResources()
    defer { unit.deallocateRenderResources() }
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    var flags = AudioUnitRenderActionFlags(), timestamp = AudioTimeStamp()
    let render = unit.internalRenderBlock
    let budget = Double(frames) / rate
    var cpuTimes: [Double] = []
    var wallMisses = 0, cpuMisses = 0, silentBlocks = 0, worst = 0.0
    var fingerprint: UInt64 = 14695981039346656037
    for note in 48..<56 { unit.noteOn(note, velocity: 0.8) }
    for block in 0..<1024 {
        if block == 512 {
            precondition(unit.heldVoiceCount == 8)
            for note in 48..<56 { unit.noteOff(note) }
        }
        let start = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        let cpuStart = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
        precondition(render(&flags,&timestamp,frames,0,buffer.mutableAudioBufferList,nil,nil) == noErr)
        let cpu = Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - cpuStart) / 1e9
        let wall = Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - start) / 1e9
        if block >= 20 {
            cpuTimes.append(cpu)
            if wall > budget { wallMisses += 1 }
            if cpu > budget { cpuMisses += 1 }
            worst = max(worst, wall)
            var audible = false
            for channel in 0..<2 {
                for i in 0..<Int(frames) {
                    let sample = buffer.floatChannelData![channel][i]
                    precondition(sample.isFinite)
                    fingerprint = (fingerprint ^ UInt64(sample.bitPattern)) &* 1099511628211
                    audible = audible || abs(sample) > 0.000001
                }
            }
            if !audible { silentBlocks += 1 }
        }
        timestamp.mSampleTime += Double(frames)
    }
    precondition(unit.activeVoiceCount == 8)
    precondition(silentBlocks == 0)
    print("Waveform fingerprint: \(fingerprint)")
    cpuTimes.sort()
    print(String(format:"CPU p50 %.3f ms / p99 %.3f ms", cpuTimes[cpuTimes.count / 2]*1000, cpuTimes[cpuTimes.count*99/100]*1000))
    print(String(format:"%.0f Hz / %d frames: wall misses %d, CPU misses %d, silent blocks %d / 1004, worst %.3f ms, budget %.3f ms",
        rate,Int(frames),wallMisses,cpuMisses,silentBlocks,worst*1000,budget*1000))
}
try checkPolyphony()
print("Classic 5, Extended 8, retirement and 8-voice unison passed")
for rate in [44100.0,48000.0,96000.0] {
    for frames: UInt32 in [64,128] {
        try checkStress(rate: rate, frames: frames)
    }
}
