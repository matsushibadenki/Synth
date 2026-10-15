// Reference-led instrument: cyan / acid yellow enamel, spun aluminium, black rack chassis.
import MetalKit
import simd

struct PanelLayout {
    let columns: Int
    static func columns(for width: CGFloat) -> Int { width >= 900 ? 3 : (width >= 600 ? 2 : 1) }
    var rows: Int { (Rev3.sections.count+columns-1)/columns }
    var width: Float { Float(columns)*6.6+0.3 }
    func rowHeight(_ row: Int) -> Float {
        let count=Rev3.sections[(row*columns)..<min((row+1)*columns,Rev3.sections.count)].map { $0.switches.count }.max() ?? 0
        return count > 3 ? 3.75 : (count > 0 ? 3.05 : 2.65)
    }
    var height: Float { (0..<rows).reduce(0) { $0+rowHeight($1) }+(columns == 3 ? 0.3:2.2) }
    func bankTop(_ bank: Int) -> Float { height/2-0.15-(0..<(bank/columns)).reduce(0) { $0+rowHeight($1) } }
    var scale: Float { height*0.5+0.16 }
    var aspect: Float { (width*0.5+0.2)/scale }
    func bankCenter(_ bank: Int) -> SIMD3<Float> {
        SIMD3(-width/2+3.45+Float(bank%columns)*6.6,bankTop(bank)-rowHeight(bank/columns)/2,0.05)
    }
    func title(_ section: Int) -> SIMD3<Float> { SIMD3(bankCenter(section).x,bankTop(section)-0.35,0.09) }
    func knob(_ index: Int) -> SIMD3<Float> {
        let section=Rev3.sections.firstIndex { $0.knobs.contains(index) }!
        let ids=Rev3.sections[section].knobs
        let slot=ids.firstIndex(of:index)!
        return SIMD3(bankCenter(section).x+(Float(slot)-Float(ids.count-1)/2)*1.5,bankTop(section)-1.46,0.3)
    }
    func toggle(_ index: Int) -> SIMD3<Float> {
        let section=Rev3.sections.firstIndex { $0.switches.contains(index) }!
        let ids=Rev3.sections[section].switches
        let slot=ids.firstIndex(of:index)!
        let count=min(3,ids.count-slot/3*3)
        return SIMD3(bankCenter(section).x+(Float(slot%3)-Float(count-1)/2)*1.7,bankTop(section)-2.55-Float(slot/3)*0.7,0.16)
    }
    func wheel(_ index: Int, value: Float=0.5) -> SIMD3<Float> {
        SIMD3(keyboardLeft+0.5+Float(index)*1.1,keyY+(value-0.5)*0.9,0.17)
    }
    func point(_ p: SIMD3<Float>) -> CGPoint {
        // Orthographic front view with a slight elevation keeps every control aligned.
        CGPoint(x:CGFloat(0.5+p.x/(scale*aspect)*0.5),y:CGFloat(0.5-(p.y*0.98+p.z*0.2)/scale*0.5))
    }
    var whiteNotes: [Int] { [60,62,64,65,67,69,71,72] }
    var blackNotes: [(note: Int, slot: Int)] { [(61,0),(63,1),(66,3),(68,4),(70,5)] }
    var keyboardLeft: Float { -width/2+(columns == 3 ? 6.85:0.15) }
    var keyY: Float { columns == 3 ? bankCenter(9).y-0.2 : -height/2+0.85 }
    var keyboardWidth: Float { width-(columns == 3 ? 9.35:2.65) }
    var keyWidth: Float { keyboardWidth/8 }
    func keyX(_ index: Int) -> Float { keyboardLeft+2.25+(Float(index)+0.5)*keyWidth }
}

