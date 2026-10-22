import Foundation

/// Fixed-capacity stereo storage; allocated before the render callback starts.
final class FXStereoLine {
    private var samples: [SIMD2<Float>]
    private var cursor = 0
    init(capacity: Int) { samples=Array(repeating:.zero,count:max(8,capacity)) }
    func read(_ delay: Float) -> SIMD2<Float> {
        let d=min(Float(samples.count-3),max(1,delay))
        var position=Float(cursor)-d
        if position < 0 { position += Float(samples.count) }
        if position >= Float(samples.count) { position=0 }
        let index=Int(position), fraction=position-Float(index)
        return samples[index]*(1-fraction)+samples[(index+1)%samples.count]*fraction
    }
    func write(_ value: SIMD2<Float>) { samples[cursor]=value; cursor=(cursor+1)%samples.count }
}

final class FXProcessor {
    let kind: EffectKind
    let sr: Float
    private let delay: FXStereoLine
    private let pitch: FXStereoLine
    private let predelay: FXStereoLine
    private var tanks: [FXStereoLine] = []
    private var tankTimes=Array(repeating:Float(0),count:8)
    private var tankGains=Array(repeating:Float(0),count:8)
    private var tankFilters=Array(repeating:SIMD2<Float>.zero,count:8)
    private var target=SIMD8<Float>(repeating:0)
    private var smooth=SIMD8<Float>(repeating:0)
    private var phase: Float=0, carrier: Float=0, pitchPhase: Float=0, reversePhase: Float=0
    private var filtered=SIMD2<Float>.zero
    private var previous=SIMD2<Float>.zero
    private var damping: Float=0.2, wetGain: Float=0, envelope: Float=0
    private var settings: FXSettings
    private var initialized=false
    private var delaySamples: Float=1
    private var loop: [SIMD2<Float>] = []
    private var loopPosition: Float=0, loopLength=0, lastLoopSerial: UInt32=0
    private(set) var loopState=0
    var loopSeconds: Float { Float(loopLength)/sr }

