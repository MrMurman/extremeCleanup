import SpriteKit

/// What lies behind the glass, in layers that shift with the viewer's gaze: a far backdrop with a deep red glow,
/// distant tumbling debris, drifting fog, things that swim in it, wisps of mist just behind the glass, and
/// spores floating up. It sits in screen
/// space, so every hole looks into the same continuous void.
final class TheVoid: SKNode {
    /// Creatures swim between the fog and the glass.
    let creatureLayer = SKNode()

    private let deep: SKSpriteNode
    private let debris = SKNode()
    private let fog: SKSpriteNode
    private let mist: SKSpriteNode
    private let spores = SKEmitterNode()
    private let size: CGSize
    /// How far each layer shifts, in points, when the gaze moves from the centre to a screen edge.
    private let depth = (deep: CGFloat(40), debris: CGFloat(28), fog: CGFloat(14), spores: CGFloat(8), mist: CGFloat(4))
    private var drift: [(node: SKNode, velocity: CGVector, spin: CGFloat)] = []

    init(size: CGSize, dot: SKTexture) {
        self.size = size
        let margin = depth.deep
        let padded = CGSize(width: size.width + 2 * margin, height: size.height + 2 * margin)
        let sizeUniform = SKUniform(name: "u_size", vectorFloat2: vector_float2(Float(padded.width), Float(padded.height)))
        deep = SKSpriteNode(color: .black, size: padded)
        fog = SKSpriteNode(color: .black, size: padded)
        mist = SKSpriteNode(color: .black, size: padded)
        super.init()

        for (layer, source) in [(deep, TheVoid.deepSource), (fog, TheVoid.fogSource), (mist, TheVoid.mistSource)] {
            layer.anchorPoint = .zero
            layer.position = CGPoint(x: -margin, y: -margin)
            layer.shader = SKShader(source: TheVoid.noiseSource + source, uniforms: [sizeUniform])
        }
        deep.zPosition = 0
        debris.zPosition = 0.1
        fog.zPosition = 0.2
        creatureLayer.zPosition = 0.3
        mist.zPosition = 0.35
        spores.zPosition = 0.4
        [deep, debris, fog, creatureLayer, mist, spores].forEach(addChild)
        scatterDebris()

        spores.particleTexture = dot
        spores.particleBirthRate = size.width * size.height / 12_000
        spores.particleLifetime = 10
        spores.particleLifetimeRange = 4
        spores.particlePositionRange = CGVector(dx: size.width + 2 * margin, dy: size.height + 2 * margin)
        spores.position = CGPoint(x: size.width / 2, y: size.height / 2)
        spores.particleSpeed = 10
        spores.particleSpeedRange = 10
        spores.emissionAngle = .pi / 2
        spores.emissionAngleRange = 2 * .pi
        spores.yAcceleration = 3
        spores.particleScale = 0.22
        spores.particleScaleRange = 0.14
        spores.particleColor = NSColor(red: 0.78, green: 0.8, blue: 0.86, alpha: 1)
        spores.particleColorBlendFactor = 1
        spores.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [0, 0.55, 0] as [NSNumber],
                                                          times: [0, 0.5, 1])

        isHidden = true
        isPaused = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Starts rendering the void; until the first hole there is nothing to see, so it costs nothing.
    func open() {
        guard isHidden else { return }
        isHidden = false
        isPaused = false
        spores.advanceSimulationTime(10)
    }

    /// Shifts the layers for a gaze offset in -1...1 on each axis; deeper layers move further, the other way.
    func look(_ gaze: CGPoint) {
        func shift(_ amount: CGFloat) -> CGPoint { CGPoint(x: -gaze.x * amount, y: -gaze.y * amount) }
        let margin = depth.deep
        deep.position = shift(depth.deep) - CGPoint(x: margin, y: margin)
        fog.position = shift(depth.fog) - CGPoint(x: margin, y: margin)
        mist.position = shift(depth.mist) - CGPoint(x: margin, y: margin)
        debris.position = shift(depth.debris)
        creatureLayer.position = shift(depth.fog)
        spores.position = shift(depth.spores) + CGPoint(x: size.width / 2, y: size.height / 2)
    }

    func advance(by dt: TimeInterval) {
        guard !isHidden else { return }
        let dt = CGFloat(dt), margin: CGFloat = 60
        for item in drift {
            var p = item.node.position
            p.x += item.velocity.dx * dt
            p.y += item.velocity.dy * dt
            if p.x < -margin { p.x = size.width + margin } else if p.x > size.width + margin { p.x = -margin }
            if p.y < -margin { p.y = size.height + margin } else if p.y > size.height + margin { p.y = -margin }
            item.node.position = p
            item.node.zRotation += item.spin * dt
        }
    }

