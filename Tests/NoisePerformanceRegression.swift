// Concatenate after audio sources and Rev3Regression.swift; run without other jobs.
// CPU timings are diagnostic. Compare unchanged fixtures across source snapshots.
func measureNoiseRender() throws {
    func cpuTime() -> Double {
        var time=timespec(); precondition(clock_gettime(CLOCK_THREAD_CPUTIME_ID,&time)==0)
        return Double(time.tv_sec)+Double(time.tv_nsec)*1e-9
    }
    for extended in [false,true] {
        var p=SynthParameters()
        p.oscSync=true; p.oscAPulse=true; p.oscBPulse=true
        p.polyModOscB=1; p.polyModToFreqA=true; p.polyModToFilter=true; p.polyModToPWA=true
        p.resonance=1; p.modWheel=1; p.wheelSourceMix=1
        p.lfoToOscA=false; p.lfoToPWA=true; p.lfoToPWB=true
        p.expression.enabled=extended; p.expression.ladder=1
        p.expression.drive=0.8; p.expression.feedback=0.8
        let probe=try AudioProbe(p)
        for note in [48,55,60,64,67] { probe.unit.noteOn(note,velocity:1) }
        func render(_ blocks: Int) {
            for _ in 0..<blocks {
                precondition(probe.render(&probe.flags,&probe.time,256,0,probe.buffer.mutableAudioBufferList,nil,nil)==noErr)
                probe.time.mSampleTime += 256
            }
        }
        render(30)
        let start=cpuTime()
        render(300)
        let cpu=cpuTime()-start
        for channel in 0..<2 {
            for frame in 0..<256 { precondition(probe.buffer.floatChannelData![channel][frame].isFinite) }
        }
        print(String(format:"noise %@ CPU %.6f seconds, %.2f%% of audio budget",extended ? "extended":"classic",cpu,cpu/(300*256/48000.0)*100))
    }
}
try measureNoiseRender()
