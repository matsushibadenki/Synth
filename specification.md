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

- Five voices, two oscillators per voice, white noise → mono mixer → four-pole low-pass → amplifier ADSR. Stereo host channels carry the same mono signal.
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

🟠 [Next] Additional antialiasing for sync and audio-rate modulation.

🔴 [Later] Measured hardware calibration for envelope, glide, oscillator and filter behavior.

⭕️ [Pending] Physical iPhone touch/load testing and direct comparison with a hardware Rev3. Circuit fidelity and exact calibrated knob response are not established by the software regression tests.

## Reference

Sequential Circuits, **Model 1000 Prophet-5 Operation Manual, CM1000D, February 1982**: section 2 for controls, pp. 6-5–6-6 for 24 pots / 22 switch bits, section 1-3 for Rev3.3 program organization.
[Original manual scan](https://synthfool.com/docs/SequentialCircuits/Prophet_Series/Sequential%20Circuits%20Prophet%205%20Owners%20Manual.pdf).
