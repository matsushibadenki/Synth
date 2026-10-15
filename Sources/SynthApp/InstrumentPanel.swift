import SwiftUI
import MetalKit

func instrumentText(_ en: String, _ ja: String, _ zh: String) -> String {
    let language=Locale.preferredLanguages.first ?? "en"
    if language.hasPrefix("ja") { return ja }
    if language.hasPrefix("zh") { return zh }
    return en
}

struct PanelControl {
    let label: String
    let title: String
    let value: Binding<Double>
    let range: ClosedRange<Double>
    var logarithmic = false
    var quantized = false
    var resetValue: Double = 0.5
    var normalized: Double {
        let v=value.wrappedValue.isFinite ? min(range.upperBound,max(range.lowerBound,value.wrappedValue)) : range.lowerBound
        if logarithmic { return log(v/range.lowerBound)/log(range.upperBound/range.lowerBound) }
        return (v-range.lowerBound)/(range.upperBound-range.lowerBound)
    }
    func setNormalized(_ value: Double) {
        let n=min(1,max(0,value))
        let v=logarithmic ? range.lowerBound*pow(range.upperBound/range.lowerBound,n) : range.lowerBound+n*(range.upperBound-range.lowerBound)
        self.value.wrappedValue=quantized ? v.rounded() : v
    }
    var displayValue: String {
        if quantized { return String(format:"%+.0f st",value.wrappedValue-24) }
        if range.lowerBound < 0 { return String(format:"%+.1f",value.wrappedValue) }
        if logarithmic { return String(format: value.wrappedValue < 1 ? "%.3f" : "%.2f",value.wrappedValue) }
        return String(format:"%.1f",normalized*10)
    }
}
struct PanelSwitch {
    let label: String
    let title: String
    let value: Binding<Bool>
}

struct InstrumentPanel: View {
    @Environment(\.scenePhase) private var scenePhase
    let controls: [PanelControl]
    let switches: [PanelSwitch]
    let enabled: Bool
    let changed: () -> Void
    let noteOn: (Int) -> Void
    let noteOff: (Int) -> Void
    var onUnavailable: () -> Void = {}
    @State private var activeNotes=Set<Int>()
    @State private var info=false
    @State private var gpuUnavailable=false
    @State private var dragStart=[Int:Double]()
    @State private var panelColumns=1
    @State private var hovering: Int?

