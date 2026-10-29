import AppKit

/// What the player picked in the launcher; remembered between launches.
struct LaunchSettings: Equatable, CustomStringConvertible {
    var displays: [CGDirectDisplayID]
    var controls: CGDirectDisplayID
    var sound: Bool
    var tool: DeskScene.Tool

    var description: String {
        "displays=\(displays) controls=\(controls) sound=\(sound) tool=\(tool.rawValue)"
    }

    static func load(from defaults: UserDefaults, home: NSScreen) -> LaunchSettings {
        let saved = (defaults.array(forKey: "displays") as? [Int])?.map { CGDirectDisplayID($0) } ?? []
        let settings = LaunchSettings(
            displays: saved, controls: CGDirectDisplayID(defaults.integer(forKey: "controls")),
            sound: defaults.object(forKey: "sound") as? Bool ?? true,
            tool: DeskScene.Tool(rawValue: defaults.string(forKey: "tool") ?? "") ?? .hammer)
        return settings.fitted(home: home)
    }

    func save(to defaults: UserDefaults) {
        defaults.set(displays.map { Int($0) }, forKey: "displays")
        defaults.set(Int(controls), forKey: "controls")
        defaults.set(sound, forKey: "sound")
        defaults.set(tool.rawValue, forKey: "tool")
    }

    /// Drops displays that are no longer connected; falls back to the launcher's own display.
    func fitted(home: NSScreen) -> LaunchSettings {
        let connected = NSScreen.screens.map(Snapshot.displayID)
        let homeID = Snapshot.displayID(of: home)
        var fitted = self
        fitted.displays = connected.filter(displays.contains)
        if fitted.displays.isEmpty { fitted.displays = [homeID] }
        if !fitted.displays.contains(controls) {
            fitted.controls = fitted.displays.contains(homeID) ? homeID : fitted.displays[0]
        }
        return fitted
    }
}

/// The shareware-style starter window: where to play, sound, starting tool, and a few words about the toy.
@MainActor
final class Launcher {
    static let archiveURL = URL(string: "https://gamia-archive.fandom.com/wiki/Desktop_Destroyer_Game")!
    static let about = [
        "Extreme Cleanup turns your screen into a sheet of glass you can smash with a variety of tools. "
            + "It doesn't affect your actual desktop: press Esc to leave.",
        "A tribute to the original freeware from the 2000s by Gemtree Software.",
    ]

    var onStart: ((LaunchSettings) -> Void)?
    var onQuit: (() -> Void)?
    private(set) var settings: LaunchSettings
    private let window: LauncherWindow
    private var displayChecks: [(CGDirectDisplayID, RetroToggle)] = []
    private var controlRadios: [(CGDirectDisplayID, RetroToggle)] = []
    private var soundRadios: [RetroToggle] = []
    private var toolRadios: [RetroToggle] = []

    var isVisible: Bool { window.isVisible }
    var frame: CGRect { window.frame }
    var windowNumber: Int { window.windowNumber }
    var screen: NSScreen { window.screen ?? NSScreen.screens[0] }

    init(settings: LaunchSettings) {
        self.settings = settings
        window = LauncherWindow(contentRect: CGRect(x: 0, y: 0, width: 420, height: 400), styleMask: .borderless,
                                backing: .buffered, defer: false)
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = Retro.face
    }

