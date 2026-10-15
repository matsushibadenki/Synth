import Foundation

// Original Prophet-5 Rev3: 24 programmable potentiometers and 22 switches.
// Source: Sequential CM1000D (2/82), sections 2 and 6-7, pp. 6-5–6-6.
struct SynthParameters: Equatable {
    var polyModFilterEnv: Float = 0
    var polyModOscB: Float = 0
    var lfoRateHz: Float = 3
    var wheelSourceMix: Float = 0
    var oscAFrequency: Float = 24
    var oscAPulseWidth: Float = 0.5
    var oscBFrequency: Float = 24
    var oscBFineCents: Float = 5
    var oscBPulseWidth: Float = 0.5
    var oscALevel: Float = 0.7
    var oscBLevel: Float = 0.7
    var noiseLevel: Float = 0
    var cutoffNorm: Float = 0.42
    var resonance: Float = 0.28
    var filterEnvAmount: Float = 0.35
    var envAAttack: Float = 0.02
    var envADecay: Float = 0.2
    var envASustain: Float = 0.75
    var envARelease: Float = 0.3
    var envBAttack: Float = 0.01
    var envBDecay: Float = 0.18
    var envBSustain: Float = 0.8
    var envBRelease: Float = 0.3
    var glideTime: Float = 0
    var masterTuneSemitones: Float = 0
    var masterVolume: Float = 0.8
    var polyModToFreqA: Bool = false
    var polyModToPWA: Bool = false
    var polyModToFilter: Bool = false
    var lfoSaw: Bool = false
    var lfoTriangle: Bool = true
    var lfoSquare: Bool = false
    var lfoToOscA: Bool = true
    var lfoToOscB: Bool = false
    var lfoToPWA: Bool = false
    var lfoToPWB: Bool = false
    var lfoToFilter: Bool = false
    var oscASaw: Bool = true
    var oscAPulse: Bool = false
    var oscSync: Bool = false
    var oscBSaw: Bool = true
    var oscBTriangle: Bool = false
    var oscBPulse: Bool = false
    var oscBLowFreqMode: Bool = false
    var oscBKeyboardTrack: Bool = true
    var filterKeyboardTrack: Bool = true
    var releaseEnabled: Bool = true
    var unisonMode: Bool = false
    // Performance controls and commands are not part of a stored voice program.
    var modWheel: Float = 0
    var pitchWheel: Float = 0
    var referenceA440 = false
    var autoTuneTrigger: UInt32 = 0
}

