import Foundation
import MapleFocusCore

/// Plain leaves from sessions (syrup van design §2, §13 answers 1 and 2). Pure.
///
/// Special leaves are not this: the 155 species still come from the reward table's milestones.
public enum LeafEarnings {
    /// The seconds of a session that earn leaves: its counted time when it blocked apps, its time focused when it was a
    /// plain timer (which counts nothing as saved).
    public static func seconds(of record: SessionRecord, credit: SessionCredit?) -> Int {
        record.plan.kind == .plainTimer ? record.focusedSeconds : max(0, credit?.seconds ?? 0)
    }

    /// Whole leaves in `seconds`.
    public static func leaves(forSeconds seconds: Int, tuning: WorkshopTuning = .starting) -> Int {
        guard tuning.secondsPerLeaf > 0 else { return 0 }
        return max(0, seconds) / tuning.secondsPerLeaf
    }

    /// The leaves one session earned. A session ended early keeps the ones that had fallen.
    public static func leaves(of record: SessionRecord, credit: SessionCredit?, tuning: WorkshopTuning = .starting) -> Int {
        leaves(forSeconds: seconds(of: record, credit: credit), tuning: tuning)
    }

    /// Every leaf the ledger's sessions have earned, counted session by session.
    /// - Parameters:
    ///   - records: The whole ledger's sessions, the ones removed from History included: removing a session keeps what
    ///     it earned.
    ///   - credits: `HoursCredit.credit` over the same records.
    ///   - running: The session running now. Its leaves aren't in the van until it ends.
    public static func total(
        _ records: [SessionRecord], credits: [SessionCredit], running: UUID?, tuning: WorkshopTuning = .starting
    ) -> Int {
        var byID: [UUID: SessionCredit] = [:]
        for credit in credits where byID[credit.id] == nil { byID[credit.id] = credit }
        return records.reduce(0) { sum, record in
            record.id == running ? sum : sum + leaves(of: record, credit: byID[record.id], tuning: tuning)
        }
    }
}
