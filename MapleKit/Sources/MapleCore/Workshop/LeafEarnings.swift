import Foundation
import MapleFocusCore

/// Plain leaves from sessions (syrup van design §2). Pure.
///
/// A session earns only by reaching the end of its timer. Then it earns from its time focused
/// (`SessionRecord.focusedSeconds`: its length without breaks), whether it blocked apps or was a plain timer. A session
/// ended before its timer ran out earns nothing, however long it ran; it stays in the record as ended early. Time
/// saved, with its daily cap and its rules about unlocks, decides the special leaves and nothing here. Special leaves
/// are not this: the 155 species still come from the reward table's milestones.
public enum LeafEarnings {
    /// The version of the earning rules. Raise it with any change that would give sessions already in the ledger a
    /// different total (what a session's seconds are, which sessions earn, or how leaves are rounded), so the van
    /// starts a new count (`WorkshopBank.noteEarned`) instead of paying old sessions twice or holding new leaves back.
    /// A change of pace needs no new version: the van notices that by itself.
    public static let rulesVersion = 1

    /// The leaves in `seconds`, rounded up: any part of a leaf counts as one.
    public static func leaves(forSeconds seconds: Int, tuning: WorkshopTuning = .starting) -> Int {
        guard tuning.leavesPerHour > 0, seconds > 0 else { return 0 }
        let (scaled, overflow) = seconds.multipliedReportingOverflow(by: tuning.leavesPerHour)
        guard !overflow, scaled <= Int.max - 3599 else { return WorkshopBank.limit }
        return min((scaled + 3599) / 3600, WorkshopBank.limit)
    }

    /// The leaves one session earned: its time focused, rounded up, if it reached the end of its timer
    /// (`EndReason.completed`). Ended any other way (End early, the emergency release, Release all apps) or still
    /// running, it has earned nothing.
    public static func leaves(of record: SessionRecord, tuning: WorkshopTuning = .starting) -> Int {
        guard record.endReason == .completed else { return 0 }
        return leaves(forSeconds: record.focusedSeconds, tuning: tuning)
    }

    /// Every leaf the ledger's sessions have earned, rounded session by session.
    /// - Parameter records: The whole ledger's sessions, the ones removed from History included: removing a session
    ///   keeps what it earned. The running session is among them and adds nothing until it reaches its end.
    public static func total(_ records: [SessionRecord], tuning: WorkshopTuning = .starting) -> Int {
        records.reduce(0) { min($0 + leaves(of: $1, tuning: tuning), WorkshopBank.limit) }
    }
}
