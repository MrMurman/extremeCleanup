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
