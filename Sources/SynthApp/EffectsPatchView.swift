import SwiftUI

struct EffectsPatchView: View {
    @ObservedObject var rack: EffectsController
    let editEffect: (EffectKind) -> Void
    @State private var source: Int?
    @State private var showInfo=false
    @State private var moving: Int?
    @State private var offset=CGSize.zero
    private let cardWidth: CGFloat=200
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            HStack(spacing:6) {
                Text("PATCH / STEREO").font(InstrumentFinish.legend(11))
                Spacer(minLength:4)
                tool("arrow.uturn.backward",fxText("Undo","元に戻す","撤销"),enabled:rack.canUndo) { rack.undo() }
                tool("arrow.uturn.forward",fxText("Redo","やり直す","重做"),enabled:rack.canRedo) { rack.redo() }
                Button { showInfo.toggle() } label: { Image(systemName:"info.circle").frame(width:32,height:32) }
                    .buttonStyle(HardwareButtonStyle()).help(instructions)
                    .popover(isPresented:$showInfo) { Text(instructions).padding(20).frame(idealWidth:300) }
            }
            HStack(spacing:6) {
                Button { source=nil; rack.serial() } label: { Label("SERIES",systemImage:"arrow.right").padding(.horizontal,10).frame(height:32) }
                Button { source=nil; rack.parallel() } label: { Label("PARALLEL",systemImage:"arrow.triangle.branch").padding(.horizontal,10).frame(height:32) }
                Spacer(minLength:0)
                if source != nil { tool("xmark",fxText("Cancel cable","接続をキャンセル","取消连线")) { source=nil } }
            }.buttonStyle(HardwareButtonStyle())
            ScrollViewReader { proxy in
            ScrollView([.horizontal,.vertical]) {
                ZStack(alignment:.topLeading) {
                    Color.clear.frame(width:1,height:1).id("patch-origin")
                    Canvas { context,size in
                        for x in stride(from:CGFloat(12),to:size.width,by:20) {
                            for y in stride(from:CGFloat(12),to:size.height,by:20) {
                                context.fill(Path(ellipseIn:CGRect(x:x,y:y,width:1.5,height:1.5)),with:.color(InstrumentFinish.metalEdge))
                            }
                        }
                        for edge in rack.document.edges {
                            guard let from=rack.document.nodes.first(where:{$0.id == edge.from}),let to=rack.document.nodes.first(where:{$0.id == edge.to}) else { continue }
                            let a=point(from,output:true), b=point(to,output:false,port:edge.port)
                            var path=Path(); path.move(to:a)
                            let bend=min(120,max(55,abs(b.x-a.x)*0.45))
                            path.addCurve(to:b,control1:CGPoint(x:a.x+bend,y:a.y),control2:CGPoint(x:b.x-bend,y:b.y))
                            context.stroke(path,with:.color(from.kind.finish.opacity(0.9)),lineWidth:4)
                            context.stroke(path,with:.color(InstrumentFinish.ink.opacity(0.45)),lineWidth:1)
                        }
                    }.allowsHitTesting(false)
                    ForEach(rack.document.nodes) { node in nodeCard(node).offset(x:CGFloat(node.x)+(moving == node.id ? offset.width:0),y:CGFloat(node.y)+(moving == node.id ? offset.height:0)) }
                }.frame(width:960,height:650).background(InstrumentFinish.recess)
            }.frame(height:480).clipShape(RoundedRectangle(cornerRadius:6))
                .overlay { RoundedRectangle(cornerRadius:6).strokeBorder(InstrumentFinish.metalEdge,lineWidth:1) }
                .onAppear { proxy.scrollTo("patch-origin",anchor:.topLeading) }
            }
            if let source {
                Text(fxText("Connect: ","接続元：","连接源：")+EffectKind(rawValue:source)!.title)
                    .font(InstrumentFinish.legend(9)).foregroundStyle(InstrumentFinish.amber)
            }
            if !rack.error.isEmpty { Text(rack.error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal:false,vertical:true) }
            DisclosureGroup {
                VStack(spacing:4) {
                    ForEach(rack.document.edges) { edge in
                        HStack {
                            Text("\(EffectKind(rawValue:edge.from)!.title) → \(EffectKind(rawValue:edge.to)!.title) · \(edge.port.uppercased())")
                                .font(InstrumentFinish.legend(9)).fixedSize(horizontal:false,vertical:true)
                            Spacer(minLength:4)
                            tool("xmark",fxText("Disconnect","接続を解除","断开连接")) { rack.execute(.disconnect(edge.id)) }
                        }
                    }
                }
            } label: { Label(fxText("Cables","ケーブル","连线"),systemImage:"cable.connector").font(InstrumentFinish.legend(10)) }
        }.foregroundStyle(InstrumentFinish.ink).padding(.horizontal,16).padding(.vertical,12)
    }
    private func nodeCard(_ node: FXNode) -> some View {
        ZStack(alignment:.topLeading) {
            RoundedRectangle(cornerRadius:7).fill(InstrumentFinish.metal)
                .overlay { RoundedRectangle(cornerRadius:7).strokeBorder(source == node.id ? InstrumentFinish.amber:node.kind.finish,lineWidth:source == node.id ? 2:1) }
            VStack(alignment:.leading,spacing:7) {
                HStack(spacing:6) {
                    Image(systemName:node.kind.symbol).foregroundStyle(InstrumentFinish.ink)
                    Text(shortName(node.kind)).font(InstrumentFinish.legend(11)).lineLimit(1)
                    Spacer(minLength:0)
                    Image(systemName:"line.3.horizontal").font(.system(size:9)).opacity(0.4)
                }.padding(10).background(node.kind.finish,in:RoundedRectangle(cornerRadius:7))
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance:4).onChanged { event in moving=node.id; offset=event.translation }.onEnded { event in
                        rack.execute(.move(node.id,min(700,max(0,node.x+event.translation.width)),min(480,max(0,node.y+event.translation.height))))
                        moving=nil; offset = .zero
                    })
                HStack {
                    Text(node.kind.modes[node.settings.mode]).font(InstrumentFinish.legend(8)).foregroundStyle(InstrumentFinish.muted)
                    Spacer(minLength:0)
                    if (1...6).contains(node.id) {
                        Button { editEffect(node.kind) } label: { Image(systemName:"slider.horizontal.3").frame(width:24,height:20) }
                            .buttonStyle(.plain).help(fxText("Edit effect","エフェクトを編集","编辑效果"))
                    }
                }.padding(.horizontal,10)
            }
            ForEach(node.inputs,id:\.self) { port in
                portButton(node,output:false,port:port).position(x:12,y:port == "b" ? 112:80)
            }
            if !node.outputs.isEmpty { portButton(node,output:true,port:"out").position(x:cardWidth-12,y:80) }
            if (1...6).contains(node.id) {
                Button { rack.update(node.kind) { $0.enabled.toggle() } } label: {
                    Circle().fill(node.settings.enabled ? InstrumentFinish.amber:InstrumentFinish.amberOff).frame(width:7,height:7).frame(width:28,height:28)
                }.buttonStyle(.plain).position(x:cardWidth/2,y:82)
                    .accessibilityLabel(node.kind.title+" "+fxText("Bypass","バイパス","旁通"))
                    .accessibilityValue(node.settings.enabled ? fxText("Engaged","有効","启用"):fxText("Bypassed","バイパス","旁通"))
            }
            if node.kind == .mixer {
                HStack(spacing:10) {
                    ForEach(0..<2) { index in
                        VStack(spacing:0) {
                            Text(index == 0 ? "A":"B").font(InstrumentFinish.legend(8))
                            Slider(value:Binding(get:{Double(node.settings.values[index])},set:{ value in rack.update(.mixer) { $0.values[index]=Float(value) } }),in:0...1)
                                .frame(width:62).accessibilityLabel(index == 0 ? "Mix A":"Mix B")
                        }
                    }
                }.position(x:cardWidth/2,y:104)
            }
        }.frame(width:cardWidth,height:node.kind == .mixer ? 140:112)
            .shadow(color:.black.opacity(0.5),radius:4,y:3)
    }
    private func portButton(_ node: FXNode,output: Bool,port: String) -> some View {
        Button {
            if output { source=node.id; rack.error="" }
            else if let from=source { rack.connect(from:from,to:node.id,port:port); if rack.error.isEmpty { source=nil } }
            else { rack.error=fxText("Select an output port first.","先に出力ポートを選択してください。","请先选择输出端口。") }
        } label: {
            Circle().fill(InstrumentFinish.recess).frame(width:12,height:12)
                .overlay { Circle().strokeBorder(source == node.id && output ? InstrumentFinish.amber:InstrumentFinish.ink,lineWidth:2) }
                .frame(width:28,height:28).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel(node.kind.title+" "+(output ? fxText("Output","出力","输出"):fxText("Input ","入力 ","输入 ")+port.uppercased()))
            .help(output ? fxText("Select output","出力を選択","选择输出"):fxText("Connect input; secondary click to disconnect","入力を接続。右クリック／長押しで切断","连接输入，右键或长按断开"))
            .contextMenu {
                ForEach(rack.document.edges.filter { output ? $0.from == node.id:($0.to == node.id && $0.port == port) }) { edge in
                    Button(fxText("Disconnect ","接続を解除：","断开连接：")+EffectKind(rawValue:output ? edge.to:edge.from)!.title) { rack.execute(.disconnect(edge.id)) }
                }
            }
    }
    private func point(_ node: FXNode,output: Bool,port: String="out") -> CGPoint {
        CGPoint(x:node.x+(output ? Double(cardWidth-12):12)+(moving == node.id ? offset.width:0),y:node.y+(port == "b" ? 112:80)+(moving == node.id ? offset.height:0))
    }
    private func shortName(_ kind: EffectKind) -> String { ["SYNTH / 05","DIMENSION","SKY","TIME","ECHO PEDAL","RING / 102","STUDIO","MIX / A + B","STEREO OUT"][kind.rawValue] }
    private var instructions: String {
        fxText("Select an output port, then an input port. Remove cables from the input's context menu or cable list. Drag node headers to move. MIX A/B combines parallel branches; disconnected inputs are silent. Edits and settings are saved automatically.","出力ポート→入力ポートの順に選択して接続。入力の右クリック／長押し、またはケーブル一覧から切断できます。見出しをドラッグして移動。MIX A/Bで並列経路を合流します。未接続の入力は無音です。編集と設定は自動保存されます。","依次选择输出、输入端口连接。右键或长按输入端口，或从连线列表断开。拖动标题移动节点。MIX A/B合并并行路径，未连接输入为静音。编辑和设置自动保存。")
    }
    private func tool(_ icon: String,_ help: String,enabled: Bool=true,action: @escaping () -> Void) -> some View {
        Button(action:action) { Image(systemName:icon).frame(width:32,height:32) }.buttonStyle(HardwareButtonStyle()).help(help).accessibilityLabel(help).disabled(!enabled)
    }
}
