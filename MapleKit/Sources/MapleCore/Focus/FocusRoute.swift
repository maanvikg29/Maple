import Foundation
import MapleFocusCore

/// Which screen the Focus tab shows (F1 design §5), from the session store's state at `now`. Drawn from the store,
/// so a killed app comes back to the same session (§5.4), and a session that ended while Maple was closed opens on
/// its receipt, never on a running dial at 0:00 (§5.8; Review Focus 1, 2).
///
/// In order:
/// 1. Before the store's first refresh: `settling`.
/// 2. A running session: `minimised` once ⌄ tucked it away; `breakTime` while its break runs; otherwise `running`.
///    Past its planned end it keeps that screen's last frame (`frameTime`) for `endGrace`, while the refresh that ends
///    it lands, and is `settling` after that: a session found past its end then ended while Maple was away.
/// 3. A receipt to show (the one on screen, or `ReceiptPicker.pending`).
/// 4. `needsScreenTime` while blocking isn't available, until the member picks the plain timer.
/// 5. `start`.
public enum FocusRoute: Sendable, Hashable {
    /// Nothing is drawn: the store's first refresh hasn't run, or a running session is found well past its planned end.
    case settling
    case start
    case needsScreenTime
    case running(UUID)
    /// The running session tucked away: the start screen's "Session running, minimised" state (§5.1).
    case minimised(UUID)
    case breakTime(UUID)
    case receipt(UUID)

    /// - Parameters:
    ///   - isLoaded: The store's first refresh has run and the ledger can be read (`FocusSessionStore.isLoaded` and
    ///     `isLedgerReadable`).
    ///   - running: The store's running session.
    ///   - receipt: The receipt on screen, else the one to show (`ReceiptPicker.pending`); nil for none.
    ///   - canBlock: The build can block and Screen Time allows it.
    ///   - usesPlainTimer: The member chose the plain timer (or took it after a failed lock).
    public static func resolve(
        isLoaded: Bool, running: SessionRecord?, receipt: UUID?, isMinimised: Bool, canBlock: Bool, usesPlainTimer: Bool,
        now: Date
    ) -> FocusRoute {
        guard isLoaded else { return .settling }
        if let running, !running.isEnded {
            guard now < running.plannedEnd.addingTimeInterval(endGrace) else { return .settling }
            if isMinimised { return .minimised(running.id) }
            return running.isInBreak(at: frameTime(running, now: now)) ? .breakTime(running.id) : .running(running.id)
        }
        if let receipt { return .receipt(receipt) }
        return canBlock || usesPlainTimer ? .start : .needsScreenTime
    }

    /// How long a running session's screen keeps its last frame after the planned end, while the refresh that ends the
    /// session lands (`FocusUpkeep` asks for it a tenth of a second after the end, half a second at most), so the finish
    /// follows the last running frame with nothing blank between. A session found past its end any later ended while
    /// Maple was away: nothing is drawn until its receipt, never a running dial (Review Focus 2).
    public static let endGrace: TimeInterval = 2

    /// The moment a running session's screen draws at `now`: `now`, held just short of the planned end. In the beat
    /// between the end and the refresh that ends the session the screen keeps its last running frame, never 0:00.
    public static func frameTime(_ session: SessionRecord, now: Date) -> Date {
        min(now, session.plannedEnd.addingTimeInterval(-0.001))
    }

    /// When the route can next change with time alone: the running break's end, else the end of the last frame's grace
    /// (`endGrace` after the planned end); nil when nothing runs. The tab reads its route again then, because nothing in
    /// the store changes when a break runs out.
    public static func nextChange(running: SessionRecord?, now: Date) -> Date? {
        guard let running, !running.isEnded else { return nil }
        return running.breakEnd(at: now) ?? running.plannedEnd.addingTimeInterval(endGrace)
    }
}
