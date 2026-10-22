import SwiftUI

/// Uses the synth's unchanged Metal knob mesh at the same projected unit scale.
struct MasterVolumeControl: View {
    let controls: [PanelControl]
    let switches: [Bool]
    let scale: CGFloat
    let horizontal: Bool
    let changed: () -> Void
    @State private var gpuUnavailable=false
    @State private var dragStart: Double?
    private let layout=PanelLayout(columns:1,masterVolumeOnly:true)
    private var control: PanelControl { controls[25] }
    private var diameter: CGFloat { scale*1.28 }

    var body: some View {
        Group {
            if horizontal {
                HStack(spacing:4) {
                    VStack(alignment:.trailing,spacing:2) { legend; readout }
                    knob
                }
            } else {
                VStack(spacing:2) { legend; knob; readout }
            }
        }.fixedSize()
    }
    private var legend: some View {
        Text("VOLUME").font(InstrumentFinish.legend(9)).foregroundStyle(InstrumentFinish.ink).accessibilityHidden(true)
    }
    private var readout: some View {
        Text(control.displayValue).font(InstrumentFinish.legend(9)).monospacedDigit()
            .foregroundStyle(InstrumentFinish.muted).accessibilityHidden(true)
    }
    private var knob: some View {
        ZStack {
            if gpuUnavailable {
                Circle().fill(LinearGradient(colors:[.black,Color(white:0.2),.black],startPoint:.topLeading,endPoint:.bottomTrailing))
                    .frame(width:scale*0.88,height:scale*0.88)
                    .overlay { Circle().fill(AngularGradient(colors:[.gray,.white,.gray,.black,.gray],center:.center)).padding(scale*0.2) }
                Capsule().fill(InstrumentFinish.ink).frame(width:scale*0.032,height:scale*0.12)
                    .offset(y:-scale*0.31).rotationEffect(.degrees(-135+control.normalized*270))
            } else {
                MetalInstrumentSurface(layout:layout,values:controls.map(\.normalized),activeNotes:[],switches:switches,unavailable:$gpuUnavailable)
                    .accessibilityHidden(true)
            }
        }.frame(width:diameter,height:diameter).clipShape(RoundedRectangle(cornerRadius:scale*0.12)).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance:1).onChanged { event in
                if dragStart == nil { dragStart=control.normalized }
                control.setNormalized((dragStart ?? control.normalized)-Double(event.translation.height/180)); changed()
            }.onEnded { _ in dragStart=nil })
            .onTapGesture(count:2) { control.value.wrappedValue=control.resetValue; changed() }
            .accessibilityElement(children:.ignore).accessibilityIdentifier("shared.masterVolume").accessibilityLabel(control.title).accessibilityValue(control.displayValue)
            .accessibilityAdjustableAction { direction in
                control.setNormalized(control.normalized+(direction == .increment ? 0.02:-0.02)); changed()
            }
            .help(control.title+" · "+control.displayValue)
    }
}
