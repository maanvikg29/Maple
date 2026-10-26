import Foundation
import Testing
@testable import MapleCore

@Suite("Focus settings copy")
struct FocusSettingsCopyTests {
    private func window() throws -> StudyReminderWindow {
        try #require(StudyReminderWindow(weekly: .standard, around: at(2026, 10, 12, 9), calendar: utc))
    }

    @Test("Settings' Focus rows, word for word, in the member's clock style")
    func rows() throws {
        let window = try window()
        #expect(FocusSettingsCopy.sessionEndTitle == "Session end")
        #expect(FocusSettingsCopy.sessionEndDetail == "When a session ends, with its length.")
        #expect(FocusSettingsCopy.studyTitle == "Daily study reminder")
        #expect(FocusSettingsCopy.studyOff == "Once a day, at a time you choose.")
        #expect(FocusSettingsCopy.studyOn(ClockTime(hour: 16), locale: enGB) == "At 16:00, unless a session has already started that day.")
        #expect(FocusSettingsCopy.studyOn(ClockTime(hour: 16), locale: enUS) == "At 4:00 PM, unless a session has already started that day.")
        #expect(FocusSettingsCopy.studyOutsideDay(ClockTime(hour: 21), window: window, locale: enGB)
            == "21:00 is outside your day now. Choose a time from 10:00 to 20:14.")
        #expect(FocusSettingsCopy.studyNoDaytime == "Your sleep schedule leaves no daytime for it.")
        #expect(FocusSettingsCopy.studyChangeTime == "Change time")
        #expect(FocusSettingsCopy.studyRange(window, locale: enGB) == "Any time from 10:00 to 20:14.")
        #expect(FocusSettingsCopy.studyRange(window, locale: enUS) == "Any time from 10:00 AM to 8:14 PM.")
        #expect(FocusSettingsCopy.save == "Save")
        #expect(FocusSettingsCopy.close == "Close")
        #expect(FocusSettingsCopy.releaseAllDetail == "If an app stays locked after a session ends, this opens it.")
        #expect(FocusSettingsCopy.releaseAllDone == "Every app is open again.")
    }

    @Test("The study row's line never contradicts its switch: a saved time shows only while notifications are allowed")
    func studyDetail() throws {
        let window = try window()
        let four = ClockTime(hour: 16)
        #expect(FocusSettingsCopy.studyDetail(four, window: window, isAllowed: true, locale: enGB)
            == "At 16:00, unless a session has already started that day.")
        #expect(FocusSettingsCopy.studyDetail(ClockTime(hour: 21), window: window, isAllowed: true, locale: enGB)
            == "21:00 is outside your day now. Choose a time from 10:00 to 20:14.")
        #expect(FocusSettingsCopy.studyDetail(nil, window: window, isAllowed: true, locale: enGB) == "Once a day, at a time you choose.")
        // Not asked yet, or turned off in iOS: the switch rests off, and so does the line.
        #expect(FocusSettingsCopy.studyDetail(four, window: window, isAllowed: false, locale: enGB) == "Once a day, at a time you choose.")
        #expect(FocusSettingsCopy.studyDetail(ClockTime(hour: 21), window: window, isAllowed: false, locale: enGB)
            == "Once a day, at a time you choose.")
        // No daytime at all says why the switch can't turn on.
        #expect(FocusSettingsCopy.studyDetail(nil, window: nil, isAllowed: true, locale: enGB) == "Your sleep schedule leaves no daytime for it.")
        #expect(FocusSettingsCopy.studyDetail(four, window: nil, isAllowed: false, locale: enGB) == "Your sleep schedule leaves no daytime for it.")
    }

    @Test("Calm: sentence case, no exclamation marks, nothing about leaves, streaks or missed days")
    func calm() throws {
        let window = try window()
        let lines = [
            FocusSettingsCopy.sessionEndTitle, FocusSettingsCopy.sessionEndDetail, FocusSettingsCopy.studyTitle,
            FocusSettingsCopy.studyOff, FocusSettingsCopy.studyOn(ClockTime(hour: 16), locale: enGB),
            FocusSettingsCopy.studyOutsideDay(ClockTime(hour: 21), window: window, locale: enGB),
            FocusSettingsCopy.studyNoDaytime, FocusSettingsCopy.studyChangeTime, FocusSettingsCopy.studyRange(window, locale: enGB),
            FocusSettingsCopy.save, FocusSettingsCopy.close, FocusSettingsCopy.releaseAllDetail, FocusSettingsCopy.releaseAllDone,
        ]
        for line in lines {
            #expect(!line.contains("!"))
            #expect(line.first?.isUppercase == true || line.first?.isNumber == true)
            for word in ["leaf", "streak", "missed", "fail", "quit"] {
                #expect(!line.lowercased().contains(word))
            }
        }
    }
}
