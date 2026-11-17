import SwiftUI

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
                        .allowsHitTesting(false)
                }
                ForEach(0..<2,id:\.self) { index in wheel(index,size:geo.size) }
                ForEach(Array(layout.whiteNotes.enumerated()),id:\.element) { index,note in
                    key(note:note,center:SIMD3(layout.keyX(index),layout.keyY,0.16),width:layout.keyWidth-0.025,depth:1,black:false,size:geo.size)
                }
                ForEach(layout.blackNotes,id:\.note) { item in
                    key(note:item.note,center:SIMD3(layout.keyX(item.slot)+layout.keyWidth/2,layout.keyY+0.19,0.3),width:layout.keyWidth*0.56,depth:0.63,black:true,size:geo.size)
                }
                #if os(macOS)
                mouseSurface(size: geo.size)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .accessibilityHidden(true)
                #endif
            }
        }.aspectRatio(CGFloat(layout.aspect),contentMode:.fit)
            .onChange(of:enabled) { running in if !running { releaseKeys() } }
            .onChange(of:scenePhase) { phase in if phase != .active { releaseKeys() } }
            .onChange(of: layout) { _ in releaseKeys() }
            .onDisappear { releaseKeys() }
    }
    private func wheel(_ index: Int,size: CGSize) -> some View {
        let control=controls[26+index], center=layout.wheel(index), p=layout.point(center)
        let scale=size.width/CGFloat(layout.width+0.4)
        let hitWidth = wheelHitWidth(index, size: size)
        return Group {
            if gpuUnavailable {
                Capsule().fill(InstrumentFinish.metalEdge).frame(width:8,height:scale*1.2)
                    .position(x:p.x*size.width,y:p.y*size.height)
                RoundedRectangle(cornerRadius:3).fill(InstrumentFinish.muted).frame(width:24,height:10)
                    .position(x:p.x*size.width,y:layout.point(layout.wheel(index,value:Float(control.normalized))).y*size.height)
            }
            Color.clear.frame(width:hitWidth,height:max(44,scale*1.25)).contentShape(Rectangle())
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
    private func wheelHitWidth(_ index: Int, size: CGSize) -> CGFloat {
        let p = layout.point(layout.wheel(index))
        let nextWheel = layout.point(layout.wheel(1 - index))
        let spacing = abs(nextWheel.x - p.x) * size.width
        let firstKeyEdge = layout.point(SIMD3(layout.keyX(0) - layout.keyWidth / 2, layout.keyY, 0.16)).x
        let clearance = (firstKeyEdge - p.x) * size.width
        return max(1, min(44, spacing, 2 * clearance))
    }

    #if os(macOS)
    private func mouseSurface(size: CGSize) -> KeyboardMouseSurface {
        var targets: [KeyboardMouseSurface.Target] = []
        for index in 0..<2 {
            let center = layout.point(layout.wheel(index))
            let width = wheelHitWidth(index, size: size)
            let scale = size.width / CGFloat(layout.width + 0.4)
            let height = max(44, scale * 1.25)
            targets.append(.init(control: .wheel(index),
                                 rect: CGRect(x: center.x * size.width - width / 2,
                                              y: center.y * size.height - height / 2,
                                              width: width, height: height)))
        }
        for (index, note) in layout.whiteNotes.enumerated() {
            let center = SIMD3(layout.keyX(index), layout.keyY, 0.16)
            targets.append(.init(control: .key(note),
                                 rect: keyRect(center: center, width: layout.keyWidth - 0.025, depth: 1, size: size)))
        }
        for item in layout.blackNotes {
            let center = SIMD3(layout.keyX(item.slot) + layout.keyWidth / 2, layout.keyY + 0.19, 0.3)
            targets.append(.init(control: .key(item.note),
                                 rect: keyRect(center: center, width: layout.keyWidth * 0.56, depth: 0.63, size: size)))
        }
        return KeyboardMouseSurface(targets: targets, down: { control, clicks in
            switch control {
            case .key(let note):
                if enabled, activeNotes.insert(note).inserted { noteOn(note) }
            case .wheel(let index):
                let knob = controls[26 + index]
                if clicks == 2 {
                    knob.value.wrappedValue = knob.resetValue
                    changed()
                }
                wheelStart[index] = knob.normalized
            }
        }, drag: { control, distance in
            guard case .wheel(let index) = control, let start = wheelStart[index] else { return }
            controls[26 + index].setNormalized(start - Double(distance / 100))
            changed()
        }, up: { control in
            switch control {
            case .key(let note):
                if activeNotes.remove(note) != nil { noteOff(note) }
            case .wheel(let index):
                wheelStart[index] = nil
            }
        })
    }
    #endif

    private func keyRect(center: SIMD3<Float>, width: Float, depth: Float, size: CGSize) -> CGRect {
        let top = layout.point(center + SIMD3(0, depth / 2, 0))
        let bottom = layout.point(center - SIMD3(0, depth / 2, 0))
        let left = layout.point(center - SIMD3(width / 2, 0, 0))
        let right = layout.point(center + SIMD3(width / 2, 0, 0))
        return CGRect(x: left.x * size.width, y: top.y * size.height,
                      width: (right.x - left.x) * size.width,
                      height: (bottom.y - top.y) * size.height)
    }
    private func key(note: Int,center: SIMD3<Float>,width: Float,depth: Float,black: Bool,size: CGSize) -> some View {
        let rect = keyRect(center: center, width: width, depth: depth, size: size)
        return RoundedRectangle(cornerRadius:3)
            .fill(gpuUnavailable ? (activeNotes.contains(note) ? Color.cyan:(black ? Color(white:0.08):Color(white:0.8))):Color.clear)
            .frame(width: rect.width, height: rect.height)
            .contentShape(Rectangle()).position(x: rect.midX, y: rect.midY)
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
    private func releaseKeys() {
        for note in activeNotes { noteOff(note) }
        activeNotes.removeAll()
        wheelStart.removeAll()
    }
}

#if os(macOS)
/// AppKit keeps a drag with its originating target in embedded AU windows.
private struct KeyboardMouseSurface: NSViewRepresentable {
    enum Control { case key(Int), wheel(Int) }
    struct Target {
        let control: Control
        let rect: CGRect
    }

    let targets: [Target]
    let down: (Control, Int) -> Void
    let drag: (Control, CGFloat) -> Void
    let up: (Control) -> Void

    func makeNSView(context: Context) -> MouseView { MouseView() }
    func updateNSView(_ view: MouseView, context: Context) { view.surface = self }

    final class MouseView: NSView {
        var surface: KeyboardMouseSurface?
        private var pressed: Control?
        private var startY: CGFloat = 0
        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            target(at: convert(point, from: superview)) == nil ? nil : self
        }

        private func target(at point: NSPoint) -> Control? {
            surface?.targets.last { $0.rect.contains(point) }?.control
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            guard let control = target(at: point) else { return }
            pressed = control
            startY = point.y
            surface?.down(control, event.clickCount)
        }

        override func mouseDragged(with event: NSEvent) {
            guard let pressed else { return }
            let point = convert(event.locationInWindow, from: nil)
            surface?.drag(pressed, point.y - startY)
        }

        override func mouseUp(with event: NSEvent) {
            guard let pressed else { return }
            self.pressed = nil
            surface?.up(pressed)
        }
    }
}
#endif
