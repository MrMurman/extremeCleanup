import SpriteKit

/// Autumn: a branch canopy slides in from the top, leaves drift down and pile up as individual
/// liftable leaves, and a leaf blower blows them along the ground, into the air, and off the screen.
///
/// The motion is hand-rolled rather than using SpriteKit physics, so falling, sliding and blown
/// leaves all respond to the same cone of wind. Resting leaves are never simulated; the pile is a
/// 16-pixel-bucket height profile that resettles when leaves are removed.
final class Leaves {
    private enum State { case air, slide, rest }

    private final class Leaf {
        let node = SKSpriteNode()
        var x: CGFloat = 0, y: CGFloat = 0
        var vx: CGFloat = 0, vy: CGFloat = 0
        var age: CGFloat = 0
        var sway: CGFloat = 0, phase: CGFloat = 0, spin: CGFloat = 0, period: CGFloat = 1.3
        var baseSize: CGFloat = 0
        var speed: CGFloat = 0
        var restAngle: CGFloat = 0
        var mass: CGFloat = 1, thickness: CGFloat = 3
        var variant = 0, pose = 0
        var usePose = true
        var state: State = .air
        var blown = false
        /// Carried by a gust: may leave the screen like a blown leaf, but keeps falling gently.
        var adrift = false
        var support: CGFloat = 0
        var finished = false
        var swept = false
        /// The icon it rests on; nil on the ground pile.
        var perch: Perch?
    }

    /// The top edge of a desktop icon's image or of a window, which catches leaves.
    struct Ledge {
        static let iconLeaves = 6        // per icon; the drift height usually stops it sooner
        static let windowLeavesPer64pt = 5

        /// The icon's tile or the window's frame: identifies the ledge when the icon drops.
        let frame: CGRect
        let minX: CGFloat
        let step: CGFloat
        /// The top edge per column (scene y); nil where nothing is there to land on.
        let tops: [CGFloat?]
        let capacity: Int
    }

    private final class Perch {
        let ledge: Ledge
        var tops: [CGFloat?]
        var heights: [CGFloat]
        var count = 0
        init(_ ledge: Ledge) {
            self.ledge = ledge; tops = ledge.tops
            heights = [CGFloat](repeating: 0, count: ledge.tops.count)
        }

        func centre(_ i: Int) -> CGFloat { ledge.minX + (CGFloat(i) + 0.5) * ledge.step }
        func column(_ x: CGFloat) -> Int? {
            let i = Int(floor((x - ledge.minX) / ledge.step))
            return tops.indices.contains(i) && tops[i] != nil ? i : nil
        }
        func surface(_ x: CGFloat) -> CGFloat? { column(x).map { tops[$0]! + heights[$0] } }
        /// Rise over run of the ledge's own edge around `x`.
        func slope(_ x: CGFloat) -> CGFloat {
            guard let i = column(x) else { return 0 }
            let l = (max(0, i - 2)...i).first { tops[$0] != nil }!
            let r = (i...min(tops.count - 1, i + 2)).last { tops[$0] != nil }!
            return r == l ? 0 : (tops[r]! - tops[l]!) / (CGFloat(r - l) * ledge.step)
        }
    }

    // MARK: Inputs
    private let layer: SKNode
    private let size: CGSize
    private let style: AutumnStyle
    private let frames: [SKTexture]
    private let poses: [SKTexture]
    private let poseAspect: [CGFloat]
    private let canopy: Canopy

    // MARK: Tunables (from the browser prototype that came with the art, with lower caps)
    private let maxTotal = 600           // hard cap on leaves on screen; fall pauses only when this deep
    private let maxActive = 300
    private let leafRate: CGFloat = 16   // leaves/second raining down while autumn is on
    private let settledRate: CGFloat = 4 // ...easing to this once the screen is mostly full
    private let shakeRate: CGFloat = 3   // extra leaves a full gust shakes off the canopy
    private let perchMaxHeight: CGFloat = 14
    private let canopyClearance: CGFloat = 24  // ledges this close under the foliage catch nothing...
    private let canopyReach: CGFloat = 96      // ...counting foliage this far to either side
    private let perchMaxSlope: CGFloat = 0.8  // steeper shoulders shed leaves instead of catching them
    private let blowerRange: CGFloat = 460
    private let coneBase: CGFloat = 18
    private let coneSlope: CGFloat = 0.38
    private var power: CGFloat = 0.72

