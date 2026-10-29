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

    static func sweep(scene: DeskScene, screen: NSScreen, iconsBefore: [DesktopIcon], into dir: URL) async {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var report = "visible icons on this display: \(scene.iconCentres.count)\n"
        try? await Task.sleep(for: .seconds(1))

        // Shatter the glass under a few icons, plus some open wallpaper.
        let w = scene.size.width, h = scene.size.height
        let targets = Array(scene.iconCentres.prefix(4)) + [CGPoint(x: w * 0.45, y: h * 0.5), CGPoint(x: w * 0.6, y: h * 0.4)]
        for point in targets {
            for _ in 0..<3 {
                scene.hammer(at: point)
                try? await Task.sleep(for: .seconds(0.12))
            }
        }
        try? await Task.sleep(for: .seconds(2))
        report += "icons dropped: \(scene.iconsDropped)\n"
        await capture(screen, to: dir.appendingPathComponent("1-wrecked.png"))

        let start = Date()
        scene.sweep()
        try? await Task.sleep(for: .seconds(0.8))
        await capture(screen, to: dir.appendingPathComponent("2-sweeping.png"))
        while !scene.isClean && Date().timeIntervalSince(start) < 10 {
            try? await Task.sleep(for: .milliseconds(20))
        }
        report += String(format: "sweep → clean desktop: %.2f s (clean: %@)\n", Date().timeIntervalSince(start),
                         scene.isClean ? "yes" : "no")
        try? await Task.sleep(for: .seconds(2))
        await capture(screen, to: dir.appendingPathComponent("3-clean.png"))

        let after = DesktopIcons.read()
        report += "Finder icons before/after: \(iconsBefore.count)/\(after.count), unchanged: "
            + (after == iconsBefore ? "yes" : "NO") + "\n"
        try? report.write(to: dir.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
    }

    static func belt(scene: DeskScene, screen: NSScreen, into dir: URL) async {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var report = ""
        func check(_ name: String, _ ok: Bool) { report += (ok ? "PASS " : "FAIL ") + name + "\n" }
        let pockets = scene.beltPockets
        check("belt has 8 pockets", pockets.count == 8)
        guard pockets.count == 8 else { return }
        try? await Task.sleep(for: .seconds(1))
        await capture(screen, to: dir.appendingPathComponent("1-belt-hammer.png"))

        scene.press(at: pockets[1])
        check("click pocket 2 selects the minigun", scene.tool == .minigun)
        try? await Task.sleep(for: .seconds(1))
        await capture(screen, to: dir.appendingPathComponent("2-belt-minigun.png"))
        scene.press(at: pockets[0])
        check("click pocket 1 selects the hammer", scene.tool == .hammer)

        let sites = scene.damagedSites, rounds = scene.roundsFired
        for i in 0..<8 { scene.press(at: pockets[i]) }
        scene.press(at: pockets[1])
        for i in 0..<8 { scene.press(at: pockets[i]) }
        check("clicks on the belt never damage the glass", scene.damagedSites == sites && scene.roundsFired == rounds)
        scene.press(at: pockets[0])
        for i in 2..<8 { scene.press(at: pockets[i]) }
        check("empty pockets keep the current tool", scene.tool == .hammer)

        // Load the screen with damage, then measure the frame rate with the belt up.
        scene.press(at: pockets[1])
        scene.resetFrameStats()
        let w = scene.size.width, h = scene.size.height
        scene.startFiring(at: CGPoint(x: w / 2, y: h / 2))
        let start = Date()
        while Date().timeIntervalSince(start) < 15 {
            let t = CGFloat(Date().timeIntervalSince(start))
            scene.aim(at: CGPoint(x: w * 0.45 + w * 0.35 * sin(t * 0.7), y: h / 2 + h * 0.35 * sin(t * 1.1)))
            try? await Task.sleep(for: .milliseconds(10))
        }
        scene.stopFiring()
        report += String(format: "worst 1-s fps over 15 s of fire with the belt up: %.1f\n", scene.worstFPS)
        try? await Task.sleep(for: .seconds(1.5))
        await capture(screen, to: dir.appendingPathComponent("3-wrecked.png"))

        if let charm = scene.beltCharm {
            scene.press(at: charm)
            try? await Task.sleep(for: .seconds(0.3))
            await capture(screen, to: dir.appendingPathComponent("4-charm-falling.png"))
            try? await Task.sleep(for: .seconds(0.6))
            await capture(screen, to: dir.appendingPathComponent("5-sweeping.png"))
            let begin = Date()
            while !scene.isClean && Date().timeIntervalSince(begin) < 10 {
                try? await Task.sleep(for: .milliseconds(20))
            }
            check("clicking the broom charm sweeps to the clean desktop", scene.isClean)
            check("the belt is gone in the clean finale", !scene.beltVisible)
            try? await Task.sleep(for: .seconds(2))
            await capture(screen, to: dir.appendingPathComponent("6-clean.png"))
        } else {
            check("broom charm present", false)
        }
        try? report.write(to: dir.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
    }

    static func launcher(app: AppDelegate, into dir: URL) async {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var report = ""
        func check(_ name: String, _ ok: Bool) { report += (ok ? "PASS " : "FAIL ") + name + "\n" }
        let launcher = app.launcher
        try? await Task.sleep(for: .seconds(1))
        check("launcher is up on launch", launcher.isVisible)
        check("nothing captured before Start", Snapshot.captures == 0 && !app.isPlaying)

        let home = launcher.screen
        let homeID = Snapshot.displayID(of: home)
        let others = NSScreen.screens.filter { $0 != home }
        // Only the launcher's own window, never the rest of the screen.
        if let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
           let window = content.windows.first(where: { Int($0.windowID) == launcher.windowNumber }),
           let image = try? await SCScreenshotManager.captureImage(
               contentFilter: SCContentFilter(desktopIndependentWindow: window),
               configuration: { let c = SCStreamConfiguration(); c.width = Int(window.frame.width * 2)
                                c.height = Int(window.frame.height * 2); return c }()) {
            write(image, to: dir.appendingPathComponent("launcher.png"))
        }
        let withLauncher = await snapshot(home)
        let launcherRect = launcher.frame.offsetBy(dx: -home.frame.minX, dy: -home.frame.minY)

        func waitForPlay() async {
            for _ in 0..<100 where !app.isPlaying { try? await Task.sleep(for: .milliseconds(50)) }
            try? await Task.sleep(for: .seconds(0.8))
        }
        func launcherAbsent() -> Bool {
            guard let before = withLauncher, let shot = app.shots.first else { return false }
            return meanDifference(before, shot.image, in: launcherRect, size: home.frame.size) > 12
        }

        // First go: this display only, sound off, minigun.
        launcher.choose(LaunchSettings(displays: [homeID], controls: homeID, sound: false, tool: .minigun))
        launcher.start()
        await waitForPlay()
        guard let scene = app.scenes.first else {
            check("Start begins play", false)
            try? report.write(to: dir.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
            return
        }
        check("launcher hidden during play", !launcher.isVisible)
        check("only the checked display is covered", app.windows.map(\.frame) == [home.frame])
        check("toolbelt on the controls display", scene.beltVisible)
        check("starting tool honoured (minigun)", scene.tool == .minigun)
        check("launcher absent from the snapshot", launcherAbsent())
        var played = SoundFX.shared.played
        scene.hammer(at: CGPoint(x: launcherRect.midX, y: launcherRect.midY))
        scene.hammer(at: CGPoint(x: launcherRect.midX, y: launcherRect.midY))
        scene.hammer(at: CGPoint(x: launcherRect.midX, y: launcherRect.midY))
        try? await Task.sleep(for: .seconds(1.2))
        check("sound off is silent", SoundFX.shared.played == played)
        check("shards cut from the launcher's spot", scene.shatters > 0)

        app.backToLauncher()
        try? await Task.sleep(for: .seconds(0.5))
        check("Esc brings the launcher back", launcher.isVisible && app.windows.isEmpty && !app.isPlaying)

        // Second go: sound on, hammer, a fresh snapshot.
        let capturesBefore = Snapshot.captures
        launcher.choose(LaunchSettings(displays: [homeID], controls: homeID, sound: true, tool: .hammer))
        launcher.start()
        await waitForPlay()
        check("second Start takes a fresh snapshot", Snapshot.captures > capturesBefore && app.isPlaying)
        if let again = app.scenes.first {
            check("starting tool honoured (hammer)", again.tool == .hammer)
            check("launcher absent from the second snapshot", launcherAbsent())
            played = SoundFX.shared.played
            again.hammer(at: CGPoint(x: again.size.width * 0.3, y: again.size.height * 0.5))
            try? await Task.sleep(for: .seconds(0.3))
            check("sound on plays", SoundFX.shared.played > played)
        }
        app.backToLauncher()
        try? await Task.sleep(for: .seconds(0.5))

        // Third go, given a second display: play there only, with the toolbelt there too.
        if let other = others.first {
            let otherID = Snapshot.displayID(of: other)
            launcher.choose(LaunchSettings(displays: [otherID], controls: otherID, sound: true, tool: .hammer))
            launcher.start()
            await waitForPlay()
            check("other display only: this one stays uncovered", app.windows.map(\.frame) == [other.frame])
            check("toolbelt follows to the other display", app.scenes.first?.beltVisible ?? false)
            app.backToLauncher()
            try? await Task.sleep(for: .seconds(0.5))
            // Both displays, controls on the other one: only that one gets the belt.
            launcher.choose(LaunchSettings(displays: [homeID, otherID], controls: otherID, sound: false, tool: .minigun))
            launcher.start()
            await waitForPlay()
            let belts = zip(app.shots, app.scenes).map { (Snapshot.displayID(of: $0.screen), $1.beltVisible) }
            check("both displays covered", app.windows.count == 2)
            check("toolbelt only on the chosen display", belts.allSatisfy { $0.1 == ($0.0 == otherID) })
            app.backToLauncher()
            try? await Task.sleep(for: .seconds(0.5))
        } else {
            report += "SKIP second-display checks: one display connected\n"
        }

        check("About credits the original as a tribute", Launcher.about.joined().contains("tribute to the original"))
        check("About links to the archive page", Launcher.archiveURL.host == "gamia-archive.fandom.com")
        let saved = LaunchSettings.load(from: app.defaults, home: home)
        check("choices saved", saved == launcher.settings)
        try? "\(launcher.settings)".write(to: dir.appendingPathComponent("expected.txt"), atomically: true, encoding: .utf8)
        try? report.write(to: dir.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
    }

    /// Run on a fresh launch after `launcher(app:into:)`: the launcher should come up with the choices it left.
    static func recall(launcher: Launcher, into dir: URL) async {
        try? await Task.sleep(for: .seconds(0.5))
        let expected = (try? String(contentsOf: dir.appendingPathComponent("expected.txt"), encoding: .utf8)) ?? "?"
        let ok = "\(launcher.settings)" == expected && launcher.isVisible
        let line = (ok ? "PASS" : "FAIL") + " choices survive a relaunch (\(launcher.settings))\n"
        try? line.write(to: dir.appendingPathComponent("recall.txt"), atomically: true, encoding: .utf8)
    }

    /// Mean per-channel difference (0–255) between two captures of the same display, over a rect in points.
    private static func meanDifference(_ a: CGImage, _ b: CGImage, in rect: CGRect, size: CGSize) -> Double {
        func pixels(_ image: CGImage) -> [UInt8] {
            let scale = CGFloat(image.width) / size.width
            let box = CGRect(x: rect.minX * scale, y: (size.height - rect.maxY) * scale,
                             width: rect.width * scale, height: rect.height * scale).integral
            let w = 200, h = 200
            var out = [UInt8](repeating: 0, count: w * h * 4)
            guard let crop = image.cropping(to: box),
                  let context = CGContext(data: &out, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return out }
            context.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
            return out
        }
        let pa = pixels(a), pb = pixels(b)
        var total = 0
        for i in 0..<pa.count where i % 4 != 3 { total += abs(Int(pa[i]) - Int(pb[i])) }
        return Double(total) / Double(pa.count / 4 * 3)
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
