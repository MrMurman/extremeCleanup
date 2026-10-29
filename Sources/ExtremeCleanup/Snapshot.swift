import AppKit
import ScreenCaptureKit

struct ScreenShot {
    let screen: NSScreen
    let image: CGImage
    /// False when screen capture was unavailable and the wallpaper stands in for the screen.
    let isLive: Bool
    /// The desktop picture alone, without icons or windows.
    let wallpaper: CGImage
}

enum Snapshot {
    static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// How many displays have been snapshotted since launch.
    private(set) static var captures = 0

    /// Snapshots the given displays. The app's own windows are left out, so the launcher can never end up in the glass.
    static func captureAll(_ screens: [NSScreen]) async -> [ScreenShot] {
        captures += screens.count
        guard CGPreflightScreenCaptureAccess(),
              let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        else {
            CGRequestScreenCaptureAccess()
            return screens.map(standIn)
        }
        let ownApp = content.applications.filter { $0.processID == getpid() }
        var shots: [ScreenShot] = []
        for screen in screens {
            if let display = content.displays.first(where: { $0.displayID == displayID(of: screen) }),
               let image = try? await capture(SCContentFilter(display: display, excludingApplications: ownApp,
                                                              exceptingWindows: [])) {
                let wallpaper = await captureWallpaper(of: display, in: content) ?? standIn(for: screen).image
                shots.append(ScreenShot(screen: screen, image: image, isLive: true, wallpaper: wallpaper))
            } else {
                shots.append(standIn(for: screen))
            }
        }
        return shots
    }

    static func capture(_ display: SCDisplay) async throws -> CGImage {
        try await capture(SCContentFilter(display: display, excludingWindows: []))
    }

    /// The Dock draws each display's desktop picture in its own window; capturing only that window gives the
    /// wallpaper as the user actually sees it, which the API for the wallpaper's file doesn't always report.
    private static func captureWallpaper(of display: SCDisplay, in content: SCShareableContent) async -> CGImage? {
        guard let window = content.windows.first(where: {
            $0.owningApplication?.bundleIdentifier == "com.apple.dock" && ($0.title ?? "").hasPrefix("Wallpaper-")
                && display.frame.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY))
        }) else { return nil }
        return try? await capture(SCContentFilter(display: display, including: [window]))
    }

    /// Frames of ordinary app windows on screen, in global AppKit coordinates.
    static func windowFrames() async -> [CGRect] {
        guard CGPreflightScreenCaptureAccess(),
              let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        else { return [] }
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        return content.windows.filter {
            $0.windowLayer == 0 && $0.isOnScreen && $0.owningApplication?.processID != getpid()
        }.map {
            CGRect(x: $0.frame.minX, y: mainHeight - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height)
        }
    }

    private static func capture(_ filter: SCContentFilter) async throws -> CGImage {
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
        let image = context.makeImage()!
        return ScreenShot(screen: screen, image: image, isLive: false, wallpaper: image)
    }
}
