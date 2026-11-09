# Deadline isolation / 期限超過の切り分け / 超时排查

🟢 [Done] `Tests/MatchedDeadlineProbe.swift` records the actual output sample rate and complete frame-length sequence, then replays the same sequence from fresh AU instances with the same fixed patch and FX. All builds finish before measurements. Each run drops 20 warmup callbacks. Default and User Interactive diagnostic QoS alternate, are checked against their requested values, and restore the original thread QoS afterward. Production scheduling is unchanged.

実出力のレート／フレーム列をそのまま再生し、条件不一致を減らす検証を追加。全試験は最終出力を無音にし、音源とFXは動作します。実出力とオフラインのCPU時間差は処理速度改善の証拠ではありません。オフラインは無待機で連続実行し、実出力とはスケジューリング・周波数・温度条件が異なります。

新增验证会按实际输出的采样率及帧数序列重放，减少条件不一致。所有测试最终静音，音源及效果仍运行。离线连续执行与实际输出的调度、频率和温度条件不同，CPU时间差不能当作性能优化证据。

| Profile | Rate / frames | Timed callbacks | Wall overruns | CPU overruns |
| --- | --- | ---: | ---: | ---: |
| Muted output | 96kHz / 512 | 5,605 | 0 | 0 |
| Offline Default, first | same sequence | 5,605 | 17 | 0 |
| Offline User Interactive, first | same sequence | 5,605 | 0 | 0 |
| Offline User Interactive, second | same sequence | 5,605 | 7 | 0 |
| Offline Default, second | same sequence | 5,605 | 17 | 0 |

Budget: 5.333ms per block. Every wall overrun had thread CPU time within that budget. This supports investigating descheduling/non-CPU elapsed time; it does not identify the OS scheduler as the sole cause or establish a fix. QoS alone did not remove offline overruns. One sequential host experiment does not isolate temperature, frequency or run-order effects.

全超過でCPU時間は予算内でした。待機・プリエンプション等の非CPU時間を調べる根拠にはなりますが、単一原因の特定や解消を意味しません。QoSだけでは解消しませんでした。温度、動作周波数、試験順の影響は未分離です。

所有超时的CPU时间均在预算内，说明需要继续排查等待／抢占等非CPU时间，但尚未确定单一原因或修复。仅提高QoS未能消除超时；温度、频率和执行顺序影响仍未分离。

`pilot.json` retains the preliminary inherited-QoS experiment, where both inherited and explicit interactive QoS were actually 33. Its labels are historical, not evidence of different QoS conditions. The verified comparison is `matched.json` (Default 21 versus User Interactive 33).

## Reproduction / 再実行 / 重现

Run on macOS with a working output device; no system audio settings are changed. Compile before running and do not run builds or other benchmarks alongside measurements.

```sh
swiftc -O Sources/SynthApp/Rev3Parameters.swift Sources/SynthApp/EffectsGraph.swift Sources/SynthApp/EffectsDSP.swift Sources/SynthApp/ProphetCore.swift Tests/MatchedDeadlineProbe.swift -o /tmp/synth-matched-deadline
/tmp/synth-matched-deadline --run-muted-output --seconds 30 --report /tmp/matched.json

swiftc -O Sources/SynthApp/Rev3Parameters.swift Sources/SynthApp/EffectsGraph.swift Sources/SynthApp/EffectsDSP.swift Sources/SynthApp/ProphetCore.swift Sources/SynthApp/MetalPanelRenderer.swift Sources/SynthApp/InstrumentChrome.swift Sources/SynthApp/InstrumentPanel.swift Sources/SynthApp/MasterVolumeControl.swift Tests/UIGPUDeadlineProbe.swift -o /tmp/synth-ui-gpu-routing
/tmp/synth-ui-gpu-routing --run-muted-output --seconds 180 --ui-gpu --fx-routing --report /tmp/routing.json
```

🟠 [Next] Paced versus unpaced offline comparisons, finer non-CPU-time attribution and mixed LFO/noise correction weighting. FX-route transition sound quality requires a separate audible/nonzero-signal test; muted timing does not verify it.

⭕️ [Pending] Physical iPhone load/interaction/dropouts and matched hardware calibration. AU timing excludes downstream mixer/driver, audible dropouts and driver underrun counters. Timestamp continuity is not a dropout count. This synthetic component harness does not exhaustively exercise the full app.
