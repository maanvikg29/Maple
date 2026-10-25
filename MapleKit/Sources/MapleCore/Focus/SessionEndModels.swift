import Foundation
import MapleFocusCore

/// End early, for Gentle and Steady (F1 design §5.6): a sheet over the session. Copy and timings are `FocusCopy.EndEarly`'s.
public struct EndEarlyModel: Sendable, Equatable {
    public enum Stage: Sendable, Equatable {
        /// "End this session?", with the way out still to take.
        case asking
        /// The way out was taken: the session ends when this many seconds have passed (Steady's quiet 15, Gentle's
        /// 5-second ring). "Keep going" still cancels.
        case ending(secondsLeft: Int)
    }

    public let path: SessionEndPath
    public let stage: Stage
    /// "End this session?", or "Ending in 15s" once the countdown runs, down to "Ending in 1s".
    public let title: String
    /// The title for VoiceOver: "Ending in 15 seconds".
    public let spokenTitle: String
    /// "18 minutes saved so far. They stay yours either way.", or "This session isn't counting toward leaves."
    public let body: String
    /// The primary, "Keep going", at every stage.
    public let keepGoingTitle: String
    /// Steady while asking: "Hold to end".
    public let holdTitle: String?
    /// Gentle while asking: "End session".
    public let endTitle: String?
    /// Steady while asking and while the preset's break is unused: "Take a 5-minute break instead".
    public let breakInsteadTitle: String?
    /// Gentle's ring, 0...1 of its 5 seconds; nil when it isn't running.
    public let ringProgress: Double?

    /// - Parameters:
    ///   - path: `.gentle` or `.steady` (Locked's way out is `EmergencyReleaseModel`).
    ///   - countedSeconds: This session's counted seconds so far (`FocusSessionStore.countedSoFar(_:)`).
    ///   - breakAvailable: The preset has a break, it is unused, time is left, and apps are locked
    ///     (`RunningSessionModel.breakAvailable(_:at:)`).
    public init(path: SessionEndPath, countedSeconds: Int, breakAvailable: Bool, stage: Stage) {
        self.path = path
        self.stage = stage
        body = FocusCopy.EndEarly.savedLine(countedSeconds: countedSeconds)
        keepGoingTitle = FocusCopy.keepGoing
        switch stage {
        case .asking:
            title = FocusCopy.EndEarly.title
            spokenTitle = title
            holdTitle = path == .steady ? FocusCopy.EndEarly.holdToEnd : nil
            endTitle = path == .gentle ? FocusCopy.EndEarly.gentleEnd : nil
            breakInsteadTitle = path == .steady && breakAvailable ? FocusCopy.EndEarly.takeBreakInstead : nil
            ringProgress = nil
        case .ending(let left):
            // The session ends as the countdown reaches zero, while the sheet is still sliding away: the words stop at
            // 1s, so it never reads "Ending in 0s". The ring runs to its end.
            let shown = max(1, left)
            title = FocusCopy.EndEarly.endingIn(seconds: shown)
            spokenTitle = "Ending in \(shown) \(shown == 1 ? "second" : "seconds")"
            holdTitle = nil
            endTitle = nil
            breakInsteadTitle = nil
            let ring = Self.countdown(for: .gentle)
            let seconds = max(0, left)
            ringProgress = path == .gentle ? min(1, max(0, Double(ring - seconds) / Double(ring))) : nil
        }
    }

    /// How long the countdown runs once the way out is taken: Steady's 15 seconds, Gentle's 5.
    public static func countdown(for path: SessionEndPath) -> Int {
        path == .gentle ? Int(FocusCopy.EndEarly.gentleBreathSeconds) : FocusCopy.EndEarly.countdownSeconds
    }

    /// The whole seconds left of a countdown that ends at `endsAt`, rounded up: "Ending in 15s" first.
    public static func secondsLeft(until endsAt: Date, now: Date) -> Int {
        max(0, Int((endsAt.timeIntervalSince(now) - 1e-9).rounded(.up)))
    }

    /// Gentle's ring breathes once over its 5 seconds: a transform only, none under Reduce Motion.
    public static func ringScale(progress: Double, reduceMotion: Bool) -> Double {
        guard !reduceMotion else { return 1 }
        let p = min(1, max(0, progress))
        return 0.88 + 0.12 * sin(.pi * p)
    }
}

/// Locked's emergency release (F1 design §5.7, F1-1): a 10-second hold, the release as the hold completes, one slow
/// breath (4 seconds in, 4 out), then the ended state. Always there, with no allowance. Copy and timings are
/// `FocusCopy.Emergency`'s. The ended state's numeral and caption follow `ReceiptModel`'s rule for this ending.
public struct EmergencyReleaseModel: Sendable, Equatable {
    public enum Stage: Sendable, Equatable {
        /// The hold, `progress` 0...1 of its 10 seconds.
        case hold(progress: Double)
        /// Released: this many seconds into the breath; from 8 seconds, the ended state.
        case released(seconds: Double)
    }

