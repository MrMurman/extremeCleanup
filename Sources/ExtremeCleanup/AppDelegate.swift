import AppKit
import SpriteKit
import QuartzCore

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var windows: [OverlayWindow] = []
    private(set) var scenes: [DeskScene] = []
    private(set) var shots: [ScreenShot] = []
    private var isStarting = false

    /// `--defaults-suite <name>`: keep the launcher's choices somewhere other than the app's own defaults.
    let defaults = AppDelegate.argument(after: "--defaults-suite").flatMap(UserDefaults.init(suiteName:)) ?? .standard
    private(set) lazy var launcher: Launcher = {
        let launcher = Launcher(settings: LaunchSettings.load(from: defaults, home: NSScreen.screens[0]))
        launcher.onStart = { [weak self] settings in
            guard let self else { return }
            settings.save(to: defaults)
            Task { await self.play(settings) }
        }
        launcher.onQuit = { NSApp.terminate(nil) }
        return launcher
    }()

    /// `--self-check <dir>`: re-capture the screen with the overlay up, write a pixel diff report, quit.
    private let selfCheckDir = AppDelegate.directory(after: "--self-check")
    /// `--demo-hammer|minigun|void|sweep|belt <dir>`: scripted run on the main display, with captures and a report.
    private let hammerDemoDir = AppDelegate.directory(after: "--demo-hammer")
    private let minigunDemoDir = AppDelegate.directory(after: "--demo-minigun")
    private let voidDemoDir = AppDelegate.directory(after: "--demo-void")
    private let sweepDemoDir = AppDelegate.directory(after: "--demo-sweep")
    private let beltDemoDir = AppDelegate.directory(after: "--demo-belt")
    /// `--demo-launcher <dir>`: drives the launcher through Start, Esc and a second Start; `--demo-recall <dir>`
    /// checks on a later launch that the choices came back.
    private let launcherDemoDir = AppDelegate.directory(after: "--demo-launcher")
    private let recallDemoDir = AppDelegate.directory(after: "--demo-recall")

    private static func argument(after flag: String) -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    private static func directory(after flag: String) -> URL? {
        argument(after: flag).map { URL(fileURLWithPath: $0) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installKeys()
        let scripted = [selfCheckDir, hammerDemoDir, minigunDemoDir, voidDemoDir, sweepDemoDir, beltDemoDir]
        guard scripted.allSatisfy({ $0 == nil }) else {
            Task { await runScripted() }
            return
        }
        launcher.show()
        if let dir = launcherDemoDir {
            Task {
                await Demo.launcher(app: self, into: dir)
                NSApp.terminate(nil)
            }
        } else if let dir = recallDemoDir {
            Task {
                await Demo.recall(launcher: launcher, into: dir)
                NSApp.terminate(nil)
            }
        }
    }

    /// The pre-launcher scripted runs: straight into play on the main display.
    private func runScripted() async {
        let main = Snapshot.displayID(of: NSScreen.screens[0])
        await play(LaunchSettings(displays: [main], controls: main, sound: true, tool: .hammer))
        if let dir = selfCheckDir {
            try? await Task.sleep(for: .seconds(1))
            await SelfCheck.run(shots: shots, icons: DesktopIcons.read(), into: dir)
        }
        if let scene = scenes.first, let shot = shots.first {
            if let dir = hammerDemoDir {
                await Demo.hammer(scene: scene, screen: shot.screen, into: dir)
            } else if let dir = minigunDemoDir {
                select(.minigun)
                await Demo.minigun(scene: scene, screen: shot.screen, into: dir)
            } else if let dir = beltDemoDir {
                await Demo.belt(scene: scene, screen: shot.screen, into: dir)
            } else if let dir = sweepDemoDir {
                await Demo.sweep(scene: scene, screen: shot.screen, iconsBefore: DesktopIcons.read(), into: dir)
            } else if let dir = voidDemoDir {
                await Demo.void(scene: scene, screen: shot.screen, into: dir)
            }
        }
        NSApp.terminate(nil)
    }

    var isPlaying: Bool { !scenes.isEmpty }

    func play(_ settings: LaunchSettings) async {
        guard !isPlaying, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        launcher.hide()
        SoundFX.shared.isEnabled = settings.sound
        let screens = NSScreen.screens.filter { settings.displays.contains(Snapshot.displayID(of: $0)) }
        let shots = await Snapshot.captureAll(screens)
        let icons = DesktopIcons.read()
        let windowFrames = await Snapshot.windowFrames()
        self.shots = shots
        show(shots, icons: DesktopIcons.uncovered(icons, by: windowFrames), controls: settings.controls)
        select(settings.tool)
    }

    /// Esc during play: drop the overlays and bring the launcher back for another go.
    func backToLauncher() {
        for window in windows {
            (window.contentView as? SKView)?.presentScene(nil)
            window.orderOut(nil)
        }
        windows.removeAll()
        scenes.removeAll()
        shots.removeAll()
        NSCursor.arrow.set()
        launcher.show()
    }

    private func show(_ shots: [ScreenShot], icons: [DesktopIcon], controls: CGDirectDisplayID) {
        for shot in shots {
            let window = OverlayWindow(contentRect: shot.screen.frame, styleMask: .borderless,
                                       backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.setFrame(shot.screen.frame, display: false)
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.isOpaque = true
            window.hasShadow = false
            window.acceptsMouseMovedEvents = true
            if let space = shot.image.colorSpace { window.colorSpace = NSColorSpace(cgColorSpace: space) }

            let view = SKView(frame: CGRect(origin: .zero, size: shot.screen.frame.size))
            view.ignoresSiblingOrder = true
            view.preferredFramesPerSecond = shot.screen.maximumFramesPerSecond
            let scene = DeskScene(shot: shot, icons: icons,
                                  showsControls: Snapshot.displayID(of: shot.screen) == controls)
            scene.onPickTool = { [weak self] tool in self?.select(tool) }
            scene.onSweepRequest = { [weak self] in self?.scenes.forEach { $0.sweep() } }
            view.presentScene(scene)
            window.contentView = view
            (view.layer as? CAMetalLayer)?.colorspace = shot.image.colorSpace
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
            scenes.append(scene)
        }
        NSApp.activate()
    }

    private func select(_ tool: DeskScene.Tool) {
        scenes.forEach { $0.tool = tool }
        (tool == .minigun ? NSCursor.crosshair : NSCursor.arrow).set()
    }

    private func installKeys() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 12 && event.modifierFlags.contains(.command) {  // ⌘Q
                NSApp.terminate(nil)
                return nil
            }
            guard isPlaying else {
                if [36, 76].contains(event.keyCode) && launcher.isVisible {  // Return, Enter
                    launcher.start()
                    return nil
                }
                return event
            }
            switch event.keyCode {
            case 53: backToLauncher()  // Esc
            case 2: scenes.forEach { $0.toggleDebug() }  // D
            case 8: scenes.forEach { $0.sweep() }  // C
            case 18: select(.hammer)  // 1
            case 19: select(.minigun)  // 2
            default: return event
            }
            return nil
        }
    }
}
