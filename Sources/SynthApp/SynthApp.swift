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
    @State private var showEditor = false
    @State private var gpuUnavailable = false
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
            Color(red:0.018,green:0.024,blue:0.028).ignoresSafeArea()
            ScrollView {
                VStack(spacing:14) {
                    toolbar
                    InstrumentPanel(controls:controls,switches:switches,enabled:engine.isRunning,changed:apply,
                        noteOn:{ engine.playNote($0) },noteOff:{ engine.releaseNote($0) },
                        onUnavailable:{ gpuUnavailable=true; showEditor=true })
                    memory
                    if gpuUnavailable { fallbackKeyboard }
                    DisclosureGroup(isExpanded:$showEditor) {
                        nativeEditor
                    } label: {
                        Label(instrumentText("Parameter editor","パラメーター編集","参数编辑"),systemImage:"slider.horizontal.3")
                    }.font(.caption).tint(.white.opacity(0.7))
                }.padding(.horizontal,16).padding(.vertical,16)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { loadProgram(); apply(); engine.start() }
    }

    private var toolbar: some View {
        HStack(spacing:12) {
            Text("5 VOICES / REV 3").font(.system(size:11,weight:.medium,design:.monospaced)).foregroundStyle(.secondary)
            Spacer(minLength:4)
            Button { parameters.autoTuneTrigger &+= 1; apply() } label: { Image(systemName:"tuningfork") }
                .help(instrumentText("Tune oscillators","オシレーターをチューニング","振荡器调音"))
                .accessibilityLabel(instrumentText("Tune","チューニング","调音"))
            Button { parameters.referenceA440.toggle(); apply() } label: {
                Text("A-440").font(.system(size:11,weight:.semibold,design:.monospaced))
                    .foregroundStyle(parameters.referenceA440 ? .orange:.primary)
            }.help(instrumentText("440 Hz reference tone","440 Hz 基準音","440 Hz 参考音"))
                .accessibilityValue(parameters.referenceA440 ? "On":"Off")
            Button(action:togglePower) { Image(systemName:"power").foregroundStyle(engine.isRunning ? .mint:.secondary) }
                .help(instrumentText("Power","電源","电源"))
                .accessibilityLabel(instrumentText("Power","電源","电源"))
        }.buttonStyle(.borderless).controlSize(.regular)
    }

    private var memory: some View {
        VStack(alignment:.leading,spacing:8) {
            HStack {
                Text("PROGRAMMER").font(.system(size:11,weight:.semibold,design:.monospaced))
                Spacer()
                Text("\(selectedFile) · \(bank)–\(program)").monospacedDigit().foregroundStyle(.orange)
                Button { loadProgram() } label: { Image(systemName:"arrow.down.doc") }
                    .help(instrumentText("Recall program","音色を読み込む","载入音色"))
                    .accessibilityLabel(instrumentText("Recall program","音色を読み込む","载入音色"))
                Button { saveProgram() } label: { Image(systemName:"record.circle") }
                    .help(instrumentText("Record program","音色を保存","保存音色"))
                    .accessibilityLabel(instrumentText("Record program","音色を保存","保存音色"))
            }
            HStack {
                Picker("FILE",selection:$selectedFile) { ForEach(1...3,id:\.self) { Text("\($0)").tag($0) } }
                Picker("BANK",selection:$bank) { ForEach(1...5,id:\.self) { Text("\($0)").tag($0) } }
            }.pickerStyle(.menu)
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:4),count:8),spacing:4) {
                ForEach(1...8,id:\.self) { number in
                    Button { program=number; loadProgram() } label: {
                        Text("\(number)").font(.system(size:12,weight:.semibold,design:.monospaced))
                            .frame(maxWidth:.infinity,minHeight:32).padding(.horizontal,2)
                            .foregroundStyle(program == number ? .orange:.primary)
                            .background(.white.opacity(0.07),in:RoundedRectangle(cornerRadius:5))
                    }.buttonStyle(.plain)
                }
            }
            if !memoryStatus.isEmpty { Text(memoryStatus).font(.caption).foregroundStyle(.secondary) }
        }.padding(12).background(.white.opacity(0.035),in:RoundedRectangle(cornerRadius:8))
    }

    private var nativeEditor: some View {
        VStack(alignment:.leading,spacing:18) {
            ForEach(Rev3.sections.indices,id:\.self) { index in
                VStack(alignment:.leading,spacing:8) {
                    Text(Rev3.sections[index].title).font(.system(.caption,design:.monospaced)).foregroundStyle(.mint)
                    ForEach(Rev3.sections[index].knobs,id:\.self) { knob in editorControl(knob) }
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
    private var fallbackKeyboard: some View {
        HStack(spacing:4) {
            ForEach([60,62,64,65,67,69,71,72],id:\.self) { note in
                Text(["C","C♯","D","D♯","E","F","F♯","G","G♯","A","A♯","B"][note%12])
                    .font(.caption).frame(width:30,height:70).background(.white.opacity(0.15),in:RoundedRectangle(cornerRadius:4))
                    .gesture(DragGesture(minimumDistance:0).onChanged { _ in engine.playNote(note) }.onEnded { _ in engine.releaseNote(note) })
            }
        }
    }
    private func apply() { engine.sharedParams.set { $0=parameters } }
    private func togglePower() {
        if engine.isRunning { engine.stop() } else { engine.start(); apply() }
    }
    private var memoryKey: String { "synth.rev3.v1.\(selectedFile).\(bank).\(program)" }
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
