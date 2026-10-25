import Foundation
import MapleFocusCore

/// Which Needs Screen Time card shows (F1 design §5.3).
public enum NeedsScreenTimeState: String, Sendable, Hashable, CaseIterable {
    case notAsked, declined, restricted, noPasscode, freeBuild

    /// The card a probe calls for; nil when blocking is allowed. A build that can't block always shows the free
    /// build's card, whatever the probe says (F1-17).
    public init?(probe: BlockingProbe, capability: BlockingCapability) {
        guard capability.canBlock else {
            self = .freeBuild
            return
        }
        switch probe {
        case .allowed: return nil
        case .notDetermined: self = .notAsked
        case .declined: self = .declined
        case .restricted: self = .restricted
        case .noPasscode: self = .noPasscode
        case .unavailable: self = .freeBuild
        }
    }
}

/// Every fixed Focus string that no screen model owns (F1 design §5, ruling P3), so views hold no copy and every line
/// is tested. Sentence case, no "!", and never "fail", "quit" or "streak lost".
public enum FocusCopy {
    // MARK: Start (§5.1, §5.2, §5.4, §5.16)

    /// The intention line's placeholder (§5.1, §5.16).
    public static let intentionPrompt = "What's this for?"
    /// The "+" chip, read aloud and shown at accessibility sizes (§5.13, §5.17).
    public static let newPreset = "New preset"
    /// The dial's caption until the member has turned it once (§4.5).
    public static let turnHint = "turn to set the length"
    public static let chooseApps = "Choose apps"
    public static let returnToSession = "Return to session"
    /// What a plain tap on Locked's hold shows, for `holdHintSeconds` (§5.2, F1-21).
    public static let holdHint = "Hold to start. Locked ends early only by emergency release."
    public static let holdHintSeconds = 4.0
    /// Locked's hold to start (§5.2).
    public static let holdToStartSeconds = 1.5
    /// The block couldn't be applied or read back (§5.1).
    public static let couldntLock = "Couldn't lock your apps · Start as a plain timer?"
    public static let startPlainTimer = "Start as a plain timer"
    /// Under the running dial, in the first session only (§5.4, P4).
    public static let firstSessionLine = "You can lock your phone. Maple keeps time."
    public static let keepGoing = "Keep going"
    public static let done = "Done"

    /// Locked's capsule: "Hold to start · 50m".
    public static func holdToStart(minutes: Int) -> String {
        "Hold to start · \(FocusTimeText.length(minutes: minutes))"
    }

    /// A hold-to-start button's VoiceOver name (§4.9): "Hold to start, Locked 50 minutes".
    public static func holdToStartName(minutes: Int, locale: Locale) -> String {
        "Hold to start, Locked \(FocusTimeText.spokenLength(minutes: minutes, locale: locale))"
    }

    /// The start dial's VoiceOver label (§4.9): "Session length, 50 minutes".
    public static func sessionLengthLabel(minutes: Int, locale: Locale) -> String {
        "Session length, \(FocusTimeText.spokenLength(minutes: minutes, locale: locale))"
    }

    /// A session's header (§5.4, §5.8): "Study · Chemistry ch. 4", or the preset alone without an intention.
    public static func sessionTitle(presetName: String, intention: String?) -> String {
        guard let intention = intention.flatMap({ RecentIntentions.normalized($0) }) else { return presetName }
        return "\(presetName) · \(intention)"
    }

    // MARK: Needs Screen Time (§5.3, F1-17)

    public struct ScreenTimeCard: Sendable, Hashable {
        public let title: String
        public let body: String?
        /// The primary capsule; nil when there is nothing Maple can ask for.
        public let primary: String?
    }

    public static let turnOnScreenTime = "Turn on Screen Time"
    /// The link under every card (§5.3).
    public static let plainTimerLink = "Use a plain timer · it won't count"

    public static func card(_ state: NeedsScreenTimeState) -> ScreenTimeCard {
        switch state {
        case .notAsked:
            ScreenTimeCard(
                title: "Lock apps with Screen Time",
                body: "Maple keeps your chosen apps resting while you focus. It never sees which apps you use.",
                primary: turnOnScreenTime
            )
        case .declined:
            ScreenTimeCard(title: "Screen Time is off for Maple", body: "Turn it on to count your focus time.", primary: turnOnScreenTime)
        case .restricted:
            ScreenTimeCard(title: "Screen Time is managed on this iPhone", body: "A parent can allow Maple in Screen Time settings.",
                           primary: nil)
        case .noPasscode:
            ScreenTimeCard(title: "Set a passcode to use Screen Time", body: nil, primary: nil)
        case .freeBuild:
            ScreenTimeCard(title: "This version of Maple can't lock apps", body: "The timer still runs, but it won't count.", primary: nil)
        }
    }

    // MARK: Strictness (§5.13)

    public static func strictnessName(_ strictness: Strictness) -> String {
        switch strictness {
        case .gentle: "Gentle"
        case .steady: "Steady"
        case .locked: "Locked"
        }
    }

    /// Each level's one honest line in the strictness chooser (F1-21).
    public static func strictnessLine(_ strictness: Strictness) -> String {
        switch strictness {
        case .gentle: "Unlock an app when you need it. Unlocked time doesn't count."
        case .steady: "Two unlocks a session. Ending early takes a hold and 15 seconds."
        case .locked:
            "No unlocks. Ending early takes a 10-second hold and a breath. Calls and Always Allowed apps keep working, and you can turn off Screen Time for Maple in Settings."
        }
    }

