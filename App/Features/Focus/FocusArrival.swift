import SwiftUI
import UIKit
import MapleCore
import MapleServices

/// Brings the Focus tab forward as the member arrives (F1 design §5.4, §5.8; `FocusLanding`): a relaunch mid-session
/// opens on the running session, and a receipt that waits shows once when Maple is next opened.
///
/// - At launch it decides once, after the session store's first refresh (`FocusSessionStore.isLoaded`).
/// - On each return from the background it decides after that return's refresh, so a session that ended while away has
///   its receipt by then. A return mid-session moves no one.
/// - Never during the first run, or while a sheet, a full-screen cover (the reveal among them) or an alert is up: the
///   receipt then waits on the Focus tab.
/// - A DEBUG launch with `-MapleDemoTab` keeps the tab it asked for.
///
/// Applied once, in `RootView`, inside its `AppRouter`.
private struct FocusArrival: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(FocusSessionStore.self) private var sessions
    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router
    let isOnboarding: Bool
    /// The launch's landing has been decided.
    @State private var hasLanded = false
    /// Maple has been in the background since it was last active.
    @State private var wasInBackground = false

    func body(content: Content) -> some View {
        content
            .onChange(of: sessions.isLoaded, initial: true) { _, loaded in
                guard loaded, !hasLanded else { return }
                hasLanded = true
                #if DEBUG
                // A demo launch's explicit tab wins.
                if UserDefaults.standard.string(forKey: "MapleDemoTab") != nil { return }
                #endif
                land(.launch)
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                switch phase {
                case .background:
                    wasInBackground = true
                case .active:
                    let returned = wasInBackground && hasLanded
                    wasInBackground = false
                    guard returned else { return }
                    Task {
                        // This return's own refresh, in line after the one `focusUpkeep()` asks for: once it has run, a
                        // session that ended while away has ended.
                        await sessions.refresh()
                        land(.foreground)
                    }
                default:
                    break
                }
            }
    }

    private func land(_ arrival: FocusLanding.Arrival) {
        guard FocusLanding.opensFocus(
            arrival, running: sessions.running, sessions: sessions.sessions, seen: settings.lastReceiptSeen,
            isOnboarding: isOnboarding, isPresenting: Self.isPresenting, now: sessions.now
        ) else { return }
        router.selectedTab = .focus
    }

    /// A sheet, a full-screen cover or an alert is up in one of Maple's windows, presented from any screen.
    private static var isPresenting: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .contains { presents($0.rootViewController) }
    }

    private static func presents(_ controller: UIViewController?) -> Bool {
        guard let controller else { return false }
        return controller.presentedViewController != nil || controller.children.contains { presents($0) }
    }
}

extension View {
    /// Brings the Focus tab forward as the member arrives (`FocusLanding`). Apply once, at the root, inside the
    /// `AppRouter`'s environment.
    func focusArrival(isOnboarding: Bool) -> some View {
        modifier(FocusArrival(isOnboarding: isOnboarding))
    }
}
