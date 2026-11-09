# Original Prophet-5 Rev3 parameter specification

この仕様は以前のRev2/Rev3混在案を置き換えます。ユーザー指定のオリジナルRev3に固定します。
This specification replaces the earlier mixed Rev2/Rev3 proposal. The target is original Rev3.
本规范取代此前混合Rev2／Rev3的方案，目标固定为原版Rev3。

## Canonical controls

| Section | Continuous controls | Binary controls |
|---|---|---|
| Poly-Mod | Filter Env Amount, Osc B Amount | Freq A, PW A, Filter |
| LFO | Frequency | Saw, Triangle, Square |
| Wheel-Mod | Source Mix (LFO ↔ pink noise) | Freq A, Freq B, PW A, PW B, Filter |
| Oscillator A | Frequency, Pulse Width | Saw, Pulse, Sync |
| Oscillator B | Frequency, Fine, Pulse Width | Saw, Triangle, Pulse, Lo Freq, Keyboard |
| Mixer | Osc A, Osc B, white Noise | — |
| Filter | Cutoff, Resonance, Envelope Amount, Attack, Decay, Sustain, Release | Keyboard |
| Amplifier | Attack, Decay, Sustain, Release | — |
| Performance (stored) | Glide | Release, Unison |
| **Stored total** | **24** | **22** |

Non-programmed controls: Master Tune and Volume (two knobs), Pitch and Mod (two wheels), Tune command and A-440 toggle. Program selection/storage and power are application operations and do not add voice parameters. The compact keyboard is a playing aid, not a reproduction of the physical 61-key keyboard. The programmer uses modern recall/record controls; cassette transport, scale-program mode and rear-panel electrical interfaces are outside this voice-parameter implementation.

非保存操作はMaster Tune／Volume、Pitch／Mod、Tune／A-440。メモリー・電源操作とミニ鍵盤を音色パラメーター数へ含めません。カセット、音階プログラム、背面電気インターフェイスは本実装の対象外です。
非音色保存控制为总调音／音量、弯音／调制轮、Tune／A-440。存储、电源和迷你键盘不计入参数数目。磁带、音阶程序及背面电气接口不在此实现范围内。

## Signal and control rules

- Five voices, two oscillators per voice, white noise → mono mixer → four-pole low-pass → amplifier ADSR. The source is duplicated to two host channels before the optional stereo effects graph; master volume follows the effects.
- A: saw and pulse independently enabled and summed at full level. B: saw, triangle and pulse independently summed. No enabled shape means no oscillator audio. B's phase still clocks sync when B shapes are off.
- Frequency knobs use 49 semitone positions across four octaves (software display −24…+24 st). B Fine raises pitch 0…100 cents. Pulse width 1…99%. B Lo Freq is approximately 0.4…30Hz with Keyboard off.
- LFO 0.04…20Hz; three independent full-level shapes. Wheel-Mod continuously mixes LFO and pink noise; Mod wheel sets the depth to all enabled destinations.
- Poly-Mod first sums the filter-envelope and oscillator-B source amounts, then sends the same source to each enabled destination. B's mixer level does not attenuate Poly-Mod.
- Filter Keyboard is a binary one-volt-per-octave equivalent. Velocity and aftertouch do not modulate sound. Rev4 Vintage and filter-revision selection are absent.
- ADSR time controls span approximately 1ms…30s. Release off substitutes a short anti-click release for both envelopes.
- Unison assigns all five voices to the lowest held note. Releasing it returns to the next held note. Glide only operates in Unison. Pitch wheel spans approximately a fifth in either direction.
- Per-card offset/wander and filter saturation are internal fixed model behavior, not additional user parameters.
- Audio commands are transferred from UI to the render callback; UI does not mutate voice arrays.

## Programs and compatibility

`Rev3Program` serializes exactly 24 numeric values and 22 booleans, identified by stable IDs. Decode rejects missing/extra keys and non-finite values, clamps supported ranges and quantizes oscillator frequency. Recall preserves volume, tuning, wheels, A-440 and the Tune command counter.

Rev3.3 memory arrangement: three files × five banks × eight programs. Early Rev3's 40 memories are not conflated with Rev3.3's 120. No claim of factory-preset contents or hardware cassette-format compatibility.

New keys: `synth.rev3.v1.<file>.<bank>.<program>`. Legacy keys `synth.preset.A/B.<1…40>` remain intact. With no new program present, file 1/2 reads the corresponding A/B slot. Supported values migrate; unsupported Sub/Drive/Drift/SSM/velocity settings are discarded. Legacy A triangle approximates saw; random LFO approximates pink noise. Migration is explicitly reported in the UI. Users record converted sounds into the separate format.

## UI and verification

🟢 [Done] One shared definition drives the 26 knobs, 22 switches, localized native editor and stored programs. Metal meshes, label positions and hit areas share their layout math. One/two/three columns preserve narrow-screen layout. Outer horizontal padding is 16pt and only the background ignores safe areas.

🟢 [Done] Voice-count/schema regression, program round trip, independent waveforms, velocity independence, low-note unison, release switch, wheel pink noise, Poly-Mod PWM and reference-tone tests. Existing filter stress tests run at 44.1/48/96kHz. Metal tests cover five widths.

🟠 [Next] Reduce residual aliasing at extreme sync/audio-rate modulation depths; profile on physical iPhones.

🔴 [Later] Measured hardware calibration for envelope, glide, oscillator and filter behavior.

⭕️ [Pending] Physical iPhone touch/load testing and direct comparison with a hardware Rev3. Circuit fidelity and exact calibrated knob response are not established by the software regression tests.

## Reference

