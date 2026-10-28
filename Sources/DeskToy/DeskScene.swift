import SpriteKit

final class DeskScene: SKScene {
    private let debugLayer = SKNode()

    init(shot: ScreenShot, icons: [DesktopIcon]) {
        super.init(size: shot.screen.frame.size)
        scaleMode = .resizeFill
        anchorPoint = .zero

        let texture = DeskScene.texture(from: shot.image)
        let backdrop = SKSpriteNode(texture: texture, size: size)
        backdrop.anchorPoint = .zero
        addChild(backdrop)

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

    func toggleDebug() { debugLayer.isHidden.toggle() }

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
