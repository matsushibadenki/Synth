// ProductKeyboardMouseRegression covers window event delivery through this geometry.
import Foundation

@main
private struct PianoKeyboardRegression {
    static func main() {
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
        for count in [15,25,37] {
            let first = count == 15 ? 60 : 48
            let white = (first..<(first+count)).filter { [0,2,4,5,7,9,11].contains($0%12) }
            let adaptive = PianoKeyboardLayout(white:white)
            precondition(adaptive.white.count+adaptive.black.count == count)
            for size in [CGSize(width:210,height:70),CGSize(width:550,height:84),CGSize(width:1000,height:144)] {
                let step = size.width/CGFloat(white.count)
                for (index,note) in white.enumerated() {
                    precondition(adaptive.note(at:CGPoint(x:(CGFloat(index)+0.5)*step,y:size.height*0.9),size:size)==note)
                }
                for key in adaptive.black {
                    let r = adaptive.blackFrame(key,size:size)
                    precondition(adaptive.note(at:CGPoint(x:r.midX,y:r.midY),size:size)==key.note)
                }
            }
        }
        print("Piano keyboard hit geometry passed for 15, 25 and 37 keys")
    }
}
