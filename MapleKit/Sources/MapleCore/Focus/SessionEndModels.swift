import Foundation
import MapleFocusCore

/// End early, for Gentle and Steady (F1 design §5.6): the sheet over the session that asks. Its way out (Gentle's "End
/// session", Steady's 3-second hold) leads to the breath (`EndBreathModel`), never straight to the end. Copy and
/// timings are `FocusCopy.EndEarly`'s.
public struct EndEarlyModel: Sendable, Equatable {
    public let path: SessionEndPath
    /// "End this session?"
    public let title: String
    /// "18 minutes saved so far. They stay yours either way.", or "This session isn't counting toward leaves."
    public let body: String
    /// The primary, "Keep going".
    public let keepGoingTitle: String
    /// Steady: "Hold to end".
    public let holdTitle: String?
    /// Gentle: "End session".
    public let endTitle: String?
    /// Steady, while the preset's break is unused: "Take a 5-minute break instead".
    public let breakInsteadTitle: String?

    /// - Parameters:
    ///   - path: `.gentle` or `.steady` (Locked's way out is `EmergencyReleaseModel`).
    ///   - countedSeconds: This session's counted seconds so far (`FocusSessionStore.countedSoFar(_:)`).
    ///   - breakAvailable: The preset has a break, it is unused, time is left, and apps are locked
    ///     (`RunningSessionModel.breakAvailable(_:at:)`).
    public init(path: SessionEndPath, countedSeconds: Int, breakAvailable: Bool) {
        self.path = path
        title = FocusCopy.EndEarly.title
        body = FocusCopy.EndEarly.savedLine(countedSeconds: countedSeconds)
        keepGoingTitle = FocusCopy.keepGoing
        holdTitle = path == .steady ? FocusCopy.EndEarly.holdToEnd : nil
        endTitle = path == .gentle ? FocusCopy.EndEarly.gentleEnd : nil
        breakInsteadTitle = path == .steady && breakAvailable ? FocusCopy.EndEarly.takeBreakInstead : nil
    }
}

/// After End early's sheet (F1-32): the breath in the session's place, then the question again. Gentle takes one slow
/// breath (4 seconds in, 4 out) and Steady two, while a disc and the cool bloom swell and settle (a transform and an
/// opacity). Then "Still want to end?", with "Keep going" and "End session": the session ends only on that last tap.
/// "Keep going" is there throughout. Copy and timings are `FocusCopy.EndEarly`'s.
public struct EndBreathModel: Sendable, Equatable {
    /// What the dial's centre shows.
    public enum Centre: Sendable, Equatable {
        /// "Breathe in", then "and out".
        case breath(String)
        /// "18m" over "saved so far" ("19m" over "focused" when the session can't count).
        case asking(numeral: String, caption: String)
    }

    /// The second question fades in over this (§4.6: fade-ins last at least 0.6 s).
    public static let askFade: TimeInterval = 0.6

    /// How long the breathing lasts: 8 seconds for Gentle, 16 for Steady.
    public static func breathSeconds(for path: SessionEndPath) -> TimeInterval {
        Double(FocusCopy.EndEarly.breaths(for: path)) * 2 * FocusCopy.EndEarly.breathHalfSeconds
    }

    public let centre: Centre
    /// The dial for VoiceOver: "Breathe in", then "18 minutes saved so far".
    public let spoken: String
    /// Under the dial while breathing: "One slow breath before you decide."
    public let line: String?
    /// Once it asks again: "Still want to end?"
    public let title: String?
    /// Once it asks again: "18 minutes saved so far. They stay yours either way."
    public let body: String?
    /// The dial's numeral and caption as one line, repeated under it at accessibility sizes (§5.17); nil while breathing.
    public let timeLine: String?
    /// "Keep going", from the first moment.
    public let keepGoingTitle: String
    /// "End session": it holds its place through the breath and fades in with `askOpacity`.
    public let endTitle: String
    /// 0 through the breath, then 0…1 as the question fades in.
    public let askOpacity: Double
    /// The breathing disc, as a share of its full size (1 under Reduce Motion), and its strength.
    public let discScale: Double
    public let discOpacity: Double
    /// The cool bloom's swell (1 under Reduce Motion) and its strength.
    public let bloomScale: Double
    public let bloomOpacity: Double

    public var isAsking: Bool { if case .asking = centre { true } else { false } }
    public var isBreathing: Bool { !isAsking }

