import SwiftUI

/// One stable panel outside the selected-tab subtree owns all playing gestures.
struct SharedPerformancePanel<Header: View>: View {
    let header: Header
    @Binding var file: Int
    @Binding var bank: Int
    @Binding var program: Int
    let status: String
    let recall: () -> Void
    let record: () -> Void
    let controls: [PanelControl]
    let switches: [Bool]
    let enabled: Bool
    let changed: () -> Void
    let noteOn: (Int) -> Void
    let noteOff: (Int) -> Void

    var body: some View {
        VStack(spacing:0) {
            header
            ViewThatFits(in:.horizontal) {
                HStack(alignment:.center,spacing:8) {
                    programmer(splitKeys:true).frame(width:316)
                    keyboard(columns:2).frame(width:720)
                }.padding(.horizontal,16).padding(.vertical,4)
                VStack(spacing:0) {
                    programmer()
                    ViewThatFits(in:.horizontal) {
                        keyboard(columns:2).frame(minWidth:600,maxWidth:720).padding(.horizontal,16)
                        keyboard(columns:1).frame(maxWidth:599).padding(.horizontal,16)
                    }.padding(.bottom,4)
                }
            }
        }.fixedSize(horizontal:false,vertical:true).background(CabinetFinish()).overlay(CabinetRails())
    }
    private func programmer(splitKeys: Bool=false) -> some View {
        ProgrammerPanel(file:$file,bank:$bank,program:$program,status:status,recall:recall,record:record,compact:true,splitKeys:splitKeys)
    }
    private func keyboard(columns: Int) -> some View {
        SharedMetalKeyboard(layout:PanelLayout(columns:columns,keyboardOnly:true),controls:controls,switches:switches,
                            enabled:enabled,changed:changed,noteOn:noteOn,noteOff:noteOff)
    }
}

struct SharedMetalKeyboard: View {
    @Environment(\.scenePhase) private var scenePhase
    let layout: PanelLayout
    let controls: [PanelControl]
    let switches: [Bool]
    let enabled: Bool
    let changed: () -> Void
    let noteOn: (Int) -> Void
    let noteOff: (Int) -> Void
    @State private var activeNotes=Set<Int>()
    @State private var gpuUnavailable=false
    @State private var wheelStart=[Int:Double]()

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment:.topLeading) {
                if !gpuUnavailable {
                    MetalInstrumentSurface(layout:layout,values:controls.map(\.normalized),activeNotes:activeNotes,switches:switches,unavailable:$gpuUnavailable)
                        .accessibilityHidden(true)
                }
                ForEach(0..<2,id:\.self) { index in wheel(index,size:geo.size) }
                ForEach(Array(layout.whiteNotes.enumerated()),id:\.element) { index,note in
                    key(note:note,center:SIMD3(layout.keyX(index),layout.keyY,0.16),width:layout.keyWidth-0.025,depth:1,black:false,size:geo.size)
                }
                ForEach(layout.blackNotes,id:\.note) { item in
                    key(note:item.note,center:SIMD3(layout.keyX(item.slot)+layout.keyWidth/2,layout.keyY+0.19,0.3),width:layout.keyWidth*0.56,depth:0.63,black:true,size:geo.size)
                }
            }
        }.aspectRatio(CGFloat(layout.aspect),contentMode:.fit)
            .onChange(of:enabled) { running in if !running { releaseKeys() } }
            .onChange(of:scenePhase) { phase in if phase != .active { releaseKeys() } }
            .onDisappear { releaseKeys() }
    }
    private func wheel(_ index: Int,size: CGSize) -> some View {
        let control=controls[26+index], center=layout.wheel(index), p=layout.point(center)
        let scale=size.width/CGFloat(layout.width+0.4)
        return Group {
            if gpuUnavailable {
                Capsule().fill(InstrumentFinish.metalEdge).frame(width:8,height:scale*1.2)
                    .position(x:p.x*size.width,y:p.y*size.height)
                RoundedRectangle(cornerRadius:3).fill(InstrumentFinish.muted).frame(width:24,height:10)
                    .position(x:p.x*size.width,y:layout.point(layout.wheel(index,value:Float(control.normalized))).y*size.height)
            }
            Color.clear.frame(width:max(32,min(44,scale*1.12)),height:max(44,scale*1.25)).contentShape(Rectangle())
                .position(x:p.x*size.width,y:p.y*size.height)
                .gesture(DragGesture(minimumDistance:1).onChanged { event in
                    if wheelStart[index] == nil { wheelStart[index]=control.normalized }
                    control.setNormalized((wheelStart[index] ?? control.normalized)-Double(event.translation.height/100)); changed()
                }.onEnded { _ in wheelStart[index]=nil })
                .onTapGesture(count:2) { control.value.wrappedValue=control.resetValue; changed() }
                .accessibilityElement().accessibilityLabel(control.title).accessibilityValue(control.displayValue)
                .accessibilityAdjustableAction { direction in control.setNormalized(control.normalized+(direction == .increment ? 0.02:-0.02)); changed() }
                .help(control.title+" · "+control.displayValue)
            Text(index == 0 ? "PITCH":"MOD").font(InstrumentFinish.legend(9)).foregroundStyle(InstrumentFinish.ink)
                .position(x:p.x*size.width,y:layout.point(center+SIMD3(0,0.76,0)).y*size.height)
                .allowsHitTesting(false).accessibilityHidden(true)
        }
    }
    private func key(note: Int,center: SIMD3<Float>,width: Float,depth: Float,black: Bool,size: CGSize) -> some View {
        let top=layout.point(center+SIMD3(0,depth/2,0)),bottom=layout.point(center-SIMD3(0,depth/2,0))
        let left=layout.point(center-SIMD3(width/2,0,0)),right=layout.point(center+SIMD3(width/2,0,0))
        return RoundedRectangle(cornerRadius:3)
            .fill(gpuUnavailable ? (activeNotes.contains(note) ? Color.cyan:(black ? Color(white:0.08):Color(white:0.8))):Color.clear)
            .frame(width:(right.x-left.x)*size.width,height:(bottom.y-top.y)*size.height)
            .contentShape(Rectangle()).position(x:(left.x+right.x)/2*size.width,y:(top.y+bottom.y)/2*size.height)
            .gesture(DragGesture(minimumDistance:0).onChanged { _ in
                guard enabled,activeNotes.insert(note).inserted else { return }; noteOn(note)
            }.onEnded { _ in if activeNotes.remove(note) != nil { noteOff(note) } })
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
