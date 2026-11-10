import Foundation

/// The focus counters at one instant: what they were once a session's credit was proven (F1 design §7.2).
public struct FocusMark: Sendable, Equatable {
    public var instant: Date
    public var hours: Double
    public var sessions: Int

    public init(instant: Date, hours: Double, sessions: Int) {
        self.instant = instant
        self.hours = hours
        self.sessions = sessions
    }
}

/// Turns the book into dated marks, so each leaf is unlocked at the moment its credit was proven: unlock dates,
/// tended days and the reveal hold all follow that moment (F1-12).
public enum FocusCounters {
    /// One mark per session still held by an open day, in the order its credit was proven. Each carries the running
    /// totals: the baseline and frozen days, plus each open day's sessions so far within the daily caps.
    public static func marks(book: FocusBook) -> [FocusMark] {
        var fixedSeconds = book.baseline.seconds
        var fixedFinished = book.baseline.finished
        var tallies: [(day: String, tally: SessionTally)] = []
        for day in book.days {
            if day.frozen || day.sessions.isEmpty {
                fixedSeconds += day.seconds
                fixedFinished += day.finished
            } else {
                tallies += day.sessions.values.map { (day.id, $0) }
            }
        }
        tallies.sort { ($0.tally.provenAt, $0.day) < ($1.tally.provenAt, $1.day) }

        var seconds: [String: Int] = [:]
        var finished: [String: Int] = [:]
        return tallies.map { entry in
            seconds[entry.day, default: 0] += entry.tally.seconds
            if entry.tally.finished { finished[entry.day, default: 0] += 1 }
            let totalSeconds = fixedSeconds + seconds.values.reduce(0) { $0 + min(HoursCredit.dailyCap, $1) }
            let totalFinished = fixedFinished + finished.values.reduce(0) { $0 + min(HoursCredit.finishedPerDay, $1) }
            return FocusMark(instant: entry.tally.provenAt, hours: Double(totalSeconds) / 3600, sessions: totalFinished)
        }
    }
}
