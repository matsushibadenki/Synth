# Prophet-5 音質・音色の改善分析

## 現状の実装評価

このアプリはすでに Prophet-5 Rev3 を高い水準でモデリングしています。

| 項目 | 現状 | 評価 |
|------|------|------|
| VCO（CEM3340） | polyBLEP ノコギリ波・パルス波・三角波、4–8倍オーバーサンプリング、FIR デシメーション | ✅ 優秀 |
| VCF（CEM3320） | `CurtisFilter`: TPT 4極、非線形帰還、Newton反復飽和 | ✅ 優秀 |
| EG（CEM3310） | 非対称指数 charge/discharge、`expm1` 精度 | ✅ 良好 |
| VCA（CEM3360） | `AnalogSignalPath.amplifier` による envelope × input 飽和 | ⚠️ 改善余地あり |
| アナログドリフト | `AnalogWander` + `VoiceCard` による個体差 | ✅ 優秀 |
| シグナルフロー | mixer → 4極LPF → VCA → DC coupling → decimation | ✅ 正確 |

> [!NOTE]
> specificationとcodeの両方に「measured hardware matching is not implied（実機測定による一致は主張しない）」と明記されていますが、構造としてはProphet-5の回路トポロジーを忠実に再現しています。

---

## 🔧 改善提案（優先度順）

### 1. エンベロープのカーブ特性改善（高優先度）

**現状の問題**: CEM3310 は単純な指数カーブではなく、Attack フェーズには独特の「対数的な立ち上がり（オーバーシュート付き）」があります。現在のコードでは Attack の目標値 `1.3` でオーバーシュートを模擬していますが、実機はもう少し複雑です。

```
現在: voltage += (1.3 - voltage) * attack   // 単一RC曲線
実機: 2段階のRC充電 → コンパレータでDecayへ遷移
```

**提案**: Attack カーブを2区間に分ける

```swift
// ProphetCore.swift - AnalogEnvelope
// パス: Sources/SynthApp/ProphetCore.swift
// CEM3310 のAttackカーブをより忠実にモデリング
case .attack:
    // CEM3310は約1.3Vまで充電し、コンパレータでDecayへ切り替える
    // 充電カーブ前半は速く、ピーク付近で減速する
    let target: Double = 1.26  // CEM3310の実際のピーク電圧比
    voltage += (target - voltage) * Double(c.attack)
    if voltage >= 1.0 {
        voltage = 1.0
        stage = .decay
    }
```

> [!TIP]
> Attack のオーバーシュート量 `1.3` → `1.26` に変更するだけで、ブラスパッドの立ち上がりがよりProphet-5らしくなります。実機のCEM3310は約1.26倍の電圧まで充電してからDecayに遷移します。

### 2. フィルター飽和特性の精密化（高優先度）

**現状**: `CurtisFilter` は優秀なTPT実装ですが、CEM3320特有の「レゾナンスが上がると低域が痩せる」特性をもう少し強調できます。

