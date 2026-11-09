# UNGE → Synth native adapter

Source: `/Users/littlebuddha/Desktop/alias/UNGE`, unge-core v0.1.0, MIT license selected. `model.rs` and `command.rs` are unmodified source snapshots. Copyright and license are preserved in `LICENSE-MIT`.

Synth reuses the model and command code by a native Swift port in `Sources/SynthApp/EffectsGraph.swift`: typed port direction/cardinality checks, stable Kahn topological layers, cycle rejection, transactional command batches, document placement, bounded undo/redo, and versioned serialization. The audio-specific schema fixes nine nodes (source, six processors, a two-input mixer, output), with one stereo resource per cable. It is a deliberately smaller host adapter, not a replacement distribution of UNGE and not compatible with UNGE's complete document JSON schema.

UNGE does not contain these audio effects. `EffectsDSP.swift` implements independent streaming DSP and compiles the validated graph to bounded routing steps. Its preallocated stereo buffers stay on the audio thread. The asynchronous UNGE executor, Tauri, wgpu, ACX, groups, and large-graph renderer are not linked into this SwiftUI/Metal host. The original UNGE directory is unchanged. Original Rust sources are preserved for provenance, not compiled by SwiftPM.

`Tests/EffectsRegression.swift` covers the adapted contracts: invalid edits preserve the document, single-input occupancy, cycle rejection, direction checks, deterministic routing order, undo/redo, serialization, silent disconnected inputs, and parallel mixer gains. The existing Synth Metal renderer is unchanged by this integration; the small graph uses SwiftUI Canvas and native accessible buttons.

日本語：UNGEのモデル／命令コードをSwiftへ移植した限定的なネイティブアダプターです。Rustの原本は変更せずライセンスとともに保存しています。非同期実行器・Tauri・wgpu全体の取り込みではありません。音声DSPは新規実装で、シンセ本体の46項目とは独立して保存します。

简体中文：这是将UNGE模型与命令代码移植到Swift的原生适配器。保留未修改的Rust源代码及许可证，不包含异步执行器、Tauri或wgpu整体集成。音频DSP为独立新实现，存储与合成器的46个参数分离。

Node presentation now also references upstream `unge-render` scene/theme sources. See [ADAPTATION.md](ADAPTATION.md) for provenance and native presentation scope.
