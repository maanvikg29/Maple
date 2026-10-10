import AVFoundation
import os

/// The reveal sound (spec §5.8, §8.7): a soft two-note chime as a bud opens, only when Settings › "Reveal sound" is
/// on (it is off by default). It plays through the ambient session, so it mixes with whatever else is playing and
/// stays silent with the ring/silent switch off.
///
/// The chime is synthesised once into a short buffer (C6 then G6, bell-like partials, a gentle 6 ms attack and a
/// sub-second decay), so there is no audio file to ship. Nothing here runs on the main actor: the audio session, the
/// synthesis and the engine belong to `RevealChimeAudio`, so a tap never stalls the unfurl's first frames.
///
/// ```swift
/// RevealChime.shared.prepare()   // the reveal cover appeared with Reveal sound on
/// RevealChime.shared.play()      // a bud opened
/// RevealChime.shared.release()   // the cover went
/// ```
@MainActor
final class RevealChime {
    static let shared = RevealChime()

    private let audio = RevealChimeAudio()

    private init() {}

    /// Warms the session, the buffer and the engine for a sitting, so the first tap only schedules the chime.
    func prepare() {
        let audio = audio
        Task { await audio.prepare() }
    }

    func play() {
        let audio = audio
        Task { await audio.play() }
    }

    /// The sitting is over: the engine stops and other audio returns to full volume.
    func release() {
        let audio = audio
        Task { await audio.release() }
    }
}

/// The chime's audio, on its own actor: the session, the synthesised buffer and the engine, which runs for a reveal
/// sitting (stopped when the cover goes, or a minute after the warm-up or the last chime should it stay).
actor RevealChimeAudio {
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var buffer: AVAudioPCMBuffer?
    private var idleStop: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.maanvikgupta.maple", category: "sound")

    func prepare() {
        do {
            try running()
            stopWhenIdle()
        } catch {
            logger.error("Couldn't prepare the reveal chime: \(String(describing: error), privacy: .public)")
        }
    }

    func play() {
        do {
            let (player, buffer) = try running()
            player.scheduleBuffer(buffer, at: nil, options: [.interrupts])
            if !player.isPlaying { try player.playAudio() }
            stopWhenIdle()
        } catch {
            logger.error("Couldn't play the reveal chime: \(String(describing: error), privacy: .public)")
        }
    }

    func release() {
        idleStop?.cancel()
        idleStop = nil
        stop()
    }

    /// The ambient session active and the engine built and running.
    @discardableResult
    private func running() throws -> (AVAudioPlayerNode, AVAudioPCMBuffer) {
        let session = AVAudioSession.sharedInstance()
        if session.category != .ambient { try session.setCategory(.ambient, mode: .default) }
        let engine: AVAudioEngine, player: AVAudioPlayerNode, buffer: AVAudioPCMBuffer
        if let built = self.engine, let builtPlayer = self.player, let builtBuffer = self.buffer {
            (engine, player, buffer) = (built, builtPlayer, builtBuffer)
        } else {
            buffer = try Self.chime()
            engine = AVAudioEngine()
            player = AVAudioPlayerNode()
            engine.attach(player)
            try engine.connectNode(player, to: engine.mainMixerNode, format: buffer.format)
            engine.prepare()
            (self.engine, self.player, self.buffer) = (engine, player, buffer)
        }
        if !engine.isRunning {
            try session.setActive(true)
            try engine.start()
        }
        return (player, buffer)
    }

    private func stop() {
        guard let engine, engine.isRunning else { return }
        player?.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// A cover left open doesn't keep the engine running: it stops a minute after the warm-up or the last chime.
    private func stopWhenIdle() {
        idleStop?.cancel()
        idleStop = Task {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            stop()
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
