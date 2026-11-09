# SYNTH/05 Audio Unit

🟢 [Done] AUv3 instrument for macOS 13+ and iOS 17+, with the existing SwiftUI/Metal interface, MIDI velocity, sustain, wheels and the native FX graph. Audio belongs to the host: the extension starts neither an AVAudioEngine nor CoreMIDI device connections. Each instance owns its patch, FX settings and render state.

AUv3インストゥルメントとして既存のUIとSYNTH/05表記を維持しています。ホストからのMIDIは発音位置をブロック内で分割して処理し、ベロシティ、サステイン、Pitch／Modに反映。アプリ版は従来どおり単独で演奏できます。AU内の電源ボタンは無効になり、音声の開始／停止はホストが管理します。

AUv3乐器保留原有UI及SYNTH/05名称。宿主MIDI按块内事件位置分段处理，支持力度、延音与弯音／调制。独立应用仍可单独演奏；扩展不启动自己的音频引擎或设备MIDI连接，电源由宿主管理。

## Build / ビルド / 构建

Open [`Synth05.xcodeproj`](../../Synth05.xcodeproj) in Xcode. Choose **SYNTH05-macOS** or **SYNTH05-iOS**. Both application targets embed their matching AUv3 extension. Choose a signing team for physical iOS devices/distribution. The checked-in project is generated from [`project.yml`](../../project.yml); after adding files or changing targets, regenerate with `xcodegen generate`.

Xcodeでプロジェクトを開き、macOS／iOSのスキームを選んでビルドします。拡張は親アプリに含まれます。macOSではアプリを通常のアプリ配置先へ置いて一度起動し、AUv3対応DAWの音源一覧から **SYNTH/05** を選びます。今回の開発用ビルドはローカル署名です。

在Xcode中选择macOS／iOS方案构建，扩展会嵌入父应用。macOS将应用放至常用应用目录并启动一次，然后在支持AUv3的DAW乐器列表选择 **SYNTH/05**。开发构建采用本地签名。

```sh
# macOS local development build; no account/team needed for this ad-hoc build.
xcodebuild -project Synth05.xcodeproj -scheme SYNTH05-macOS -configuration Debug -derivedDataPath build/DerivedData CODE_SIGN_IDENTITY=- build

# iOS Simulator compilation (not physical-device or DAW validation).
xcodebuild -project Synth05.xcodeproj -scheme SYNTH05-iOS -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath build/iOSDerivedData CODE_SIGNING_ALLOWED=NO build

# After the extension is registered on macOS:
auval -v aumu S05a Sy05
```

The instrument identifier is **aumu / S05a / Sy05**. This deliverable targets AUv3 hosts; an AUv2-only host needs a separate wrapper. Existing SwiftPM builds remain the standalone application; use the Xcode project to embed the extension.

## Host control and state / ホスト制御・保存 / 宿主控制与保存

🟢 [Done] Fifty AU parameters: 26 knobs, 22 switches, Pitch and Mod. Stable addresses: knobs **0–25**, switches **100–121**, Pitch **200**, Mod **201**. Values use the existing physical ranges; switch values are 0/1. Host step events are applied at their event offsets; existing DSP smoothing is retained. Linear host parameter ramps are not advertised (`CanRamp` is unset); incoming ramp events use the target as a step with the existing control slew.

🟢 [Done] The existing custom UI reports parameter edits to host observers. Unrelated UI edits preserve newer automation values. Host automation/state changes refresh the open UI. FX graph edits use per-instance storage and do not overwrite standalone FX defaults.

🟢 [Done] Host `fullState`/`fullStateForDocument` saves the patch, expression settings and FX graph/settings. Saved notes, stream formats, A-440/auto-tune commands, active MIDI state and recorded loop audio are excluded. State is versioned and validated before publication. The original 46-setting program format remains unchanged. Host reset clears voices, decimator and FX histories without allocating new DSP buffers; reallocation does not replay held voices from the old render lifetime.

ホストのセッション保存には音色・拡張設定・FX接続と設定を含めます。発音中のノート、録音ループの音声などは保存しません。FX／拡張パラメーターは状態保存に含みますが、今回の50項目のAUオートメーション対象には含めていません。ホストのリセット時は音声履歴を消去し、音色値は維持します。

宿主会保存音色、扩展设置及效果图／设置，不保存活动音符或录音循环音频。效果／扩展参数可保存状态，但不在本次50项AU自动化参数内。宿主重置会清除声音历史并保留音色参数。

## Verification / 検証 / 验证

🟢 [Done] macOS application/extension and iOS Simulator application/extension builds; Apple `auval` validation; separate-process host creation, custom UI request, state roundtrip and MIDI/velocity rendering without starting an output device.

🟢 [Done] Offline tests cover 44.1/48/96kHz event offsets, velocity-zero release, nil output buffers, end-of-block MIDI, 50-parameter access, public MIDI/parameter scheduling, instance isolation, expression/FX state, malformed state rejection, unrelated UI edits during automation, resource reallocation and host reset including delay tails. FX controller tests cover restoring hosted state without changing standalone defaults.

Tests: `Tests/AudioUnitRegression.swift`, `Tests/AudioUnitHostProbe.swift`, `Tests/EffectsControllerRegression.swift`, `Tests/EffectsRegression.swift`. The host probe is compiled with `swiftc -O -parse-as-library`; it requires the built extension to be registered. It does not start an audio output device.

⭕️ [Pending] Physical iPhone/iPad AUv3 hosts and controllers; commercial DAW session reopen, automation recording, offline bounce and UI resize behavior. This development-host validation is not a guarantee for every DAW or device. AUv2 wrapping, FX automation, linear parameter ramp processing and recorded-loop persistence remain future work.

実機iPhone／iPad、各DAWでのセッション再読込・オートメーション録音・バウンス・UIサイズ変更は保留です。開発環境の検証と実機／各ホストでの動作保証は区別します。

实体iPhone／iPad以及各DAW的工程重开、自动化录制、导出与界面缩放待验证。开发环境结果不代表所有宿主／设备均已验证。

API references: [AUAudioUnitFactory](https://developer.apple.com/documentation/audiotoolbox/auaudiounitfactory), [AUViewController](https://developer.apple.com/documentation/coreaudiokit/auviewcontroller), [AURenderEvent](https://developer.apple.com/documentation/audiotoolbox/aurenderevent).
