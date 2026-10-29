import SpriteKit

/// A leather tool belt down the right edge: numbered pockets holding the tools, empty pockets for tools still to
/// come, and the broom hanging underneath like a charm.
final class Toolbelt: SKNode {
    var onPick: ((DeskScene.Tool) -> Void)?
    var onSweep: (() -> Void)?

    private let tools: [DeskScene.Tool?] = [.hammer, .minigun, nil, nil, nil, nil, nil, nil]
    private static let pocket: CGFloat = 64, gap: CGFloat = 6, pad: CGFloat = 12, width: CGFloat = 86
    private static var height: CGFloat { pad * 2 + pocket * 8 + gap * 7 }
    private static let cordLength: CGFloat = 16

    private var items: [DeskScene.Tool: (sprite: SKSpriteNode, frames: [SKTexture])] = [:]
    private var marks: [Int: SKLabelNode] = [:]
    private let highlight: SKShapeNode
    private let charm = SKNode()
    private let broom: SKSpriteNode
    /// The broom charm is drawn this much smaller than the sweeping broom.
    static let charmScale: CGFloat = 0.32
    /// Rotation that makes the broom's slanted handle hang straight down.
    static let charmTilt: CGFloat = 0.257

    init(screenSize: CGSize, broomTexture: SKTexture, broomSize: CGSize, handleTop: CGPoint) {
        highlight = SKShapeNode(rectOf: CGSize(width: Toolbelt.pocket + 2, height: Toolbelt.pocket + 2), cornerRadius: 11)
        broom = SKSpriteNode(texture: broomTexture, size: broomSize)
        super.init()

        let strap = SKSpriteNode(texture: Toolbelt.strapTexture)
        strap.size = CGSize(width: Toolbelt.width, height: Toolbelt.height)
        addChild(strap)

        for (i, tool) in tools.enumerated() {
            let centre = Toolbelt.centre(of: i)
            let number = SKLabelNode(text: "\(i + 1)")
            number.fontName = "HelveticaNeue-Bold"
            number.fontSize = 11
            number.fontColor = NSColor(red: 0.95, green: 0.86, blue: 0.68, alpha: 0.75)
            number.position = CGPoint(x: centre.x - Toolbelt.pocket / 2 + 9, y: centre.y + Toolbelt.pocket / 2 - 15)
            number.zPosition = 2
            addChild(number)
            if let tool {
                let frames = ToolModels.swivel(tool)
                let sprite = SKSpriteNode(texture: frames[0], size: CGSize(width: 60, height: 60))
                sprite.position = centre
                sprite.zPosition = 1
                addChild(sprite)
                items[tool] = (sprite, frames)
            } else {
                let mark = SKLabelNode(text: "?")
                mark.fontName = "HelveticaNeue-Bold"
                mark.fontSize = 24
                mark.fontColor = NSColor(red: 0.95, green: 0.86, blue: 0.68, alpha: 0.22)
                mark.verticalAlignmentMode = .center
                mark.position = centre
                addChild(mark)
                marks[i] = mark
            }
        }

        highlight.strokeColor = NSColor(red: 1, green: 0.76, blue: 0.32, alpha: 0.95)
        highlight.lineWidth = 2.5
        highlight.zPosition = 3
        let halo = SKShapeNode(rectOf: CGSize(width: Toolbelt.pocket + 6, height: Toolbelt.pocket + 6), cornerRadius: 13)
        halo.strokeColor = NSColor(red: 1, green: 0.76, blue: 0.32, alpha: 0.3)
        halo.lineWidth = 4
        highlight.addChild(halo)
        addChild(highlight)

        let cord = SKShapeNode()
        let cordPath = CGMutablePath()
        cordPath.move(to: .zero)
        cordPath.addLine(to: CGPoint(x: 0, y: -Toolbelt.cordLength))
        cord.path = cordPath
        cord.strokeColor = NSColor(red: 0.25, green: 0.14, blue: 0.07, alpha: 1)
        cord.lineWidth = 2
        charm.addChild(cord)
        broom.anchorPoint = CGPoint(x: handleTop.x / broomSize.width, y: handleTop.y / broomSize.height)
        broom.setScale(Toolbelt.charmScale)
        broom.zRotation = Toolbelt.charmTilt
        broom.position = CGPoint(x: 0, y: -Toolbelt.cordLength + 2)
        charm.addChild(broom)
        charm.position = CGPoint(x: 0, y: -Toolbelt.height / 2 + 4)
        charm.zPosition = -1
        addChild(charm)
        let sway = SKAction.sequence([.rotate(toAngle: 0.1, duration: 1.4), .rotate(toAngle: -0.1, duration: 1.4)])
        sway.timingMode = .easeInEaseOut
        charm.run(.repeatForever(sway))

        let extent = Toolbelt.height + Toolbelt.cordLength + broomSize.height * Toolbelt.charmScale
        setScale(min(1, (screenSize.height - 40) / extent))
        let overhang = (Toolbelt.cordLength + broomSize.height * Toolbelt.charmScale) * xScale
        position = CGPoint(x: screenSize.width - (Toolbelt.width / 2 + 14) * xScale,
                           y: screenSize.height / 2 + overhang / 2)
        zPosition = 40
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func select(_ tool: DeskScene.Tool) {
        for (t, item) in items {
            item.sprite.removeAction(forKey: "spin")
            item.sprite.texture = item.frames[0]
            if t == tool {
                item.sprite.run(.repeatForever(.animate(with: item.frames, timePerFrame: 1.0 / 24)), withKey: "spin")
                highlight.position = item.sprite.position
            }
        }
    }

    /// Handles a click if it lands on the belt or the broom; returns false when the glass should take it.
    func handleClick(at scenePoint: CGPoint) -> Bool {
        guard !isHidden, let scene else { return false }
        let point = convert(scenePoint, from: scene)
        if !charm.isHidden, charm.calculateAccumulatedFrame().contains(point) {
            onSweep?()
            return true
        }
        let half = CGSize(width: Toolbelt.width / 2, height: Toolbelt.height / 2)
        guard abs(point.x) <= half.width, abs(point.y) <= half.height else { return false }
        let index = Int((half.height - Toolbelt.pad - point.y) / (Toolbelt.pocket + Toolbelt.gap))
        guard (0..<tools.count).contains(index) else { return true }
        if let tool = tools[index] {
            onPick?(tool)
        } else if let mark = marks[index] {
            SoundFX.shared.play(.thud, volume: 0.2)
            mark.removeAllActions()
            mark.run(.sequence([.rotate(toAngle: 0.25, duration: 0.05), .rotate(toAngle: -0.25, duration: 0.08),
                                .rotate(toAngle: 0.12, duration: 0.06), .rotate(toAngle: 0, duration: 0.05)]))
        }
        return true
    }

    /// Unhooks the broom charm: returns where it hung, in scene coordinates, and hides it.
    func releaseBroom() -> CGPoint? {
        guard !charm.isHidden, let scene else { return nil }
        charm.isHidden = true
        return broom.parent.map { scene.convert(broom.position, from: $0) }
    }

    var pocketCentres: [CGPoint] {
        guard let scene else { return [] }
        return (0..<tools.count).map { scene.convert(Toolbelt.centre(of: $0), from: self) }
    }

    var charmCentre: CGPoint? {
        guard let scene, !charm.isHidden else { return nil }
        let frame = charm.calculateAccumulatedFrame()
        return scene.convert(CGPoint(x: frame.midX, y: frame.midY), from: self)
    }

    /// Slides the belt off the right edge of the screen.
    func leave() {
        run(.sequence([.moveBy(x: (Toolbelt.width + 40) * xScale, y: 0, duration: 0.4), .hide()]))
    }

    private static func centre(of index: Int) -> CGPoint {
        CGPoint(x: 0, y: height / 2 - pad - pocket / 2 - CGFloat(index) * (pocket + gap))
    }

    private static let strapTexture: SKTexture = {
        let scale: CGFloat = 2
        let context = CGContext(data: nil, width: Int(width * scale), height: Int(height * scale), bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: scale, y: scale)
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let outline = CGPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), cornerWidth: 14, cornerHeight: 14, transform: nil)

