import Foundation

/// The two local notifications Maple sends (M1, the sleep loop). There are no others.
public enum ReminderKind: String, Sendable, Hashable, CaseIterable {
    /// "Time to wind down" at the start of wind-down. It never mentions leaves or progress (rewards.md).
    case windDown
    /// "A new leaf is waiting" at the start of the morning, only when one is.
    case morningLeaf

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

    /// How a notification of this kind shows while Maple is open: wind-down shows nothing (the member is already
    /// here), the morning leaf shows as a banner.
    public var foregroundPresentation: ReminderForegroundPresentation {
        switch self {
        case .windDown: .hidden
        case .morningLeaf: .banner
        }
    }

    /// Where a tap on this kind leads: the morning leaf opens the reveal; wind-down just opens the app.
    public var route: ReminderRoute? {
        switch self {
        case .windDown: nil
        case .morningLeaf: .reveal
        }
    }
}

/// How a notification arrives (`UNNotificationInterruptionLevel`, without importing UserNotifications).
public enum ReminderInterruption: String, Sendable, Hashable {
    /// Silent: no sound, the screen stays dark; it waits on the Lock Screen and in Notification Center.
    case passive
    /// The usual alert, which Focus modes (Sleep included) may hold back.
    case active
}

/// How a notification shows while the app is in the foreground.
public enum ReminderForegroundPresentation: Sendable, Hashable {
    case hidden
    case banner
}

/// Where a notification tap leads in the app.
public enum ReminderRoute: String, Sendable, Hashable {
    /// The reveal (`RevealFlow()`), for the waiting leaves.
    case reveal
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

    /// Where a tap leads.
    public var route: ReminderRoute? { kind.route }
}

/// Which reminders the member wants (Profile › Settings). Both are on until they turn one off; nothing is sent
/// until iOS allows Maple's notifications.
public struct ReminderSettings: Sendable, Hashable {
    public var windDown: Bool
    public var morningLeaf: Bool

    public init(windDown: Bool = true, morningLeaf: Bool = true) {
        self.windDown = windDown
        self.morningLeaf = morningLeaf
    }

    public static let allOn = ReminderSettings()
    public static let allOff = ReminderSettings(windDown: false, morningLeaf: false)

    public func allows(_ kind: ReminderKind) -> Bool {
        switch kind {
        case .windDown: windDown
        case .morningLeaf: morningLeaf
        }
    }
}

/// An earned leaf that hasn't been opened yet, and when it may first be opened: its unlock time, or for a leaf
/// earned from Evening on, the next morning start (`RevealSchedule.releaseDate`).
public struct WaitingLeaf: Sendable, Hashable {
    public var speciesID: String
    public var opensAt: Date

    public init(speciesID: String, opensAt: Date) {
        self.speciesID = speciesID
        self.opensAt = opensAt
    }
}

/// The reminders' words (calm, sentence case, one short line each, no emoji or exclamation marks, never guilt).
public enum ReminderCopy {
    public static let windDownTitle = "Time to wind down"

    /// "Bed at 23:00." or "Bed at 11:00 PM.", in the member's clock style.
    public static func windDownBody(bedtime: Date, calendar: Calendar, locale: Locale) -> String {
        "Bed at \(HomeFormat.clock(HomeFormat.clockTime(of: bedtime, calendar: calendar), locale: locale))."
    }

    /// "A new leaf is waiting" or "2 new leaves are waiting", as Home's waiting row says it.
    public static func morningLeafTitle(count: Int) -> String {
        count <= 1 ? "A new leaf is waiting" : "\(count) new leaves are waiting"
    }

    public static func morningLeafBody(count: Int) -> String {
        count <= 1 ? "Open it on your maple." : "Open them on your maple."
    }
}