    // MARK: Pile surface
    private var pileHeights: [CGFloat]
    private let profileStep: CGFloat = 16
    private var maxPile: CGFloat { min(size.height * 0.3, 240) }

    // MARK: State
    private var moving: [Leaf] = []
    private var resting: [Leaf] = []
    private var restBuckets: [Int: [Leaf]] = [:]
    private var perches: [Perch] = []
    private var running = false
    private var spawnBudget: CGFloat = 0
    private var elapsed: CGFloat = 0
    private var pileDirty = false

    private var blowOn = false
    private var blowOrigin = CGPoint.zero
    private var blowAngle: CGFloat = 0

    // MARK: Wind gusts
    // Random gusts keep an idle screen alive: they push falling leaves sideways and blow some of the
    // pile off the downwind edge, which makes room under `maxTotal` so the fall never stalls.
    private var gust: CGFloat = 0              // current strength, 0...1
    private var gustDir: CGFloat = 1
    private var gustTime: CGFloat = 0
    private var gustLength: CGFloat = 0        // 0 between gusts
    private var gustPeak: CGFloat = 0
    private var nextGust: CGFloat = 5

    init(layer: SKNode, size: CGSize, assets: AutumnAssets.StyleAssets, style: AutumnStyle) {
        self.layer = layer
        self.size = size
        self.style = style
        frames = assets.leafFrames
        poses = assets.pileFrames
        poseAspect = assets.pileAspects.map { max($0, 0.1) }
        let count = max(8, Int(size.width / profileStep))
        pileHeights = [CGFloat](repeating: 0, count: count)

        canopy = Canopy(size: size, pieces: assets.branches, style: style)
        canopy.node.zPosition = 2  // in front: falling leaves pass behind the branches
        layer.addChild(canopy.node)
    }

    var isOn: Bool { running }
    var isGusting: Bool { gustLength > 0 }

    /// Called as each gust begins, with its length (s), peak strength (0...1) and direction (±1).
    var onGust: ((_ seconds: CGFloat, _ strength: CGFloat, _ direction: CGFloat) -> Void)?

    func start() {
        guard !running else { return }
        running = true
        canopy.show()
    }

    /// Starts a gust now, for a directed take, instead of waiting for the random schedule.
    func startGust(seconds: CGFloat, strength: CGFloat, direction: CGFloat) {
        guard running else { return }
        gustDir = direction < 0 ? -1 : 1
        gustLength = max(0.1, seconds)
        gustPeak = min(1, max(0, strength))
        gustTime = 0
        onGust?(gustLength, gustPeak, gustDir)
    }

    func stop() {
        running = false
        canopy.hide()
    }

    /// The icons leaves can settle on.
    /// Parts of a ledge hidden in the canopy are left out: leaves there would read as foliage.
    func setLedges(_ ledges: [Ledge]) {
        perches = ledges.map(Perch.init)
        for perch in perches {
            for (i, top) in perch.tops.enumerated() {
                // The deepest foliage nearby: a leaf at that height beside a hanging cluster reads as
                // part of it, not only one directly underneath.
                let around = stride(from: perch.centre(i) - canopyReach, through: perch.centre(i) + canopyReach, by: 8)
                if let top, let foliage = around.compactMap({ canopy.foliageBottom(atX: $0) }).min(), top > foliage - canopyClearance {
                    perch.tops[i] = nil
                }
            }
        }
        perches.removeAll { $0.tops.allSatisfy { $0 == nil } }
    }

    /// The icon has dropped out of the glass: the leaves on it fall.
    func removeLedge(_ frame: CGRect) {
        guard let perch = perches.first(where: { $0.ledge.frame == frame }) else { return }
        perches.removeAll { $0 === perch }
        release(resting.filter { $0.perch === perch })
    }