    /// Far-off fragments of other broken worlds, too distant to make out.
    private func scatterDebris() {
        var rng = SeededRandom(seed: 2_718)
        let count = Int(size.width * size.height / 70_000)
        for _ in 0..<count {
            let radius = rng.range(4...16)
            let corners = Int(rng.range(3...5.9))
            let shape = CGMutablePath()
            shape.addLines(between: (0..<corners).map { i in
                let angle = CGFloat(i) / CGFloat(corners) * 2 * .pi + rng.range(-0.4...0.4)
                let r = radius * rng.range(0.5...1)
                return CGPoint(x: cos(angle) * r, y: sin(angle) * r)
            })
            shape.closeSubpath()
            let piece = SKShapeNode(path: shape)
            piece.fillColor = NSColor(red: 0.07, green: 0.075, blue: 0.11, alpha: 0.9)
            piece.strokeColor = NSColor(red: 0.5, green: 0.08, blue: 0.08, alpha: 0.35)
            piece.lineWidth = 0.6
            piece.position = CGPoint(x: rng.range(0...size.width), y: rng.range(0...size.height))
            debris.addChild(piece)
            let heading = rng.range(0...(2 * .pi)), speed = rng.range(2...7)
            drift.append((piece, CGVector(dx: cos(heading) * speed, dy: sin(heading) * speed), rng.range(-0.3...0.3)))
        }
    }

    private static let noiseSource = """
    float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

    float noise(vec2 p) {
        vec2 i = floor(p);
        vec2 f = fract(p);
        vec2 u = f * f * (3.0 - 2.0 * f);
        return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
                   mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
    }

    float fbm(vec2 p) {
        float v = 0.0;
        float a = 0.5;
        for (int i = 0; i < 4; i++) {
            v += a * noise(p);
            p = p * 2.03 + vec2(1.7, 9.2);
            a *= 0.5;
        }
        return v;
    }

    """

    private static let deepSource = """
    void main() {
        vec2 pt = v_tex_coord * u_size;
        vec2 uv = pt / 420.0;
        float t = u_time * 0.02;
        float haze = fbm(uv + vec2(t, -t * 0.5));
        float glow = smoothstep(0.45, 0.85, fbm(uv * 0.6 - vec2(0.0, t)));
        vec3 col = vec3(0.01, 0.012, 0.03) + vec3(0.05, 0.06, 0.1) * haze;
        col += vec3(0.24, 0.025, 0.06) * glow * (0.6 + 0.4 * sin(u_time * 0.4));

        // Faint far specks, each twinkling at its own pace.
        vec2 cell = floor(pt / 9.0);
        float h = hash(cell);
        float dist = length(fract(pt / 9.0) - 0.5);
        float speck = step(0.994, h) * smoothstep(0.14, 0.0, dist) * (0.5 + 0.5 * sin(u_time * (0.6 + h * 2.0) + h * 40.0));
        col += vec3(0.55, 0.55, 0.65) * speck * 0.7;

        gl_FragColor = vec4(col, 1.0);
    }
    """

    /// Large, faster wisps close behind the glass; mostly clear, so everything deeper stays visible.
    private static let mistSource = """
    void main() {
        vec2 uv = v_tex_coord * u_size / vec2(420.0, 260.0);
        float t = u_time * 0.16;
        vec2 warp = vec2(fbm(uv * 0.7 + vec2(t * 0.5, 0.0)), fbm(uv * 0.7 + vec2(3.1, -t * 0.4)));
        float wisp = fbm(uv + 1.4 * warp + vec2(t, t * 0.25));
        float alpha = smoothstep(0.5, 0.82, wisp) * 0.5;
        vec3 col = mix(vec3(0.42, 0.46, 0.56), vec3(0.62, 0.66, 0.74), smoothstep(0.6, 0.9, wisp));
        gl_FragColor = vec4(col * alpha, alpha);
    }
    """

    private static let fogSource = """
    void main() {
        vec2 uv = v_tex_coord * u_size / 120.0;
        float t = u_time * 0.09;
        vec2 q = vec2(fbm(uv + vec2(0.0, t)), fbm(uv + vec2(5.2, 1.3) - t));
        float fog = fbm(uv + 1.8 * q + vec2(t * 0.6, -t * 0.3));

        vec3 col = mix(vec3(0.12, 0.15, 0.24), vec3(0.36, 0.4, 0.5), fog);
        float alpha = smoothstep(0.25, 0.8, fog);

        float pulse = 0.5 + 0.5 * sin(u_time * 1.3 + q.x * 6.0);
        float red = smoothstep(0.5, 0.9, fbm(uv * 0.5 + q * 0.8 - vec2(0.0, t * 0.4)));
        float redGlow = red * (0.35 + 0.65 * pulse * pulse);

        // Rare distant flashes, as if a storm is moving somewhere far behind.
        float flash = pow(max(0.0, sin(u_time * 0.7) * sin(u_time * 2.9 + 1.0)), 12.0);

        // Premultiplied: thin fog lets the deep layer show through.
        vec3 premul = col * alpha + vec3(0.6, 0.06, 0.04) * redGlow + vec3(0.5, 0.08, 0.06) * flash * (0.3 + red);
        gl_FragColor = vec4(premul, max(alpha, max(redGlow, flash) * 0.6));
    }
    """
}

private func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
private func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