/// The local notifications Maple should have scheduled right now (M1). Pure: the app builds the input from its
/// stores, and `NotificationScheduler` replaces Maple's pending requests with `requests`.
///
/// Rules:
/// - **Wind-down** at each night's wind-down start: "Time to wind down" · "Bed at 23:00.". Not once that moment
///   has passed, not on a night with no wind-down (it starts at bedtime), and not on a night whose wind-down mode
///   the member has already opened (from 2 hours before wind-down until bedtime, the Evening and Wind-down
///   phases in which it can be opened).
/// - **Morning leaf** at a morning start, only when a leaf is waiting that this morning is the first to offer:
///   a leaf held overnight (earned from Evening on, opening at this morning start), or one that opened since the
///   last morning start and is still unopened. Each leaf is announced on one morning only, so an unopened leaf
///   never brings a second reminder. The count is every leaf openable by then: "2 new leaves are waiting".
///   It is passive and silent, because the morning starts an hour before wake-up.
/// - At most one of each kind per night, named by the night's evening; a second night with the same name (an
///   overlap in the input) adds nothing.
/// - Nothing ever fires between a bedtime and the next morning start.
/// - Only within the next 7 days (`horizonDays`), well under iOS's 64 pending requests.
/// - A kind the member turned off schedules nothing.
public struct ReminderPlan: Sendable, Equatable {
    /// Days ahead the plan covers.
    public static let horizonDays = 7
    /// How long before wind-down starts wind-down mode can be opened (the Evening phase, spec §3.3).
    public static let windDownLead: TimeInterval = 2 * 3600

    public struct Input: Sendable {
        /// Nights in order. Nights whose moments have passed are fine: the latest morning start before `now`
        /// marks which waiting leaves were already announced.
        public var nights: [UpcomingNight]
        public var settings: ReminderSettings
        /// Every earned leaf not yet opened (held or pending).
        public var waiting: [WaitingLeaf]
        /// When wind-down mode was last opened (the bedside log's start); nil if never.
        public var windDownOpenedAt: Date?
        public var now: Date
        /// The member's calendar, for naming nights and reading the bedtime's clock time.
        public var calendar: Calendar
        public var locale: Locale

        public init(
            nights: [UpcomingNight], settings: ReminderSettings, waiting: [WaitingLeaf] = [],
            windDownOpenedAt: Date? = nil, now: Date, calendar: Calendar, locale: Locale
        ) {
            self.nights = nights
            self.settings = settings
            self.waiting = waiting
            self.windDownOpenedAt = windDownOpenedAt
            self.now = now
            self.calendar = calendar
            self.locale = locale
        }
    }

    /// What to schedule, in fire order.
    public let requests: [ReminderRequest]
    /// Kinds whose delivered notifications no longer hold and should leave Notification Center: the morning leaf
    /// once nothing is waiting to be opened, wind-down outside a wind-down the member hasn't started.
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

        for (index, night) in nights.enumerated() {
            let name = night.name(in: input.calendar).description
            // A night that overlaps one already planned (the same evening) adds nothing.
            guard named.insert(name).inserted else { continue }
            let previousMorning = index > 0
                ? nights[index - 1].morningStart
                : night.morningStart.addingTimeInterval(-24 * 3600)
            let candidates = [
                Self.windDown(for: night, name: name, input: input),
                Self.morningLeaf(for: night, name: name, previousMorning: previousMorning, input: input),
            ]
            for request in candidates.compactMap({ $0 })
            where request.fireDate > input.now && request.fireDate <= horizon
                && !Self.isDuringSleep(request.fireDate, nights: nights) {
                requests.append(request)
            }
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

    private static func morningLeaf(
        for night: UpcomingNight, name: String, previousMorning: Date, input: Input
    ) -> ReminderRequest? {
        guard input.settings.morningLeaf else { return nil }
        let morning = night.morningStart
        // Announced on the first morning start at or after it opens, and on no other.
        let new = input.waiting.contains { $0.opensAt > previousMorning && $0.opensAt <= morning }
        guard new else { return nil }
        let count = input.waiting.filter { $0.opensAt <= morning }.count
        let kind = ReminderKind.morningLeaf
        return ReminderRequest(
            id: kind.identifierPrefix + name, kind: kind, fireDate: morning, calendar: input.calendar,
            title: ReminderCopy.morningLeafTitle(count: count), body: ReminderCopy.morningLeafBody(count: count),
            threadID: kind.threadID, interruption: .passive, playsSound: false
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
        var stale: Set<ReminderKind> = []
        if !input.waiting.contains(where: { $0.opensAt <= input.now }) {
            stale.insert(.morningLeaf)
        }
        let inWindDown = nights.contains { night in
            input.now >= night.windDownStart && input.now < night.bedtime
                && !(input.windDownOpenedAt.map { openedWindDown(of: night, at: $0) } ?? false)
        }
        if !inWindDown { stale.insert(.windDown) }
        return stale
    }
}
