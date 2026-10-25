# Synth — 05 Rev3 inspired

<img src="docs/images/synth-image1.png">
<img src="docs/images/synth-image2.png">
<img src="docs/images/synth-image3.png">

SwiftUI / Metal / AUAudioUnitによる5ボイスの減算合成シンセです。参考画像のシアン／黄緑、金属キャップ付きノブ、黒い筐体を維持し、音色パラメーターをオリジナルRev3に統一しています。
A five-voice SwiftUI / Metal synthesizer with the original Rev3 voice controls and the supplied cyan/lime visual reference.
基于SwiftUI / Metal的五声部减法合成器，采用原版Rev3音色参数及参考图的青色／黄绿色设计。

## パラメーター / Parameters / 参数

**音色46項目 = ノブ24項目 + スイッチ22項目。** Master Tune・Volumeの2ノブ、Pitch・Modの2ホイール、Tune・A-440は音色保存の対象外です。
**46 stored settings = 24 pots + 22 switches.** Master Tune, Volume, both wheels, Tune and A-440 are live controls, excluded from voice programs.
**46个音色参数 = 24个旋钮参数 + 22个开关参数。** 总调音、主音量、两个控制轮、Tune和A-440不随音色保存。

| Section                  |  Knobs | Switches |
| ------------------------ | -----: | -------: |
| Poly-Mod                 |      2 |        3 |
| LFO                      |      1 |        3 |
| Wheel-Mod                |      1 |        5 |
| Oscillator A             |      2 |        3 |
| Oscillator B             |      3 |        5 |
| Mixer                    |      3 |        0 |
| Filter + envelope        |      7 |        1 |
| Amplifier envelope       |      4 |        0 |
| Glide / Release / Unison |      1 |        2 |
| **Program total**        | **24** |   **22** |

