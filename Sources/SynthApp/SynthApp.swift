import SwiftUI

@main
struct SynthApp: App {
    @StateObject private var engine = SynthEngine()
    var body: some Scene {
        WindowGroup { ContentView(engine: engine) }
        #if os(macOS)
        .defaultSize(width: 1120, height: 920)
        #endif
    }
}

struct ContentView: View {
    @ObservedObject var engine: SynthEngine
    @State private var parameters = SynthParameters()
    @State private var selectedTab: RackTab = .synth
    @State private var showEditor = false
    @State private var showInfo = false
    @State private var selectedFile = 1
    @State private var bank = 1
    @State private var program = 1
    @State private var memoryStatus = ""

    private func title(_ names: [String]) -> String { instrumentText(names[0],names[1],names[2]) }
    private func binding(_ key: WritableKeyPath<SynthParameters,Float>) -> Binding<Double> {
        Binding(get:{ Double(parameters[keyPath:key]) },set:{ parameters[keyPath:key]=Float($0) })
    }
    private func binding(_ key: WritableKeyPath<SynthParameters,Bool>) -> Binding<Bool> {
        Binding(get:{ parameters[keyPath:key] },set:{ parameters[keyPath:key]=$0 })
    }
    private var controls: [PanelControl] {
        Rev3.knobs.map { item in
            PanelControl(label:item.label,title:title(item.names),value:binding(item.key),range:Double(item.range.lowerBound)...Double(item.range.upperBound),logarithmic:item.curve == 1,quantized:item.curve == 2,resetValue:Double(SynthParameters()[keyPath:item.key]))
        } + [
            PanelControl(label:"PITCH",title:instrumentText("Pitch wheel","ピッチホイール","弯音轮"),value:binding(\.pitchWheel),range:-1...1,resetValue:0),
            PanelControl(label:"MOD",title:instrumentText("Modulation wheel","モジュレーションホイール","调制轮"),value:binding(\.modWheel),range:0...1,resetValue:0)
        ]
    }
    private var switches: [PanelSwitch] {
        Rev3.switches.map { PanelSwitch(label:$0.label,title:title($0.names),value:binding($0.key)) }
    }

