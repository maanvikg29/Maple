import Foundation
import MapleCore

extension WorkshopStore {
    /// Brings the van's leaves up to what the whole ledger shows (syrup van design §2). Call it after
    /// `FocusSessionStore.loadHistory()`: at launch, and when a session ends. Calling it again with the same ledger
    /// changes nothing.
    /// - Parameter history: `FocusSessionStore.history`; nil before History has been read, which changes nothing. The
    ///   running session is in it and adds nothing until it reaches the end of its timer.
    /// - Returns: The leaves newly in the van.
    @discardableResult
    public func collect(from history: FocusSessionStore.History?) -> Int {
        guard let history else { return 0 }
        return noteEarned(LeafEarnings.total(history.records, tuning: tuning))
    }
}
