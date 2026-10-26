import Foundation
import Testing
@testable import MapleCore

@Suite("Focus sheet copy")
struct FocusSheetCopyTests {
    @Test("Saved today's heading and hint; its lines are Task 5's")
    func savedToday() {
        #expect(FocusSheetCopy.savedTodayHint == "Opens Saved today")
        #expect(FocusSheetCopy.howWeCountTitle == "How we count")
    }

    @Test("The week starts on the calendar's first weekday (P8)")
    func weekdayInitials() {
        var monday = utc
        monday.firstWeekday = 2
        #expect(FocusSheetCopy.weekdayInitials(calendar: monday) == ["M", "T", "W", "T", "F", "S", "S"])
        var sunday = utc
        sunday.locale = enUS
        sunday.firstWeekday = 1
        #expect(FocusSheetCopy.weekdayInitials(calendar: sunday) == ["S", "M", "T", "W", "T", "F", "S"])
        var saturday = utc
        saturday.firstWeekday = 7
        #expect(FocusSheetCopy.weekdayInitials(calendar: saturday).first == "S")
        #expect(FocusSheetCopy.weekdayInitials(calendar: saturday).count == 7)
    }
}