    /// Glass broke under these ledge points: they go, and the leaves resting there fall.
    func breakLedges(in hole: CGPath) {
        var falling: [Leaf] = []
        for perch in perches {
            var broken = false
            for (i, top) in perch.tops.enumerated() where top != nil && hole.contains(CGPoint(x: perch.centre(i), y: top!)) {
                perch.tops[i] = nil; broken = true
            }
            if broken { falling += resting.filter { $0.perch === perch && perch.column($0.x) == nil } }
        }
        perches.removeAll { $0.tops.allSatisfy { $0 == nil } }
        release(falling)
    }

    private func release(_ falling: [Leaf]) {
        for leaf in falling {
            leaf.perch = nil; leaf.state = .air; leaf.finished = false
            leaf.vx = .random(in: -20...20); leaf.vy = 0; leaf.age = 0
            moving.append(leaf)
        }
        let set = Set(falling.map { ObjectIdentifier($0) })
        resting.removeAll { set.contains(ObjectIdentifier($0)) }
        pileDirty = true
    }

    /// Stops new leaves falling; the broom then pushes the pile off with `sweepPast`.
    func beginSweep() { running = false }

    /// Called each frame while the broom crosses right-to-left: leaves its leading edge has reached
    /// are lifted off the pile and driven left ahead of it, the way shards are shoved off-screen.
    func sweepPast(_ broomX: CGFloat, speed: CGFloat) {
        let lead = broomX - 45  // the broom head's leading (left) edge
        var woke = false
        for leaf in resting where !leaf.swept && leaf.x >= lead {
            leaf.swept = true; leaf.state = .air; leaf.blown = true; leaf.vy = 120; leaf.perch = nil
            moving.append(leaf); woke = true
        }
        if woke { resting.removeAll { $0.swept }; pileDirty = true }
        for leaf in moving where leaf.swept {
            leaf.state = .air; leaf.vx = speed
            if leaf.vy < 40 { leaf.vy = 80 }
        }
    }

    func setBlow(on: Bool, origin: CGPoint, angle: CGFloat, power: CGFloat) {
        blowOn = on; blowOrigin = origin; blowAngle = angle; self.power = power
    }

    // MARK: - Step

    func advance(by dt: TimeInterval) {
        // Bounded substeps keep the jet and ground contact stable on slow frames.
        let count = max(1, Int(ceil(dt / (1.0 / 60))))
        let step = CGFloat(dt) / CGFloat(count)
        for _ in 0..<count { stepOnce(step) }
        canopy.advance(by: CGFloat(dt), gust: gust, direction: gustDir)
    }

    private func stepOnce(_ dt: CGFloat) {
        elapsed += dt
        // Rain down continuously; once the screen is mostly full the fall eases, and gusts or the
        // blower clearing leaves off-screen keep making room for it.
        if running, moving.count < maxActive {
            let fill = CGFloat(population) / CGFloat(maxTotal)
            spawnBudget += dt * ((fill < 0.75 ? leafRate : settledRate) + shakeRate * gust)
            while spawnBudget >= 1 { spawnBudget -= 1; if population < maxTotal { spawn() } }
        }
        updateGust(dt)
        if pileDirty { rebuildPile() }
        if blowOn { wakeFromBlower() }
        if gust > 0.1 { wakeFromGust(dt) }

        for leaf in moving {
            leaf.age += dt
            let force = beam(leaf.x, leaf.y)
            if leaf.state == .slide { applySlide(leaf, force, dt) } else { applyAir(leaf, force, dt) }
        }
        // `finished` drops a leaf from the moving list; only despawned (blown-off) leaves lose their
        // node — a leaf that just came to rest keeps its node and lives on in the pile.
        for leaf in moving where leaf.finished && leaf.state != .rest { leaf.node.removeFromParent() }
        moving.removeAll { $0.finished }
        if pileDirty { rebuildPile() }
    }

    private var population: Int { moving.count + resting.count }

    // MARK: - Spawning

