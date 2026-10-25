import Foundation
import MapleCore

extension FocusStores {
    /// Starts a session from a screen (F1 design §5.1, P4): the store's start, and once it has started:
    /// - the preset is marked used, so the next start preselects it, and a starter preset is saved with its id;
    /// - the intention is kept for the session, at its start, in `session-notes.json`, never in the ledger (a blank one
    ///   keeps nothing);
    /// - the first start is recorded (`AppSettings.hasStartedFocus`).
    ///
    /// Nothing is kept when the session doesn't start.
    public func start(
        _ request: FocusSessionStore.StartRequest, intention: String?, settings: AppSettings
    ) async -> FocusSessionStore.StartOutcome {
        let outcome = await sessions.start(request)
        guard case .started(let id) = outcome else { return outcome }
        presets.markUsed(request.preset.id)
        if let text = intention.flatMap(RecentIntentions.normalized) {
            notes.setIntention(text, for: id, at: sessions.running?.started.placed ?? sessions.now)
        }
        settings.hasStartedFocus = true
        return outcome
    }
}