struct Rev3Knob {
    let id: String
    let label: String
    let names: [String]
    let key: WritableKeyPath<SynthParameters, Float>
    let range: ClosedRange<Float>
    let curve: Int // 0 linear; 1 logarithmic; 2 quantized semitones
    var programmable: Bool { id != "masterTuneSemitones" && id != "masterVolume" }
    func clamped(_ value: Float) -> Float {
        let value = value.isFinite ? min(range.upperBound,max(range.lowerBound,value)) : range.lowerBound
        return curve == 2 ? value.rounded() : value
    }
    func normalized(_ p: SynthParameters) -> Double {
        let v=clamped(p[keyPath:key])
        return Double(curve == 1 ? log(v/range.lowerBound)/log(range.upperBound/range.lowerBound) : (v-range.lowerBound)/(range.upperBound-range.lowerBound))
    }
    func value(_ n: Double) -> Float {
        let v=Float(min(1,max(0,n)))
        return clamped(curve == 1 ? range.lowerBound*pow(range.upperBound/range.lowerBound,v) : range.lowerBound+v*(range.upperBound-range.lowerBound))
    }
}
struct Rev3Switch {
    let id: String
    let label: String
    let names: [String]
    let key: WritableKeyPath<SynthParameters, Bool>
}
struct Rev3Section {
    let title: String
    let knobs: [Int]
    let switches: [Int]
}
enum Rev3 {
    static let knobs: [Rev3Knob] = [
        .init(id:"polyModFilterEnv",label:"FILTER ENV",names:["Poly-Mod filter envelope","Poly-Mod フィルターEG","Poly-Mod 滤波包络"],key:\.polyModFilterEnv,range:0...1,curve:0),
        .init(id:"polyModOscB",label:"OSC B",names:["Poly-Mod oscillator B","Poly-Mod OSC B","Poly-Mod 振荡器B"],key:\.polyModOscB,range:0...1,curve:0),
        .init(id:"lfoRateHz",label:"FREQUENCY",names:["LFO frequency","LFO 周波数","LFO 频率"],key:\.lfoRateHz,range:0.04...20,curve:1),
        .init(id:"wheelSourceMix",label:"SOURCE MIX",names:["Wheel-Mod LFO / noise mix","Wheel-Mod LFO／ノイズ比率","Wheel-Mod LFO／噪声混合"],key:\.wheelSourceMix,range:0...1,curve:0),
        .init(id:"oscAFrequency",label:"FREQUENCY",names:["Oscillator A frequency","OSC A 周波数","振荡器A频率"],key:\.oscAFrequency,range:0...48,curve:2),
        .init(id:"oscAPulseWidth",label:"PULSE WIDTH",names:["Oscillator A pulse width","OSC A パルス幅","振荡器A脉宽"],key:\.oscAPulseWidth,range:0.01...0.99,curve:0),
        .init(id:"oscBFrequency",label:"FREQUENCY",names:["Oscillator B frequency","OSC B 周波数","振荡器B频率"],key:\.oscBFrequency,range:0...48,curve:2),
        .init(id:"oscBFineCents",label:"FINE",names:["Oscillator B fine tuning","OSC B 微調整","振荡器B微调"],key:\.oscBFineCents,range:0...100,curve:0),
        .init(id:"oscBPulseWidth",label:"PULSE WIDTH",names:["Oscillator B pulse width","OSC B パルス幅","振荡器B脉宽"],key:\.oscBPulseWidth,range:0.01...0.99,curve:0),
        .init(id:"oscALevel",label:"OSC A",names:["Oscillator A level","OSC A レベル","振荡器A电平"],key:\.oscALevel,range:0...1,curve:0),
        .init(id:"oscBLevel",label:"OSC B",names:["Oscillator B level","OSC B レベル","振荡器B电平"],key:\.oscBLevel,range:0...1,curve:0),
        .init(id:"noiseLevel",label:"NOISE",names:["White noise level","ホワイトノイズ","白噪声电平"],key:\.noiseLevel,range:0...1,curve:0),
        .init(id:"cutoffNorm",label:"CUTOFF",names:["Filter cutoff","フィルター カットオフ","滤波器截止频率"],key:\.cutoffNorm,range:0...1,curve:0),
        .init(id:"resonance",label:"RESONANCE",names:["Filter resonance","フィルター レゾナンス","滤波器共振"],key:\.resonance,range:0...1,curve:0),
        .init(id:"filterEnvAmount",label:"ENV AMOUNT",names:["Filter envelope amount","フィルターEG量","滤波包络深度"],key:\.filterEnvAmount,range:0...1,curve:0),
        .init(id:"envAAttack",label:"ATTACK",names:["Filter attack","フィルター アタック","滤波器起音"],key:\.envAAttack,range:0.001...30,curve:1),
        .init(id:"envADecay",label:"DECAY",names:["Filter decay","フィルター ディケイ","滤波器衰减"],key:\.envADecay,range:0.001...30,curve:1),
        .init(id:"envASustain",label:"SUSTAIN",names:["Filter sustain","フィルター サステイン","滤波器持续"],key:\.envASustain,range:0...1,curve:0),
        .init(id:"envARelease",label:"RELEASE",names:["Filter release","フィルター リリース","滤波器释音"],key:\.envARelease,range:0.001...30,curve:1),
        .init(id:"envBAttack",label:"ATTACK",names:["Amplifier attack","音量 アタック","音量起音"],key:\.envBAttack,range:0.001...30,curve:1),
        .init(id:"envBDecay",label:"DECAY",names:["Amplifier decay","音量 ディケイ","音量衰减"],key:\.envBDecay,range:0.001...30,curve:1),
        .init(id:"envBSustain",label:"SUSTAIN",names:["Amplifier sustain","音量 サステイン","音量持续"],key:\.envBSustain,range:0...1,curve:0),
        .init(id:"envBRelease",label:"RELEASE",names:["Amplifier release","音量 リリース","音量释音"],key:\.envBRelease,range:0.001...30,curve:1),
        .init(id:"glideTime",label:"GLIDE",names:["Unison glide","ユニゾン グライド","齐奏滑音"],key:\.glideTime,range:0...5,curve:0),
        .init(id:"masterTuneSemitones",label:"MASTER TUNE",names:["Master tune","マスターチューン","总调音"],key:\.masterTuneSemitones,range:-1...1,curve:0),
        .init(id:"masterVolume",label:"VOLUME",names:["Master volume","マスター音量","主音量"],key:\.masterVolume,range:0...1,curve:0),
    ]
    static let switches: [Rev3Switch] = [
        .init(id:"polyModToFreqA",label:"FREQ A",names:["Poly-Mod to oscillator A frequency","Poly-Mod → OSC A 周波数","Poly-Mod → A频率"],key:\.polyModToFreqA),
        .init(id:"polyModToPWA",label:"PW A",names:["Poly-Mod to oscillator A pulse width","Poly-Mod → OSC A パルス幅","Poly-Mod → A脉宽"],key:\.polyModToPWA),
        .init(id:"polyModToFilter",label:"FILTER",names:["Poly-Mod to filter","Poly-Mod → フィルター","Poly-Mod → 滤波器"],key:\.polyModToFilter),
        .init(id:"lfoSaw",label:"SAW",names:["LFO sawtooth","LFO ノコギリ波","LFO 锯齿波"],key:\.lfoSaw),
        .init(id:"lfoTriangle",label:"TRIANGLE",names:["LFO triangle","LFO 三角波","LFO 三角波"],key:\.lfoTriangle),
        .init(id:"lfoSquare",label:"SQUARE",names:["LFO square","LFO 矩形波","LFO 方波"],key:\.lfoSquare),
        .init(id:"lfoToOscA",label:"FREQ A",names:["Wheel-Mod to oscillator A frequency","Wheel-Mod → OSC A 周波数","Wheel-Mod → A频率"],key:\.lfoToOscA),
        .init(id:"lfoToOscB",label:"FREQ B",names:["Wheel-Mod to oscillator B frequency","Wheel-Mod → OSC B 周波数","Wheel-Mod → B频率"],key:\.lfoToOscB),
        .init(id:"lfoToPWA",label:"PW A",names:["Wheel-Mod to oscillator A pulse width","Wheel-Mod → OSC A パルス幅","Wheel-Mod → A脉宽"],key:\.lfoToPWA),
        .init(id:"lfoToPWB",label:"PW B",names:["Wheel-Mod to oscillator B pulse width","Wheel-Mod → OSC B パルス幅","Wheel-Mod → B脉宽"],key:\.lfoToPWB),
        .init(id:"lfoToFilter",label:"FILTER",names:["Wheel-Mod to filter","Wheel-Mod → フィルター","Wheel-Mod → 滤波器"],key:\.lfoToFilter),
        .init(id:"oscASaw",label:"SAW",names:["Oscillator A sawtooth","OSC A ノコギリ波","振荡器A锯齿波"],key:\.oscASaw),
        .init(id:"oscAPulse",label:"PULSE",names:["Oscillator A pulse","OSC A パルス波","振荡器A脉冲波"],key:\.oscAPulse),
        .init(id:"oscSync",label:"SYNC",names:["Oscillator sync B to A","OSC 同期 B → A","振荡器同步 B → A"],key:\.oscSync),
        .init(id:"oscBSaw",label:"SAW",names:["Oscillator B sawtooth","OSC B ノコギリ波","振荡器B锯齿波"],key:\.oscBSaw),
        .init(id:"oscBTriangle",label:"TRIANGLE",names:["Oscillator B triangle","OSC B 三角波","振荡器B三角波"],key:\.oscBTriangle),
        .init(id:"oscBPulse",label:"PULSE",names:["Oscillator B pulse","OSC B パルス波","振荡器B脉冲波"],key:\.oscBPulse),
        .init(id:"oscBLowFreqMode",label:"LO FREQ",names:["Oscillator B low frequency","OSC B 低周波モード","振荡器B低频模式"],key:\.oscBLowFreqMode),
        .init(id:"oscBKeyboardTrack",label:"KEYBOARD",names:["Oscillator B keyboard tracking","OSC B キーボード追従","振荡器B键盘跟踪"],key:\.oscBKeyboardTrack),
        .init(id:"filterKeyboardTrack",label:"KEYBOARD",names:["Filter keyboard tracking","フィルター キーボード追従","滤波器键盘跟踪"],key:\.filterKeyboardTrack),
        .init(id:"releaseEnabled",label:"RELEASE",names:["Enable envelope release","EGリリース有効","启用包络释音"],key:\.releaseEnabled),
        .init(id:"unisonMode",label:"UNISON",names:["Unison lowest-note priority","ユニゾン 最低音優先","齐奏最低音优先"],key:\.unisonMode),
    ]
    static let sections: [Rev3Section] = [
        .init(title:"POLY-MOD",knobs:[0,1],switches:[0,1,2]),
        .init(title:"LFO",knobs:[2],switches:[3,4,5]),
        .init(title:"WHEEL-MOD",knobs:[3],switches:[6,7,8,9,10]),
        .init(title:"OSCILLATOR A",knobs:[4,5],switches:[11,12,13]),
        .init(title:"OSCILLATOR B",knobs:[6,7,8],switches:[14,15,16,17,18]),
        .init(title:"MIXER",knobs:[9,10,11],switches:[]),
        .init(title:"FILTER",knobs:[12,13,14],switches:[19]),
        .init(title:"FILTER ENVELOPE",knobs:[15,16,17,18],switches:[]),
        .init(title:"AMPLIFIER",knobs:[19,20,21,22],switches:[]),
        .init(title:"PERFORMANCE",knobs:[23,24,25],switches:[20,21])
    ]
}

