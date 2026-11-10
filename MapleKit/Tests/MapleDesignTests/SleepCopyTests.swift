import Foundation
import MapleCore
import Testing
@testable import MapleDesign

/// The sleep schedule's words (Settings › Sleep schedule, the editor) and wind-down mode's (spec §8.1). They were
/// tested with the Rest tab's dial, which F1 retires (F1 design §1.1).
@Suite("Sleep copy")
struct SleepCopyTests {
    private let h24 = Locale(identifier: "en_GB")
    private let h12 = Locale(identifier: "en_US")
    private let late = SleepSchedule(bedtime: ClockTime(hour: 0, minute: 30), wake: ClockTime(hour: 8, minute: 30), windDownMinutes: 60)

    @Test("Settings' row reads the night as a span, and VoiceOver hears it in words")
    func settingsRow() {
        #expect(RestCopy.span(.standard, locale: h24) == "23:00 → 07:00")
        #expect(RestCopy.span(.standard, locale: h12) == "11:00 PM → 7:00 AM")
        #expect(RestCopy.spokenSchedule(.standard, locale: h24) == "Bed at 23:00, wake-up at 07:00")
        #expect(RestCopy.spokenSchedule(late, locale: h12) == "Bed at 12:30 AM, wake-up at 8:30 AM")
    }

    @Test("Time in bed and the wind-down choices read like Home's durations")
    func inBed() {
        #expect(RestCopy.inBed(.standard) == "8h in bed")
        let short = SleepSchedule(bedtime: ClockTime(hour: 23, minute: 30), wake: ClockTime(hour: 7), windDownMinutes: 30)
        #expect(RestCopy.inBed(short) == "7h 30m in bed")
        #expect(RestCopy.windDownOption(minutes: 30) == "30m")
        #expect(RestCopy.windDownOption(minutes: 60) == "1h")
        #expect(RestCopy.editorSummary(late, locale: h24) == "Wind-down from 23:30 · 8h in bed")
    }

    @Test("The bedside line counts down to bed, then names the wake-up once the night starts")
    func bedsideLine() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        func at(_ hour: Int, _ minute: Int) throws -> Date {
            try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: hour, minute: minute)))
        }
        let windDown = RestCopy.bedsideLine(at: try at(22, 22), schedule: .standard, calendar: calendar, locale: h24)
        #expect(windDown.text == "38m until bed")
        #expect(windDown.spoken == "38 minutes until bed.")
        let evening = RestCopy.bedsideLine(at: try at(20, 55), schedule: .standard, calendar: calendar, locale: h24)
        #expect(evening.text == "2h 5m until bed")
        let night = RestCopy.bedsideLine(at: try at(1, 30), schedule: .standard, calendar: calendar, locale: h24)
        #expect(night.text == "Wake-up at 07:00")
        // After midnight, before a 00:30 bedtime, it still counts down.
        let beforeLateBed = RestCopy.bedsideLine(at: try at(0, 10), schedule: .everyNight(late), calendar: calendar, locale: h24)
        #expect(beforeLateBed.text == "20m until bed")
        #expect(RestCopy.phoneDown(at: ClockTime(hour: 23, minute: 4), locale: h12) == "Phone down at 11:04 PM")
    }
}
