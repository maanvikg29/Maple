import Foundation
import MapleFocusCore

/// Last night's sleep from Apple Health (Home's morning numeral).
public struct LastNightSleep: Sendable, Hashable {
    public var asleep: Date
    public var awake: Date
    /// Time asleep, which can be shorter than awake − asleep.
    public var duration: TimeInterval

    public init(asleep: Date, awake: Date, duration: TimeInterval) {
        self.asleep = asleep
        self.awake = awake
        self.duration = duration
    }
}

/// What Home's Start would begin (F1 design §5.10): the last-used preset, and whether it can start at once.
public struct FocusStart: Sendable, Hashable {
    public var presetID: UUID
    public var verb: FocusVerb
    public var minutes: Int
    public var strictness: Strictness
    /// Ready starts at once (a hold for Locked); otherwise Start opens the Focus tab with this preset selected.
    public var readiness: StartReadiness

    public init(presetID: UUID, verb: FocusVerb, minutes: Int, strictness: Strictness, readiness: StartReadiness) {
        self.presetID = presetID
        self.verb = verb
        self.minutes = minutes
        self.strictness = strictness
        self.readiness = readiness
    }

    /// Locked with nothing to warn about: Start is a 1.5-second hold, on Home as everywhere (§5.2).
    public var needsHold: Bool { readiness == .ready(needsHold: true) }

    /// "Start study · 50m", or "Hold to start · Locked 50m" when Start is a hold. A Locked preset whose start screen
    /// has something to say reads like any other: a tap opens the Focus tab, and the hold happens there.
    public var title: String {
        let length = HomeFormat.duration(minutes: minutes)
        return needsHold ? "Hold to start · Locked \(length)" : "\(verb.startTitle) · \(length)"
    }
}

/// Today's focus, for Home (F1 design §5.10). Seconds are display credit: counted, plus a running session's
/// provisional time, so Home and the dial agree.
public struct FocusStatus: Sendable, Hashable {
    public enum Blocking: Sendable, Hashable {
        case ready
        /// Screen Time isn't allowed for Maple yet: Home offers "Turn on blocking".
        case needsPermission
        /// A build that can't block: no action.
        case notInThisBuild
    }

    public var savedTodaySeconds: Int
    public var savedYesterdaySeconds: Int
    public var savedTotalSeconds: Int
    /// Seconds left in a running session; nil when none is running.
    public var remaining: TimeInterval?
    /// What Start would begin; nil when there is no preset.
    public var start: FocusStart?
    public var blocking: Blocking

    public init(
        savedTodaySeconds: Int = 0, savedYesterdaySeconds: Int = 0, savedTotalSeconds: Int = 0, remaining: TimeInterval? = nil,
        start: FocusStart? = nil, blocking: Blocking = .ready
    ) {
        self.savedTodaySeconds = savedTodaySeconds
        self.savedYesterdaySeconds = savedYesterdaySeconds
        self.savedTotalSeconds = savedTotalSeconds
        self.remaining = remaining
        self.start = start
        self.blocking = blocking
    }
}

/// What Home's NowBlock, next-leaf row and primary capsule show right now (spec §3.3–3.4, F1 design §5.10). Pure:
/// build it with `NowState.resolve(…)` inside a `TimelineView(.everyMinute)` (every second while a session runs).
public struct NowState: Sendable, Equatable {
    /// Which row of the table the numeral and caption come from.
    public enum Content: Sendable, Equatable {
        /// Morning with Apple Health: "7h 12m" · "asleep 23:08 · up 06:20".
        case lastNightSleep
        /// Morning without Apple Health: "23:04" · "in bed · bedtime 23:00".
        case goodnight
        /// Morning with no sleep data, once something was saved yesterday: "1h 50m" · "saved yesterday · 41h in all".
        case savedYesterday
        /// Morning with no data for last night: tonight's wind-down start as a clock time, "22:15" ·
        /// "wind-down tonight · bed 23:00" (a countdown would read "14h 45m" at 7 AM).
        case windDownTonight
        /// Day: "1h 20m" · "saved today · 41h in all".
        case savedToday
        /// Day before its first session: "41h" · "saved in all · none yet today" (F1-25).
        case savedInAll
        /// Day before focus ships, without blocking, or with nothing ever saved; and evening: "1h 20m" ·
        /// "until wind-down · bed 23:00".
        case untilWindDown
        /// A session running, in every phase: "18m" · "left in this session".
        case focusRunning
        /// Wind-down: "38m" · "until bed · phone down at 23:00".
        case untilBed
        /// Night: "07:00" · "wake-up · your maple is resting".
        case wake
    }