    var body: some View {
        VStack(spacing:8) {
            HStack {
                Text("SYNTH / 05 · REV 3").font(.system(size:15,weight:.semibold,design:.monospaced)).tracking(1)
                Spacer(minLength:8)
                Button { info.toggle() } label: { Image(systemName:"info.circle").frame(width:32,height:32) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(instrumentText("Controls","操作方法","操作说明"))
                    .help(instrumentText("Drag knobs and faders vertically.","ノブとフェーダーを上下にドラッグします。","上下拖动旋钮和推子。"))
                    .popover(isPresented:$info) {
                        Text(instrumentText("Drag knobs and faders vertically. Double-click to restore the initial setting. Hold keys to play.","ノブとフェーダーは上下にドラッグ。ダブルタップで初期値に戻ります。鍵盤を押して演奏します。","上下拖动旋钮和推子，双击恢复初始值，按住琴键演奏。"))
                            .padding(20).frame(idealWidth:280)
                    }
            }
            .foregroundStyle(Color(red:0.64,green:0.8,blue:0.78))
            GeometryReader { geo in
                let layout=PanelLayout(columns:PanelLayout.columns(for:geo.size.width))
                ZStack(alignment:.topLeading) {
                    MetalInstrumentSurface(layout:layout,values:controls.map(\.normalized),activeNotes:activeNotes,switches:switches.map { $0.value.wrappedValue },unavailable:$gpuUnavailable)
                        .accessibilityHidden(true)
                    ForEach(0..<26,id: \.self) { index in
                        control(index,layout:layout,size:geo.size)
                    }
                    ForEach(0..<22,id: \.self) { bank in
                        switchControl(bank,layout:layout,size:geo.size)
                    }
                    ForEach(Rev3.sections.indices,id: \.self) { index in
                        printed(Rev3.sections[index].title,at:layout.point(layout.title(index)),size:geo.size,pointSize:geo.size.width/CGFloat(layout.width)*0.2,pill:true)
                    }
                    ForEach(0..<2,id: \.self) { index in wheelControl(index,layout:layout,size:geo.size) }
                    ForEach(Array(layout.whiteNotes.enumerated()),id: \.element) { index,note in
                        key(note:note,center:SIMD3(layout.keyX(index),layout.keyY,0.16),width:layout.keyWidth-0.025,depth:1,layout:layout,size:geo.size)
                    }
                    ForEach(layout.blackNotes,id: \.note) { item in
                        key(note:item.note,center:SIMD3(layout.keyX(item.slot)+layout.keyWidth/2,layout.keyY+0.19,0.3),width:layout.keyWidth*0.56,depth:0.63,layout:layout,size:geo.size)
                    }
                }
            }
            .aspectRatio(CGFloat(PanelLayout(columns:panelColumns).aspect),contentMode:.fit)
            .overlay {
                GeometryReader { proxy in
                    Color.clear.onAppear { panelColumns=PanelLayout.columns(for:proxy.size.width) }
                        .onChange(of:proxy.size.width) { width in panelColumns=PanelLayout.columns(for:width) }
                }.allowsHitTesting(false)
            }
            .frame(height:gpuUnavailable ? 0:nil)
            .clipped()
            if gpuUnavailable {
                Label(instrumentText("Metal unavailable · use the editor below","Metalを利用できません。下の詳細設定から操作できます","Metal不可用，请使用下方音色编辑器"),systemImage:"exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .onChange(of:gpuUnavailable) { unavailable in if unavailable { onUnavailable() } }
        .onChange(of:enabled) { running in if !running { releaseKeys() } }
        .onChange(of:scenePhase) { phase in if phase != .active { releaseKeys() } }
        .onDisappear { releaseKeys() }
    }

    private func control(_ index: Int, layout: PanelLayout, size: CGSize) -> some View {
        let c=controls[index]
        let world=layout.knob(index)
        let p=layout.point(world)
        let screenScale=size.width/CGFloat(layout.width+0.4)
        let titlePoint=layout.point(world+SIMD3<Float>(0,0.77,-0.2))
        let valuePoint=layout.point(world+SIMD3<Float>(0,-0.62,-0.2))
        return Group {
            hitControl(index,width:max(44,screenScale*0.98),height:max(44,screenScale),travel:180)
                .position(x:p.x*size.width,y:p.y*size.height)
            printed(c.label,at:titlePoint,size:size,pointSize:screenScale*0.19,pill:false)
            printed(c.displayValue,at:valuePoint,size:size,pointSize:screenScale*0.16)
        }
    }

    private func hitControl(_ index: Int,width: CGFloat,height: CGFloat,travel: CGFloat) -> some View {
        let c=controls[index]
        return RoundedRectangle(cornerRadius:6)
            .fill(hovering==index ? Color.white.opacity(0.08):Color.clear)
            .frame(width:width,height:height)
            .contentShape(Rectangle())
            .onHover { hovering=$0 ? index:nil }
            .gesture(DragGesture(minimumDistance:1)
                .onChanged { event in
                    if dragStart[index]==nil { dragStart[index]=c.normalized }
                    c.setNormalized((dragStart[index] ?? c.normalized)-Double(event.translation.height/max(1,travel)))
                    changed()
                }
                .onEnded { _ in dragStart[index]=nil })
            .onTapGesture(count:2) { c.value.wrappedValue=c.resetValue; changed() }
            .accessibilityElement()
            .accessibilityLabel(c.title)
            .accessibilityValue(c.displayValue)
            .accessibilityAdjustableAction { direction in c.setNormalized(c.normalized+(direction == .increment ? 1.0:-1.0)*(c.quantized ? 1.0/48:0.02)); changed() }
            .help(c.title+" · "+c.displayValue)
    }

    private func printed(_ text: String,at point: CGPoint,size: CGSize,pointSize: CGFloat,pill: Bool=false) -> some View {
        Text(text)
            .font(.system(size:max(9,min(13,pointSize)),weight:.semibold,design:.monospaced))
            .tracking(-0.25)
            .foregroundStyle(Color(red:0.025,green:0.08,blue:0.085))
            .lineLimit(1).minimumScaleFactor(0.75)
            .padding(.horizontal,pill ? 5:0).padding(.vertical,pill ? 1:0)
            .overlay { if pill { Capsule().stroke(Color.black.opacity(0.6),lineWidth:0.7) } }
            .position(x:point.x*size.width,y:point.y*size.height)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func switchControl(_ bank: Int,layout: PanelLayout,size: CGSize) -> some View {
        let c=layout.toggle(bank),p=layout.point(c)
        return Group {
            Button { switches[bank].value.wrappedValue.toggle(); changed() } label: { Color.clear.frame(width:44,height:28).contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .position(x:p.x*size.width,y:p.y*size.height)
                .accessibilityLabel(switches[bank].title)
                .accessibilityValue(switches[bank].value.wrappedValue ? instrumentText("On","オン","开"):instrumentText("Off","オフ","关"))
                .help(switches[bank].title)
            printed(switches[bank].label,at:layout.point(c+SIMD3(0,0.29,-0.08)),size:size,pointSize:size.width/CGFloat(layout.width)*0.16)
        }
    }

    private func wheelControl(_ index: Int,layout: PanelLayout,size: CGSize) -> some View {
        let c=layout.wheel(index),p=layout.point(c)
        let scale=size.width/CGFloat(layout.width+0.4)
        return Group {
            hitControl(26+index,width:max(44,scale*0.85),height:scale*1.25,travel:scale*0.9)
                .position(x:p.x*size.width,y:p.y*size.height)
            Text(index == 0 ? "PITCH":"MOD")
                .font(.system(size:9,weight:.semibold,design:.monospaced)).foregroundStyle(.white)
                .position(x:layout.point(c+SIMD3(0,0.76,0)).x*size.width,y:layout.point(c+SIMD3(0,0.76,0)).y*size.height)
                .allowsHitTesting(false)
        }
    }

    private func key(note: Int,center: SIMD3<Float>,width: Float,depth: Float,layout: PanelLayout,size: CGSize) -> some View {
        let top=layout.point(center+SIMD3(0,depth/2,0)),bottom=layout.point(center-SIMD3(0,depth/2,0))
        let left=layout.point(center-SIMD3(width/2,0,0)),right=layout.point(center+SIMD3(width/2,0,0))
        return Color.clear.frame(width:(right.x-left.x)*size.width,height:(bottom.y-top.y)*size.height)
            .contentShape(Rectangle()).position(x:(left.x+right.x)/2*size.width,y:(top.y+bottom.y)/2*size.height)
            .gesture(DragGesture(minimumDistance:0)
                .onChanged { _ in guard enabled,activeNotes.insert(note).inserted else { return }; noteOn(note) }
                .onEnded { _ in if activeNotes.remove(note) != nil { noteOff(note) } })
            .accessibilityElement().accessibilityAddTraits(.isButton)
            .accessibilityLabel("\(["C","C♯","D","D♯","E","F","F♯","G","G♯","A","A♯","B"][note%12])\(note/12-1)")
            .accessibilityAction {
                guard enabled,activeNotes.insert(note).inserted else { return }
                noteOn(note)
                DispatchQueue.main.asyncAfter(deadline:.now()+0.25) { if activeNotes.remove(note) != nil { noteOff(note) } }
            }
    }
    private func releaseKeys() { for note in activeNotes { noteOff(note) }; activeNotes.removeAll() }
}

private struct MetalInstrumentSurface {
    let layout: PanelLayout
    let values: [Double]
    let activeNotes: Set<Int>
    let switches: [Bool]
    @Binding var unavailable: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var renderer: MetalPanelRenderer?
    }

    func makeSurface(_ coordinator: Coordinator) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.clearColor = MTLClearColor(red: 0.006, green: 0.008, blue: 0.01, alpha: 1)
        view.depthStencilPixelFormat = .depth32Float
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        if let device = view.device {
            do {
                coordinator.renderer = try MetalPanelRenderer(device: device)
                view.sampleCount = coordinator.renderer?.sampleCount ?? 1
                view.delegate = coordinator.renderer
            } catch {
                print("Metal panel initialization failed: \(error)")
                DispatchQueue.main.async { unavailable = true }
            }
        } else {
            DispatchQueue.main.async { unavailable = true }
        }
        return view
    }

    func refresh(_ view: MTKView, _ coordinator: Coordinator) {
        coordinator.renderer?.update(layout: layout, values: values, activeNotes: activeNotes, switches: switches)
        #if os(macOS)
        view.needsDisplay = true
        #else
        view.setNeedsDisplay()
        #endif
    }
}

#if os(macOS)
extension MetalInstrumentSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> MTKView { makeSurface(context.coordinator) }
    func updateNSView(_ view: MTKView, context: Context) { refresh(view, context.coordinator) }
}
#else
extension MetalInstrumentSurface: UIViewRepresentable {
    func makeUIView(context: Context) -> MTKView { makeSurface(context.coordinator) }
    func updateUIView(_ view: MTKView, context: Context) { refresh(view, context.coordinator) }
}
#endif

