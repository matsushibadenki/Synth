# Input stage and four-pole circuit model

The input transfer now uses a slightly biased `tanh` differential-pair approximation, subtracting idle current and normalizing incremental gain to 0.65. Its bias is a behavioral design value, not a measured component tolerance. This replaces the previous quadratic term after a symmetric clipper.

Each filter stage models a capacitor driven by a bounded differential current:

```
current(v) = v / sqrt(1 + 1.96*v*v)
y[i] = history[i] + g*current(input[i] - y[i])
input[0] = mixer(input) - k*y[3]
input[i] = y[i-1], i > 0
historyNext[i] = 2*y[i] - history[i]
g = tan(pi*cutoff/internalSampleRate)
k = min(4.5, 4.4*max(0,resonance))
```

All four stages and the resonance feedback are solved simultaneously using their sparse Newton Jacobian. The differential current's derivative is included in the solve. This removes frozen per-stage compression coefficients and the previous generic saturator around the linear feedback equation. The implementation uses four-lane SIMD, at most three iterations in the normal engine frequency range, and up to four for extreme normalized cutoffs (`g > 0.25`). Convergence can stop earlier. No render-time allocations or new controls were introduced.

This is an OTA/capacitor behavioral model. It does **not** establish a transistor-level CEM3320 match or hardware-calibrated saturation voltage. Existing cutoff/resonance controls, natural feedback bass loss, oversampling, decimation, UI, SYNTH/05 branding, state schema and Classic 5 / Extended 8 voice allocation are retained. AUv3 uses the same core.

## Validation

`Tests/FilterCircuitRegression.swift` checks the independently evaluated capacitor/current equations during overload, four-pole frequency response, feedback bass loss, driven sample-rate convergence and monotonic biased input saturation. Existing audio and analog suites cover onset behavior, self-oscillation, decimation and sustained tones. Timing evidence is recorded separately from these functional checks; offline blocks cannot prove audible output is dropout-free.

## Final measurements (2026-11-23)

Optimized Swift (`-O`), development Mac. Each offline case renders 1,024 blocks, excludes the first 20, releases all eight notes halfway, and enables eight-second releases, Sync/Poly-Mod, maximum resonance, Ladder 0.6, oscillator color/mixer drive 0.5 and all six FX. Three paired trials alternate order: before/after, after/before, before/after. `--interactive` sets the diagnostic thread to user-interactive QoS only. All compilers and other agent-launched tests had finished before timing. The measurements do not control other applications, thermal state or core scheduling.

| Rate / frames | Before CPU p50 median (ms) | After CPU p50 median (ms) | Change | Before wall misses, each trial | After wall misses, each trial |
|---|---:|---:|---:|---|---|
| 44100 / 64 | 1.209 | 1.430 | +18.3% | 3, 18, 79 | 423, 989, 462 |
| 44100 / 128 | 2.596 | 3.170 | +22.1% | 385, 70, 377 | 975, 899, 595 |
| 48000 / 64 | 1.282 | 1.564 | +22.0% | 979, 269, 312 | 933, 432, 994 |
| 48000 / 128 | 2.667 | 3.088 | +15.8% | 437, 817, 516 | 976, 763, 965 |
| 96000 / 64 | 0.737 | 0.892 | +21.0% | 982, 918, 882 | 1004, 1004, 1004 |
| 96000 / 128 | 1.441 | 1.730 | +20.1% | 984, 849, 863 | 994, 994, 996 |

The final offline medians increased about 16–22%; this is **not** a CPU speedup. Both builds show deadline misses and substantial timing variation. No silent blocks or invalid samples occurred in the six final cases across three trials. `initial-solver/` retains exploratory normal/interactive-priority runs before reciprocal reuse and the residual-based early stop; those runs are not final performance claims.

### Actual muted output

| 96 kHz device buffer | Measured callbacks | Core wall p95 / max (ms) | Budget (ms) | Wall / CPU overruns | Source timestamp gaps |
|---|---:|---:|---:|---|---:|
| 64 | 17980 | 0.365 / 0.425 | 0.667 | 0 / 0 | 0 |
| 128 | 8980 | 0.740 / 0.823 | 1.333 | 0 / 0 | 0 |

Each device capture lasted 12 seconds, including a six-second held chord followed by six seconds of the eight-second release. The kernel renders normally with master zero, so DSP/FX work runs but the output is muted. The default device was verified at 96 kHz with the requested 64/128 frame size, then its original 96 kHz / 512 frames were restored after each test (see logs). Source timing excludes downstream mixer/driver delivery and does not establish audible dropout-free playback, long-duration UI/GPU robustness or physical iPhone performance.

### Sound-model checks

The final nonlinear equation residual was approximately 1.3e-7 in the tested normal band and below 1e-6 at extreme cutoff, including abrupt cutoff changes, overload and feedback clamp. The driven-response gain across 192/384/768 kHz internal rates varied by about 0.005%. Four-pole rolloff, 0.65 small-signal mixer gain, zero idle output and natural bass loss passed. The initial solver also passed the full analog suite, including bounded self-oscillation and 30-second sustain cases; its log is retained separately. Final audio, expression, velocity and AU host regressions are recorded alongside this report.

The nonlinear operating level changes timbre and high-resonance level. Initial-model self-oscillation RMS was about 0.256 at 176.4/192 kHz internal rates. Existing patch values remain loadable, but exact old waveform/level identity is not promised. Hardware-recording calibration and listening A/B remain pending.
