import SpriteKit

final class DeskScene: SKScene {
    enum Tool: String { case hammer = "Hammer", minigun = "Minigun" }

    var tool: Tool = .hammer {
        didSet { stopFiring(); announce(tool.rawValue); toolbelt?.select(tool); pointer.tool = tool }
    }
    /// Asks the app to switch every display to a tool picked on the belt.
    var onPickTool: ((Tool) -> Void)?
    /// Asks the app to sweep every display, when the broom on the belt is clicked.
    var onSweepRequest: (() -> Void)?
    var onClean: (() -> Void)?
    private var toolbelt: Toolbelt?
    private let pointer = ToolCursor()
    private var pointerRefresh = 0
    /// While set, the tool stands here instead of on the mouse, and the mouse is ignored: a directed take.
    var scriptedPointer: CGPoint? {
        didSet { if let scriptedPointer { lookToward(scriptedPointer) } }
    }

    private let world = SKNode()
    /// The snapshot and its cracks, masked so that holes show what lies behind.
    private let surface = SKCropNode()
    private let crackLayer = SKNode()
    private let markLayer = SKNode()
    private let shardLayer = SKNode()
    private let iconLayer = SKNode()
    private let patchLayer = SKNode()
    private let tendrilLayer = SKNode()
    private let theVoid: TheVoid
    private let tendrils: Tendrils
    private let debugLayer = SKNode()
    private let backdropTexture: SKTexture
    private let snapshot: CGImage
    private let wallpaper: CGImage
    /// Desktop icons still stuck to the glass, as tiles (icon plus label) in scene coordinates.
    private var icons: [CGRect]
    private(set) var iconsDropped = 0
    private var broom: SKSpriteNode?
    private(set) var isClean = false

    private var damage = DamageModel()
    private var crackNodes: [Int: SKNode] = [:]
    private var holes: [CGPath] = []
    private let mask: CGContext
    private let maxShards = 250
    /// The hole mask is redrawn on every shatter, so it is kept at half resolution.
    private let maskScale: CGFloat = 0.5
    private let maxMarks = 600
    /// Where the viewer seems to look from, -1...1 on each axis; it eases toward the cursor.
    private var gaze = CGPoint.zero
    private var gazeTarget = CGPoint.zero
    private var lastUpdate: TimeInterval = 0

    /// Where the minigun is aimed while the trigger is held.
    private var trigger: CGPoint?
    private var nextRoundAt: TimeInterval = 0
    private let roundInterval: TimeInterval = 1.0 / 15
    /// Seven rounds on one spot shatter it, the same as three hammer hits.
    private let roundDamage = 3.0 / 7
    private let shells = SKEmitterNode()
    private(set) var roundsFired = 0
    private(set) var shatters = 0