    /// - Parameters:
    ///   - path: `.gentle` or `.steady`.
    ///   - countedSeconds: The session's counted seconds so far (`FocusSessionStore.countedSoFar(_:)`).
    ///   - focusedSeconds: From the countdown's start to now: the numeral when the session can't count.
    ///   - canCount: The session could count (`FocusPlan.canCount`).
    ///   - seconds: Since the breath began, on trusted time.
    public init(
        path: SessionEndPath, countedSeconds: Int, focusedSeconds: Int, canCount: Bool, seconds: Double, reduceMotion: Bool,
        locale: Locale = .current
    ) {
        let t = seconds.isNaN ? 0 : max(0, seconds)
        let total = Self.breathSeconds(for: path)
        keepGoingTitle = FocusCopy.keepGoing
        endTitle = FocusCopy.EndEarly.gentleEnd
        if t < total {
            let half = FocusCopy.EndEarly.breathHalfSeconds
            let within = t.truncatingRemainder(dividingBy: 2 * half)
            let words = within < half ? FocusCopy.EndEarly.breatheIn : FocusCopy.EndEarly.breatheOut
            centre = .breath(words)
            spoken = words
            line = FocusCopy.EndEarly.breathLine(breaths: FocusCopy.EndEarly.breaths(for: path))
            title = nil
            body = nil
            timeLine = nil
            askOpacity = 0
            // One swell a breath: up through the 4 seconds in, back through the 4 out.
            let wave = 0.5 - 0.5 * cos(.pi * within / half)
            discScale = reduceMotion ? 1 : 0.45 + 0.55 * wave
            discOpacity = 0.35 + 0.65 * wave
            bloomScale = reduceMotion ? 1 : 0.8 + 0.45 * wave
            bloomOpacity = 0.5 + 0.5 * wave
        } else {
            let shown = canCount ? max(0, countedSeconds) / 60 : max(0, focusedSeconds) / 60
            let numeral = FocusTimeText.length(minutes: shown)
            let caption = canCount ? FocusCopy.EndEarly.savedCaption : FocusCopy.EndEarly.focusedCaption
            centre = .asking(numeral: numeral, caption: caption)
            spoken = "\(FocusTimeText.spokenLength(minutes: shown, locale: locale)) \(caption)"
            line = nil
            title = FocusCopy.EndEarly.askAgain
            body = FocusCopy.EndEarly.savedLine(countedSeconds: countedSeconds)
            timeLine = "\(numeral) \(caption)"
            let fade = min(1, (t - total) / Self.askFade)
            askOpacity = fade
            // The disc settles away as the question comes in.
            discScale = reduceMotion ? 1 : 0.45
            discOpacity = 0.35 * (1 - fade)
            bloomScale = reduceMotion ? 1 : 0.8
            bloomOpacity = 0.5
        }
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
    /// The dial for VoiceOver: "4 seconds, keep holding", "Breathe in", and once ended its numeral and caption in words,
    /// "18 minutes saved, they stay yours." (§4.9).
    public let spoken: String?
    /// The dial's time repeated under it at accessibility sizes, where its numeral stops growing (§5.17): "10s hold to
    /// release", then "18m saved · they stay yours"; nil during the breath, which shows no time.
    public let timeLine: String?
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
        presetName: String, countedSeconds: Int, focusedSeconds: Int, canCount: Bool, stage: Stage, reduceMotion: Bool,
        locale: Locale = .current
    ) {
        title = FocusCopy.Emergency.title
        subtitle = FocusCopy.Emergency.subtitle(presetName: presetName)
        switch stage {
        case .hold(let raw):
            let progress = raw.isFinite ? min(1, max(0, raw)) : 0
            let numeral = FocusCopy.Emergency.secondsLeft(FocusCopy.Emergency.holdSeconds * (1 - progress))
            let caption = progress > 0 ? FocusCopy.Emergency.keepHolding : FocusCopy.Emergency.holdCaption
            centre = .countdown(numeral: numeral, caption: caption)
            timeLine = "\(numeral) \(caption)"
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
                timeLine = nil
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
                let numeral = FocusTimeText.length(minutes: shown)
                let caption = FocusCopy.Emergency.endedCaption(countedSeconds: countedSeconds)
                centre = .ended(numeral: numeral, caption: caption)
                spoken = FocusCopy.Emergency.endedSpoken(minutes: shown, countedSeconds: countedSeconds, locale: locale)
                timeLine = "\(numeral) \(caption)"
                body = FocusCopy.Emergency.endedLine
                doneTitle = FocusCopy.done
                endedOpacity = min(1, (t - Self.breathSeconds) / Self.endedFade)
                bloomScale = 1
                bloomOpacity = 0.5
            }
        }
    }
}
