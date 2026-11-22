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
                        .mask(alignment: .leading) {
                            Rectangle().frame(width: keyboardRect(size: geo.size).minX)
                        }
                }
                ForEach(0..<2,id:\.self) { index in wheel(index,size:geo.size) }
                pianoKeys(size: geo.size)
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
    private func keyboardRect(size: CGSize) -> CGRect {
        let first = keyRect(center: SIMD3(layout.keyX(0),layout.keyY,0.16),
                            width: layout.keyWidth,depth: 1,size: size)
        return CGRect(x:first.minX,y:first.minY,
                      width:CGFloat(layout.keyboardWidth / (layout.width+0.4))*size.width,
                      height:first.height)
    }

    private func pianoKeys(size: CGSize) -> some View {
        let rect = keyboardRect(size:size)
        return PianoKeyboardView(layout:PianoKeyboardLayout(white:layout.whiteNotes),
                                 pressed:activeNotes,showLabels:rect.height >= 64,
                                 miniature:rect.height < 100,
                                 onTouches: { notes in
            guard enabled else { return }
            for note in activeNotes.subtracting(notes) { noteOff(note) }
            for note in notes.subtracting(activeNotes) { noteOn(note) }
            activeNotes = notes
        }, onAccessibilityPlay: { note in
            guard enabled,activeNotes.insert(note).inserted else { return }
            noteOn(note)
            DispatchQueue.main.asyncAfter(deadline:.now()+0.25) {
                if activeNotes.remove(note) != nil { noteOff(note) }
            }
        })
        .id(enabled)
        .frame(width:rect.width,height:rect.height)
        .position(x:rect.midX,y:rect.midY)
        .allowsHitTesting(enabled)
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

// Adapted from Piano/Piano/KeyboardView.swift: shared drawing and native input.
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

func pianoKeyName(_ note: Int) -> String {
    let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
    return "\(names[note % 12])\(note / 12 - 1)"
}

struct PianoKeyboardLayout {
    struct Accidental {
        let note: Int
        let boundary: Int
    }

    let white: [Int]
    let black: [Accidental]

    init(white: [Int]) {
        self.white = white
        black = zip(white,white.dropFirst()).enumerated().compactMap { index,pair in
            pair.1-pair.0 == 2 ? Accidental(note:pair.0+1,boundary:index+1) : nil
        }
    }

    func blackFrame(_ key: Accidental, size: CGSize) -> CGRect {
        let step = size.width / CGFloat(white.count)
        let width = step * 0.59
        return CGRect(x: CGFloat(key.boundary) * step - width / 2, y: 0,
                      width: width, height: size.height * 0.63)
    }

    func note(at point: CGPoint, size: CGSize) -> Int? {
        guard !white.isEmpty, size.width > 0, size.height > 0, CGRect(origin: .zero, size: size).contains(point) else { return nil }
        if let key = black.first(where: { blackFrame($0, size: size).contains(point) }) { return key.note }
        return white[min(white.count - 1, Int(point.x / size.width * CGFloat(white.count)))]
    }
}

struct PianoKeyboardView: View {
    @Environment(\.displayScale) private var displayScale
    let layout: PianoKeyboardLayout
    let pressed: Set<Int>
    let showLabels: Bool
    var miniature = false
    let onTouches: (Set<Int>) -> Void
    let onAccessibilityPlay: (Int) -> Void

    var body: some View {
        GeometryReader { proxy in
            let step = proxy.size.width / CGFloat(layout.white.count)
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(layout.white, id: \.self) { note in
                        key(note, black: false)
                            .frame(width: step, height: proxy.size.height)
                    }
                }
                ForEach(layout.black, id: \.note) { accidental in
                    let rect = layout.blackFrame(accidental, size: proxy.size)
                    key(accidental.note, black: true)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX)
                }
                PianoTouchSurface(layout: layout, onTouches: onTouches)
                    .accessibilityHidden(true)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .top) {
                Rectangle().fill(.black.opacity(0.24)).frame(height: 2).allowsHitTesting(false)
            }
        }
    }

    private func key(_ note: Int, black: Bool) -> some View {
        let down = pressed.contains(note)
        let gold = Color(red: 0.045, green: 0.64, blue: 0.70)
        let radius: CGFloat = miniature ? (black ? 2 : 3) : (black ? 5 : 7)
        // Two pixels across adjacent insets leave a full visible pixel
        // even when the key boundary falls between display pixels.
        let keyInset = max(miniature ? 0.4 : 0.6, 1 / displayScale)
        return RoundedRectangle(cornerRadius: radius)
            .fill(LinearGradient(
                colors: down ? [gold.opacity(0.75), gold] : black
                    ? [Color(white: 0.11), Color(white: 0.23)]
                    : [Color(red: 0.85, green: 0.82, blue: 0.76), Color(red: 0.99, green: 0.97, blue: 0.92)],
                startPoint: .top, endPoint: .bottom
            ))
            .padding(.horizontal, black ? 0 : keyInset)
            .shadow(color: .black.opacity(black ? 0.4 : 0), radius: 3, y: 3)
            .overlay(alignment: .bottom) {
                if showLabels && !black && (!miniature || note % 12 == 0) {
                    Text(verbatim: pianoKeyName(note))
                        .font(miniature ? .system(size: 8, weight: .medium, design: .monospaced)
                            : .caption2.monospaced().weight(note % 12 == 0 ? .bold : .regular))
                        .foregroundStyle(Color(white: 0.28))
                        .padding(.bottom, miniature ? 5 : 13)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: pianoKeyName(note)))
            .accessibilityAddTraits(.isButton)
            .accessibilitySortPriority(Double(109 - note))
            .accessibilityAction { onAccessibilityPlay(note) }
    }
}

