// Concatenate after Rev3Parameters, EffectsGraph, EffectsDSP, ProphetCore and
// Rev3Regression. Compile with the normal Debug flags (-Onone -g -O).
// No audio device is started. Timing is diagnostic, not a universal host guarantee.
import Dispatch

extension ProphetLikeAudioUnit {
    fileprivate func holdEventQueue(locked: DispatchSemaphore, release: DispatchSemaphore, done: DispatchSemaphore) {
        eventLock.lock()
        locked.signal()
        _ = release.wait(timeout:.now()+2)
        eventLock.unlock()
        done.signal()
    }
}

func checkHeldKeyStorage() {
    var keys=HeldMIDIKeys(), expected=Set<Int>()
    for note in [0,63,64,127,36,96] {
        keys.insert(note); expected.insert(note)
        precondition(keys.min()==expected.min())
    }
    for note in 0..<128 { precondition(keys.contains(note)==expected.contains(note)) }
    for note in expected.sorted() {
        keys.remove(note); expected.remove(note)
        precondition(keys.min()==expected.min())
    }
    precondition(keys.min()==nil)
    for note in 0..<128 { keys.insert(note) }
    keys.removeAll()
    precondition((0..<128).allSatisfy { !keys.contains($0) })
    print("Held-key bitset: full MIDI range and low-note priority passed")
}

func checkRenderNeverWaitsForUI() throws {
    var patch=SynthParameters(); patch.releaseEnabled=false
    let probe=try AudioProbe(patch)
    probe.unit.noteOn(60,velocity:1); _=probe.samples(10)
    let locked=DispatchSemaphore(value:0), release=DispatchSemaphore(value:0), done=DispatchSemaphore(value:0)
    DispatchQueue.global().async {
        probe.parameters.set { p in
            p.masterVolume=0
            locked.signal()
            _ = release.wait(timeout:.now()+2)
        }
        done.signal()
    }
    precondition(locked.wait(timeout:.now()+2) == .success)
    let start=Date.timeIntervalSinceReferenceDate
    let held=probe.samples(1)
    let elapsed=Date.timeIntervalSinceReferenceDate-start
    release.signal()
    precondition(done.wait(timeout:.now()+2) == .success)
    precondition(elapsed<0.25,"Render must not wait for a UI parameter edit")
    precondition(rms(held)>0.001,"Lock contention keeps rendering the last valid patch")
    precondition(rms(probe.samples(1))==0,"The newly published patch applies on the next available block")
    probe.parameters.set { $0.masterVolume=0.8 }; _=probe.samples(1)

    // A release remains pending if the UI holds the event mutex during a block.
    probe.unit.noteOff(60)
    DispatchQueue.global().async { probe.unit.holdEventQueue(locked:locked,release:release,done:done) }
    precondition(locked.wait(timeout:.now()+2) == .success)
    let eventStart=Date.timeIntervalSinceReferenceDate
    let continued=probe.samples(1)
    let eventElapsed=Date.timeIntervalSinceReferenceDate-eventStart
    release.signal()
    precondition(done.wait(timeout:.now()+2) == .success)
    precondition(eventElapsed<0.25,"Render must not wait for the MIDI/UI queue")
    precondition(rms(continued)>0.001)
    precondition(rms(Array(probe.samples(30).suffix(256)))<0.00001,"Deferred note-off must be delivered")

    probe.unit.noteOn(60,velocity:1); _=probe.samples(10)
    for event in 0..<600 {
        let note=event%128
        if event%2==0 { probe.unit.noteOn(note,velocity:1) } else { probe.unit.noteOff(note) }
    }
    precondition(rms(Array(probe.samples(30).suffix(256)))<0.00001,"Queue overflow must not leave a stuck note")
    probe.unit.noteOn(67,velocity:1)
    precondition(rms(probe.samples(10))>0.001,"Queue recovers after overflow")
    print("Render contention: parameters and note events never wait; deferred release and overflow recovery passed")
}

func measureRenderDeadlines() throws {
    let params=SharedSynthParameters(), effects=SharedEffects()
    ProphetLikeAudioUnit.sharedParameters=params; ProphetLikeAudioUnit.sharedEffects=effects
    params.set {
        $0.unisonMode=true; $0.oscSync=true; $0.polyModOscB=0.7
        $0.polyModToFreqA=true; $0.polyModToFilter=true; $0.oscAPulse=true
        $0.oscBTriangle=true; $0.oscBPulse=true; $0.resonance=1
    }
    let unit=try ProphetLikeAudioUnit(componentDescription:AudioComponentDescription(
        componentType:kAudioUnitType_Generator,componentSubType:0x50723535,
        componentManufacturer:0x53796E74,componentFlags:0,componentFlagsMask:0))
    func cpuSeconds() -> Double {
        var t=timespec(); precondition(clock_gettime(CLOCK_THREAD_CPUTIME_ID,&t)==0)
        return Double(t.tv_sec)+Double(t.tv_nsec)*1e-9
    }
    for rate in [44100.0,48000.0,96000.0] {
        try unit.outputBusses[0].setFormat(AVAudioFormat(standardFormatWithSampleRate:rate,channels:2)!)
        try unit.allocateRenderResources()
        unit.noteOn(60,velocity:1)
        let buffer=AVAudioPCMBuffer(pcmFormat:unit.outputBusses[0].format,frameCapacity:256)!
        let render=unit.internalRenderBlock
        var flags=AudioUnitRenderActionFlags(), timestamp=AudioTimeStamp()
        for enabled in [false,true] {
            var document=FXDocument.initial
            for index in 1...6 { document.nodes[index].settings.enabled=enabled }
            effects.set(try document.configuration())
            for frames: AUAudioFrameCount in [64,128,256] {
                var times=[Double](), cpu=[Double]()
                for block in 0..<100 {
                    let start=Date.timeIntervalSinceReferenceDate, cpuStart=cpuSeconds()
                    let status=render(&flags,&timestamp,frames,0,buffer.mutableAudioBufferList,nil,nil)
                    let elapsed=Date.timeIntervalSinceReferenceDate-start, spent=cpuSeconds()-cpuStart
                    precondition(status==noErr)
                    if block>=20 { times.append(elapsed); cpu.append(spent) }
                    timestamp.mSampleTime += Double(frames)
                    for channel in 0..<2 {
                        precondition((0..<Int(frames)).allSatisfy { buffer.floatChannelData![channel][$0].isFinite })
                    }
                }
                times.sort(); cpu.sort()
                let budget=Double(frames)/rate, p95=times[76], cpu95=cpu[76]
                print(String(format:"%.0f Hz / %d frames / FX %@: deadline %.2f ms; wall p95 %.2f ms; CPU p95 %.2f ms; misses %d/80",
                    rate,Int(frames),enabled ? "on":"off",budget*1000,p95*1000,cpu95*1000,times.filter { $0>budget }.count))
            }
        }
        unit.deallocateRenderResources()
    }
}

checkHeldKeyStorage()
try checkRenderNeverWaitsForUI()
try measureRenderDeadlines()
print("Realtime regression checks passed")