    /// Home's one primary action. Nil when there is none: the capsule disappears and nothing replaces it.
    public enum Action: Sendable, Hashable {
        case startWindDown
        case returnToWindDown
        /// Begins the preset at once when its readiness allows; otherwise opens the Focus tab with it selected. There
        /// is no long-press menu (F1-20).
        case startFocus(FocusStart)
        case returnToSession
        /// Opens Needs Screen Time.
        case turnOnBlocking
        /// Opens the reveal for the waiting leaves.
        case openReveals(count: Int)

        /// The capsule's label.
        public var title: String {
            switch self {
            case .startWindDown: "Start wind-down"
            case .returnToWindDown: "Return to wind-down"
            case .startFocus(let start): start.title
            case .returnToSession: "Return to session"
            case .turnOnBlocking: "Turn on blocking"
            case .openReveals(let count): count == 1 ? "Open your new leaf" : "Open \(count) new leaves"
            }
        }
    }

    /// A 44pt glass capsule in place of the primary (night, once sounds ship).
    public enum SecondaryAction: Sendable, Hashable {
        case sleepSounds

        public var title: String { "Sleep sounds" }
    }

    /// The hero numeral's parts and its spoken form.
    public struct Numeral: Sendable, Equatable {
        public var parts: [NumeralPart]

        public init(parts: [NumeralPart]) {
            self.parts = parts
        }

        /// As printed: "1h 20m", "07:00", "7:00 AM".
        public var text: String {
            var text = ""
            for (index, part) in parts.enumerated() {
                if index > 0, !part.isUnit, parts[index - 1].isUnit { text += " " }
                text += part.text
            }
            return text
        }
    }

    public let phase: NowPhase
    public let content: Content
    public let numeral: Numeral
    /// One line, 7 words or fewer.
    public let caption: String
    /// The numeral and caption as one VoiceOver sentence with full units.
    public let spoken: String
    public let action: Action?
    /// Evening and wind-down use the dimmed primary capsule.
    public let actionIsDimmed: Bool
    public let secondaryAction: SecondaryAction?
    /// Leaves waiting to be opened that Home shows now (0 in wind-down and at night). Above 0, the next-leaf row
    /// becomes its waiting variant.
    public let waitingCount: Int
    /// 0.8 at night for every Home text and the next-leaf row.
    public let contentOpacity: Double
    /// Score and week blocks are hidden at night.
    public let showsBelowTheFold: Bool
    /// True while a focus session runs: refresh every second instead of every minute.
    public let refreshesEverySecond: Bool

    /// The waiting row's text: "A new leaf is waiting" or "2 new leaves are waiting".
    public var waitingLine: String? {
        switch waitingCount {
        case 0: nil
        case 1: "A new leaf is waiting"
        default: "\(waitingCount) new leaves are waiting"
        }
    }

    /// Resolves Home's state (spec §3.4).
    /// - Parameters:
    ///   - pending: Leaves that are no longer held (`CollectionStore.pending(at:)`); they surface only in morning,
    ///     day and evening.
    ///   - features: What this build ships.
    ///   - lastNight: Last night's sleep from Apple Health, when available.
    ///   - goodnightAt: Last night's Goodnight tap, used when Apple Health has nothing.
    ///   - focus: Today's focus, once the timer ships (display credit).
    ///   - windDownActive: Wind-down mode is open.
    public static func resolve(
        date: Date, schedule: SleepSchedule, calendar: Calendar = .current, locale: Locale = .current,
        pending: Int = 0, features: ShippedFeatures = .current,
        lastNight: LastNightSleep? = nil, goodnightAt: Date? = nil, focus: FocusStatus? = nil,
        windDownActive: Bool = false
    ) -> NowState {
        resolve(
            date: date, weekly: .everyNight(schedule), calendar: calendar, locale: locale, pending: pending,
            features: features, lastNight: lastNight, goodnightAt: goodnightAt, focus: focus,
            windDownActive: windDownActive
        )
    }

