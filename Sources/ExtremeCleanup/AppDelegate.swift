import AppKit
import SpriteKit
import QuartzCore

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Declares the hidden pointer as this view's own, so macOS re-applies it whenever the mouse is over the game.
final class OverlayView: SKView {
    override func resetCursorRects() { addCursorRect(bounds, cursor: ToolCursor.blank) }
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
        launcher.onChange = { Music.shared.isEnabled = $0.music }
        launcher.onQuit = { NSApp.terminate(nil) }
        return launcher
    }()

    /// `--self-check <dir>`: re-capture the screen with the overlay up, write a pixel diff report, quit.
    private let selfCheckDir = AppDelegate.directory(after: "--self-check")
    /// `--demo-hammer|minigun|void|sweep|belt|cursor <dir>`: scripted run on the main display, with captures and a report.
    private let hammerDemoDir = AppDelegate.directory(after: "--demo-hammer")
    private let minigunDemoDir = AppDelegate.directory(after: "--demo-minigun")
    private let voidDemoDir = AppDelegate.directory(after: "--demo-void")
    private let sweepDemoDir = AppDelegate.directory(after: "--demo-sweep")
    private let beltDemoDir = AppDelegate.directory(after: "--demo-belt")
    private let cursorDemoDir = AppDelegate.directory(after: "--demo-cursor")
    /// `--demo-launcher <dir>`: drives the launcher through Start, Esc and a second Start; `--demo-recall <dir>`
    /// checks on a later launch that the choices came back.
    private let launcherDemoDir = AppDelegate.directory(after: "--demo-launcher")
    private let recallDemoDir = AppDelegate.directory(after: "--demo-recall")
    /// `--direct <choreography.json>`: play a scripted take on the main display; Space starts it, Esc quits.
    private let choreography = AppDelegate.directory(after: "--direct")
    private var director: Director?

    private static func argument(after flag: String) -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    private static func directory(after flag: String) -> URL? {
        argument(after: flag).map { URL(fileURLWithPath: $0) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        /// `--export-music <file.wav>`: write the theme and quit.
        if let path = AppDelegate.argument(after: "--export-music") {
            try? Music.export(to: URL(fileURLWithPath: path))
            NSApp.terminate(nil)
            return
        }
        installKeys()
        Music.shared.prepare()
        if let choreography {
            Task { await direct(choreography) }
            return
        }
        let scripted = [selfCheckDir, hammerDemoDir, minigunDemoDir, voidDemoDir, sweepDemoDir, beltDemoDir, cursorDemoDir]
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
        await play(LaunchSettings(displays: [main], controls: main, sound: true, music: true))
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
            } else if let dir = cursorDemoDir {
                await Demo.cursor(scene: scene, screen: shot.screen, select: { [weak self] in self?.select($0) }, into: dir)
            } else if let dir = voidDemoDir {
                await Demo.void(scene: scene, screen: shot.screen, into: dir)
            }
        }
        NSApp.terminate(nil)
    }

    /// Straight into play on the main display with the choreography's sound and music, then the take.
    private func direct(_ file: URL) async {
        do {
            let choreography = try Choreography.load(file)
            let main = Snapshot.displayID(of: NSScreen.screens[0])
            await play(LaunchSettings(displays: [main], controls: main, sound: choreography.sound,
                                      music: choreography.music))
            guard let scene = scenes.first, let shot = shots.first else { return NSApp.terminate(nil) }
            let director = try Director(choreography, from: file, scene: scene, screen: shot.screen,
                                        icons: DesktopIcons.read(), select: { [weak self] in self?.select($0) })
            self.director = director
            print("Ready: press Space to start the take, Esc to quit.")
            let log = try await director.run()
            print("Take done. Log: \(log.path)")
        } catch {
            FileHandle.standardError.write(Data("--direct: \(error)\n".utf8))
            NSApp.terminate(nil)
        }
    }

    var isPlaying: Bool { !scenes.isEmpty }

    func play(_ settings: LaunchSettings) async {
        guard !isPlaying, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        launcher.hide()
        SoundFX.shared.isEnabled = settings.sound
        Music.shared.isEnabled = settings.music
        Music.shared.set(.play)
        let screens = NSScreen.screens.filter { settings.displays.contains(Snapshot.displayID(of: $0)) }
        let shots = await Snapshot.captureAll(screens)
        let icons = DesktopIcons.read()
        let windowFrames = await Snapshot.windowFrames()
        self.shots = shots
        show(shots, icons: DesktopIcons.uncovered(icons, by: windowFrames), controls: settings.controls)
        select(.hammer)
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
        Music.shared.set(.launcher)
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

            let view = OverlayView(frame: CGRect(origin: .zero, size: shot.screen.frame.size))
            view.ignoresSiblingOrder = true
            view.preferredFramesPerSecond = shot.screen.maximumFramesPerSecond
            let scene = DeskScene(shot: shot, icons: icons,
                                  showsControls: Snapshot.displayID(of: shot.screen) == controls)
            scene.onPickTool = { [weak self] tool in self?.select(tool) }
            scene.onSweepRequest = { [weak self] in self?.scenes.forEach { $0.sweep() } }
            scene.onClean = { Music.shared.set(.finale) }
            view.presentScene(scene)
            window.contentView = view
            (view.layer as? CAMetalLayer)?.colorspace = shot.image.colorSpace
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
            scenes.append(scene)
        }
        NSApp.activate()
    }

    /// M during play; the launcher shows the new choice and it is saved with the next Start.
    func toggleMusic() {
        var settings = launcher.settings
        settings.music.toggle()
        launcher.choose(settings)
    }

    private func select(_ tool: DeskScene.Tool) {
        scenes.forEach { $0.tool = tool }
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
            if let director {
                switch event.keyCode {
                case 49: director.start()  // Space
                case 53: NSApp.terminate(nil)  // Esc
                default: return event
                }
                return nil
            }
            switch event.keyCode {
            case 53: backToLauncher()  // Esc
            case 2: scenes.forEach { $0.toggleDebug() }  // D
            case 8: scenes.forEach { $0.sweep() }  // C
            case 46: toggleMusic()  // M
            case 18: select(.hammer)  // 1
            case 19: select(.minigun)  // 2
            default: return event
            }
            return nil
        }
    }
}
