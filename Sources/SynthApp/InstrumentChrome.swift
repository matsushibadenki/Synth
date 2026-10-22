import SwiftUI

// Hallmark · reference-led instrument enclosure · native SwiftUI tokens
// Pre-emit critique: P5 H4 E4 S5 R4 V4. Existing cyan/lime panel stays primary.
enum InstrumentFinish {
    static let backdrop = Color(red:0.025,green:0.028,blue:0.03)
    static let metal = Color(red:0.065,green:0.073,blue:0.078)
    static let metalEdge = Color(red:0.17,green:0.185,blue:0.19)
    static let recess = Color(red:0.018,green:0.022,blue:0.022)
    static let ink = Color(red:0.83,green:0.84,blue:0.77)
    static let muted = Color(red:0.62,green:0.66,blue:0.64)
    static let amber = Color(red:1,green:0.61,blue:0.25)
    static let amberOff = Color(red:0.20,green:0.115,blue:0.055)
    static let wood = Color(red:0.28,green:0.13,blue:0.065)
    static let woodEdge = Color(red:0.48,green:0.27,blue:0.13)
    static let shadow = Color.black
    static let highlight = Color.white
    static func legend(_ size: CGFloat = 10) -> Font { .system(size:size,weight:.semibold,design:.monospaced) }
    static let wordmark = Font.custom("HelveticaNeue-CondensedBold",size:26)
}

