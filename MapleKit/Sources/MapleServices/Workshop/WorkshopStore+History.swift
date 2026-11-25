import Foundation
import MapleCore

extension WorkshopStore {
    /// Brings the van's leaves up to what the whole ledger shows (syrup van design §2). Call it after
    /// `FocusSessionStore.loadHistory()`: at launch, and when a session ends. Calling it again with the same ledger
    /// changes nothing.
    /// - Parameters:
    ///   - history: `FocusSessionStore.history`; nil before History has been read, which changes nothing.
    ///   - running: The session running now (`FocusSessionStore.running?.id`). Its leaves arrive when it ends.
    /// - Returns: The leaves newly in the van.
    @discardableResult
    public func collect(from history: FocusSessionStore.History?, running: UUID?) -> Int {
        guard let history else { return 0 }
        return noteEarned(LeafEarnings.total(history.records, credits: history.credits, running: running, tuning: tuning))
    }
}
