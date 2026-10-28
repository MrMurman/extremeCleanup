import AppKit
import SpriteKit
import QuartzCore

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [OverlayWindow] = []
    private var scenes: [DeskScene] = []

    /// `--self-check <dir>`: re-capture the screen with the overlay up, write a pixel diff report, quit.
    private let selfCheckDir: URL? = {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--self-check"), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[i + 1])
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            let shots = await Snapshot.captureAll()
            let icons = DesktopIcons.read()
            show(shots, icons: icons)
            installKeys()
            if let dir = selfCheckDir {
                try? await Task.sleep(for: .seconds(1))
                await SelfCheck.run(shots: shots, icons: icons, into: dir)
                NSApp.terminate(nil)
            }
        }
    }

    private func show(_ shots: [ScreenShot], icons: [DesktopIcon]) {
        for shot in shots {
            let window = OverlayWindow(contentRect: shot.screen.frame, styleMask: .borderless,
                                       backing: .buffered, defer: false)
            window.setFrame(shot.screen.frame, display: false)
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.isOpaque = true
            window.hasShadow = false
            if let space = shot.image.colorSpace { window.colorSpace = NSColorSpace(cgColorSpace: space) }

            let view = SKView(frame: CGRect(origin: .zero, size: shot.screen.frame.size))
            view.ignoresSiblingOrder = true
            let scene = DeskScene(shot: shot, icons: icons)
            view.presentScene(scene)
            window.contentView = view
            (view.layer as? CAMetalLayer)?.colorspace = shot.image.colorSpace
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
            scenes.append(scene)
        }
        NSApp.activate()
    }

    private func installKeys() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            switch event.keyCode {
            case 53: NSApp.terminate(nil)  // Esc
            case 12 where event.modifierFlags.contains(.command): NSApp.terminate(nil)  // ⌘Q
            case 2: self?.scenes.forEach { $0.toggleDebug() }  // D
            default: return event
            }
            return nil
        }
    }
}