    private func spawn() {
        let leaf = makeLeaf()
        // In a gust, a share of new leaves is shaken off the branches rather than falling from above.
        if gust > 0.15, CGFloat.random(in: 0...1) < 0.6, let spot = canopy.shedPoint() {
            leaf.x = spot.x; leaf.y = spot.y
            leaf.vx = gustDir * .random(in: 40...120); leaf.vy = -.random(in: 10...40)
        } else {
            leaf.x = .random(in: 0...size.width)
            leaf.y = size.height + 70
        }
        leaf.node.zPosition = 1
        layer.addChild(leaf.node)
        moving.append(leaf)
        drawMoving(leaf)
    }

    private func makeLeaf() -> Leaf {
        let leaf = Leaf()
        leaf.variant = Int.random(in: 0..<frames.count)
        leaf.speed = .random(in: 90...170)
        leaf.vy = -.random(in: 70...130)
        leaf.vx = .random(in: -12...12)
        leaf.sway = .random(in: 12...32)
        leaf.phase = .random(in: 0..<2 * .pi)
        leaf.baseSize = style == .retro ? 48 : .random(in: 36...58)
        leaf.spin = .random(in: -0.7...0.7)
        leaf.period = .random(in: 1...1.7)
        leaf.pose = style == .realistic ? leaf.variant % poses.count : Int.random(in: 0..<poses.count)
        leaf.usePose = CGFloat.random(in: 0...1) < 0.8
        leaf.mass = .random(in: 0.75...1.6)
        leaf.thickness = .random(in: 2.2...3.7)
        leaf.restAngle = .random(in: -0.32...0.32)
        leaf.node.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        return leaf
    }

    // MARK: - Pile surface

    private func surfaceAt(_ x: CGFloat) -> CGFloat {
        let pos = max(0, min(1, x / max(1, size.width))) * CGFloat(pileHeights.count - 1)
        let i = Int(pos), t = pos - CGFloat(i)
        return pileHeights[i] * (1 - t) + pileHeights[min(i + 1, pileHeights.count - 1)] * t
    }

    /// What the leaf rests on: its icon's drift, or the ground pile.
    private func supportUnder(_ leaf: Leaf) -> CGFloat {
        leaf.perch?.surface(leaf.x) ?? surfaceAt(leaf.x)
    }

    private func restDims(_ leaf: Leaf) -> CGSize {
        leaf.usePose
            ? CGSize(width: leaf.baseSize, height: leaf.baseSize * poseAspect[leaf.pose])
            : CGSize(width: leaf.baseSize, height: leaf.baseSize * 0.62)
    }

    private func restHalfHeight(_ leaf: Leaf) -> CGFloat {
        let d = restDims(leaf)
        return (abs(sin(leaf.restAngle)) * d.width + abs(cos(leaf.restAngle)) * d.height) * 0.46
    }

    private func putToRest(_ leaf: Leaf) {
        leaf.state = .rest; leaf.vx = 0; leaf.vy = 0; leaf.blown = false; leaf.adrift = false
        resting.append(leaf)
        pileDirty = true
    }

    private func rebuildPile() {
        pileHeights = [CGFloat](repeating: 0, count: pileHeights.count)
        restBuckets.removeAll()
        for perch in perches { perch.heights = perch.heights.map { _ in 0 }; perch.count = 0 }
        let step = size.width / CGFloat(pileHeights.count - 1)
        for leaf in resting {
            leaf.x = min(max(8, leaf.x), size.width - 8)
            if let perch = leaf.perch, let base = perch.surface(leaf.x) {
                leaf.support = base
                leaf.y = base + restHalfHeight(leaf)
                let reach = leaf.baseSize * 0.55
                for (i, top) in perch.tops.enumerated() where top != nil {
                    let weight = max(0, 1 - abs(perch.centre(i) - leaf.x) / reach)
                    perch.heights[i] += leaf.thickness * weight
                }
                perch.count += 1
                restBuckets[Int(leaf.x / 64), default: []].append(leaf)
                drawResting(leaf)
                continue
            }
            leaf.perch = nil
            leaf.support = surfaceAt(leaf.x)
            leaf.y = leaf.support + restHalfHeight(leaf)
            let reach = leaf.baseSize * 0.55
            let first = max(0, Int((leaf.x - reach) / step))
            let last = min(pileHeights.count - 1, Int(ceil((leaf.x + reach) / step)))
            if first <= last {
                for i in first...last {
                    let weight = max(0, 1 - abs(CGFloat(i) * step - leaf.x) / reach)
                    pileHeights[i] = min(maxPile, pileHeights[i] + leaf.thickness * weight)
                }
            }
            let bucket = Int(leaf.x / 64)
            restBuckets[bucket, default: []].append(leaf)
            drawResting(leaf)
        }
        pileDirty = false
    }

