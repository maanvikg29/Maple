import Foundation
import MapleFocusCore

extension CollectionSnapshot {
    /// The Maple day and frozen awake window for a session starting at `start` (F1 design §3.3 step 6). Each night is
    /// judged by the schedule in force at 18:00 that evening, so a bedtime edit after 18:00 applies from the next night.
    public func focusWindow(at start: Date, context: CollectionContext) -> (day: LocalDay, window: AwakeWindow) {
        AwakeWindow.frozen(at: start, schedule: { nights.schedule(for: $0, current: context.schedule) }, calendar: context.calendar)
    }

    /// The Maple day the member is still living in at `date`: `focusWindow`'s day, or the day before it until that day's
    /// window opens (wake − 60). A session starting after bedtime belongs to the next day, but the member's evening
    /// isn't over until then, so a receipt says "that day" only from that moment (F1-31).
    public func livingDay(at date: Date, context: CollectionContext) -> LocalDay {
        let frozen = focusWindow(at: date, context: context)
        return date < frozen.window.start ? frozen.day.adding(days: -1, calendar: context.calendar) : frozen.day
    }
}

extension CollectionSnapshot {
    /// Records replayed sessions' credit in the book and raises the focus counters to its totals (F1 design §3.5,
    /// §7.2). Each session's credit is applied at the moment it was proven, so leaves are dated then; then the final
    /// totals and the best run are raised at `now`. Counters never fall. Applying the same credit again changes
    /// nothing. Ignored before the maple is planted.
    ///
    /// When the book has no start (a first run, or an older build dropped it) it takes as its baseline whatever the
    /// counters hold beyond what this replay recounts.
    /// - Returns: Leaves unlocked, each dated by the credit that earned it.
    @discardableResult
    public mutating func applyFocus(
        _ credits: [SessionCredit], at now: Date, context: CollectionContext, engine: LeafEngine = LeafEngine()
    ) -> [LeafUnlock] {
        guard hasPlantedMaple else { return [] }
        let calendar = context.calendar
        var book = focus
        book.record(credits)
        if book.startedAt == nil {
            let recounted = FocusBook(days: book.days)
            book.baseline = FocusTotals(
                seconds: max(0, Int(((counters[.hoursSaved] ?? 0) * 3600).rounded()) - recounted.totalSeconds),
                finished: max(0, Int(counters[.sessionsFinished] ?? 0) - recounted.totalFinished)
            )
            book.bestRun = max(book.bestRun, Int(counters[.focusStreak] ?? 0))
            book.startedAt = now
        }
        // The marks are taken before the freeze, which empties a day's sessions: a day first seen after its freeze
        // moment (the app closed at its end and opened days later) still dates its leaves when its credit was proven.
        let marks = FocusCounters.marks(book: book)
        book.freeze(at: now)
        book.bestRun = max(book.bestRun, FocusRuns(focusDays: book.focusDays, today: focusWindow(at: now, context: context).day).best)
        focus = book

        var added: [LeafUnlock] = []
        for mark in marks where mark.instant <= now {
            raise(.hoursSaved, to: mark.hours, at: mark.instant, calendar: calendar)
            raise(.sessionsFinished, to: Double(mark.sessions), at: mark.instant, calendar: calendar)
            added += runEngine(at: mark.instant, context: context, engine: engine)
        }
        raise(.hoursSaved, to: Double(book.totalSeconds) / 3600, at: now, calendar: calendar)
        raise(.sessionsFinished, to: Double(book.totalFinished), at: now, calendar: calendar)
        raise(.focusStreak, to: Double(book.bestRun), at: now, calendar: calendar)
        added += runEngine(at: now, context: context, engine: engine)
        return added
    }

    /// The current Focus streak run at `date` (§3.4): today is the Maple day whose awake window holds `date`, or the
    /// next one in a sleep window, and stays pending.
    public func currentRun(at date: Date, context: CollectionContext) -> Int {
        FocusRuns(focusDays: focus.focusDays, today: focusWindow(at: date, context: context).day).current
    }
}
