import Foundation
import MapleCore
import Observation
import os

/// Which reminders the member wants, and whether the reminder primer has been offered.
nonisolated public struct ReminderSettings: Codable, Sendable, Equatable {
    /// A nudge as wind-down starts. On unless the member turns it off (it still needs iOS's permission).
    public var windDown: Bool
    /// The quiet morning check-in. Off unless the member turns it on (rewards.md sends no morning push by default).
    public var morning: Bool
    /// When the primer was first offered on its own (after the first run); nil until then. It is offered once.
    public var primerOfferedAt: Date?

    public init(windDown: Bool = true, morning: Bool = false, primerOfferedAt: Date? = nil) {
        self.windDown = windDown
        self.morning = morning
        self.primerOfferedAt = primerOfferedAt
    }

    public func isOn(_ kind: ReminderKind) -> Bool {
        switch kind {
        case .windDown: windDown
        case .morning: morning
        }
    }

    mutating func set(_ kind: ReminderKind, _ isOn: Bool) {
        switch kind {
        case .windDown: windDown = isOn
        case .morning: morning = isOn
        }
    }

    // MARK: Codable (tolerant: missing values take their defaults)

    private enum CodingKeys: String, CodingKey {
        case windDown, morning, primerOfferedAt
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        windDown = (try? c.decodeIfPresent(Bool.self, forKey: .windDown)) ?? true
        morning = (try? c.decodeIfPresent(Bool.self, forKey: .morning)) ?? false
        primerOfferedAt = try? c.decodeIfPresent(Date.self, forKey: .primerOfferedAt)
    }
}

/// Maple's wind-down and morning reminders (architecture M1): what the member wants, what iOS allows, and keeping
/// the scheduled notifications in step with the sleep schedule. One instance for the app, injected with
/// `.environment(_:)`.
///
/// Notifications are scheduled only while iOS allows them; otherwise any pending ones are removed. Every change
/// (a toggle, a new schedule, a foreground that finds the permission changed in Settings) schedules again.
///
/// ```swift
/// @Environment(Reminders.self) private var reminders
///
/// reminders.isOn(.windDown)                               // the Settings toggle
/// await reminders.set(.morning, on: true)                 // false if iOS needs asking first: show the primer
/// await reminders.requestAuthorization(enabling: .morning) // the primer's Continue
/// ```
@Observable
public final class Reminders {
    nonisolated public static let file = "reminders.json"

    public private(set) var settings: ReminderSettings
    /// What iOS allows; nil until the first `refresh()`.
    public private(set) var authorization: ReminderAuthorization?
    /// Apple's prompt is up (or about to be).
    public private(set) var isRequesting = false
    /// False while `reminders.json` exists but can't be read yet (before the first unlock after a restart).
    public private(set) var isAvailable: Bool
    /// The schedule the reminders follow. Set it with `update(schedule:)`.
    public private(set) var schedule: SleepSchedule

    @ObservationIgnored private let storage: JSONStorage<ReminderSettings>
    @ObservationIgnored private let center: any ReminderCenter
    @ObservationIgnored private let locale: Locale
    private static var logger: Logger { Logger(subsystem: "com.maanvikgupta.maple", category: "reminders") }

    /// - Parameter locale: The clock style of the times in the reminders' words.
    public init(
        storage: JSONStorage<ReminderSettings>, center: any ReminderCenter, schedule: SleepSchedule = .standard,
        locale: Locale = .autoupdatingCurrent
    ) {
        self.storage = storage
        self.center = center
        self.schedule = schedule
        self.locale = locale
        switch storage.read() {
        case .value(let saved):
            settings = saved
            isAvailable = true
        case .absent:
            settings = ReminderSettings()
            isAvailable = true
        case .unavailable:
            settings = ReminderSettings()
            isAvailable = false
        }
    }

    // MARK: Reading

    /// The toggle's state: wanted and allowed by iOS.
    public func isOn(_ kind: ReminderKind) -> Bool {
        authorization == .allowed && settings.isOn(kind)
    }

