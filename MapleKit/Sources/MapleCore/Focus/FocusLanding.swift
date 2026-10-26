import Foundation
import MapleFocusCore

/// Whether Maple brings the Focus tab forward as the member arrives (F1 design §5.4, §5.8), so the session's own
/// screen greets them: a relaunch mid-session opens on the running session, and a receipt that waits (one that ended
/// while Maple was away among them) shows once "when the member next opens Maple", under its usual finish rules.
///
/// It is asked at two moments only: at launch, once the session store's first refresh has run
/// (`FocusSessionStore.isLoaded`), and on each return from the background, once that return's refresh has run. A
/// session that ends while Maple is open moves no one: its receipt waits on the Focus tab.
public enum FocusLanding {
    public enum Arrival: Sendable, Hashable {
        /// Maple launched, or was brought forward for the first time since a launch in the background.
        case launch
        /// Maple came back from the background.
        case foreground
    }

    /// - Parameters:
    ///   - running: The store's running session.
    ///   - sessions: The store's sessions, for the receipt that waits (`ReceiptPicker.pending`).
    ///   - seen: The last receipt seen (`AppSettings.lastReceiptSeen`).
    ///   - isOnboarding: The first run is on screen.
    ///   - isPresenting: A sheet or full-screen cover is up (the reveal is one): the member is in the middle of
    ///     something, so a receipt waits on the Focus tab instead.
    ///   - now: The store's trusted time.
    /// - Returns: True when Maple should select the Focus tab.
    public static func opensFocus(
        _ arrival: Arrival, running: SessionRecord?, sessions: [SessionRecord], seen: UUID?, isOnboarding: Bool,
        isPresenting: Bool, now: Date
    ) -> Bool {
        guard !isOnboarding, !isPresenting else { return false }
        if let running, !running.isEnded, running.secondsLeft(at: now) > 0 {
            // A relaunch shows the session (§5.4); a return mid-session leaves the member where they were.
            return arrival == .launch
        }
        return ReceiptPicker.pending(sessions, seen: seen, now: now) != nil
    }
}