#if os(macOS)
private struct PianoTouchSurface: NSViewRepresentable {
    let layout: PianoKeyboardLayout
    let onTouches: (Set<Int>) -> Void

    func makeNSView(context: Context) -> MouseView { MouseView() }

    func updateNSView(_ view: MouseView, context: Context) {
        view.layout = layout
        view.onTouches = onTouches
    }

    final class MouseView: NSView {
        var layout: PianoKeyboardLayout?
        var onTouches: ((Set<Int>) -> Void)?
        override var isFlipped: Bool { true }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { play(event) }
        override func mouseDragged(with event: NSEvent) { play(event) }
        override func mouseUp(with event: NSEvent) { onTouches?([]) }

        private func play(_ event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            if let note = layout?.note(at: point, size: bounds.size) {
                onTouches?([note])
            } else {
                onTouches?([])
            }
        }
    }
}
#else
private struct PianoTouchSurface: UIViewRepresentable {
    let layout: PianoKeyboardLayout
    let onTouches: (Set<Int>) -> Void

    func makeUIView(context: Context) -> TouchView {
        let view = TouchView()
        view.isMultipleTouchEnabled = true
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: TouchView, context: Context) {
        view.layout = layout
        view.onTouches = onTouches
    }

    final class TouchView: UIView {
        var layout: PianoKeyboardLayout?
        var onTouches: ((Set<Int>) -> Void)?
        private var notes: [ObjectIdentifier: Int] = [:]

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { update(touches) }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { update(touches) }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { remove(touches) }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { remove(touches) }

        private func update(_ touches: Set<UITouch>) {
            for touch in touches {
                notes[ObjectIdentifier(touch)] = layout?.note(at: touch.location(in: self), size: bounds.size)
            }
            onTouches?(Set(notes.values))
        }

        private func remove(_ touches: Set<UITouch>) {
            for touch in touches { notes[ObjectIdentifier(touch)] = nil }
            onTouches?(Set(notes.values))
        }
    }
}
#endif
