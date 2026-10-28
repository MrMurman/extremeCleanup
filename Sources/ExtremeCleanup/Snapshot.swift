import AppKit
import ScreenCaptureKit

struct ScreenShot {
    let screen: NSScreen
    let image: CGImage
    /// False when screen capture was unavailable and the wallpaper stands in for the screen.
    let isLive: Bool
}

enum Snapshot {
    static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    static func captureAll() async -> [ScreenShot] {
        let screens = NSScreen.screens
        guard CGPreflightScreenCaptureAccess(),
              let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        else {
            CGRequestScreenCaptureAccess()
            return screens.map(standIn)
        }
        var shots: [ScreenShot] = []
        for screen in screens {
            if let display = content.displays.first(where: { $0.displayID == displayID(of: screen) }),
               let image = try? await capture(display) {
                shots.append(ScreenShot(screen: screen, image: image, isLive: true))
            } else {
                shots.append(standIn(for: screen))
            }
        }
        return shots
    }

    static func capture(_ display: SCDisplay) async throws -> CGImage {
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        config.width = Int(filter.contentRect.width * scale)
        config.height = Int(filter.contentRect.height * scale)
        config.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// The wallpaper scaled to fill the screen, or a flat dark fill if even that is unavailable.
    static func standIn(for screen: NSScreen) -> ScreenShot {
        let scale = screen.backingScaleFactor
        let width = Int(screen.frame.width * scale)
        let height = Int(screen.frame.height * scale)
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 0.12, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if let url = NSWorkspace.shared.desktopImageURL(for: screen),
           let wallpaper = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let fill = max(CGFloat(width) / CGFloat(wallpaper.width), CGFloat(height) / CGFloat(wallpaper.height))
            let size = CGSize(width: CGFloat(wallpaper.width) * fill, height: CGFloat(wallpaper.height) * fill)
            context.draw(wallpaper, in: CGRect(x: (CGFloat(width) - size.width) / 2,
                                               y: (CGFloat(height) - size.height) / 2,
                                               width: size.width, height: size.height))
        }
        return ScreenShot(screen: screen, image: context.makeImage()!, isLive: false)
    }
}
