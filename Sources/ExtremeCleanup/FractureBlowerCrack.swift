import AppKit
import ImageIO
import SpriteKit

final class FractureBlowerCrack {
    let node = SKNode()

    private let big: Bool
    private let from: CGFloat
    private let span: CGFloat
    private let extensionGrowth: SKSpriteNode
    private let secondGrowth: SKSpriteNode
    private var thirdGrowth: SKSpriteNode?
    private let previousLight: SKSpriteNode
    private let nextLight: SKSpriteNode
    private var thirdLight: SKSpriteNode?
    private let pulseLayer = SKNode()
    private let centreLight: SKSpriteNode
    private var didBurst = false
    private var isPulsing = false

    private static let glassShaderSource = """
    void main() {
        vec4 tex = texture2D(u_texture, v_tex_coord);
        vec2 offset = v_tex_coord * 2.0 - vec2(1.0);
        float threshold = clamp(length(offset) / 1.2, 0.0, 1.0);
        float reveal = smoothstep(threshold - 0.02, threshold + 0.02, a_progress);
        reveal *= step(0.001, a_progress);
        if (a_progress >= 0.999) {
            reveal = 1.0;
        }
        float alpha = tex.a * reveal * 0.68;
        float detail = clamp(max(tex.r, max(tex.g, tex.b)), 0.0, 1.0);
        vec3 glass = mix(vec3(0.48, 0.58, 0.64), vec3(0.92, 0.96, 1.0), detail);
        gl_FragColor = vec4(glass * alpha, alpha);
    }
    """

    /// One shader for every glass layer: `a_progress` is set per sprite, so adding a crack never compiles a new one.
    private static let glassShader: SKShader = {
        let shader = SKShader(source: glassShaderSource)
        shader.attributes = [SKAttribute(name: "a_progress", type: .float)]
        return shader
    }()

    private static let centreTexture = makeRadialTexture(side: 96, spark: false)
    private static let sparkTexture = makeRadialTexture(side: 12, spark: true)

    /// Textures are loaded once at launch and then shared; a first crack must not decode or upload its art mid-take.
    private static let cacheLock = NSLock()
    private static var cache: [String: SKTexture] = [:]
    private static var didPrewarm = false

    init(site: DamageModel.Site, big: Bool, from: CGFloat, to: CGFloat) {
        self.big = big
        self.from = from
        span = max(to - from, 0.001)

        let random = Self.random(seed: site.id)
        let size = CGSize(width: 460, height: 460)

        let base = Self.makeGlass(size: size, progress: 1)
        node.addChild(base)
        Self.loadTexture(named: "lvl1-fracture-core.png") {
            base.texture = $0
            base.isHidden = false
        }

        let outer = Self.makeGlass(size: size, progress: 0)
        extensionGrowth = outer
        node.addChild(outer)
        Self.loadTexture(named: "lvl1-fracture-extension.png") {
            outer.texture = $0
            outer.isHidden = false
        }

        let second = Self.makeGlass(size: size, progress: 0)
        secondGrowth = second
        node.addChild(second)
        Self.loadTexture(named: "lvl2-fracture.png") {
            second.texture = $0
            second.isHidden = false
        }

        if big {
            let third = Self.makeGlass(size: size, progress: 0)
            thirdGrowth = third
            node.addChild(third)
            Self.loadTexture(named: "lvl3-fracture.png") {
                third.texture = $0
                third.isHidden = false
            }
        }

        let previousLight = Self.makeLight(size: size)
        let nextLight = Self.makeLight(size: size)
        self.previousLight = previousLight
        self.nextLight = nextLight
        previousLight.zPosition = 2
        nextLight.zPosition = 2
        pulseLayer.zPosition = 2
        node.addChild(previousLight)
        node.addChild(nextLight)
        node.addChild(pulseLayer)

        Self.loadTexture(named: "lvl1-fracture-core-glow.png") {
            previousLight.texture = $0
        }
        Self.loadTexture(named: "lvl2-fracture-glow.png") {
            nextLight.texture = $0
        }
        if big {
            let thirdLight = Self.makeLight(size: size)
            self.thirdLight = thirdLight
            pulseLayer.addChild(thirdLight)
            Self.loadTexture(named: "lvl3-fracture-glow.png") {
                thirdLight.texture = $0
            }
        }

        centreLight = SKSpriteNode(texture: Self.centreTexture,
                                   size: CGSize(width: big ? 44 : 54, height: big ? 44 : 54))
        centreLight.blendMode = .add
        centreLight.zPosition = 3
        node.addChild(centreLight)

        node.position = site.centre
        node.zRotation = CGFloat((random >> 8) % 6_283) / 1_000
        node.xScale = random & (1 << 24) == 0 ? 1 : -1
        node.yScale = random & (1 << 25) == 0 ? 1 : -1
        setReach(from)
    }

