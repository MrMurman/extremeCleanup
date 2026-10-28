import CoreGraphics
import Foundation

/// Deterministic randomness, so a site's cracks keep their shape as they grow.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64
    init(seed: Int) { state = UInt64(truncatingIfNeeded: seed) &* 0x9E37_79B9_7F4A_7C15 | 1 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func range(_ r: ClosedRange<CGFloat>) -> CGFloat { CGFloat.random(in: r, using: &self) }
}

enum CrackArt {
    /// Radial cracks around `centre`; a bigger `reach` adds longer rays and ring fractures.
    static func cracks(around centre: CGPoint, reach: CGFloat, rings: Bool, seed: Int) -> CGPath {
        var rng = SeededRandom(seed: seed)
        let path = CGMutablePath()
        let rayCount = Int(rng.range(6...9))
        var ringPoints: [[CGPoint]] = []
        for i in 0..<rayCount {
            var angle = CGFloat(i) / CGFloat(rayCount) * 2 * .pi + rng.range(-0.3...0.3)
            let length = reach * rng.range(0.55...1.0)
            var point = centre
            var ray = [point]
            path.move(to: point)
            let steps = 5
            for _ in 0..<steps {
                angle += rng.range(-0.35...0.35)
                let step = length / CGFloat(steps) * rng.range(0.7...1.3)
                point = CGPoint(x: point.x + cos(angle) * step, y: point.y + sin(angle) * step)
                path.addLine(to: point)
                ray.append(point)
            }
            ringPoints.append(ray)
            // An occasional side branch off the middle of the ray.
            if rng.range(0...1) < 0.5 {
                let from = ray[2]
                let branch = angle + rng.range(-1.0...1.0)
                path.move(to: from)
                path.addLine(to: CGPoint(x: from.x + cos(branch) * length * 0.35, y: from.y + sin(branch) * length * 0.35))
            }
        }
        if rings {
            for level in [2, 4] {
                for i in 0..<ringPoints.count where rng.range(0...1) < 0.75 {
                    let a = ringPoints[i][level], b = ringPoints[(i + 1) % ringPoints.count][level]
                    let mid = CGPoint(x: (a.x + b.x) / 2 + rng.range(-4...4), y: (a.y + b.y) / 2 + rng.range(-4...4))
                    path.move(to: a)
                    path.addLine(to: mid)
                    path.addLine(to: b)
                }
            }
        }
        return path
    }

    /// An irregular polygon outlining a hole.
    static func hole(around centre: CGPoint, radius: CGFloat, seed: Int) -> [CGPoint] {
        var rng = SeededRandom(seed: seed &+ 7919)
        let count = 13
        return (0..<count).map { i in
            let angle = CGFloat(i) / CGFloat(count) * 2 * .pi + rng.range(-0.15...0.15)
            let r = radius * rng.range(0.72...1.15)
            return CGPoint(x: centre.x + cos(angle) * r, y: centre.y + sin(angle) * r)
        }
    }

    /// Splits a hole polygon into convex triangles fanning out from a point near its centre.
    static func shards(of polygon: [CGPoint], centre: CGPoint, seed: Int) -> [[CGPoint]] {
        var rng = SeededRandom(seed: seed &+ 104_729)
        let hub = CGPoint(x: centre.x + rng.range(-6...6), y: centre.y + rng.range(-6...6))
        var triangles: [[CGPoint]] = []
        for i in polygon.indices {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            let t = rng.range(0.35...0.65)
            let split = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            triangles.append([hub, a, split])
            triangles.append([hub, split, b])
        }
        return triangles.map(counterClockwise)
    }

    private static func counterClockwise(_ points: [CGPoint]) -> [CGPoint] {
        var area: CGFloat = 0
        for i in points.indices {
            let p = points[i], q = points[(i + 1) % points.count]
            area += p.x * q.y - q.x * p.y
        }
        return area >= 0 ? points : points.reversed()
    }
}
