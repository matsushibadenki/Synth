// Concatenate Rev3Parameters.swift and MetalPanelRenderer.swift before this file and compile with swiftc.
import AppKit
import ImageIO
import UniformTypeIdentifiers

guard let device = MTLCreateSystemDefaultDevice() else {
    fatalError("Metal device unavailable: GPU check cannot run in this environment")
}
let renderer = try MetalPanelRenderer(device: device)
for width in [288, 343, 382, 736, 1100] {
    let layout = PanelLayout(columns: PanelLayout.columns(for:CGFloat(width)))
    // Changing the panel's height must not scale down physical controls.
    let projectedUnit = layout.point(SIMD3(1,0,0)).x-layout.point(.zero).x
    precondition(abs(projectedUnit*CGFloat(width)-CGFloat(width)/CGFloat(Float(layout.columns)*6.6+0.7)) < 0.001)
    let panelHeight=CGFloat(width)/CGFloat(layout.aspect)
    let fontSize=max(9,min(13,CGFloat(width)/CGFloat(layout.width+0.4)*0.19))
    let titleSize=max(9,min(13,CGFloat(width)/CGFloat(layout.width)*0.2))
    func lineHeight(_ size: CGFloat) -> CGFloat {
        let font=NSFont.monospacedSystemFont(ofSize:size,weight:.semibold)
        return ceil(font.ascender-font.descender+font.leading)
    }
    for (sectionIndex,section) in Rev3.sections.enumerated() {
        let headingY=layout.point(layout.title(sectionIndex)).y*panelHeight
        for index in section.knobs {
            let labelY=layout.point(layout.knobLabel(index)).y*panelHeight
            let gap=labelY-headingY-(lineHeight(titleSize)+2+lineHeight(fontSize))/2
            precondition(gap >= 4,"Section titles and knob labels need at least 4pt separation")
        }
        for index in section.switches {
            let switchY=layout.point(layout.toggleLabel(index)).y*panelHeight
            for knob in section.knobs {
                let valueY=layout.point(layout.knobValue(knob)).y*panelHeight
                let valueSize=max(9,min(13,CGFloat(width)/CGFloat(layout.width+0.4)*0.16))
                precondition(switchY-valueY-lineHeight(valueSize) >= 4,"Values and switch labels must not touch")
            }
        }
    }
    for section in Rev3.sections {
        for (a,b) in zip(section.switches,section.switches.dropFirst()) {
            let left=layout.point(layout.toggle(a)),right=layout.point(layout.toggle(b))
            precondition((right.x-left.x)*CGFloat(width) >= 44,"Switch hit targets must not overlap")
        }
    }
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

// The persistent keyboard is a separate Metal surface; changing presentation
// with the same column count must invalidate the renderer's mesh cache.
for width in [256, 288, 343, 382, 600, 720] {
    let columns=width >= 600 ? 2:1
    let keyboard=PanelLayout(columns:columns,keyboardOnly:true)
    let synth=PanelLayout(columns:columns,showsKeyboard:false)
    precondition(synth.height < PanelLayout(columns:columns).height)
    let scale=CGFloat(width)/CGFloat(keyboard.width+0.4)
    let wheelGap=(keyboard.point(keyboard.wheel(1)).x-keyboard.point(keyboard.wheel(0)).x)*CGFloat(width)
    // Narrowest device uses 256pt inside the common panel's two margins.
    precondition(wheelGap >= 40,"Wheel gesture areas must remain separable")
    for i in 0..<8 {
        for x in [-keyboard.keyWidth/2,keyboard.keyWidth/2] {
            for y: Float in [-0.5,0.5] {
                let p=keyboard.point(SIMD3(keyboard.keyX(i)+x,keyboard.keyY+y,0.22))
                precondition(p.x > 0 && p.x < 1 && p.y > 0 && p.y < 1,"Shared keyboard must fit")
            }
        }
    }
    renderer.update(layout:synth,values:Array(repeating:0.5,count:28),activeNotes:[60],switches:Array(repeating:false,count:22))
    let controlsImage=try renderer.preview(width:width,height:160).dataProvider!.data! as Data
    renderer.update(layout:keyboard,values:Array(repeating:0.5,count:28),activeNotes:[60],switches:Array(repeating:false,count:22))
    let keyboardComparable=try renderer.preview(width:width,height:160).dataProvider!.data! as Data
    precondition(controlsImage != keyboardComparable,"Presentation change must rebuild geometry")
    let height=Int(Float(width)/keyboard.aspect)
    let image=try renderer.preview(width:width,height:height)
    precondition(scale > 0)
    let url=URL(fileURLWithPath:"/tmp/synth-shared-keyboard-\(width).png")
    let destination=CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil)!
    CGImageDestinationAddImage(destination,image,nil); precondition(CGImageDestinationFinalize(destination))
    print("Shared Metal keyboard passed: \(width)pt")
}

let volumeLayout=PanelLayout(columns:1,masterVolumeOnly:true)
for width in [288,343,382,736,1088] {
    let synth=PanelLayout(columns:PanelLayout.columns(for:CGFloat(width)),showsKeyboard:false,omitsMasterVolume:true)
    let scale=CGFloat(width)/CGFloat(synth.width+0.4)
    let sourceUnit=(synth.point(SIMD3(1,0,0)).x-synth.point(.zero).x)*CGFloat(width)
    let sharedUnit=(volumeLayout.point(SIMD3(1,0,0)).x-volumeLayout.point(.zero).x)*scale*1.28
    precondition(abs(sourceUnit-sharedUnit)<0.001,"Shared master knob must retain the synth's projected size")
}
var volumeValues=Array(repeating:0.5,count:28)
volumeValues[25]=0
renderer.update(layout:volumeLayout,values:volumeValues,activeNotes:[],switches:Array(repeating:false,count:22))
let quietVolume=try renderer.preview(width:128,height:128).dataProvider!.data! as Data
volumeValues[25]=1
renderer.update(layout:volumeLayout,values:volumeValues,activeNotes:[],switches:Array(repeating:false,count:22))
let loudVolume=try renderer.preview(width:128,height:128).dataProvider!.data! as Data
precondition(quietVolume != loudVolume,"Shared master volume needle must update")
print("Shared master volume: original projected knob size at five widths / GPU state passed")
