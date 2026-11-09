
## Node presentation adaptation (2026-11-09)

`render-reference/scene.rs` and `render-reference/theme.rs` preserve the upstream node-presentation sources used as a design/code reference (MIT selected). The native adaptation is `PatchNodeCard.swift` and the updated `EffectsPatchView.swift`: tinted header, symbol badge, 2pt selected border/halo, ring/core ports, role-colored cables and one shared anchor geometry. Existing metal enclosure colors remain; brighter role accents are reserved for the graph. Small static processing glyphs are symbols, not audio meters or measured DSP response curves. No wgpu runtime or continuous render timer is introduced. Graph storage, routing validation and source UNGE files remain unchanged.

日本語：ノードのヘッダー、選択枠、端子、役割色、ケーブルの色対応をネイティブSwiftUIへ適用。処理グリフは静的なシンボルで、実測メーターではありません。

简体中文：将节点标题、选中边框、端口、角色配色与线缆颜色关联适配至SwiftUI。处理图形为静态符号，并非实时测量表。
