import Foundation

/// The one local notification Maple sends: "Time to wind down". There is no morning notification (rewards.md; focus
/// spec §8), so a waiting leaf is only ever shown in the app.
public enum ReminderKind: String, Sendable, Hashable, CaseIterable {
    /// "Time to wind down" at the start of wind-down. It never mentions leaves or progress (rewards.md).
    case windDown

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

    /// - Parameter calendar: The member's calendar, which turns `fireDate` into its local wall-clock time.
    public init(
        id: String, kind: ReminderKind, fireDate: Date, calendar: Calendar, title: String, body: String,
        threadID: String, interruption: ReminderInterruption, playsSound: Bool
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
    }
}

/// Which reminders the member wants (Profile › Settings). On until they turn it off; nothing is sent until iOS
/// allows Maple's notifications.
public struct ReminderSettings: Sendable, Hashable {
    public var windDown: Bool

    public init(windDown: Bool = true) {
        self.windDown = windDown
    }

    public static let allOn = ReminderSettings()
    public static let allOff = ReminderSettings(windDown: false)

    public func allows(_ kind: ReminderKind) -> Bool {
        switch kind {
        case .windDown: windDown
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
/// - Turned off, it schedules nothing.
public struct ReminderPlan: Sendable, Equatable {
    /// Days ahead the plan covers.
    public static let horizonDays = 7
    /// How long before wind-down starts wind-down mode can be opened (the Evening phase, spec §3.3).
    public static let windDownLead: TimeInterval = 2 * 3600

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

        public init(
            nights: [UpcomingNight], settings: ReminderSettings, windDownOpenedAt: Date? = nil, now: Date,
            calendar: Calendar, locale: Locale
        ) {
            self.nights = nights
            self.settings = settings
            self.windDownOpenedAt = windDownOpenedAt
            self.now = now
            self.calendar = calendar
            self.locale = locale
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
