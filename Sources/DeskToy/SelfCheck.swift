import AppKit
import ScreenCaptureKit
import UniformTypeIdentifiers

/// Compares what the overlay shows against the snapshot it was built from. A pixel-exact overlay
/// re-captures as the same image, so any shift, scaling or colour error shows up in the diff.
enum SelfCheck {
    static func run(shots: [ScreenShot], icons: [DesktopIcon], into dir: URL) async {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var report = "icons: \(icons.count)" + (DesktopIcons.lastError.map { " (\($0))" } ?? "") + "\n"
        for icon in icons { report += "  \(icon.name): \(icon.frame)\n" }

        let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        for (index, shot) in shots.enumerated() {
            report += "display \(index) \(shot.screen.frame) live=\(shot.isLive)\n"
            guard let display = content?.displays.first(where: { $0.displayID == Snapshot.displayID(of: shot.screen) }),
                  let shown = try? await Snapshot.capture(display) else {
                report += "  re-capture unavailable\n"
                continue
            }
            write(shot.image, to: dir.appendingPathComponent("display\(index)-snapshot.png"))
            write(shown, to: dir.appendingPathComponent("display\(index)-shown.png"))
            report += "  " + compare(shot.image, shown) + "\n"
        }
        try? report.write(to: dir.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
    }

    private static func compare(_ a: CGImage, _ b: CGImage) -> String {
        guard a.width == b.width, a.height == b.height else {
            return "SIZE MISMATCH \(a.width)x\(a.height) vs \(b.width)x\(b.height)"
        }
        let pa = pixels(a), pb = pixels(b)
        var differing = 0, total = 0
        var maxDelta = 0
        for i in stride(from: 0, to: pa.count, by: 4) {
            let delta = max(abs(Int(pa[i]) - Int(pb[i])), abs(Int(pa[i + 1]) - Int(pb[i + 1])),
                            abs(Int(pa[i + 2]) - Int(pb[i + 2])))
            total += delta
            maxDelta = max(maxDelta, delta)
            if delta > 8 { differing += 1 }
        }
        let count = pa.count / 4
        return String(format: "%dx%d  differing(>8): %.3f%%  meanDelta: %.2f  maxDelta: %d",
                      a.width, a.height, Double(differing) / Double(count) * 100,
                      Double(total) / Double(count), maxDelta)
    }

    private static func pixels(_ image: CGImage) -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &buffer, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return buffer
    }

    private static func write(_ image: CGImage, to url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}