    func show() {
        let firstShow = window.contentView?.subviews.isEmpty ?? true
        settings = settings.fitted(home: screen)
        let top = window.frame.maxY
        build()
        if firstShow {
            window.center()
        } else {
            window.setFrameOrigin(CGPoint(x: window.frame.minX, y: top - window.frame.height))
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func hide() { window.orderOut(nil) }

    func choose(_ settings: LaunchSettings) {
        self.settings = settings
        refresh()
    }

    func start() { onStart?(settings) }

    // MARK: - Layout

    private func build() {
        // Wide enough for the tribute line to sit on one line.
        let tribute = (Launcher.about.last! as NSString).size(withAttributes: [.font: Retro.font(11)]).width
        let pad: CGFloat = 12, width = max(420, ceil(tribute) + pad * 2 + 24 + 8), inner = width - pad * 2
        let panel = RetroPanel(frame: .zero)
        displayChecks = []; controlRadios = []
        var y: CGFloat = 4

        let title = RetroTitleBar(frame: CGRect(x: 4, y: y, width: width - 8, height: 20))
        title.onClose = { [weak self] in self?.onQuit?() }
        panel.addSubview(title)
        y += 24
        panel.addSubview(RetroBanner(frame: CGRect(x: pad, y: y, width: inner, height: 78)))
        y += 78 + 10

        let screens = NSScreen.screens
        let listHeight = 26 + CGFloat(screens.count) * 20
        let playOn = RetroGroup(title: "Play on", frame: CGRect(x: pad, y: y, width: inner, height: listHeight))
        panel.addSubview(playOn)
        y += listHeight + 8
        let controlsOn = RetroGroup(title: "Toolbelt on", frame: CGRect(x: pad, y: y, width: inner, height: listHeight))
        panel.addSubview(controlsOn)
        y += listHeight + 8
        for (i, screen) in screens.enumerated() {
            let id = Snapshot.displayID(of: screen)
            let name = "\(screen.localizedName) (\(Int(screen.frame.width))×\(Int(screen.frame.height)))"
                + (screen == self.screen ? " — this screen" : "")
            let rowFrame = CGRect(x: 12, y: 20 + CGFloat(i) * 20, width: inner - 24, height: 18)
            let check = RetroToggle(kind: .check, label: name, frame: rowFrame)
            check.onChange = { [weak self] on in self?.setDisplay(id, on: on) }
            playOn.addSubview(check)
            displayChecks.append((id, check))
            let radio = RetroToggle(kind: .radio, label: name, frame: rowFrame)
            radio.onChange = { [weak self] _ in self?.settings.controls = id; self?.refresh() }
            controlsOn.addSubview(radio)
            controlRadios.append((id, radio))
        }

        let half = (inner - 8) / 2
        let sound = RetroGroup(title: "Sound", frame: CGRect(x: pad, y: y, width: half, height: 44))
        let tool = RetroGroup(title: "Starting tool", frame: CGRect(x: pad + half + 8, y: y, width: half, height: 44))
        soundRadios = ["On", "Off"].enumerated().map { i, label in
            let radio = RetroToggle(kind: .radio, label: label, frame: CGRect(x: 12 + CGFloat(i) * 70, y: 20, width: 64, height: 18))
            radio.onChange = { [weak self] _ in self?.settings.sound = i == 0; self?.refresh() }
            sound.addSubview(radio)
            return radio
        }
        toolRadios = [DeskScene.Tool.hammer, .minigun].enumerated().map { i, kind in
            let radio = RetroToggle(kind: .radio, label: kind.rawValue,
                                    frame: CGRect(x: 12 + CGFloat(i) * 84, y: 20, width: 80, height: 18))
            radio.onChange = { [weak self] _ in self?.settings.tool = kind; self?.refresh() }
            tool.addSubview(radio)
            return radio
        }
        panel.addSubview(sound)
        panel.addSubview(tool)
        y += 44 + 6

        let keys = Retro.label("In play: 1 / 2 switch tools  ·  C sweeps up  ·  Esc comes back here",
                               size: 10, color: Retro.ink.withAlphaComponent(0.6))
        keys.frame = CGRect(x: pad + 2, y: y, width: inner, height: 14)
        panel.addSubview(keys)
        y += 14 + 8

        let textWidth = inner - 24
        let paragraphs = Launcher.about.map { Retro.label($0, size: 11, color: Retro.ink, wraps: true) }
        var textY: CGFloat = 20
        for text in paragraphs {
            let height = ceil(text.sizeThatFits(CGSize(width: textWidth, height: 1000)).height)
            text.frame = CGRect(x: 12, y: textY, width: textWidth, height: height)
            textY += height + 8
        }
        let aboutHeight = textY + 16 + 10
        let about = RetroGroup(title: "About", frame: CGRect(x: pad, y: y, width: inner, height: aboutHeight))
        paragraphs.forEach(about.addSubview)
        about.addSubview(RetroLink(text: "Desktop Destroyer on the Gamia archive ↗", url: Launcher.archiveURL,
                                   frame: CGRect(x: 12, y: textY, width: textWidth, height: 16)))
        panel.addSubview(about)
        y += aboutHeight + 12

        let start = RetroButton(title: "Start the cleanup", isDefault: true,
                                frame: CGRect(x: width - pad - 150, y: y, width: 150, height: 28))
        start.onClick = { [weak self] in self?.start() }
        let quit = RetroButton(title: "Quit", isDefault: false,
                               frame: CGRect(x: width - pad - 150 - 10 - 84, y: y, width: 84, height: 28))
        quit.onClick = { [weak self] in self?.onQuit?() }
        panel.addSubview(start)
        panel.addSubview(quit)
        y += 28 + 12

        panel.frame = CGRect(x: 0, y: 0, width: width, height: y)
        window.setContentSize(panel.frame.size)
        window.contentView = panel
        refresh()
    }

    private func setDisplay(_ id: CGDirectDisplayID, on: Bool) {
        if on {
            settings.displays = NSScreen.screens.map(Snapshot.displayID).filter { settings.displays.contains($0) || $0 == id }
        } else if settings.displays.count > 1 {
            settings.displays.removeAll { $0 == id }
        }
        if !settings.displays.contains(settings.controls) { settings.controls = settings.displays[0] }
        refresh()
    }

    private func refresh() {
        for (id, check) in displayChecks { check.isOn = settings.displays.contains(id) }
        for (id, radio) in controlRadios {
            radio.isOn = settings.controls == id
            radio.isEnabled = settings.displays.contains(id)
        }
        for (i, radio) in soundRadios.enumerated() { radio.isOn = (i == 0) == settings.sound }
        for (radio, kind) in zip(toolRadios, [DeskScene.Tool.hammer, .minigun]) { radio.isOn = settings.tool == kind }
    }
}

final class LauncherWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Retro widgets

/// An original take on the bevelled grey look of 1990s shareware.
enum Retro {
    static let face = NSColor(calibratedRed: 0.79, green: 0.78, blue: 0.75, alpha: 1)
    static let highlight = NSColor(calibratedWhite: 1, alpha: 1)
    static let soft = NSColor(calibratedRed: 0.89, green: 0.88, blue: 0.86, alpha: 1)
    static let shade = NSColor(calibratedRed: 0.47, green: 0.46, blue: 0.44, alpha: 1)
    static let ink = NSColor(calibratedWhite: 0.08, alpha: 1)

    static func font(_ size: CGFloat, bold: Bool = false) -> NSFont {
        let base = NSFont(name: "Geneva", size: size) ?? .systemFont(ofSize: size)
        return bold ? NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask) : base
    }

    /// Two-pixel bevel inside `rect`, in a flipped view.
    static func bevel(_ rect: CGRect, raised: Bool) {
        let rings: [(NSColor, NSColor)] = raised ? [(highlight, ink), (soft, shade)] : [(shade, highlight), (ink, soft)]
        var r = rect
        for (topLeft, bottomRight) in rings {
            topLeft.setFill()
            CGRect(x: r.minX, y: r.minY, width: r.width, height: 1).fill()
            CGRect(x: r.minX, y: r.minY, width: 1, height: r.height).fill()
            bottomRight.setFill()
            CGRect(x: r.minX, y: r.maxY - 1, width: r.width, height: 1).fill()
            CGRect(x: r.maxX - 1, y: r.minY, width: 1, height: r.height).fill()
            r = r.insetBy(dx: 1, dy: 1)
        }
    }

    static func label(_ text: String, size: CGFloat, color: NSColor, wraps: Bool = false) -> NSTextField {
        let field = wraps ? NSTextField(wrappingLabelWithString: text) : NSTextField(labelWithString: text)
        field.font = font(size)
        field.textColor = color
        field.isSelectable = false
        return field
    }

    static func draw(_ text: String, at point: CGPoint, font: NSFont, color: NSColor) {
        (text as NSString).draw(at: point, withAttributes: [.font: font, .foregroundColor: color])
    }
}

class RetroView: NSView {
    override var isFlipped: Bool { true }
}

final class RetroPanel: RetroView {
    override func draw(_ dirtyRect: CGRect) {
        Retro.face.setFill()
        bounds.fill()
        Retro.bevel(bounds, raised: true)
    }
}

final class RetroTitleBar: RetroView {
    var onClose: (() -> Void)?
    private var closeBox: CGRect { CGRect(x: bounds.maxX - 19, y: 3, width: 16, height: 14) }

