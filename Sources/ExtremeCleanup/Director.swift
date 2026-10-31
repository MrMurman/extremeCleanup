import AppKit

/// A take written down as timed beats, so the same action can be filmed again and again.
///
/// Positions are on the stage: the 9:16 column at the right edge of the main display, which is what a vertical
/// video crops. `[x, y]` are fractions of the stage from its top-left corner; `{"icon": name, "dx": …, "dy": …}`
/// is the middle of a desktop icon's tile, nudged by stage fractions; `{"belt": 2}` and `{"belt": "broom"}` are a pocket
/// and the broom charm on the toolbelt, so a take can pick a tool or start the sweep with a visible click.
struct Choreography: Decodable {
    enum Action: String, Decodable { case move, press, fire, tool, sweep, mark, end }
    enum Ease: String, Decodable { case linear, inOut }

    enum Target: Decodable {
        case point(x: Double, y: Double)
        case icon(name: String, dx: Double, dy: Double)
        case pocket(Int)
        case broom

        private enum Keys: String, CodingKey { case icon, dx, dy, belt }

        init(from decoder: Decoder) throws {
            if var list = try? decoder.unkeyedContainer() {
                self = .point(x: try list.decode(Double.self), y: try list.decode(Double.self))
                return
            }
            let keyed = try decoder.container(keyedBy: Keys.self)
            if keyed.contains(.belt) {
                self = (try? keyed.decode(Int.self, forKey: .belt)).map(Target.pocket) ?? .broom
                return
            }
            self = .icon(name: try keyed.decode(String.self, forKey: .icon),
                         dx: try keyed.decodeIfPresent(Double.self, forKey: .dx) ?? 0,
                         dy: try keyed.decodeIfPresent(Double.self, forKey: .dy) ?? 0)
        }
    }

    /// A point on a firing path, and how long the aim rests there: `[x, y, hold]` or `{"icon": …, "hold": …}`.
    struct Stop: Decodable {
        let target: Target
        let hold: Double

        private enum Keys: String, CodingKey { case hold }

        init(from decoder: Decoder) throws {
            target = try Target(from: decoder)
            if var list = try? decoder.unkeyedContainer() {
                _ = try list.decode(Double.self)
                _ = try list.decode(Double.self)
                hold = list.isAtEnd ? 0 : try list.decode(Double.self)
            } else {
                hold = try decoder.container(keyedBy: Keys.self).decodeIfPresent(Double.self, forKey: .hold) ?? 0
            }
        }
    }

    struct Beat: Decodable {
        let at: Double
        let action: Action
        let to: Target?
        let path: [Stop]?
        let duration: Double?
        let ease: Ease?
        let tool: String?
        let name: String?

        private enum CodingKeys: String, CodingKey {
            case at, action = "do", to, path, duration = "for", ease, tool, name
        }
    }

    /// Sound effects and music for the take, whatever the launcher last saved.
    let sound: Bool
    let music: Bool
    /// Where the tool stands when the scene opens.
    let start: Target
    /// Played straight away, before Space: preparation the video doesn't need, such as pre-cracking a spot.
    let setup: [Beat]
    /// Played after Space, timed from that press.
    let beats: [Beat]

    static func load(_ file: URL) throws -> Choreography {
        try JSONDecoder().decode(Choreography.self, from: Data(contentsOf: file))
    }
}

@MainActor
final class Director {
    struct Entry: Encodable {
        let action: String
        let name: String?
        let planned: Double
        let actual: Double
    }

    struct Log: Encodable {
        let file: String
        let beats: [Entry]
        let shatters: Int
        let roundsFired: Int
        let iconsDropped: Int
        let creaturesReleased: Int
        let worstFPS: Double
        let maxDriftMs: Double
        /// The take's movie, and how far into it the beats' time zero falls.
        let video: String?
        let videoOffset: Double?
        /// Set when finishing the movie reported a problem; the movie on disk may still be complete.
        let filmingError: String?
    }

    enum Failure: Error, CustomStringConvertible {
        case unknownIcon(String, available: [String])
        case unknownTool(String)
        case noBelt(String)
        case missing(String, in: Choreography.Action)

        var description: String {
            switch self {
            case let .unknownIcon(name, available):
                "no desktop icon named \"\(name)\"; on the desktop: \(available.joined(separator: ", "))"
            case let .unknownTool(name): "unknown tool \"\(name)\"; use hammer or minigun"
            case let .noBelt(what): "\(what) is not on the toolbelt here"
            case let .missing(field, action): "a \(action.rawValue) beat needs \"\(field)\""
            }
        }
    }

