import Foundation

/// What the screens show of a session: when it ended, the time left and the break (F1 design §5.4–§5.8). Every screen
/// passes trusted time (`FocusSessionStore.now`) as the date.
extension SessionRecord {
    /// When the session ended, as the receipt and Saved today say it. For a session that ran to its end, that is the
    /// planned end: the end event is stamped when the app noticed (a relaunch can be hours later, P5). For every other
    /// ending it is the end itself. Nil while the session runs.
    public var endedAt: Date? {
        guard let end else { return nil }
        return endReason == .completed ? min(end.placed, plannedEnd) : end.placed
    }

    /// Seconds to the planned end at `date` (`plannedEnd − date`, on every surface), never below zero; 0 once the
    /// session has ended.
    public func secondsLeft(at date: Date) -> TimeInterval {
        guard end == nil else { return 0 }
        return max(0, plannedEnd.timeIntervalSince(date))
    }

    /// The preset's one break is running at `date`: started, not ended by "Back to studying", and not yet run out (it
    /// stops at the planned end).
    public func isInBreak(at date: Date) -> Bool {
        breakEnd(at: date) != nil
    }

    /// Seconds of the running break left at `date`; nil when no break is running.
    public func breakSecondsLeft(at date: Date) -> TimeInterval? {
        breakEnd(at: date).map { max(0, $0.timeIntervalSince(date)) }
    }
}