    override func draw(_ dirtyRect: CGRect) {
        NSGradient(starting: NSColor(calibratedRed: 0.1, green: 0.09, blue: 0.32, alpha: 1),
                   ending: NSColor(calibratedRed: 0.62, green: 0.14, blue: 0.22, alpha: 1))?.draw(in: bounds, angle: 0)
        Retro.draw("Extreme Cleanup", at: CGPoint(x: 6, y: 3), font: Retro.font(12, bold: true), color: .white)
        Retro.face.setFill()
        closeBox.fill()
        Retro.bevel(closeBox, raised: true)
        let cross = NSBezierPath()
        let c = CGPoint(x: closeBox.midX - 0.5, y: closeBox.midY - 0.5)
        cross.move(to: CGPoint(x: c.x - 3, y: c.y - 3)); cross.line(to: CGPoint(x: c.x + 3, y: c.y + 3))
        cross.move(to: CGPoint(x: c.x + 3, y: c.y - 3)); cross.line(to: CGPoint(x: c.x - 3, y: c.y + 3))
        cross.lineWidth = 2
        Retro.ink.setStroke()
        cross.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        if closeBox.contains(convert(event.locationInWindow, from: nil)) {
            onClose?()
        } else {
            window?.performDrag(with: event)
        }
    }
}

final class RetroBanner: RetroView {
    override func draw(_ dirtyRect: CGRect) {
        NSColor(calibratedRed: 0.06, green: 0.06, blue: 0.1, alpha: 1).setFill()
        bounds.fill()
        NSBezierPath(rect: bounds).setClip()
        // A spray of cracks from one impact point, the toy's whole premise in a picture.
        var rng = SeededRandom(seed: 7)
        let impact = CGPoint(x: bounds.maxX - 64, y: bounds.midY - 4)
        let cracks = NSBezierPath()
        for k in 0..<11 {
            var p = impact
            var angle = CGFloat(k) / 11 * 2 * .pi + CGFloat(rng.range(-0.2...0.2))
            cracks.move(to: p)
            for _ in 0..<5 {
                angle += CGFloat(rng.range(-0.35...0.35))
                let step = CGFloat(rng.range(8...22))
                p = CGPoint(x: p.x + cos(angle) * step, y: p.y + sin(angle) * step)
                cracks.line(to: p)
            }
        }
        for ring in [9.0, 19.0] as [CGFloat] {
            cracks.appendOval(in: CGRect(x: impact.x - ring, y: impact.y - ring * 0.8, width: ring * 2, height: ring * 1.6))
        }
        cracks.lineWidth = 0.8
        NSColor(calibratedWhite: 1, alpha: 0.42).setStroke()
        cracks.stroke()

        let title = NSFont(name: "Impact", size: 30) ?? .boldSystemFont(ofSize: 30)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(calibratedRed: 0.7, green: 0.1, blue: 0.2, alpha: 1)
        shadow.shadowOffset = CGSize(width: 2, height: -2)
        shadow.shadowBlurRadius = 0
        ("EXTREME CLEANUP" as NSString).draw(at: CGPoint(x: 14, y: 8), withAttributes: [
            .font: title, .foregroundColor: NSColor(calibratedRed: 1, green: 0.93, blue: 0.75, alpha: 1), .shadow: shadow,
        ])
        Retro.draw("Smash the desktop. Sweep it up. Start over.", at: CGPoint(x: 15, y: 50),
                   font: Retro.font(11), color: NSColor(calibratedWhite: 0.78, alpha: 1))
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        Retro.draw("v\(version)", at: CGPoint(x: bounds.maxX - 44, y: bounds.maxY - 16),
                   font: Retro.font(10), color: NSColor(calibratedWhite: 0.6, alpha: 1))
        Retro.bevel(bounds, raised: false)
    }
}

final class RetroGroup: RetroView {
    private let title: String

