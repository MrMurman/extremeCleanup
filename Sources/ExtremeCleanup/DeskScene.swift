import SpriteKit

final class DeskScene: SKScene {
    private let world = SKNode()
    /// The snapshot and its cracks, masked so that holes show what lies behind.
    private let surface = SKCropNode()
    private let crackLayer = SKNode()
    private let shardLayer = SKNode()
    private let debugLayer = SKNode()
    private let backdropTexture: SKTexture
    private let snapshot: CGImage

    private var damage = DamageModel()
    private var crackNodes: [Int: SKNode] = [:]
    private var holes: [CGPath] = []
    private let mask: CGContext
    private let maxShards = 250
    /// The hole mask is redrawn on every shatter, so it is kept at half resolution.
    private let maskScale: CGFloat = 0.5

    init(shot: ScreenShot, icons: [DesktopIcon]) {
        backdropTexture = DeskScene.texture(from: shot.image)
        snapshot = shot.image
        let size = shot.screen.frame.size
        mask = CGContext(data: nil, width: Int(size.width / 2), height: Int(size.height / 2), bitsPerComponent: 8,
                         bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        mask.setFillColor(gray: 1, alpha: 1)
        mask.fill(CGRect(x: 0, y: 0, width: mask.width, height: mask.height))
        super.init(size: size)
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = .black

        let backdrop = SKSpriteNode(texture: backdropTexture, size: size)
        backdrop.anchorPoint = .zero
        crackLayer.zPosition = 1
        shardLayer.zPosition = 2
        debugLayer.zPosition = 10
        surface.addChild(backdrop)
        surface.addChild(crackLayer)
        world.addChild(surface)
        world.addChild(shardLayer)
        addChild(world)

        // Floor and walls, open at the top, so debris piles up at the bottom of the screen.
        let bounds = CGMutablePath()
        bounds.move(to: CGPoint(x: 0, y: size.height * 3))
        bounds.addLine(to: .zero)
        bounds.addLine(to: CGPoint(x: size.width, y: 0))
        bounds.addLine(to: CGPoint(x: size.width, y: size.height * 3))
        physicsBody = SKPhysicsBody(edgeChainFrom: bounds)

        let origin = shot.screen.frame.origin
        for icon in icons where shot.screen.frame.intersects(icon.frame) {
            let outline = SKShapeNode(rect: icon.frame.offsetBy(dx: -origin.x, dy: -origin.y))
            outline.strokeColor = .systemPink
            outline.lineWidth = 2
            debugLayer.addChild(outline)
        }
        debugLayer.isHidden = true
        addChild(debugLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func toggleDebug() {
        debugLayer.isHidden.toggle()
        view?.showsFPS = !debugLayer.isHidden
        view?.showsNodeCount = !debugLayer.isHidden
    }

    // MARK: - Input

    override func mouseDown(with event: NSEvent) {
        hammer(at: event.location(in: self))
    }

    func hammer(at point: CGPoint) {
        SoundFX.shared.play(.thud)
        dust(at: point)
        apply(damage.hit(at: point, amount: 1), impact: point)
    }

    // MARK: - Damage rendering

    private func apply(_ result: DamageModel.HitResult, impact: CGPoint) {
        for id in result.merged { crackNodes.removeValue(forKey: id)?.removeFromParent() }
        let site = result.site
        switch site.stage {
        case .intact:
            break
        case .crack, .bigCrack:
            drawCracks(for: site)
            SoundFX.shared.play(.crack, volume: site.stage == .crack ? 0.6 : 1)
        case .shattered:
            if result.previousStage < .bigCrack { drawCracks(for: site, stage: .bigCrack) }
            let radius = min(55 + 14 * CGFloat(site.damage - 3), 170)
            shatter(around: site.centre, radius: radius, seed: site.id &* 31 &+ Int(site.damage * 10), impact: impact)
            SoundFX.shared.play(.shatter, volume: result.previousStage == .shattered ? 0.6 : 1)
            shake(strength: result.previousStage == .shattered ? 4 : 9)
        }
    }

    private func drawCracks(for site: DamageModel.Site, stage: DamageModel.Stage? = nil) {
        crackNodes.removeValue(forKey: site.id)?.removeFromParent()
        let big = (stage ?? site.stage) >= .bigCrack
        let path = CrackArt.cracks(around: site.centre, reach: big ? 75 : 34, rings: big, seed: site.id)
        let node = SKNode()
        let shadow = SKShapeNode(path: path)
        shadow.strokeColor = NSColor(white: 0, alpha: 0.45)
        shadow.lineWidth = big ? 2.6 : 2
        shadow.position = CGPoint(x: 0.6, y: -0.6)
        let glint = SKShapeNode(path: path)
        glint.strokeColor = NSColor(white: 1, alpha: 0.85)
        glint.lineWidth = big ? 1.1 : 0.9
        node.addChild(shadow)
        node.addChild(glint)
        crackLayer.addChild(node)
        crackNodes[site.id] = node
    }

    private func shatter(around centre: CGPoint, radius: CGFloat, seed: Int, impact: CGPoint) {
        let polygon = CrackArt.hole(around: centre, radius: radius, seed: seed)
        let outline = CGMutablePath()
        outline.addLines(between: polygon)
        outline.closeSubpath()

        for triangle in CrackArt.shards(of: polygon, centre: centre, seed: seed) {
            let centroid = CGPoint(x: triangle.map(\.x).reduce(0, +) / 3, y: triangle.map(\.y).reduce(0, +) / 3)
            // Glass that is already gone can't break again.
            guard !holes.contains(where: { $0.contains(centroid) }) else { continue }
            spawnShard(triangle, centroid: centroid, impact: impact)
        }

        holes.append(outline)
        mask.setBlendMode(.clear)
        var scale = CGAffineTransform(scaleX: maskScale, y: maskScale)
        mask.addPath(outline.copy(using: &scale)!)
        mask.fillPath()
        let maskSprite = SKSpriteNode(texture: SKTexture(cgImage: mask.makeImage()!), size: size)
        maskSprite.anchorPoint = .zero
        surface.maskNode = maskSprite
        glints(at: centre, radius: radius)
    }

    private func spawnShard(_ triangle: [CGPoint], centroid: CGPoint, impact: CGPoint) {
        let local = triangle.map { CGPoint(x: $0.x - centroid.x, y: $0.y - centroid.y) }
        let path = CGMutablePath()
        path.addLines(between: local)
        path.closeSubpath()

        // Sprites anchor at their bounding box, the physics body at the centroid.
        let box = path.boundingBox
        let shard = SKSpriteNode(texture: shardTexture(triangle), size: box.size)
        shard.position = centroid
        shard.anchorPoint = CGPoint(x: -box.minX / box.width, y: -box.minY / box.height)

        let body = SKPhysicsBody(polygonFrom: path)
        body.restitution = 0.15
        body.friction = 0.7
        body.density = 2
        shard.physicsBody = body
        shardLayer.addChild(shard)

        let away = CGVector(dx: centroid.x - impact.x, dy: centroid.y - impact.y)
        let length = max(hypot(away.dx, away.dy), 1)
        let speed = CGFloat.random(in: 40...180)
        body.velocity = CGVector(dx: away.dx / length * speed, dy: away.dy / length * speed + 60)
        body.angularVelocity = .random(in: -6...6)

        if shardLayer.children.count > maxShards, let oldest = shardLayer.children.first {
            oldest.removeFromParent()
        }
    }

    /// The snapshot pixels inside `triangle`, cut out on a transparent background.
    private func shardTexture(_ triangle: [CGPoint]) -> SKTexture {
        let scale = CGFloat(snapshot.width) / size.width
        let xs = triangle.map(\.x), ys = triangle.map(\.y)
        let box = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        let width = max(Int(ceil(box.width * scale)), 1), height = max(Int(ceil(box.height * scale)), 1)
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: snapshot.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -box.minX, y: -box.minY)
        let clip = CGMutablePath()
        clip.addLines(between: triangle)
        clip.closeSubpath()
        context.addPath(clip)
        context.clip()
        context.draw(snapshot, in: CGRect(origin: .zero, size: size))
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.25))
        context.setLineWidth(1 / scale)
        context.addPath(clip)
        context.strokePath()
        return SKTexture(cgImage: context.makeImage()!)
    }

