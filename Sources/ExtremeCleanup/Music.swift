import AVFoundation

/// The theme: one synth loop composed and rendered in code at launch, then looped.
final class Music {
    enum Mood { case launcher, play, finale }

    static let shared = Music()

    var isEnabled = true { didSet { fade() } }
    private(set) var mood: Mood = .launcher
    private(set) var renderSeconds: Double = 0
    private(set) var loop: (left: [Float], right: [Float])?
    var volume: Float { player.volume }
    var targetVolume: Float {
        guard isEnabled else { return 0 }
        switch mood {
        case .launcher: return 0.55
        case .play: return 0.22
        case .finale: return 0
        }
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var fader: Timer?

    private init() {}

    /// Renders the loop off the main thread and starts it, silent until a mood asks for it.
    func prepare() {
        DispatchQueue.global(qos: .userInitiated).async {
            let start = Date()
            let loop = Composer.render(sampleRate: 44_100)
            let seconds = Date().timeIntervalSince(start)
            DispatchQueue.main.async {
                self.renderSeconds = seconds
                self.loop = loop
                self.start(loop)
            }
        }
    }

    func set(_ mood: Mood) {
        self.mood = mood
        fade()
    }

    /// Writes the loop as a 16-bit stereo WAV, e.g. for cutting videos to the same track.
    static func export(to url: URL) throws {
        let loop = Composer.render(sampleRate: 44_100)
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100,
                                       AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(loop.left.count))!
        buffer.frameLength = buffer.frameCapacity
        loop.left.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: $0.count) }
        loop.right.withUnsafeBufferPointer { buffer.floatChannelData![1].update(from: $0.baseAddress!, count: $0.count) }
        try file.write(from: buffer)
    }

    private func start(_ loop: (left: [Float], right: [Float])) {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(loop.left.count))
        else { return }
        buffer.frameLength = buffer.frameCapacity
        loop.left.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: $0.count) }
        loop.right.withUnsafeBufferPointer { buffer.floatChannelData![1].update(from: $0.baseAddress!, count: $0.count) }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        guard (try? engine.start()) != nil else { return }
        player.volume = 0
        player.scheduleBuffer(buffer, at: nil, options: .loops)
        player.play()
        fade()
    }

    private func fade() {
        fader?.invalidate()
        guard loop != nil else { return }
        fader = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            let target = targetVolume, step: Float = mood == .finale ? 0.005 : 0.02
            let current = player.volume
            if abs(target - current) <= step {
                player.volume = target
                timer.invalidate()
            } else {
                player.volume = current + (target > current ? step : -step)
            }
        }
    }
}

/// An original 80s-horror synth piece: a twisting minor arpeggio over a pumping bass and a slow pad, with a filter
/// that breathes every 8 bars. Am – F – Dm – E, two bars each, 32 bars at 100 BPM.
enum Composer {
    static let bpm = 100.0
    static let bars = 32

    private struct Chord { let bass: Int; let third: Int }
    private static let chords = [Chord(bass: 33, third: 3), Chord(bass: 29, third: 4),
                                 Chord(bass: 38, third: 3), Chord(bass: 40, third: 4)]
    /// Indexes into root, fifth, octave, tenth, twelfth: it turns back on itself rather than running up and down.
    private static let arpPattern = [0, 2, 1, 3, 2, 4, 3, 1, 0, 2, 1, 3, 2, 4, 3, 2]
    /// (start beat, length in beats, MIDI note) over one 8-bar phrase.
    private static let melody: [(Double, Double, Int)] = [
        (0, 3, 76), (3, 1, 74), (4, 4, 72),
        (8, 3, 72), (11, 1, 69), (12, 4, 72),
        (16, 3, 74), (19, 1, 77), (20, 4, 76),
        (24, 4, 71), (28, 3.5, 68),
    ]