        context.saveGState()
        context.addPath(outline)
        context.clip()
        let edge = CGColor(red: 0.27, green: 0.15, blue: 0.08, alpha: 1)
        let middle = CGColor(red: 0.47, green: 0.28, blue: 0.15, alpha: 1)
        let leather = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [edge, middle, edge] as CFArray,
                                 locations: [0, 0.5, 1])!
        context.drawLinearGradient(leather, start: .zero, end: CGPoint(x: width, y: 0), options: [])
        // Grain: faint random scuffs.
        var rng = SeededRandom(seed: 31)
        for _ in 0..<260 {
            context.setFillColor(CGColor(gray: rng.range(0...1) < 0.5 ? 0 : 1, alpha: rng.range(0.02...0.06)))
            let r = rng.range(0.5...2.2)
            context.fillEllipse(in: CGRect(x: rng.range(0...width), y: rng.range(0...height), width: r * 2, height: r))
        }
        context.restoreGState()

        context.setStrokeColor(CGColor(red: 0.95, green: 0.85, blue: 0.62, alpha: 0.55))
        context.setLineWidth(1.2)
        context.setLineDash(phase: 0, lengths: [5, 4])
        context.addPath(CGPath(roundedRect: bounds.insetBy(dx: 5, dy: 5), cornerWidth: 10, cornerHeight: 10, transform: nil))
        context.strokePath()
        context.setLineDash(phase: 0, lengths: [])

        for i in 0..<8 {
            // Strap coordinates have their origin at the bottom-left; pocket centres are measured from the middle.
            let c = centre(of: i)
            let rect = CGRect(x: width / 2 - pocket / 2, y: height / 2 + c.y - pocket / 2, width: pocket, height: pocket)
            let pocketPath = CGPath(roundedRect: rect, cornerWidth: 10, cornerHeight: 10, transform: nil)
            context.addPath(pocketPath)
            context.setFillColor(CGColor(red: 0.17, green: 0.09, blue: 0.05, alpha: 1))
            context.fillPath()
            context.saveGState()
            context.addPath(pocketPath)
            context.clip()
            context.setStrokeColor(CGColor(gray: 0, alpha: 0.55))
            context.setLineWidth(5)
            var drop = CGAffineTransform(translationX: 0, y: -2)
            context.addPath(pocketPath.copy(using: &drop)!)
            context.strokePath()
            context.restoreGState()
            context.setStrokeColor(CGColor(red: 1, green: 0.9, blue: 0.75, alpha: 0.12))
            context.setLineWidth(1)
            context.addPath(CGPath(roundedRect: rect.insetBy(dx: -1, dy: -1), cornerWidth: 11, cornerHeight: 11, transform: nil))
            context.strokePath()
            for x in [rect.minX + 2, rect.maxX - 2] {
                let rivet = CGRect(x: x - 3, y: rect.maxY + 0.5, width: 6, height: 6)
                let brass = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                       colors: [CGColor(red: 1, green: 0.9, blue: 0.6, alpha: 1),
                                                CGColor(red: 0.55, green: 0.38, blue: 0.14, alpha: 1)] as CFArray,
                                       locations: [0, 1])!
                context.saveGState()
                context.addEllipse(in: rivet)
                context.clip()
                context.drawRadialGradient(brass, startCenter: CGPoint(x: rivet.midX - 1, y: rivet.midY + 1), startRadius: 0,
                                           endCenter: CGPoint(x: rivet.midX, y: rivet.midY), endRadius: 3.5, options: [])
                context.restoreGState()
            }
        }
        context.setStrokeColor(CGColor(gray: 0, alpha: 0.6))
        context.setLineWidth(1.5)
        context.addPath(outline)
        context.strokePath()
        return SKTexture(cgImage: context.makeImage()!)
    }()
}
