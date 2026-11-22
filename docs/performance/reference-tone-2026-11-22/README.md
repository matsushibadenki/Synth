# Reference-inspired tone refinement validation

2026-11-22, development Mac, optimized Swift offline DSP tests.

Changes: attack target 1.30 → 1.26 with time-normalized RC rate; bounded 3% even-order mixer term; feedback saturation color 0.90 → 0.90–0.98 with resonance. These are behavioral design choices, not measured CEM component calibration. The supplied analysis's decreased filter color would reduce compression in this solver, so its literal formula was not applied. Feedback gain, VCA envelope mapping and oscillator edge correction remain as before.

`analog.txt`: three-rate attack timing and curvature, overload monotonicity, small-signal gain, four-pole response, self-oscillation, decimation and 30-second sustain cases passed. Updated the existing classic phase test to inspect five active-mode cards rather than all eight allocated slots.

`audio.txt`: schema, voice behavior, render at 44.1/48/96 kHz and fast note onset checks passed. macOS app and AUv3 build succeeded.

`eight-voice.txt`: long releases, Sync/Poly-Mod, high resonance and FX, 64/128 frames. All six cases retained eight voices without silent blocks. The 96 kHz/64-frame case had 33 wall-time and 29 CPU overruns out of 1004 measured blocks; no deadline guarantee or audible-dropout conclusion is implied. No paired baseline was measured in this session. Listening comparison, physical iPhone and hardware-recording calibration remain pending.