    /// A looser level waiting for the next day (`FocusPreset.pendingStrictness`): "Steady starts tomorrow".
    public static func pendingLine(_ strictness: Strictness) -> String {
        "\(strictnessName(strictness)) starts tomorrow"
    }

    // MARK: Break (§5.5, §4.9)

    public enum BreakTime {
        public static let header = "Break · apps stay locked"
        /// Under the break dial's numeral.
        public static let caption = "left of your break"
        public static let backToStudying = "Back to studying"
        /// Something to do away from the phone, one at a time.
        public static let suggestions = ["Stand up and stretch.", "Look out of a window.", "Get a glass of water."]
        /// Each suggestion shows this long, so a 5-minute break shows all three.
        public static let suggestionSeconds: TimeInterval = 100

        public static func suggestion(secondsIntoBreak: TimeInterval) -> String {
            suggestions[Int(max(0, secondsIntoBreak) / suggestionSeconds) % suggestions.count]
        }

        /// "The break counts. Back to studying at 14:28."
        public static func line(backAt: Date, locale: Locale, calendar: Calendar) -> String {
            "The break counts. Back to studying at \(FocusCopy.clock(backAt, locale: locale, calendar: calendar))."
        }

        /// The break dial's VoiceOver label (§4.9): "4 minutes of break left. Back to studying at 14:28." Minutes round
        /// up, as the dial's numeral does; the last minute reads in seconds.
        public static func dialLabel(secondsLeft: TimeInterval, backAt: Date, locale: Locale, calendar: Calendar) -> String {
            let left = max(0, secondsLeft)
            let wholeSeconds = max(0, Int((left - 1e-9).rounded(.up)))
            let amount = wholeSeconds >= 60
                ? HomeFormat.spokenDuration(minutes: Int((left / 60 - 1e-9).rounded(.up)), locale: locale)
                : "\(wholeSeconds) \(wholeSeconds == 1 ? "second" : "seconds")"
            return "\(amount) of break left. Back to studying at \(FocusCopy.clock(backAt, locale: locale, calendar: calendar))."
        }
    }

    // MARK: End early (§5.6)

    public enum EndEarly {
        public static let title = "End this session?"
        public static let holdToEnd = "Hold to end"
        /// Steady's hold, then its quiet countdown that "Keep going" still cancels.
        public static let holdSeconds = 3.0
        public static let countdownSeconds = 15
        /// Offered while the preset's break is unused; it is cut short at the planned end.
        public static let takeBreakInstead = "Take a 5-minute break instead"
        /// Gentle's way out: a 5-second breathing ring, then the session ends.
        public static let gentleEnd = "End session"
        public static let gentleBreathSeconds = 5.0

        /// From counted seconds only: "18 minutes saved so far. They stay yours either way."
        public static func savedLine(countedSeconds: Int) -> String {
            let minutes = countedSeconds / 60
            if countedSeconds <= 0 { return "This session isn't counting toward leaves." }
            if minutes == 0 { return "Under a minute saved so far. It stays yours either way." }
            if minutes == 1 { return "1 minute saved so far. It stays yours either way." }
            return "\(minutes) minutes saved so far. They stay yours either way."
        }

        /// "Ending in 15s".
        public static func endingIn(seconds: Int) -> String {
            "Ending in \(max(0, seconds))s"
        }
    }

    // MARK: Emergency release (§5.7)

    public enum Emergency {
        public static let title = "Emergency release"
        /// The button, and its VoiceOver name and named action (F1-22).
        public static let holdToRelease = "Hold to release"
        public static let holdSeconds = 10.0
        /// The dial's caption; it reads `keepHolding` while the hold is pressed.
        public static let holdCaption = "hold to release"
        public static let keepHolding = "keep holding"
        public static let breatheIn = "Breathe in"
        public static let breatheOut = "and out"
        /// Each half of the breath.
        public static let breathSeconds = 4.0
        public static let endedLine = "Session ended. It won't count as finished."

        /// Under the title: "Study · Locked".
        public static func subtitle(presetName: String) -> String {
            "\(presetName) · Locked"
        }

        /// The hold's countdown in the dial: "10s", whole seconds rounded up.
        public static func secondsLeft(_ seconds: Double) -> String {
            "\(max(0, Int((seconds - 1e-9).rounded(.up))))s"
        }

        /// "Ends this session now. Your 18 minutes stay yours, but it won't count as finished." With nothing counted
        /// the middle of it is left out.
        public static func body(countedSeconds: Int) -> String {
            let minutes = countedSeconds / 60
            if countedSeconds <= 0 { return "Ends this session now. It won't count as finished." }
            if minutes == 0 { return "Ends this session now. Your time so far stays yours, but it won't count as finished." }
            if minutes == 1 { return "Ends this session now. Your 1 minute stays yours, but it won't count as finished." }
            return "Ends this session now. Your \(minutes) minutes stay yours, but it won't count as finished."
        }

        /// The ended state's caption under its numeral ("18m").
        public static func endedCaption(countedSeconds: Int) -> String {
            countedSeconds > 0 ? "saved · they stay yours" : "not counted toward leaves"
        }
    }

    // MARK: Release all apps (§5.12)

    public enum ReleaseAll {
        /// The Settings row, and the confirmation's destructive button.
        public static let title = "Release all apps"
        public static let question = "Release all apps?"
        public static let body = "Every app Maple is resting opens again now."
        public static let cancel = "Cancel"
    }

    /// "14:28" or "2:28 PM".
    static func clock(_ date: Date, locale: Locale, calendar: Calendar) -> String {
        HomeFormat.clock(HomeFormat.clockTime(of: date, calendar: calendar), locale: locale)
    }
}
