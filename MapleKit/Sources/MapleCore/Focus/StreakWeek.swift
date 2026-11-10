import Foundation

/// The streak sheet (F1 design §5.15, §3.4): the current run, the best run, the rest-day rule, and this week as 7 dots.
/// Finished days are tinted. Rest days, misses and days still to come are all neutral, so the week never counts rest
/// days down. Today is pending until a session finishes.
public struct StreakWeek: Sendable, Equatable {
    public enum Dot: Sendable, Hashable {
        /// A focus day: season tint.
        case finished
        /// A rest day, a miss, or a day still to come.
        case neutral
        /// Today, before a session finishes.
        case pending
    }

    /// "12 days".
    public let title: String
    /// "Best: 21 days", then "2 rest days a week are built in" (§5.15's line; the allowance is F1-13's 2 in any 7 days).
    public let lines: [String]
    /// This week's 7 days, from the calendar's first weekday (P8).
    public let days: [LocalDay]
    public let dots: [Dot]
    /// The week for VoiceOver: "3 finished days this week".
    public let weekLabel: String

    /// - Parameters:
    ///   - focusDays: Days with a finished session (`FocusBook.focusDays`).
    ///   - today: The Maple day now.
    ///   - calendar: The collection's calendar; its `firstWeekday` starts the week.
    ///   - current: The current run (`CollectionStore.currentRun(at:)`).
    ///   - best: The best run (`FocusBook.bestRun`).
    public init(focusDays: [(day: LocalDay, zone: String)], today: LocalDay, calendar: Calendar, current: Int, best: Int) {
        let finished = Set(focusDays.map { $0.day }.filter { $0 <= today })
        let noon = today.startDate(in: calendar).addingTimeInterval(12 * 3600)
        let offset = (calendar.component(.weekday, from: noon) - calendar.firstWeekday + 7) % 7
        let first = today.adding(days: -offset, calendar: calendar)
        let week = (0..<7).map { first.adding(days: $0, calendar: calendar) }
        days = week
        dots = week.map { day in
            if finished.contains(day) { return .finished }
            return day == today ? .pending : .neutral
        }
        title = Self.dayCount(max(0, current))
        lines = [
            "Best: \(Self.dayCount(max(best, current, 0)))",
            "\(FocusRuns.restDays) rest days a week are built in",
        ]
        let count = dots.filter { $0 == .finished }.count
        switch count {
        case 0: weekLabel = "No finished days yet this week"
        case 1: weekLabel = "1 finished day this week"
        default: weekLabel = "\(count) finished days this week"
        }
    }

    private static func dayCount(_ count: Int) -> String {
        count == 1 ? "1 day" : "\(count) days"
    }
}
