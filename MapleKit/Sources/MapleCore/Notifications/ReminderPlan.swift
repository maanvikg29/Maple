import Foundation

/// Maple's local notifications: wind-down, a session's end, and the opt-in study reminder. There is no morning
/// notification (rewards.md; focus spec §8), so a waiting leaf is only ever shown in the app.
public enum ReminderKind: String, Sendable, Hashable, CaseIterable {
    /// "Time to wind down" at the start of wind-down. It never mentions leaves or progress (rewards.md).
    case windDown
    /// "Session done · Study, 50 minutes" at a running session's planned end (F1 design §6, F1-16).
    case sessionEnd
    /// "Ready to study?", once a day at the member's time, in the Day phase; off by default (F1-4).
    case studyReminder

    /// Every identifier Maple schedules starts with this, so rescheduling touches nothing else.
    public static let identifierPrefix = "maple.reminder."

    /// The prefix of this kind's identifiers ("maple.reminder.windDown.").
    public var identifierPrefix: String { Self.identifierPrefix + rawValue + "." }

    /// The notification thread, so iOS stacks each kind on its own.
    public var threadID: String { "maple." + rawValue }

    /// The kind a Maple identifier belongs to; nil for anything else.
    public init?(identifier: String) {
        guard let kind = Self.allCases.first(where: { identifier.hasPrefix($0.identifierPrefix) }) else { return nil }
        self = kind
    }
}

/// How a notification arrives (`UNNotificationInterruptionLevel`, without importing UserNotifications).
public enum ReminderInterruption: String, Sendable, Hashable {
    /// Silent: no sound, the screen stays dark; it waits on the Lock Screen and in Notification Center.
    case passive
    /// The usual alert, which Focus modes (Sleep included) may hold back.
    case active
}

/// One local notification to schedule.
public struct ReminderRequest: Sendable, Hashable, Identifiable {
    /// Deterministic: the kind and the night it belongs to ("maple.reminder.windDown.2026-10-12", named by the
    /// night's evening), so rescheduling replaces a request rather than adding a second one.
    public var id: String
    public var kind: ReminderKind
    public var fireDate: Date
    /// The fire date as a local wall-clock time (year to second, no time zone), so the reminder keeps its local
    /// time if the member's time zone changes before Maple reschedules.
    public var fireComponents: DateComponents
    public var title: String
    public var body: String
    public var threadID: String
    public var interruption: ReminderInterruption
    /// The default notification sound; false for a silent one.
    public var playsSound: Bool
    /// Fires after the real time left rather than at a wall-clock time, so a clock or time-zone change can't move it
    /// (a session's end).
    public var isAbsolute: Bool

    /// - Parameter calendar: The member's calendar, which turns `fireDate` into its local wall-clock time.
    public init(
        id: String, kind: ReminderKind, fireDate: Date, calendar: Calendar, title: String, body: String,
        threadID: String, interruption: ReminderInterruption, playsSound: Bool, isAbsolute: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.fireDate = fireDate
        fireComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
        self.title = title
        self.body = body
        self.threadID = threadID
        self.interruption = interruption
        self.playsSound = playsSound
        self.isAbsolute = isAbsolute
    }
}

/// Which reminders the member wants (Settings). Wind-down and a session's end are on until turned off; the study
/// reminder is off until the member picks its time. Nothing is sent until iOS allows Maple's notifications.
public struct ReminderSettings: Sendable, Hashable {
    public var windDown: Bool
    public var sessionEnd: Bool
    /// The study reminder's time; nil when it is off.
    public var studyReminder: ClockTime?

    public init(windDown: Bool = true, sessionEnd: Bool = true, studyReminder: ClockTime? = nil) {
        self.windDown = windDown
        self.sessionEnd = sessionEnd
        self.studyReminder = studyReminder
    }

    public static let allOn = ReminderSettings()
    public static let allOff = ReminderSettings(windDown: false, sessionEnd: false, studyReminder: nil)

    public func allows(_ kind: ReminderKind) -> Bool {
        switch kind {
        case .windDown: windDown
        case .sessionEnd: sessionEnd
        case .studyReminder: studyReminder != nil
        }
    }
}

/// The reminder's words (calm, sentence case, one short line each, no emoji or exclamation marks, never guilt).
public enum ReminderCopy {
    public static let windDownTitle = "Time to wind down"

    /// "Bed at 23:00." or "Bed at 11:00 PM.", in the member's clock style.
    public static func windDownBody(bedtime: Date, calendar: Calendar, locale: Locale) -> String {
        "Bed at \(HomeFormat.clock(HomeFormat.clockTime(of: bedtime, calendar: calendar), locale: locale))."
    }