    static func render(sampleRate sr: Double) -> (left: [Float], right: [Float]) {
        let beat = 60 / bpm
        let n = Int(Double(bars) * 4 * beat * sr)
        let total = n + Int(5 * sr)
        var left = [Float](repeating: 0, count: total)
        var right = [Float](repeating: 0, count: total)
        var send = [Float](repeating: 0, count: total)
        var noise = SeededRandom(seed: 13)

        func hz(_ midi: Double) -> Double { 440 * pow(2, (midi - 69) / 12) }
        func chord(atBar bar: Int) -> Chord { chords[(bar / 2) % chords.count] }

        // Arpeggio: two saws through a resonant low-pass whose cutoff opens and closes over 8 bars.
        for step in 0..<(bars * 16) {
            let bar = step / 16
            let c = chord(atBar: bar)
            let root = c.bass + 12
            let tones = [root, root + 7, root + 12, root + 12 + c.third, root + 19]
            let f = hz(Double(tones[arpPattern[step % 16]]))
            let start = Double(step) * beat / 4
            let breath = 0.5 - 0.5 * cos(2 * .pi * start / (8 * 4 * beat))
            let base = 320 * pow(9, breath)
            let accent = step % 4 == 0 ? 1.0 : 0.72
            voice(into: &left, &right, send: &send, sendLevel: 0.22, pan: 0.15 * sin(Double(step) * 0.7),
                  start: start, length: beat / 4 * 0.92, sr: sr) { t, phase in
                let env = exp(-t / 0.09)
                let saw = blepSaw(phase(f)) + 0.6 * blepSaw(phase(f * 1.004))
                return (saw, env * 0.16 * accent, min(6000, base * (1 + 2.5 * env)))
            }
        }

        // Bass: pumping eighths an octave under the arp.
        for eighth in 0..<(bars * 8) {
            let f = hz(Double(chord(atBar: eighth / 8).bass))
            let accent = eighth % 2 == 0 ? 1.0 : 0.75
            voice(into: &left, &right, send: &send, sendLevel: 0, pan: 0,
                  start: Double(eighth) * beat / 2, length: beat / 2 * 0.85, sr: sr) { t, phase in
                let env = exp(-t / 0.16)
                return (blepSaw(phase(f)), env * 0.3 * accent, 180 + 500 * env)
            }
        }

        // Pad: a detuned triad per chord, slow in and slow out, spread wide.
        for bar in stride(from: 0, to: bars, by: 2) {
            let c = chord(atBar: bar)
            let start = Double(bar) * 4 * beat, length = 8 * beat
            for note in [c.bass + 24, c.bass + 24 + c.third, c.bass + 31] {
                for (cents, pan) in [(-9.0, -0.8), (0.0, 0.0), (9.0, 0.8)] {
                    let f = hz(Double(note) + cents / 100)
                    voice(into: &left, &right, send: &send, sendLevel: 0.1, pan: pan, start: start,
                          length: length + 1.2, sr: sr) { t, phase in
                        let env = min(1, t / 0.9) * (t > length ? max(0, 1 - (t - length) / 1.2) : 1)
                        return (blepSaw(phase(f)), env * 0.028, 1100)
                    }
                }
            }
        }

        // Hi-hat from bar 8: closed sixteenths, an open hat on the off-beat.
        for step in (8 * 16)..<(bars * 16) {
            let open = step % 4 == 2
            let start = Int(Double(step) * beat / 4 * sr)
            let decay = open ? 0.08 : 0.022
            var low: Double = 0
            for i in 0..<Int((open ? 0.25 : 0.08) * sr) where start + i < total {
                let t = Double(i) / sr
                let white = Double(noise.range(-1...1))
                low += (white - low) * 0.35
                let v = Float((white - low) * exp(-t / decay) * (open ? 0.05 : 0.035) * min(1, t / 0.001))
                left[start + i] += v * 0.8
                right[start + i] += v
            }
        }

        // Kick on beats one and three, and the lead melody with its echo, in the second half.
        for bar in 16..<bars {
            for b in [0, 2] {
                let start = Int((Double(bar * 4 + b)) * beat * sr)
                var phase = 0.0
                for i in 0..<Int(0.35 * sr) where start + i < total {
                    let t = Double(i) / sr
                    phase += (45 + 70 * exp(-t / 0.03)) / sr
                    let v = Float(sin(2 * .pi * phase) * exp(-t / 0.18) * 0.42 * min(1, t / 0.002))
                    left[start + i] += v
                    right[start + i] += v
                }
            }
        }
        for phrase in [16, 24] {
            for (at, beats, note) in melody {
                let f = hz(Double(note))
                let length = beats * beat
                voice(into: &left, &right, send: &send, sendLevel: 0.55, pan: -0.1,
                      start: (Double(phrase * 4) + at) * beat, length: length + 0.25, sr: sr) { t, phase in
                    let vibrato = pow(2, 0.2 / 12 * sin(2 * .pi * 5.5 * t) * min(1, max(0, t - 0.25) / 0.4))
                    let p = phase(f * vibrato)
                    let env = min(1, t / 0.03) * (t > length ? max(0, 1 - (t - length) / 0.25) : 1)
                    return (0.6 * blepSaw(p) + 0.8 * sin(2 * .pi * p.0), env * 0.11, 1600)
                }
            }
        }

        // Ping-pong echo, three sixteenths apart.
        let d = Int(0.75 * beat * sr)
        var echoL = [Float](repeating: 0, count: total), echoR = [Float](repeating: 0, count: total)
        for i in d..<total {
            echoL[i] = send[i - d] + 0.38 * echoR[i - d]
            echoR[i] = echoL[i - d]
            left[i] += echoL[i] * 0.5
            right[i] += echoR[i] * 0.5
        }

        // Fold the tail over the start so the loop point is seamless, then level it.
        for i in 0..<(total - n) {
            left[i] += left[n + i]
            right[i] += right[n + i]
        }
        left.removeLast(total - n)
        right.removeLast(total - n)
        // Tape-style saturation: tames the kick's peaks so the whole mix can sit louder.
        let peak = max(left.map(abs).max() ?? 1, right.map(abs).max() ?? 1, 0.001)
        let drive = Float(2.2) / peak, ceiling = Float(0.85) / tanh(Float(2.2))
        for i in 0..<n {
            left[i] = tanh(left[i] * drive) * ceiling
            right[i] = tanh(right[i] * drive) * ceiling
        }
        return (left, right)
    }