基準資料は[Sequential Circuits CM1000D（1982年2月）](https://synthfool.com/docs/SequentialCircuits/Prophet_Series/Sequential%20Circuits%20Prophet%205%20Owners%20Manual.pdf)です。第2章の操作説明と6-5〜6-6ページの24バイト保存形式を照合しています。メモリー構成はRev3.3の3ファイル×5バンク×8音色＝120枠です。初期Rev3の40枠とは区別します。工場音色の複製は含みません。
The reference is the original CM1000D manual, section 2 and the 24-byte program table on pages 6-5–6-6. Memory follows Rev3.3: 3 files × 5 banks × 8 programs = 120 slots; earlier Rev3 units had 40. Factory patches are not bundled.
依据原版CM1000D说明书第2章及6-5至6-6页的24字节音色格式。存储采用Rev3.3的120个位置；早期Rev3为40个，不附带工厂音色。

## 実装 / Implementation / 实现

- 🟢 [Done] 補正の聴き比べ用にピアノ／バイオリンのシンセ音色を追加。PROGRAMMERの読込アイコン（書類＋下矢印）から選べます。ピアノは速い打鍵と減衰、バイオリンは滑らかな立ち上がりと持続音。FINE=0、ノイズ／ユニゾンなしで読み込み、Pitch／ModホイールとA-440を中立化します。主音量とマスターチューンは維持。ユーザー音色枠は上書きせず、保存する場合だけ録音ボタンを使います。FX設定は維持するため、補正確認時はFXをOFFにしてください。これは減算合成による楽器風音色です。
  Piano and Violin synth presets are available from PROGRAMMER's document/down-arrow recall menu. Piano tests attack/decay; Violin tests sustained stability. Recall uses FINE=0, no noise/unison, neutral wheels and A-440 off, preserving master volume/tuning. User slots are only written with Record. Bypass FX when comparing; these are subtractive synth interpretations.
  从PROGRAMMER的文档下箭头菜单选择钢琴／小提琴合成音色。钢琴用于检查起音与衰减，小提琴用于检查持续音稳定性。FINE=0、关闭噪声／齐奏，轮控归零且A-440关闭，保留主音量与总调音。仅按保存按钮才写入用户音色位。比较时请关闭效果；音色采用减法合成。

  [ピアノ / Piano / 钢琴](Previews/piano-preset.wav) · [バイオリン / Violin / 小提琴](Previews/violin-preset.wav) — FXなし、10.8秒／13.76秒。 / Dry, 10.8 / 13.76 seconds. / 干声10.8／13.76秒。

- 🟢 [Done] FINE=0で長く伸ばした音の安定性を改善。同じボイス内のOSC A/Bで自然な音程変動・トラッキング誤差・Tune補正を共有し、微小な音程差が積み重なって生じる音量のうねりを抑えます。5ボイスは別々に緩やかに揺れ、フィルター／ADSR／VCAの個体差も維持します。FINEや変調、ユニゾンで意図的に生じるうなりは残ります。新しい操作項目や保存音色の書き換えはありません。
  Improved long-note stability at FINE=0 by sharing incidental pitch drift, tracking error and Tune correction between A/B within each voice. Five voices retain separate slow motion and filter/envelope/VCA tolerances. Intentional Fine, modulation and unison beating remain; no added controls or saved-patch rewrites.
  改善FINE=0时的长音稳定性：同一声部的A/B共享自然音高漂移、跟踪误差与Tune校正，避免微小频差累积造成音量起伏。五个声部仍各自缓慢漂移，保留滤波器／ADSR／VCA差异；FINE、调制和齐奏产生的拍频仍保留。不增加参数，也不改写已存音色。

- 🟢 [Done] FXなしの単音で目立つ速いうなりを軽減。初期OSC B FINEを0セントにし、独立した音程揺れを小さく・ゆっくりに調整しました。遅い温度変動と自由走行する発振器は維持します。保存済み音色のFINEは変更しないため、既存音色ではOSC B FINEを0にして確認してください。意図的なデチューンによるうなりは残ります。
  Reduced rapid dry-note beating: neutral initial OSC B FINE, smaller/slower independent pitch wander, retained slow thermal motion and free-running phases. Saved patches retain their FINE value; set OSC B FINE to 0 when checking an existing patch. Intentional detuning still beats naturally.
  减轻干声单音的快速拍频：初始OSC B FINE设为0，减小并放慢独立音高漂移，保留缓慢温度变化与自由运行相位。已存音色的FINE不变，检查旧音色时请将OSC B FINE设为0；有意失谐仍会产生自然拍频。

- 🟢 [Done] 演奏中のプツプツ音への対策：通常のXcode Run／DebugビルドでもSwift DSPを最適化し、音声コールバックのパラメーター取得とノート受信を非待機化。ノートキューは256イベントの固定容量、押鍵状態は固定ビット列で管理します。ロック競合中も直前の音色で演奏を継続し、保留した離鍵は次に受信できたブロックで処理します。揺れ・共振・プリセットの値は変更しません。
  Crackle fix: optimize Swift DSP in normal Xcode Run/Debug builds and remove waiting for parameter/note locks from render. A fixed 256-event queue and MIDI-key bitset replace growing collections. Contention keeps the last valid patch playing and defers queued note-offs. Timbre and saved programs are unchanged.
  修复演奏爆音：普通Xcode Run／Debug构建也优化Swift DSP，音频回调不再等待参数／音符锁。采用固定256事件队列和按键位集；锁冲突时继续使用上一份有效音色，稍后处理保留的松键事件，不改变音色与预设。

- 🟢 [Done] 音源のアナログ挙動を改良。10発振器を離鍵中も動かし、独立した緩やかな音程変動、5ボイスのフィルター／ADSR／VCA差、Tune補正、CVベースのGlideを実装。44.1／48kHzでは音源全体を4倍、88.2／96kHzでは2倍で処理し、FIRで折り返しを抑制します。フィルターの非線形帰還、自己発振、パルスのDC除去と4msの主要コントロール平滑化も追加。操作項目は同じ46項目です。
  Free-running VCOs, independent slow pitch drift, per-card filter/envelope/VCA tolerances, tuning correction and pitch-CV glide. The complete voice path runs at 4× for 44.1/48 kHz and 2× for 88.2/96 kHz, followed by FIR decimation. Nonlinear filter feedback, self-oscillation, DC removal and 4 ms smoothing of main timbre controls are included; the 46-setting format is unchanged.
  新增自由运行振荡器、独立缓慢音高漂移、声部间滤波器／包络／VCA差异、调音补偿与音高CV滑音。44.1／48kHz采用4倍、88.2／96kHz采用2倍全音源过采样并通过FIR降采样，改善非线性反馈、自激振荡、直流消除及主要音色控制平滑处理；仍为46个音色参数。

  [ドライ試聴 / Dry demo / 干声试听](Previews/rev3-analog-demo.wav)：ブラス → ユニゾンベース → Syncリード → Poly-Modベル。FXなし、16.27秒。揺れ軽減前の参考録音です。 / No FX, 16.27 seconds; recorded before the beating adjustment. / 无效果，16.27秒；拍频调整前的参考录音。

- 🟢 [Done] マスター音量を共通タイトル帯へ移設し、全エフェクト画面から操作可能に。元と同じMetalノブ形状・描画倍率・操作感度を維持し、シンセ操作面の重複ノブを削除。狭い幅ではタイトル／操作ボタンの右側へ縦配置し、288pt幅の共通パネル高は327ptを維持。
  Master volume now lives in the shared header across all FX tabs. Its Metal mesh, projected size and drag sensitivity are unchanged; the duplicate synth control is removed. Narrow layouts place it beside the title/utilities.
  将主音量移到所有效果标签共用的标题栏，保持Metal旋钮形状、绘制比例和操作灵敏度，移除合成器区域的重复旋钮。窄屏放在标题与操作按钮右侧。

- 🟢 [Done] 共通パネルを再圧縮。広い画面ではPROGRAMMERと鍵盤を横並びにし、音色ボタンは4×2段、狭い画面は8ボタン1列を維持。保存／読込を空きスペースへ移動し、鍵盤とボタンのサイズを保って、5幅で高さを約15〜31%短縮（1088pt幅：326→226pt、288pt幅：388→327pt）。
  A tighter shared panel places programmer and keyboard side by side on wide screens. Program keys use two rows on desktop and one row on narrow screens; control sizes stay intact. Panel height drops about 15–31% across five widths.
  重新压缩共用面板，宽屏将音色区与琴键并排，音色按钮宽屏4×2排列、窄屏单行8个。保持琴键与按钮尺寸，五种宽度下面板高度减少约15–31%。

- 🟢 [Done] タイトル帯のInfo／Tune／A-440／電源、PROGRAMMER、Metal鍵盤とPitch／Modを、タブ外の共通パネルへ統合。音色選択・保存・演奏は全タブで共通。スクロールする操作面から分離し、高さの低い画面では共通パネル内もスクロールしてSafe Areaに収めます。
  One persistent panel combines header utilities, programmer, Metal keyboard and wheels across all tabs. Only the selected workspace changes; short viewports allow scrolling inside the common panel.
  将标题栏功能、音色选择与保存、Metal琴键及控制轮合并为所有标签共用的固定面板。仅切换下方工作区，较矮的窗口允许面板内部滚动以适应安全区域。

- 🟢 [Done] 黒い金属筐体、木目サイド、固定ネジ、銘板、通気スリット、鍵盤の赤いフェルトを追加。音色選択部はアンバー色7セグ表示と立体ボタンに統一し、狭い画面では段組みを変更。FILE／BANKはクリックで送り、右クリック／長押しで直接選択。
  Metal enclosure, wooden sides, screws, nameplate, vents and red keyboard felt. The responsive programmer uses amber seven-segment digits and beveled buttons; click FILE/BANK to advance or use the context menu to select directly.
  新增黑色金属外壳、木纹侧板、螺丝、铭牌、散热槽及键盘红色毛毡。音色区采用琥珀色七段显示与立体按钮，窄屏自动换行；点击FILE／BANK切换，右键或长按直接选择。

- 🟢 [Done] ノブ／スイッチの寸法と描画倍率を維持し、見出し・ノブラベル・数値・スイッチ名の縦間隔を調整。見出しとノブラベル、数値とスイッチ名の間は検証対象幅で4pt以上を確保し、隣接するノブラベルも幅を制限して接触を防止。
  Control sizes and projection stay unchanged. Section/knob labels and value/switch labels have at least 4pt vertical clearance at the tested widths; bounded label widths keep neighboring legends apart.
  保持旋钮／开关尺寸与绘制比例，调整标题、旋钮标签、数值和开关名称的纵向间距。在测试宽度下保留至少4pt纵向空隙，并限制相邻标签宽度以避免接触。

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
- 🟠 [Next] 極端なSync／Poly-Mod設定で残る折り返しの改善と、iPhone向け負荷調整。
  Further alias suppression at extreme modulation depths and iPhone profiling. 进一步降低极端同步／调制下的混叠并优化iPhone负载。
- 🔴 [Later] 実機録音による周波数、時間定数、飽和特性の校正。
  Hardware-based response calibration. 根据实机录音校准响应。
- ⭕️ [Pending] iPhone実機のタッチ、マルチタッチ、GPU／CPU負荷、実機Rev3との聴感比較。
  Physical iPhone interaction/load tests and hardware listening comparison. iPhone实机交互／负载及实机听感对比。

項目の一致とアナログ回路の完全再現は別です。DSPはCEM3340／3310／3320の構成を参考にした挙動モデルで、実機の部品値を測定した回路シミュレーターではありません。揺れ・個体差・飽和量は控えめな近似値で、時間定数やノブ応答の実機校正は未実施です。詳細と検証値は[specification.md](specification.md#analog-voice-refinement-2026-10-22)を参照してください。
This is a behavioral model informed by the CEM3340/3310/3320 architecture, not a measured circuit simulation. Drift, tolerances and saturation use restrained approximations; time constants and knob responses still need hardware calibration. See the specification for measurements and limits.
这是参考CEM3340／3310／3320结构的行为模型，并非基于实测元件的电路仿真。漂移、个体差异与饱和度采用适度近似，时间常数及旋钮响应尚未经过实机校准。测量结果与限制见规范文档。

## 実行・検証 / Run and validate / 运行与验证

Xcodeで`Package.swift`を開いて実行します。 / Open `Package.swift` in Xcode. / 在Xcode中打开`Package.swift`。

```sh
CLANG_MODULE_CACHE_PATH=/tmp/synth-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/synth-swift-cache swift build --disable-sandbox
cat Sources/SynthApp/Rev3Parameters.swift Sources/SynthApp/EffectsGraph.swift Sources/SynthApp/EffectsDSP.swift Sources/SynthApp/ProphetCore.swift Tests/Rev3Regression.swift Tests/AudioRegression.swift Tests/AnalogRegression.swift > /tmp/synth-regression.swift
swiftc -O -module-cache-path /tmp/synth-clang-cache /tmp/synth-regression.swift -o /tmp/synth-regression
/tmp/synth-regression
cat Sources/SynthApp/Rev3Parameters.swift Sources/SynthApp/MetalPanelRenderer.swift Tests/MetalPanelRegression.swift > /tmp/synth-metal-check.swift
swiftc -module-cache-path /tmp/synth-clang-cache /tmp/synth-metal-check.swift -o /tmp/synth-metal-check
/tmp/synth-metal-check
```

通常のDebugビルドにも`-O`を適用しています。Xcodeから通常どおり停止→実行することで修正が反映されます。デバッグシンボルは維持しますが、最適化によって変数の参照やステップ実行が制限される場合があります。Releaseビルドも利用できます。
Normal Debug builds now use `-O`; stop and run again in Xcode to load the fix. Debug symbols remain, but optimized variables/stepping may be limited. Release remains available.
普通Debug构建现已使用`-O`，在Xcode停止后重新运行即可加载修复。保留调试符号，但优化可能限制变量查看与单步调试，仍可使用Release构建。

```sh
CLANG_MODULE_CACHE_PATH=/tmp/synth-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/synth-swift-cache swift build -c release --disable-sandbox
.build/release/SynthApp
```

試聴ファイルの再生成 / Regenerate the demo / 重新生成试听：
```sh
cat Sources/SynthApp/Rev3Parameters.swift Sources/SynthApp/EffectsGraph.swift Sources/SynthApp/EffectsDSP.swift Sources/SynthApp/ProphetCore.swift Tests/Rev3Regression.swift Tests/AnalogDemo.swift > /tmp/synth-analog-demo.swift
swiftc -O -module-cache-path /tmp/synth-clang-cache /tmp/synth-analog-demo.swift -o /tmp/synth-analog-demo
/tmp/synth-analog-demo /tmp/rev3-analog-demo.wav
```

音切れ対策の回帰検証 / Realtime regression / 实时回归验证：
```sh
cat Sources/SynthApp/Rev3Parameters.swift Sources/SynthApp/EffectsGraph.swift Sources/SynthApp/EffectsDSP.swift Sources/SynthApp/ProphetCore.swift Tests/Rev3Regression.swift Tests/RealtimeRegression.swift > /tmp/synth-realtime-regression.swift
swiftc -Onone -g -O -module-cache-path /tmp/synth-clang-cache /tmp/synth-realtime-regression.swift -o /tmp/synth-realtime-regression
/tmp/synth-realtime-regression
```

音源テストは44.1/48/96kHzの安定性、ADSR、波形併用、最低音優先、Release、変調経路、A-440、保存項目数と非保存コントロールの維持を検査します。GPUテストは288／343／382／736／1100pxで描画し、状態変化と領域内配置を確認します。GPUチェックにはMetalデバイスへのアクセスが必要です。
Audio tests cover sample-rate stability and Rev3 behaviors/schema; GPU tests cover five widths, bounds and visible state changes. GPU access is required.
音频测试覆盖多采样率稳定性、Rev3行为及参数格式；GPU测试检查五种宽度、边界及状态变化，需要GPU访问权限。

`Rev3Parameters.swift`がパネル・DSP・保存の共通定義、`MetalPanelRenderer.swift`がメッシュ、`InstrumentPanel.swift`が印字と操作を担当します。iPhone SE (3rd generation)／iPhone 16 Pro MaxのSwiftUI Previewを含みます。

## エフェクト / Effects / 效果

🟢 [Done] タブはSYNTH → DIMENSION → SKY / TIME → PEDAL → RING → STUDIO → PATCHの順です。初回は全エフェクトがバイパス。各モジュールのフットスイッチで有効にし、上部の共通鍵盤で試奏できます。
Tabs follow the requested order. Effects start bypassed; engage their footswitches and audition with the keyboard.
标签按请求顺序排列，首次启动全部效果旁通。点击脚踏开关启用，用上方共用琴键试听。

| Tab | Implemented independent DSP |
| --- | --- |
| DIMENSION | Stereo multi-voice chorus, positive/negative feedback flanger |
| SKY / TIME | Hall / Plate / Cloud / octave Shimmer; Digital / Tape / Bucket / Ping-pong delay, tap tempo |
| PEDAL | Digital / Tape / overlapping-grain Reverse delay; stereo 12-second record/play/overdub looper, reverse, half-speed, A/B/C recall/store |
| RING | Sine carrier, low/high frequency ranges, sine/triangle LFO, amount, drive, wet/dry |
| STUDIO | SCF-inspired chorus/flange; 2290-inspired ducking stereo echo |
| PATCH | Source + six effects + MIX A/B + OUT; port connections, disconnection, node dragging, series/parallel presets, undo/redo |

🟢 [Done] UNGEの型付き接続・DAG・CommandのSwift移植を使用。元コードとMITライセンス、移植範囲は[Vendor/UNGE/INTEGRATION.md](Vendor/UNGE/INTEGRATION.md)に保存。音声用の事前確保バッファと処理順をAudioUnitへ接続し、マスター音量はエフェクト後へ適用しています。
A Swift port of UNGE's graph/command core validates routing. A precompiled audio plan processes host-owned stereo buffers; master volume follows the effects.
使用UNGE图与命令核心的Swift移植进行连接验证，预编译处理顺序并预分配立体声缓冲，主音量位于效果之后。

出力ポート→入力ポートの順で選択。入力の右クリック／長押し、またはケーブル一覧から切断します。並列経路はMIX A/Bで合流。各入力は1本、未接続入力は無音、循環接続は拒否します。9個の固定ノードを並べ替えて接続する構成で、同一エフェクトの複数インスタンス生成には未対応です。
Select an output, then an input. Disconnect through a port's context menu or cable list. Merge parallel branches with MIX A/B. Inputs accept one cable, disconnected inputs are silent, cycles are rejected. The nine nodes are fixed; duplicate effect instances are not implemented.
先选输出再选输入，通过端口菜单或连线列表断开，用MIX A/B合并并行分支。每个输入仅允许一条连线，未连接为静音，禁止循环。当前为九个固定节点，不支持同类效果的多个实例。

設定・接続・配置は自動保存され、Rev3の音色46項目から独立しています。ルーパー音声はRAM内のみで、電源停止時に消去されます。プリセット操作で録音を開始することはありません。各実機の全機能・全アルゴリズムや音響特性を再現したものではありません。
FX settings/routing/placement save separately from Rev3 programs. Loops live only in RAM and clear when power stops; preset recall cannot trigger recording. These are original inspired algorithms, not full hardware emulations.
效果设置、连接与位置独立自动保存，循环音频仅存在于RAM并在停止电源时清除，预设不会触发录音。这些为参考实机的独立算法，并非完整仿真。

```sh
cat Sources/SynthApp/EffectsGraph.swift Sources/SynthApp/EffectsDSP.swift Tests/EffectsRegression.swift > /tmp/synth-effects-tests.swift
swiftc -O -parse-as-library -module-cache-path /tmp/synth-clang-cache /tmp/synth-effects-tests.swift -o /tmp/synth-effects-tests
/tmp/synth-effects-tests
cat Sources/SynthApp/Rev3Parameters.swift Sources/SynthApp/EffectsGraph.swift Sources/SynthApp/EffectsDSP.swift Sources/SynthApp/ProphetCore.swift Tests/EffectsIntegration.swift > /tmp/synth-fx-integration.swift
swiftc -O -parse-as-library -module-cache-path /tmp/synth-clang-cache /tmp/synth-fx-integration.swift -o /tmp/synth-fx-integration
/tmp/synth-fx-integration
cat Sources/SynthApp/EffectsGraph.swift Sources/SynthApp/EffectsController.swift Tests/EffectsControllerRegression.swift > /tmp/synth-fx-host.swift
swiftc -parse-as-library -module-cache-path /tmp/synth-clang-cache /tmp/synth-fx-host.swift -o /tmp/synth-fx-host
/tmp/synth-fx-host
```

🟢 [Done] 44.1/48/96kHzの各モード、残響、ステレオ差、最大フィードバック、ルーパー、グラフ契約、AU経由の処理／ミュート／OUT切断を検証。5幅の画面描画、macOSでのポート接続・Undo・並列接続を確認。
Verified modes/tails/stereo/feedback/looper at three sample rates, graph contracts and AU routing/mute/disconnection; rendered five UI widths and exercised macOS patch editing.
已验证三种采样率的模式／尾音／立体声／反馈／循环录音，以及图契约和AU连接／静音／断开；检查五种界面宽度及macOS节点编辑。

🟠 [Next] 音声帯域リング変調と高速ディレイ変調の追加アンチエイリアス。 Additional ring/delay modulation antialiasing. 进一步抑制环形调制和高速延迟调制混叠。
🔴 [Later] 同一エフェクトの複数インスタンス、独立したFXプリセットファイル、長時間ループ保存。 Multiple instances, portable FX preset files and persistent long loops. 多实例、独立预设文件及长循环存储。
⭕️ [Pending] iPhone実機の操作／負荷／音切れ検証と、参考実機との聴感・測定比較。 Physical iPhone interaction/load/dropout and hardware comparisons. iPhone实机交互／负载／断音测试及参考设备对比。

参考にした公式資料： [Roland SBF-325](https://static.roland.com/manuals/sh-4d/jpn/50233808.html)、[Strymon TimeLine](https://www.strymon.net/support/timeline/)、[Strymon BigSky](https://www.strymon.net/get-know-bigsky-rabea-massaad-pt-3/)、[Line 6 DL4 MkII](https://line6.com/effects-pedals/dl4-mkii/)、[t.c. electronic 2290](https://www.tcelectronic.com/en/products/0815-aak)、[Moog MF-102 manual](https://api.moogmusic.com/sites/default/files/2018-06/MF_102_Ring_Modulator_Manual.pdf)。


楽器プリセット検証・試聴の生成 / Instrument preset checks and demos / 乐器预设验证与试听：
```sh
cat Sources/SynthApp/Rev3Parameters.swift Sources/SynthApp/EffectsGraph.swift Sources/SynthApp/EffectsDSP.swift Sources/SynthApp/ProphetCore.swift Tests/Rev3Regression.swift Tests/InstrumentPresetsRegression.swift > /tmp/synth-instrument-presets.swift
swiftc -O -module-cache-path /tmp/synth-clang-cache /tmp/synth-instrument-presets.swift -o /tmp/synth-instrument-presets
/tmp/synth-instrument-presets Previews
```

## Extended expression / 音の表現拡張 / 声音表现扩展

🟢 [Done] SYNTH上部のSYNTH/05 / Extendedで切り替え。初期状態はSYNTH/05。Extendedにはサイン波の1オクターブ下のサブ音源、独立したフィルター揺らぎ、オートパンと共通速度（0.05–8Hz）を追加。切り替えと各深度は4msで平滑化します。既存FXはどちらのモードでも独立して動作します。
Switch above the SYNTH panel. SYNTH/05 is the default; Extended adds a sine sub one octave below the played pitch, independent filter motion, and auto pan with a shared 0.05–8Hz rate. Depths and bypass use 4ms smoothing. Existing FX remain independent in both modes.
在SYNTH顶部切换，默认为SYNTH/05。Extended添加低一个八度的正弦波低音、独立滤波调制及自动声像，共用0.05–8Hz速率。深度和旁通采用4ms平滑处理，两种模式下原有效果均独立运行。

🟢 [Done] 拡張設定とモードはアプリ共通で自動保存し、SYNTH/05への切り替え中も保持。既存の46項目の音色保存・呼び出し・楽器プリセットはそのまま利用可能です。拡張値は音色スロットには含みません。
Extension settings and mode save globally and survive bypass. The original 46-setting programs and instrument presets retain their schema; extension settings are outside program slots.
扩展参数与模式全局自动保存，旁通时保留。原有46项音色及乐器预设格式保持不变，音色槽不包含扩展参数。

⭕️ [Pending] iPhone実機での新パネルのレイアウト、操作、負荷と聴感の確認。
New panel layout, interaction, load and listening checks on physical iPhones remain pending.
iPhone实机新面板布局、交互、性能与听感验证待完成。

```sh
cat Sources/SynthApp/Rev3Parameters.swift Sources/SynthApp/EffectsGraph.swift Sources/SynthApp/EffectsDSP.swift Sources/SynthApp/ProphetCore.swift Tests/Rev3Regression.swift Tests/ExpressionRegression.swift > /tmp/synth-expression-test.swift
swiftc -O -module-cache-path /tmp/synth-clang-cache /tmp/synth-expression-test.swift -o /tmp/synth-expression-test
/tmp/synth-expression-test
```

### Ladder color / ラダー系の音作り / 梯形滤波音色

🟢 [Done] ExtendedにLADDER（既存フィルターとの混合）、DRIVE（入力と出力の飽和）、FEEDBACK（各ボイスの4段目の出力を入力へ戻す量）、6／12／18／24dB/octの傾き切り替えを追加。既存のカットオフ、レゾナンス、フィルターEGと連動し、5音ポリフォニーを維持。LADDERを上げて使用します。初期値はLADDER／DRIVE／FEEDBACKすべて0。SYNTH/05で追加処理をバイパスし、設定は保持します。
Extended adds LADDER blend, DRIVE saturation, FEEDBACK from each voice's fourth filter stage, and 6/12/18/24dB/oct slopes. Raise LADDER to use the color path. Existing cutoff, resonance and filter envelope control both paths; five-voice polyphony remains. All three new knobs default to zero. SYNTH/05 bypasses the additions and retains settings.
Extended新增LADDER混合、DRIVE饱和、每个声部第四级输出的FEEDBACK反馈，以及6/12/18/24dB/oct斜率。提高LADDER即可使用。截止频率、共振和滤波包络共用，保留五音复音。三个新旋钮默认为0，SYNTH/05旁通新增处理并保留参数。

🟢 [Done] 新パラメーターは既存の拡張設定へ保存。旧形式の拡張設定は新項目を初期値で補完して読み込みます。既存の46項目の音色スロット形式は維持。音声処理は既存のオーバーサンプリング内で実行し、切り替え・深度・傾きを平滑化します。
Color settings save with expression settings, with defaults supplied when decoding older data. The original 46-setting voice schema is unchanged. The color path runs inside existing oversampling with smoothed controls.
新参数随扩展设置保存，旧数据缺少的新项按默认值补全。原有46项音色格式保持不变，滤波在现有过采样内运行并平滑控制变化。

🟢 [Done] 44.1／48／96kHzで全傾き、最大共振・歪み・フィードバック、ステレオ出力、SYNTH/05バイパス、旧設定の移行と既存音源の回帰テストを検証。アプリのビルドと288／343／398／1000pt幅のパネル描画を確認。
Verified slopes, maximum resonance/drive/feedback, stereo output, bypass, migration and existing audio regressions at three sample rates; built the app and inspected panel renders at four widths.
已验证三种采样率的斜率、最大共振／驱动／反馈、立体声输出、旁通、旧设置迁移及现有音源回归，完成应用构建与四种宽度的面板检查。

⭕️ [Pending] iPhone実機での負荷・操作・聴感、および参考実機との比較。
Physical iPhone performance, interaction, listening and reference hardware comparisons remain pending.
iPhone实机性能、交互、听感及参考硬件对比待验证。

参考 / Reference / 参考：[Moog Subsequent 37 official manual](https://api.moogmusic.com/sites/default/files/2017-09/Subsequent_37_Manual_0.pdf)。機能構成を参考にした独自DSPで、実機の回路・音響特性の完全再現ではありません。Original inspired DSP, not a circuit-accurate hardware emulation. 参考功能设计的独立DSP，并非硬件电路精确仿真。
