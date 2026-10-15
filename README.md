# Synth — Prophet-5 Rev3 inspired

SwiftUI / Metal / AUAudioUnitによる5ボイスの減算合成シンセです。参考画像のシアン／黄緑、金属キャップ付きノブ、黒い筐体を維持し、音色パラメーターをオリジナルRev3に統一しています。
A five-voice SwiftUI / Metal synthesizer with the original Rev3 voice controls and the supplied cyan/lime visual reference.
基于SwiftUI / Metal的五声部减法合成器，采用原版Rev3音色参数及参考图的青色／黄绿色设计。

## パラメーター / Parameters / 参数

**音色46項目 = ノブ24項目 + スイッチ22項目。** Master Tune・Volumeの2ノブ、Pitch・Modの2ホイール、Tune・A-440は音色保存の対象外です。
**46 stored settings = 24 pots + 22 switches.** Master Tune, Volume, both wheels, Tune and A-440 are live controls, excluded from voice programs.
**46个音色参数 = 24个旋钮参数 + 22个开关参数。** 总调音、主音量、两个控制轮、Tune和A-440不随音色保存。

| Section | Knobs | Switches |
|---|---:|---:|
| Poly-Mod | 2 | 3 |
| LFO | 1 | 3 |
| Wheel-Mod | 1 | 5 |
| Oscillator A | 2 | 3 |
| Oscillator B | 3 | 5 |
| Mixer | 3 | 0 |
| Filter + envelope | 7 | 1 |
| Amplifier envelope | 4 | 0 |
| Glide / Release / Unison | 1 | 2 |
| **Program total** | **24** | **22** |

