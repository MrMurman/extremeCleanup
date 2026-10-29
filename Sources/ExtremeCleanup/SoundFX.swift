import AVFoundation

/// Procedurally synthesised effects, so the app ships no audio files.
final class SoundFX {
    enum Effect { case thud, crack, shatter, shot, sweep }

    static let shared = SoundFX()

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var buffers: [Effect: AVAudioPCMBuffer] = [:]
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

    private init() {
        // Enough voices that a stream of gunshots doesn't cut a shatter short.
        for _ in 0..<16 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }
        buffers[.thud] = synth(seconds: 0.3) { t, noise in
            sin(2 * .pi * 70 * t) * exp(-t * 16) * 0.9 + noise * exp(-t * 70) * 0.5
        }
        buffers[.shot] = synth(seconds: 0.12) { t, noise in
            noise * exp(-t * 45) * 0.7 + sin(2 * .pi * 95 * t) * exp(-t * 35) * 0.6
        }
        var smooth: Float = 0
        buffers[.sweep] = synth(seconds: 1.6) { t, noise in
            smooth += (noise - smooth) * 0.08  // low-passed: a broad brushing hiss
            return smooth * sin(.pi * t / 1.6) * 2.2
        }
        var last: Float = 0
        buffers[.crack] = synth(seconds: 0.15) { t, noise in
            let edge = noise - last  // crude high-pass: glassy rather than thuddy
            last = noise
            return edge * exp(-t * 35) * 0.6
        }
        var rng = SeededRandom(seed: 42)
        let pings = (0..<28).map { _ in (start: Float(rng.range(0...0.6)), freq: Float(rng.range(2_200...7_500))) }
        buffers[.shatter] = synth(seconds: 1.1) { t, noise in
            var v = noise * exp(-t * 6) * 0.45
            for p in pings where t > p.start {
                let dt = t - p.start
                v += sin(2 * .pi * p.freq * dt) * exp(-dt * 28) * 0.12
            }
            return v
        }
        try? engine.start()
    }

    var isEnabled = true
    /// Effects actually played since launch.
    private(set) var played = 0

    func play(_ effect: Effect, volume: Float = 1) {
        guard isEnabled, engine.isRunning, let buffer = buffers[effect] else { return }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.volume = volume
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        player.play()
        played += 1
    }

    private func synth(seconds: Float, _ sample: (Float, Float) -> Float) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(seconds * Float(format.sampleRate))
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let out = buffer.floatChannelData![0]
        for i in 0..<Int(frames) {
            out[i] = max(-1, min(1, sample(Float(i) / Float(format.sampleRate), Float.random(in: -1...1))))
        }
        return buffer
    }
}