    /// Renders one note: `sound(t, phase)` returns (oscillator, amplitude, filter cutoff) at time `t`, where
    /// `phase(f)` advances an oscillator at frequency `f` and returns its phase in 0..<1.
    private static func voice(into left: inout [Float], _ right: inout [Float], send: inout [Float], sendLevel: Float,
                              pan: Double, start: Double, length: Double, sr: Double,
                              sound: (Double, (Double) -> (Double, Double)) -> (Double, Double, Double)) {
        let first = Int(start * sr)
        let count = min(Int(length * sr), left.count - first)
        guard count > 0 else { return }
        let gl = Float(sqrt(0.5 * (1 - pan))), gr = Float(sqrt(0.5 * (1 + pan)))
        var low = 0.0, band = 0.0
        var phases: [Double] = [0, 0, 0]
        for i in 0..<count {
            let t = Double(i) / sr
            var k = 0
            let (osc, amp, cutoff) = sound(t) { f in
                defer { k += 1 }
                phases[k] += f / sr
                phases[k] -= floor(phases[k])
                return (phases[k], f / sr)
            }
            // Chamberlin state-variable low-pass, a touch of resonance.
            let fc = 2 * sin(.pi * min(cutoff, sr / 7) / sr)
            low += fc * band
            let high = osc - low - 0.55 * band
            band += fc * high
            // Short fade at both ends so no note clicks.
            let edge = min(1, t / 0.003, Double(count - i) / sr / 0.005)
            let v = Float(low * amp * edge)
            left[first + i] += v * gl
            right[first + i] += v * gr
            send[first + i] += v * sendLevel
        }
    }

    /// Band-limited sawtooth from a phase and its per-sample increment.
    private static func blepSaw(_ p: (Double, Double)) -> Double {
        let (t, dt) = p
        var blep = 0.0
        if t < dt {
            let x = t / dt
            blep = x + x - x * x - 1
        } else if t > 1 - dt {
            let x = (t - 1) / dt
            blep = x * x + x + x + 1
        }
        return 2 * t - 1 - blep
    }
}
