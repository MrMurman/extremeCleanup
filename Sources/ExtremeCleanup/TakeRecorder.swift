import AppKit
import ScreenCaptureKit

/// Films the stage of a directed take to a movie, with the game's own sound and without the system pointer.
@available(macOS 15, *)
final class TakeRecorder: NSObject, SCRecordingOutputDelegate, @unchecked Sendable {
    enum Failure: Error, CustomStringConvertible {
        case noDisplay
        var description: String { "the display to record is not available to screen capture" }
    }

    private let lock = NSLock()
    private var startedAt: ContinuousClock.Instant?
    private var onStart: CheckedContinuation<ContinuousClock.Instant, Error>?
    private var onFinish: CheckedContinuation<Void, Error>?
    private var stream: SCStream?

    /// Starts filming `stage` (scene points, bottom-left origin) and returns when the first frame is written.
    func start(screen: NSScreen, stage: CGRect, to url: URL) async throws -> ContinuousClock.Instant {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == Snapshot.displayID(of: screen) }) else {
            throw Failure.noDisplay
        }
        // Only this app: its overlay covers the whole display, and other apps' sounds stay out of the take.
        let ownApp = content.applications.filter { $0.processID == getpid() }
        let filter = SCContentFilter(display: display, including: ownApp, exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.sourceRect = CGRect(x: stage.minX, y: screen.frame.height - stage.maxY,
                                   width: stage.width, height: stage.height)
        config.width = Int(stage.width * screen.backingScaleFactor)
        config.height = Int(stage.height * screen.backingScaleFactor)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.showsCursor = false
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = false
        config.sampleRate = 48_000
        config.channelCount = 2

        let recording = SCRecordingOutputConfiguration()
        recording.outputURL = url
        recording.outputFileType = .mov
        recording.videoCodecType = .hevc
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addRecordingOutput(SCRecordingOutput(configuration: recording, delegate: self))
        self.stream = stream
        try await stream.startCapture()
        return try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                if let startedAt { continuation.resume(returning: startedAt) } else { onStart = continuation }
            }
        }
    }

    /// Stops filming and returns once the movie is finalised.
    func stop() async throws {
        guard let stream else { return }
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock { onFinish = continuation }
            Task { try? await stream.stopCapture() }
        }
        self.stream = nil
    }

    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        let now = ContinuousClock.now
        lock.withLock {
            startedAt = now
            onStart?.resume(returning: now)
            onStart = nil
        }
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        lock.withLock {
            onStart?.resume(throwing: error)
            onStart = nil
            onFinish?.resume(throwing: error)
            onFinish = nil
        }
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        lock.withLock {
            onFinish?.resume()
            onFinish = nil
        }
    }
}
