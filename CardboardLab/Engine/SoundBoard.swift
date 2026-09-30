import AVFoundation
import Foundation

enum Sfx: CaseIterable {
    case cut, score, glue, fold, snap, success, coin, pop, tap, whoosh
}

/// Tiny synthesiser: every sound effect is generated at launch (no audio assets), and
/// played through a small pool of player nodes so sounds can overlap.
@MainActor
final class SoundBoard {
    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var buffers: [Sfx: AVAudioPCMBuffer] = [:]
    private var lastPlayed: [Sfx: Double] = [:]
    private var nextPlayer = 0
    private var started = false
    private let sampleRate: Double = 44_100
    var isEnabled: () -> Bool = { true }

    init() {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }
        for _ in 0..<8 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            players.append(p)
        }
        for s in Sfx.allCases {
            if let b = synthesize(s, format: format) { buffers[s] = b }
        }
    }

    private func ensureStarted() {
        guard !started else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        do {
            try engine.start()
            started = true
        } catch {
            started = false
        }
    }

    /// Plays an effect; `minInterval` throttles rapid repeats (e.g. while cutting).
    func play(_ s: Sfx, volume: Float = 1, minInterval: Double = 0, now: Double = uptimeSeconds()) {
        guard isEnabled(), let buffer = buffers[s], !players.isEmpty else { return }
        if minInterval > 0, let last = lastPlayed[s], now - last < minInterval { return }
        lastPlayed[s] = now
        ensureStarted()
        guard started else { return }
        let p = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        p.stop()
        p.volume = volume
        p.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        p.play()
    }

    // MARK: Synthesis

    private func synthesize(_ s: Sfx, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let samples = render(s)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for (i, v) in samples.enumerated() { channel[i] = v }
        return buffer
    }

    private func render(_ s: Sfx) -> [Float] {
        let sr = Float(sampleRate)
        func buffer(_ seconds: Float, _ f: (Float, Float) -> Float) -> [Float] {
            let n = Int(seconds * sr)
            return (0..<n).map { i in
                let t = Float(i) / sr
                return f(t, t / seconds)
            }
        }
        var noiseState: UInt32 = 0x1234_5678
        func noise() -> Float {
            noiseState ^= noiseState << 13
            noiseState ^= noiseState >> 17
            noiseState ^= noiseState << 5
            return Float(noiseState) / Float(UInt32.max) * 2 - 1
        }
        func sine(_ freq: Float, _ t: Float) -> Float { sin(2 * .pi * freq * t) }

        switch s {
        case .cut:
            // Scratchy: differentiated noise with a fast decay.
            var prev: Float = 0
            return buffer(0.07) { _, k in
                let n = noise()
                let v = (n - prev) * 0.5
                prev = n
                return v * exp(-k * 5) * 0.55
            }
        case .score:
            var lp: Float = 0
            return buffer(0.09) { _, k in
                lp += (noise() - lp) * 0.18
                return lp * exp(-k * 4) * 0.7
            }
        case .glue:
            return buffer(0.14) { t, k in
                let f = 190 - 80 * k
                return (sine(f, t) * 0.6 + noise() * 0.08) * sin(.pi * k) * 0.5
            }
        case .fold:
            return buffer(0.2) { t, k in
                let click: Float = k < 0.05 ? noise() * (1 - k / 0.05) * 0.4 : 0
                return (sine(115, t) * exp(-k * 7) * 0.7 + click)
            }
        case .snap:
            return buffer(0.16) { t, k in
                let click: Float = k < 0.08 ? noise() * (1 - k / 0.08) * 0.5 : 0
                return sine(170 - 60 * k, t) * exp(-k * 9) * 0.8 + click
            }
        case .success:
            return buffer(0.42) { t, k in
                let note: Float = k < 0.4 ? 659.3 : 987.8
                let local = k < 0.4 ? k / 0.4 : (k - 0.4) / 0.6
                let tone = sine(note, t) * 0.6 + sine(note * 2, t) * 0.15
                return tone * exp(-local * 4) * 0.4
            }
        case .coin:
            return buffer(0.26) { t, k in
                let note: Float = k < 0.3 ? 1318.5 : 1975.5
                let local = k < 0.3 ? k / 0.3 : (k - 0.3) / 0.7
                return sine(note, t) * exp(-local * 5) * 0.3
            }
        case .pop:
            return buffer(0.35) { t, k in
                (noise() * exp(-k * 12) * 0.5 + sine(520 - 300 * k, t) * exp(-k * 5) * 0.35)
            }
        case .tap:
            return buffer(0.035) { t, k in sine(900, t) * (1 - k) * 0.25 }
        case .whoosh:
            var lp: Float = 0
            return buffer(0.45) { _, k in
                lp += (noise() - lp) * (0.02 + 0.1 * k)
                return lp * sin(.pi * k) * 1.4
            }
        }
    }
}

/// Monotonic time in seconds.
func uptimeSeconds() -> Double {
    ProcessInfo.processInfo.systemUptime
}
