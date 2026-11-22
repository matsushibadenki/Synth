// Compile Sources/SynthApp/*.swift with -D SYNTH_AUDIO_UNIT -parse-as-library, then this file.
// Opens a test window and starts the real standalone audio engine.
import SwiftUI
import AVFoundation
private final class AudioMeter {
 let lock=NSLock()
 private var maximum:Float=0
 func capture(_ buffer:AVAudioPCMBuffer) {
  guard let channels=buffer.floatChannelData else { return }
  var peak:Float=0
  for i in 0..<Int(buffer.frameLength) { peak=max(peak,abs(channels[0][i])) }
  lock.lock();maximum=max(maximum,peak);lock.unlock()
 }
 var peak:Float { lock.lock();defer {lock.unlock()};return maximum }
}
@main struct AppKeyboardMouseRegression {
 @MainActor static func main() throws {
  _ = NSApplication.shared
  let engine=SynthEngine()
  let window=NSWindow(contentRect:NSRect(x:100,y:100,width:900,height:650),styleMask:[.titled],backing:.buffered,defer:false)
  let host=NSHostingView(rootView:ContentView(engine:engine));window.contentView=host;window.makeKeyAndOrderFront(nil)
  RunLoop.main.run(until:Date().addingTimeInterval(2))
  print("running",engine.isRunning)
  guard let graph=Mirror(reflecting:engine).children.first(where:{$0.label == "engine"})?.value as? AVAudioEngine else { fatalError("Missing standalone graph") }
  let meter=AudioMeter()
  graph.mainMixerNode.installTap(onBus:0,bufferSize:256,format:nil) { buffer,_ in meter.capture(buffer) }
  func find(_ v:NSView)->NSView? {
   if NSStringFromClass(type(of:v)).contains("KeyboardMouseSurface") && NSStringFromClass(type(of:v)).contains("MouseView") {return v}
   for c in v.subviews { if let found=find(c) {return found} };return nil
  }
  guard let surface=find(host) else { fatalError("No product mouse surface") }
  print("surface",surface.frame)
  let size=surface.bounds.size,layout=PanelLayout(columns:size.width>=600 ? 2:1,keyboardOnly:true)
  let left=layout.point(SIMD3(layout.keyX(0)-layout.keyWidth/2,layout.keyY,0.16)).x*size.width
  func send(_ type:NSEvent.EventType) {
   let point=surface.convert(NSPoint(x:left+10,y:size.height-20),to:nil)
   print("hit",String(describing:host.hitTest(host.convert(point,from:nil))))
   NSApp.sendEvent(NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!)
   RunLoop.main.run(until:Date().addingTimeInterval(0.2))
  }
  send(.leftMouseDown)
  print("gate",engine.gateOn,"note",engine.midiNote)
  precondition(engine.gateOn)
  precondition(meter.peak>0.001,"Product source node must deliver audible-level signal to the mixer")
  print("Standalone mixer peak",meter.peak)
  send(.leftMouseUp)
  precondition(!engine.gateOn)
  graph.mainMixerNode.removeTap(onBus:0)
  engine.stop()
  precondition(!engine.isRunning)
  for _ in 0..<3 {
   engine.start()
   precondition(engine.isRunning && engine.startupError == nil,"Standalone restart must not depend on component registration")
   engine.stop()
  }
  print("Full ContentView + SynthEngine mouse input passed")
 }
}
