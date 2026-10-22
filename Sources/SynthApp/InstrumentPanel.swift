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
    let controls: [PanelControl]
    let switches: [PanelSwitch]
    let enabled: Bool
    let changed: () -> Void
    var onUnavailable: () -> Void = {}
    @State private var gpuUnavailable=false
    @State private var dragStart=[Int:Double]()
    @State private var panelColumns=1
    @State private var hovering: Int?

    var body: some View {
        VStack(spacing:4) {
            GeometryReader { geo in
                let layout=PanelLayout(columns:PanelLayout.columns(for:geo.size.width),showsKeyboard:false,omitsMasterVolume:true)
                ZStack(alignment:.topLeading) {
                    MetalInstrumentSurface(layout:layout,values:controls.map(\.normalized),activeNotes:[],switches:switches.map { $0.value.wrappedValue },unavailable:$gpuUnavailable)
                        .accessibilityHidden(true)
                    ForEach(0..<25,id: \.self) { index in
                        control(index,layout:layout,size:geo.size)
                    }
                    ForEach(0..<22,id: \.self) { bank in
                        switchControl(bank,layout:layout,size:geo.size)
                    }
                    ForEach(Rev3.sections.indices,id: \.self) { index in
                        printed(Rev3.sections[index].title,at:layout.point(layout.title(index)),size:geo.size,pointSize:geo.size.width/CGFloat(layout.width)*0.2,pill:true)
                    }

                }
            }
            .aspectRatio(CGFloat(PanelLayout(columns:panelColumns,showsKeyboard:false,omitsMasterVolume:true).aspect),contentMode:.fit)
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

    }

    private func control(_ index: Int, layout: PanelLayout, size: CGSize) -> some View {
        let c=controls[index]
        let world=layout.knob(index)
        let p=layout.point(world)
        let screenScale=size.width/CGFloat(layout.width+0.4)
        let titlePoint=layout.point(layout.knobLabel(index))
        let valuePoint=layout.point(layout.knobValue(index))
        return Group {
            hitControl(index,width:max(44,screenScale*0.98),height:max(44,screenScale),travel:180)
                .position(x:p.x*size.width,y:p.y*size.height)
            printed(c.label,at:titlePoint,size:size,pointSize:screenScale*0.19,pill:false,width:screenScale*1.34-6)
            printed(c.displayValue,at:valuePoint,size:size,pointSize:screenScale*0.16,width:screenScale*1.34-6)
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

    private func printed(_ text: String,at point: CGPoint,size: CGSize,pointSize: CGFloat,pill: Bool=false,width: CGFloat?=nil) -> some View {
        Text(text)
            .font(.system(size:max(9,min(13,pointSize)),weight:.semibold,design:.monospaced))
            .tracking(-0.25)
            .foregroundStyle(Color(red:0.025,green:0.08,blue:0.085))
            .lineLimit(1).minimumScaleFactor(0.75)
            .frame(width:width)
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
            printed(switches[bank].label,at:layout.point(layout.toggleLabel(bank)),size:size,pointSize:size.width/CGFloat(layout.width)*0.16,width:size.width/CGFloat(layout.width+0.4)*1.16-4)
        }
    }


}

struct MetalInstrumentSurface {
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

