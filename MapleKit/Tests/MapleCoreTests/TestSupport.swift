import Foundation
@testable import MapleCore

/// A fixed Gregorian calendar in UTC, so tests never depend on the machine's time zone.
let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.locale = Locale(identifier: "en_GB")
    return calendar
}()

/// 24-hour English, as in the spec's wireframes.
let enGB = Locale(identifier: "en_GB")
/// 12-hour English.
let enUS = Locale(identifier: "en_US")

/// A date in `calendar` (UTC by default).
func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0, in calendar: Calendar = utc) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
}

/// A hand-built progress row for picker tests.
func progressRow(
    _ id: String, _ category: RewardCategoryID, threshold: Double, current: Double = 0,
    availability: LeafAvailability = .available, state: LeafState = .locked, estimate: Double?
) -> LeafProgress {
    LeafProgress(speciesID: id, category: category, threshold: threshold, tier: .common, current: current,
                 availability: availability, state: state, estimatedDays: estimate)
}

/// The words in a line of copy, not counting the "·" separator.
func wordCount(_ line: String) -> Int {
    line.split(separator: " ").filter { $0 != "·" }.count
}

/// The species a rung awards, for readable expectations.
func species(_ category: RewardCategoryID, rung index: Int) -> String {
    RewardCatalog.shared.rungs(in: category)[index].speciesID
}
