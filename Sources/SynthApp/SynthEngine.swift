import AVFoundation
import AudioToolbox
import Foundation

@MainActor
final class SynthEngine: ObservableObject {
    @Published var isRunning = false
    @Published var gateOn = false
    @Published var midiNote: Double = 48 {
        didSet {
            if gateOn && !isKeyboardUpdate {
                let note = Int(midiNote.rounded())
                heldNotes.remove(lastNote)
                heldNotes.insert(note)
                audioUnit?.noteOff(lastNote)
                audioUnit?.noteOn(note, velocity: 0.85)
                lastNote = note
            }
        }
    }

    let sharedParams = SharedSynthParameters()

    private let engine = AVAudioEngine()
    private var node: AVAudioUnit?
    private var audioUnit: ProphetLikeAudioUnit?
    private var lastNote: Int = 48
    private var isKeyboardUpdate = false
    private var heldNotes = Set<Int>()

    private let componentDescription = AudioComponentDescription(
        componentType: kAudioUnitType_Generator,
        componentSubType: 0x50723535, // 'Pr55'
        componentManufacturer: 0x53796E74, // 'Synt'
        componentFlags: 0,
        componentFlagsMask: 0
    )

    init() {
        ProphetLikeAudioUnit.sharedParameters = sharedParams
        AUAudioUnit.registerSubclass(
            ProphetLikeAudioUnit.self,
            as: componentDescription,
            name: "Local ProphetLike Generator",
            version: UInt32.max
        )
    }

    func start() {
        if isRunning { return }

        AVAudioUnit.instantiate(with: componentDescription, options: []) { [weak self] avUnit, error in
            Task { @MainActor in
                guard let self else { return }
                guard error == nil, let avUnit else { return }

                self.node = avUnit
                self.audioUnit = avUnit.auAudioUnit as? ProphetLikeAudioUnit
                self.lastNote = Int(self.midiNote.rounded())

                self.engine.attach(avUnit)
                self.engine.connect(avUnit, to: self.engine.mainMixerNode, format: nil)

                do {
                    try self.engine.start()
                    self.isRunning = true
                } catch {
                    print("Engine start error: \(error)")
                }
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        for note in heldNotes { audioUnit?.noteOff(note) }
        heldNotes.removeAll()
        gateOn = false
        engine.stop()
        if let node {
            engine.disconnectNodeInput(node)
            engine.detach(node)
            self.node = nil
        }
        isRunning = false
    }

    deinit {
        engine.stop()
    }

    func noteOnCurrent() {
        lastNote = Int(midiNote.rounded())
        if heldNotes.insert(lastNote).inserted { audioUnit?.noteOn(lastNote, velocity: 0.85) }
        gateOn = true
    }

    func noteOffCurrent() {
        for note in heldNotes { audioUnit?.noteOff(note) }
        heldNotes.removeAll()
        gateOn = false
    }

    func playNote(_ midi: Int, velocity: Float = 0.85) {
        isKeyboardUpdate = true
        midiNote = Double(midi)
        isKeyboardUpdate = false
        lastNote = midi
        if heldNotes.insert(midi).inserted { audioUnit?.noteOn(midi, velocity: velocity) }
        gateOn = true
    }

    func releaseNote(_ midi: Int) {
        heldNotes.remove(midi)
        audioUnit?.noteOff(midi)
        gateOn = !heldNotes.isEmpty
    }
}
