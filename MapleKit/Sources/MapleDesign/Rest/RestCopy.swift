import Foundation
import MapleCore

/// The words and numbers of the sleep schedule (Settings › Sleep schedule, its editor and onboarding) and of
/// wind-down mode (spec §8.1), kept pure so they can be tested. Durations follow Home's style ("8h", "7h 30m",
/// "38m"); clock times follow the locale ("23:00" or "11:00 PM").
nonisolated public enum RestCopy {
    // MARK: Schedule

    /// "8h in bed", "7h 30m in bed".
    public static func inBed(_ schedule: SleepSchedule) -> String {
        "\(HomeFormat.duration(minutes: schedule.minutesInBed)) in bed"
    }

    /// "Bed at 23:00, wake-up at 07:00": Settings' "Sleep schedule" row, for VoiceOver.
    public static func spokenSchedule(_ schedule: SleepSchedule, locale: Locale) -> String {
        "Bed at \(HomeFormat.clock(schedule.bedtime, locale: locale)), wake-up at \(HomeFormat.clock(schedule.wake, locale: locale))"
    }

    /// The editor's summary line: "Wind-down from 22:15 · 8h in bed".
    public static func editorSummary(_ schedule: SleepSchedule, locale: Locale) -> String {
        "Wind-down from \(HomeFormat.clock(schedule.windDownStart, locale: locale)) · \(inBed(schedule))"
    }

    /// The wind-down choice as a segment title: "30m", "45m", "1h".
    public static func windDownOption(minutes: Int) -> String {
        HomeFormat.duration(minutes: minutes)
    }

    // MARK: Weekday and weekend nights

    /// "23:00 → 07:00": Settings' "Sleep schedule" row.
    public static func span(_ schedule: SleepSchedule, locale: Locale) -> String {
        "\(HomeFormat.clock(schedule.bedtime, locale: locale)) → \(HomeFormat.clock(schedule.wake, locale: locale))"
    }

    /// Which nights a variant covers, from the calendar's weekend: "Friday and Saturday nights" and "Sunday to
    /// Thursday nights" where the weekend is Saturday and Sunday.
    public static func nights(_ variant: WeeklySleepSchedule.Variant, calendar: Calendar) -> String {
        let weekend = Set(WeeklySleepSchedule.weekendEvenings(calendar: calendar))
        let evenings = (1...7).filter { weekend.contains($0) == (variant == .weekend) }
        if evenings.count == 7 { return "Every night" }
        return evenings.isEmpty ? "No nights" : "\(days(evenings)) nights"
    }

    /// The mornings weekend nights wake into: "Saturday and Sunday mornings".
    public static func weekendMornings(calendar: Calendar) -> String {
        let mornings = WeeklySleepSchedule.weekendEvenings(calendar: calendar).map { $0 % 7 + 1 }
        return mornings.isEmpty ? "No mornings" : "\(days(mornings)) mornings"
    }

    /// Weekdays (1 is Sunday) as words, in a run that wraps the week where it must: "Friday and Saturday", "Sunday to
    /// Thursday", "Saturday to Wednesday".
    static func days(_ weekdays: [Int]) -> String {
        var english = Calendar(identifier: .gregorian)
        english.locale = Locale(identifier: "en_US_POSIX")
        let names = english.weekdaySymbols
        let set = Set(weekdays)
        guard !set.isEmpty else { return "No" }
        guard set.count < 7 else { return "All" }
        // Start the run after a day that isn't in it, so a run across Saturday and Sunday stays in order.
        let start = (1...7).first { set.contains($0) && !set.contains(($0 + 5) % 7 + 1) } ?? 1
        let ordered = (0..<7).map { (start - 1 + $0) % 7 + 1 }.filter(set.contains)
        let contiguous = ordered.count == set.count
            && zip(ordered, ordered.dropFirst()).allSatisfy { $0 % 7 + 1 == $1 }
        let words = ordered.map { names[$0 - 1] }
        switch words.count {
        case 1: return words[0]
        case 2: return "\(words[0]) and \(words[1])"
        default:
            if contiguous { return "\(words[0]) to \(words[words.count - 1])" }
            return words.dropLast().joined(separator: ", ") + " and " + words[words.count - 1]
        }
    }

    // MARK: Wind-down mode

    /// The line under the bedside clock, and its spoken form: "38m until bed" before tonight's bedtime, "Wake-up at
    /// 07:00" (tonight's wake) once the night has started.
    public static func bedsideLine(
        at date: Date, schedule: WeeklySleepSchedule, calendar: Calendar, locale: Locale
    ) -> (text: String, spoken: String) {
        let windows = PhaseWindows(weekly: schedule)
        let today = windows.day(containing: date, calendar: calendar)
        if today.phase(at: date) == .night {
            let wake = HomeFormat.clock(schedule.schedule(forNight: today.day, calendar: calendar).wake, locale: locale)
            return ("Wake-up at \(wake)", "Wake-up at \(wake).")
        }
        let bedtime = windows.nextStart(of: .night, after: date, calendar: calendar)
        let minutes = HomeFormat.minutesUntil(bedtime, from: date)
        return ("\(HomeFormat.duration(minutes: minutes)) until bed",
                "\(HomeFormat.spokenDuration(minutes: minutes, locale: locale)) until bed.")
    }

    /// After Goodnight: "Phone down at 23:04".
    public static func phoneDown(at time: ClockTime, locale: Locale) -> String {
        "Phone down at \(HomeFormat.clock(time, locale: locale))"
    }
}