    init(kind: EffectKind,sampleRate: Float) {
        self.kind=kind; sr=sampleRate; settings=FXSettings(kind)
        delay=FXStereoLine(capacity:Int(sampleRate*(kind == .pedal ? 4.2:2.2))+8)
        pitch=FXStereoLine(capacity:Int(sampleRate*0.12)+8)
        predelay=FXStereoLine(capacity:Int(sampleRate*0.21)+8)
        if kind == .sky { tanks=(0..<8).map { _ in FXStereoLine(capacity:Int(sampleRate*0.25)+8) } }
        if kind == .pedal { loop=Array(repeating:.zero,count:Int(sampleRate*12)) }
    }
    func configure(_ next: FXSettings) {
        if kind == .pedal, next.loopSerial != lastLoopSerial {
            lastLoopSerial=next.loopSerial
            switch next.loopAction {
            case 1:
                if loopState == 1 { loopState=loopLength > 0 ? 2:0; loopPosition=0 }
                else if loopState == 2 { loopState=3 }
                else if loopState == 3 { loopState=2 }
                else { loopState=1; loopPosition=0; loopLength=0 }
            case 2: loopState=loopState == 2 || loopState == 3 ? 4:(loopLength > 0 ? 2:0)
            case 3: loopState=0; loopLength=0; loopPosition=0
            default: break
            }
        }
        guard !initialized || next != settings else { return }
        settings=next
        for index in next.values.indices { target[index]=next.values[index] }
        if !initialized { smooth=target; initialized=true; delaySamples=25*powf(80,target[0])*0.001*sr }
        damping=1-expf(-2 * .pi * (500+powf(target[2],2)*14000)/sr)
        if kind == .sky {
            let seconds=kind.controls[0].actual(target[0])
            let times=SIMD8<Float>(0.0297,0.0371,0.0411,0.0437,0.0531,0.0617,0.0719,0.0797)
            let scale: Float=next.mode == 1 ? 0.72:(next.mode >= 2 ? 1.8:1.2)
            for i in 0..<8 {
                tankTimes[i]=times[i]*scale*sr
                tankGains[i]=powf(0.001,times[i]*scale/seconds)
            }
        }
    }
    func process(_ dry: SIMD2<Float>) -> SIMD2<Float> {
        // Slew continuous parameters and bypass, including delay-time changes.
        smooth += (target-smooth)*min(1,1/(sr*0.02))
        wetGain += ((settings.enabled ? 1:0)-wetGain)*min(1,1/(sr*0.008))
        if wetGain < 0.00001 && !settings.enabled { return dry }
        let wet: SIMD2<Float>
        switch kind {
        case .dimension: wet=modulation(dry,studio:false)
        case .sky: wet=reverb(dry)
        case .time: wet=echo(dry,mode:settings.mode)
        case .pedal: wet=settings.mode == 3 ? looper(dry):echo(dry,mode:settings.mode == 2 ? 4:settings.mode)
        case .ring: wet=ring(dry)
        case .studio: wet=settings.mode == 2 ? echo(dry,mode:3,studio:true):modulation(dry,studio:true)
        default: return dry
        }
        let mix=smooth[4]*wetGain
        return dry*(1-mix)+wet*mix
    }
    private func modulation(_ input: SIMD2<Float>,studio: Bool) -> SIMD2<Float> {
        let rate=studio ? 0.05*powf(100,smooth[0]):0.03*powf(5/0.03,smooth[0])
        phase += rate/sr; phase -= floorf(phase)
        let a=sinf(2 * .pi * phase), b=sinf(2 * .pi * phase + .pi*0.5)
        let dimension=studio ? settings.mode == 0:settings.mode == 0
        let base: Float=dimension ? 8+smooth[2]*18:(studio ? 0.7+smooth[2]*9:0.3+smooth[2]*11.7)
        let width: Float=dimension ? 7: min(base*0.9,5)
        let l=delay.read((base+width*smooth[1]*a)*0.001*sr)
        let r=delay.read((base+width*smooth[1]*b)*0.001*sr)
        var result=SIMD2(l.x,r.y)
        if dimension {
            let second=delay.read((base-width*smooth[1]*b)*0.001*sr)
            result=(result+SIMD2(second.y,-second.x))*0.5
        }
        if studio { filtered += (result-filtered)*damping; result=filtered }
        let feedback: Float=dimension ? smooth[3]*0.2:(studio ? smooth[3]*0.92:smooth[3]*0.92*(settings.mode == 2 ? -1:1))
        let sample=input+result*feedback
        delay.write(SIMD2(tanhf(sample.x),tanhf(sample.y)))
        return result
    }
    private func echo(_ input: SIMD2<Float>,mode: Int,studio: Bool=false) -> SIMD2<Float> {
        let normalized=smooth[0]
        let milliseconds: Float=25*powf(80,normalized)
        let desired=milliseconds*0.001*sr
        delaySamples += (desired-delaySamples)*min(1,1/(sr*0.05))
        let modulation=studio ? smooth[1]:smooth[3]
        phase += (0.15+modulation*1.4)/sr; phase -= floorf(phase)
        let wow=sinf(phase*2 * .pi)*modulation*(mode == 1 ? 0.004:0.0008)*sr
        var wet=delay.read(delaySamples+wow)
        if mode == 4 {
            // Two overlapping reverse grains avoid a discontinuity at wrap.
            reversePhase += 1/max(32,delaySamples); reversePhase -= floorf(reversePhase)
            let q=reversePhase < 0.5 ? reversePhase+0.5:reversePhase-0.5
            let w=0.5-0.5*cosf(reversePhase*2 * .pi)
            wet=delay.read(1+reversePhase*delaySamples*2)*w+delay.read(1+q*delaySamples*2)*(1-w)
        }
        let coefficient=mode == 2 ? min(damping,0.12):damping
        filtered += (wet-filtered)*coefficient
        wet=filtered
        let feedback=studio ? smooth[3]*0.92:smooth[1]*0.94
        let returned=mode == 3 ? SIMD2(wet.y,wet.x):wet
        var feed=input+returned*feedback
        if mode == 1 || mode == 2 { feed=SIMD2(tanhf(feed.x*1.2),tanhf(feed.y*1.2))/1.2 }
        // Alternate the injected channels for a true stereo ping-pong echo.
        if mode == 3 { feed=SIMD2((input.x+input.y)*0.5+returned.x*feedback,returned.y*feedback) }
        delay.write(feed)
        if studio {
            let level=max(abs(input.x),abs(input.y))
            envelope += (level-envelope)*min(1,1/(sr*(level > envelope ? 0.005:0.25)))
            wet /= 1+envelope*12
        }
        return wet
    }
    private func reverb(_ input: SIMD2<Float>) -> SIMD2<Float> {
        let pre=predelay.read(max(1,smooth[1]*0.2*sr)); predelay.write(input)
        phase += 0.17/sr; phase -= floorf(phase)
        var reads=SIMD8<Float>(repeating:0), sum: Float=0
        for i in 0..<8 {
            let modulation=sinf(phase*2 * .pi+Float(i))*smooth[3]*sr*0.0007
            let value=tanks[i].read(tankTimes[i]+modulation)
            tankFilters[i] += (value-tankFilters[i])*damping
            reads[i]=tankFilters[i].x
            sum += reads[i]
        }
        // Orthogonal Householder FDN, eight unequal delays and damping.
        let shimmer: Float
        if settings.mode == 3 {
            pitch.write(previous)
            pitchPhase += 1/(sr*0.06); pitchPhase -= floorf(pitchPhase)
            let q=pitchPhase < 0.5 ? pitchPhase+0.5:pitchPhase-0.5
            let w=0.5-0.5*cosf(pitchPhase*2 * .pi)
            let shifted=pitch.read(1+(1-pitchPhase)*sr*0.06)*w+pitch.read(1+(1-q)*sr*0.06)*(1-w)
            shimmer=(shifted.x+shifted.y)*0.08
        } else { shimmer=0 }
        for i in 0..<8 {
            let reflected=reads[i]-sum*0.25
            let injection=(i%2 == 0 ? pre.x:pre.y)*0.5*(i%4 < 2 ? 1:-1)+shimmer
            let sample=tanhf(injection+reflected*tankGains[i])
            tanks[i].write(SIMD2(repeating:sample))
        }
        var wet=SIMD2((reads[0]+reads[2]-reads[4]+reads[6])*0.5,(reads[1]-reads[3]+reads[5]+reads[7])*0.5)
        if settings.mode == 2 { wet=(wet+previous)*0.5 }
        previous=wet
        return wet
    }
    private func ring(_ input: SIMD2<Float>) -> SIMD2<Float> {
        phase += 0.1*powf(250,smooth[1])/sr; phase -= floorf(phase)
        let lfo=settings.mode%2 == 0 ? sinf(phase*2 * .pi):1-4*abs(phase-0.5)
        let low=settings.mode < 2
        let frequency=(low ? 0.6*powf(80/0.6,smooth[0]):30*powf(4000/30,smooth[0]))*powf(2,lfo*smooth[2]*2)
        carrier += min(sr*0.4,frequency)/sr; carrier -= floorf(carrier)
        let drive=1+smooth[3]*7
        let signal=SIMD2(tanhf(input.x*drive),tanhf(input.y*drive))/tanhf(drive)
        return signal*sinf(carrier*2 * .pi)
    }
    private func looper(_ input: SIMD2<Float>) -> SIMD2<Float> {
        if loopState == 1 {
            loop[loopLength]=input; loopLength += 1
            if loopLength == loop.count { loopState=2; loopPosition=0 }
            return input
        }
        guard loopLength > 0, loopState == 2 || loopState == 3 else { return .zero }
        let index=min(loopLength-1,max(0,Int(loopPosition)))
        let next=(index+1)%loopLength, fraction=loopPosition-Float(index)
        let sample=loop[index]*(1-fraction)+loop[next]*fraction
        if loopState == 3 { loop[index]=loop[index]*0.98+input*0.6 }
        let speed: Float=settings.halfSpeed ? 0.5:1
        loopPosition += settings.reverse ? -speed:speed
        if loopPosition < 0 { loopPosition += Float(loopLength) }
        if loopPosition >= Float(loopLength) { loopPosition -= Float(loopLength) }
        return sample
    }
}

