import SwiftUI

@MainActor
final class EffectsController: ObservableObject {
    private var editor: FXEditor
    let shared: SharedEffects
    @Published var error = ""
    @Published private(set) var loopState = 0
    @Published private(set) var loopSeconds: Float = 0
    private var lastTap: Date?
    private var presets: [FXSettings]
    private let storage: UserDefaults
    private let persistent: Bool
    var document: FXDocument { editor.document }
    var canUndo: Bool { editor.canUndo }; var canRedo: Bool { editor.canRedo }
    init(shared: SharedEffects, storage: UserDefaults = .standard, persistent: Bool = true) {
        self.shared=shared; self.storage=storage;self.persistent=persistent
        var saved=persistent ? storage.data(forKey:"synth.effects.document.v1").flatMap { try? JSONDecoder().decode(FXDocument.self,from:$0) }:shared.documentSnapshot()
        if let i=saved?.nodes.firstIndex(where:{$0.kind == .pedal}) { saved?.nodes[i].settings.loopAction=0; saved?.nodes[i].settings.loopSerial=0 }
        editor=(saved.flatMap { try? FXEditor($0) }) ?? (try! FXEditor(.initial))
        let fallback=(0..<3).map { mode -> FXSettings in
            var state=FXSettings(.pedal); state.mode=mode; state.enabled=true; return state
        }
        let savedPresets=persistent ? storage.data(forKey:"synth.effects.pedal.presets.v1").flatMap { try? JSONDecoder().decode([FXSettings].self,from:$0) }:nil
        presets=(savedPresets?.count == 3 && savedPresets!.allSatisfy { state in
            var doc=FXDocument.initial; doc.nodes[4].settings=state; return (try? doc.validate()) != nil
        }) ? savedPresets!:fallback
        publish(save:false)
    }
    func settings(_ kind: EffectKind) -> FXSettings { document.nodes.first { $0.kind == kind }!.settings }
    func execute(_ command: FXCommand) {
        do { try editor.execute(command); error=""; publish() }
        catch { self.error=message(error) }
    }
    func update(_ kind: EffectKind, _ edit: (inout FXSettings) -> Void) {
        var state=settings(kind); edit(&state); execute(.settings(kind.rawValue,state))
    }
    func preview(_ kind: EffectKind,index: Int,value: Float) {
        var doc=document
        let i=doc.nodes.firstIndex { $0.kind == kind }!
        doc.nodes[i].settings.values[index]=min(1,max(0,value))
        if let config=try? doc.configuration() { shared.set(config) }
    }
    func connect(from: Int,to: Int,port: String) { execute(.connect(FXEdge(from:from,to:to,port:port))) }
    func undo() { editor.undo(); error=""; publish() }
    func redo() { editor.redo(); error=""; publish() }
    func serial() {
        let chain=[0,1,2,3,4,5,6,8]
        execute(.batch(document.edges.map { .disconnect($0.id) } + zip(chain,chain.dropFirst()).map { .connect(FXEdge(from:$0,to:$1,port:"in")) }))
    }
    func parallel() {
        let edges=[FXEdge(from:0,to:1,port:"in"),FXEdge(from:1,to:2,port:"in"),FXEdge(from:0,to:3,port:"in"),FXEdge(from:2,to:7,port:"a"),FXEdge(from:3,to:7,port:"b"),FXEdge(from:7,to:8,port:"in")]
        execute(.batch(document.edges.map { .disconnect($0.id) } + edges.map { .connect($0) }))
    }
    func tap(_ kind: EffectKind) {
        let now=Date(); defer { lastTap=now }
        guard let lastTap else { return }
        let seconds=now.timeIntervalSince(lastTap)
        guard (0.025...2).contains(seconds) else { return }
        update(kind) { $0.values[0]=Float(log(seconds/0.025)/log(80)) }
    }
    func loop(_ action: Int) {
        update(.pedal) { state in state.enabled=true; state.mode=3 }; shared.sendLoop(action)
    }
    func recallPedal(_ index: Int) {
        var state=presets[index]
        let current=settings(.pedal)
        state.loopSerial=current.loopSerial; state.loopAction=current.loopAction
        execute(.settings(4,state))
    }
    func storePedal(_ index: Int) {
        presets[index]=settings(.pedal)
        if persistent, let data=try? JSONEncoder().encode(presets) { storage.set(data,forKey:"synth.effects.pedal.presets.v1") }
    }
    func refreshTelemetry() { let result=shared.readLoop(); loopState=result.0; loopSeconds=result.1 }
    func refreshHostedDocument() {
        let next=shared.documentSnapshot()
        guard next != document,let editor=try? FXEditor(next) else { return }
        self.editor=editor;objectWillChange.send()
    }
    private func publish(save: Bool=true) {
        objectWillChange.send()
        if let config=try? document.configuration() { shared.set(config,document:document) }
        if save && persistent, let data=try? JSONEncoder().encode(document) { storage.set(data,forKey:"synth.effects.document.v1") }
    }
    private func message(_ error: Error) -> String {
        switch error as? FXGraphError {
        case .cycle: return fxText("A feedback cycle is not allowed. Use the effect's feedback control.","循環接続はできません。エフェクト内のフィードバックを使用してください。","不能循环连接，请使用效果内的反馈控制。")
        case .occupied: return fxText("Input already connected. Remove its cable first, or use MIX A/B.","接続済みの入力です。先にケーブルを外すか、MIX A/Bを使用してください。","输入已连接，请先移除连线或使用MIX A/B。")
        case .duplicate: return fxText("Cable already connected.","すでに接続されています。","连线已存在。")
        default: return fxText("Invalid graph or port.","グラフまたはポートが不正です。","图或端口无效。")
        }
    }
}
