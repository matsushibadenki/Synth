96 kHz Extended 8-voice timing, 2026-11-14

🟢 [Done] The offline workload uses eight notes, an eight-second release, Sync, Poly-Mod, maximum resonance, 60% ladder blend, oscillator color, mixer drive and all six FX. Build the concatenated sources listed in Tests/ExtendedPolyphonyRegression.swift using swiftc -O. The optional --without-ladder and --without-fx runs isolate their contributions.

At 96 kHz / 64 frames, the baseline CPU median was 0.327 ms. Without ladder it was 0.232 ms, and without FX it was 0.278 ms. The paired optimized runs measured 0.322 ms. Baseline and optimized waveform fingerprints matched across all six conditions in both passes. Baseline 96 kHz / 64-frame wall misses were 11 and 0. The optimized passes each had zero. One optimized 96 kHz / 128-frame run still had 23 wall misses, including 22 CPU misses, while the other had zero. The source of this run-to-run timing variation remains open.

🟢 [Done] A 96 kHz muted hardware-backed AVAudioEngine run at each buffer size checked AU kernel timing and consecutive sample timestamps. Each ran for 12 seconds and released the chord halfway through. The device buffer returned to 512 frames after each run.

| Buffer | Measured callbacks | Maximum kernel wall time | Budget | Misses / timestamp gaps |
| --- | ---: | ---: | ---: | ---: |
| 64 | 17,980 | 0.434 ms | 0.667 ms | 0 / 0 |
| 128 | 8,980 | 0.790 ms | 1.333 ms | 0 / 0 |

⭕️ [Pending] Audible dropout testing, downstream mixer/driver underrun counters, repeated long tests under concurrent UI load and physical iPhone testing.
