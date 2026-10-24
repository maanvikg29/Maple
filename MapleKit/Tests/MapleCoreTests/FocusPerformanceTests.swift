import Foundation
import Testing
@testable import MapleCore

/// F1 design §8.1: replaying the open days stays well inside a frame budget, and a full rebuild of years of sessions
/// stays under a second, in the Debug simulator.
@Suite("Focus performance")
struct FocusPerformanceTests {
    /// Two sessions a day (50 and 25 minutes) for `days` days, each in its own day's awake window.
    private func synthetic(days: Int) -> [FocusEvent] {
        let first = at(2023, 10, 23, 9)
        let day = FocusDay(first)
        for index in 0..<days {
            let morning = first.addingTimeInterval(Double(index) * 86_400)
            let label = LocalDay(morning, calendar: utc).description
            let window = AwakeWindow(start: morning.addingTimeInterval(-3 * 3600), end: morning.addingTimeInterval(14 * 3600),
                                     windDown: morning.addingTimeInterval(13 * 3600))
            day.at(morning)
            day.session(minutes: 50, plan: FocusFixtures.plan(day: label, window: window))
            day.at(morning.addingTimeInterval(4 * 3600))
            day.session(minutes: 25, plan: FocusFixtures.plan(minutes: 25, day: label, window: window))
        }
        return day.events
    }

    private func rebuild(_ events: [FocusEvent]) -> FocusBook {
        var book = FocusBook()
        book.record(HoursCredit.credit(FocusLedger(events).sessions(), crediting: [.live], now: .distantFuture))
        _ = FocusCounters.marks(book: book)
        _ = FocusRuns(focusDays: book.focusDays, today: LocalDay(year: 2026, month: 10, day: 23))
        return book
    }

    @Test("Replaying two months of open days takes under 50 ms")
    func openDays() {
        let events = synthetic(days: 62)
        var book = FocusBook()
        let elapsed = ContinuousClock().measure { book = rebuild(events) }
        #expect(book.days.count == 62)
        #expect(elapsed < .milliseconds(50), "\(elapsed)")
    }

    @Test("Rebuilding 3 years of sessions takes under a second")
    func threeYears() {
        let events = synthetic(days: 3 * 365)
        var book = FocusBook()
        let elapsed = ContinuousClock().measure { book = rebuild(events) }
        #expect(book.days.count == 3 * 365)
        #expect(book.totalFinished == 2 * 3 * 365)
        #expect(elapsed < .seconds(1), "\(elapsed)")
    }
}
