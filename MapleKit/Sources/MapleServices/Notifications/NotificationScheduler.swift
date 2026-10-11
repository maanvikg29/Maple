import Foundation
import MapleCore
import Observation
import UserNotifications
import os

/// Whether iOS lets Maple send notifications.
nonisolated public enum ReminderAuthorization: Sendable, Equatable {
    /// Maple hasn't asked yet: Settings offers the primer.
    case notDetermined
    /// The member said no, or turned Maple's notifications off in iOS Settings.
    case denied
    /// Allowed (provisional and ephemeral authorizations count too).
    case allowed

    public init(_ status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .denied: self = .denied
        case .authorized, .provisional, .ephemeral: self = .allowed
        @unknown default: self = .denied
        }
    }
}

/// When a notification fires.
nonisolated public enum ReminderTrigger: Sendable, Hashable {
    /// At a local wall-clock time (`ReminderRequest.fireComponents`).
    case date(DateComponents)
    /// After a number of seconds (DEBUG demos).
    case after(TimeInterval)
}

/// The parts of `UNUserNotificationCenter` Maple uses: `UserNotificationCenter` in the app, a stand-in in tests.
public protocol NotificationCentering: AnyObject {
    func authorization() async -> ReminderAuthorization
    /// Shows iOS's notification prompt (alerts and sounds; never badges).
    func requestAuthorization() async throws -> Bool
    func pendingIdentifiers() async -> [String]
    func deliveredIdentifiers() async -> [String]
    func removePending(_ identifiers: [String])
    func removeDelivered(_ identifiers: [String])
    /// Adds the request, replacing a pending one with the same identifier.
    func add(_ request: ReminderRequest, trigger: ReminderTrigger) async throws
}

/// The app's notification center.
public final class UserNotificationCenter: NotificationCentering {
    private var center: UNUserNotificationCenter { .current() }

    public init() {}

    public func authorization() async -> ReminderAuthorization {
        ReminderAuthorization(await center.notificationSettings().authorizationStatus)
    }

    public func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    public func pendingIdentifiers() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }

    public func deliveredIdentifiers() async -> [String] {
        await center.deliveredNotifications().map(\.request.identifier)
    }

    public func removePending(_ identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    public func removeDelivered(_ identifiers: [String]) {
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    public func add(_ request: ReminderRequest, trigger: ReminderTrigger) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.threadIdentifier = request.threadID
        content.interruptionLevel = switch request.interruption {
        case .passive: .passive
        case .active: .active
        }
        content.sound = request.playsSound ? .default : nil
        let notificationTrigger: UNNotificationTrigger = switch trigger {
        case .date(let components): UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        case .after(let seconds): UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        }
        try await center.add(UNNotificationRequest(identifier: request.id, content: content, trigger: notificationTrigger))
    }
}

/// Maple's local notification: "Time to wind down", nothing else (focus spec §8). One instance for the app,
/// created by `MapleApp` and injected with `.environment(_:)`.
///
/// ```swift
/// @Environment(NotificationScheduler.self) private var reminders
///
/// reminders.authorization                     // .notDetermined, .denied or .allowed
/// await reminders.requestAuthorization()      // iOS's prompt (alerts and sounds, no badge)
/// await reminders.reschedule(plan: plan)      // Maple's pending requests become exactly the plan's
/// ```
///
/// While Maple is open iOS shows nothing (there is no notification-center delegate); a tap just opens the app.
@Observable
public final class NotificationScheduler {
    /// Whether iOS lets Maple notify. Read again on every foreground (`refreshAuthorization()`).
    public private(set) var authorization: ReminderAuthorization
    /// iOS's prompt is up (or about to be).
    public private(set) var isRequesting = false
    /// What the last reschedule left pending, in fire order.
    public private(set) var scheduled: [ReminderRequest] = []
    /// False for DEBUG demo launches: their stores live in memory, so they never replace the member's real
    /// reminders.
    @ObservationIgnored public var schedulesReminders = true

    @ObservationIgnored private let center: any NotificationCentering
    @ObservationIgnored private let clock: MapleClock
    /// The reschedule in progress; each waits for the one before, so two never interleave.
    @ObservationIgnored private var work: Task<Void, Never>?
    private static var logger: Logger { Logger(subsystem: "com.maanvikgupta.maple", category: "reminders") }

    public init(center: any NotificationCentering, clock: MapleClock = .live, authorization: ReminderAuthorization = .notDetermined) {
        self.center = center
        self.clock = clock
        self.authorization = authorization
    }

