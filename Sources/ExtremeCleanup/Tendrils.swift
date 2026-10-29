import SpriteKit

/// Strands that reach into each hole from under the glass. When the glass they cling to breaks away, a group
/// lets go, curls up into a creature and swims off into the void.
final class Tendrils {
    private final class Group {
        let node: SKNode
        let roots: [CGPoint]
        let radius: CGFloat
        var lost: Set<Int> = []
        init(node: SKNode, roots: [CGPoint], radius: CGFloat) {
            self.node = node
            self.roots = roots
            self.radius = radius
        }
    }

    private let rimLayer: SKNode
    private let creatureLayer: SKNode
    private var groups: [Group] = []
    private(set) var released = 0
    private let maxGroups = 80
    private let maxCreatures = 10
    /// A group lets go once this share of its roots hangs in open void.
    private let releaseShare = 0.4

    init(rimLayer: SKNode, creatureLayer: SKNode) {
        self.rimLayer = rimLayer
        self.creatureLayer = creatureLayer
    }

    /// Marks roots that `hole` has just opened up, releasing groups that lost their grip.
    func swallow(_ hole: CGPath) {
        for group in groups {
            for (i, root) in group.roots.enumerated() where hole.contains(root) { group.lost.insert(i) }
        }
        let released = groups.filter { Double($0.lost.count) >= Double($0.roots.count) * releaseShare }
        groups.removeAll { group in released.contains { $0 === group } }
        released.forEach(release)
        self.released += released.count
    }

    func grow(around polygon: [CGPoint], centre: CGPoint, radius: CGFloat, seed: Int, isOpen: (CGPoint) -> Bool) {
        let (path, roots) = CrackArt.tendrils(of: polygon, centre: centre, seed: seed, isOpen: isOpen)
        guard !roots.isEmpty else { return }
        let node = SKNode()
        let body = SKShapeNode(path: path)
        body.strokeColor = NSColor(red: 0.05, green: 0.01, blue: 0.02, alpha: 0.95)
        body.lineWidth = 3
        body.lineCap = .round
        let vein = SKShapeNode(path: path)
        vein.strokeColor = NSColor(red: 0.55, green: 0.06, blue: 0.05, alpha: 0.5)
        vein.lineWidth = 0.8
        node.addChild(body)
        node.addChild(vein)
        node.position = centre
        node.setScale(0.6)
        rimLayer.addChild(node)

        // They creep in, then keep slowly reaching and pulling back.
        let breathe = SKAction.sequence([
            .group([.scale(to: 1.08, duration: 2.6), .rotate(byAngle: 0.04, duration: 2.6)]),
            .group([.scale(to: 0.96, duration: 2.6), .rotate(byAngle: -0.04, duration: 2.6)]),
        ])
        breathe.timingMode = .easeInEaseOut
        node.run(.sequence([.scale(to: 1, duration: 1.5), .repeatForever(breathe)]))

        groups.append(Group(node: node, roots: roots, radius: radius))
        if groups.count > maxGroups { groups.removeFirst().node.removeFromParent() }
    }

    private func release(_ group: Group) {
        let strands = group.node
        strands.removeAllActions()
        let creature = SKNode()
        creature.position = rimLayer.convert(strands.position, to: creatureLayer)
        strands.removeFromParent()
        strands.position = .zero
        creature.addChild(strands)
        creatureLayer.addChild(creature)

        let r = group.radius
        let core = SKShapeNode(circleOfRadius: r * 0.16)
        core.fillColor = NSColor(red: 0.02, green: 0.008, blue: 0.015, alpha: 1)
        core.strokeColor = NSColor(red: 0.45, green: 0.05, blue: 0.05, alpha: 0.6)
        core.lineWidth = 1
        core.alpha = 0
        creature.addChild(core)
        for side in [-1.0, 1.0] as [CGFloat] {
            let eye = SKShapeNode(circleOfRadius: max(1.4, r * 0.022))
            eye.fillColor = NSColor(red: 0.95, green: 0.12, blue: 0.08, alpha: 1)
            eye.strokeColor = .clear
            eye.position = CGPoint(x: side * r * 0.055, y: r * 0.03)
            eye.alpha = 0
            core.addChild(eye)
            let blink = SKAction.sequence([.wait(forDuration: .random(in: 2...5)),
                                           .fadeAlpha(to: 0.1, duration: 0.08), .fadeAlpha(to: 1, duration: 0.12)])
            eye.run(.sequence([.wait(forDuration: 1.8), .fadeIn(withDuration: 0.6), .repeatForever(blink)]))
        }

        // Curl up into a knot, then pulse like something swimming.
        let pulse = SKAction.sequence([.scale(to: 0.42, duration: 0.5), .scale(to: 0.32, duration: 1.1)])
        pulse.timingMode = .easeInEaseOut
        let curl = SKAction.group([.scale(to: 0.35, duration: 1.8), .rotate(byAngle: .random(in: -1...1), duration: 1.8)])
        curl.timingMode = .easeOut
        strands.run(.sequence([curl, .repeatForever(pulse)]))
        core.run(.sequence([.wait(forDuration: 0.6), .fadeIn(withDuration: 1.2)]))

        var heading = CGFloat.random(in: 0..<2 * .pi)
        var strokes: [SKAction] = [.wait(forDuration: 1.8)]
        for _ in 0..<24 {
            heading += .random(in: -0.8...0.8)
            let reach = CGFloat.random(in: 25...70)
            let stroke = SKAction.move(by: CGVector(dx: cos(heading) * reach, dy: sin(heading) * reach), duration: 1.6)
            stroke.timingMode = .easeOut
            strokes.append(stroke)
        }
        // It drifts deeper as it goes: smaller and fainter until it is gone.
        let sink = SKAction.sequence([.wait(forDuration: 1.8),
                                      .group([.scale(to: 0.25, duration: 24),
                                              .sequence([.wait(forDuration: 14), .fadeOut(withDuration: 10)])]),
                                      .removeFromParent()])
        creature.run(.group([.sequence(strokes), sink,
                             .repeatForever(.rotate(byAngle: .random(in: -1.2...1.2), duration: 12))]))

        let swimming = creatureLayer.children.filter { $0.name == nil }
        if swimming.count > maxCreatures, let oldest = swimming.first {
            oldest.name = "leaving"
            oldest.run(.sequence([.fadeOut(withDuration: 0.8), .removeFromParent()]))
        }
    }
}
