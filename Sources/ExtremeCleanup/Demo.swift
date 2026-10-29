import AppKit
import ScreenCaptureKit

/// Scripted runs that drive the toy without a mouse and record what the screen showed.
@MainActor
enum Demo {
    static func hammer(scene: DeskScene, screen: NSScreen, into dir: URL) async {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var report = ""
        let a = CGPoint(x: scene.size.width * 0.5, y: scene.size.height * 0.55)

        try? await Task.sleep(for: .seconds(0.5))
        for click in 1...3 {
            scene.hammer(at: a)
            try? await Task.sleep(for: .seconds(click == 3 ? 1.2 : 0.4))
            await capture(screen, to: dir.appendingPathComponent("1-click\(click).png"))
        }

        // Two separate sites 90 pt apart, then a hit between them fuses both into a shatter.
        let left = CGPoint(x: scene.size.width * 0.2, y: scene.size.height * 0.55)
        let right = CGPoint(x: left.x + 90, y: left.y)
        scene.hammer(at: left)
        scene.hammer(at: right)
        try? await Task.sleep(for: .seconds(0.4))
        await capture(screen, to: dir.appendingPathComponent("2-two-sites.png"))
        scene.hammer(at: CGPoint(x: left.x + 45, y: left.y))
        try? await Task.sleep(for: .seconds(1.2))
        await capture(screen, to: dir.appendingPathComponent("3-merged-shatter.png"))

        // Sustained hammering: 10 hits a second across the screen.
        scene.resetFrameStats()
        for _ in 0..<150 {
            scene.hammer(at: CGPoint(x: .random(in: 40...(scene.size.width - 40)),
                                     y: .random(in: 80...(scene.size.height - 40))))
            try? await Task.sleep(for: .seconds(0.1))
        }
        try? await Task.sleep(for: .seconds(1))
        await capture(screen, to: dir.appendingPathComponent("4-after-barrage.png"))
        report += String(format: "worst 1-s fps during 15 s barrage: %.1f\n", scene.worstFPS)
        report += "display max fps: \(screen.maximumFramesPerSecond)\n"
        try? report.write(to: dir.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
    }

    static func minigun(scene: DeskScene, screen: NSScreen, into dir: URL) async {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let w = scene.size.width, h = scene.size.height
        var report = ""
        try? await Task.sleep(for: .seconds(1.5))

        let held = await roundsToShatter(scene, at: CGPoint(x: w * 0.5, y: h * 0.6))
        report += "held on one spot: shattered after \(held) rounds\n"
        try? await Task.sleep(for: .seconds(1))
        await capture(screen, to: dir.appendingPathComponent("1-held.png"))

        let spot = CGPoint(x: w * 0.2, y: h * 0.6)
        scene.hammer(at: spot)
        try? await Task.sleep(for: .seconds(0.3))
        let mixed = await roundsToShatter(scene, at: spot)
        report += "1 hammer hit + \(mixed) rounds: shattered\n"
        try? await Task.sleep(for: .seconds(1))
        await capture(screen, to: dir.appendingPathComponent("2-mixed.png"))

        for (name, y, seconds) in [("fast", h * 0.3, 1.2), ("slow", h * 0.42, 3.0)] {
            let shattersBefore = scene.shatters, roundsBefore = scene.roundsFired
            await sweep(scene, from: CGPoint(x: 60, y: y), to: CGPoint(x: w - 60, y: y), seconds: seconds)
            report += "\(name) sweep (\(Int((w - 120) / seconds)) pt/s): \(scene.roundsFired - roundsBefore) rounds, "
                + "\(scene.shatters - shattersBefore) shatters\n"
        }
        try? await Task.sleep(for: .seconds(0.5))
        await capture(screen, to: dir.appendingPathComponent("3-sweeps.png"))

        // Continuous fire for 30 s, aim wandering over the whole screen.
        scene.resetFrameStats()
        let roundsBefore = scene.roundsFired
        scene.startFiring(at: CGPoint(x: w / 2, y: h / 2))
        let start = Date()
        while Date().timeIntervalSince(start) < 30 {
            let t = CGFloat(Date().timeIntervalSince(start))
            scene.aim(at: CGPoint(x: w / 2 + w * 0.4 * sin(t * 0.7), y: h / 2 + h * 0.35 * sin(t * 1.1)))
            try? await Task.sleep(for: .milliseconds(10))
        }
        scene.stopFiring()
        try? await Task.sleep(for: .seconds(1))
        await capture(screen, to: dir.appendingPathComponent("4-after-30s.png"))
        report += String(format: "30 s continuous fire: %d rounds, worst 1-s fps %.1f (display max %d)\n",
                         scene.roundsFired - roundsBefore, scene.worstFPS, screen.maximumFramesPerSecond)
        try? report.write(to: dir.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
    }

    static func void(scene: DeskScene, screen: NSScreen, into dir: URL) async {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let w = scene.size.width, h = scene.size.height
        try? await Task.sleep(for: .seconds(1.5))

        // Five separate holes, then two holes close enough to overlap into one opening.
        var probes = [(0.15, 0.62), (0.38, 0.7), (0.62, 0.62), (0.85, 0.7), (0.3, 0.32)]
            .map { CGPoint(x: w * $0.0, y: h * $0.1) }
        let pair = (CGPoint(x: w * 0.62, y: h * 0.32), CGPoint(x: w * 0.62 + 95, y: h * 0.32))
        for point in probes + [pair.0, pair.1] {
            for _ in 0..<3 {
                scene.hammer(at: point)
                try? await Task.sleep(for: .seconds(0.12))
            }
        }
        probes.append(pair.0.moved(toward: pair.1, by: 0.5))  // the seam between the merged pair

        // Growing a hole breaks away the glass its tendrils cling to, so they turn into creatures.
        for _ in 0..<2 {
            scene.hammer(at: probes[1])
            try? await Task.sleep(for: .seconds(0.3))
        }
        try? await Task.sleep(for: .seconds(2.5))
        await capture(screen, to: dir.appendingPathComponent("0-creatures.png"))

        scene.resetFrameStats()
        let first = await snapshot(screen), wait = 0.5
        try? await Task.sleep(for: .seconds(wait))
        let second = await snapshot(screen)
        // Sweep the gaze around the screen so the layers shift against each other.
        let start = Date()
        while Date().timeIntervalSince(start) < 14 {
            let t = CGFloat(Date().timeIntervalSince(start))
            scene.lookToward(CGPoint(x: w / 2 + w / 2 * cos(t * 0.9), y: h / 2 + h / 2 * sin(t * 0.9)))
            try? await Task.sleep(for: .milliseconds(10))
        }

        var report = ""
        if let first, let second {
            write(first, to: dir.appendingPathComponent("1-void.png"))
            write(second, to: dir.appendingPathComponent("2-void-later.png"))
            for (i, probe) in probes.enumerated() {
                let a = sample(first, at: probe, in: scene.size), b = sample(second, at: probe, in: scene.size)
                let change = zip(a, b).map { abs($0 - $1) }.reduce(0, +) / Double(a.count)
                report += String(format: "%@ %d at (%.0f, %.0f): brightness %.1f, change over %.1f s %.2f\n",
                                 i == probes.count - 1 ? "seam" : "hole", i + 1, probe.x, probe.y,
                                 a.reduce(0, +) / Double(a.count), wait, change)
            }
        } else {
            report += "capture failed\n"
        }
        report += "creatures released: \(scene.creaturesReleased)\n"
        report += String(format: "worst 1-s fps over 15 s with %d holes open: %.1f (display max %d)\n",
                         probes.count + 1, scene.worstFPS, screen.maximumFramesPerSecond)
        try? report.write(to: dir.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
    }

    private static func snapshot(_ screen: NSScreen) async -> CGImage? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let display = content.displays.first(where: { $0.displayID == Snapshot.displayID(of: screen) })
        else { return nil }
        return try? await Snapshot.capture(display)
    }

    /// Per-pixel brightness (0–255) of a 16×16 pt box around a scene point.
    private static func sample(_ image: CGImage, at point: CGPoint, in size: CGSize) -> [Double] {
        let scale = CGFloat(image.width) / size.width
        let side = Int(16 * scale)
        let box = CGRect(x: (point.x - 8) * scale, y: (size.height - point.y - 8) * scale,
                         width: CGFloat(side), height: CGFloat(side))
        guard let crop = image.cropping(to: box.integral) else { return [0] }
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let context = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(crop, in: CGRect(x: 0, y: 0, width: side, height: side))
        return stride(from: 0, to: pixels.count, by: 4).map { (i: Int) -> Double in
            let r = Double(pixels[i]), g = Double(pixels[i + 1]), b = Double(pixels[i + 2])
            return 0.2126 * r + 0.7152 * g + 0.0722 * b
        }
    }

    private static func write(_ image: CGImage, to url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }

    /// Holds the trigger on `point` until the glass there shatters; returns the rounds it took.
    private static func roundsToShatter(_ scene: DeskScene, at point: CGPoint) async -> Int {
        let shattersBefore = scene.shatters, roundsBefore = scene.roundsFired
        scene.startFiring(at: point)
        while scene.shatters == shattersBefore && scene.roundsFired - roundsBefore < 40 {
            try? await Task.sleep(for: .milliseconds(5))
        }
        scene.stopFiring()
        return scene.roundsFired - roundsBefore
    }

    private static func sweep(_ scene: DeskScene, from a: CGPoint, to b: CGPoint, seconds: Double) async {
        scene.startFiring(at: a)
        let start = Date()
        while Date().timeIntervalSince(start) < seconds {
            scene.aim(at: a.moved(toward: b, by: CGFloat(Date().timeIntervalSince(start) / seconds)))
            try? await Task.sleep(for: .milliseconds(10))
        }
        scene.stopFiring()
    }

    private static func capture(_ screen: NSScreen, to url: URL) async {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let display = content.displays.first(where: { $0.displayID == Snapshot.displayID(of: screen) }),
              let image = try? await Snapshot.capture(display),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}