    /// The app's scheduler, on the system notification center.
    public static func live() -> NotificationScheduler {
        NotificationScheduler(center: UserNotificationCenter())
    }

    /// What this launch should use: the live scheduler, which DEBUG demo launches keep from rescheduling.
    public static func launch() -> NotificationScheduler {
        let scheduler = live()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("-MapleDemo") }) {
            scheduler.schedulesReminders = false
        }
        // `-MapleDemoNotifyStatus allowed|denied|notDetermined`: Settings as if iOS had answered that way.
        switch UserDefaults.standard.string(forKey: "MapleDemoNotifyStatus")?.lowercased() {
        case "allowed": scheduler.showForDemo(.allowed)
        case "denied": scheduler.showForDemo(.denied)
        case "notdetermined": scheduler.showForDemo(.notDetermined)
        default: break
        }
        #endif
        return scheduler
    }

    public var isAllowed: Bool { authorization == .allowed }

    /// Reads iOS's answer again (the member may have changed it in iOS Settings).
    public func refreshAuthorization() async {
        #if DEBUG
        if let demoAuthorization {
            authorization = demoAuthorization
            return
        }
        #endif
        let status = await center.authorization()
        if status != authorization { authorization = status }
    }

    /// iOS's notification prompt, asking for alerts and sounds (no badge).
    /// - Returns: Whether Maple may notify now.
    @discardableResult
    public func requestAuthorization() async -> Bool {
        guard !isRequesting else { return isAllowed }
        isRequesting = true
        defer { isRequesting = false }
        do {
            _ = try await center.requestAuthorization()
        } catch {
            Self.logger.error("The notification prompt failed: \(String(describing: error), privacy: .public)")
        }
        await refreshAuthorization()
        return isAllowed
    }

    /// Makes Maple's pending requests exactly the plan's: removes the ones it no longer has, adds (or replaces)
    /// the rest, and clears delivered ones that no longer hold. Only the next 7 days are ever pending, and nothing
    /// while iOS doesn't allow Maple to notify. Requests other apps' code made are never touched.
    public func reschedule(plan: ReminderPlan) async {
        let previous = work
        let task = Task { [weak self] in
            await previous?.value
            await self?.apply(plan)
        }
        work = task
        await task.value
    }

    // MARK: Private

    private func apply(_ plan: ReminderPlan) async {
        guard schedulesReminders else { return }
        await refreshAuthorization()
        let now = clock.now()
        let horizon = now.addingTimeInterval(TimeInterval(ReminderPlan.horizonDays) * 24 * 3600)
        let wanted = isAllowed ? plan.requests.filter { $0.fireDate > now && $0.fireDate <= horizon } : []
        let wantedIDs = Set(wanted.map(\.id))

        let stale = await center.pendingIdentifiers()
            .filter { $0.hasPrefix(ReminderKind.identifierPrefix) && !wantedIDs.contains($0) }
        if !stale.isEmpty { center.removePending(stale) }
        var added: [ReminderRequest] = []
        for request in wanted {
            do {
                try await center.add(request, trigger: .date(request.fireComponents))
                added.append(request)
            } catch {
                Self.logger.error("Couldn't schedule \(request.id, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }

        if !plan.staleDelivered.isEmpty {
            let outdated = await center.deliveredIdentifiers().filter { identifier in
                ReminderKind(identifier: identifier).map(plan.staleDelivered.contains) ?? false
            }
            if !outdated.isEmpty { center.removeDelivered(outdated) }
        }
        if added != scheduled { scheduled = added }
    }

    #if DEBUG
    /// DEBUG `-MapleDemoNotifyStatus`: shows this answer instead of iOS's, for screenshots of each state.
    @ObservationIgnored private var demoAuthorization: ReminderAuthorization?

    public func showForDemo(_ status: ReminderAuthorization) {
        demoAuthorization = status
        authorization = status
    }

    /// DEBUG `-MapleDemoNotify`: posts `request` `seconds` from now, asking iOS first if it hasn't been asked.
    public func postDemo(_ request: ReminderRequest, after seconds: TimeInterval) async {
        if await center.authorization() == .notDetermined { _ = try? await center.requestAuthorization() }
        do {
            try await center.add(request, trigger: .after(seconds))
        } catch {
            Self.logger.error("Couldn't post the demo reminder: \(String(describing: error), privacy: .public)")
        }
    }
    #endif
}
