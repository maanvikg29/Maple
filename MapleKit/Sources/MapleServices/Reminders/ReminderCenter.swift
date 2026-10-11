import Foundation
import MapleCore
import UserNotifications

/// What iOS allows for Maple's notifications.
nonisolated public enum ReminderAuthorization: Sendable, Equatable {
    /// Apple's prompt hasn't been shown yet.
    case notDetermined
    /// The member said no, or turned notifications off in Settings.
    case denied
    /// Notifications can be delivered (authorized, provisional or ephemeral).
    case allowed
}

/// Delivers Maple's reminders: `UserNotificationCenter` in the app, a stand-in in tests and DEBUG demos.
public protocol ReminderCenter {
    func authorization() async -> ReminderAuthorization
    /// Shows Apple's notification prompt. Returns whether notifications are allowed once it is answered.
    func requestAuthorization() async throws -> Bool
    /// Replaces every pending Maple reminder with `reminders` (an empty list removes them all).
    func schedule(_ reminders: [Reminder]) async throws
}

/// `UNUserNotificationCenter`, with one daily calendar trigger per reminder. The triggers carry no time zone, so
/// they follow the device's: a reminder set for 22:15 fires at 22:15 wherever the member is, and across
/// daylight-saving changes.
public struct UserNotificationCenter: ReminderCenter {
    public init() {}

    private var center: UNUserNotificationCenter { .current() }

    public func authorization() async -> ReminderAuthorization {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .authorized, .provisional, .ephemeral: .allowed
        case .denied: .denied
        @unknown default: .denied
        }
    }

    public func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    public func schedule(_ reminders: [Reminder]) async throws {
        center.removePendingNotificationRequests(withIdentifiers: ReminderKind.allCases.map(\.identifier))
        for reminder in reminders {
            try await center.add(Self.request(for: reminder))
        }
    }

    static func request(for reminder: Reminder) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = reminder.isQuiet ? nil : .default
        content.interruptionLevel = reminder.isQuiet ? .passive : .active
        content.threadIdentifier = reminder.kind.identifier
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: DateComponents(hour: reminder.time.hour, minute: reminder.time.minute), repeats: true
        )
        return UNNotificationRequest(identifier: reminder.kind.identifier, content: content, trigger: trigger)
    }
}

#if DEBUG
/// DEBUG demos: notifications count as allowed, so Settings shows its reminder rows on, and nothing is ever
/// scheduled on the device.
public struct SilentReminderCenter: ReminderCenter {
    public init() {}
    public func authorization() async -> ReminderAuthorization { .allowed }
    public func requestAuthorization() async throws -> Bool { true }
    public func schedule(_ reminders: [Reminder]) async throws {}
}
#endif
