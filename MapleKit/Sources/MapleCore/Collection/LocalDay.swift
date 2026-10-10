import Foundation

/// A calendar day in the member's time zone, e.g. 10 Oct 2026. Tended days, counter history and nights are kept
/// per local day. Encodes as "2026-10-10".
public struct LocalDay: Sendable, Hashable, Comparable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The day `date` falls on in `calendar`'s time zone.
    public init(_ date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// Midnight at the start of the day.
    public func startDate(in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }

    public func adding(days: Int, calendar: Calendar) -> LocalDay {
        // Noon avoids daylight-saving edges.
        let noon = calendar.date(byAdding: .hour, value: 12, to: startDate(in: calendar)) ?? startDate(in: calendar)
        return LocalDay(calendar.date(byAdding: .day, value: days, to: noon) ?? noon, calendar: calendar)
    }

    /// Whole days from this day to `other` (negative when `other` is earlier).
    public func days(until other: LocalDay, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: startDate(in: calendar), to: other.startDate(in: calendar)).day ?? 0
    }

    public static func < (lhs: LocalDay, rhs: LocalDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public var description: String {
        let y = String(year).leftPadded(to: 4), m = String(month).leftPadded(to: 2), d = String(day).leftPadded(to: 2)
        return "\(y)-\(m)-\(d)"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected a yyyy-MM-dd day, got \(text)")
        }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

private extension String {
    func leftPadded(to length: Int) -> String {
        count >= length ? self : String(repeating: "0", count: length - count) + self
    }
}