    init(title: String, frame: CGRect) {
        self.title = title
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: CGRect) {
        let box = CGRect(x: 0, y: 7, width: bounds.width - 1, height: bounds.height - 8)
        Retro.shade.setStroke()
        NSBezierPath(rect: box.offsetBy(dx: 0.5, dy: 0.5)).stroke()
        Retro.highlight.setStroke()
        NSBezierPath(rect: box.offsetBy(dx: 1.5, dy: 1.5)).stroke()
        let font = Retro.font(11, bold: true)
        let width = (title as NSString).size(withAttributes: [.font: font]).width
        Retro.face.setFill()
        CGRect(x: 8, y: 0, width: width + 8, height: 14).fill()
        Retro.draw(title, at: CGPoint(x: 12, y: 0), font: font, color: Retro.ink)
    }
}

final class RetroToggle: RetroView {
    enum Kind { case check, radio }

    var isOn = false { didSet { needsDisplay = true } }
    var isEnabled = true { didSet { needsDisplay = true } }
    var onChange: ((Bool) -> Void)?
    private let kind: Kind
    private let label: String

    init(kind: Kind, label: String, frame: CGRect) {
        self.kind = kind
        self.label = label
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: CGRect) {
        let box = CGRect(x: 0, y: (bounds.height - 13) / 2, width: 13, height: 13)
        let fill = isEnabled ? Retro.highlight : Retro.face
        switch kind {
        case .check:
            fill.setFill()
            box.fill()
            Retro.bevel(box, raised: false)
            if isOn {
                let tick = NSBezierPath()
                tick.move(to: CGPoint(x: box.minX + 3, y: box.midY))
                tick.line(to: CGPoint(x: box.minX + 5.5, y: box.maxY - 3.5))
                tick.line(to: CGPoint(x: box.maxX - 3, y: box.minY + 3))
                tick.lineWidth = 2
                (isEnabled ? Retro.ink : Retro.shade).setStroke()
                tick.stroke()
            }
        case .radio:
            let ring = box.insetBy(dx: 0.5, dy: 0.5)
            fill.setFill()
            NSBezierPath(ovalIn: ring).fill()
            Retro.shade.setStroke()
            NSBezierPath(ovalIn: ring).stroke()
            let lit = NSBezierPath()
            lit.appendArc(withCenter: CGPoint(x: ring.midX, y: ring.midY), radius: ring.width / 2,
                          startAngle: -45, endAngle: 135)
            Retro.highlight.setStroke()
            lit.stroke()
            if isOn {
                (isEnabled ? Retro.ink : Retro.shade).setFill()
                NSBezierPath(ovalIn: box.insetBy(dx: 4, dy: 4)).fill()
            }
        }
        Retro.draw(label, at: CGPoint(x: 19, y: (bounds.height - 15) / 2), font: Retro.font(12),
                   color: isEnabled ? Retro.ink : Retro.shade)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        if kind == .check {
            isOn.toggle()
            onChange?(isOn)
        } else if !isOn {
            isOn = true
            onChange?(true)
        }
    }
}

final class RetroButton: RetroView {
    var onClick: (() -> Void)?
    private let title: String
    private let isDefault: Bool
    private var isPressed = false { didSet { needsDisplay = true } }