struct CabinetFinish: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius:8)
                .fill(LinearGradient(colors:[InstrumentFinish.metalEdge,InstrumentFinish.metal,InstrumentFinish.recess],startPoint:.top,endPoint:.bottom))
            RoundedRectangle(cornerRadius:8).strokeBorder(InstrumentFinish.metalEdge,lineWidth:1)
        }
        .shadow(color:InstrumentFinish.shadow.opacity(0.6),radius:12,y:6)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct CabinetRails: View {
    var body: some View {
        HStack {
            WoodCheek().frame(width:8)
            Spacer(minLength:0)
            WoodCheek().frame(width:8)
        }.padding(2).allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct WoodCheek: View {
    var body: some View {
        RoundedRectangle(cornerRadius:3)
            .fill(LinearGradient(colors:[InstrumentFinish.woodEdge,InstrumentFinish.wood,InstrumentFinish.woodEdge.opacity(0.8)],startPoint:.leading,endPoint:.trailing))
            .overlay {
                Canvas { context,size in
                    for i in 0..<7 {
                        var path=Path()
                        let x=CGFloat(i)*1.6
                        path.move(to:CGPoint(x:x,y:0))
                        path.addCurve(to:CGPoint(x:x+1,y:size.height),control1:CGPoint(x:x-3,y:size.height*0.3),control2:CGPoint(x:x+4,y:size.height*0.7))
                        context.stroke(path,with:.color(InstrumentFinish.shadow.opacity(0.2)),lineWidth:0.55)
                    }
                }.clipShape(RoundedRectangle(cornerRadius:3))
            }
    }
}

struct PanelScrew: View {
    var body: some View {
        Circle().fill(InstrumentFinish.recess).frame(width:7,height:7)
            .overlay { Capsule().fill(InstrumentFinish.muted.opacity(0.55)).frame(width:4,height:1).rotationEffect(.degrees(-25)) }
            .overlay { Circle().strokeBorder(InstrumentFinish.highlight.opacity(0.12),lineWidth:0.5) }
            .accessibilityHidden(true)
    }
}

struct HardwareButtonStyle: ButtonStyle {
    var selected=false
    func makeBody(configuration: Configuration) -> some View {
        HardwareButtonFace(configuration:configuration,selected:selected)
    }
    private struct HardwareButtonFace: View {
        let configuration: ButtonStyle.Configuration
        let selected: Bool
        @Environment(\.isEnabled) private var enabled
        @State private var hovering=false
        var body: some View {
            configuration.label
                .font(InstrumentFinish.legend(11)).lineLimit(1)
                .foregroundStyle(enabled ? (selected ? InstrumentFinish.amber:InstrumentFinish.ink):InstrumentFinish.muted)
                .background {
                    RoundedRectangle(cornerRadius:3)
                        .fill(LinearGradient(colors:configuration.isPressed ? [InstrumentFinish.recess,InstrumentFinish.metal]:[InstrumentFinish.metalEdge,InstrumentFinish.metal],startPoint:.top,endPoint:.bottom))
                        .overlay { RoundedRectangle(cornerRadius:3).strokeBorder(hovering ? InstrumentFinish.muted:InstrumentFinish.metalEdge,lineWidth:1) }
                        .shadow(color:InstrumentFinish.shadow.opacity(0.8),radius:1,y:configuration.isPressed ? 0:2)
                }
                .overlay(alignment:.top) {
                    if selected { Capsule().fill(InstrumentFinish.amber).frame(width:12,height:2).padding(.top,3) }
                }
                .offset(y:configuration.isPressed ? 1:0)
                .onHover { hovering=$0 }
        }
    }
}

struct ProgramReadout: View {
    let file: Int
    let bank: Int
    let program: Int
    var body: some View {
        VStack(spacing:4) {
            Text("FILE  BANK  PROGRAM").font(InstrumentFinish.legend(8)).tracking(0.3).foregroundStyle(InstrumentFinish.muted).lineLimit(1)
            HStack(spacing:10) {
                SegmentDigit(value:file)
                SegmentDigit(value:bank)
                SegmentDigit(value:program)
            }.padding(.horizontal,12).padding(.vertical,7)
                .background(InstrumentFinish.recess,in:RoundedRectangle(cornerRadius:3))
                .overlay { RoundedRectangle(cornerRadius:3).strokeBorder(InstrumentFinish.metalEdge,lineWidth:1) }
        }
        .fixedSize(horizontal:true,vertical:false)
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(instrumentText("Program","プログラム","音色"))
        .accessibilityValue("\(file) · \(bank)–\(program)")
    }
}

private struct SegmentDigit: View {
    let value: Int
    private let masks: [Int] = [0x3f,0x06,0x5b,0x4f,0x66,0x6d,0x7d,0x07,0x7f,0x6f]
    var body: some View {
        Canvas { context,size in
            let segments: [(CGFloat,CGFloat,CGFloat,CGFloat)] = [
                (3,0,12,2),(16,3,2,10),(16,16,2,10),(3,27,12,2),
                (0,16,2,10),(0,3,2,10),(3,13.5,12,2)
            ]
            for (i,s) in segments.enumerated() {
                let rect=CGRect(x:s.0,y:s.1,width:s.2,height:s.3)
                let path=Path(roundedRect:rect,cornerRadius:1)
                context.fill(path,with:.color(masks[min(9,max(0,value))] & (1<<i) != 0 ? InstrumentFinish.amber:InstrumentFinish.amberOff))
            }
        }.frame(width:18,height:29).accessibilityHidden(true)
    }
}

struct ProgrammerPanel: View {
    @Binding var file: Int
    @Binding var bank: Int
    @Binding var program: Int
    let status: String
    let recall: () -> Void
    let record: () -> Void
    var compact = false
    var splitKeys = false

    var body: some View {
        if compact { compactBody } else { standardBody }
    }
    private var standardBody: some View {
        VStack(alignment:.leading,spacing:8) {
            HStack(spacing:8) {
                PanelScrew()
                Text("PROGRAMMER").font(InstrumentFinish.legend()).tracking(1.5)
                Rectangle().fill(InstrumentFinish.metalEdge).frame(height:1)
                PanelScrew()
            }.foregroundStyle(InstrumentFinish.ink)
            ViewThatFits(in:.horizontal) {
                VStack(alignment:.leading,spacing:8) {
                    HStack(alignment:.bottom,spacing:18) {
                        readout
                        selectors
                        keys.frame(width:336)
                        actions
                        VentGrille().frame(minWidth:0,maxWidth:.infinity,minHeight:32,maxHeight:32).padding(.horizontal,2)
                    }
                    statusLabel
                }
                VStack(spacing:10) {
                    HStack(alignment:.bottom) { readout; Spacer(minLength:8); selectors }
                    keys
                    HStack { statusLabel; Spacer(minLength:4); actions }
                }
            }
        }
        .padding(.horizontal,16).padding(.vertical,10)
        .background(InstrumentFinish.metal.opacity(0.8))
        .overlay(alignment:.top) { Rectangle().fill(InstrumentFinish.metalEdge).frame(height:1) }
    }
    private var compactBody: some View {
        ViewThatFits(in:.horizontal) {
            VStack(alignment:.leading,spacing:6) {
                compactHeading
                HStack(alignment:.bottom,spacing:8) { readout; selectors; keys.frame(width:336); actions }
            }
            VStack(alignment:.leading,spacing:6) {
                compactHeading
                HStack(alignment:.bottom,spacing:6) { readout; selectors; actions }
                keys
            }
            VStack(alignment:.leading,spacing:6) {
                HStack(spacing:6) { compactHeading; actions }
                HStack(alignment:.bottom,spacing:6) { readout; Spacer(minLength:0); selectors }
                keys
            }
        }.padding(.horizontal,16).padding(.vertical,6)
    }
    private var compactHeading: some View {
        HStack(spacing:6) {
            PanelScrew()
            Text("PROGRAMMER").font(InstrumentFinish.legend(9)).tracking(0.7).fixedSize()
            Text(status).font(InstrumentFinish.legend(9)).foregroundStyle(InstrumentFinish.muted).lineLimit(1)
            Spacer(minLength:0)
        }.foregroundStyle(InstrumentFinish.ink).help(status)
    }
    private var readout: some View { ProgramReadout(file:file,bank:bank,program:program) }
    private var selectors: some View {
        HStack(spacing:6) {
            selector("FILE",value:$file,range:1...3)
            selector("BANK",value:$bank,range:1...5)
        }
    }
    private func selector(_ label: String,value: Binding<Int>,range: ClosedRange<Int>) -> some View {
        VStack(spacing:4) {
            Text(label).font(InstrumentFinish.legend(8)).foregroundStyle(InstrumentFinish.muted)
            Button {
                value.wrappedValue=value.wrappedValue == range.upperBound ? range.lowerBound:value.wrappedValue+1
            } label: {
                HStack(spacing:6) { Text("\(value.wrappedValue)"); Image(systemName:"chevron.right").font(InstrumentFinish.legend(8)) }
                    .frame(width:42,height:32)
            }
            .buttonStyle(HardwareButtonStyle())
            .contextMenu {
                ForEach(Array(range),id:\.self) { item in
                    Button { value.wrappedValue=item } label: {
                        if item == value.wrappedValue { Label("\(item)",systemImage:"checkmark") } else { Text("\(item)") }
                    }
                }
            }
            .help(instrumentText("Advance selection; secondary click to choose directly","クリックで次へ。右クリック／長押しで直接選択","点击切换，右键或长按直接选择"))
            .accessibilityValue("\(value.wrappedValue)")
            .accessibilityLabel(label == "FILE" ? instrumentText("Program file","プログラムファイル","音色文件"):instrumentText("Bank","バンク","音色库"))
        }
    }
    private var keys: some View {
        LazyVGrid(columns:Array(repeating:splitKeys ? GridItem(.fixed(38),spacing:5):GridItem(.flexible(),spacing:5),count:splitKeys ? 4:8),alignment:.leading,spacing:5) {
            ForEach(1...8,id:\.self) { number in
                Button { program=number; recall() } label: {
                    Text("\(number)").frame(maxWidth:.infinity,minHeight:32).padding(.horizontal,1)
                }
                .buttonStyle(HardwareButtonStyle(selected:program == number))
                .accessibilityLabel(instrumentText("Program \(number)","プログラム \(number)","音色 \(number)"))
                .accessibilityAddTraits(program == number ? .isSelected:[])
            }
        }
    }
    private var actions: some View {
        HStack(spacing:6) {
            Button(action:recall) { Image(systemName:"arrow.down.doc").frame(width:32,height:32) }
                .help(instrumentText("Recall program","音色を読み込む","载入音色"))
                .accessibilityLabel(instrumentText("Recall program","音色を読み込む","载入音色"))
            Button(action:record) { Image(systemName:"record.circle").frame(width:32,height:32) }
                .help(instrumentText("Record program","音色を保存","保存音色"))
                .accessibilityLabel(instrumentText("Record program","音色を保存","保存音色"))
        }.buttonStyle(HardwareButtonStyle())
    }
    private var statusLabel: some View {
        Text(status.isEmpty ? " ":status).font(InstrumentFinish.legend(9))
            .foregroundStyle(InstrumentFinish.muted).fixedSize(horizontal:false,vertical:true)
    }
}

private struct VentGrille: View {
    var body: some View {
        Canvas { context,size in
            guard size.width > 55 else { return }
            let count=Int(size.width/9)
            for index in 0..<count {
                let slot=CGRect(x:CGFloat(index)*9+2,y:4,width:3,height:size.height-8)
                context.fill(Path(roundedRect:slot.offsetBy(dx:0,dy:1),cornerRadius:1.5),with:.color(InstrumentFinish.metalEdge))
                context.fill(Path(roundedRect:slot,cornerRadius:1.5),with:.color(InstrumentFinish.recess))
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
