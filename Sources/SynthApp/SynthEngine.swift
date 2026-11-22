import AVFoundation
import AudioToolbox
import Foundation
import os

@MainActor
final class SynthEngine: ObservableObject {
    @Published var isRunning = false
    @Published var startupError: String?
    private let audioLog=Logger(subsystem:"com.synth05.Synth",category:"AudioStartup")
    @Published private(set) var midiSourceCount=0
    @Published private(set) var midiError: OSStatus?
    @Published private(set) var midiControlEvent: MIDIAction?
    @Published var gateOn = false
    @Published var midiNote: Double = 48 {
        didSet {
            if heldNotes.contains(lastNote) && !isKeyboardUpdate {
                let note = Int(midiNote.rounded())
                heldNotes.remove(lastNote)
                heldNotes.insert(note)
                if !midiNotes.contains(lastNote) { audioUnit?.noteOff(lastNote) }
                audioUnit?.noteOn(note, velocity: 1)
                lastNote = note
            }
        }
    }

    let sharedParams: SharedSynthParameters
    let sharedEffects: SharedEffects
    lazy var effects = EffectsController(shared:sharedEffects,persistent:!isHosted)
    let hostedUnit:HostedSynthAudioUnit?
    var isHosted:Bool { hostedUnit != nil }
    @Published private(set) var hostParameters:SynthParameters?
    private var hostTimer:Timer?
    private let engine: AVAudioEngine?
    private var node: AVAudioNode?
    private var audioUnit: ProphetLikeAudioUnit?
    private var lastNote: Int = 48
    private var isKeyboardUpdate = false
    private var heldNotes = Set<Int>()
    private var midiNotes = Set<Int>()
    private let midi=MIDIInput()
    private var isStarting=false

    private let componentDescription = AudioComponentDescription(
        componentType: kAudioUnitType_Generator,
        componentSubType: 0x50723535, // 'Pr55'
        componentManufacturer: 0x53796E74, // 'Synt'
        componentFlags: 0,
        componentFlagsMask: 0
    )

    init(hostedUnit:HostedSynthAudioUnit? = nil) {
        self.hostedUnit=hostedUnit
        sharedParams=hostedUnit?.parameterStorage ?? SharedSynthParameters()
        sharedEffects=hostedUnit?.effectStorage ?? SharedEffects()
        engine=hostedUnit==nil ? AVAudioEngine():nil
        if let hostedUnit {
            audioUnit=hostedUnit;isRunning=true;hostParameters=sharedParams.snapshot()
        }
        _ = effects
        midi.action = { [weak self] in self?.receiveMIDI($0) }
        midi.status = { [weak self] count,error in self?.midiSourceCount=count;self?.midiError=error }
    }

    func start() {
        if isHosted {
            isRunning=true
            guard hostTimer==nil else { return }
            hostTimer=Timer.scheduledTimer(withTimeInterval:1.0/30,repeats:true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let next=self.sharedParams.snapshot()
                    if next != self.hostParameters { self.hostParameters=next }
                    self.effects.refreshHostedDocument()
                }
            }
            return
        }
        if isRunning || isStarting { return }
        guard let engine else { return }
        startupError=nil
        isStarting=true
        defer { isStarting=false }
        do {
            // The standalone instrument owns its DSP directly. Component-registry
            // lookup can reject a process-local registration in a sandboxed app.
            let unit=try ProphetLikeAudioUnit(componentDescription:componentDescription,options:[],
                                             parameters:sharedParams,effects:sharedEffects)
            audioUnit=unit
            let rate=engine.outputNode.inputFormat(forBus:0).sampleRate
            guard rate.isFinite,rate>0,let format=AVAudioFormat(standardFormatWithSampleRate:rate,channels:2) else {
                throw NSError(domain:NSOSStatusErrorDomain,code:Int(kAudioUnitErr_FormatNotSupported))
            }
            try unit.outputBusses[0].setFormat(format)
            try unit.allocateRenderResources()
            let render=unit.internalRenderBlock
            let source=AVAudioSourceNode(format:format) { silent,timestamp,frames,buffers in
                var flags=AudioUnitRenderActionFlags()
                let status=render(&flags,timestamp,frames,0,buffers,nil,nil)
                silent.pointee=ObjCBool(flags.contains(.unitRenderAction_OutputIsSilence))
                return status
            }
            node=source
            engine.attach(source)
            engine.connect(source,to:engine.mainMixerNode,format:format)
            try engine.start()
            lastNote=Int(midiNote.rounded())
            isRunning=true
            midi.start()
        } catch {
            startupError=error.localizedDescription
            audioLog.error("Audio engine start failed: \(error.localizedDescription,privacy:.public)")
            stop()
        }
    }

    func stop() {
        if isHosted { noteOffCurrent();return } // Host owns the render lifecycle.
        isStarting=false
        midi.stop()
        for note in heldNotes.union(midiNotes) { audioUnit?.noteOff(note) }
        heldNotes.removeAll();midiNotes.removeAll()
        gateOn = false
        engine?.stop()
        if let node {
            engine?.disconnectNodeInput(node)
            engine?.detach(node)
            self.node = nil
        }
        audioUnit?.deallocateRenderResources()
        audioUnit=nil
        isRunning = false
        sharedEffects.resetLoop()
    }

    deinit {
        hostTimer?.invalidate();engine?.stop()
        if hostedUnit == nil { audioUnit?.deallocateRenderResources() }
    }
    func applyParameters(_ parameters:SynthParameters) {
        if let hostedUnit {
            hostedUnit.applyUIParameters(parameters,previousUI:hostParameters)
            hostParameters=sharedParams.snapshot()
        }
        else { sharedParams.set { $0=parameters } }
    }

    func noteOnCurrent() {
        guard isRunning else { return }
        lastNote = Int(midiNote.rounded())
        if heldNotes.insert(lastNote).inserted { audioUnit?.noteOn(lastNote, velocity: 1) }
        gateOn = true
    }

    func noteOffCurrent() {
        midi.resetPerformance()
        for note in heldNotes.union(midiNotes) { audioUnit?.noteOff(note) }
        heldNotes.removeAll();midiNotes.removeAll()
        gateOn = false
    }

    func playNote(_ midi: Int, velocity: Float = 1) {
        audioLog.debug("Screen keyboard note \(midi,privacy:.public), running \(self.isRunning,privacy:.public)")
        guard isRunning,(0...127).contains(midi) else { return }
        isKeyboardUpdate = true
        midiNote = Double(midi)
        isKeyboardUpdate = false
        lastNote = midi
        if heldNotes.insert(midi).inserted { audioUnit?.noteOn(midi, velocity: velocity) }
        gateOn = true
    }

    func releaseNote(_ midi: Int) {
        if heldNotes.remove(midi) != nil && !midiNotes.contains(midi) { audioUnit?.noteOff(midi) }
        gateOn = !heldNotes.isEmpty || !midiNotes.isEmpty
    }
    private func receiveMIDI(_ action:MIDIAction) {
        switch action {
        case let .on(note,velocity):
            guard isRunning else { return }
            midiNotes.insert(note)
            if !heldNotes.contains(note) { audioUnit?.noteOn(note,velocity:velocity) }
        case let .off(note):
            if midiNotes.remove(note) != nil && !heldNotes.contains(note) { audioUnit?.noteOff(note) }
        case let .pitch(value):
            midiControlEvent=action;sharedParams.set { $0.pitchWheel=value }
        case let .mod(value):
            midiControlEvent=action;sharedParams.set { $0.modWheel=value }
        }
        gateOn = !heldNotes.isEmpty || !midiNotes.isEmpty
    }

}