Sequential Circuits, **Model 1000 Prophet-5 Operation Manual, CM1000D, February 1982**: section 2 for controls, pp. 6-5–6-6 for 24 pots / 22 switch bits, section 1-3 for Rev3.3 program organization.
[Original manual scan](https://synthfool.com/docs/SequentialCircuits/Prophet_Series/Sequential%20Circuits%20Prophet%205%20Owners%20Manual.pdf).

## Stereo effects host (2026-10-21)

The Rev3 parameter schema remains exactly 46 stored settings. The optional post-synth FX document is independent and contains six effect processors plus source, MIX A/B and output. Initial order matches the requested family sequence; all effects initially bypass. FX document schema version 1 validates the complete fixed node set, mode/property ranges, single-input cardinality, port direction, finite placement and DAG order before publication to audio. A failed batch preserves the original document. Port selection, context-menu disconnection, node dragging, series/parallel presets and bounded undo/redo share this command path.

UNGE core model/command code was ported to Swift under MIT; the unmodified Rust snapshots and adapter boundaries are recorded in `Vendor/UNGE/INTEGRATION.md`. The async scheduler and Rust/wgpu renderer are not used in this native SwiftUI host. DSP uses fixed-capacity stereo delay lines, a damped eight-line Householder FDN with optional octave feedback, modulated delays, ring modulation and a 12-second RAM looper. Buffers are allocated during render-resource preparation; audio accepts validated block snapshots with a nonblocking try-lock. Graph evaluation is bounded to nine nodes. Disconnected input is zero, fan-out is supported, and parallel fan-in goes through MIX A/B gains. OUT disconnection produces silence after the brief topology transition.

Continuous controls and bypass slew; topology changes ramp for 10ms. The output has a hard safety bound before master volume. The looper's commands are transient, independent of undo/persistence; power stop clears its command/state. Loop audio is not serialized. The UI's file/bank/program still recalls only Rev3 parameters. FX settings and three pedal memories use separate versioned UserDefaults keys. These are independent inspired algorithms, not factory algorithm replicas or calibrated hardware emulations.

🟢 [Done] Modes and feedback at 44.1/48/96kHz, stereo tails, bypass identity, parallel routing gains, invalid-edit rollback, undo/redo, serialization, loop record/play/overdub/stop/clear/reverse/half-speed and actual AudioUnit integration/mute/disconnect tests.
🟢 [Done] Native macOS port connection, undo and parallel preset; five rendered widths (288/343/382/736/1056pt) and iOS type checking.
🟠 [Next] Residual aliasing at extreme modulation depths and physical iPhone profiling.
🔴 [Later] Multiple instances, portable FX preset files and persistent long loops.
⭕️ [Pending] Physical iPhone load/dropout/touch and hardware sound comparisons.

## Shared performance panel

🟢 [Done] `SharedPerformancePanel` lives outside the selected-tab subtree and groups the nameplate/header utilities, PROGRAMMER, a dedicated Metal keyboard and Pitch/Mod wheels. The synth surface omits its former embedded keyboard, and FX tabs no longer substitute an eight-note fallback. All tabs expose the same thirteen notes and program state. Tab selection no longer sends all-notes-off; keyboard release still occurs on gesture end, scene deactivation, power stop, or panel disappearance. Short viewports scroll the common panel inside its bounded area; normal viewports keep it fixed above the independently scrolling workspace.

🟢 [Done] `PanelLayout` separates control-only and keyboard-only Metal presentations. The mesh cache includes the full layout; six keyboard widths test bounds and switching presentations with otherwise identical renderer inputs. Native macOS verifies common controls survive switching to SKY / TIME; iOS type checking and five common-panel layout widths pass.
⭕️ [Pending] Physical iPhone multitouch and orientation validation.

🟢 [Done] Compact common-panel revision: reduced header spacing, compact programmer with actions in the spare header space on narrow screens, and a desktop side-by-side programmer/720pt keyboard layout. Desktop program keys reflow to 4×2 with 38×32pt faces; narrow views retain the original eight-column sizing. Keyboard geometry is unchanged. Measured common-panel heights at widths 288/343/382/736/1088pt are 327/328/342/275/226pt (previously 388/407/421/323/326pt).

## Shared master volume

🟢 [Done] Master Volume (canonical knob index 25) is hosted by `MasterVolumeControl` in the persistent header. All tabs bind directly to the existing `SynthParameters.masterVolume` and the existing post-FX volume stage. Synth mesh, label, gesture and expanded-editor entries omit this moved control; Glide and Master Tune recenter inside PERFORMANCE. No voice-program field or DSP behavior is added.

🟢 [Done] The standalone Metal presentation reuses the exact knob profile. Its viewport is 1.28 × the synth's projected world-unit scale, so the physical knob diameter matches at each adaptive column breakpoint. Five-width projection tests and GPU needle changes pass. macOS verifies volume increment from SKY / TIME and retention in RING; iOS type checking passes. Narrow 288pt panel height remains 327pt; the additional full-size knob increases wide header height to fit its existing diameter.
⭕️ [Pending] Physical iPhone touch validation.

## Analog voice refinement (2026-10-22)

🟢 [Done] Rev3-specific behavior was refined without adding patch controls or changing the 24-pot/22-switch program format. The persistent master volume remains after FX. All ten VCO phases now advance even with closed gates; VCO/LFO phase accumulators use Double precision to preserve low-frequency timing at the oversampled rate; no note-on phase reset is introduced. Five fixed card identities retain their own component offsets across voice allocations and patch recalls.

- As of 2026-10-25, incidental A/B pitch variation is shared within each card. Two independent 3–7.5-second trajectories are averaged at ±0.04 cent total, two 7–21-second trajectories at ±0.08 cent total, plus a thermal component at ±0.45 cent over 11–30 seconds. Initial bias is bounded by ±0.10 cent and shared tracking error by ±0.025 cent/octave. Total pre-Tune pitch offset remains bounded by ±0.67 cent excluding tracking error. Cards retain independent seeds, but equal-frequency A/B oscillators receive identical incidental corrections. This is an intentional stability tradeoff, **not a measured Prophet-5 tolerance specification**.
- Tune captures the current pitch bias of each card and slews the shared A/B correction over 60 ms. It preserves oscillator phases and the ongoing random trajectories. This is a simplified correction, not the hardware's ten-C measurement table or its tuning sequence. Drift can grow again after tuning.
- Card differences include up to ±0.035 octave filter offset, ±1.2% resonance gain, ±4.5% independent ADSR times, ±1.4% VCA gain and ±0.18 percentage-point PWM offsets. ADSRs retain exponential charge/discharge and retrigger from the present capacitor level. `expm1` coefficients preserve accuracy at long times/high internal rates; coefficients are prepared per block, not per sample.
- Glide now slews logarithmic pitch CV instead of linear Hz. Double-precision capacitor state avoids long glides stalling at the oversampled rate. Main cutoff/resonance, mixer levels, pulse widths and filter-envelope amount slew over 4 ms. Envelopes and audio-rate modulation remain at the internal audio rate.
- The oscillator/Poly-Mod/mixer/nonlinear four-pole filter/VCA path runs at 176.4/192 kHz for 44.1/48/88.2/96 kHz hosts (4× or 2×). A Blackman-windowed sinc FIR removes ultrasonic content before host-rate FX. FIR group delay is 32 host samples (0.67 ms at 48 kHz), reported by the AudioUnit. Rates above 96 kHz use the host rate directly. A-440 is generated directly at the host rate.
- Filter feedback is solved with three bounded-work Newton iterations including saturation, followed by the four TPT poles. It retains resonance-related bass loss and can self-oscillate with no oscillator signal. A 5 Hz AC-coupling stage removes PWM DC before the final VCA. White-noise density and pinking coefficients account for the internal rate.

🟢 [Done] `AnalogRegression.swift` verifies bounded/smooth independent drift, elapsed-time invariance, Tune without restarting drift, per-card ADSR timings, retrigger continuity, high-rate glide convergence, four-pole response, bounded self-oscillation, FIR rejection and actual AudioUnit free-running phases. Existing Rev3/audio tests pass at 44.1/48/96 kHz, including strong modulation, maximum resonance, release silence, exact post-FX mute and the unchanged schema.

Measured on this development Mac with an optimized offline render: five voices with Sync, multiple waves, Poly-Mod and maximum resonance consumed about 31% render-thread CPU and 34% wall-time budget in the measured run. This is not a physical iPhone or live audio dropout measurement. Per-block buffer access avoids repeatedly copying the expanded voice state; buffers/taps are allocated when render resources are prepared.

The dry demonstration contains brass, unison bass, Sync lead and Poly-Mod bell, with no FX or normalization. `AnalogDemo.swift` reproduces it and a sustained high-note Sync probe. For that one probe at 48 kHz, the power outside ±20 Hz windows around harmonic peaks (100 Hz–20 kHz analysis band, Hann window, 131072 samples) changed from −23.64 dB to −37.32 dB relative to harmonic power, a 13.68 dB reduction. This metric includes modulation sidebands and does not isolate all aliasing. `CompareSyncSpectrum.py` reproduces the analysis using NumPy/SciPy. Full suppression at extreme settings is not claimed.

🟠 [Next] Further sync-discontinuity correction and residual alias suppression at extreme Poly-Mod depths; mobile CPU profiling.
🔴 [Later] Calibrate oscillator tracking, envelope curves and mixer/filter saturation against matched dry recordings and settings from an actual Rev3.
⭕️ [Pending] Physical Rev3 A/B listening and iPhone audio-load/dropout tests. No claim of indistinguishability or measured circuit fidelity.

Primary architectural reference: Sequential Circuits **TM1000D.2 (October 1981), sections 2-4 to 2-7 and 2-13**, covering CEM3340 VCOs, CEM3320 VCF, CEM3310 envelopes and oscillator tuning: [original service-manual scan](https://www.synfo.nl/servicemanuals/Sequential/SEQUENTIAL_PROPHET-5-REV3_SERVICE_MANUAL.pdf), [searchable scan transcription](https://device.report/m/8a61dcdfae3351f3408202a0617fe6219a8c78476f624f8b913dd3796b173728). Numeric drift/tolerance choices above are implementation choices, not values taken from that manual.

## Realtime crackle correction (2026-10-22)

🟢 [Done] The reported symptom was intermittent clicks/crackle while playing. A 48 kHz, 256-frame offline probe reproduced a deadline problem in the previous unoptimized Debug configuration: a 5.33 ms block deadline versus 19.68 ms median / 22.90 ms p95 processing time, with 50/50 blocks late. With the new normal Debug flags (`-Onone -O -g`, effective optimization `-O`), the same probe measured 1.43 ms median / 2.03 ms p95, with 0/50 late blocks. This establishes a reproducible software cause; it is not a capture of the user's live device output.

`Package.swift` now enables optimization for Debug as well as Release, so Xcode's ordinary Run path does not require the user to discover a special Release setting. Symbols remain; optimized stepping/variable inspection is a tradeoff. This applies to the standalone executable target. The analog synthesis coefficients, oversampling, drift, modulation depths, saved programs and UI controls were not reduced or reset.

The audio callback takes a nonblocking synth-parameter snapshot, retaining the last valid patch if UI publication is busy. Note events use a preallocated 256-entry queue and separate preallocated render scratch storage. A busy event mutex defers consumption to a later block while continuing audio. MIDI held-note state uses two UInt64 bitsets instead of Set insertion/sorting in render. Queue overflow triggers a release of all held voices and clears the flooded batch, then accepts new events; this favors avoiding stuck notes over retaining an unbounded event burst. These changes remove explicit parameter/event mutex waits and event/held-key collection growth; they do not claim that every framework call is allocation-free.

🟢 [Done] `RealtimeRegression.swift` deliberately holds both UI locks while audio renders, verifies deferred publication/note-off delivery, queue-overflow recovery and the full MIDI range. Its timing matrix covers 44.1/48/96 kHz, 64/128/256-frame blocks, five voices with Sync/Poly-Mod/resonance, and all six FX both bypassed and enabled. Timing results are host diagnostics, not portable pass thresholds.
The 18-case timing matrix recorded CPU p95 below the deadline in every case. At 48 kHz with all six FX, 256-frame CPU p95 was 1.91 ms against 5.33 ms. Across 1440 measured blocks there were three wall-clock overruns (44.1 kHz / 256 frames / all FX); this offline thread is not a live audio workgroup, and host scheduling remains outside the DSP measurement. These outliers are retained rather than described as zero live dropouts. Audio/analog/schema regressions, the normal Debug app build and iOS type checking pass.

⭕️ [Pending] Confirm the user's live playback after rebuilding/restarting, and test physical iPhone audio deadlines under UI/GPU load.


## Dry sustain beating adjustment (2026-10-22)

🟢 [Done] The user also hears tremolo with FX bypassed and one held note. An offline comparison at MIDI 72 / 48 kHz found a 4.39 dB 5–95% RMS span for the previous default dual-saw patch versus 0.042 dB with OSC B muted. Even with Fine=0, the previous independent pitch wander produced 4.44 dB of span. These results isolate oscillator interference in these patches, not a recording of the user's current saved program.

The default OSC B FINE is now 0 rather than 5 cents. Independent initial tuning offsets, tracking error and random wander are smaller; the faster trajectory now takes 3–7.5 seconds instead of 0.7–2.7. The shared slow thermal component, free-running oscillator phases, VCA/envelope behavior, modulation routes and manual Fine range remain intact. No gain normalization or phase locking is used. Saved programs retain their explicit Fine settings; set OSC B FINE to 0 when evaluating an existing patch. New defaults do not silently migrate saved programs.

For the same default-patch MIDI 72 probe, the RMS span becomes 1.75 dB and the largest adjacent 80 ms level change becomes 0.085 dB (previously 2.30 dB). Measurement discards the first 200 × 256 frames, then uses 100 non-overlapping 3840-sample RMS windows, totaling 8 seconds. This describes reduced rapid pumping; slower amplitude changes from free-running oscillator interference still exist, especially with intentional detune, high notes or unison. The old demo and spectral comparison above are historical pre-adjustment artifacts.

`AnalogRegression.swift` covers neutral-Fine sustain at MIDI 48/72/84, an isolated oscillator, saved Fine=5 recall and preserved intentional beating, plus relative pitch bounds across all five cards. Parameter counts and ranges remain unchanged. The normal Debug build and schema/audio/analog/realtime functional regressions pass. MIDI 84 still has a 4.73 dB span over eight seconds, but its maximum adjacent 80 ms change is 0.127 dB; the change slows interference rather than eliminating it.

The accompanying offline timing run had substantial host scheduling delays (48 kHz / 256 frames / all FX: CPU p95 2.26 ms, wall p95 35.28 ms, 17/80 late blocks). No claim of dropout-free live playback is made from this run; the realtime test reports timing diagnostically and its functional assertions check lock contention, event delivery and overflow recovery.

⭕️ [Pending] Listening confirmation on the user's actual patch and audio device; physical Rev3 calibration remains pending.


## Sustained-note stability (2026-10-25)

🟢 [Done] The previous fix slowed beating but did not bound its long-term depth: even tiny independent A/B frequency errors integrate into large relative-phase changes. At Fine=0 the previous default patch still measured 4.68 dB (MIDI 72) and 4.74 dB (MIDI 84) P5–95 RMS span during a 30-second offline hold at 48 kHz after two seconds of settling.

Incidental tuning bias, tracking error, drift and Tune correction now use one shared value per voice card. Fast/slow trajectory pairs are averaged; slow thermal motion stays at its existing depth. Both VCOs use the same pitch-correction expression, so identical nominal frequencies remain matched. Their phases still run freely, start separately, and never reset on note-on or Tune. No compressor, automatic gain correction or amplitude LFO is added. This deliberately sacrifices independent A/B tuning imperfections to make neutral patches stable, while preserving independent motion across five cards, component coloration, all modulation routes and explicit Fine detuning. The random-draw order is retained so the existing filter/ADSR/VCA/PWM identities do not change.

Regression tests now assert the complete sustained RMS span, not just change between adjacent short windows. They cover 30-second holds on all five card identities, low/middle/high notes, idle time before the note and a Tune operation midway through the hold. An actual-render relative-phase assertion checks that equal-frequency A/B do not accumulate incidental detune. Existing checks retain deliberate Fine=5 beating, saved-program recall, independent card motion, free-running phases, envelopes, resonance, Sync and Poly-Mod.

🟢 [Done] Normal Debug build and schema/audio/analog regressions pass. At 48 kHz, the 30-second holds with 80 ms RMS windows produced P5–95 spans of 0.207 dB (MIDI 48), 0.034 dB (MIDI 72) and 0.022 dB (MIDI 84) on card 1. All five cards at MIDI 72 measured 0.030–0.037 dB; their full min–max spans were below 0.041 dB. These tests include 200 idle blocks, 375 settling blocks, 375 measurement windows and Tune at window 187. Short-window low-note RMS variation includes window/cycle alignment. The unchanged eight-second MIDI 84 probe measured 0.021 dB, versus 4.73 dB on 2026-10-22. Explicit Fine=5 still produced 4.52 dB of span in its eight-second test.

⭕️ [Pending] Listening confirmation with the user's patch/device and physical Rev3 calibration. Intentional Fine/modulation/unison beating remains possible; this change does not flatten all sounds.


## Instrument reference presets (2026-10-25)

🟢 [Done] `InstrumentPreset` defines Piano and Violin as ordinary 24-pot/22-switch Rev3 programs. They are separate built-ins, never installed over user slots. PROGRAMMER's existing recall icon now opens a menu containing saved-program recall and localized Piano/Violin choices; dimensions and button count are unchanged, and the shared menu stays available on every effect tab. Recall updates the status label with the instrument name, releases held engine notes, applies the program and neutralizes pitch/mod wheels plus the reference tone. Master volume/tuning and Tune serial are preserved. Record remains the explicit way to save into the selected user slot. FX settings and routing are retained; bypass FX for a dry comparison.

Piano combines a triangle body with a narrow pulse one octave above, a short filter transient and zero-sustain amplitude decay. Violin combines saw harmonics with a quieter triangle body, gradual attack, sustained level and short release. Fine is zero; noise/unison/Poly-Mod are off. Violin's mod wheel can add matched A/B vibrato, but loads at zero. These are original subtractive synth interpretations rather than acoustic samples or copied factory programs.

🟢 [Done] Debug build, iOS simulator type checking and offline preset tests pass: canonical schema round-trip, neutralized performance offsets, preserved master controls, piano held-note decay, violin swell, sustain and release. The held violin measured 0.050 dB P5–95 RMS span in the eight-second A4 test. Dry demos export without normalization at 48 kHz: Piano 10.8 seconds (single notes and chord), Violin 13.76 seconds (phrase and long A4). UI accessibility verified the localized preset menu; further UI reads timed out after choosing Piano.

⭕️ [Pending] End-to-end native selection/status inspection and narrow-device visual inspection, due to computer-use timeouts. Physical-device listening remains pending.


## RING antialiasing milestone (2026-11-06)

🟢 [Done] RING saturation/carrier multiplication now use fixed 4x polyphase interpolation and FIR decimation (97-tap normalized Blackman-windowed sinc, cutoff 0.1125 cycles per oversampled frame). Storage is prepared before rendering; no per-sample allocation. Latency is 24 host frames. Engaged dry/wet paths align; bypass crossfades to undelayed input and becomes sample-exact once settled. Parallel graph branches do not yet implement automatic delay compensation. Existing controls, persistence and other FX algorithms retain their interfaces.

🟢 [Done] `Tests/RingAntialiasRegression.swift` compares the old 1x saturation/multiplication against 4x at normalized high-carrier and high-drive probes, checks >20dB selected alias reduction (observed 74.2/76.2dB), retained wanted sideband, channel independence, impulse alignment and exact settled bypass. These selected probes are not a universal alias rejection specification. Existing FX and AU integration regressions pass. Development-Mac realtime tests met every measured deadline across 44.1/48/96kHz, 64/128/256-frame blocks and FX on/off (1,440 post-warmup blocks).

🟠 [Next] Fast-delay modulation and extreme Sync/Poly-Mod antialiasing, with quality/CPU comparisons.
🔴 [Later] Automatic delay compensation for parallel graph paths; portable FX preset files and persistent loop storage.
⭕️ [Pending] Physical iPhone deadline/load/dropout and listening checks; hardware comparisons.


## Fast modulation quality milestone (2026-11-06)

🟢 [Done] TIME/PEDAL delay and STUDIO echo reads use 32-tap Blackman-windowed sinc kernels, with 256 fractional phases and read-speed banks at 1/1.5/2/3/4/6/8/12/24/48x. Phase and speed banks interpolate continuously. The speed estimate is `abs(1 - deltaDelay)`; cutoffs decrease from 0.45 cycles/source sample as read speed increases. Reverse grains track each read head independently, excluding zero-window-gain wrap seeks from their speed estimate. Reads reserve 17 samples on the short side and 18 on the long side for support; no additional fixed group delay is introduced around the requested read position. Finite kernel length and bounded speed banks leave residual aliasing for extreme conditions. Tables are prepared before rendering. Other fractional-delay uses retain their original interpolation.

🟢 [Done] `SyncEdgeOscillator` corrects saw/pulse wraps, pulse edges and partial-cycle reset jumps with a fractional two-sample polynomial BLEP, using one internal-sample history for sync OSC A. Non-sync waveform evaluation remains the original polyBLEP path. The full voice path oversamples by 8x through 48kHz, 4x through 96kHz and 2x above, with the existing windowed-sinc decimator and 32-host-frame FIR latency. This increases CPU cost, and neither finite-rate oversampling nor the edge correction makes all deep modulation bandlimited.

🟢 [Done] `Tests/ModulationQualityRegression.swift` measures a fixed 2x delay-read alias probe (~55.9dB reduction), retained low band, normalized kernel gain over phase/speed banks, sync saw/pulse/sum magnitude-spectrum error against a 64x reference (~97–98% lower), and synthetic deep exponential modulation rate error (~65% lower at 8x versus 4x). These are algorithm probes, not hardware measurements or a universal sound-quality metric. Full FX, AU integration, voice/analog regressions and all-card long sustains passed.

🟠 [Next] Reduce CPU overhead; evaluate residual aliasing under moving PWM and more extreme modulation.
⭕️ [Pending] Physical iPhone CPU/GPU load, deadlines, dropout and listening comparisons.


🟢 [Done] Non-gliding voices cache base A/B tuning and filter keyboard tracking once per host sample (card drift is already updated at this rate). The actual glide path retains per-internal-sample tuning. Six offline render comparisons covering sync, pulse, deep Poly-Mod, low-frequency B, disabled B tracking, Fine, unison, glide and live pitch/frequency changes produced byte-identical output hashes before/after this cache optimization.


🟢 [Done] Final optimized build and voice/quality regressions passed. The realtime workload now includes maximum modulation depth and alternating delay times in TIME/PEDAL/STUDIO with all FX enabled. On the development Mac, every CPU-time p95 was below the corresponding deadline across 44.1/48/96kHz and 64/128/256-frame blocks with FX on/off. Wall-time deadline misses remained at 7/1,440 measured blocks, so this is not a dropout-free guarantee. The earlier RING-only milestone's zero-miss measurement is historical and does not certify this heavier workload. CPU/load stability remains Next; physical iPhone validation remains Pending.


## Filter response / saturation milestone (2026-11-06)

🟢 [Done] The existing Rev3-style four-pole feedback filter now freezes individual signal-dependent pole coefficients per trapezoidal step: `g_i = g / sqrt(1 + (0.55 * state_i)^2)`, `G_i = g_i / (1 + g_i)`. The cascade forward gain and memory feedthrough are recalculated from these four coefficients for the existing three-iteration nonlinear zero-delay feedback solve. This is a behavioral approximation of gain-cell compression, not a transistor-level or calibrated CEM3320 model. Small-signal response, resonance bass loss and bounded self-oscillation are retained; no resonance loudness compensation is added.

🟢 [Done] `AnalogSignalPath.mixer` separates input headroom (`0.65 * tanh(0.48*x)/0.48`) from feedback saturation. `AnalogSignalPath.amplifier` applies envelope and card gain before `tanh(0.35*x)/0.35`, rather than multiplying a fixed-distortion signal by the envelope afterward. Small-signal scaling, post-FX user master volume, UI/branding and the program schema remain intact. Saturation coefficients are design choices awaiting hardware calibration.

🟢 [Done] `Tests/FilterColorRegression.swift` covers cutoff-region resonance gain, bass loss, four-pole rejection, overload compression, self-oscillation and bounded random cutoff/input/resonance changes at 176.4/192/352.8/384kHz. Mixer H3/fundamental rises from ~0.0000077 at input amplitude 0.02 to ~0.0626 at amplitude 2; VCA H3/fundamental at input amplitude 3 falls from ~0.0722 with envelope 1 to ~0.000916 with envelope 0.1. These are software test levels, not hardware measurements. Existing voice/analog/all-card long-sustain/preset/expression/ladder/AU tests and app build pass.

🟢 [Done] `Tests/FilterColorDemo.swift` generates the post-change dry single-saw/two-oscillator/resonant-sweep clip. The retained before/after WAVs use identical control sequences and one constant gain per entire clip to match overall RMS. They compare this software revision, not an actual instrument.

🟠 [Next] Envelope/Poly-Mod response evaluation and CPU/deadline stability work.
⭕️ [Pending] Matched hardware dry recordings for response/saturation calibration, controlled listening comparison and physical iPhone validation.

Architectural references: [Rev3 service manual](https://www.synfo.nl/servicemanuals/Sequential/SEQUENTIAL_PROPHET-5-REV3_SERVICE_MANUAL.pdf), [original CEM3320 datasheet](https://akizukidenshi.com/goodsaffix/CEM3320.pdf). Numeric coefficients above are not specified measurements from these documents.


🟢 [Done] Final filter-milestone realtime run on the development Mac recorded 0/1,440 wall-time deadline misses across 44.1/48/96kHz, 64/128/256 frames, FX on/off, including delay-time sweeps. This run is not evidence that the prior seven misses' root cause has been eliminated; physical iPhone and repeatability validation remain pending.


## Envelope timing and control-response milestone (2026-11-07)

🟢 [Done] `AnalogEnvelope` stores its capacitor voltage in Double and exports Float levels. This fixes accumulated rounding error at long times/high internal rates without changing the coefficient definitions: attack reaches full scale from zero at the specified duration; decay reaches 1% of its initial distance to sustain; release reaches 0.01% (−80dB) of its starting amplitude, before the existing silence threshold is applied. Retrigger retains the existing voltage. The 30s attack probe measured 30.000000–30.000021s across 44.1/48/96/352.8/384kHz.

🟢 [Done] Per-voice filter/amp envelope coefficient targets are prepared per render block; the active coefficients slew once per host sample using the existing 4ms control time constant. The two Poly-Mod amounts now use the same slew. Their source waveforms and actual envelope integration retain audio/oversampled rates. Initial render/resource reallocation initializes directly to current parameters. Release off immediately assigns its existing 5ms release coefficients, preserving fast note-off. No parameter ranges, modulation endpoint depths, stored voice settings, UI or branding change.

🟢 [Done] `Tests/EnvelopeControlRegression.swift` covers short and 30s attack timing, full 30s decay/release definitions, retrigger continuity, control convergence, exact 64/256-frame response agreement, initial patch state, fast Release off and knob mapping roundtrips. Voice/analog/long-sustain/preset/expression/ladder/filter/AU regressions and app build are included in validation. These test the software's current definitions, not measured hardware matching.

🟠 [Next] Moving PWM/extreme modulation residual artifacts and CPU/deadline work.
🔴 [Later] Adjustable per-voice variation with stable default tuning.
⭕️ [Pending] Hardware recordings to calibrate envelope knob curves and Poly-Mod depth; physical iPhone validation.


🟢 [Done] The final envelope-milestone Mac realtime probe recorded 0/1,440 deadline misses across 44.1/48/96kHz, 64/128/256-frame blocks and FX on/off. This is a development-host observation; physical iPhone performance and hardware equivalence remain pending.


## Moving PWM boundary milestone (2026-11-07)

🟢 [Done] `PWMPulse.sample` preserves the phase-wrap BLEP and corrects the moving width boundary using `min(0.5, abs(step - widthStep))`, where width deltas use the already clamped 0.01–0.99 width. Static non-sync pulses retain the old samples. Per-voice width history feeds both A/B audio evaluation and the B Poly-Mod source; resource allocation clears stale history. No additional fixed latency or oversampling stage is introduced.

🟢 [Done] `SyncEdgeOscillator` uses linear width interpolation over each internal sample. Ordinary phase wrap is independent of moving-boundary crossings; crossings solve the signed relative slope for both directions, while reset jumps use the width at the fractional reset time. Its existing one-internal-sample history remains. Finite BLEP support and the correction-width cap do not fully bandlimit arbitrary noise/fast modulation.

🟢 [Done] `Tests/PWMQualityRegression.swift` compares 8x squared magnitude-spectrum error against a 64x reference for fixed audio-rate PWM probes (carrier 9/128 host cycles, modulation 31/128, width depth 0.42; sync probe uses slave 29/128 and master 3/128). Errors dropped ~93.3% without sync and ~35.3% with sync relative to the old static-width correction. These are synthetic algorithm convergence probes, not hardware measurements. Tests cover static pulse identity, reversing/stationary/extreme edges, and actual AU rendering at 44.1/48/96kHz with simultaneous A Poly-Mod PWM/B wheel PWM, Sync on/off, width endpoints and resource reset. Existing voice/ADSR/preset/expression/ladder regressions and app build passed. The realtime workload includes deep Poly-Mod PWM and 20Hz wheel PWM.

🟠 [Next] Residual alias evaluation for discontinuous noise modulation/extreme speeds and CPU/deadline work.
⭕️ [Pending] Physical iPhone load/listening and matched hardware recordings.


🟢 [Done] The final Mac realtime run with deep A Poly-Mod PWM, B wheel PWM, Sync, maximum resonance, delay-time sweeps and FX on/off recorded 0/1,440 deadline misses across the three tested sample rates and three block sizes. This remains a development-host measurement, not a physical iPhone guarantee.


## Noise control / render-efficiency milestone (2026-11-07)

🟢 [Done] Wheel-Mod source blend now uses the existing 4ms host-rate control time constant, initialized from the stored patch at resource startup. No new noise-waveform filter, depth change, UI/branding or schema change is introduced. `NoiseControlRegression.swift` covers three rates, Sync on/off, combined deep A/B PWM, source/width changes, finite output, fast release, startup and persistence.

🟢 [Done] Curtis/Ladder Newton solves retain their three-iteration maximum but stop when the next Float iterate equals the current result. Zero-envelope amplifier saturation and zero-depth sub sine evaluation are skipped; expression sine is shared and omitted if both destinations have zero depth. Phase/card/filter/random updates are retained. Eight before/after source-snapshot fingerprints matched exactly for fixed source-mix settings, including idle gates, five-note chords, noise PWM, Sync/Poly-Mod, releases and expression/ladder. Source-mix edits intentionally have a new smoothed transient.

🟢 [Done] Final alternating three-run medians on the development Mac, 48kHz/256 frames/300 timed blocks, were classic 0.309042→0.294879s (~4.6% reduction) and Extended+Ladder 0.477352→0.471249s (~1.3% reduction). Run variation exists; these are diagnostics, not universal speedup guarantees. The final deadline workload includes noise/LFO blend switches and delay sweeps; it recorded 0/1,440 misses across three rates, three block sizes and FX on/off. App build and modulation/envelope/voice/preset/filter/expression regressions passed.

🟢 [Done] `NoisePWMQualityRegression.swift` tracks fixed-seed held-noise width spectra at 8/16/32x against a 64x reference. Current non-sync errors are approximately 0.000367/0.0000654/0.00000817; sync errors 0.000417/0.0000887/0.0000109. This quantifies finite-rate residuals and convergence; this milestone does not claim to eliminate noise-PWM aliases. The global processing rate is unchanged.

🟠 [Next] Compare local discontinuous-PWM correction strategies against residual error and CPU cost.
⭕️ [Pending] Physical iPhone load/dropout/interaction and hardware dry-recording calibration.


## Local held-width PWM milestone (2026-11-07)

🟢 [Done] `SyncEdgeOscillator.sample(widthJump: true)` applies a width-change BLEP at interval time zero, holds the new boundary within that internal sample, and handles oscillator wraps/reset jumps separately. Normal moving-boundary evaluation remains the default. `PWMPulse.heldCorrection` uses this pulse-only path for A/B and B's Poly-Mod source. Source B reconstructs its preceding phase interval from the previous actual B advance, rather than the next frequency step.

🟢 [Done] Local correction is routed only for direct noise-to-PW destinations with pulse enabled and blended by clamped `smoothedWheelMix * modWheel`. Weights ≤1e−6 are skipped; B Poly-Mod correction is skipped at negligible source amount. A sync blends two one-sample-history paths; normal pulse components and B modulation acquire up to one internal sample (~2.6µs at 384kHz) in the local path. No global oversampling or FIR-latency-report change. New histories reset on resource allocation.

🟢 [Done] Fixed held-noise probes at 8x against a 64x held-width reference measured squared magnitude-spectrum error 0.000477189→0.00000228630 without sync (~99.5% less) and 0.000547483→0.00000500323 with sync (~99.1% less). Both paths are compared against the same held-width reference. This is a synthetic convergence metric, not a general alias rejection or hardware calibration measurement. Nine `RenderFingerprint --noise-free` fixtures matched the prior source snapshot, including zero wheel, disabled PWM destinations and disabled pulse waveforms. AU noise-control, voice, envelope, preset, expression/ladder and modulation regressions plus app build passed.

🟢 [Done] Final Mac realtime CPU p95 remained within budget in all tested conditions, while wall-time deadlines were missed in 2/1,440 blocks (44.1/48/96kHz, 64/128/256 frames, FX on/off, source-blend changes and delay sweeps). Extra local-history processing increases workload; no dropout-free guarantee is made. Dry 4.32s before/after demos use identical control sequences and one constant RMS-matching gain per clip.

🟠 [Next] Mixed-source correction weighting and local-correction CPU optimization.
⭕️ [Pending] Physical iPhone behavior/load/dropout and matched hardware calibration. README's current-roadmap section is the active priority list; earlier milestones retain their historical status/measurements.


## Local PWM cost refinement (2026-11-07)

🟢 [Done] Held pulse and saw+pulse samples with no fractional reset use an arithmetic-order-preserving specialized solver. The ordinary oscillator exports its pulse component through an internal scratch argument, and local correction consumes that component instead of evaluating the same BLEP again. Weighting, oversampling, histories, latency, UI/branding and persistence are unchanged. Fixed-patch and blend-sweep fingerprints match in 12 scenarios each; 400,000 samples match the prior general solver; 10,000 cached corrections match uncached results. Build and voice/noise/envelope/preset/expression/ladder/modulation regressions pass.

🟢 [Done] Final alternating three-run noise-PWM CPU medians: classic 0.433525→0.372906s (~14.0% reduction), Extended+Ladder 0.568539→0.530757s (~6.6%), 48kHz/256 frames/300 timed blocks after 30 warmup blocks. Diagnostics are host/load dependent.

🟢 [Done] Deadline instrumentation records per-block CPU budget violations and CPU maxima during wall overruns, before sorting distributions. Inherited-QoS wall overruns were 6→43 and explicit interactive diagnostic-QoS overruns 0→8 across 4,320 blocks per version per condition; CPU-budget overruns were zero throughout. CPU improvement does not establish offline wall-deadline improvement. `--interactive-qos` only affects the diagnostic process thread; production AVAudioEngine scheduling is unchanged.

🟢 [Done] Opt-in `Tests/DeviceDeadlineProbe.swift --run-muted-output` invokes the AU DSP from an actual AVAudioEngine output-thread AVAudioSourceNode with synth master zero and all FX enabled. At 88.2kHz, after 20 warmups, 256 timed callbacks had 0 wall/CPU kernel overruns, maximum 2.546ms against minimum budget 5.805ms. It freezes telemetry before signaling completion; no audio is emitted. These figures exclude downstream mixer/driver costs and do not measure audible dropout events, long-run UI/GPU stress or physical iPhones.

Data: `docs/performance/held-pwm-2026-11-07.json` retains all paired CPU samples and both offline scheduling conditions without replacing failed observations with later zero-overrun runs.

🟠 [Next] Mixed-source weighting and long output-device runs under UI/GPU load.
⭕️ [Pending] Physical iPhone dropout/load/interaction and matched hardware sound calibration.


## UI/GPU負荷と描画更新 / UI/GPU load and geometry updates / UI／GPU负载与几何更新（2026-11-07）

🟢 [Done] Metalの固定筐体とノブ本体を保持し、同じレイアウトでは変更した指針／スイッチ／ホイール／鍵盤だけを更新します。不可視の操作変更はアップロードを省略。GPUバッファは更新ごとにコピーし、描画中の共有領域を書き換えません。UI、SYNTH/05表記、音源、保存形式は維持。7レイアウト×12状態の画像84枚が変更前と完全一致し、キャッシュ／既存レイアウト回帰とアプリ全体のビルドを確認しました。

Incremental Metal geometry retains static surfaces and patches changed controls. Invisible changes skip uploads; buffers remain copied per update to avoid in-flight writes. UI, SYNTH/05 branding, DSP and persistence stay unchanged. All 84 pixel comparisons, cache/layout regressions and the full app build pass.

Metal保留固定表面，仅更新变化的控件；不可见变化跳过上传，每次更新仍复制缓冲区以避免覆盖正在绘制的数据。UI、SYNTH/05名称、音源与保存格式保持不变。84种图像像素比较、缓存／布局回归及完整应用构建通过。

🟢 [Done] `Tests/UIGPUDeadlineProbe.swift` uses muted actual AVAudioEngine output, existing SwiftUI controls at 60Hz, 30fps Metal previews, and repeated 1100/740/390pt resizes. At 88.2kHz, each 120-second loaded run completed 20,672 measured callbacks and 3,605 previews. Both had zero AU-kernel wall/CPU overruns and sample-timestamp gaps (minimum budget 5.805ms). Together with two 30-second control runs: 51,680 callbacks across approximately 300 seconds. Renderer-update CPU p95 fell 2.376→1.016ms (~57.2%); process CPU per elapsed time fell ~11.9%. These are one paired host measurement, not a universal speedup guarantee.

120秒の負荷試験は変更前後ともDSP期限超過を再現しませんでした。以前の小ブロックのオフライン超過が解消した根拠にはなりません。音声計測はAUカーネル内のみで、後段ミキサー／ドライバーと聴感上の音切れは対象外。コールバック間隔の外れ値はドライバーのアンダーラン数ではありません。プレビュー時間はテクスチャ作成・読戻しを含み、純粋なGPU時間ではありません。

Neither loaded run reproduced kernel overruns; this does not resolve earlier offline small-block overruns. Measurements exclude downstream mixer/driver and audible dropout detection. Callback interval outliers are not driver underrun counts; preview duration includes allocation/readback rather than pure GPU execution. This synthetic component harness is not exhaustive full-app interaction or an endurance guarantee.

两次负载测试均未复现音源内超时，不能据此认定此前离线小块超时已解决。测量不含后级混音／驱动与听感断音；回调间隔异常不等于驱动欠载次数，预览耗时包含分配和回读。组件模拟测试不能替代完整应用交互或长期稳定性保证。

Data / 測定記録 / 测量记录: [summary and raw paired runs](docs/performance/ui-gpu-2026-11-07/summary.json).

🟠 [Next] Matched-rate/block offline versus output-thread comparisons, longer runs and FX routing changes; mixed LFO/noise correction weighting.
⭕️ [Pending] Physical iPhone load/dropout/interaction and matched hardware sound calibration.