    // MARK: - Juice

    private func shake(strength: CGFloat) {
        world.removeAction(forKey: "shake")
        var steps: [SKAction] = []
        for i in 0..<6 {
            let s = strength * CGFloat(6 - i) / 6
            steps.append(.move(to: CGPoint(x: .random(in: -s...s), y: .random(in: -s...s)), duration: 0.025))
        }
        steps.append(.move(to: .zero, duration: 0.03))
        world.run(.sequence(steps), withKey: "shake")
    }

    private func dust(at point: CGPoint) {
        burst(at: point, count: 18, speed: 110, color: NSColor(white: 0.85, alpha: 1), lifetime: 0.45, scale: 0.35)
    }

    private func glints(at point: CGPoint, radius: CGFloat) {
        burst(at: point, count: 60, speed: 260, color: .white, lifetime: 0.7, scale: 0.18, spread: radius * 0.6)
    }

    private func burst(at point: CGPoint, count: Int, speed: CGFloat, color: NSColor, lifetime: CGFloat,
                       scale: CGFloat, spread: CGFloat = 4) {
        let emitter = SKEmitterNode()
        emitter.particleTexture = DeskScene.dot
        emitter.numParticlesToEmit = count
        emitter.particleBirthRate = CGFloat(count) * 40
        emitter.particleLifetime = lifetime
        emitter.particleLifetimeRange = lifetime * 0.5
        emitter.particleSpeed = speed
        emitter.particleSpeedRange = speed * 0.8
        emitter.emissionAngleRange = 2 * .pi
        emitter.particlePositionRange = CGVector(dx: spread, dy: spread)
        emitter.yAcceleration = -300
        emitter.particleAlpha = 0.9
        emitter.particleAlphaSpeed = -0.9 / lifetime
        emitter.particleScale = scale
        emitter.particleScaleRange = scale * 0.6
        emitter.particleColor = color
        emitter.particleColorBlendFactor = 1
        emitter.position = point
        emitter.zPosition = 3
        world.addChild(emitter)
        emitter.run(.sequence([.wait(forDuration: Double(lifetime) * 2), .removeFromParent()]))
    }