    // MARK: - Blower

    private func beam(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
        guard blowOn else { return 0 }
        let dx = x - blowOrigin.x, dy = y - blowOrigin.y
        let c = cos(blowAngle), s = sin(blowAngle)
        let along = dx * c + dy * s, cross = abs(-dx * s + dy * c)
        guard along >= 0, along <= blowerRange else { return 0 }
        let radius = coneBase + along * coneSlope
        guard cross <= radius else { return 0 }
        return pow(1 - along / blowerRange, 0.65) * pow(1 - cross / radius, 0.9) * power
    }

    private func wakeFromBlower() {
        guard moving.count < maxActive else { return }
        let tipX = blowOrigin.x + cos(blowAngle) * blowerRange, margin = blowerRange * 0.4 + 20
        let first = Int((min(blowOrigin.x, tipX) - margin) / 64)
        let last = Int(ceil((max(blowOrigin.x, tipX) + margin) / 64))
        var woken: [Leaf] = []
        var allowance = min(16, maxActive - moving.count)
        for bucket in first...last where allowance > 0 {
            guard let candidates = restBuckets[bucket] else { continue }
            for leaf in candidates.reversed() where allowance > 0 {
                let force = beam(leaf.x, leaf.y)
                let burial = max(0, supportUnder(leaf) - leaf.support - leaf.thickness)
                if force <= 0.09 + leaf.mass * 0.055 + burial * 0.018 { continue }
                // Off an icon there is no ground to slide along: it is blown into the air.
                leaf.state = force > 0.36 || leaf.perch != nil ? .air : .slide
                leaf.perch = nil
                leaf.blown = true; leaf.finished = false
                leaf.vx = cos(blowAngle) * (60 + force * 210) / leaf.mass
                leaf.vy = leaf.state == .air ? max(45, 45 + force * 135 + sin(blowAngle) * 120) : 0
                leaf.age = 0
                moving.append(leaf); woken.append(leaf); allowance -= 1
            }
        }
        if !woken.isEmpty {
            let set = Set(woken.map { ObjectIdentifier($0) })
            resting.removeAll { set.contains(ObjectIdentifier($0)) }
            pileDirty = true
        }
    }

    // MARK: - Gusts

    private func updateGust(_ dt: CGFloat) {
        guard running else { gust = 0; gustLength = 0; return }
        if gustLength == 0 {
            nextGust -= dt
            guard nextGust <= 0 else { return }
            gustDir = Bool.random() ? 1 : -1
            gustLength = .random(in: 2.5...4.5)
            gustPeak = .random(in: 0.55...1)
            gustTime = 0
            onGust?(gustLength, gustPeak, gustDir)
        }
        gustTime += dt
        let p = gustTime / gustLength
        if p >= 1 { gust = 0; gustLength = 0; nextGust = .random(in: 4...9); return }
        gust = gustPeak * pow(sin(.pi * p), 2)
    }

    /// The gust at a point: a ripple rolling downwind, so leaves don't all move in lockstep.
    private func gustAt(_ x: CGFloat) -> CGFloat {
        gust * (0.65 + 0.35 * sin(x * 0.006 - elapsed * 2.4 * gustDir))
    }