    init(shot: ScreenShot, icons: [DesktopIcon], showsControls: Bool) {
        backdropTexture = DeskScene.texture(from: shot.image)
        snapshot = shot.image
        wallpaper = shot.wallpaper
        let origin = shot.screen.frame.origin
        self.icons = icons.map(\.tile).filter { shot.screen.frame.contains($0) }.map { $0.offsetBy(dx: -origin.x, dy: -origin.y) }
        let size = shot.screen.frame.size
        mask = CGContext(data: nil, width: Int(size.width / 2), height: Int(size.height / 2), bitsPerComponent: 8,
                         bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        mask.setFillColor(gray: 1, alpha: 1)
        mask.fill(CGRect(x: 0, y: 0, width: mask.width, height: mask.height))
        theVoid = TheVoid(size: size, dot: DeskScene.dot)
        tendrils = Tendrils(rimLayer: tendrilLayer, creatureLayer: theVoid.creatureLayer)
        super.init(size: size)
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = .black

        let backdrop = SKSpriteNode(texture: backdropTexture, size: size)
        backdrop.anchorPoint = .zero
        // The void stays out of `world`, so a screen shake reveals more void rather than black edges.
        theVoid.zPosition = -2
        tendrilLayer.zPosition = -1
        patchLayer.zPosition = 0.25
        markLayer.zPosition = 0.5
        crackLayer.zPosition = 1
        shardLayer.zPosition = 2
        iconLayer.zPosition = 2.5
        debugLayer.zPosition = 10
        surface.addChild(backdrop)
        surface.addChild(patchLayer)
        surface.addChild(markLayer)
        surface.addChild(crackLayer)
        addChild(theVoid)
        world.addChild(tendrilLayer)
        world.addChild(surface)
        world.addChild(shardLayer)
        world.addChild(iconLayer)
        addChild(world)
        setUpShells()

        // Floor and walls, open at the top, so debris piles up at the bottom of the screen.
        let bounds = CGMutablePath()
        bounds.move(to: CGPoint(x: 0, y: size.height * 3))
        bounds.addLine(to: .zero)
        bounds.addLine(to: CGPoint(x: size.width, y: 0))
        bounds.addLine(to: CGPoint(x: size.width, y: size.height * 3))
        physicsBody = SKPhysicsBody(edgeChainFrom: bounds)
        physicsBody?.categoryBitMask = Category.edge

        for tile in self.icons {
            let outline = SKShapeNode(rect: tile)
            outline.strokeColor = .systemPink
            outline.lineWidth = 2
            debugLayer.addChild(outline)
        }
        debugLayer.isHidden = true
        addChild(debugLayer)
        pointer.zPosition = 100
        pointer.isHidden = true
        addChild(pointer)

        if showsControls {
            let belt = Toolbelt(screenSize: size, broomTexture: DeskScene.broomTexture, broomSize: DeskScene.broomSize,
                                handleTop: DeskScene.broomHandleTop)
            belt.onPick = { [weak self] tool in self?.onPickTool?(tool) }
            belt.onSweep = { [weak self] in self?.onSweepRequest?() }
            belt.select(tool)
            addChild(belt)
            toolbelt = belt
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func toggleDebug() {
        debugLayer.isHidden.toggle()
        view?.showsFPS = !debugLayer.isHidden
        view?.showsNodeCount = !debugLayer.isHidden
    }

    // MARK: - Input

    override func mouseMoved(with event: NSEvent) {
        guard scriptedPointer == nil else { return }
        lookToward(event.location(in: self))
    }

    var creaturesReleased: Int { tendrils.released }
    var damagedSites: Int { damage.sites.count }
    var beltPockets: [CGPoint] { toolbelt?.pocketCentres ?? [] }
    var beltCharm: CGPoint? { toolbelt?.charmCentre }
    var beltVisible: Bool { toolbelt.map { !$0.isHidden } ?? false }
    var pointerVisible: Bool { !pointer.isHidden }
    var pointerPosition: CGPoint { pointer.position }
    var pointerSwinging: Bool { pointer.isSwinging }
    var pointerSpinning: Bool { pointer.isSpinning }
    var pointerHotspotOffset: CGPoint { pointer.hotspotOffset }
    /// Centres of the icons still on the glass.
    var iconCentres: [CGPoint] { icons.map { CGPoint(x: $0.midX, y: $0.midY) } }

    func lookToward(_ point: CGPoint) {
        gazeTarget = CGPoint(x: max(-1, min(1, point.x / size.width * 2 - 1)),
                             y: max(-1, min(1, point.y / size.height * 2 - 1)))
    }

    override func mouseDown(with event: NSEvent) {
        guard scriptedPointer == nil else { return }
        press(at: event.location(in: self))
    }

    /// A mouse press: the belt takes it if it lands there, otherwise the current tool does.
    func press(at point: CGPoint) {
        guard broom == nil, !isClean else { return }
        lookToward(point)
        if toolbelt?.handleClick(at: point) == true { return }
        switch tool {
        case .hammer: pointer.swing { [weak self] in self?.hammer(at: point) }
        case .minigun: startFiring(at: point)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard scriptedPointer == nil else { return }
        lookToward(event.location(in: self))
        if trigger != nil { aim(at: event.location(in: self)) }
    }

    override func mouseUp(with event: NSEvent) {
        guard scriptedPointer == nil else { return }
        stopFiring()
    }

    func hammer(at point: CGPoint) {
        SoundFX.shared.play(.thud)
        dust(at: point)
        apply(damage.hit(at: point, amount: 1), impact: point)
    }

    func startFiring(at point: CGPoint) {
        guard broom == nil, !isClean else { return }
        trigger = point
        nextRoundAt = 0
        shells.position = CGPoint(x: point.x + ToolCursor.ejectOffset.x, y: point.y + ToolCursor.ejectOffset.y)
        shells.particleBirthRate = CGFloat(1 / roundInterval)
        pointer.spin(true)
    }

    func aim(at point: CGPoint) {
        trigger = point
        shells.position = CGPoint(x: point.x + ToolCursor.ejectOffset.x, y: point.y + ToolCursor.ejectOffset.y)
    }

    func stopFiring() {
        trigger = nil
        shells.particleBirthRate = 0
        pointer.spin(false)
    }

    private func fireRound(at aim: CGPoint) {
        roundsFired += 1
        let angle = CGFloat.random(in: 0..<2 * .pi), spread = 7 * sqrt(CGFloat.random(in: 0...1))
        let point = CGPoint(x: aim.x + cos(angle) * spread, y: aim.y + sin(angle) * spread)
        SoundFX.shared.play(.shot, volume: 0.55)
        flash(at: point)
        if !holes.contains(where: { $0.contains(point) }) { mark(at: point) }
        burst(at: point, count: 8, speed: 180, color: NSColor(red: 1, green: 0.85, blue: 0.5, alpha: 1),
              lifetime: 0.25, scale: 0.15)
        shake(strength: 1.5)
        apply(damage.hit(at: point, amount: roundDamage), impact: point)
    }

    // MARK: - Damage rendering

    private func apply(_ result: DamageModel.HitResult, impact: CGPoint) {
        for id in result.merged { crackNodes.removeValue(forKey: id)?.removeFromParent() }
        let site = result.site
        switch site.stage {
        case .intact:
            break
        case .crack, .bigCrack:
            // A round that adds to a crack without changing it leaves the drawn cracks alone.
            guard site.stage > result.previousStage || !result.merged.isEmpty else { break }
            drawCracks(for: site)
            SoundFX.shared.play(.crack, volume: site.stage == .crack ? 0.6 : 1)
        case .shattered:
            // Glass that is already shattered breaks further only once per hammer's worth of damage.
            let crossed = Int(site.damage + 1e-9) > Int(result.previousDamage + 1e-9)
            guard result.previousStage < .shattered || crossed else { break }
            shatters += 1
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
        theVoid.open()
        dropIcons(in: outline, impact: impact)
        tendrils.swallow(outline)
        tendrils.grow(around: polygon, centre: centre, radius: radius, seed: seed) { root in
            holes.contains { $0.contains(root) }
        }
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
        body.categoryBitMask = Category.debris
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
        cut(triangle, from: snapshot, outlined: true)
    }

    private func cut(_ polygon: [CGPoint], from image: CGImage, outlined: Bool) -> SKTexture {
        let scale = CGFloat(image.width) / size.width
        let xs = polygon.map(\.x), ys = polygon.map(\.y)
        let box = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        let width = max(Int(ceil(box.width * scale)), 1), height = max(Int(ceil(box.height * scale)), 1)
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -box.minX, y: -box.minY)
        let clip = CGMutablePath()
        clip.addLines(between: polygon)
        clip.closeSubpath()
        context.addPath(clip)
        context.clip()
        context.draw(image, in: CGRect(origin: .zero, size: size))
        guard outlined else { return SKTexture(cgImage: context.makeImage()!) }
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.25))
        context.setLineWidth(1 / scale)
        context.addPath(clip)
        context.strokePath()
        return SKTexture(cgImage: context.makeImage()!)
    }

    private func mark(at point: CGPoint) {
        let mark = SKSpriteNode(texture: DeskScene.bulletHoles.randomElement()!)
        mark.position = point
        mark.zRotation = .random(in: 0..<2 * .pi)
        markLayer.addChild(mark)
        if markLayer.children.count > maxMarks, let oldest = markLayer.children.first {
            oldest.removeFromParent()
        }
    }

    // MARK: - Icons

    /// Icons whose middle sat on glass that just broke fall out, leaving bare wallpaper behind.
    private func dropIcons(in hole: CGPath, impact: CGPoint) {
        let falling = icons.filter { hole.contains(CGPoint(x: $0.midX, y: $0.midY)) }
        icons.removeAll { tile in falling.contains(tile) }
        for tile in falling {
            let corners = [CGPoint(x: tile.minX, y: tile.minY), CGPoint(x: tile.maxX, y: tile.minY),
                           CGPoint(x: tile.maxX, y: tile.maxY), CGPoint(x: tile.minX, y: tile.maxY)]
            let patch = SKSpriteNode(texture: cut(corners, from: wallpaper, outlined: false), size: tile.size)
            patch.anchorPoint = .zero
            patch.position = tile.origin
            patchLayer.addChild(patch)

            let icon = SKSpriteNode(texture: iconTexture(tile), size: tile.size)
            icon.position = CGPoint(x: tile.midX, y: tile.midY)
            let body = SKPhysicsBody(rectangleOf: CGSize(width: tile.width * 0.8, height: tile.height * 0.9))
            body.categoryBitMask = Category.debris
            body.restitution = 0.2
            body.friction = 0.6
            body.density = 1.5
            icon.physicsBody = body
            iconLayer.addChild(icon)
            let away = CGVector(dx: tile.midX - impact.x, dy: tile.midY - impact.y)
            let length = max(hypot(away.dx, away.dy), 1)
            body.velocity = CGVector(dx: away.dx / length * 120, dy: away.dy / length * 120 + 140)
            body.angularVelocity = .random(in: -3...3)
            iconsDropped += 1
        }
    }

    /// The icon and its label without the desktop around them: only pixels that differ from the bare
    /// wallpaper are kept.
    private func iconTexture(_ tile: CGRect) -> SKTexture {
        let scale = CGFloat(snapshot.width) / size.width
        let width = Int(ceil(tile.width * scale)), height = Int(ceil(tile.height * scale))
        func pixels(of image: CGImage) -> [UInt8] {
            var buffer = [UInt8](repeating: 0, count: width * height * 4)
            let context = CGContext(data: &buffer, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width * 4, space: snapshot.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -tile.minX, y: -tile.minY)
            context.draw(image, in: CGRect(origin: .zero, size: size))
            return buffer
        }
        var icon = pixels(of: snapshot)
        let bare = pixels(of: wallpaper)
        for i in stride(from: 0, to: icon.count, by: 4) {
            let diff = max(abs(Int(icon[i]) - Int(bare[i])), abs(Int(icon[i + 1]) - Int(bare[i + 1])),
                           abs(Int(icon[i + 2]) - Int(bare[i + 2])))
            // Soft threshold, so label shadows and antialiased edges fade out instead of cutting off hard.
            let alpha = max(0, min(255, (diff - 10) * 8))
            for c in 0..<3 { icon[i + c] = UInt8(Int(icon[i + c]) * alpha / 255) }
            icon[i + 3] = UInt8(alpha)
        }
        let data = Data(icon)
        return SKTexture(data: data, size: CGSize(width: width, height: height), flipped: true)
    }

    // MARK: - Tidy-up

    /// A broom pushes all the debris off the screen, then the desktop fades to bare wallpaper.
    func sweep() {
        guard broom == nil, !isClean else { return }
        stopFiring()
        SoundFX.shared.play(.sweep)

        // Floor runs on past the left edge, with no wall there, so the debris can be pushed out.
        let floor = CGMutablePath()
        floor.move(to: CGPoint(x: size.width, y: size.height * 3))
        floor.addLine(to: CGPoint(x: size.width, y: 0))
        floor.addLine(to: CGPoint(x: -2000, y: 0))
        physicsBody = SKPhysicsBody(edgeChainFrom: floor)
        physicsBody?.categoryBitMask = Category.edge

        let broom = SKSpriteNode(texture: DeskScene.broomTexture, size: DeskScene.broomSize)
        broom.anchorPoint = CGPoint(x: 0.5, y: 0)
        broom.zPosition = 5
        world.addChild(broom)
        self.broom = broom
        let start = CGPoint(x: size.width + DeskScene.broomSize.width / 2, y: 0)
        let push = SKAction.run {
            let head = SKPhysicsBody(rectangleOf: CGSize(width: 70, height: 150), center: CGPoint(x: -10, y: 75))
            head.categoryBitMask = Category.broom
            head.collisionBitMask = Category.debris
            head.affectedByGravity = false
            head.allowsRotation = false
            head.mass = 10_000
            broom.physicsBody = head
        }
        // The broom charm drops off the belt, grows to full size as it lands, and starts sweeping from there.
        var lead: TimeInterval = 0
        if let hung = toolbelt?.releaseBroom() {
            lead = 0.4
            let hangPoint = DeskScene.broomHandleTop
            broom.anchorPoint = CGPoint(x: hangPoint.x / DeskScene.broomSize.width, y: hangPoint.y / DeskScene.broomSize.height)
            broom.position = hung
            broom.setScale(Toolbelt.charmScale)
            broom.zRotation = Toolbelt.charmTilt
            let land = CGPoint(x: min(hung.x, size.width - 40), y: 0)
            let fall = SKAction.group([.scale(to: 1, duration: lead), .rotate(toAngle: 0, duration: lead),
                                       .move(to: CGPoint(x: land.x, y: hangPoint.y), duration: lead)])
            fall.timingMode = .easeIn
            broom.run(.sequence([fall, .run {
                broom.anchorPoint = CGPoint(x: 0.5, y: 0)
                broom.position = CGPoint(x: land.x - (hangPoint.x - DeskScene.broomSize.width / 2), y: 0)
            }, push]))
            toolbelt?.leave()
        } else {
            broom.position = start
            broom.run(push)
        }

        let clean = SKSpriteNode(texture: DeskScene.texture(from: wallpaper), size: size)
        clean.anchorPoint = .zero
        clean.zPosition = 50
        clean.alpha = 0
        addChild(clean)
        run(.sequence([
            .wait(forDuration: 1.5 + lead),
            .run { [weak self] in
                self?.shardLayer.run(.fadeOut(withDuration: 0.4))
                self?.iconLayer.run(.fadeOut(withDuration: 0.4))
            },
            .run { clean.run(.fadeIn(withDuration: 0.9)) },
            .wait(forDuration: 0.9),
            .run { [weak self] in
                guard let self else { return }
                self.world.removeFromParent()
                self.theVoid.removeFromParent()
                self.broom = nil
                self.isClean = true
                self.onClean?()
            },
            .wait(forDuration: 1),
            .run { [weak self] in self?.showCleanHint() },
        ]))
    }

    /// Without it, the spotless screen looks like the app broke the desktop rather than a joke about it.
    private func showCleanHint() {
        let headline = SKLabelNode(text: "Ahh. Much better.")
        headline.fontName = "HelveticaNeue-Bold"
        headline.fontSize = 30
        headline.position = CGPoint(x: 0, y: 6)
        let line = SKLabelNode(text: "Enjoy the view. Press Esc whenever you miss your stuff.")
        line.fontName = "HelveticaNeue"
        line.fontSize = 17
        line.position = CGPoint(x: 0, y: -24)
        let width = max(headline.frame.width, line.frame.width) + 64
        let plate = SKShapeNode(rectOf: CGSize(width: width, height: 96), cornerRadius: 22)
        plate.fillColor = NSColor(white: 0, alpha: 0.45)
        plate.strokeColor = NSColor(white: 1, alpha: 0.15)
        for label in [headline, line] {
            label.fontColor = .white
            plate.addChild(label)
        }
        plate.position = CGPoint(x: size.width / 2, y: size.height * 0.18)
        plate.zPosition = 60
        plate.alpha = 0
        addChild(plate)
        plate.run(.fadeIn(withDuration: 0.8))
    }

    private enum Category {
        static let edge: UInt32 = 1
        static let debris: UInt32 = 2
        static let broom: UInt32 = 4
    }

    private static let broomSize = CGSize(width: 150, height: 300)
    /// Top end of the broom's handle, in the broom texture's points.
    private static let broomHandleTop = CGPoint(x: broomSize.width - 14, y: broomSize.height - 8)

    /// A push broom leaning back against the direction it sweeps (right to left).
    private static let broomTexture: SKTexture = {
        let scale: CGFloat = 2
        let w = broomSize.width, h = broomSize.height
        let context = CGContext(data: nil, width: Int(w * scale), height: Int(h * scale), bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: w, y: 0)
        context.scaleBy(x: -1, y: 1)
        context.setLineCap(.round)
        context.setStrokeColor(CGColor(red: 0.45, green: 0.28, blue: 0.14, alpha: 1))
        context.setLineWidth(9)
        context.move(to: CGPoint(x: w / 2 + 6, y: 60))
        context.addLine(to: CGPoint(x: 14, y: h - 8))
        context.strokePath()
        context.setStrokeColor(CGColor(red: 0.62, green: 0.42, blue: 0.22, alpha: 1))
        context.setLineWidth(3)
        context.move(to: CGPoint(x: w / 2 + 4, y: 62))
        context.addLine(to: CGPoint(x: 13, y: h - 10))
        context.strokePath()

        var rng = SeededRandom(seed: 77)
        context.setLineWidth(1.6)
        for i in 0..<70 {
            let x = w / 2 - 34 + CGFloat(i)
            let bristle = rng.range(0.78...0.95)
            context.setStrokeColor(CGColor(red: 0.85 * bristle, green: 0.68 * bristle, blue: 0.3 * bristle, alpha: 1))
            context.move(to: CGPoint(x: x + 2, y: 52))
            context.addLine(to: CGPoint(x: x + rng.range(-4...4), y: rng.range(0...4)))
            context.strokePath()
        }
        context.setFillColor(CGColor(red: 0.28, green: 0.17, blue: 0.09, alpha: 1))
        let block = CGRect(x: w / 2 - 38, y: 48, width: 84, height: 18)
        context.addPath(CGPath(roundedRect: block, cornerWidth: 4, cornerHeight: 4, transform: nil))
        context.fillPath()
        return SKTexture(cgImage: context.makeImage()!)
    }()

    // MARK: - Juice

    private func flash(at point: CGPoint) {
        let flash = SKSpriteNode(texture: DeskScene.dot, size: CGSize(width: 22, height: 22))
        flash.color = NSColor(red: 1, green: 0.92, blue: 0.7, alpha: 1)
        flash.colorBlendFactor = 1
        flash.blendMode = .add
        flash.position = point
        flash.zPosition = 3
        world.addChild(flash)
        flash.run(.sequence([.group([.scale(to: 1.7, duration: 0.06), .fadeOut(withDuration: 0.06)]),
                             .removeFromParent()]))
    }

    /// Spent brass flying off to the right of the gun while the trigger is held.
    private func setUpShells() {
        shells.particleTexture = DeskScene.shell
        shells.particleBirthRate = 0
        shells.particleLifetime = 1.2
        shells.particleSpeed = 260
        shells.particleSpeedRange = 80
        shells.emissionAngle = .pi / 3
        shells.emissionAngleRange = 0.5
        shells.yAcceleration = -1100
        shells.particleRotationRange = 2 * .pi
        shells.particleRotationSpeed = 14
        shells.particleAlphaSpeed = -0.6
        shells.zPosition = 4
        shells.targetNode = world
        world.addChild(shells)
    }

    private func announce(_ text: String) {
        childNode(withName: "announcement")?.removeFromParent()
        let label = SKLabelNode(text: text)
        label.fontName = "HelveticaNeue-Bold"
        label.fontSize = 22
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        let plate = SKShapeNode(rectOf: CGSize(width: label.frame.width + 36, height: 40), cornerRadius: 20)
        plate.fillColor = NSColor(white: 0, alpha: 0.6)
        plate.strokeColor = .clear
        plate.addChild(label)
        plate.name = "announcement"
        plate.position = CGPoint(x: size.width / 2, y: 70)
        plate.zPosition = 20
        addChild(plate)
        plate.run(.sequence([.wait(forDuration: 0.9), .fadeOut(withDuration: 0.3), .removeFromParent()]))
    }

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

    /// A few bullet-hole variants: a dark puncture with a pale rim and short radial cracks.
    private static let bulletHoles: [SKTexture] = (0..<4).map { variant in
        let side: CGFloat = 28, scale: CGFloat = 2
        let context = CGContext(data: nil, width: Int(side * scale), height: Int(side * scale), bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: scale, y: scale)
        let centre = CGPoint(x: side / 2, y: side / 2)
        let cracks = CrackArt.cracks(around: centre, reach: 11, rings: false, seed: 900 + variant)
        context.setLineCap(.round)
        context.translateBy(x: 0.4, y: -0.4)
        context.addPath(cracks)
        context.setStrokeColor(CGColor(gray: 0, alpha: 0.45))
        context.setLineWidth(1.2)
        context.strokePath()
        context.translateBy(x: -0.4, y: 0.4)
        context.addPath(cracks)
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.8))
        context.setLineWidth(0.6)
        context.strokePath()
        context.setFillColor(CGColor(gray: 1, alpha: 0.45))
        context.fillEllipse(in: CGRect(x: centre.x - 3.6, y: centre.y - 3.6, width: 7.2, height: 7.2))
        context.setFillColor(CGColor(gray: 0.05, alpha: 0.9))
        context.fillEllipse(in: CGRect(x: centre.x - 2.6, y: centre.y - 2.6, width: 5.2, height: 5.2))
        return SKTexture(cgImage: context.makeImage()!)
    }