/// Audio thread owns processor state. UI supplies only validated small snapshots.
final class EffectsRackDSP {
    private var configuration=try! FXDocument.initial.configuration()
    private var processors: [FXProcessor?]
    private var values=Array(repeating:SIMD2<Float>.zero,count:9)
    private var previous=SIMD2<Float>.zero
    private var transition: Float=1
    private let sampleRate: Float
    init(sampleRate: Float) {
        self.sampleRate=sampleRate
        processors=EffectKind.allCases.map { (1...6).contains($0.rawValue) ? FXProcessor(kind:$0,sampleRate:sampleRate):nil }
    }
    func prepare(_ next: FXRenderConfiguration) {
        if configuration.steps != next.steps { transition=0 }
        configuration=next
        for i in 1...6 { processors[i]?.configure(next.settings[i]) }
    }
    func process(_ input: SIMD2<Float>) -> SIMD2<Float> {
        values[0]=input
        for step in configuration.steps {
            let a=step.a >= 0 ? values[step.a]:.zero
            if step.id == 7 {
                let b=step.b >= 0 ? values[step.b]:.zero
                let settings=configuration.settings[7]
                values[7]=a*settings.values[0]+b*settings.values[1]
            } else if step.id == 8 { values[8]=a }
            else { values[step.id]=processors[step.id]!.process(a) }
        }
        let output=values[8]
        transition=min(1,transition+1/(sampleRate*0.01))
        let result=previous*(1-transition)+output*transition
        if transition == 1 { previous=output }
        return SIMD2(result.x.isFinite ? min(1,max(-1,result.x)):0,result.y.isFinite ? min(1,max(-1,result.y)):0)
    }
    var loopState: Int { processors[4]?.loopState ?? 0 }
    var loopSeconds: Float { processors[4]?.loopSeconds ?? 0 }
}
