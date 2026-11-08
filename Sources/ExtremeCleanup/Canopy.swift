import SpriteKit

/// The branch canopy along the top of the screen: a corner piece at each side and a top strip tiled
/// between them, drawn near the art's native scale. Pieces drop in one after another, sway on their
/// own phases, and swing harder and lean downwind in a gust.
///
/// Layout numbers are in top-down screen coordinates (y grows downwards).
final class Canopy {
    private final class Placement {
        let sprite: SKSpriteNode
        let piece: AutumnAssets.BranchPiece
        let origin: CGPoint   // the piece's top-left corner
        let root: CGPoint     // where it hangs from and pivots
        let phase: CGFloat
        let side: CGFloat
        let delay: CGFloat    // reveal order
        var progress: CGFloat = 0

        init(_ piece: AutumnAssets.BranchPiece, scale: CGFloat, origin: CGPoint, root: CGPoint,
             phase: CGFloat, side: CGFloat, delay: CGFloat) {
            self.piece = piece; self.origin = origin; self.root = root
            self.phase = phase; self.side = side; self.delay = delay
            let w = piece.size.width * scale, h = piece.size.height * scale
            sprite = SKSpriteNode(texture: piece.texture, size: CGSize(width: w, height: h))
            sprite.anchorPoint = CGPoint(x: (root.x - origin.x) / w, y: 1 - (root.y - origin.y) / h)
        }
    }

    let node = SKNode()
    private let size: CGSize
    private let scale: CGFloat
    private let retro: Bool
    private var placements: [Placement] = []
    private var showing = false
    private var clock: CGFloat = 0    // since the last show/hide
    private var time: CGFloat = 0

    private let showSeconds: CGFloat = 0.55
    private let hideSeconds: CGFloat = 0.45
    private let stagger: CGFloat = 0.08
    private let stripWave: CGFloat = 0.3  // strips drop in from the corners towards the middle, over this
    private let calm: CGFloat = 0.55  // resting wind strength: a gentle idle sway

    init(size: CGSize, pieces: AutumnAssets.BranchPieces, style: AutumnStyle) {
        self.size = size
        retro = style == .retro
        scale = min(retro ? 0.44 : 0.52, size.width / 950)

        let left = pieces.left, right = pieces.right, top = pieces.top
        placements.append(Placement(left, scale: scale, origin: CGPoint(x: -5, y: 0), root: CGPoint(x: 0, y: 0),
                                    phase: 0.3, side: 1, delay: 0))
        placements.append(Placement(right, scale: scale, origin: CGPoint(x: size.width - right.size.width * scale + 5, y: 0),
                                    root: CGPoint(x: size.width, y: 0), phase: 1.1, side: -1, delay: stagger))
        // Top strips fill the gap between the corners, overlapping them a little; alternate heights
        // and mirroring keep the repeat from reading as a tile.
        let corner = max(left.size.width, right.size.width) * scale
        let start = corner * 0.85, end = size.width - corner * 0.85
        let tile = top.size.width * scale
        let count = max(1, Int(ceil((end - start) / (tile * 0.95))))
        for i in 0..<count {
            let centre = start + (end - start) * (CGFloat(i) + 0.5) / CGFloat(count)
            let lift = CGFloat(i % 3) * 5
            let p = Placement(top, scale: scale, origin: CGPoint(x: centre - tile / 2, y: -8 - lift),
                              root: CGPoint(x: centre, y: -8), phase: 2 + CGFloat(i) * 1.6,
                              side: i % 2 == 0 ? -1 : 1,
                              delay: stagger * 2 + stripWave * (1 - abs(centre - size.width / 2) / (size.width / 2)))
            if i % 2 == 1 { p.sprite.xScale = -1 }
            placements.append(p)
        }
        for (i, p) in placements.enumerated() {
            p.sprite.zPosition = i < 2 ? 0.1 : 0  // corners over the strips they overlap
            node.addChild(p.sprite)
        }
        place(gust: 0, direction: 1)
    }

    var isShown: Bool { placements.allSatisfy { $0.progress >= 1 } }

    func show() { showing = true; clock = 0 }
    func hide() { showing = false; clock = 0 }

    func advance(by dt: CGFloat, gust: CGFloat, direction: CGFloat) {
        time += dt; clock += dt
        let last = placements.map(\.delay).max() ?? 0
        for p in placements {
            if showing {
                if clock >= p.delay { p.progress = min(1, p.progress + dt / showSeconds) }
            } else if clock >= last - p.delay {  // leave in reverse order
                p.progress = max(0, p.progress - dt / hideSeconds)
            }
        }
        place(gust: gust, direction: direction)
    }

    /// A point on fully shown foliage, for a leaf the wind shakes loose.
    func shedPoint() -> CGPoint? {
        guard let p = placements.filter({ $0.progress >= 1 && !$0.piece.leafSpots.isEmpty }).randomElement(),
              let spot = p.piece.leafSpots.randomElement() else { return nil }
        let w = p.piece.size.width * scale, h = p.piece.size.height * scale
        let x = p.sprite.xScale < 0 ? 1 - spot.x : spot.x
        return CGPoint(x: p.origin.x + x * w, y: size.height - (p.origin.y + spot.y * h))
    }

    /// The lowest the foliage hangs at `x` when the canopy is down (scene y); nil where no piece has
    /// foliage over `x`.
    func foliageBottom(atX x: CGFloat) -> CGFloat? {
        var lowest: CGFloat?
        for p in placements {
            let w = p.piece.size.width * scale
            guard x >= p.origin.x, x < p.origin.x + w else { continue }
            var column = Int((x - p.origin.x) / scale)
            if p.sprite.xScale < 0 { column = p.piece.bottoms.count - 1 - column }
            guard p.piece.bottoms.indices.contains(column), let row = p.piece.bottoms[column] else { continue }
            let y = size.height - (p.origin.y + CGFloat(row + 1) * scale)
            lowest = min(lowest ?? y, y)
        }
        return lowest
    }

    private func place(gust: CGFloat, direction: CGFloat) {
        let strength = calm + 0.9 * gust
        for p in placements {
            let swing = sin(time * 0.72) * 0.65 + sin(time * 1.43 + p.phase) * 0.35
            let dx = strength * 2.5 * swing + direction * gust * 4
            let dy = strength * 1.7 * sin(time * 0.94 + p.phase)
            // The sway is worked out clockwise-positive (y-down); SpriteKit's angle is counter-clockwise.
            let angle = -strength * (0.014 * swing + 0.004 * sin(time * 1.9 + p.phase)) * p.side
            let eased = 1 - pow(1 - p.progress, 3)
            let hidden = (1 - eased) * (p.sprite.size.height + 50)
            var position = CGPoint(x: p.root.x + dx, y: size.height - p.root.y - dy + hidden)
            if retro { position = CGPoint(x: position.x.rounded(), y: position.y.rounded()) }
            p.sprite.position = position
            p.sprite.zRotation = angle + direction * gust * 0.012
            p.sprite.isHidden = p.progress <= 0
        }
    }
}
