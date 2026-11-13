import AppKit
import CoreImage
import QuartzCore
import SpriteKit

/// Which look the blower's crack uses. `code` is the original Slice A drawing; the texture
/// styles are runtime-selectable A2 experiments.
enum BlowerCrackStyle: String, CaseIterable {
    case code
    case texture
    case texturePlain
    case textureEmber
    case textureFracture

    var label: String {
        switch self {
        case .code: return "code"
        case .texture: return "texture"
        case .texturePlain: return "texture, plain"
        case .textureEmber: return "texture, ember"
        case .textureFracture: return "texture, fracture"
        }
    }
}

/// The look of one blower-cracked site. The scene owns the timing and calls `setReach` as the
/// crack grows; the visual owns everything that is drawn.
protocol BlowerCrackVisual: AnyObject {
    var node: SKNode { get }
    /// The crack's current reach in points, 0...230 — the same value Slice A drew with.
    func setReach(_ reach: CGFloat)
    /// Called once when the crack appears; the texture look uses it for the opening spark burst.
    func burst()
}

/// Slice A's look, kept as the baseline for comparisons: radial code-drawn paths plus a two-layer
/// additive glow.
final class DrawnBlowerCrack: BlowerCrackVisual {
    let node = SKNode()
    private let centre: CGPoint
    private let big: Bool
    private let seed: Int
    private let rays: ClosedRange<CGFloat>
    private let shapes: [SKShapeNode]

    init(site: DamageModel.Site, big: Bool, from: CGFloat, rays: ClosedRange<CGFloat>) {
        centre = site.centre
        self.big = big
        seed = site.id
        self.rays = rays

        let glow = SKNode()
        let layers: [(width: CGFloat, color: NSColor)] = [
            (big ? 18 : 10, NSColor(red: 1, green: 0.38, blue: 0.08, alpha: big ? 0.22 : 0.12)),
            (big ? 3 : 2.2, NSColor(red: 1, green: 0.62, blue: 0.25, alpha: big ? 0.8 : 0.45)),
        ]
        var shapes: [SKShapeNode] = []
        for (width, color) in layers {
            let light = SKShapeNode()
            light.strokeColor = color
            light.lineWidth = width
            light.lineCap = .round
            light.lineJoin = .round
            light.blendMode = .add
            glow.addChild(light)
            shapes.append(light)
        }
        let low = SKAction.fadeAlpha(to: 0.55, duration: big ? 0.6 : 0.9)
        let high = SKAction.fadeAlpha(to: 1, duration: big ? 0.6 : 0.9)
        low.timingMode = .easeInEaseOut
        high.timingMode = .easeInEaseOut
        glow.run(.repeatForever(.sequence([low, high])))
        node.addChild(glow)

        let shadow = SKShapeNode()
        shadow.strokeColor = NSColor(white: 0, alpha: 0.45)
        shadow.lineWidth = big ? 2.6 : 2
        shadow.position = CGPoint(x: 0.6, y: -0.6)
        node.addChild(shadow)
        shapes.append(shadow)

        let glint = SKShapeNode()
        glint.strokeColor = NSColor(white: 1, alpha: 0.85)
        glint.lineWidth = big ? 1.1 : 0.9
        node.addChild(glint)
        shapes.append(glint)

        self.shapes = shapes
        setReach(from)
    }

    func setReach(_ reach: CGFloat) {
        let path = CrackArt.cracks(around: centre, reach: reach, rings: big, seed: seed, rays: rays)
        for shape in shapes { shape.path = path }
    }

    func burst() {}
}

/// The A2 look: one of the generated crack textures, scaled from small to big with a feathered
/// outer edge, plus a pre-blurred additive glow and optional sparks. Texture work happens once,
/// in `prepare()`.
enum BlowerCrackArt {
    static let maxReach: CGFloat = 230
    static let size: CGFloat = 460

    struct Variant {
        let texture: SKTexture
        let glow: SKTexture
        let alpha: CGFloat
    }

    private static var variants: [Variant] = []
    private static var dotTexture: SKTexture?
    private static let ciContext = CIContext()
    private static var prepared = false
    private(set) static var isAvailable = false

    /// Loads the four crack PNGs, feathers their outer edge, and builds the blurred glow copies.
    /// Safe to call repeatedly; the first call does the work.
    static func prepare() {
        guard !prepared else { return }
        prepared = true
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("assets") else { return }
        let names = ["thin-fissure", "lvl1-impact", "lvl2-impact", "lvl3-impact"]
        var built: [Variant] = []
        for name in names {
            guard let image = NSImage(contentsOf: dir.appendingPathComponent(name + ".png")),
                  let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let soft = feathered(cg),
                  let glowImage = blurred(soft, side: 512, radius: 6)
            else { continue }
            let texture = SKTexture(cgImage: soft)
            texture.filteringMode = .linear
            let glow = SKTexture(cgImage: glowImage)
            glow.filteringMode = .linear
            built.append(Variant(texture: texture, glow: glow, alpha: name == "lvl3-impact" ? 1 : 0.92))
        }
        variants = built
        isAvailable = built.count >= 2
        dotTexture = makeDot()
        let all = built.flatMap { [$0.texture, $0.glow] } + [dotTexture].compactMap { $0 }
        Task { await SKTexture.preload(all) }
    }

