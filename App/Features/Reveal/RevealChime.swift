import AVFoundation
import os

/// The reveal sound (spec §5.8, §8.7): a soft two-note chime as a bud opens, only when Settings › "Reveal sound" is
/// on (it is off by default). It plays through the ambient session, so it mixes with whatever else is playing and
/// stays silent with the ring/silent switch off.
///
/// The chime is synthesised once into a short buffer (C6 then G6, bell-like partials, a gentle 6 ms attack and a
/// sub-second decay), so there is no audio file to ship. The engine stops a few seconds after the last chime.
@MainActor
final class RevealChime {
    static let shared = RevealChime()

    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var buffer: AVAudioPCMBuffer?
    private var stopTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.maanvikgupta.maple", category: "sound")

    private init() {}

    func play() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default)
            try session.setActive(true)
            let (engine, player, buffer) = try prepared()
            if !engine.isRunning { try engine.start() }
            player.scheduleBuffer(buffer, at: nil, options: [.interrupts])
            if !player.isPlaying { try player.playAudio() }
            stopSoon()
        } catch {
            logger.error("Couldn't play the reveal chime: \(String(describing: error), privacy: .public)")
        }
    }

    private func prepared() throws -> (AVAudioEngine, AVAudioPlayerNode, AVAudioPCMBuffer) {
        if let engine, let player, let buffer { return (engine, player, buffer) }
        let buffer = try Self.chime()
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        try engine.connectNode(player, to: engine.mainMixerNode, format: buffer.format)
        self.engine = engine
        self.player = player
        self.buffer = buffer
        return (engine, player, buffer)
    }

    /// Lets the session go a few seconds after the chime, so other audio returns to full volume and nothing runs.
    private func stopSoon() {
        stopTask?.cancel()
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self else { return }
            self.player?.stop()
            self.engine?.stop()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private struct ChimeError: Error {}

    /// 1.8 s of mono audio: a soft C6, and a G6 110 ms later, each with two quickly fading overtones.
    private static func chime() throws -> AVAudioPCMBuffer {
        let rate = 44_100.0
        let duration = 1.8
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(rate * duration)),
              let samples = buffer.floatChannelData?[0] else { throw ChimeError() }
        buffer.frameLength = buffer.frameCapacity
        func bell(_ frequency: Double, at t: Double) -> Double {
            guard t >= 0 else { return 0 }
            let envelope = min(1, t / 0.006) * exp(-t / 0.45)
            let tone = 0.62 * sin(2 * .pi * frequency * t)
                + 0.24 * sin(2 * .pi * frequency * 2.01 * t) * exp(-t / 0.18)
                + 0.14 * sin(2 * .pi * frequency * 2.76 * t) * exp(-t / 0.1)
            return envelope * tone
        }
        for index in 0..<Int(buffer.frameLength) {
            let t = Double(index) / rate
            // Quiet on purpose: a chime, not an alert.
            samples[index] = Float(0.14 * (bell(1046.5, at: t) + 0.7 * bell(1568.0, at: t - 0.11)))
        }
        return buffer
    }
}
