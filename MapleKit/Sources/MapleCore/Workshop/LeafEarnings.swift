import Foundation
import MapleFocusCore

/// Plain leaves from sessions (syrup van design §2). Pure.
///
/// Every session earns from its time focused (`SessionRecord.focusedSeconds`: its length without breaks), whether it
/// blocked apps or was a plain timer. Time saved, with its daily cap and its rules about unlocks, decides the special
/// leaves and nothing here. Special leaves are not this: the 155 species still come from the reward table's milestones.
public enum LeafEarnings {
    /// The version of the earning rules. Raise it with any change that would give sessions already in the ledger a
    /// different total (what a session's seconds are, the shortest session that earns, or how leaves are rounded), so
    /// the van starts a new count (`WorkshopBank.noteEarned`) instead of paying old sessions twice or holding new
    /// leaves back. A change of pace needs no new version: the van notices that by itself.
    public static let rulesVersion = 1

    /// The leaves in `seconds`, rounded up: any part of a leaf counts as one.
    public static func leaves(forSeconds seconds: Int, tuning: WorkshopTuning = .starting) -> Int {
        guard tuning.secondsPerLeaf > 0, seconds > 0 else { return 0 }
        return (seconds + tuning.secondsPerLeaf - 1) / tuning.secondsPerLeaf
    }

    /// The leaves one ended session earned: its time focused, rounded up as it ends. A start that never got going
    /// (under `StudyHistory.minimumSeconds`, which History doesn't list either) earns nothing.
    public static func leaves(of record: SessionRecord, tuning: WorkshopTuning = .starting) -> Int {
        let seconds = record.focusedSeconds
        guard seconds >= StudyHistory.minimumSeconds else { return 0 }
        return leaves(forSeconds: seconds, tuning: tuning)
    }

    /// Every leaf the ledger's sessions have earned, rounded session by session.
    /// - Parameters:
    ///   - records: The whole ledger's sessions, the ones removed from History included: removing a session keeps what
    ///     it earned.
    ///   - running: The session running now. Its leaves aren't in the van until it ends.
    public static func total(_ records: [SessionRecord], running: UUID?, tuning: WorkshopTuning = .starting) -> Int {
        records.reduce(0) { sum, record in
            record.id == running ? sum : sum + leaves(of: record, tuning: tuning)
        }
    }
}
