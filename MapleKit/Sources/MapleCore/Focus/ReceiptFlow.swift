import Foundation
import MapleFocusCore

/// What the receipt does around `ReceiptModel` (F1 design §5.8, F1-20): which leaves this session opened, Again by
/// start readiness, and the intention Again carries forward.
public enum ReceiptFlow {
    /// What "Again · 50m" does, from the start readiness of the session's preset at its planned length, now.
    public enum Again: Sendable, Equatable {
        /// One tap starts it.
        case start
        /// Locked: Again is a hold, like every Locked start (§5.2).
        case hold
        /// The start screen has something to say first: Again opens it with the preset and length selected.
        case openStartScreen
    }

    /// The leaf in the receipt dial's centre (§4.3).
    public struct CentreLeaf: Sendable, Equatable {
        public let speciesID: String
        /// This session opened it: it grows into the centre, gold. Otherwise it is the next hours leaf, filled with
        /// what was saved before and during the session.
        public let opened: Bool

        public init(speciesID: String, opened: Bool) {
            self.speciesID = speciesID
            self.opened = opened
        }
    }

    /// The hours leaf this session opened, else the next hours leaf (`next`, after this session's credit); nil when
    /// the session couldn't count (a plain timer, a selection that doesn't qualify) or no hours leaf is left.
    public static func centreLeaf(
        unlocks: [LeafUnlock], next: LeafProgress?, canCount: Bool, catalog: RewardCatalog = .shared
    ) -> CentreLeaf? {
        guard canCount else { return nil }
        if let opened = unlocks.first(where: { catalog.reward(forSpecies: $0.speciesID)?.categoryID == .hoursSaved }) {
            return CentreLeaf(speciesID: opened.speciesID, opened: true)
        }
        guard let next, next.category == .hoursSaved, next.state == .locked else { return nil }
        return CentreLeaf(speciesID: next.speciesID, opened: false)
    }

    public static func again(_ readiness: StartReadiness) -> Again {
        switch readiness {
        case .ready(let needsHold): needsHold ? .hold : .start
        case .needsStartScreen: .openStartScreen
        }
    }

    /// The intention Again starts with: this session's, unless the member said "All done" (§5.8: the reflection
    /// carries forward).
    public static func againIntention(_ intention: String?, reflection: Reflection?) -> String? {
        guard reflection != .allDone else { return nil }
        return intention.flatMap { RecentIntentions.normalized($0) }
    }

    /// The Focus leaves this session opened, for `ReceiptModel(unlocks:)`, oldest first. The store's
    /// `sessionUnlocks` count only when they belong to this session (`storeSession`, the store's `lastEnded`), and any
    /// Focus leaf the collection dated inside the session is added, so a relaunch after the end still names it.
    ///
    /// The session runs to the later of its shown end (`endedAt`) and the moment the app noticed the end
    /// (`end.placed`): an end noticed late (the 15-second refresh, a foreground, a relaunch) dates the focus-streak leaf
    /// at that refresh, after the planned end the receipt shows. The extra second covers the settle that follows an
    /// end's write.
    public static func unlocks(
        store: [LeafUnlock], storeSession: UUID?, collection: [LeafUnlock], session: SessionRecord,
        catalog: RewardCatalog = .shared
    ) -> [LeafUnlock] {
        let focus: Set<RewardCategoryID> = [.hoursSaved, .sessionsFinished, .focusStreak]
        let ended = session.endedAt ?? session.plannedEnd
        let until = max(ended, session.end?.placed ?? ended).addingTimeInterval(1)
        let dated = collection.filter { unlock in
            guard let category = catalog.reward(forSpecies: unlock.speciesID)?.categoryID else { return false }
            return focus.contains(category) && unlock.date >= session.countdownStart && unlock.date <= until
        }
        var seen = Set<String>()
        let own = storeSession == session.id ? store : []
        return (own + dated).filter { seen.insert($0.speciesID).inserted }.sorted { $0.date < $1.date }
    }

    /// The one opened leaf waits for the morning (F1-12): it was earned in wind-down or at night and is still
    /// unopened. False for none or several, which read without it.
    public static func heldUntilMorning(
        _ unlocks: [LeafUnlock], schedule: WeeklySleepSchedule, calendar: Calendar, at date: Date
    ) -> Bool {
        guard unlocks.count == 1, let only = unlocks.first else { return false }
        return RevealSchedule.isHeld(only, at: date, schedule: schedule, calendar: calendar)
    }
}