private enum PanelMaterial {
    static let chassis = SIMD4<Float>(0.012,0.016,0.019,0)
    static let cyan = SIMD4<Float>(0.045,0.47,0.53,0)
    static let lime = SIMD4<Float>(0.53,0.56,0.055,0)
    static let ink = SIMD4<Float>(0.008,0.016,0.017,0)
    static let silver = SIMD4<Float>(0.63,0.66,0.65,1)
    static let rubber = SIMD4<Float>(0.015,0.019,0.022,2)
    static let ivory = SIMD4<Float>(0.78,0.8,0.72,0)
    static let light = SIMD4<Float>(0.8,0.015,0.008,3)
}

private struct PanelVertex {
    var position: SIMD4<Float>
    var normal: SIMD4<Float>
    var color: SIMD4<Float>
    var local: SIMD4<Float>
}

private struct PanelMesh {
    var vertices = [PanelVertex]()
    mutating func triangle(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, normal: SIMD3<Float>, color: SIMD4<Float>, origin: SIMD3<Float> = .zero) {
        for p in [a,b,c] { vertices.append(PanelVertex(position: SIMD4(p,1), normal: SIMD4(normal,0), color: color, local: SIMD4(p-origin,0))) }
    }
    // Extruded rounded rectangle with a narrow bevel around the top enamel face.
    mutating func plate(_ c: SIMD3<Float>, size: SIMD2<Float>, radius: Float, depth: Float, color: SIMD4<Float>) {
        var rim = [SIMD3<Float>]()
        for corner in 0..<4 {
            let angle = Float(corner) * .pi / 2
            let center = SIMD3<Float>(corner == 0 || corner == 3 ? size.x/2-radius : -size.x/2+radius,
                                      corner < 2 ? size.y/2-radius : -size.y/2+radius, 0)
            for j in 0...8 {
                let a = angle + Float(j) / 8 * .pi/2
                rim.append(c + center + SIMD3(cos(a)*radius, sin(a)*radius, 0))
            }
        }
        for i in rim.indices {
            let next = (i+1)%rim.count
            let a = rim[i], b = rim[next]
            let edge = b-a
            let n = simd_normalize(SIMD3(edge.y,-edge.x,0))
            let topA = a + SIMD3(-n.x*0.025,-n.y*0.025,depth)
            let topB = b + SIMD3(-n.x*0.025,-n.y*0.025,depth)
            triangle(c+SIMD3(0,0,depth),topA,topB,normal:[0,0,1],color:color,origin:c)
            triangle(a,b,topB,normal:simd_normalize(n+SIMD3(0,0,0.6)),color:color,origin:c)
            triangle(a,topB,topA,normal:simd_normalize(n+SIMD3(0,0,0.6)),color:color,origin:c)
        }
    }
    // Surface of revolution: tapered skirt, chamfer and spun metal cap.
    mutating func lathe(_ c: SIMD3<Float>, profile: [(Float,Float)], color: SIMD4<Float>, segments: Int = 64) {
        for ring in 0..<profile.count-1 {
            let (r0,z0) = profile[ring], (r1,z1) = profile[ring+1]
            for i in 0..<segments {
                let a = Float(i)/Float(segments)*2 * .pi, b = Float(i+1)/Float(segments)*2 * .pi
                let p0 = c+SIMD3(cos(a)*r0,sin(a)*r0,z0), p1 = c+SIMD3(cos(b)*r0,sin(b)*r0,z0)
                let p2 = c+SIMD3(cos(b)*r1,sin(b)*r1,z1), p3 = c+SIMD3(cos(a)*r1,sin(a)*r1,z1)
                let normal = simd_normalize(SIMD3(cos((a+b)/2)*(z1-z0),sin((a+b)/2)*(z1-z0),r0-r1))
                triangle(p0,p1,p2,normal:normal,color:color,origin:c)
                triangle(p0,p2,p3,normal:normal,color:color,origin:c)
            }
        }
    }
    mutating func line(_ a: SIMD3<Float>, _ b: SIMD3<Float>, width: Float, color: SIMD4<Float>) {
        let delta = b-a
        let side = simd_normalize(SIMD3(-delta.y,delta.x,0))*width/2
        triangle(a-side,b-side,b+side,normal:[0,0,1],color:color)
        triangle(a-side,b+side,a+side,normal:[0,0,1],color:color)
    }
}

