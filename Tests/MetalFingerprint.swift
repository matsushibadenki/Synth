// Concatenate Rev3Parameters.swift + a renderer revision + this file.
// Compare binary outputs from before/after builds with cmp.
import AppKit
let output=CommandLine.arguments.count>1 ? CommandLine.arguments[1]:"/tmp/synth-metal-fingerprint.bin"
guard let device=MTLCreateSystemDefaultDevice() else { fatalError("Metal unavailable") }
let renderer=try MetalPanelRenderer(device:device)
FileManager.default.createFile(atPath:output,contents:nil)
let file=try FileHandle(forWritingTo:URL(fileURLWithPath:output));try file.truncate(atOffset:0)
let layouts=[PanelLayout(columns:1),PanelLayout(columns:2),PanelLayout(columns:3),
    PanelLayout(columns:1,keyboardOnly:true),PanelLayout(columns:2,keyboardOnly:true),
    PanelLayout(columns:1,masterVolumeOnly:true),PanelLayout(columns:3,showsKeyboard:false,omitsMasterVolume:true)]
for (index,layout) in layouts.enumerated() {
    var values=Array(repeating:0.5,count:28),switches=Array(repeating:false,count:22)
    for frame in 0..<12 {
        try autoreleasepool {
            if frame == 1 { values=Array(repeating:0,count:28) }
            if frame == 2 { values=Array(repeating:1,count:28) }
            if frame>=3 {
                values[(frame*7)%28]=Double(frame%5)/4
                switches[(frame*3)%22].toggle()
            }
            if frame == 10 { values[12] = .nan;values[25] = .infinity }
            let notes: Set<Int>=frame%3 == 0 ? [60,61,64,66,72]:(frame%3 == 1 ? [62,63,65,67,70]:[])
            renderer.update(layout:layout,values:values,activeNotes:notes,switches:switches)
            let width=layout.masterVolumeOnly ? 96:(layout.columns == 1 ? 288:736)
            let image=try renderer.preview(width:width,height:Int(Float(width)/layout.aspect))
            let data=image.dataProvider!.data! as Data
            try file.write(contentsOf:Data("\(index),\(frame),\(data.count)\n".utf8))
            try file.write(contentsOf:data)
        }
    }
}
try file.close()
print("Metal fingerprint: 7 layouts × 12 states → \(output)")
