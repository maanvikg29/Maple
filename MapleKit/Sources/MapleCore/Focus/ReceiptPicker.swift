import Foundation

/// Which ended session's receipt to show (P5): a receipt shows once, including for a session that ended while Maple
/// was closed (F1 design §5.8 "Ended while away").
public enum ReceiptPicker {
    /// How long a receipt waits to be seen after its session ended.
    public static let window: TimeInterval = 24 * 3600

    /// The newest ended session (by `endedAt`), when it ended less than 24 hours before `now` and isn't `seen`
    /// (`AppSettings.lastReceiptSeen`); otherwise nil. An older unseen session never comes back once a newer one has
    /// ended. A start written only halfway (a blocking session whose block was never confirmed, ended at once) and a
    /// hidden session are never receipts.
    public static func pending(_ sessions: [SessionRecord], seen: UUID?, now: Date) -> SessionRecord? {
        var newest: (session: SessionRecord, endedAt: Date)?
        for session in sessions where !session.isHidden && !isHalfWritten(session) {
            guard let endedAt = session.endedAt else { continue }
            if newest.map({ endedAt >= $0.endedAt }) ?? true { newest = (session, endedAt) }
        }
        guard let newest, newest.session.id != seen, now.timeIntervalSince(newest.endedAt) < window else { return nil }
        return newest.session
    }

    /// A blocking session that ended without its block ever confirmed: the start couldn't be written whole, so it was
    /// ended at once (`FocusSessionStore`).
    private static func isHalfWritten(_ session: SessionRecord) -> Bool {
        session.plan.kind == .blocking && session.applied == nil
    }
}