    /// iOS has said no; only the Settings app can change that.
    public var isDenied: Bool { authorization == .denied }

    /// The primer should be offered on its own: iOS hasn't asked yet, and it hasn't been offered before.
    public var shouldOfferPrimer: Bool {
        isAvailable && authorization == .notDetermined && settings.primerOfferedAt == nil
    }

    /// The reminders that would be scheduled now, whatever iOS allows.
    public var planned: [Reminder] {
        ReminderPlan.reminders(for: schedule, windDown: settings.windDown, morning: settings.morning, locale: locale)
    }

    // MARK: Changing

    /// Reads what iOS allows (the member may have changed it in Settings) and schedules again.
    public func refresh() async {
        authorization = await center.authorization()
        await reschedule()
    }

    /// Follows a new sleep schedule.
    public func update(schedule: SleepSchedule) async {
        guard schedule != self.schedule else { return }
        self.schedule = schedule
        await reschedule()
    }

    /// Turns a reminder on or off.
    /// - Returns: False when turning it on needs iOS's permission first: nothing changes, and the caller shows the
    ///   primer (not determined) or points to Settings (denied).
    @discardableResult
    public func set(_ kind: ReminderKind, on isOn: Bool) async -> Bool {
        if isOn, authorization != .allowed { return false }
        change { $0.set(kind, isOn) }
        await reschedule()
        return true
    }

    /// The primer's "Continue": shows Apple's prompt, then turns `kind` on if notifications were allowed.
    /// - Returns: Whether notifications are allowed now.
    @discardableResult
    public func requestAuthorization(enabling kind: ReminderKind? = nil) async -> Bool {
        guard !isRequesting else { return authorization == .allowed }
        isRequesting = true
        defer { isRequesting = false }
        do {
            _ = try await center.requestAuthorization()
        } catch {
            Self.logger.error("The notification prompt failed: \(String(describing: error), privacy: .public)")
        }
        authorization = await center.authorization()
        let allowed = authorization == .allowed
        if allowed, let kind { change { $0.set(kind, true) } }
        await reschedule()
        return allowed
    }

    /// Records that the primer was offered on its own, so it never is again.
    public func markPrimerOffered(at date: Date) {
        guard settings.primerOfferedAt == nil else { return }
        change { $0.primerOfferedAt = date }
    }

    /// Reads the settings again if they couldn't be read at launch.
    /// - Returns: Whether the store now holds the member's real settings (or knows there are none).
    @discardableResult
    public func reloadIfUnavailable() -> Bool {
        guard !isAvailable else { return false }
        switch storage.read() {
        case .value(let saved): settings = saved
        case .absent: settings = ReminderSettings()
        case .unavailable: return false
        }
        isAvailable = true
        return true
    }

    // MARK: Launch

    /// The member's reminder settings in `directory`, delivered through iOS.
    public static func live(
        directory: URL = MapleContainer.directory(), center: any ReminderCenter = UserNotificationCenter(),
        schedule: SleepSchedule
    ) -> Reminders {
        Reminders(storage: JSONStorage(.file(directory.appending(path: file))), center: center, schedule: schedule)
    }

    // MARK: Private

    /// Schedules what is wanted while iOS allows it; removes Maple's pending reminders otherwise. Nothing is
    /// touched until iOS has been asked (`authorization` is read first) or while the settings can't be read.
    private func reschedule() async {
        guard let authorization, isAvailable else { return }
        let reminders = authorization == .allowed ? planned : []
        do {
            try await center.schedule(reminders)
        } catch {
            Self.logger.error("Couldn't schedule reminders: \(String(describing: error), privacy: .public)")
        }
    }

    private func change(_ edit: (inout ReminderSettings) -> Void) {
        // A change lands on the member's real settings, never on defaults saved over an unreadable file.
        if !isAvailable { reloadIfUnavailable() }
        var copy = settings
        edit(&copy)
        guard copy != settings else { return }
        settings = copy
        storage.save(copy)
    }
}
