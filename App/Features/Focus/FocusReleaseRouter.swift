import MapleCore
import MapleServices

/// Settings' "Release all apps", once its confirmation ("Release all apps? Every app Maple is resting opens again
/// now.", `FocusCopy.ReleaseAll`) is accepted (F1 design §5.12). Task 17's Settings row calls it.
///
/// - With no session running it clears every store now (`FocusSessionStore.releaseAllUnlessRunning()`; on F1 builds, the
///   preview stores) and returns true.
/// - During a session it goes through that strictness level's own way out first and returns false: the Focus tab
///   opens on End early (Gentle, Steady, and every plain timer, which is Gentle whatever its preset) or the emergency
///   release (Locked), through `FocusRequest.releaseAll`.
///   Completing it ends the session and clears every store; "Keep going" leaves everything as it was.
///
/// The store refreshes first, so a session that has just reached its planned end isn't sent through a way out.
@MainActor struct FocusReleaseRouter {
    let router: AppRouter

    /// - Returns: True when every store was cleared now; false when the session's way out was opened instead.
    @discardableResult func releaseAll(from sessions: FocusSessionStore) async -> Bool {
        let released = await sessions.releaseAllUnlessRunning()
        if !released { router.showFocus(.releaseAll) }
        return released
    }
}
