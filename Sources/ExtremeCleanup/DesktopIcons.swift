import AppKit

struct DesktopIcon: Codable, Equatable {
    let name: String
    /// Global AppKit coordinates (origin at the bottom-left of the main screen).
    let frame: CGRect

    /// The icon with its name label underneath.
    var tile: CGRect {
        CGRect(x: frame.minX - 14, y: frame.minY - 34, width: frame.width + 28, height: frame.height + 34)
    }
}

enum DesktopIcons {
    private static let script = """
    tell application "Finder"
        set iconSize to icon size of icon view options of window of desktop
        set positions to desktop position of every item of desktop
        set names to name of every item of desktop
    end tell
    set out to (iconSize as text)
    repeat with i from 1 to count of positions
        set p to item i of positions
        set out to out & linefeed & (item 1 of p as text) & tab & (item 2 of p as text) & tab & (item i of names)
    end repeat
    return out
    """

    private(set) static var lastError: String?

    /// Icons no window covers, even partly: only those can be seen, so only those can fall.
    static func uncovered(_ icons: [DesktopIcon], by windows: [CGRect]) -> [DesktopIcon] {
        icons.filter { icon in !windows.contains { $0.intersects(icon.tile) } }
    }

    /// Reads icon positions from Finder. Empty if Automation access is denied or Finder doesn't answer.
    static func read() -> [DesktopIcon] {
        var error: NSDictionary?
        guard let text = NSAppleScript(source: script)?.executeAndReturnError(&error).stringValue else {
            lastError = error?[NSAppleScript.errorMessage] as? String ?? "no reply from Finder"
            return []
        }
        var lines = text.components(separatedBy: "\n")
        guard let iconSize = Double(lines.removeFirst()) else { return [] }
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        return lines.compactMap { line in
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 3, let x = Double(parts[0]), let y = Double(parts[1]) else { return nil }
            // Finder reports the icon's centre in top-left-origin coordinates.
            let centre = CGPoint(x: x, y: mainHeight - y)
            let frame = CGRect(x: centre.x - iconSize / 2, y: centre.y - iconSize / 2, width: iconSize, height: iconSize)
            return DesktopIcon(name: parts[2...].joined(separator: "\t"), frame: frame)
        }
    }
}
