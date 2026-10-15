// Concatenate Rev3Parameters.swift and MetalPanelRenderer.swift before this file and compile with swiftc.
import ImageIO
import UniformTypeIdentifiers

guard let device = MTLCreateSystemDefaultDevice() else {
    fatalError("Metal device unavailable: GPU check cannot run in this environment")
}
let renderer = try MetalPanelRenderer(device: device)
for width in [288, 343, 382, 736, 1100] {
    let layout = PanelLayout(columns: PanelLayout.columns(for:CGFloat(width)))
    for i in 0..<26 {
        let p = layout.point(layout.knob(i))
        precondition(p.x > 0 && p.x < 1 && p.y > 0 && p.y < 1)
    }
    for index in 0..<22 {
        let p=layout.point(layout.toggle(index))
        precondition(p.x>0 && p.x<1 && p.y>0 && p.y<1,"All switches must fit")
    }
    for index in 0..<8 {
        for x in [-layout.keyWidth/2, layout.keyWidth/2] {
            for y: Float in [-0.5, 0.5] {
                let p = layout.point(SIMD3(layout.keyX(index)+x, layout.keyY+y, 0.22))
                precondition(p.x > 0 && p.x < 1 && p.y > 0 && p.y < 1, "Keyboard must fit the surface")
            }
        }
    }
    let defaults=SynthParameters()
    renderer.update(layout:layout,values:Rev3.knobs.map { $0.normalized(defaults) }+[0.5,0],activeNotes:[60,66],switches:Rev3.switches.map { defaults[keyPath:$0.key] })
    let image = try renderer.preview(width: width, height: Int(Float(width) / layout.aspect))
    let data = image.dataProvider!.data! as Data
    precondition(Set(data).count > 32, "GPU must render shaded geometry")
    let url = URL(fileURLWithPath: "/tmp/synth-panel-\(width).png")
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    precondition(CGImageDestinationFinalize(destination))
    print("Metal render passed: \(width)px → \(url.path)")
}

let layout = PanelLayout(columns: 2)
renderer.update(layout: layout, values: Array(repeating: 0, count: 28), activeNotes: [], switches: Array(repeating:false,count:22))
let low = try renderer.preview(width: 736, height: 600).dataProvider!.data! as Data
renderer.update(layout: layout, values: Array(repeating: 1, count: 28), activeNotes: [60], switches: Array(repeating:true,count:22))
let high = try renderer.preview(width: 736, height: 600).dataProvider!.data! as Data
precondition(low != high, "Controls must visibly update the GPU geometry")
print("Control-state rendering passed")