    /// Resolves Home's state (spec §3.4) for the member's weekly schedule. Every caption names tonight's times ("bed
    /// 00:30" on a weekend night, `WeeklySleepSchedule.tonight(at:calendar:)`); the morning's "in bed · bedtime" names
    /// last night's bedtime, the one the Goodnight tap answered.
    public static func resolve(
        date: Date, weekly: WeeklySleepSchedule, calendar: Calendar = .current, locale: Locale = .current,
        pending: Int = 0, features: ShippedFeatures = .current,
        lastNight: LastNightSleep? = nil, goodnightAt: Date? = nil, focus: FocusStatus? = nil,
        windDownActive: Bool = false
    ) -> NowState {
        let windows = PhaseWindows(weekly: weekly)
        let today = windows.day(containing: date, calendar: calendar)
        let phase = today.phase(at: date)
        // Tonight's schedule drives the evening, wind-down and night; last night's woke the member this morning.
        let schedule = weekly.schedule(forNight: today.day, calendar: calendar)
        let previous = weekly.schedule(forNight: today.day.adding(days: -1, calendar: calendar), calendar: calendar)
        let bed = HomeFormat.clock(schedule.bedtime, locale: locale)

        func untilWindDown() -> (Content, [NumeralPart], String, String) {
            let windDown = windows.nextStart(of: .windDown, after: date, calendar: calendar)
            let minutes = HomeFormat.minutesUntil(windDown, from: date)
            return (.untilWindDown, HomeFormat.durationParts(minutes: minutes), "until wind-down · bed \(bed)",
                    "\(HomeFormat.spokenDuration(minutes: minutes, locale: locale)) until wind-down. Bed at \(bed).")
        }

        func inAll(_ seconds: Int) -> [NumeralPart] {
            seconds >= 3600 ? [.value("\(seconds / 3600)"), .unit("h")] : HomeFormat.durationParts(minutes: seconds / 60)
        }
        func spokenInAll(_ seconds: Int) -> String {
            HomeFormat.spokenDuration(minutes: seconds >= 3600 ? seconds / 3600 * 60 : seconds / 60, locale: locale)
        }

        func dayContent() -> (Content, [NumeralPart], String, String) {
            guard features.focus, let focus, focus.blocking == .ready else { return untilWindDown() }
            let total = Numeral(parts: inAll(focus.savedTotalSeconds)).text
            if focus.savedTodaySeconds >= 60 {
                let minutes = focus.savedTodaySeconds / 60
                return (.savedToday, HomeFormat.durationParts(minutes: minutes), "saved today · \(total) in all",
                        "\(HomeFormat.spokenDuration(minutes: minutes, locale: locale)) saved today. "
                            + "\(spokenInAll(focus.savedTotalSeconds)) in all.")
            }
            if focus.savedTotalSeconds >= 60 {
                return (.savedInAll, inAll(focus.savedTotalSeconds), "saved in all · none yet today",
                        "\(spokenInAll(focus.savedTotalSeconds)) saved in all. None yet today.")
            }
            return untilWindDown()
        }

        let runningFocus = features.focus ? focus?.remaining.flatMap { $0 > 0 ? $0 : nil } : nil
        let content: (Content, [NumeralPart], String, String)
        if let remaining = runningFocus {
            let text = FocusTimeText.remaining(remaining)
            let parts: [NumeralPart] = text.hasPrefix("0:")
                ? [.value(text)] : HomeFormat.durationParts(minutes: Int((remaining / 60 - 1e-9).rounded(.up)))
            content = (.focusRunning, parts, "left in this session",
                       "\(FocusTimeText.spokenRemaining(remaining, locale: locale)) in this session.")
        } else {
            switch phase {
            case .morning:
                if let lastNight {
                    let minutes = Int((lastNight.duration / 60).rounded())
                    let asleep = HomeFormat.clock(HomeFormat.clockTime(of: lastNight.asleep, calendar: calendar), locale: locale)
                    let up = HomeFormat.clock(HomeFormat.clockTime(of: lastNight.awake, calendar: calendar), locale: locale)
                    content = (.lastNightSleep, HomeFormat.durationParts(minutes: minutes), "asleep \(asleep) · up \(up)",
                               "\(HomeFormat.spokenDuration(minutes: minutes, locale: locale)) asleep last night. Asleep at \(asleep), up at \(up).")
                } else if let goodnightAt {
                    let time = HomeFormat.clockTime(of: goodnightAt, calendar: calendar)
                    let text = HomeFormat.clock(time, locale: locale)
                    let lastBed = HomeFormat.clock(previous.bedtime, locale: locale)
                    content = (.goodnight, HomeFormat.clockParts(time, locale: locale), "in bed · bedtime \(lastBed)",
                               "In bed at \(text). Bedtime \(lastBed).")
                } else if features.focus, let focus, focus.savedYesterdaySeconds >= 60 {
                    let minutes = focus.savedYesterdaySeconds / 60
                    let total = Numeral(parts: inAll(focus.savedTotalSeconds)).text
                    content = (.savedYesterday, HomeFormat.durationParts(minutes: minutes), "saved yesterday · \(total) in all",
                               "\(HomeFormat.spokenDuration(minutes: minutes, locale: locale)) saved yesterday. "
                                   + "\(spokenInAll(focus.savedTotalSeconds)) in all.")
                } else {
                    let windDown = HomeFormat.clock(schedule.windDownStart, locale: locale)
                    content = (.windDownTonight, HomeFormat.clockParts(schedule.windDownStart, locale: locale),
                               "wind-down tonight · bed \(bed)", "Wind-down tonight at \(windDown). Bed at \(bed).")
                }
            case .day:
                content = dayContent()
            case .evening:
                content = untilWindDown()
            case .windDown:
                let bedtime = windows.nextStart(of: .night, after: date, calendar: calendar)
                let minutes = HomeFormat.minutesUntil(bedtime, from: date)
                content = (.untilBed, HomeFormat.durationParts(minutes: minutes), "until bed · phone down at \(bed)",
                           "\(HomeFormat.spokenDuration(minutes: minutes, locale: locale)) until bed. Phone down at \(bed).")
            case .night:
                let wake = HomeFormat.clock(schedule.wake, locale: locale)
                content = (.wake, HomeFormat.clockParts(schedule.wake, locale: locale), "wake-up · your maple is resting",
                           "Wake-up at \(wake). Your maple is resting.")
            }
        }

        let waiting = RevealSchedule.opensIn(phase) ? max(0, pending) : 0
        let action: Action?
        if runningFocus != nil {
            action = .returnToSession
        } else if waiting > 0 {
            action = .openReveals(count: waiting)
        } else {
            switch phase {
            case .morning, .night:
                action = nil
            case .day:
                if features.focus, let focus {
                    switch focus.blocking {
                    case .ready: action = focus.start.map { .startFocus($0) }
                    case .needsPermission: action = .turnOnBlocking
                    case .notInThisBuild: action = nil
                    }
                } else {
                    action = nil
                }
            case .evening, .windDown:
                action = windDownActive ? .returnToWindDown : .startWindDown
            }
        }

        return NowState(
            phase: phase, content: content.0, numeral: Numeral(parts: content.1), caption: content.2, spoken: content.3,
            action: action,
            actionIsDimmed: phase == .evening || phase == .windDown,
            secondaryAction: phase == .night && features.sleepSounds ? .sleepSounds : nil,
            waitingCount: waiting, contentOpacity: phase == .night ? 0.8 : 1, showsBelowTheFold: phase != .night,
            refreshesEverySecond: runningFocus != nil
        )
    }

    private init(
        phase: NowPhase, content: Content, numeral: Numeral, caption: String, spoken: String,
        action: Action?, actionIsDimmed: Bool, secondaryAction: SecondaryAction?, waitingCount: Int, contentOpacity: Double,
        showsBelowTheFold: Bool, refreshesEverySecond: Bool
    ) {
        self.phase = phase
        self.content = content
        self.numeral = numeral
        self.caption = caption
        self.spoken = spoken
        self.action = action
        self.actionIsDimmed = actionIsDimmed
        self.secondaryAction = secondaryAction
        self.waitingCount = waitingCount
        self.contentOpacity = contentOpacity
        self.showsBelowTheFold = showsBelowTheFold
        self.refreshesEverySecond = refreshesEverySecond
    }
}