    private static let shell: SKTexture = {
        let context = CGContext(data: nil, width: 6, height: 14, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.86, green: 0.66, blue: 0.27, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 6, height: 14))
        context.setFillColor(CGColor(red: 1, green: 0.88, blue: 0.55, alpha: 1))
        context.fill(CGRect(x: 1, y: 0, width: 1.5, height: 14))
        return SKTexture(cgImage: context.makeImage()!)
    }()

    // MARK: - Frame timing

    private var windowStart: TimeInterval = 0
    private var framesInWindow = 0
    /// Lowest frames-per-second seen over any one-second window since the last reset.
    private(set) var worstFPS: Double = .infinity

    /// Keeps the tool on the mouse on this display, and the system arrow wherever no overlay is under it.
    private func trackPointer() {
        guard let window = view?.window else { return }
        if let scriptedPointer {
            pointer.isHidden = false
            pointer.position = scriptedPointer
            pointerRefresh = (pointerRefresh + 1) % 15
            if NSApp.isActive && (NSCursor.current != ToolCursor.blank || pointerRefresh == 0) { ToolCursor.blank.set() }
            return
        }
        let mouse = NSEvent.mouseLocation
        let inside = window.frame.contains(mouse)
        // Only the active app can hide the system pointer; while another app is active the tool steps aside rather
        // than draw under that app's pointer, and the next click on the game brings it back.
        pointer.isHidden = !inside || !NSApp.isActive
        if inside { pointer.position = CGPoint(x: mouse.x - window.frame.minX, y: mouse.y - window.frame.minY) }
        guard NSApp.isActive else { return }
        let overOverlay = NSApp.windows.contains { $0 is OverlayWindow && $0.isVisible && $0.frame.contains(mouse) }
        let wanted = overOverlay ? ToolCursor.blank : NSCursor.arrow
        // macOS can put its own pointer back without `NSCursor.current` noticing, so over the game the hidden one
        // is re-applied a few times a second rather than only when it looks lost.
        pointerRefresh = (pointerRefresh + 1) % 15
        if NSCursor.current != wanted || (inside && pointerRefresh == 0) { wanted.set() }
    }

    func resetFrameStats() { worstFPS = .infinity; windowStart = 0 }

    override func update(_ currentTime: TimeInterval) {
        if let broom, let body = broom.physicsBody {
            body.velocity = CGVector(dx: -(size.width + 2 * DeskScene.broomSize.width) / 1.4, dy: 0)
            broom.position.y = 0
        }
        let dt = lastUpdate == 0 ? 0 : min(currentTime - lastUpdate, 0.1)
        lastUpdate = currentTime
        trackPointer()
        gaze = gaze.moved(toward: gazeTarget, by: 0.06)
        theVoid.look(gaze)
        theVoid.advance(by: dt)
        if let aim = trigger {
            if nextRoundAt == 0 { nextRoundAt = currentTime }
            while currentTime >= nextRoundAt {
                fireRound(at: aim)
                nextRoundAt += roundInterval
            }
        }
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