    private let choreography: Choreography
    private let file: URL
    private let scene: DeskScene
    private let screen: NSScreen
    private let icons: [DesktopIcon]
    private let select: (DeskScene.Tool) -> Void
    private var go: CheckedContinuation<Void, Never>?
    private let tick = Duration.milliseconds(4)

    init(_ choreography: Choreography, from file: URL, scene: DeskScene, screen: NSScreen, icons: [DesktopIcon],
         select: @escaping (DeskScene.Tool) -> Void) throws {
        self.choreography = choreography
        self.file = file
        self.scene = scene
        self.screen = screen
        self.icons = icons
        self.select = select
        // Every target and tool is checked up front, so a typo fails before the take rather than in the middle of it.
        _ = try point(choreography.start)
        for beat in choreography.setup + choreography.beats { try validate(beat) }
    }

    /// Space: start the take.
    func start() {
        go?.resume()
        go = nil
    }

    /// Plays the setup, waits for Space, then plays the take, filming it (macOS 15 and later) next to the choreography
    /// as `<file>.take-<time>.mov` and logging it to `<file>.log-<time>.json`.
    func run() async throws -> URL {
        scene.scriptedPointer = try point(choreography.start)
        try? await Task.sleep(for: .seconds(1))
        _ = try await play(choreography.setup)
        await withCheckedContinuation { go = $0 }
        let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "")
        let base = file.deletingPathExtension()
        var video: URL?
        var filmingSince: ContinuousClock.Instant?
        var stopFilming: (() async throws -> Void)?
        if #available(macOS 15, *) {
            let recorder = TakeRecorder()
            let url = base.appendingPathExtension("take-\(stamp).mov")
            filmingSince = try await recorder.start(screen: screen, stage: stage, to: url)
            video = url
            stopFilming = recorder.stop
            // A little stillness on both ends gives the edit room to cut.
            try? await Task.sleep(for: .seconds(1))
        }
        let (origin, entries) = try await play(choreography.beats)
        var filmingError: String?
        if let stopFilming {
            try? await Task.sleep(for: .seconds(1))
            do { try await stopFilming() } catch { filmingError = "\(error)" }
        }
        let log = Log(file: file.lastPathComponent, beats: entries, shatters: scene.shatters,
                      roundsFired: scene.roundsFired, iconsDropped: scene.iconsDropped,
                      creaturesReleased: scene.creaturesReleased,
                      worstFPS: scene.worstFPS.isFinite ? scene.worstFPS : 0,
                      maxDriftMs: (entries.map { abs($0.actual - $0.planned) }.max() ?? 0) * 1000,
                      video: video?.lastPathComponent, videoOffset: filmingSince.map { (origin - $0).inSeconds },
                      filmingError: filmingError)
        let url = base.appendingPathExtension("log-\(stamp).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(log).write(to: url)
        return url
    }

    private func play(_ beats: [Choreography.Beat]) async throws -> (ContinuousClock.Instant, [Entry]) {
        let clock = ContinuousClock()
        let origin = clock.now
        var entries: [Entry] = []
        var running: [Task<Void, Never>] = []
        scene.resetFrameStats()
        for beat in beats.sorted(by: { $0.at < $1.at }) {
            try? await clock.sleep(until: origin + .seconds(beat.at), tolerance: .zero)
            let elapsed = clock.now - origin
            entries.append(Entry(action: beat.action.rawValue, name: beat.name, planned: beat.at,
                                 actual: elapsed.inSeconds))
            switch beat.action {
            case .move:
                let to = try point(beat.to!)
                running.append(Task { await self.move(to: to, over: beat.duration ?? 0.5, ease: beat.ease ?? .inOut) })
            case .press:
                if let target = beat.to { scene.scriptedPointer = try point(target) }
                if let at = scene.scriptedPointer { scene.press(at: at) }
            case .fire:
                let stops = try beat.path!.map { (point: try point($0.target), hold: $0.hold) }
                running.append(Task { await self.fire(along: stops, over: beat.duration!) })
            case .tool:
                select(try tool(beat.tool!))
            case .sweep:
                scene.sweep()
            case .mark, .end:
                break
            }
        }
        for task in running { await task.value }
        return (origin, entries)
    }

    private func move(to end: CGPoint, over seconds: Double, ease: Choreography.Ease) async {
        let begin = scene.scriptedPointer ?? end
        let clock = ContinuousClock()
        let origin = clock.now
        while true {
            let elapsed = clock.now - origin
            let t = min(1, elapsed.inSeconds / seconds)
            let k = ease == .linear ? t : t * t * (3 - 2 * t)
            scene.scriptedPointer = begin.moved(toward: end, by: CGFloat(k))
            if t >= 1 { return }
            try? await Task.sleep(for: tick)
        }
    }

    /// Holds the trigger along the path: the aim rests on each stop for its hold, and travels between stops at an
    /// even speed in the time the holds leave. Glass gives way only where rounds land together, so holds shatter it.
    private func fire(along stops: [(point: CGPoint, hold: Double)], over seconds: Double) async {
        guard let first = stops.first?.point, let last = stops.last?.point else { return }
        let legs = zip(stops, stops.dropFirst()).map { hypot($1.point.x - $0.point.x, $1.point.y - $0.point.y) }
        let travel = max(seconds - stops.map(\.hold).reduce(0, +), 0)
        let length = max(legs.reduce(0, +), 1)
        var segments: [(from: CGPoint, to: CGPoint, duration: Double)] = []
        for (i, stop) in stops.enumerated() {
            if stop.hold > 0 { segments.append((stop.point, stop.point, stop.hold)) }
            if i < legs.count { segments.append((stop.point, stops[i + 1].point, travel * legs[i] / length)) }
        }
        let total = segments.map(\.duration).reduce(0, +)
        scene.scriptedPointer = first
        scene.startFiring(at: first)
        let clock = ContinuousClock()
        let origin = clock.now
        while true {
            let elapsed = (clock.now - origin).inSeconds
            var left = elapsed, aim = last
            for segment in segments {
                if left <= segment.duration {
                    let k = segment.duration > 0 ? CGFloat(left / segment.duration) : 1
                    aim = segment.from.moved(toward: segment.to, by: k)
                    break
                }
                left -= segment.duration
            }
            scene.scriptedPointer = aim
            scene.aim(at: aim)
            if elapsed >= total { break }
            try? await Task.sleep(for: tick)
        }
        scene.stopFiring()
    }

    private func validate(_ beat: Choreography.Beat) throws {
        switch beat.action {
        case .move:
            guard let to = beat.to else { throw Failure.missing("to", in: .move) }
            _ = try point(to)
        case .press:
            if let to = beat.to { _ = try point(to) }
        case .fire:
            guard let path = beat.path, !path.isEmpty else { throw Failure.missing("path", in: .fire) }
            guard beat.duration != nil else { throw Failure.missing("for", in: .fire) }
            _ = try path.map { try point($0.target) }
        case .tool:
            guard let name = beat.tool else { throw Failure.missing("tool", in: .tool) }
            _ = try tool(name)
        case .sweep, .mark, .end:
            break
        }
    }

    private func tool(_ name: String) throws -> DeskScene.Tool {
        switch name.lowercased() {
        case "hammer": .hammer
        case "minigun": .minigun
        default: throw Failure.unknownTool(name)
        }
    }

    /// The 9:16 column at the right edge of the display, in scene coordinates.
    private var stage: CGRect {
        let width = scene.size.height * 9 / 16
        return CGRect(x: scene.size.width - width, y: 0, width: width, height: scene.size.height)
    }

    /// A target in scene coordinates.
    private func point(_ target: Choreography.Target) throws -> CGPoint {
        let stage = stage
        switch target {
        case let .point(x, y):
            return CGPoint(x: stage.minX + CGFloat(x) * stage.width, y: stage.maxY - CGFloat(y) * stage.height)
        case let .icon(name, dx, dy):
            guard let icon = icons.first(where: { $0.name == name }) else {
                throw Failure.unknownIcon(name, available: icons.map(\.name))
            }
            let tile = icon.tile.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
            return CGPoint(x: tile.midX + CGFloat(dx) * stage.width, y: tile.midY - CGFloat(dy) * stage.height)
        case let .pocket(number):
            let pockets = scene.beltPockets
            guard pockets.indices.contains(number - 1) else { throw Failure.noBelt("pocket \(number)") }
            return pockets[number - 1]
        case .broom:
            guard let charm = scene.beltCharm else { throw Failure.noBelt("the broom") }
            return charm
        }
    }
}

private extension Duration {
    var inSeconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}
