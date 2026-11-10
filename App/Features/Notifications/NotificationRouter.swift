import Foundation
import Observation
import UserNotifications
import MapleCore

/// What a tapped notification asks Maple to show (F1 design §6). Tapping a session's end opens that session's
/// receipt: `tappedReceipt` is set here, and `RootView` hands it to the Focus tab as `FocusRequest.receipt(_:)` once
/// the tabs are up, a tap that launched Maple included. Tapping wind-down or the study reminder just opens Maple.
@Observable
final class NotificationRouter {
    /// The session whose end notification was tapped, until `RootView` takes it.
    var tappedReceipt: UUID?

    /// The notification with this identifier was tapped.
    func opened(_ identifier: String) {
        guard let session = ReminderKind.session(inSessionEndIdentifier: identifier) else { return }
        tappedReceipt = session
    }
}

/// Maple's notification-center delegate. `MapleApp.init` sets it before launch finishes, so a tap that launched the
/// app still arrives. iOS may call it off the main thread, so it is nonisolated, and it hands only the tapped
/// identifier, a string, to the main actor.
///
/// - While Maple is in front it presents none of Maple's notifications: a session's end has its receipt on screen,
///   and wind-down and the study reminder never showed in the foreground before either.
/// - A tap on the notification itself (not a dismissal) goes to `opened`, which `MapleApp` points at
///   `NotificationRouter.opened(_:)`.
nonisolated final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    private let opened: @MainActor @Sendable (String) -> Void

    init(opened: @escaping @MainActor @Sendable (String) -> Void) {
        self.opened = opened
        super.init()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            let identifier = response.notification.request.identifier
            let opened = self.opened
            Task { @MainActor in opened(identifier) }
        }
        completionHandler()
    }
}