    /// Lifts or slides exposed leaves off the top of the pile; downwind they leave the screen.
    private func wakeFromGust(_ dt: CGFloat) {
        var allowance = min(6, maxActive - moving.count)
        guard allowance > 0 else { return }
        var woken: [Leaf] = []
        for leaf in resting.shuffled() where allowance > 0 {
            let burial = supportUnder(leaf) - leaf.support - leaf.thickness
            guard burial < 5 else { continue }
            let g = gustAt(leaf.x)
            guard CGFloat.random(in: 0...1) < g * 0.9 / leaf.mass * dt * 8 else { continue }
            leaf.state = CGFloat.random(in: 0...1) < g || leaf.perch != nil ? .air : .slide
            leaf.perch = nil
            leaf.blown = true; leaf.finished = false
            leaf.vx = gustDir * (220 + g * 380) * .random(in: 0.5...1.3) / leaf.mass
            leaf.vy = leaf.state == .air ? (90 + g * 180) * .random(in: 0.4...1.4) : 0
            leaf.spin = .random(in: -2...2)
            leaf.age = 0
            moving.append(leaf); woken.append(leaf); allowance -= 1
        }
        if !woken.isEmpty {
            let set = Set(woken.map { ObjectIdentifier($0) })
            resting.removeAll { set.contains(ObjectIdentifier($0)) }
            pileDirty = true
        }
    }

    // MARK: - Motion (y-up: gravity pulls down, lift pushes up)

    private func applyAir(_ leaf: Leaf, _ force: CGFloat, _ dt: CGFloat) {
        if force > 0 {
            leaf.blown = true
            leaf.vx += cos(blowAngle) * 1450 * force / leaf.mass * dt
            leaf.vy += (sin(blowAngle) * 1050 + 520) * force / leaf.mass * dt
            leaf.spin += sin(leaf.phase + elapsed * 4) * force * dt * 3
        }
        let wind = gustAt(leaf.x)
        if wind > 0 {
            leaf.vx += gustDir * 380 * wind / leaf.mass * dt
            leaf.vy += 50 * wind * dt
            if wind > 0.05 { leaf.adrift = true }
        }
        leaf.vy -= (leaf.blown ? 200 : 70) * dt
        leaf.vx *= exp(-(leaf.blown ? 0.85 : 0.6) * dt)
        if !leaf.blown { leaf.vy = max(leaf.vy, -leaf.speed) }
        leaf.vx = max(-650, min(650, leaf.vx))
        leaf.vy = max(-350, min(450, leaf.vy))
        leaf.x += leaf.vx * dt + cos(leaf.age * 1.7 + leaf.phase) * leaf.sway * 1.7 * dt * (leaf.blown ? 0.15 : 1)
        leaf.y += leaf.vy * dt

        if leaf.y > size.height + 120 { leaf.y = size.height + 120; leaf.vy = -abs(leaf.vy) * 0.2 }
        // Blown and gust-carried leaves are allowed off the edges and despawn; ambient leaves stay on screen.
        if leaf.blown || leaf.adrift, leaf.x < -60 || leaf.x > size.width + 60 || leaf.y > size.height + 280 {
            leaf.finished = true; return
        }
        if !leaf.blown && !leaf.adrift {
            if leaf.x < 6 { leaf.x = 6; leaf.vx = abs(leaf.vx) * 0.25 }
            if leaf.x > size.width - 6 { leaf.x = size.width - 6; leaf.vx = -abs(leaf.vx) * 0.25 }
        }
        if leaf.vy <= 0, settleOnIcon(leaf, dt) { return }
        let floor = surfaceAt(leaf.x)
        if leaf.vy <= 0, leaf.y - restHalfHeight(leaf) <= floor {
            leaf.y = floor + restHalfHeight(leaf); leaf.vy = 0
            if abs(leaf.vx) > 24 { leaf.state = .slide } else { putToRest(leaf); leaf.finished = true }
        }
        drawMoving(leaf)
    }

