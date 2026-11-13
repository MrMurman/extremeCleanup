import AppKit
import ImageIO
import SpriteKit

final class EmberBlowerCrack: BlowerCrackVisual {
    let node = SKNode()

    private let big: Bool
    private let from: CGFloat
    private let span: CGFloat
    private let to: CGFloat
    private let revealMask: SKShapeNode
    private let lightLayer = SKNode()
    private let cracks: [SKSpriteNode]
    private let glows: [SKSpriteNode]
    private var didBurst = false
    private var isPulsing = false

    private static let sparkTexture: SKTexture = {
        let context = CGContext(data: nil, width: 12, height: 12,
                                bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(gray: 1, alpha: 1)
        context.fillEllipse(in: CGRect(x: 3, y: 3, width: 6, height: 6))
        return SKTexture(cgImage: context.makeImage()!)
    }()

    init(site: DamageModel.Site, big: Bool, from: CGFloat, to: CGFloat) {
        self.big = big
        self.from = from
        self.to = to
        span = max(to - from, 0.001)

        let random = Self.random(seed: site.id)
        let side: CGFloat = 460
        let size = CGSize(width: side, height: side)
        var cracks: [SKSpriteNode] = []
        var glows: [SKSpriteNode] = []

        let firstLevel = big ? 2 : 1
        for level in firstLevel...(firstLevel + 1) {
            let glow = SKSpriteNode(color: .clear, size: size)
            glow.blendMode = .add
            glow.zPosition = 0
            glow.alpha = 0
            glows.append(glow)
            lightLayer.addChild(glow)

            let crack = SKSpriteNode(color: .clear, size: size)
            crack.blendMode = .add
            crack.color = NSColor(calibratedRed: 1, green: 0.12, blue: 0.22, alpha: 1)
            crack.colorBlendFactor = 0.82
            crack.zPosition = 1
            crack.alpha = 0
            cracks.append(crack)
            lightLayer.addChild(crack)

            Self.loadArt(named: "lvl\(level)-impact.png") { crackTexture, glowTexture in
                crack.texture = crackTexture
                glow.texture = glowTexture
            }
        }
        self.cracks = cracks
        self.glows = glows

        let mask = SKShapeNode(circleOfRadius: side / 2)
        mask.fillColor = .white
        mask.strokeColor = .clear
        mask.lineWidth = 0
        revealMask = mask
        let crop = SKCropNode()
        crop.maskNode = mask
        crop.addChild(lightLayer)
        crop.zPosition = 1

        node.position = site.centre
        node.zRotation = CGFloat((random >> 8) % 6_283) / 1_000
        node.xScale = random & (1 << 24) == 0 ? 1 : -1
        node.yScale = random & (1 << 25) == 0 ? 1 : -1
        node.addChild(crop)
        setReach(from)
    }

    func setReach(_ reach: CGFloat) {
        let progress = min(1, max(0, (reach - from) / span))
        let reveal = 0.3 + progress * 0.7
        let visibleReach = to * reveal / 230
        revealMask.setScale(visibleReach)

        let transitionProgress = min(1, max(0, (progress - 0.45) / 0.55))
        let blend = transitionProgress * transitionProgress * (3 - 2 * transitionProgress)
        let stage = big ? 1 : 0
        let crackStrength: [CGFloat] = [0.7, 0.86, 1]
        let glowStrength: [CGFloat] = [0.28, 0.5, 0.78]
        cracks[0].alpha = (1 - blend) * crackStrength[stage]
        cracks[1].alpha = blend * crackStrength[stage + 1]
        glows[0].alpha = (1 - blend) * glowStrength[stage]
        glows[1].alpha = blend * glowStrength[stage + 1]

        if big && blend > 0 {
            startPulse()
        }
    }

    func burst() {
        guard !didBurst else { return }
        didBurst = true
        let count = big ? 12 : 7
        let sparks = SKEmitterNode()
        sparks.particleTexture = Self.sparkTexture
        sparks.numParticlesToEmit = count
        sparks.particleBirthRate = CGFloat(count) / 0.08
        sparks.particleLifetime = 0.55
        sparks.particleLifetimeRange = 0.2
        sparks.particleSpeed = big ? 170 : 110
        sparks.particleSpeedRange = 65
        sparks.emissionAngleRange = 2 * .pi
        sparks.particleAlpha = 0.95
        sparks.particleAlphaSpeed = -1.8
        sparks.particleScale = 0.55
        sparks.particleScaleRange = 0.25
        sparks.particleScaleSpeed = -0.35
        sparks.particleColor = NSColor(calibratedRed: 1, green: 0.09, blue: 0.2, alpha: 1)
        sparks.particleColorBlendFactor = 1
        sparks.particleBlendMode = .add
        sparks.zPosition = 2
        node.addChild(sparks)
        sparks.run(.sequence([.wait(forDuration: 1), .removeFromParent()]))
    }

    private func startPulse() {
        guard !isPulsing else { return }
        isPulsing = true
        let low = SKAction.fadeAlpha(to: 0.68, duration: 0.5)
        let high = SKAction.fadeAlpha(to: 1, duration: 0.5)
        low.timingMode = .easeInEaseOut
        high.timingMode = .easeInEaseOut
        lightLayer.run(.repeatForever(.sequence([low, high])))
    }

    private static func random(seed: Int) -> UInt64 {
        var value = UInt64(truncatingIfNeeded: seed) &* 0x9E37_79B9_7F4A_7C15
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    private static func loadArt(named name: String,
                                completion: @escaping (SKTexture, SKTexture) -> Void) {
        let crackName = name.replacingOccurrences(of: ".png", with: "-ember.png")
        let glowName = name.replacingOccurrences(of: ".png", with: "-glow.png")
        DispatchQueue.global(qos: .userInitiated).async {
            guard let url = Bundle.main.url(forResource: crackName, withExtension: nil, subdirectory: "assets"),
                  let glowURL = Bundle.main.url(forResource: glowName, withExtension: nil, subdirectory: "assets"),
                  let crackSource = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let glowSource = CGImageSourceCreateWithURL(glowURL as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(crackSource, 0, nil),
                  let glowImage = CGImageSourceCreateImageAtIndex(glowSource, 0, nil) else {
                return
            }
            let crack = SKTexture(cgImage: image)
            let glow = SKTexture(cgImage: glowImage)
            crack.filteringMode = .linear
            glow.filteringMode = .linear
            SKTexture.preload([crack, glow]) {
                DispatchQueue.main.async {
                    completion(crack, glow)
                }
            }
        }
    }
}
