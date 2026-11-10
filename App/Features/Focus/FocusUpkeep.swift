import SwiftUI
import UIKit
import MapleCore
import MapleServices

/// Keeps `FocusSessionStore` current (F1 design §7.4 and its timing rule). It refreshes on launch and on every
/// return to the foreground, when protected data becomes available, and while a session runs: every 15 seconds,
/// and at the break's end and the planned end (`FocusRefresh`, P6). Each refresh also ends a session whose planned
/// end has passed, so a session that ended while Maple was closed has its receipt when the Focus tab opens.
///
/// Applied once at the root, beside `reminderUpkeep()`. It has no `TimelineView`: the root must not have one
/// (`MapleApp.swift`). The dial's once-a-second timeline lives in the screen that shows it.
private struct FocusUpkeep: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(FocusSessionStore.self) private var sessions

    func body(content: Content) -> some View {
        content
            // Launch, and every return to the foreground. The Live Activity hears of the return first, so this refresh
            // can ask again for an activity ActivityKit refused.
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                sessions.mapleBecameActive()
                await sessions.refresh()
            }
            // While a session runs and Maple is in front. Started again when a session starts or ends, when a break
            // starts, and on every return to the foreground.
            .task(id: RunningKey(session: sessions.running?.id, breaks: sessions.running?.breaks.count ?? 0,
                                 isActive: scenePhase == .active)) {
                guard scenePhase == .active else { return }
                await keepRefreshing()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
                Task { await sessions.refresh() }
            }
    }

    /// Refreshes at each `FocusRefresh.next` until nothing runs, or the task is cancelled.
    private func keepRefreshing() async {
        while let next = FocusRefresh.next(after: sessions.now, running: sessions.running) {
            // A tenth of a second late, so the refresh at the planned end finds the end has passed.
            let delay = max(0.5, next.timeIntervalSince(sessions.now) + 0.1)
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            await sessions.refresh()
        }
    }
}

/// What restarts the running refreshes.
private struct RunningKey: Equatable {
    var session: UUID?
    var breaks: Int
    var isActive: Bool
}

extension View {
    /// Keeps the Focus session store current. Apply once, at the root.
    func focusUpkeep() -> some View {
        modifier(FocusUpkeep())
    }
}
