import Foundation
import Testing
@testable import MapleCore

@Suite("Season")
struct SeasonTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(month: Int, day: Int = 15) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
    }

    @Test("Northern hemisphere uses meteorological seasons", arguments: [
        (1, Season.winter), (2, .winter), (3, .spring), (4, .spring), (5, .spring),
        (6, .summer), (7, .summer), (8, .summer), (9, .autumn), (10, .autumn),
        (11, .autumn), (12, .winter),
    ])
    func northern(month: Int, expected: Season) {
        #expect(Season(for: date(month: month), hemisphere: .northern, calendar: calendar) == expected)
    }

    @Test("Southern hemisphere is offset by half a year", arguments: [
        (1, Season.summer), (4, .autumn), (7, .winter), (10, .spring), (12, .summer),
    ])
    func southern(month: Int, expected: Season) {
        #expect(Season(for: date(month: month), hemisphere: .southern, calendar: calendar) == expected)
    }

    @Test("Season boundaries fall on the first of the month")
    func boundaries() {
        #expect(Season(for: date(month: 2, day: 28), hemisphere: .northern, calendar: calendar) == .winter)
        #expect(Season(for: date(month: 3, day: 1), hemisphere: .northern, calendar: calendar) == .spring)
        #expect(Season(for: date(month: 11, day: 30), hemisphere: .northern, calendar: calendar) == .autumn)
        #expect(Season(for: date(month: 12, day: 1), hemisphere: .northern, calendar: calendar) == .winter)
    }
}

@Suite("Hemisphere")
struct HemisphereTests {
    @Test("Southern-hemisphere regions are detected", arguments: ["AU", "NZ", "AR", "CL", "ZA", "BR", "UY"])
    func southernRegions(code: String) {
        #expect(Hemisphere(regionCode: code) == .southern)
    }

    @Test("Other regions default to northern", arguments: ["US", "GB", "IN", "JP", "CA", "DE"])
    func northernRegions(code: String) {
        #expect(Hemisphere(regionCode: code) == .northern)
    }

    @Test("Missing or lowercase region codes are handled")
    func edgeCases() {
        #expect(Hemisphere(regionCode: nil) == .northern)
        #expect(Hemisphere(regionCode: "au") == .southern)
    }
}