    public static let sessionDoneTitle = "Session done"
    public static let timerDoneTitle = "Timer done"
    public static let studyTitle = "Ready to study?"
    public static let studyBody = "Your apps can rest for a while."

    /// "Study, 50 minutes", or "50 minutes" for a plain timer. Fixed when the session starts, so it never says "saved".
    public static func sessionEndBody(presetName: String, minutes: Int, isPlainTimer: Bool) -> String {
        isPlainTimer ? "\(minutes) minutes" : "\(presetName), \(minutes) minutes"
    }
}

/// The local notifications Maple should have scheduled right now. Pure: the app builds the input from its stores,
/// and `NotificationScheduler` replaces Maple's pending requests with `requests`.
///
/// Rules:
/// - **Wind-down** at each night's wind-down start: "Time to wind down" · "Bed at 23:00.". Not once that moment
///   has passed, not on a night with no wind-down (it starts at bedtime), and not on a night whose wind-down mode
///   the member has already opened (from 2 hours before wind-down until bedtime, the Evening and Wind-down
///   phases in which it can be opened).
/// - At most one per night, named by the night's evening; a second night with the same name (an overlap in the
///   input) adds nothing.
/// - Nothing ever fires between a bedtime and the next morning start, and nothing is sent in the morning.
/// - Only within the next 7 days (`horizonDays`), well under iOS's 64 pending requests.
/// - **Session end** at a running session's planned end, with an absolute trigger; exempt from the night rule.
/// - **Study reminder** (opt-in) once a day at the member's time, only in the Day phase, skipped on a day a session started.
/// - Turned off, it schedules nothing.
public struct ReminderPlan: Sendable, Equatable {
    /// Days ahead the plan covers.
    public static let horizonDays = 7
    /// How long before wind-down starts wind-down mode can be opened (the Evening phase, spec §3.3).
    public static let windDownLead: TimeInterval = 2 * 3600

    /// The session running now, for its end reminder.
    public struct RunningSession: Sendable, Hashable {
        public var id: UUID
        public var plannedEnd: Date
        public var presetName: String
        public var plannedMinutes: Int
        public var isPlainTimer: Bool

        public init(id: UUID, plannedEnd: Date, presetName: String, plannedMinutes: Int, isPlainTimer: Bool) {
            self.id = id
            self.plannedEnd = plannedEnd
            self.presetName = presetName
            self.plannedMinutes = plannedMinutes
            self.isPlainTimer = isPlainTimer
        }
    }

    public struct Input: Sendable {
        /// Nights in order. Nights whose moments have passed are fine; they schedule nothing.
        public var nights: [UpcomingNight]
        public var settings: ReminderSettings
        /// When wind-down mode was last opened (the bedside log's start); nil if never.
        public var windDownOpenedAt: Date?
        public var now: Date
        /// The member's calendar, for naming nights and reading the bedtime's clock time.
        public var calendar: Calendar
        public var locale: Locale
        /// The weekly schedule, for the study reminder's Day phase.
        public var schedule: WeeklySleepSchedule
        public var runningSession: RunningSession?
        /// When the latest session started: the study reminder skips that day.
        public var lastSessionStart: Date?

        public init(
            nights: [UpcomingNight], settings: ReminderSettings, windDownOpenedAt: Date? = nil, now: Date,
            calendar: Calendar, locale: Locale, schedule: WeeklySleepSchedule = .standard,
            runningSession: RunningSession? = nil, lastSessionStart: Date? = nil
        ) {
            self.nights = nights
            self.settings = settings
            self.windDownOpenedAt = windDownOpenedAt
            self.now = now
            self.calendar = calendar
            self.locale = locale
            self.schedule = schedule
            self.runningSession = runningSession
            self.lastSessionStart = lastSessionStart
        }
    }

    /// What to schedule, in fire order.
    public let requests: [ReminderRequest]
    /// Kinds whose delivered notifications no longer hold and should leave Notification Center: wind-down outside
    /// a wind-down the member hasn't started.
    public let staleDelivered: Set<ReminderKind>

    public init(requests: [ReminderRequest], staleDelivered: Set<ReminderKind> = []) {
        self.requests = requests
        self.staleDelivered = staleDelivered
    }

    /// Nothing scheduled, nothing cleared.
    public static let empty = ReminderPlan(requests: [])