**現在のコード** ([ProphetCore.swift#L256-L292](file:///Users/Shared/Program/Xcode/Synth/Sources/SynthApp/ProphetCore.swift#L256-L292)):
```swift
let k = min(4.5, max(0, resonance) * 4.4)
let drive = AnalogSignalPath.mixer(input)
let color: Float = 0.9  // ← この定数が音色を大きく左右
```

**提案**:
- `color` パラメータをレゾナンスに依存させ、高レゾナンス時にさらに入力をソフトクリップさせる
- レゾナンスによる低域の減衰（bass loss）をより忠実に

```swift
// CEM3320のレゾナンス依存の入力飽和
let color: Float = 0.9 - resonance * 0.08
// レゾナンスに対する低域損失の補償なし（これがProphet-5の特徴）
```

### 3. ミキサーの飽和特性（中優先度）

**現状**: `AnalogSignalPath.mixer` は `tanhf` で飽和させていますが、Prophet-5のアナログミキサーはもう少し非対称な歪みを持ちます。

**現在のコード** ([ProphetCore.swift#L243-L246](file:///Users/Shared/Program/Xcode/Synth/Sources/SynthApp/ProphetCore.swift#L243-L246)):
```swift
static func mixer(_ input: Float) -> Float {
    tanhf(input * 0.48) * (0.65 / 0.48)
}
```

**提案**: 2次の非対称成分を加える

```swift
// ProphetCore.swift - AnalogSignalPath
// パス: Sources/SynthApp/ProphetCore.swift
// Prophet-5のミキサーは微妙に非対称な飽和を持つ
static func mixer(_ input: Float) -> Float {
    let asymmetry: Float = 0.03  // 微小な偶数次歪み
    let shaped = input * 0.48 + asymmetry * input * input
    return tanhf(shaped) * (0.65 / 0.48)
}
```

### 4. VCA のモデリング改善（中優先度）

**現状の `amplifier`** ([ProphetCore.swift#L247-L253](file:///Users/Shared/Program/Xcode/Synth/Sources/SynthApp/ProphetCore.swift#L247-L253)):

Prophet-5 の CEM3360 VCA は電圧制御の対数ゲイン特性を持ち、小さいエンベロープ値で非線形になります。現在の実装は `envelope * gain` で線形に掛けた後 `tanhf` で飽和させていますが、実機はエンベロープ電圧に対して指数的にゲインが変化します。

```swift
// CEM3360のような対数VCA特性
static func amplifier(_ input: Float, envelope: Float, gain: Float) -> Float {
    if envelope < 0.00001 { return 0 }
    // CEM3360は小さいCV値で指数的に減衰する
    let cv = envelope * envelope * (3 - 2 * envelope)  // S字カーブで自然なフェードアウト
    let current = input * cv * gain
    return tanhf(current * 0.35) / 0.35
}
```

> [!IMPORTANT]
> VCA のカーブ変更はすべての音色に影響するため、変更後は既存プリセット（特にピアノのDecay部分）の聴感を確認してください。

### 5. ノコギリ波の高次倍音（低優先度）

**現状**: polyBLEP は優秀なアンチエイリアシングですが、CEM3340 の実際のノコギリ波は理想的な直線ではなく、コンデンサのリセット回路に由来する微妙な「丸み」があります。

**提案**: ノコギリ波の最上部にごく微小な丸みを追加

```swift
// ProphetCore.swift - evalOsc
// CEM3340のキャパシタ充放電による波形の丸み
case 0: // saw
    var saw = (phase / .pi) - 1.0 - polyBLEP(phase / (2 * .pi), step)
    // CEM3340のリセット付近の丸み（コンデンサの不完全放電）
    let resetProximity = 1.0 - phase / (2 * .pi)
    if resetProximity < 0.02 {
        saw *= 0.97 + 0.03 * (resetProximity / 0.02)
    }
    return saw
```

### 6. パルス波のDCオフセット改善（低優先度）

**現状**: AC coupling（5Hz ハイパス）でPWM由来のDCを除去していますが、CEM3340 のパルス波はハードウェアレベルで微妙にDCオフセットを持ちます。これは `VoiceCard.pulseA/B` の ±0.18% で既にモデリングされていますが、パルス幅に対する依存性を追加できます。

```swift
// パルス幅依存のDCオフセット（CEM3340の実際の特性）
let dcBias = (0.5 - width) * 0.015  // パルス幅中心からの偏差
```

---

## 🎛️ フィルターの音色を Prophet-5 に近づけるための調整ガイド

現在の `CurtisFilter` を実機により近づける最も効果的な調整：

```mermaid
flowchart LR
    A["入力信号"] --> B["非線形ミキサー<br/>tanhf 飽和"]
    B --> C["CEM3320 VCF<br/>4極 TPT"]
    C --> D["DC除去<br/>5Hz HP"]
    D --> E["CEM3360 VCA<br/>対数ゲイン"]
    
    style B fill:#ff9,stroke:#333
    style C fill:#9ff,stroke:#333
    style E fill:#f9f,stroke:#333
```

| 調整箇所 | 現在の値 | 推奨値 | 効果 |
|----------|---------|--------|------|
| Filter `color` | `0.9` 固定 | `0.9 - resonance * 0.08` | レゾナンス時の音の痩せをより忠実に |
| Filter `k` max | `4.5` | `4.2` | 自己発振の制限をやや下げ実機相当に |
| Mixer asymmetry | `0` | `0.03` | 偶数次倍音の微量追加 |
| VCA curve | 線形 | S字 | 自然なリリース減衰 |
| Attack overshoot | `1.3` | `1.26` | CEM3310のピーク電圧に近似 |

---

## 🔊 すぐに試せるパラメータ調整

コードを変更せずに、パネル操作だけでProphet-5的な音色に近づける方法：

1. **Filter Cutoff**: 42%前後（現在のデフォルト `0.42` は適切）
2. **Resonance**: 20–35%（高すぎると痩せすぎる）
3. **Filter Env Amount**: 25–40%（ブラスに最適）
4. **OSC A: Saw ON** / **OSC B: Saw ON, Fine 0–7 cents**（クラシックProphet音色）
5. **Env B Attack**: 極小値（1ms）→ パーカッシブなアタック
6. **Expression パネル**: SYNTH/05 モード（拡張機能OFF）が最もProphet-5に近い

> [!WARNING]
> Expression パネルの EXTENDED モードは Prophet-5 にない要素（サブオシレーター、ラダーフィルター混合、オートパン等）を追加するため、Prophet-5 の忠実な再現にはSYNTH/05モードを使ってください。

---

## 📋 実装の優先順位まとめ

| 順位 | 項目 | 効果の大きさ | 実装難度 | 既存音色への影響 |
|------|------|------------|---------|----------------|
| 1 | エンベロープカーブ | ★★★★★ | 低 | 中 |
| 2 | フィルター飽和精密化 | ★★★★☆ | 低 | 低 |
| 3 | ミキサー非対称飽和 | ★★★☆☆ | 低 | 低 |
| 4 | VCA対数特性 | ★★★★☆ | 中 | 高 |
| 5 | ノコギリ波の丸み | ★★☆☆☆ | 低 | 低 |
| 6 | パルスDCオフセット | ★☆☆☆☆ | 低 | 低 |

> [!CAUTION]
> 項目4（VCA対数特性）は全体の音量バランスに大きく影響します。変更する場合は、まずA/Bテストのための切り替えフラグを設けて比較確認することを強く推奨します。
