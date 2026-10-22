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

- Pitch variation combines independent quintic-interpolated random trajectories (about 0.7–2.7 seconds and 7–21 seconds) with a slower shared-per-card thermal component (11–30 seconds). Initial error is within ±0.65 cent, wander components total at most ±2.45 cents before Tune, and scale error is within ±0.14 cent/octave. These are chosen model values, **not measured Prophet-5 tolerance specifications**. A/B share only the small thermal component. Tests compare identical elapsed times at different update rates.
- Tune captures the current pitch bias of each oscillator and slews the correction over 60 ms. It preserves oscillator phases and the ongoing random trajectories. This is a simplified correction, not the hardware's ten-C measurement table or its tuning sequence. Drift can grow again after tuning.
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
