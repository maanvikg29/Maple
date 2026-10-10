import Foundation

/// A piece of a hero numeral: digits, or a unit drawn smaller and secondary ("1h 20m" is 1, h, 20, m).
/// Map it onto `StatNumber.Part` in the view: `.value(text)` or `.unit(text)`.
public struct NumeralPart: Sendable, Hashable {
    public let text: String
    public let isUnit: Bool

    public init(text: String, isUnit: Bool) {
        self.text = text
        self.isUnit = isUnit
    }

    public static func value(_ text: String) -> NumeralPart { NumeralPart(text: text, isUnit: false) }
    public static func unit(_ text: String) -> NumeralPart { NumeralPart(text: text, isUnit: true) }
}

/// Home's number and time formatting (spec §3.6): durations as "7h 12m" or "38m", clock times in the locale's
/// 12- or 24-hour style ("23:00", "11:00 PM").
public enum HomeFormat {
    /// Whether `locale` (including the member's 24-hour setting, for `.current`) uses a 12-hour clock.
    public static func uses12HourClock(_ locale: Locale) -> Bool {
        switch locale.hourCycle {
        case .oneToTwelve, .zeroToEleven: true
        case .zeroToTwentyThree, .oneToTwentyFour: false
        @unknown default: false
        }
    }

    /// The clock time of `date` in `calendar`'s time zone.
    public static func clockTime(of date: Date, calendar: Calendar) -> ClockTime {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return ClockTime(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }

    /// "23:00" or "11:00 PM".
    public static func clock(_ time: ClockTime, locale: Locale) -> String {
        clockParts(time, locale: locale).map(\.text).joined()
    }

    /// "07:00" as one value, or "7:00" with " AM" as a unit.
    public static func clockParts(_ time: ClockTime, locale: Locale) -> [NumeralPart] {
        let minute = time.minute < 10 ? "0\(time.minute)" : "\(time.minute)"
        guard uses12HourClock(locale) else {
            let hour = time.hour < 10 ? "0\(time.hour)" : "\(time.hour)"
            return [.value("\(hour):\(minute)")]
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let hour = time.hour % 12 == 0 ? 12 : time.hour % 12
        let period = time.hour < 12 ? calendar.amSymbol : calendar.pmSymbol
        return [.value("\(hour):\(minute)"), .unit(" \(period)")]
    }

    /// "1h 20m", "2h", "38m", "0m".
    public static func duration(minutes: Int) -> String {
        let parts = durationParts(minutes: minutes)
        var text = ""
        for (index, part) in parts.enumerated() {
            if index > 0, !part.isUnit, parts[index - 1].isUnit { text += " " }
            text += part.text
        }
        return text
    }

    public static func durationParts(minutes: Int) -> [NumeralPart] {
        let total = max(0, minutes)
        let hours = total / 60, rest = total % 60
        if hours == 0 { return [.value("\(rest)"), .unit("m")] }
        if rest == 0 { return [.value("\(hours)"), .unit("h")] }
        return [.value("\(hours)"), .unit("h"), .value("\(rest)"), .unit("m")]
    }

    /// "1 hour, 20 minutes", for VoiceOver.
    public static func spokenDuration(minutes: Int, locale: Locale) -> String {
        let total = max(0, minutes)
        guard total > 0 else {
            return Duration.seconds(0).formatted(.units(allowed: [.minutes], width: .wide, zeroValueUnits: .show(length: 1)).locale(locale))
        }
        return Duration.seconds(total * 60).formatted(.units(allowed: [.hours, .minutes], width: .wide).locale(locale))
    }

    /// Whole minutes from `start` to `end`, rounded up, so a countdown never reads 0m inside its window.
    public static func minutesUntil(_ end: Date, from start: Date) -> Int {
        max(0, Int((end.timeIntervalSince(start) / 60).rounded(.up)))
    }
}