// A program contains exactly the 46 voice settings. Wheels, volume, tuning and
// A-440 remain live when recalling it, just as on the original instrument.
struct Rev3Program: Codable, Equatable {
    let version: Int
    var pots: [String: Float]
    var switches: [String: Bool]
    init(_ p: SynthParameters) {
        version=1
        pots=Dictionary(uniqueKeysWithValues:Rev3.knobs.filter(\.programmable).map { ($0.id,$0.clamped(p[keyPath:$0.key])) })
        switches=Dictionary(uniqueKeysWithValues:Rev3.switches.map { ($0.id,p[keyPath:$0.key]) })
    }
    func applying(to current: SynthParameters) -> SynthParameters? {
        guard version == 1, Set(pots.keys) == Set(Rev3.knobs.filter(\.programmable).map(\.id)),
              Set(switches.keys) == Set(Rev3.switches.map(\.id)), pots.values.allSatisfy(\.isFinite) else { return nil }
        var result=current
        for item in Rev3.knobs where item.programmable { result[keyPath:item.key]=item.clamped(pots[item.id]!) }
        for item in Rev3.switches { result[keyPath:item.key]=switches[item.id]! }
        return result
    }
}

extension Rev3Program {
    // Read-only migration. The original A/B data remains untouched until the user
    // records a separate Rev3 program. Unsupported voices cannot be lossless.
    static func migratingLegacy(_ data: Data) -> Rev3Program? {
        guard let old=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],
              old["cutoff"] is NSNumber,old["oscAWave"] is NSNumber else { return nil }
        var p=SynthParameters()
        let names=["cutoffNorm":"cutoff","oscBFineCents":"oscBFine","oscAPulseWidth":"pwmA","oscBPulseWidth":"pwmB","envAAttack":"envAA","envADecay":"envAD","envASustain":"envAS","envARelease":"envAR","envBAttack":"envBA","envBDecay":"envBD","envBSustain":"envBS","envBRelease":"envBR","lfoRateHz":"lfoRate"]
        for item in Rev3.knobs where item.programmable {
            if let v=old[names[item.id] ?? item.id] as? NSNumber { p[keyPath:item.key]=item.clamped(v.floatValue) }
        }
        for item in Rev3.switches {
            if let v=old[item.id] as? Bool { p[keyPath:item.key]=v }
        }
        let a=(old["oscAWave"] as? Int) ?? 0,b=(old["oscBWave"] as? Int) ?? 0,lfo=(old["lfoWave"] as? Int) ?? 0
        p.oscASaw=a != 2; p.oscAPulse=a == 2
        p.oscBSaw=b == 0; p.oscBTriangle=b == 1; p.oscBPulse=b == 2
        p.lfoTriangle=lfo == 0; p.lfoSaw=lfo == 1; p.lfoSquare=lfo == 2
        p.wheelSourceMix=lfo == 3 ? 1:0
        if (old["glideOn"] as? Bool) == false { p.glideTime=0 }
        return Rev3Program(p)
    }
}