    /// Draws each crack variant once at almost-zero opacity, then removes it: the first blower
    /// crack should not pay for the texture upload and the first draw.
    static func prewarm(in scene: SKScene) {
        prepare()
        guard isAvailable else { return }
        let site = DamageModel.Site(id: -1, centre: CGPoint(x: 1, y: 1), damage: 1)
        for variant in variants {
            let visual = TextureBlowerCrack(site: site, big: false, from: 1, to: 70, variant: variant,
                                            glow: true, sparks: false)
            visual.node.alpha = 0.001
            visual.node.zPosition = 1_000
            scene.addChild(visual.node)
            visual.node.run(.sequence([.wait(forDuration: 0.5), .removeFromParent()]))
        }
    }

    static var dot: SKTexture {
        prepare()
        return dotTexture ?? SKTexture()
    }

    static func make(style: BlowerCrackStyle, site: DamageModel.Site, big: Bool,
                     from: CGFloat, to: CGFloat, rays: ClosedRange<CGFloat>) -> BlowerCrackVisual {
        if style == .textureFracture {
            return FractureBlowerCrack(site: site, big: big, from: from, to: to)
        }
        if style == .textureEmber {
            return EmberBlowerCrack(site: site, big: big, from: from, to: to)
        }
        if style != .code {
            prepare()
            if isAvailable, let variant = variant(seed: site.id) {
                return TextureBlowerCrack(site: site, big: big, from: from, to: to, variant: variant,
                                          glow: style == .texture, sparks: style == .texture)
            }
        }
        return DrawnBlowerCrack(site: site, big: big, from: from, rays: rays)
    }

    private static func variant(seed: Int) -> Variant? {
        guard !variants.isEmpty else { return nil }
        // Keep the same texture for both stages of one site, so the big crack grows out of the
        // small one instead of swapping shape. `thin-fissure` is a single line, not an impact.
        let pool = [1, 2, 3]
        let valid = pool.filter { $0 < variants.count }
        guard !valid.isEmpty else { return variants[0] }
        var rng = SeededRandom(seed: seed &+ 7)
        let index = valid[Int(rng.range(0...CGFloat(valid.count - 1)))]
        return variants[min(index, variants.count - 1)]
    }

    private static func blurred(_ image: CGImage, side: Int, radius: Double) -> CGImage? {
        let input = CIImage(cgImage: image)
        let scale = CGFloat(side) / max(CGFloat(image.width), CGFloat(image.height))
        let scaled = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let extent = CGRect(x: 0, y: 0, width: side, height: side)
        let output = scaled.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: extent)
        return ciContext.createCGImage(output, from: extent)
    }

    /// Fades the art's own outer edge. The crack grows by scaling this whole texture, so the
    /// rays end in a soft fade instead of being cut by a circular crop mask.
    private static func feathered(_ image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(image, in: bounds)
        context.setBlendMode(.destinationIn)
        let centre = CGPoint(x: bounds.midX, y: bounds.midY)
        let colors = [
            CGColor(red: 1, green: 1, blue: 1, alpha: 1),
            CGColor(red: 1, green: 1, blue: 1, alpha: 1),
            CGColor(red: 1, green: 1, blue: 1, alpha: 0),
        ] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors,
                                        locations: [0, 0.72, 1]) else { return nil }
        context.drawRadialGradient(gradient, startCenter: centre, startRadius: 0,
                                   endCenter: centre, endRadius: CGFloat(max(width, height)) / 2, options: [])
        return context.makeImage()
    }

    private static func makeDot() -> SKTexture? {
        let side = 12
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fillEllipse(in: CGRect(x: 2, y: 2, width: side - 4, height: side - 4))
        guard let image = context.makeImage() else { return nil }
        return SKTexture(cgImage: image)
    }
}

/// A crack built from one of the generated textures. The whole feathered crack scales from the
/// small stage to the big one, so the rays keep their natural ends and no circular mask is drawn.
private final class TextureBlowerCrack: BlowerCrackVisual {
    let node = SKNode()
    private let content = SKNode()
    private let spark: SKEmitterNode?
    private let targetReach: CGFloat
    private var burstUntil: TimeInterval = 0