    func setReach(_ reach: CGFloat) {
        let progress = min(1, max(0, (reach - from) / span))

        if big {
            // TODO: Revisit the shared 1.1 s big-crack growth window.
            // Previous phases: 0.385 s outer growth, 0.385 s level 2, 0.33 s level 3.
            let extensionProgress = min(1, progress / 0.35)
            let secondProgress = min(1, max(0, (progress - 0.35) / 0.559))
            let thirdProgress = min(1, max(0, (progress - 0.91) / 0.09))
            let extensionBlend = extensionProgress * extensionProgress * (3 - 2 * extensionProgress)
            let secondBlend = secondProgress * secondProgress * (3 - 2 * secondProgress)
            let thirdBlend = thirdProgress * thirdProgress * (3 - 2 * thirdProgress)
            extensionGrowth.setValue(SKAttributeValue(float: Float(extensionBlend)), forAttribute: "a_progress")
            secondGrowth.setValue(SKAttributeValue(float: Float(secondBlend)), forAttribute: "a_progress")
            thirdGrowth?.setValue(SKAttributeValue(float: Float(thirdBlend)), forAttribute: "a_progress")
            previousLight.alpha = 1 - secondBlend
            nextLight.alpha = secondBlend * (1 - thirdBlend)
            thirdLight?.alpha = thirdBlend
            centreLight.alpha = 0.05 + thirdProgress * 0.03
            if thirdProgress > 0.05 {
                startPulse()
            }
        } else {
            extensionGrowth.setValue(SKAttributeValue(float: 0), forAttribute: "a_progress")
            secondGrowth.setValue(SKAttributeValue(float: 0), forAttribute: "a_progress")
            previousLight.alpha = 1
            nextLight.alpha = 0
            let centreFade = min(1, progress / 0.3)
            centreLight.alpha = 0.04 + (1 - centreFade) * 0.96
        }
    }

    func burst() {
        guard !didBurst else { return }
        didBurst = true

        let flash = SKSpriteNode(texture: Self.centreTexture,
                                 size: CGSize(width: big ? 48 : 62, height: big ? 48 : 62))
        flash.blendMode = .add
        flash.zPosition = 4
        flash.alpha = 0.8
        flash.setScale(0.7)
        node.addChild(flash)
        flash.run(.sequence([
            .group([.scale(to: 1.35, duration: 0.28), .fadeOut(withDuration: 0.28)]),
            .removeFromParent(),
        ]))

        let count = big ? 8 : 6
        let sparks = SKEmitterNode()
        sparks.particleTexture = Self.sparkTexture
        sparks.numParticlesToEmit = count
        sparks.particleBirthRate = CGFloat(count) / 0.08
        sparks.particleLifetime = 0.5
        sparks.particleLifetimeRange = 0.18
        sparks.particleSpeed = big ? 145 : 105
        sparks.particleSpeedRange = 55
        sparks.emissionAngleRange = 2 * .pi
        sparks.particleAlpha = 0.9
        sparks.particleAlphaSpeed = -1.9
        sparks.particleScale = 0.55
        sparks.particleScaleRange = 0.2
        sparks.particleScaleSpeed = -0.3
        sparks.particleColor = .white
        sparks.particleColorBlendFactor = 0
        sparks.particleBlendMode = .add
        sparks.zPosition = 4
        node.addChild(sparks)
        sparks.run(.sequence([.wait(forDuration: 1), .removeFromParent()]))
    }

    private func startPulse() {
        guard !isPulsing else { return }
        isPulsing = true
        let low = SKAction.fadeAlpha(to: 0.72, duration: 0.5)
        let high = SKAction.fadeAlpha(to: 1, duration: 0.5)
        low.timingMode = .easeInEaseOut
        high.timingMode = .easeInEaseOut
        pulseLayer.run(.repeatForever(.sequence([low, high])))
    }