    public init(_ input: Input) {
        let nights = input.nights.sorted { $0.morningStart < $1.morningStart }
        let horizon = input.now.addingTimeInterval(TimeInterval(Self.horizonDays) * 24 * 3600)
        var requests: [ReminderRequest] = []
        var named: Set<String> = []

        for night in nights {
            let name = night.name(in: input.calendar).description
            // A night that overlaps one already planned (the same evening) adds nothing.
            guard named.insert(name).inserted,
                  let request = Self.windDown(for: night, name: name, input: input),
                  request.fireDate > input.now, request.fireDate <= horizon,
                  !Self.isDuringSleep(request.fireDate, nights: nights)
            else { continue }
            requests.append(request)
        }
        if let end = Self.sessionEnd(input: input), end.fireDate > input.now, end.fireDate <= horizon {
            requests.append(end)                       // a session's end is exempt from the night rule
        }
        for study in Self.studyReminders(input: input) where study.fireDate > input.now && study.fireDate <= horizon {
            requests.append(study)
        }

        self.requests = requests.sorted { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }
        self.staleDelivered = Self.stale(input: input, nights: nights)
    }

    // MARK: Rules

    private static func windDown(for night: UpcomingNight, name: String, input: Input) -> ReminderRequest? {
        guard input.settings.windDown, night.windDownStart < night.bedtime else { return nil }
        if let opened = input.windDownOpenedAt, openedWindDown(of: night, at: opened) { return nil }
        let kind = ReminderKind.windDown
        return ReminderRequest(
            id: kind.identifierPrefix + name, kind: kind, fireDate: night.windDownStart, calendar: input.calendar,
            title: ReminderCopy.windDownTitle,
            body: ReminderCopy.windDownBody(bedtime: night.bedtime, calendar: input.calendar, locale: input.locale),
            threadID: kind.threadID, interruption: .active, playsSound: true
        )
    }

    private static func sessionEnd(input: Input) -> ReminderRequest? {
        guard input.settings.sessionEnd, let session = input.runningSession else { return nil }
        let kind = ReminderKind.sessionEnd
        return ReminderRequest(
            id: kind.identifierPrefix + session.id.uuidString.lowercased(), kind: kind, fireDate: session.plannedEnd,
            calendar: input.calendar,
            title: session.isPlainTimer ? ReminderCopy.timerDoneTitle : ReminderCopy.sessionDoneTitle,
            body: ReminderCopy.sessionEndBody(presetName: session.presetName, minutes: session.plannedMinutes,
                                              isPlainTimer: session.isPlainTimer),
            threadID: kind.threadID, interruption: .active, playsSound: true, isAbsolute: true
        )
    }

    /// One a day at the member's time while it falls in the Day phase, skipping the day the latest session started.
    private static func studyReminders(input: Input) -> [ReminderRequest] {
        guard let time = input.settings.studyReminder else { return [] }
        let calendar = input.calendar
        let today = LocalDay(input.now, calendar: calendar)
        let startedDay = input.lastSessionStart.map { LocalDay($0, calendar: calendar) }
        let kind = ReminderKind.studyReminder
        return (0...horizonDays).compactMap { offset -> ReminderRequest? in
            let day = today.adding(days: offset, calendar: calendar)
            guard day != startedDay,
                  let fire = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day.startDate(in: calendar)),
                  NowPhase.resolve(date: fire, weekly: input.schedule, calendar: calendar) == .day
            else { return nil }
            return ReminderRequest(
                id: kind.identifierPrefix + day.description, kind: kind, fireDate: fire, calendar: calendar,
                title: ReminderCopy.studyTitle, body: ReminderCopy.studyBody, threadID: kind.threadID,
                interruption: .active, playsSound: true
            )
        }
    }

    /// Wind-down mode opened in this night's Evening or Wind-down.
    private static func openedWindDown(of night: UpcomingNight, at opened: Date) -> Bool {
        opened >= night.windDownStart.addingTimeInterval(-windDownLead) && opened < night.bedtime
    }

    /// Strictly between some night's bedtime and its morning start.
    private static func isDuringSleep(_ date: Date, nights: [UpcomingNight]) -> Bool {
        nights.contains { date > $0.bedtime && date < $0.morningStart }
    }

    private static func stale(input: Input, nights: [UpcomingNight]) -> Set<ReminderKind> {
        let inWindDown = nights.contains { night in
            input.now >= night.windDownStart && input.now < night.bedtime
                && !(input.windDownOpenedAt.map { openedWindDown(of: night, at: $0) } ?? false)
        }
        return inWindDown ? [] : [.windDown]
    }
}