    /// Lands a falling leaf on an icon whose top edge it just passed, unless that icon is full or
    /// too steep there.
    private func settleOnIcon(_ leaf: Leaf, _ dt: CGFloat) -> Bool {
        let bottom = leaf.y - restHalfHeight(leaf), before = bottom - leaf.vy * dt
        for perch in perches {
            guard let top = perch.surface(leaf.x), bottom <= top, before >= top - 0.5,
                  perch.count < perch.ledge.capacity, let i = perch.column(leaf.x), perch.heights[i] < perchMaxHeight
            else { continue }
            let slope = perch.slope(leaf.x)
            guard abs(slope) < perchMaxSlope else { continue }
            leaf.restAngle = atan(slope) + .random(in: -0.12...0.12)
            leaf.perch = perch
            perch.count += 1
            leaf.y = top + restHalfHeight(leaf)
            putToRest(leaf); leaf.finished = true
            return true
        }
        return false
    }

    private func applySlide(_ leaf: Leaf, _ force: CGFloat, _ dt: CGFloat) {
        let wind = gustAt(leaf.x)
        if wind > 0.05 { leaf.adrift = true }
        leaf.vx += (cos(blowAngle) * 900 * force + gustDir * 600 * wind) / leaf.mass * dt
        if force > 0.34 { leaf.state = .air; leaf.blown = true; leaf.vy = 90 + force * 100; return }
        leaf.vx *= exp(-5 * dt)
        leaf.x += leaf.vx * dt
        let offScreen = leaf.x < 0 || leaf.x > size.width
        if leaf.blown || leaf.adrift {
            // Free to slide off the edge; one that stops out of view is gone rather than clamped back.
            if leaf.x < -40 || leaf.x > size.width + 40 || (offScreen && abs(leaf.vx) < 12) { leaf.finished = true; return }
        } else {
            leaf.x = min(max(8, leaf.x), size.width - 8)
        }
        leaf.y = surfaceAt(leaf.x) + restHalfHeight(leaf)
        if abs(leaf.vx) < 12, force < 0.1 { putToRest(leaf); leaf.finished = true } else { drawResting(leaf) }
    }

    // MARK: - Drawing (the node follows the leaf's state)

    private func retroTilt(_ leaf: Leaf) -> CGFloat {
        let a = leaf.restAngle * 0.2 + 0.24 * sin(leaf.age * 1.65 + leaf.phase) + 0.055 * sin(leaf.age * 3.1 + leaf.phase * 0.7)
        let step = CGFloat.pi / 60
        return (a / step).rounded() * step
    }

    private func drawMoving(_ leaf: Leaf) {
        let index = style == .realistic ? leaf.variant : Int(leaf.age / leaf.period * 8 + leaf.phase) % frames.count
        leaf.node.texture = frames[(index % frames.count + frames.count) % frames.count]
        // SpriteKit's `size` includes the scale, so the tumble squash is cleared before sizing.
        leaf.node.xScale = 1; leaf.node.yScale = 1
        leaf.node.size = CGSize(width: leaf.baseSize, height: leaf.baseSize)
        if style == .realistic {
            leaf.node.zRotation = leaf.spin * leaf.age + 0.18 * sin(leaf.age * 2 + leaf.phase)
            leaf.node.xScale = 0.35 + 0.65 * abs(cos(leaf.age * 2 + leaf.phase))
            leaf.node.position = CGPoint(x: leaf.x, y: leaf.y)
        } else {
            leaf.node.zRotation = retroTilt(leaf) + (leaf.blown ? (leaf.spin * leaf.age * 10).rounded() / 10 : 0)
            leaf.node.position = CGPoint(x: leaf.x.rounded(), y: leaf.y.rounded())
        }
    }

    private func drawResting(_ leaf: Leaf) {
        if leaf.usePose {
            leaf.node.texture = poses[leaf.pose]
        } else {
            leaf.node.texture = frames[style == .retro ? (leaf.variant % 2 != 0 ? 0 : min(4, frames.count - 1)) : leaf.variant]
        }
        leaf.node.xScale = 1; leaf.node.yScale = 1
        leaf.node.size = restDims(leaf)
        leaf.node.zRotation = leaf.restAngle
        leaf.node.position = style == .retro ? CGPoint(x: leaf.x.rounded(), y: leaf.y.rounded()) : CGPoint(x: leaf.x, y: leaf.y)
    }
}
