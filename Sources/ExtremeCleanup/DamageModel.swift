import CoreGraphics

/// Damage accumulates at sites: a hit within `mergeRadius` of a site adds to it, a hit farther away
/// opens a new one. A hit that reaches several sites fuses them into one.
struct DamageModel {
    struct Site {
        let id: Int
        var centre: CGPoint
        var damage: Double
        var stage: Stage { Stage(damage: damage) }
    }

    enum Stage: Int, Comparable {
        case intact, crack, bigCrack, shattered
        init(damage: Double) {
            // Rounds deal fractional damage; their sum must still reach a whole stage exactly.
            switch damage + 1e-9 {
            case ..<1: self = .intact
            case ..<2: self = .crack
            case ..<3: self = .bigCrack
            default: self = .shattered
            }
        }
        static func < (a: Stage, b: Stage) -> Bool { a.rawValue < b.rawValue }
    }

    struct HitResult {
        let site: Site
        let previousStage: Stage
        let previousDamage: Double
        /// Sites absorbed into `site` by this hit.
        let merged: [Int]
    }

    var mergeRadius: CGFloat = 60
    /// How far a site's centre moves toward a full-strength hit, as a fraction of the distance. Weaker hits
    /// pull less, so a sweep of rounds breaks into separate sites instead of dragging one along.
    var drift: CGFloat = 0.25
    private(set) var sites: [Site] = []
    private var nextID = 0

    mutating func hit(at point: CGPoint, amount: Double) -> HitResult {
        let near = sites.indices.filter { sites[$0].centre.distance(to: point) <= mergeRadius }
        guard !near.isEmpty else {
            let site = Site(id: nextID, centre: point, damage: amount)
            nextID += 1
            sites.append(site)
            return HitResult(site: site, previousStage: .intact, previousDamage: 0, merged: [])
        }

        let group = near.map { sites[$0] }
        let total = group.reduce(0) { $0 + $1.damage }
        let weighted = group.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.centre.x * $1.damage, y: $0.y + $1.centre.y * $1.damage) }
        let previous = group.map(\.stage).max() ?? .intact
        let keeper = group.max { $0.damage < $1.damage }!

        var site = keeper
        site.centre = CGPoint(x: weighted.x / total, y: weighted.y / total)
        site.centre = site.centre.moved(toward: point, by: drift * CGFloat(min(amount, 1)))
        site.damage = total + amount

        let mergedIDs = group.map(\.id).filter { $0 != keeper.id }
        sites.removeAll { s in group.contains { $0.id == s.id } }
        sites.append(site)
        return HitResult(site: site, previousStage: previous, previousDamage: total, merged: mergedIDs)
    }
}

extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat { hypot(x - other.x, y - other.y) }
    func moved(toward other: CGPoint, by fraction: CGFloat) -> CGPoint {
        CGPoint(x: x + (other.x - x) * fraction, y: y + (other.y - y) * fraction)
    }
}