    var body: some View {
        ZStack {
            InstrumentFinish.backdrop.ignoresSafeArea()
            GeometryReader { viewport in
            VStack(spacing:8) {
                if viewport.size.height < 520 {
                    ScrollView { sharedPanel(width:viewport.size.width-32) }.frame(height:max(112,(viewport.size.height-24)*0.55))
                } else { sharedPanel(width:viewport.size.width-32) }
                VStack(spacing:0) {
                    RackTabStrip(selection:$selectedTab)
                    ScrollView {
                        VStack(spacing:0) {
                        if selectedTab == .synth {
                            expressionPanel
                            InstrumentPanel(controls:controls,switches:switches,enabled:engine.isRunning,changed:apply,
                                            onUnavailable:{showEditor=true})
                            DisclosureGroup(isExpanded:$showEditor) {
                                nativeEditor
                            } label: {
                                Label(instrumentText("Parameter editor","パラメーター編集","参数编辑"),systemImage:"slider.horizontal.3")
                            }.font(InstrumentFinish.legend()).tint(InstrumentFinish.muted)
                                .padding(.horizontal,16).padding(.vertical,10)
                        } else if selectedTab == .patch {
                            EffectsPatchView(rack:engine.effects,editEffect:openEffect)
                        } else {
                            EffectsWorkspace(rack:engine.effects,tab:selectedTab,openPatch:{selectedTab = .patch})
                        }
                        }
                    }
                }.background(CabinetFinish()).overlay(CabinetRails())
            }.padding(.horizontal,16).padding(.vertical,12)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if let data=UserDefaults.standard.data(forKey:"synth.expression.v1"),
               let expression=try? JSONDecoder().decode(ExpressionParameters.self,from:data) { parameters.expression=expression }
            loadProgram(); apply(); engine.start()
        }
    }

    private func sharedPanel(width: CGFloat) -> some View {
        SharedPerformancePanel(header:toolbar(panelWidth:width),file:$selectedFile,bank:$bank,program:$program,status:memoryStatus,
                    recall:loadProgram,record:saveProgram,loadPreset:loadInstrumentPreset,controls:controls,switches:switches.map { $0.value.wrappedValue },
                    enabled:engine.isRunning,changed:apply,noteOn:{engine.playNote($0)},noteOff:{engine.releaseNote($0)})
    }

    private func openEffect(_ kind: EffectKind) {
        switch kind {
        case .synth: selectedTab = .synth
        case .dimension: selectedTab = .dimension
        case .sky, .time: selectedTab = .ambience
        case .pedal: selectedTab = .pedal
        case .ring: selectedTab = .ring
        case .studio: selectedTab = .studio
        default: break
        }
    }

    private func toolbar(panelWidth: CGFloat) -> some View {
        ViewThatFits(in:.horizontal) {
            HStack(alignment:.center,spacing:8) { nameplate; Spacer(minLength:8); masterVolume(panelWidth:panelWidth,horizontal:true); utilityControls }
            HStack(spacing:8) {
                VStack(alignment:.leading,spacing:4) { nameplate; utilityControls }
                Spacer(minLength:0)
                masterVolume(panelWidth:panelWidth,horizontal:false)
            }
        }
        .padding(.horizontal,18).padding(.vertical,6)
        .overlay(alignment:.bottom) { Rectangle().fill(InstrumentFinish.metalEdge).frame(height:1).padding(.horizontal,12) }
    }
    private func masterVolume(panelWidth: CGFloat,horizontal: Bool) -> some View {
        let layout=PanelLayout(columns:PanelLayout.columns(for:panelWidth),showsKeyboard:false)
        return MasterVolumeControl(controls:controls,switches:switches.map { $0.value.wrappedValue },
                                   scale:panelWidth/CGFloat(layout.width+0.4),horizontal:horizontal,changed:apply)
    }
    private var nameplate: some View {
        HStack(spacing:10) {
            PanelScrew()
            VStack(alignment:.leading,spacing:1) {
                Text("SYNTH/05").font(InstrumentFinish.wordmark).tracking(1).foregroundStyle(InstrumentFinish.ink)
                Text("REV 3 · 5 VOICES / 2 VCO").font(InstrumentFinish.legend(8)).tracking(0.6).foregroundStyle(InstrumentFinish.muted)
            }.fixedSize()
        }
    }
    private var utilityControls: some View {
        HStack(spacing:6) {
            Button { showInfo.toggle() } label: { Image(systemName:"info.circle").frame(width:32,height:32) }
                .help(instrumentText("Controls","操作方法","操作说明"))
                .accessibilityLabel(instrumentText("Controls","操作方法","操作说明"))
                .popover(isPresented:$showInfo) {
                    Text(instrumentText("Drag knobs and wheels vertically. Double-click to restore their initial setting. Hold keys to play.","ノブとホイールは上下にドラッグ。ダブルタップで初期値に戻ります。鍵盤を押して演奏します。","上下拖动旋钮和控制轮，双击恢复初始值，按住琴键演奏。"))
                        .padding(20).frame(idealWidth:280)
                }
            Button { parameters.autoTuneTrigger &+= 1; apply() } label: { Image(systemName:"tuningfork").frame(width:32,height:32) }
                .help(instrumentText("Tune oscillators","オシレーターをチューニング","振荡器调音"))
                .accessibilityLabel(instrumentText("Tune","チューニング","调音"))
            Button { parameters.referenceA440.toggle(); apply() } label: { Text("A-440").frame(width:46,height:32) }
                .buttonStyle(HardwareButtonStyle(selected:parameters.referenceA440))
                .help(instrumentText("440 Hz reference tone","440 Hz 基準音","440 Hz 参考音"))
                .accessibilityValue(parameters.referenceA440 ? instrumentText("On","オン","开"):instrumentText("Off","オフ","关"))
            Button(action:togglePower) { Image(systemName:"power").frame(width:32,height:32) }
                .buttonStyle(HardwareButtonStyle(selected:engine.isRunning))
                .help(instrumentText("Power","電源","电源"))
                .accessibilityLabel(instrumentText("Power","電源","电源"))
                .accessibilityValue(engine.isRunning ? instrumentText("On","オン","开"):instrumentText("Off","オフ","关"))
        }.buttonStyle(HardwareButtonStyle())
    }

    private var expressionPanel: some View {
        ExpressionPanel(parameters:$parameters.expression,changed:apply)
    }

    private var nativeEditor: some View {
        VStack(alignment:.leading,spacing:18) {
            ForEach(Rev3.sections.indices,id:\.self) { index in
                VStack(alignment:.leading,spacing:8) {
                    Text(Rev3.sections[index].title).font(.system(.caption,design:.monospaced)).foregroundStyle(.mint)
                    ForEach(Rev3.sections[index].knobs.filter { $0 != 25 },id:\.self) { knob in editorControl(knob) }
                    ForEach(Rev3.sections[index].switches,id:\.self) { index in
                        Toggle(switches[index].title,isOn:Binding(get:{switches[index].value.wrappedValue},set:{switches[index].value.wrappedValue=$0; apply()}))
                    }
                }
            }
            editorControl(26)
            editorControl(27)
        }.padding(.vertical,12)
    }
    private func editorControl(_ index: Int) -> some View {
        let control=controls[index]
        return VStack(alignment:.leading,spacing:2) {
            HStack {
                Text(control.title).fixedSize(horizontal:false,vertical:true)
                Spacer(minLength:4)
                Text(control.displayValue).monospacedDigit()
            }
            Slider(value:Binding(get:{control.normalized},set:{control.setNormalized($0); apply()}),in:0...1)
                .accessibilityLabel(control.title).accessibilityValue(control.displayValue)
        }
    }
    private func apply() {
        engine.sharedParams.set { $0=parameters }
        if let data=try? JSONEncoder().encode(parameters.expression) {
            UserDefaults.standard.set(data,forKey:"synth.expression.v1")
        }
    }
    private func togglePower() {
        if engine.isRunning { engine.stop() } else { engine.start(); apply() }
    }
    private var memoryKey: String { "synth.rev3.v1.\(selectedFile).\(bank).\(program)" }
    private func loadInstrumentPreset(_ preset: InstrumentPreset) {
        engine.noteOffCurrent()
        parameters=preset.applying(to:parameters)
        apply()
        memoryStatus=title(preset.names)
    }
    private func saveProgram() {
        guard let data=try? JSONEncoder().encode(Rev3Program(parameters)) else { return }
        UserDefaults.standard.set(data,forKey:memoryKey)
        memoryStatus=instrumentText("Recorded","保存しました","已保存")
    }
    private func loadProgram() {
        guard let data=UserDefaults.standard.data(forKey:memoryKey) else {
            let legacyKey="synth.preset.\(selectedFile == 1 ? "A":"B").\((bank-1)*8+program)"
            if selectedFile <= 2,let data=UserDefaults.standard.data(forKey:legacyKey),
               let migrated=Rev3Program.migratingLegacy(data),let next=migrated.applying(to:parameters) {
                parameters=next; apply()
                memoryStatus=instrumentText("Legacy sound adapted to Rev3; original retained","旧音色をRev3用に変換しました（元データは保持）","旧音色已适配Rev3，保留原数据")
            } else { memoryStatus=instrumentText("Empty program","空きプログラム","空音色位") }
            return
        }
        guard let program=try? JSONDecoder().decode(Rev3Program.self,from:data),let next=program.applying(to:parameters) else {
            memoryStatus=instrumentText("Could not read program","音色を読み込めませんでした","无法读取音色"); return
        }
        parameters=next; apply()
        memoryStatus=instrumentText("Recalled","読み込みました","已载入")
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(engine:SynthEngine()).previewDevice("iPhone SE (3rd generation)")
        ContentView(engine:SynthEngine()).previewDevice("iPhone 16 Pro Max")
    }
}