基準資料は[Sequential Circuits CM1000D（1982年2月）](https://synthfool.com/docs/SequentialCircuits/Prophet_Series/Sequential%20Circuits%20Prophet%205%20Owners%20Manual.pdf)です。第2章の操作説明と6-5〜6-6ページの24バイト保存形式を照合しています。メモリー構成はRev3.3の3ファイル×5バンク×8音色＝120枠です。初期Rev3の40枠とは区別します。工場音色の複製は含みません。
The reference is the original CM1000D manual, section 2 and the 24-byte program table on pages 6-5–6-6. Memory follows Rev3.3: 3 files × 5 banks × 8 programs = 120 slots; earlier Rev3 units had 40. Factory patches are not bundled.
依据原版CM1000D说明书第2章及6-5至6-6页的24字节音色格式。存储采用Rev3.3的120个位置；早期Rev3为40个，不附带工厂音色。

## 実装 / Implementation / 实现

- 🟢 [Done] 独立した波形スイッチ、半音刻み4オクターブのOSC周波数、OSC B Fine 0〜100cent、Poly-Mod共通ソースと3送り先、Wheel-ModのLFO／ピンクノイズ混合。
  Independent summed shapes, four-octave semitone tuning, B fine 0–100 cents, shared Poly-Mod sources and all destinations, LFO/pink-noise Wheel-Mod.
  独立波形叠加、四八度半音调谐、B微调0–100音分、Poly-Mod共同源和全部目标、LFO／粉红噪声调制。
- 🟢 [Done] 最低音優先ユニゾン、ユニゾン時のみのGlide、Releaseスイッチ、A-440基準音、モノラル音源を両チャンネルへ出力。Rev3にないSub／Drive／Drift／Velocity／Filter Mode等の操作項目を削除。
  Lowest-note unison, unison-only glide, release enable, A-440 and dual-mono output. Non-Rev3 controls removed.
  最低音优先齐奏、仅齐奏滑音、释音开关、A-440及双声道单声输出，移除Rev3之外的控制项。
- 🟢 [Done] 26ノブ、22スイッチ、2ホイールをMetalで表示。画面幅に合わせ1／2／3列へ変更。Safe Area、左右16pt、英語／日本語／简体中文のヘルプと詳細編集。
  Metal controls reflow across one, two or three columns with safe areas, 16pt margins and localized help/editor.
  Metal控件自适应为一／二／三列，保留安全区域、16pt边距及三语言帮助和编辑器。
- 🟢 [Done] 46項目の厳密な保存・復元。旧A/Bプリセットはファイル1/2へ読み込み時に変換し、元データを保持。非対応の波形・効果を含む旧音色は完全互換ではありません。
  Strict 46-setting program format. Legacy A/B programs can be adapted into files 1/2 without overwriting originals; unsupported old sounds cannot be reproduced losslessly.
  严格保存46项参数，旧A/B音色载入文件1/2时适配且保留原数据；不兼容音色无法无损复现。
- 🟠 [Next] ハードSync／音声帯域Poly-Modの追加アンチエイリアス。
  Further hard-sync/audio-rate modulation antialiasing. 进一步抑制硬同步和音频调制混叠。
- 🔴 [Later] 実機録音による周波数、時間定数、飽和特性の校正。
  Hardware-based response calibration. 根据实机录音校准响应。
- ⭕️ [Pending] iPhone実機のタッチ、マルチタッチ、GPU／CPU負荷、実機Rev3との聴感比較。
  Physical iPhone interaction/load tests and hardware listening comparison. iPhone实机交互／负载及实机听感对比。

項目の一致とアナログ回路の完全再現は別です。DSPはPolyBLEP発振器、指数ADSR、2サブステップの4ポールTPTフィルターで近似します。微小な個体差は固定の内部特性です。Glide・Master Tune等の数値スケールはソフトウェア上の近似です。
Control parity does not imply circuit-level emulation. DSP uses PolyBLEP oscillators, exponential ADSR and a four-pole TPT filter with two filter substeps. Card variation is fixed internally; numeric glide/tuning calibration is approximate.
参数一致不代表电路级仿真。DSP使用PolyBLEP振荡器、指数ADSR和每采样两次更新的四极TPT滤波器；个体差异为内部固定特性，滑音／调音刻度为近似值。

## 実行・検証 / Run and validate / 运行与验证

Xcodeで`Package.swift`を開いて実行します。 / Open `Package.swift` in Xcode. / 在Xcode中打开`Package.swift`。

```sh
CLANG_MODULE_CACHE_PATH=/tmp/synth-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/synth-swift-cache swift build --disable-sandbox
cat Sources/SynthApp/Rev3Parameters.swift Sources/SynthApp/ProphetCore.swift Tests/Rev3Regression.swift Tests/AudioRegression.swift > /tmp/synth-regression.swift
swiftc -O -module-cache-path /tmp/synth-clang-cache /tmp/synth-regression.swift -o /tmp/synth-regression
/tmp/synth-regression
cat Sources/SynthApp/Rev3Parameters.swift Sources/SynthApp/MetalPanelRenderer.swift Tests/MetalPanelRegression.swift > /tmp/synth-metal-check.swift
swiftc -module-cache-path /tmp/synth-clang-cache /tmp/synth-metal-check.swift -o /tmp/synth-metal-check
/tmp/synth-metal-check
```

音源テストは44.1/48/96kHzの安定性、ADSR、波形併用、最低音優先、Release、変調経路、A-440、保存項目数と非保存コントロールの維持を検査します。GPUテストは288／343／382／736／1100pxで描画し、状態変化と領域内配置を確認します。GPUチェックにはMetalデバイスへのアクセスが必要です。
Audio tests cover sample-rate stability and Rev3 behaviors/schema; GPU tests cover five widths, bounds and visible state changes. GPU access is required.
音频测试覆盖多采样率稳定性、Rev3行为及参数格式；GPU测试检查五种宽度、边界及状态变化，需要GPU访问权限。

`Rev3Parameters.swift`がパネル・DSP・保存の共通定義、`MetalPanelRenderer.swift`がメッシュ、`InstrumentPanel.swift`が印字と操作を担当します。iPhone SE (3rd generation)／iPhone 16 Pro MaxのSwiftUI Previewを含みます。