    static func prepare(in view: SKView) {
        guard !didPrewarm else { return }
        didPrewarm = true

        let names = ["lvl1-fracture-core.png", "lvl1-fracture-extension.png", "lvl2-fracture.png", "lvl3-fracture.png",
                     "lvl1-fracture-core-glow.png", "lvl1-fracture-glow.png", "lvl2-fracture-glow.png",
                     "lvl3-fracture-glow.png"]
        for name in names { _ = loadTextureSynchronously(named: name) }

        // Render a real fracture at the size it uses, so the shared shader and every texture are warm.
        let size = CGSize(width: 460, height: 460)
        let scene = SKScene(size: size)
        scene.anchorPoint = .zero
        scene.scaleMode = .resizeFill
        let site = DamageModel.Site(id: 0, centre: CGPoint(x: size.width / 2, y: size.height / 2), damage: 3)
        let visual = FractureBlowerCrack(site: site, big: true, from: 0, to: 230)
        scene.addChild(visual.node)
        visual.burst()
        _ = view.texture(from: scene)
    }

    private static func cachedTexture(named name: String) -> SKTexture? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cache[name]
    }

    private static func store(_ texture: SKTexture, as name: String) {
        cacheLock.lock()
        cache[name] = texture
        cacheLock.unlock()
    }

    private static func loadTextureSynchronously(named name: String) -> SKTexture? {
        if let cached = cachedTexture(named: name) { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "assets"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .linear
        store(texture, as: name)
        return texture
    }

    private static func makeGlass(size: CGSize, progress: Float) -> SKSpriteNode {
        let sprite = SKSpriteNode(color: .clear, size: size)
        sprite.isHidden = true
        sprite.blendMode = .alpha
        sprite.zPosition = 1
        sprite.shader = glassShader
        sprite.setValue(SKAttributeValue(float: progress), forAttribute: "a_progress")
        return sprite
    }

    private static func makeLight(size: CGSize) -> SKSpriteNode {
        let sprite = SKSpriteNode(color: .clear, size: size)
        sprite.blendMode = .add
        sprite.alpha = 0
        return sprite
    }

    private static func makeRadialTexture(side: Int, spark: Bool) -> SKTexture {
        let context = CGContext(data: nil, width: side, height: side,
                                bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        if spark {
            context.setFillColor(CGColor(red: 1, green: 0.22, blue: 0.055, alpha: 1))
            context.fillEllipse(in: CGRect(x: 2, y: 2, width: side - 4, height: side - 4))
            return SKTexture(cgImage: context.makeImage()!)
        }
        let colors = [
            CGColor(red: 1, green: 1, blue: 0.92, alpha: 1),
            CGColor(red: 1, green: 0.68, blue: 0.12, alpha: 0.95),
            CGColor(red: 1, green: 0.08, blue: 0.015, alpha: 0.35),
            CGColor(red: 1, green: 0.02, blue: 0, alpha: 0),
        ] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: colors,
                                  locations: [0, 0.16, 0.48, 1])!
        let centre = CGPoint(x: side / 2, y: side / 2)
        context.drawRadialGradient(gradient, startCenter: centre, startRadius: 0,
                                   endCenter: centre, endRadius: CGFloat(side / 2), options: [])
        return SKTexture(cgImage: context.makeImage()!)
    }

    private static func random(seed: Int) -> UInt64 {
        var value = UInt64(truncatingIfNeeded: seed) &* 0x9E37_79B9_7F4A_7C15
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    private static func loadTexture(named name: String, completion: @escaping (SKTexture) -> Void) {
        if let cached = cachedTexture(named: name) {
            if Thread.isMainThread { completion(cached) } else { DispatchQueue.main.async { completion(cached) } }
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            if let cached = cachedTexture(named: name) {
                DispatchQueue.main.async { completion(cached) }
                return
            }
            guard let url = Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "assets"),
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                return
            }
            let texture = SKTexture(cgImage: image)
            texture.filteringMode = .linear
            store(texture, as: name)
            SKTexture.preload([texture]) {
                DispatchQueue.main.async {
                    completion(texture)
                }
            }
        }
    }
}