    init(site: DamageModel.Site, big: Bool, from: CGFloat, to: CGFloat, variant: BlowerCrackArt.Variant,
         glow: Bool, sparks: Bool) {
        node.position = site.centre
        targetReach = to
        var rng = SeededRandom(seed: site.id &+ 4_242)
        let rotation = rng.range(0...(2 * .pi))
        let mirror: CGFloat = rng.range(0...1) < 0.5 ? -1 : 1
        let side = BlowerCrackArt.size

        let shadow = SKSpriteNode(texture: variant.glow, size: CGSize(width: side, height: side))
        shadow.color = NSColor(red: 0.16, green: 0.01, blue: 0.03, alpha: 1)
        shadow.colorBlendFactor = 1
        shadow.alpha = 0.38
        shadow.position = CGPoint(x: 1.4, y: -1.4)
        shadow.zRotation = rotation
        shadow.xScale = mirror
        shadow.zPosition = -2
        content.addChild(shadow)

        if glow {
            let light = SKNode()
            // Banner palette: crimson glass, a magenta fringe, red-orange heat, gold, then a
            // white-hot impact core.
            let layers: [(side: CGFloat, color: NSColor, alpha: CGFloat)] = [
                (side, NSColor(red: 1, green: 0.02, blue: 0.10, alpha: 1), big ? 0.60 : 0.48),
                (side * 0.92, NSColor(red: 1, green: 0.03, blue: 0.42, alpha: 1), big ? 0.38 : 0.30),
                (side * 0.74, NSColor(red: 1, green: 0.24, blue: 0.04, alpha: 1), big ? 0.52 : 0.44),
                (side * 0.50, NSColor(red: 1, green: 0.62, blue: 0.16, alpha: 1), big ? 0.55 : 0.48),
                (side * 0.26, NSColor(red: 1, green: 0.94, blue: 0.78, alpha: 1), big ? 0.62 : 0.54),
            ]
            for layer in layers {
                let sprite = SKSpriteNode(texture: variant.glow, size: CGSize(width: layer.side, height: layer.side))
                sprite.color = layer.color
                sprite.colorBlendFactor = 1
                sprite.alpha = layer.alpha
                sprite.blendMode = .add
                sprite.zRotation = rotation
                sprite.xScale = mirror
                light.addChild(sprite)
            }
            light.zPosition = -1
            let low = SKAction.fadeAlpha(to: 0.55, duration: big ? 0.6 : 0.9)
            let high = SKAction.fadeAlpha(to: 1, duration: big ? 0.6 : 0.9)
            low.timingMode = .easeInEaseOut
            high.timingMode = .easeInEaseOut
            light.run(.repeatForever(.sequence([low, high])))
            content.addChild(light)
        }

        // The same crack is layered three times: crimson rays, then gold, then a white-hot core.
        // Smaller copies keep the outer rays red, like the banner's glass, instead of white.
        let crackLayers: [(side: CGFloat, color: NSColor, alpha: CGFloat, z: CGFloat)] = [
            (side, NSColor(red: 1, green: 0.06, blue: 0.10, alpha: 1), variant.alpha * 0.95, 0),
            (side * 0.66, NSColor(red: 1, green: 0.58, blue: 0.14, alpha: 1), 0.62, 1),
            (side * 0.36, NSColor(red: 1, green: 0.95, blue: 0.78, alpha: 1), 0.72, 2),
        ]
        for layer in crackLayers {
            let crack = SKSpriteNode(texture: variant.texture,
                                     size: CGSize(width: layer.side, height: layer.side))
            crack.color = layer.color
            crack.colorBlendFactor = 1
            crack.alpha = layer.alpha
            crack.blendMode = .add
            crack.zRotation = rotation
            crack.xScale = mirror
            crack.zPosition = layer.z
            content.addChild(crack)
        }

        node.addChild(content)

        if sparks {
            let emitter = SKEmitterNode()
            emitter.particleTexture = BlowerCrackArt.dot
            emitter.particleBirthRate = 0
            emitter.particleLifetime = 0.55
            emitter.particleLifetimeRange = 0.3
            emitter.particleSpeed = 190
            emitter.particleSpeedRange = 130
            emitter.emissionAngleRange = 2 * .pi
            emitter.particlePositionRange = CGVector(dx: 30, dy: 30)
            emitter.yAcceleration = -320
            emitter.particleAlpha = 0.9
            emitter.particleAlphaSpeed = -1.5
            emitter.particleScale = 0.16
            emitter.particleScaleRange = 0.1
            emitter.particleColor = NSColor(red: 1, green: 0.78, blue: 0.35, alpha: 1)
            emitter.particleColorSequence = SKKeyframeSequence(
                keyframeValues: [NSColor(red: 1, green: 0.92, blue: 0.58, alpha: 1),
                                 NSColor(red: 0.95, green: 0.18, blue: 0.05, alpha: 1)],
                times: [0, 1])
            emitter.particleColorBlendFactor = 1
            emitter.particleBlendMode = .add
            emitter.zPosition = 0.2
            node.addChild(emitter)
            self.spark = emitter
        } else {
            self.spark = nil
        }

        setReach(from)
    }

    func setReach(_ reach: CGFloat) {
        let k = max(0.02, min(1, reach / BlowerCrackArt.maxReach))
        content.xScale = k
        content.yScale = k
        guard let spark else { return }
        spark.particlePositionRange = CGVector(dx: max(20, reach * 1.2), dy: max(20, reach * 1.2))
        if CACurrentMediaTime() < burstUntil { return }
        spark.particleBirthRate = reach < targetReach - 0.5 ? 22 : 0
    }

    func burst() {
        guard let spark else { return }
        spark.particleBirthRate = 650
        spark.resetSimulation()
        burstUntil = CACurrentMediaTime() + 0.12
    }
}
