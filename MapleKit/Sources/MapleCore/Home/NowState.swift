import Foundation

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

/// Today's focus, once the focus timer ships.
public struct FocusStatus: Sendable, Hashable {
    public var todayMinutes: Int
    public var weekMinutes: Int
    /// Seconds left in a running session; nil when none is running.
    public var remaining: TimeInterval?

    public init(todayMinutes: Int, weekMinutes: Int, remaining: TimeInterval? = nil) {
        self.todayMinutes = todayMinutes
        self.weekMinutes = weekMinutes
        self.remaining = remaining
    }
}

/// What Home's NowBlock, next-leaf row and primary capsule show right now (spec §3.3–3.4). Pure: build it with
/// `NowState.resolve(…)` inside a `TimelineView(.everyMinute)` (every second while focus runs).
public struct NowState: Sendable, Equatable {
    /// Which row of the §3.4 table the numeral and caption come from.
    public enum Content: Sendable, Equatable {
        /// Morning with Apple Health: "7h 12m" · "asleep 23:08 · up 06:20".
        case lastNightSleep
        /// Morning without Apple Health: "23:04" · "in bed · bedtime 23:00".
        case goodnight
        /// Day once focus ships: "1h 25m" · "focused today · 4h 10m this week".
        case focusToday
        /// Morning with no data for last night: tonight's wind-down start as a clock time, "22:15" ·
        /// "wind-down tonight · bed 23:00" (a countdown would read "14h 45m" at 7 AM).
        case windDownTonight
        /// Day before focus ships, and evening: "1h 20m" · "until wind-down · bed 23:00".
        case untilWindDown
        /// "18:42" · "left in this focus".
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
        /// Starts a session at once; a long-press offers 15, 25, 45 and 60 minutes.
        case startFocus(minutes: Int, firstTime: Bool)
        case returnToFocus
        /// Opens the reveal for the waiting leaves.
        case openReveals(count: Int)

        /// The capsule's label.
        public var title: String {
            switch self {
            case .startWindDown: "Start wind-down"
            case .returnToWindDown: "Return to wind-down"
            case .startFocus(let minutes, let firstTime): firstTime ? "Start a \(minutes)-minute focus" : "Start focus · \(minutes)m"
            case .returnToFocus: "Return to focus"
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

    public static let defaultFocusMinutes = 25

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
    ///   - counters: The member's counters (a first focus reads "Start a 25-minute focus").
    ///   - features: What this build ships.
    ///   - lastNight: Last night's sleep from Apple Health, when available.
    ///   - goodnightAt: Last night's Goodnight tap, used when Apple Health has nothing.
    ///   - focus: Today's focus, once the timer ships.
    ///   - windDownActive: Wind-down mode is open.
    public static func resolve(
        date: Date, schedule: SleepSchedule, calendar: Calendar = .current, locale: Locale = .current,
        pending: Int = 0, counters: [RewardCategoryID: Double] = [:], features: ShippedFeatures = .current,
        lastNight: LastNightSleep? = nil, goodnightAt: Date? = nil, focus: FocusStatus? = nil,
        windDownActive: Bool = false
    ) -> NowState {
        resolve(
            date: date, weekly: .everyNight(schedule), calendar: calendar, locale: locale, pending: pending,
            counters: counters, features: features, lastNight: lastNight, goodnightAt: goodnightAt, focus: focus,
            windDownActive: windDownActive
        )
    }

    /// Resolves Home's state (spec §3.4) for the member's weekly schedule. Every caption names tonight's times ("bed
    /// 00:30" on a weekend night, `WeeklySleepSchedule.tonight(at:calendar:)`); the morning's "in bed · bedtime" names
    /// last night's bedtime, the one the Goodnight tap answered.
    public static func resolve(
        date: Date, weekly: WeeklySleepSchedule, calendar: Calendar = .current, locale: Locale = .current,
        pending: Int = 0, counters: [RewardCategoryID: Double] = [:], features: ShippedFeatures = .current,
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

        func dayContent() -> (Content, [NumeralPart], String, String) {
            guard features.focus else { return untilWindDown() }
            let today = focus?.todayMinutes ?? 0
            let week = HomeFormat.duration(minutes: focus?.weekMinutes ?? 0)
            return (.focusToday, HomeFormat.durationParts(minutes: today), "focused today · \(week) this week",
                    "\(HomeFormat.spokenDuration(minutes: today, locale: locale)) focused today. "
                        + "\(HomeFormat.spokenDuration(minutes: focus?.weekMinutes ?? 0, locale: locale)) this week.")
        }

        let runningFocus = features.focus && phase != .night ? focus?.remaining.flatMap { $0 > 0 ? $0 : nil } : nil
        let content: (Content, [NumeralPart], String, String)
        if let remaining = runningFocus {
            let seconds = Int(remaining.rounded(.up))
            let text = "\(seconds / 60):\(seconds % 60 < 10 ? "0" : "")\(seconds % 60)"
            content = (.focusRunning, [.value(text)], "left in this focus",
                       "\(HomeFormat.spokenDuration(minutes: Int((remaining / 60).rounded(.up)), locale: locale)) left in this focus.")
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
            action = .returnToFocus
        } else if waiting > 0 {
            action = .openReveals(count: waiting)
        } else {
            switch phase {
            case .morning:
                action = nil
            case .day:
                let firstTime = (counters[.sessionsFinished] ?? 0) == 0 && (counters[.hoursSaved] ?? 0) == 0
                action = features.focus ? .startFocus(minutes: defaultFocusMinutes, firstTime: firstTime) : nil
            case .evening, .windDown:
                action = windDownActive ? .returnToWindDown : .startWindDown
            case .night:
                action = nil
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
