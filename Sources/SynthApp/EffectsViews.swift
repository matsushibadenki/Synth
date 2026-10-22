import SwiftUI

enum RackTab: Int, CaseIterable, Identifiable {
    case synth, dimension, ambience, pedal, ring, studio, patch
    var id: Int { rawValue }
    var title: String { ["SYNTH", "DIMENSION", "SKY / TIME", "PEDAL", "RING", "STUDIO", "PATCH"][rawValue] }
    var icon: String { ["pianokeys","waveform.path","cloud","guitars","waveform.path.ecg","slider.horizontal.3","point.3.connected.trianglepath.dotted"][rawValue] }
    var help: String {
        switch self {
        case .synth: return fxText("Synthesizer","シンセサイザー","合成器")
        case .dimension: return "Roland Dimension / Flanger"
        case .ambience: return "Strymon BigSky / TimeLine"
        case .pedal: return "Line 6 DL4 MkII"
        case .ring: return "Moog MF-102"
        case .studio: return "t.c. electronic SCF / 2290"
        case .patch: return fxText("Node connections","ノード接続","节点连接")
        }
    }
}
struct RackTabStrip: View {
    @Binding var selection: RackTab
    var body: some View {
        ScrollViewReader { proxy in
        ScrollView(.horizontal,showsIndicators:false) {
            HStack(spacing:5) {
                ForEach(RackTab.allCases) { tab in
                    Button { selection=tab } label: {
                        Label(tab.title,systemImage:tab.icon).padding(.horizontal,10).frame(height:36)
                    }.buttonStyle(HardwareButtonStyle(selected:selection == tab))
                        .help(tab.help).accessibilityLabel(tab.help)
                        .accessibilityAddTraits(selection == tab ? .isSelected:[]).id(tab.id)
                }
            }.padding(.horizontal,16).padding(.vertical,8)
        }.background(InstrumentFinish.recess)
            .onChange(of:selection) { tab in proxy.scrollTo(tab.id,anchor:.center) }
        }
    }
}
extension EffectKind {
    var finish: Color {
        switch self {
        case .dimension: return Color(red:0.24,green:0.23,blue:0.43)
        case .sky: return Color(red:0.12,green:0.36,blue:0.51)
        case .time: return Color(red:0.26,green:0.31,blue:0.32)
        case .pedal: return Color(red:0.16,green:0.36,blue:0.22)
        case .ring: return Color(red:0.30,green:0.22,blue:0.13)
        case .studio: return Color(red:0.21,green:0.25,blue:0.29)
        default: return InstrumentFinish.metal
        }
    }
}
struct EffectsWorkspace: View {
    @ObservedObject var rack: EffectsController
    let tab: RackTab
    let openPatch: () -> Void
    var body: some View {
        VStack(spacing:10) {
            HStack {
                Label("STEREO FX",systemImage:"cable.connector").font(InstrumentFinish.legend(9)).foregroundStyle(InstrumentFinish.muted)
                Spacer(minLength:4)
                Button(action:openPatch) { Image(systemName:"point.3.connected.trianglepath.dotted").frame(width:36,height:32) }
                    .buttonStyle(HardwareButtonStyle()).help(fxText("Patch cables","ケーブル接続","连线"))
            }
            if tab == .ambience {
                ViewThatFits(in:.horizontal) {
                    HStack(alignment:.top,spacing:12) {
                        EffectModule(rack:rack,kind:.sky).frame(minWidth:414,maxWidth:520).padding(.horizontal,0)
                        EffectModule(rack:rack,kind:.time).frame(minWidth:414,maxWidth:520).padding(.horizontal,0)
                    }
                    VStack(spacing:12) {
                        EffectModule(rack:rack,kind:.sky).frame(maxWidth:520).padding(.horizontal,0)
                        EffectModule(rack:rack,kind:.time).frame(maxWidth:520).padding(.horizontal,0)
                    }
                }
            } else { EffectModule(rack:rack,kind:kind).frame(maxWidth:520).padding(.horizontal,0) }
        }.padding(.horizontal,16).padding(.vertical,12)
    }
    private var kind: EffectKind {
        switch tab { case .dimension: return .dimension; case .pedal: return .pedal; case .ring: return .ring; default: return .studio }
    }
}
struct EffectModule: View {
    @ObservedObject var rack: EffectsController
    let kind: EffectKind
    @State private var showInfo=false
    private var state: FXSettings { rack.settings(kind) }
    var body: some View {
        VStack(spacing:16) {
            HStack(spacing:8) {
                PanelScrew()
                VStack(alignment:.leading,spacing:3) {
                    Text(kind.title).font(.custom("HelveticaNeue-CondensedBold",size:23)).lineLimit(1).minimumScaleFactor(0.65)
                    Text("STEREO · \(String(format:"%02d",kind.rawValue))").font(InstrumentFinish.legend(8)).tracking(2).opacity(0.6)
                }
                Spacer(minLength:0)
                Button { showInfo.toggle() } label: { Image(systemName:"info.circle").frame(width:32,height:32) }
                    .buttonStyle(.plain).help(info).accessibilityLabel(fxText("Effect information","エフェクト情報","效果信息"))
                    .popover(isPresented:$showInfo) { Text(info).font(.callout).padding(20).frame(idealWidth:300) }
                PanelScrew()
            }
            HStack(spacing:8) {
                Circle().fill(state.enabled ? InstrumentFinish.amber:InstrumentFinish.amberOff).frame(width:6,height:6)
                Picker(fxText("Mode","モード","模式"),selection:Binding(get:{state.mode},set:{ value in rack.update(kind) { $0.mode=value } })) {
                    ForEach(kind.modes.indices,id:\.self) { Text(kind.modes[$0]).tag($0) }
                }.labelsHidden().pickerStyle(.menu).tint(InstrumentFinish.ink)
                Spacer(minLength:0)
                if kind == .time || kind == .pedal {
                    Button { rack.tap(kind) } label: { Text("TAP").frame(width:44,height:32) }
                        .buttonStyle(HardwareButtonStyle()).help(fxText("Tap delay time","タップでディレイ時間を設定","点击设置延迟时间"))
                }
            }.frame(height:32).padding(8).background(InstrumentFinish.recess,in:RoundedRectangle(cornerRadius:4))
            ViewThatFits(in:.horizontal) {
                HStack(spacing:8) { knobs }
                LazyVGrid(columns:[GridItem(.adaptive(minimum:72),spacing:8)],spacing:18) { knobs }
            }
            if kind == .pedal { pedalControls }
            HStack {
                PanelScrew()
                Spacer(minLength:4)
                Button { rack.update(kind) { $0.enabled.toggle() } } label: {
                    HStack(spacing:10) {
                        FootswitchFace(active:state.enabled)
                        Text(state.enabled ? "ENGAGED":"BYPASS").font(InstrumentFinish.legend(9)).frame(width:64,alignment:.leading)
                    }
                }.buttonStyle(.plain)
                    .accessibilityLabel(fxText("Effect bypass","エフェクトバイパス","效果旁通"))
                    .accessibilityValue(state.enabled ? fxText("Engaged","有効","启用"):fxText("Bypassed","バイパス","旁通"))
                Spacer(minLength:4)
                PanelScrew()
            }
        }.foregroundStyle(InstrumentFinish.ink)
            .padding(.horizontal,16).padding(.vertical,16)
            .background {
                RoundedRectangle(cornerRadius:10).fill(LinearGradient(colors:[kind.finish.opacity(0.8),kind.finish,kind.finish.opacity(0.65)],startPoint:.topLeading,endPoint:.bottomTrailing))
                    .overlay { RoundedRectangle(cornerRadius:10).strokeBorder(.white.opacity(0.18),lineWidth:1) }
                    .shadow(color:.black.opacity(0.5),radius:4,y:4)
            }
    }
    private var knobs: some View {
        ForEach(kind.controls.indices,id:\.self) { index in
            FXKnob(control:displayControl(index),value:state.values[index],resetValue:kind.defaults[index],
                   preview:{rack.preview(kind,index:index,value:$0)},
                   commit:{ value in rack.update(kind) { $0.values[index]=value } })
        }
    }
    private func displayControl(_ index: Int) -> FXControl {
        if kind == .dimension && state.mode == 0 && index == 2 { return FXControl("MANUAL","Manual delay","手動ディレイ","手动延迟",8,26,"ms") }
        if kind == .ring && index == 0 { return FXControl("FREQ","Carrier frequency","キャリア周波数","载波频率",state.mode < 2 ? 0.6:30,state.mode < 2 ? 80:4000,"Hz",true) }
        if kind == .studio && index == 0 {
            return state.mode == 2 ? FXControl("TIME","Delay time","ディレイ時間","延迟时间",25,2000,"ms",true):FXControl("RATE","Rate","速さ","速率",0.05,5,"Hz",true)
        }
        return kind.controls[index]
    }
    private var info: String {
        kind.reference + "\n" + fxText("Inspired by the hardware. Independent DSP; not an emulation of every factory algorithm. Patch order is independent of tab order.","実機を参考にした独自DSPです。全アルゴリズムの再現ではありません。タブ順と接続順は独立しています。","参考实机的独立DSP，并非全部算法的仿真。标签顺序与连线顺序相互独立。")
        + (kind == .pedal ? "\n"+fxText("Looper: 12 seconds, stereo; record → play → overdub. Audio loops are kept in memory only.","ルーパー：ステレオ12秒。録音→再生→重ね録り。録音内容はメモリー内のみ保持します。","循环录音：立体声12秒，录音→播放→叠录，音频仅保存在内存中。") : "")
    }
    private var pedalControls: some View {
        VStack(spacing:12) {
            HStack(spacing:16) {
                ForEach(0..<3) { index in
                    Button { rack.recallPedal(index) } label: {
                        VStack(spacing:5) { Text(["A","B","C"][index]).font(InstrumentFinish.legend()); FootswitchFace(active:state.mode == index) }
                    }.buttonStyle(.plain)
                        .help(fxText("Recall; secondary click to store","読み込み。右クリック／長押しで保存","载入；右键或长按保存"))
                        .accessibilityLabel(fxText("Preset ","プリセット ","预设 ")+["A","B","C"][index])
                        .contextMenu { Button(fxText("Store here","ここに保存","保存到此处")) { rack.storePedal(index) } }
                }
            }
            if state.mode == 3 {
                HStack(spacing:8) {
                    Text(loopTitle).font(InstrumentFinish.legend(9)).foregroundStyle(InstrumentFinish.amber)
                    Spacer(minLength:0)
                    Text(String(format:"%.1f / 12 s",rack.loopSeconds)).font(InstrumentFinish.legend(9)).monospacedDigit()
                }
                HStack(spacing:6) {
                    loopButton("record.circle",fxText("Record / overdub","録音／重ね録り","录音／叠录"),active:rack.loopState == 1 || rack.loopState == 3) { rack.loop(1) }
                    loopButton("playpause",fxText("Play / stop","再生／停止","播放／停止"),active:rack.loopState == 2) { rack.loop(2) }
                    loopButton("backward.end",fxText("Reverse","逆再生","反向"),active:state.reverse) { rack.update(.pedal) { $0.reverse.toggle() } }
                    loopButton("divide",fxText("Half speed","ハーフスピード","半速"),active:state.halfSpeed) { rack.update(.pedal) { $0.halfSpeed.toggle() } }
                    loopButton("trash",fxText("Clear loop","ループを消去","清除循环"),active:false) { rack.loop(3) }
                }
            }
        }.padding(.vertical,8)
            .onReceive(Timer.publish(every:0.2,on:.main,in:.common).autoconnect()) { _ in rack.refreshTelemetry() }
    }
    private var loopTitle: String { ["EMPTY","REC","PLAY","DUB","STOP"][min(4,max(0,rack.loopState))] }
    private func loopButton(_ icon: String,_ label: String,active: Bool,action: @escaping () -> Void) -> some View {
        Button(action:action) { Image(systemName:icon).frame(width:36,height:36) }.buttonStyle(HardwareButtonStyle(selected:active)).help(label).accessibilityLabel(label)
    }
}
struct FootswitchFace: View {
    let active: Bool
    var body: some View {
        Circle().fill(LinearGradient(colors:[.white.opacity(0.8),.gray,.black],startPoint:.topLeading,endPoint:.bottomTrailing))
            .frame(width:44,height:44)
            .overlay { Circle().fill(LinearGradient(colors:[Color(white:0.65),Color(white:0.28)],startPoint:.top,endPoint:.bottom)).padding(7) }
            .overlay { Circle().strokeBorder(.black.opacity(0.6),lineWidth:1).padding(7) }
            .shadow(color:.black.opacity(0.6),radius:2,y:active ? 1:3)
            .accessibilityHidden(true)
    }
}
struct FXKnob: View {
    let control: FXControl
    let value: Float
    let resetValue: Float
    let preview: (Float) -> Void
    let commit: (Float) -> Void
    @State private var dragStart: Float?
    @State private var draft: Float?
    private var current: Float { draft ?? value }
    var body: some View {
        VStack(spacing:5) {
            Text(control.label).font(InstrumentFinish.legend(9)).lineLimit(1)
            ZStack {
                Canvas { context,size in
                    for tick in 0...10 {
                        let angle=Double(tick)*27-225
                        let a=angle * .pi / 180
                        let center=CGPoint(x:size.width/2,y:size.height/2)
                        var path=Path()
                        path.move(to:CGPoint(x:center.x+cos(a)*30,y:center.y+sin(a)*30))
                        path.addLine(to:CGPoint(x:center.x+cos(a)*33,y:center.y+sin(a)*33))
                        context.stroke(path,with:.color(.white.opacity(0.55)),lineWidth:1)
                    }
                }
                Circle().fill(LinearGradient(colors:[.black,Color(white:0.21),.black],startPoint:.topLeading,endPoint:.bottomTrailing)).frame(width:48,height:48)
                    .overlay { Circle().strokeBorder(.black,lineWidth:2) }
                    .shadow(color:.black.opacity(0.65),radius:3,x:1,y:4)
                Circle().fill(AngularGradient(colors:[Color(white:0.75),Color(white:0.25),.white,Color(white:0.35),Color(white:0.75)],center:.center)).frame(width:31,height:31)
                Capsule().fill(InstrumentFinish.ink).frame(width:2,height:11).offset(y:-16)
                    .rotationEffect(.degrees(-135+Double(current)*270))
            }.frame(width:70,height:70).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance:0).onChanged { event in
                    if dragStart == nil { dragStart=value }
                    let next=min(1,max(0,(dragStart ?? value)-Float(event.translation.height)/150))
                    draft=next; preview(next)
                }.onEnded { _ in commit(current); draft=nil; dragStart=nil })
                .onTapGesture(count:2) { commit(resetValue) }
            Text(control.display(current)).font(InstrumentFinish.legend(9)).monospacedDigit().foregroundStyle(InstrumentFinish.ink.opacity(0.75))
        }.accessibilityElement(children:.ignore).accessibilityLabel(control.title).accessibilityValue(control.display(current))
            .accessibilityAdjustableAction { direction in commit(min(1,max(0,value+(direction == .increment ? 0.02:-0.02)))) }
            .help(control.title)
            .onDisappear { if draft != nil { preview(value) } }
    }
}
