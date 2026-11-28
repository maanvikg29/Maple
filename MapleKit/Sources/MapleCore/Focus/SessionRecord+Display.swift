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

    /// When the session's focus stopped (F2 Study record): its end, never past the planned end; for a session whose end
    /// was never written, its last confirmed moment (the countdown's start when there is none).
    public var focusEnd: Date {
        max(countdownStart, min(end?.placed ?? lastCheckpoint ?? countdownStart, plannedEnd))
    }

    /// The session's breaks as they ran: each from its start to "Back to studying", its planned end or the session's
    /// focus end, whichever came first.
    public var breakIntervals: [DateInterval] {
        let limit = focusEnd
        return breaks.compactMap { taken in
            let from = max(taken.start, countdownStart), to = min(taken.end ?? taken.plannedEnd, taken.plannedEnd, limit)
            return to > from ? DateInterval(start: from, end: to) : nil
        }
    }

    /// Seconds focused (History's measure): from the countdown's start to the focus end, without the breaks. Unlocks
    /// reduce time saved, never time focused.
    public var focusedSeconds: Int {
        let whole = focusEnd.timeIntervalSince(countdownStart)
        return max(0, Int((whole - breakIntervals.reduce(0) { $0 + $1.duration }).rounded()))
    }
}
