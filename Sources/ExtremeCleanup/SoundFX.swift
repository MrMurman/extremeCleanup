import AVFoundation

/// Procedurally synthesised effects, so the app ships no audio files.
final class SoundFX {
    enum Effect { case thud, crack, shatter, shot, sweep, blow }

    static let shared = SoundFX()

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var buffers: [Effect: AVAudioPCMBuffer] = [:]
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    /// Wind has its own stereo voice: gusts are long and pan across, and mustn't steal effect voices.
    private let windPlayer = AVAudioPlayerNode()
    private let stereo = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
    private var windNoise = SeededRandom(seed: 7)
    /// Gusts are synthesised here: a few seconds of stereo noise is too much work for a frame.
    private let synthQueue = DispatchQueue(label: "SoundFX.gusts", qos: .userInitiated)

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
        var airy: Float = 0
        buffers[.blow] = synth(seconds: 0.7) { t, noise in
            airy += (noise - airy) * 0.3  // lighter low-pass than the broom: an airier rush
            return airy * sin(.pi * t / 0.7) * 1.8
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
        engine.attach(windPlayer)
        engine.connect(windPlayer, to: engine.mainMixerNode, format: stereo)
        engine.mainMixerNode.outputVolume = 0.6
        try? engine.start()
        // Voices run from the start and only ever get buffers queued: starting a player node waits on
        // the audio thread, which showed up as dropped frames when done per effect.
        (players + [windPlayer]).forEach { $0.play() }
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
        if !player.isPlaying { player.play() }  // only after the engine was stopped, e.g. an output change
        played += 1
    }

    /// A soft whoosh for one gust: swells and fades over `seconds` and pans from the upwind side
    /// to the downwind side. Synthesised per gust, since every gust has its own length.
    func playGust(seconds: Double, strength: Double, direction: Double) {
        guard isEnabled, engine.isRunning else { return }
        played += 1
        synthQueue.async { [self] in
            guard let buffer = gustBuffer(seconds: seconds, strength: strength, direction: direction) else { return }
            windPlayer.scheduleBuffer(buffer, at: nil, options: .interrupts)
            if !windPlayer.isPlaying { windPlayer.play() }
        }
    }

    func gustBuffer(seconds: Double, strength: Double, direction: Double) -> AVAudioPCMBuffer? {
        let rate = stereo.sampleRate, frames = AVAudioFrameCount(seconds * rate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: stereo, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        let left = buffer.floatChannelData![0], right = buffer.floatChannelData![1]
        let flutter = Float.random(in: 0..<(2 * .pi)), gain = Float(0.09 + 0.13 * strength)  // background: about a third of the blower
        var low: Float = 0, lower: Float = 0
        for i in 0..<Int(frames) {
            let p = Float(Double(i) / Double(frames))
            let noise = Float(Int64(bitPattern: windNoise.next()) >> 11) / Float(1 << 52)
            low += (noise - low) * 0.06    // two low-pass stages: a whoosh, not a hiss
            lower += (low - lower) * 0.06
            let swell = pow(sin(.pi * p), 2) * (0.8 + 0.2 * sin(flutter + p * 19))
            let v = max(-1, min(1, lower * 9 * swell * gain))
            let pan = (direction > 0 ? p : 1 - p) * .pi / 2  // equal-power: left at 0, right at π/2
            left[i] = v * cos(pan); right[i] = v * sin(pan)
        }
        return buffer
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
