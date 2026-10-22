import SwiftUI

@main struct EffectsControllerRegression {
    @MainActor static func main() throws {
        let name="local.synth.fx.regression.\(UUID().uuidString)"
        let store=UserDefaults(suiteName:name)!
        defer { store.removePersistentDomain(forName:name) }
        let shared=SharedEffects(), rack=EffectsController(shared:SharedEffects(),storage:store)
        rack.update(.sky) { $0.enabled=true; $0.mode=2; $0.values[0]=0.8 }
        rack.parallel()
        let restored=EffectsController(shared:shared,storage:store)
        precondition(restored.document == rack.document,"Auto-save reload")
        precondition(shared.trySnapshot()!.settings[2].mode == 2,"Restored settings published at startup")
        restored.loop(1)
        let serial=shared.trySnapshot()!.settings[4].loopSerial
        precondition(serial == 1 && shared.trySnapshot()!.settings[4].loopAction == 1)
        restored.update(.ring) { $0.enabled=true }
        precondition(shared.trySnapshot()!.settings[4].loopSerial == serial,"Parameter publication cannot drop loop event")
        restored.undo(); restored.redo()
        precondition(shared.trySnapshot()!.settings[4].loopSerial == serial,"Undo cannot trigger loop event")
        let nextShared=SharedEffects(), next=EffectsController(shared:SharedEffects(),storage:store)
        precondition(next.document.nodes[4].settings.loopAction == 0,"Transient event excluded from document")
        let another=EffectsController(shared:nextShared,storage:store)
        precondition(nextShared.trySnapshot()!.settings[4].loopSerial == 0,"Launch cannot start recording")
        another.recallPedal(1); another.update(.pedal) { $0.values[0]=0.73 }
        another.storePedal(1); another.recallPedal(0); another.recallPedal(1)
        precondition(abs(another.settings(.pedal).values[0]-0.73)<0.0001,"Pedal memory store and recall")
        shared.resetLoop()
        precondition(shared.trySnapshot()!.settings[4].loopAction == 0,"Power stop clears command")
        print("FX host: startup restore / pedal memories / transient loop commands / undo isolation passed")
    }
}
