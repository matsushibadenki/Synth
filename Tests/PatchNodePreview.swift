// Compile with all Sources/SynthApp except SynthApp.swift. Native snapshot QA;
// this harness creates no SynthEngine/audio device and uses no persistent FX storage.
import SwiftUI
import AppKit

@main struct PatchNodePreview {
    @MainActor static func main() throws {
        let app=NSApplication.shared;app.setActivationPolicy(.accessory);app.finishLaunching()
        let rack=EffectsController(shared:SharedEffects(),persistent:false)
        for kind in [EffectKind.dimension,.sky,.time,.ring] { rack.update(kind) { $0.enabled=true } }
        let original=rack.document
        let directory=CommandLine.arguments.dropFirst().first ?? "/tmp/synth-node-previews"
        try FileManager.default.createDirectory(atPath:directory,withIntermediateDirectories:true)
        func capture<V:View>(_ root:V,_ size:NSSize,_ name:String) throws {
            let window=NSWindow(contentRect:NSRect(origin:.zero,size:size),styleMask:[.borderless],backing:.buffered,defer:false)
            window.isReleasedWhenClosed=false
            let view=NSHostingView(rootView:root.preferredColorScheme(.dark));window.contentView=view
            window.orderFrontRegardless();view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until:Date().addingTimeInterval(0.15))
            let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds)!
            view.cacheDisplay(in:view.bounds,to:bitmap)
            try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:directory+"/"+name+".png"))
            window.close()
        }
        for width:CGFloat in [320,430,1100] {
            try capture(EffectsPatchView(rack:rack,editEffect:{_ in}),NSSize(width:width,height:650),"patch-\(Int(width))")
        }
        try capture(
            VStack(spacing:18) {
                ForEach(0..<3) { row in
                    HStack(spacing:18) {
                        ForEach(Array(rack.document.nodes[(row*3)..<(row*3+3)])) { node in
                            PatchNodeCard(node:node,selected:node.id==4,select:{},edit:{},bypass:{},moving:{_ in},moved:{_ in})
                        }
                    }
                }
            }.padding(24).background(InstrumentFinish.backdrop),NSSize(width:756,height:532),"node-faces")
        precondition(rack.document==original,"Rendering must not change graph state")
        print("Native node snapshots: 320/430/1100pt and selected/bypass gallery → \(directory)")
    }
}