final class MetalPanelRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let sampleCount: Int
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private var vertexBuffer: MTLBuffer?
    private var vertexCount = 0
    private var lastValues = [Double]()
    private var lastNotes = Set<Int>()
    private var lastSwitches = [Bool]()
    private var layout = PanelLayout(columns: 2)

    init(device: MTLDevice) throws {
        self.device = device
        sampleCount = device.supportsTextureSampleCount(4) ? 4 : 1
        guard let queue = device.makeCommandQueue() else { throw RenderError.unavailable }
        self.queue = queue
        let library = try device.makeLibrary(source: Self.shader, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.rasterSampleCount = sampleCount
        descriptor.vertexFunction = library.makeFunction(name: "panelVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "panelFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.depthAttachmentPixelFormat = .depth32Float
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        let depth = MTLDepthStencilDescriptor()
        depth.depthCompareFunction = .less
        depth.isDepthWriteEnabled = true
        guard let state = device.makeDepthStencilState(descriptor: depth) else { throw RenderError.unavailable }
        depthState = state
        super.init()
    }
    enum RenderError: Error { case unavailable }

    // 26 physical knobs (24 stored + tune/volume), two wheels, 22 stored switches.
    func update(layout: PanelLayout, values: [Double], activeNotes: Set<Int>, switches: [Bool]) {
        guard values.count == 28, switches.count == 22 else { return }
        guard vertexBuffer == nil || self.layout.columns != layout.columns || lastValues != values || lastNotes != activeNotes || lastSwitches != switches else { return }
        self.layout=layout; lastValues=values; lastNotes=activeNotes; lastSwitches=switches
        let v=values.map { Float($0.isFinite ? min(1,max(0,$0)) : 0) }
        var mesh=PanelMesh()
        mesh.plate([0,0,-0.18],size:[layout.width,layout.height],radius:0.12,depth:0.18,color:PanelMaterial.chassis)
        for bank in Rev3.sections.indices {
            let c=layout.bankCenter(bank)
            mesh.plate([c.x,c.y,0.012],size:[6.48,layout.rowHeight(bank/layout.columns)-0.14],radius:0.16,depth:0.055,color:bank%3 == 1 ? PanelMaterial.lime : PanelMaterial.cyan)
            for dx: Float in [-3.1,3.1] {
                for dy in [-layout.rowHeight(bank/layout.columns)/2+0.2,layout.rowHeight(bank/layout.columns)/2-0.2] {
                    let screw=SIMD3<Float>(c.x+dx,c.y+dy,0.08)
                    mesh.lathe(screw,profile:[(0.07,0),(0.065,0.045),(0,0.055)],color:PanelMaterial.rubber,segments:24)
                    mesh.line(screw+SIMD3(-0.04,0,0.057),screw+SIMD3(0.04,0,0.057),width:0.014,color:PanelMaterial.silver)
                }
            }
        }
        for i in Rev3.knobs.indices {
            let c=layout.knob(i)
            mesh.lathe([c.x,c.y,0.07],profile:[(0.44,0),(0.44,0.03),(0.4,0.045),(0,0.045)],color:PanelMaterial.ink)
            mesh.lathe([c.x,c.y,0.09],profile:[(0.39,0),(0.36,0.18),(0.31,0.24),(0,0.24)],color:PanelMaterial.rubber)
            mesh.lathe([c.x,c.y,0.33],profile:[(0.245,0),(0.225,0.025),(0,0.03)],color:PanelMaterial.silver)
            for tick in 0...10 {
                let a = -Float.pi*0.75-Float(tick)/10 * .pi*1.5
                let n=SIMD3<Float>(cos(a),sin(a),0)
                mesh.line([c.x,c.y,0.075]+n*0.47,[c.x,c.y,0.075]+n*(tick%5==0 ? 0.59:0.54),width:0.012,color:PanelMaterial.ink)
            }
            let a = -Float.pi*0.75-v[i] * .pi*1.5
            let n=SIMD3<Float>(cos(a),sin(a),0)
            mesh.line([c.x,c.y,0.367]+n*0.26,[c.x,c.y,0.367]+n*0.36,width:0.032,color:PanelMaterial.ivory)
        }
        for index in Rev3.switches.indices {
            let c=layout.toggle(index)
            mesh.plate([c.x,c.y,0.075],size:[0.58,0.24],radius:0.08,depth:0.015,color:PanelMaterial.ink)
            mesh.plate([c.x,c.y,0.09],size:[0.44,0.18],radius:0.045,depth:switches[index] ? 0.025:0.07,color:PanelMaterial.rubber)
            mesh.lathe([c.x+0.38,c.y,0.08],profile:[(0.055,0),(0.045,0.025),(0,0.03)],color:switches[index] ? PanelMaterial.light : PanelMaterial.ink,segments:24)
        }
        for index in 0..<2 {
            let w=layout.wheel(index)
            mesh.plate([w.x,w.y,0.075],size:[0.16,1.25],radius:0.065,depth:0.01,color:PanelMaterial.silver)
            mesh.plate([w.x,w.y,0.09],size:[0.1,1.2],radius:0.04,depth:0.01,color:PanelMaterial.ink)
            let handle=layout.wheel(index,value:v[26+index])
            mesh.plate([handle.x,handle.y,0.13],size:[0.58,0.25],radius:0.08,depth:0.09,color:PanelMaterial.rubber)
            mesh.line([handle.x-0.2,handle.y,0.225],[handle.x+0.2,handle.y,0.225],width:0.015,color:PanelMaterial.silver)
        }
        for (i,note) in layout.whiteNotes.enumerated() {
            let z: Float=activeNotes.contains(note) ? 0.025 : 0.07
            mesh.plate([layout.keyX(i),layout.keyY,z],size:[layout.keyWidth-0.025,1.0],radius:0.045,depth:0.09,color:activeNotes.contains(note) ? PanelMaterial.cyan : PanelMaterial.ivory)
        }
        for item in layout.blackNotes {
            let z: Float=activeNotes.contains(item.note) ? 0.14 : 0.2
            mesh.plate([layout.keyX(item.slot)+layout.keyWidth/2,layout.keyY+0.19,z],size:[layout.keyWidth*0.56,0.63],radius:0.04,depth:0.1,color:PanelMaterial.rubber)
        }
        vertexCount=mesh.vertices.count
        vertexBuffer=mesh.vertices.withUnsafeBytes { device.makeBuffer(bytes:$0.baseAddress!,length:$0.count,options:.storageModeShared) }
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        guard let drawable=view.currentDrawable,let pass=view.currentRenderPassDescriptor,let buffer=vertexBuffer,
              let command=queue.makeCommandBuffer(),let encoder=command.makeRenderCommandEncoder(descriptor:pass) else { return }
        encode(encoder,buffer:buffer); encoder.endEncoding(); command.present(drawable); command.commit()
    }
    private func encode(_ encoder: MTLRenderCommandEncoder, buffer: MTLBuffer) {
        encoder.setRenderPipelineState(pipeline); encoder.setDepthStencilState(depthState)
        encoder.setVertexBuffer(buffer,offset:0,index:0)
        var projection=SIMD4<Float>(layout.scale*layout.aspect,layout.scale,layout.height,0)
        encoder.setVertexBytes(&projection,length:MemoryLayout<SIMD4<Float>>.stride,index:1)
        let centers=(0..<26).map { SIMD4<Float>(layout.knob($0),0) }
        centers.withUnsafeBytes { encoder.setFragmentBytes($0.baseAddress!,length:$0.count,index:0) }
        encoder.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:vertexCount)
    }

    // Also used by the GPU regression check; does not need a window or audio device.
    func preview(width: Int, height: Int) throws -> CGImage {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor), let buffer = vertexBuffer,
              let command = queue.makeCommandBuffer() else { throw RenderError.unavailable }
        let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: width, height: height, mipmapped: false)
        depthDescriptor.sampleCount = sampleCount
        if sampleCount > 1 { depthDescriptor.textureType = .type2DMultisample }
        depthDescriptor.usage = [.renderTarget]
        depthDescriptor.storageMode = .private
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        if sampleCount > 1 {
            let multisample = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
            multisample.textureType = .type2DMultisample
            multisample.sampleCount = sampleCount
            multisample.storageMode = .private
            multisample.usage = .renderTarget
            guard let target = device.makeTexture(descriptor: multisample) else { throw RenderError.unavailable }
            pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].resolveTexture = texture
            pass.colorAttachments[0].storeAction = .multisampleResolve
        }
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0.006, green: 0.008, blue: 0.01, alpha: 1)
        pass.depthAttachment.texture = device.makeTexture(descriptor: depthDescriptor)
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { throw RenderError.unavailable }
        encode(encoder, buffer: buffer)
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        if let error = command.error { throw error }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { texture.getBytes($0.baseAddress!, bytesPerRow: width*4, from: MTLRegionMake2D(0,0,width,height), mipmapLevel: 0) }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width*4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue).union(.byteOrder32Little),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { throw RenderError.unavailable }
        return image
    }

    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;
    struct Vertex { float4 position; float4 normal; float4 color; float4 local; };
    struct Out { float4 position [[position]]; float3 world; float3 normal; float4 color; float3 local; };
    vertex Out panelVertex(uint id [[vertex_id]], constant Vertex *v [[buffer(0)]], constant float4 &p [[buffer(1)]]) {
        Out o; float3 w=v[id].position.xyz; float perspective=1;
        o.position=float4(w.x/p.x,(w.y*0.98+w.z*0.2)/p.y,(0.5-(w.z*0.98-w.y*0.2)/(p.z+2))*perspective,perspective);
        o.world=w; o.normal=v[id].normal.xyz; o.color=v[id].color; o.local=v[id].local.xyz; return o;
    }
    fragment float4 panelFragment(Out in [[stage_in]],constant float4 *knobs [[buffer(0)]]) {
        float3 n=normalize(in.normal), light=normalize(float3(-0.5,0.7,1.3));
        float diffuse=max(dot(n,light),0.0);
        float3 halfVector=normalize(light+float3(0,-0.2,0.98));
        float spec=pow(max(dot(n,halfVector),0.0),64.0)*0.035;
        float3 base=in.color.rgb;
        float angle=atan2(in.local.y,in.local.x);
        if(in.color.a>0.5 && in.color.a<1.5) {
            float radial=0.42+0.32*sin(angle*3+0.7)+0.18*cos(angle*6-1.2);
            float brushed=sin(length(in.local.xy)*2100)*0.025;
            base*=clamp(radial+brushed,0.12,1.2);
            spec+=pow(max(dot(n,halfVector),0.0),120.0)*0.22;
        }
        if(in.color.a>1.5 && in.color.a<2.5 && n.z<0.9) base*=0.8+0.2*cos(angle*40);
        float shade=1;
        if(in.world.z<0.085 && n.z>0.8) {
            for(int i=0;i<26;i++) {
                float2 d=in.world.xy-knobs[i].xy-float2(0.11,-0.13);
                shade*=mix(0.28,1.0,smoothstep(0.35,0.57,length(d)));
            }
        }
        float3 color=(base*(0.28+diffuse*0.7)+spec)*shade;
        if(in.color.a>2.5) color=base+float3(0.12,0.015,0.005);
        return float4(pow(max(color,float3(0)),float3(1.0/2.2)),1);
    }
    """
}
