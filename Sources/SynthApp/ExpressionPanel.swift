import SwiftUI

/// Uses the rack's existing hardware switches, engraved legends and rotary knobs.
struct ExpressionPanel: View {
    @Binding var parameters: ExpressionParameters
    let changed: () -> Void
    @State private var showInfo=false
    private var info: String {
        instrumentText("Extended adds a sine sub oscillator, filter motion and auto pan. SYNTH/05 bypasses these additions and retains their settings. Ladder blends a four-stage filter; Drive and Feedback add color, and slope selects 6–24 dB/oct. FX remain independent.","Extendedはサイン波サブ、フィルターの揺らぎ、オートパンを追加。SYNTH/05で追加処理を無効化し、調整値は保持します。Ladderで4段フィルターを混合。DriveとFeedbackで音に厚みを加え、傾きを6〜24dB/octで切り替えます。FXは独立して動作します。","Extended添加正弦波低音、滤波调制和自动声像。SYNTH/05旁通新增处理并保留参数，Ladder混合四级滤波，Drive与Feedback增加音色质感，可选6–24dB/oct斜率。效果独立运行。")
    }
    var body: some View {
        VStack(spacing:10) {
            HStack(spacing:6) {
                PanelScrew()
                ForEach([false,true],id:\.self) { extended in
                    Button { parameters.enabled=extended; changed() } label: {
                        Text(extended ? "EXTENDED":"SYNTH/05").padding(.horizontal,10).frame(height:34)
                    }.buttonStyle(HardwareButtonStyle(selected:parameters.enabled == extended))
                        .accessibilityAddTraits(parameters.enabled == extended ? .isSelected:[])
                }
                Spacer(minLength:0)
                Button { showInfo.toggle() } label: { Image(systemName:"info.circle").frame(width:32,height:32) }
                    .buttonStyle(.plain).help(info)
                    .accessibilityLabel(instrumentText("Expression information","拡張音源の情報","扩展音源信息"))
                    .popover(isPresented:$showInfo) { Text(info).padding(20).frame(idealWidth:280) }
            }
            if parameters.enabled {
                Rectangle().fill(InstrumentFinish.metalEdge).frame(height:1)
                LazyVGrid(columns:[GridItem(.adaptive(minimum:76),spacing:8)],spacing:10) {
                    knob(FXControl("SUB","Sub oscillator","サブオシレーター","低音振荡器"),key:\.sub)
                    knob(FXControl("MOTION","Filter motion","フィルターの揺らぎ","滤波调制"),key:\.motion)
                    knob(FXControl("RATE","Motion / pan rate","揺らぎ／パンの速度","调制／声像速率",0.05,8,"Hz"),key:\.rate)
                    knob(FXControl("AUTO PAN","Auto pan","オートパン","自动声像"),key:\.pan)
                }
                Rectangle().fill(InstrumentFinish.metalEdge).frame(height:1)
                LazyVGrid(columns:[GridItem(.adaptive(minimum:76),spacing:8)],spacing:10) {
                    knob(FXControl("LADDER","Ladder filter blend","ラダーフィルター混合","梯形滤波混合"),key:\.ladder)
                    knob(FXControl("DRIVE","Filter drive","フィルタードライブ","滤波驱动"),key:\.drive)
                    knob(FXControl("FEEDBACK","Filter feedback","フィルターフィードバック","滤波反馈"),key:\.feedback)
                }
                HStack(spacing:6) {
                    Text("dB/OCT").font(InstrumentFinish.legend(8)).foregroundStyle(InstrumentFinish.muted)
                    ForEach(1...4,id:\.self) { poles in
                        Button { parameters.slope=Float(poles-1)/3; changed() } label: {
                            Text("\(poles*6)").frame(width:36,height:32)
                        }.buttonStyle(HardwareButtonStyle(selected:Int((ExpressionParameters.unit(parameters.slope)*3).rounded()) == poles-1))
                            .accessibilityLabel(instrumentText("Filter slope","フィルターの傾き","滤波斜率")+" \(poles*6) dB/oct")
                            .accessibilityAddTraits(Int((ExpressionParameters.unit(parameters.slope)*3).rounded()) == poles-1 ? .isSelected:[])
                    }
                }
                HStack {
                    PanelScrew()
                    Spacer(minLength:4)
                    Circle().fill(InstrumentFinish.amber).frame(width:5,height:5)
                    Text("EXPRESSION").font(InstrumentFinish.legend(8)).tracking(1.5).foregroundStyle(InstrumentFinish.muted)
                    Spacer(minLength:4)
                    PanelScrew()
                }
            }
        }.foregroundStyle(InstrumentFinish.ink)
            .padding(.horizontal,16).padding(.vertical,10)
            .background(InstrumentFinish.metal,in:RoundedRectangle(cornerRadius:4))
            .overlay { RoundedRectangle(cornerRadius:4).strokeBorder(InstrumentFinish.metalEdge,lineWidth:1) }
            .padding(.horizontal,16).padding(.vertical,8)
    }
    private func knob(_ control: FXControl,key: WritableKeyPath<ExpressionParameters,Float>) -> some View {
        let isRate=key == \.rate
        let value=parameters[keyPath:key]
        let initial=ExpressionParameters()[keyPath:key]
        let normalize: (Float) -> Float = { isRate ? ($0-0.05)/7.95 : $0 }
        let update: (Float) -> Void = {
            parameters[keyPath:key]=isRate ? 0.05+$0*7.95 : $0
            changed()
        }
        return FXKnob(control:control,value:normalize(value),resetValue:normalize(initial),preview:update,commit:update)
    }
}

struct ExpressionPanel_Previews: PreviewProvider {
    static var previews: some View {
        ExpressionPanel(parameters:.constant(ExpressionParameters(enabled:true)),changed:{})
            .previewDevice("iPhone SE (3rd generation)")
        ExpressionPanel(parameters:.constant(ExpressionParameters(enabled:true)),changed:{})
            .previewDevice("iPhone 16 Pro Max")
    }
}