    /// What the dial's centre shows.
    public enum Centre: Sendable, Equatable {
        /// "10s" over "hold to release" (or "keep holding").
        case countdown(numeral: String, caption: String)
        /// "Breathe in", then "and out".
        case breath(String)
        /// "18m" over "saved · they stay yours": the receipt's own numeral and caption for this ending (§5.7).
        case ended(numeral: String, caption: String)
    }

    /// The breath, in and out.
    public static var breathSeconds: TimeInterval { 2 * FocusCopy.Emergency.breathSeconds }
    /// The ended state's line and Done fade in over this (§4.6: fade-ins last at least 0.6 s).
    public static let endedFade: TimeInterval = 0.6

    /// "Emergency release".
    public let title: String
    /// "Study · Locked".
    public let subtitle: String
    public let centre: Centre
    /// The dial for VoiceOver while holding and breathing: "4 seconds, keep holding", "Breathe in". Nil once ended
    /// (the receipt's `dialLabel` reads it).
    public let spoken: String?
    /// While holding: "Ends this session now. Your 18 minutes stay yours, but it won't count as finished."; once
    /// ended: "Session ended. It won't count as finished."; nil during the breath.
    public let body: String?
    /// "Hold to release", while holding.
    public let holdTitle: String?
    /// "Keep going", while holding.
    public let keepGoingTitle: String?
    /// "Done", once ended.
    public let doneTitle: String?
    /// The ended state's numeral, line and Done, fading in: 0 during the hold and the breath.
    public let endedOpacity: Double
    /// The cool bloom's swell during the breath (a transform; 1 under Reduce Motion) and its strength.
    public let bloomScale: Double
    public let bloomOpacity: Double

    public var isEnded: Bool { if case .ended = centre { true } else { false } }
    public var isBreathing: Bool { if case .breath = centre { true } else { false } }

    /// - Parameters:
    ///   - countedSeconds: The session's counted seconds (`FocusSessionStore.countedSoFar(_:)`).
    ///   - focusedSeconds: From the countdown's start to the release: the ended numeral when the session couldn't
    ///     count.
    ///   - canCount: The session could count (`FocusPlan.canCount`).
    public init(
        presetName: String, countedSeconds: Int, focusedSeconds: Int, canCount: Bool, stage: Stage, reduceMotion: Bool
    ) {
        title = FocusCopy.Emergency.title
        subtitle = FocusCopy.Emergency.subtitle(presetName: presetName)
        switch stage {
        case .hold(let raw):
            let progress = raw.isFinite ? min(1, max(0, raw)) : 0
            let numeral = FocusCopy.Emergency.secondsLeft(FocusCopy.Emergency.holdSeconds * (1 - progress))
            let caption = progress > 0 ? FocusCopy.Emergency.keepHolding : FocusCopy.Emergency.holdCaption
            centre = .countdown(numeral: numeral, caption: caption)
            let seconds = max(0, Int((FocusCopy.Emergency.holdSeconds * (1 - progress) - 1e-9).rounded(.up)))
            spoken = "\(seconds) \(seconds == 1 ? "second" : "seconds"), \(caption)"
            body = FocusCopy.Emergency.body(countedSeconds: countedSeconds)
            holdTitle = FocusCopy.Emergency.holdToRelease
            keepGoingTitle = FocusCopy.keepGoing
            doneTitle = nil
            endedOpacity = 0
            bloomScale = 1
            bloomOpacity = 1
        case .released(let raw):
            let t = raw.isFinite ? max(0, raw) : 0
            holdTitle = nil
            keepGoingTitle = nil
            if t < Self.breathSeconds {
                let words = t < FocusCopy.Emergency.breathSeconds ? FocusCopy.Emergency.breatheIn : FocusCopy.Emergency.breatheOut
                centre = .breath(words)
                spoken = words
                body = nil
                doneTitle = nil
                endedOpacity = 0
                // One swell over the breath: 0.8 → 1.25 at the turn → 0.8, as the mockup's keyframes.
                let wave = sin(.pi * t / Self.breathSeconds)
                bloomScale = reduceMotion ? 1 : 0.8 + 0.45 * wave
                bloomOpacity = 0.5 + 0.5 * wave
            } else {
                // As the receipt reads it: the counted minutes, or the minutes focused when nothing could count.
                let shown = canCount ? max(0, countedSeconds) / 60 : max(0, focusedSeconds) / 60
                centre = .ended(numeral: FocusTimeText.length(minutes: shown),
                                caption: FocusCopy.Emergency.endedCaption(countedSeconds: countedSeconds))
                spoken = nil
                body = FocusCopy.Emergency.endedLine
                doneTitle = FocusCopy.done
                endedOpacity = min(1, (t - Self.breathSeconds) / Self.endedFade)
                bloomScale = 1
                bloomOpacity = 0.5
            }
        }
    }
}
