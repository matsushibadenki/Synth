// Concatenate Rev3Parameters.swift + MetalPanelRenderer.swift + this file.
import AppKit
guard let device=MTLCreateSystemDefaultDevice() else { fatalError("Metal unavailable") }
let renderer=try MetalPanelRenderer(device:device)
var values=Array(repeating:0.5,count:28),switches=Array(repeating:false,count:22)
let layout=PanelLayout(columns:3)
renderer.update(layout:layout,values:values,activeNotes:[],switches:switches)
precondition(renderer.meshRebuildCount == 1)
for frame in 0..<120 {
    values[12]=Double(frame)/120
    renderer.update(layout:layout,values:values,activeNotes:frame%2 == 0 ? [60,61]:[],switches:switches)
}
precondition(renderer.meshRebuildCount == 1 && renderer.meshPatchCount>120)
let rebuilds=renderer.meshRebuildCount
let uploads=renderer.bufferUploadCount
renderer.update(layout:layout,values:values,activeNotes:[],switches:switches)
precondition(renderer.meshRebuildCount == rebuilds && renderer.bufferUploadCount == uploads)
let keyboard=PanelLayout(columns:2,keyboardOnly:true)
renderer.update(layout:keyboard,values:values,activeNotes:[],switches:switches)
let keyboardUploads=renderer.bufferUploadCount
values[0]=0.3;switches[0].toggle()
renderer.update(layout:keyboard,values:values,activeNotes:[],switches:switches)
precondition(renderer.bufferUploadCount == keyboardUploads,"Hidden controls must not cause GPU buffer uploads")
values[27]=0.7
renderer.update(layout:keyboard,values:values,activeNotes:[60],switches:switches)
precondition(renderer.bufferUploadCount>keyboardUploads)
renderer.update(layout:PanelLayout(columns:1,masterVolumeOnly:true),values:values,activeNotes:[],switches:switches)
let masterUploads=renderer.bufferUploadCount
values[1]=0.8
renderer.update(layout:PanelLayout(columns:1,masterVolumeOnly:true),values:values,activeNotes:[],switches:switches)
precondition(renderer.bufferUploadCount == masterUploads)
values[25]=0.2
renderer.update(layout:PanelLayout(columns:1,masterVolumeOnly:true),values:values,activeNotes:[],switches:switches)
precondition(renderer.bufferUploadCount == masterUploads+1)
print("Metal cache: incremental geometry, hidden controls, layout invalidation and uploads passed")