    private static let dot: SKTexture = {
        let side = 16
        let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(.white)
        context.fillEllipse(in: CGRect(x: 0, y: 0, width: side, height: side))
        return SKTexture(cgImage: context.makeImage()!)
    }()

    // MARK: - Frame timing

    private var windowStart: TimeInterval = 0
    private var framesInWindow = 0
    /// Lowest frames-per-second seen over any one-second window since the last reset.
    private(set) var worstFPS: Double = .infinity

    func resetFrameStats() { worstFPS = .infinity; windowStart = 0 }

    override func update(_ currentTime: TimeInterval) {
        if windowStart == 0 { windowStart = currentTime; framesInWindow = 0 }
        framesInWindow += 1
        if currentTime - windowStart >= 1 {
            worstFPS = min(worstFPS, Double(framesInWindow) / (currentTime - windowStart))
            windowStart = currentTime
            framesInWindow = 0
        }
    }

    /// Raw pixels in the snapshot's own colour space. Paired with a view that renders in that same
    /// space (see `AppDelegate`), the snapshot reaches the display without any colour conversion.
    static func texture(from image: CGImage) -> SKTexture {
        let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        var data = Data(count: image.width * image.height * 4)
        data.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                    bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return SKTexture(data: data, size: CGSize(width: image.width, height: image.height), flipped: true)
    }
}
