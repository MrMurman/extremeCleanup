import AppKit
import SpriteKit

/// The current tool drawn in place of the mouse pointer: the hammer swings when it strikes, the minigun's barrels
/// spin while it fires.
final class ToolCursor: SKNode {
    private static let art: [DeskScene.Tool: ToolModels.CursorArt] = [
        .hammer: ToolModels.cursor(.hammer), .minigun: ToolModels.cursor(.minigun),
    ]
    /// AppKit's own pointer is hidden while the tool stands in for it.
    static let blank = NSCursor(image: NSImage(size: CGSize(width: 1, height: 1)), hotSpot: .zero)

    var tool: DeskScene.Tool = .hammer { didSet { dress() } }
    private let arm = SKNode()
    private let sprite = SKSpriteNode()
    private var pendingStrike: (() -> Void)?

    var isSpinning: Bool { sprite.action(forKey: "spin") != nil }
    var isSwinging: Bool { arm.action(forKey: "swing") != nil }
    /// The point the tool acts on, relative to this node; zero when the art lines up.
    var hotspotOffset: CGPoint {
        let art = ToolCursor.art[tool]!
        return CGPoint(x: art.hotspot.x - art.grip.x + arm.position.x, y: art.hotspot.y - art.grip.y + arm.position.y)
    }

    /// Where the minigun's spent cases leave it, relative to the pointer.
    static let ejectOffset: CGPoint = {
        let art = ToolCursor.art[.minigun]!
        return CGPoint(x: art.eject.x - art.hotspot.x, y: art.eject.y - art.hotspot.y)
    }()

    override init() {
        super.init()
        arm.addChild(sprite)
        addChild(arm)
        dress()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Pivots the art about the hand so a swing turns the head around the grip, and puts the hotspot on this node.
    private func dress() {
        guard let art = ToolCursor.art[tool] else { return }
        finishStrike()
        spin(false)
        sprite.texture = art.frames[0]
        sprite.size = art.size
        sprite.anchorPoint = CGPoint(x: art.grip.x / art.size.width, y: art.grip.y / art.size.height)
        arm.position = CGPoint(x: art.grip.x - art.hotspot.x, y: art.grip.y - art.hotspot.y)
        arm.zRotation = 0
    }

    /// Raises the hammer and brings it down; `strike` runs as the head lands.
    func swing(strike: @escaping () -> Void) {
        finishStrike()
        pendingStrike = strike
        arm.run(.sequence([
            .rotate(toAngle: -0.55, duration: 0.035),
            .rotate(toAngle: 0.06, duration: 0.035),
            .run { [weak self] in self?.finishStrike() },
            .rotate(toAngle: 0, duration: 0.08),
        ]), withKey: "swing")
    }

    /// A new swing before the last one landed still lands the last one.
    private func finishStrike() {
        let strike = pendingStrike
        pendingStrike = nil
        strike?()
        if strike != nil, arm.action(forKey: "swing") == nil { arm.zRotation = 0 }
    }

    func spin(_ on: Bool) {
        guard let frames = ToolCursor.art[tool]?.frames, frames.count > 1 else { return }
        if on {
            guard !isSpinning else { return }
            sprite.run(.repeatForever(.animate(with: frames, timePerFrame: 1.0 / 40)), withKey: "spin")
        } else {
            sprite.removeAction(forKey: "spin")
        }
    }
}
