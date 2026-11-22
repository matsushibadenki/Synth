// Compile all Sources/SynthApp/*.swift with -D SYNTH_AUDIO_UNIT -parse-as-library, then this file.
import SwiftUI
import AppKit
import AVFoundation
import AudioToolbox
@main struct Check {
 @MainActor static func main() throws {
  _ = NSApplication.shared
  let params=SharedSynthParameters()
  params.set { $0.envBRelease=0.001; $0.releaseEnabled=true }
  ProphetLikeAudioUnit.sharedParameters=params
  let unit=try ProphetLikeAudioUnit(componentDescription:AudioComponentDescription(componentType:kAudioUnitType_Generator,componentSubType:0x50723535,componentManufacturer:0x53796E74,componentFlags:0,componentFlagsMask:0))
  try unit.allocateRenderResources()
  let controls=(0..<28).map { _ in PanelControl(label:"",title:"",value:.constant(0.5),range:0...1) }
  let buffer=AVAudioPCMBuffer(pcmFormat:unit.outputBusses[0].format,frameCapacity:256)!
  var flags=AudioUnitRenderActionFlags(),time=AudioTimeStamp()
  time.mFlags = .sampleTimeValid
  func peak(_ blocks:Int)->Float {
   var result:Float=0
   for _ in 0..<blocks {
    precondition(unit.internalRenderBlock(&flags,&time,256,0,buffer.mutableAudioBufferList,nil,nil)==noErr)
    for i in 0..<256 { result=max(result,abs(buffer.floatChannelData![0][i])) }
    time.mSampleTime += 256
   }
   return result
  }
  var events=[String]()
  let layout=PanelLayout(columns:2,keyboardOnly:true)
  let white=(48...84).filter { [0,2,4,5,7,9,11].contains($0%12) }
  let root=SharedMetalKeyboard(layout:layout,keyNotes:white,controls:controls,switches:[Bool](repeating:false,count:22),enabled:true,changed:{},noteOn:{events.append("on\($0)");unit.noteOn($0,velocity:1)},noteOff:{events.append("off\($0)");unit.noteOff($0)})
  let window=NSWindow(contentRect:NSRect(x:0,y:0,width:740,height:96),styleMask:[.titled],backing:.buffered,defer:false)
  let host=NSHostingView(rootView:root);window.contentView=host;window.makeKeyAndOrderFront(nil)
  RunLoop.main.run(until:Date().addingTimeInterval(0.5))
  let left=layout.point(SIMD3(layout.keyX(0)-layout.keyWidth/2,layout.keyY,0.16)).x*740
  let step=(740-left-6)/CGFloat(white.count)
  func send(_ type:NSEvent.EventType,_ x:CGFloat,_ y:CGFloat) {
   let point=NSPoint(x:x,y:96-y)
   let hit=host.hitTest(host.convert(point,from:nil))
   print("hit \(String(describing:hit))")
   let e=NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
   window.sendEvent(e)
   RunLoop.main.run(until:Date().addingTimeInterval(0.05))
  }
  send(.leftMouseDown,left+step/2,80)
  let whitePeak=peak(20)
  precondition(whitePeak>0.001,"Window-delivered white-key click must produce audio")
  send(.leftMouseUp,left+step/2,80)
  send(.leftMouseDown,left+step,20)
  let blackPeak=peak(20)
  precondition(blackPeak>0.001,"Window-delivered black-key click must produce audio")
  send(.leftMouseDragged,left+step*2.5,80)
  send(.leftMouseDragged,-1,80)
  send(.leftMouseDragged,left+step/2,80)
  send(.leftMouseUp,left+step/2,80)
  print("EVENTS",events)
  precondition(events == ["on48","off48","on49","off49","on52","off52","on48","off48"])
  _ = peak(200)
  precondition(peak(2)<0.0001,"Mouse release must stop sounding notes")
  print("Product mouse routing passed; white peak",whitePeak,"black peak",blackPeak)
 }
}
