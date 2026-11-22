// macOS native-input regression. Concatenate the Piano port section from
// SharedPerformancePanel.swift (starting with its imports) before this file.
@main
private struct PianoKeyboardRegression {
    @MainActor static func main() {
let layout = PianoKeyboardLayout(white:[60,62,64,65,67,69,71,72])
for size in [CGSize(width:180,height:35),CGSize(width:300,height:75),CGSize(width:550,height:110)] {
    let step = size.width/8
    for (index,note) in layout.white.enumerated() {
        precondition(layout.note(at:CGPoint(x:(CGFloat(index)+0.5)*step,y:size.height*0.9),size:size)==note)
    }
    for key in layout.black {
        let r=layout.blackFrame(key,size:size)
        precondition(layout.note(at:CGPoint(x:r.midX,y:r.midY),size:size)==key.note)
        precondition(layout.note(at:CGPoint(x:r.midX,y:size.height*0.9),size:size) != key.note)
    }
    precondition(layout.note(at:CGPoint(x:-1,y:0),size:size)==nil)
}
_ = NSApplication.shared
let window = NSWindow(contentRect:NSRect(x:0,y:0,width:400,height:100),styleMask:[.borderless],backing:.buffered,defer:false)
let mouse = PianoTouchSurface.MouseView(frame:NSRect(x:0,y:0,width:400,height:100))
window.contentView=mouse
mouse.layout=layout
var received=[Set<Int>]()
mouse.onTouches={received.append($0)}
func event(_ type:NSEvent.EventType,_ x:CGFloat,_ y:CGFloat)->NSEvent {
    NSEvent.mouseEvent(with:type,location:CGPoint(x:x,y:100-y),modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
}
mouse.mouseDown(with:event(.leftMouseDown,25,90))
mouse.mouseDragged(with:event(.leftMouseDragged,50,20))
mouse.mouseDragged(with:event(.leftMouseDragged,125,90))
mouse.mouseDragged(with:event(.leftMouseDragged,-1,90))
mouse.mouseUp(with:event(.leftMouseUp,-1,90))
precondition(received == [Set([60]),Set([61]),Set([64]),Set<Int>(),Set<Int>()])

print("Piano keyboard hit geometry and native mouse drag/release passed")

    }
}