    init(title: String, isDefault: Bool, frame: CGRect) {
        self.title = title
        self.isDefault = isDefault
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: CGRect) {
        var r = bounds
        Retro.face.setFill()
        r.fill()
        if isDefault {
            Retro.ink.setStroke()
            NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)).stroke()
            r = r.insetBy(dx: 1, dy: 1)
        }
        Retro.bevel(r, raised: !isPressed)
        let font = Retro.font(12, bold: isDefault)
        let size = (title as NSString).size(withAttributes: [.font: font])
        let shift: CGFloat = isPressed ? 1 : 0
        Retro.draw(title, at: CGPoint(x: (bounds.width - size.width) / 2 + shift, y: (bounds.height - size.height) / 2 + shift),
                   font: font, color: Retro.ink)
    }

    override func mouseDown(with event: NSEvent) { isPressed = true }

    override func mouseDragged(with event: NSEvent) {
        isPressed = bounds.contains(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        let fire = isPressed
        isPressed = false
        if fire { onClick?() }
    }
}

final class RetroLink: RetroView {
    private let text: String
    private let url: URL

    init(text: String, url: URL, frame: CGRect) {
        self.text = text
        self.url = url
        super.init(frame: frame)
        toolTip = url.absoluteString
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: CGRect) {
        (text as NSString).draw(at: .zero, withAttributes: [
            .font: Retro.font(11), .foregroundColor: NSColor(calibratedRed: 0.05, green: 0.1, blue: 0.62, alpha: 1),
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ])
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func mouseDown(with event: NSEvent) { NSWorkspace.shared.open(url) }
}
