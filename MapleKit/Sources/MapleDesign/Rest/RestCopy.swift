import Foundation
import MapleCore

/// The words and numbers on Rest › Sleep and in wind-down mode (spec §8.1), kept pure so they can be tested.
/// Durations follow Home's style ("8h", "7h 30m", "38m"); clock times follow the locale ("23:00" or "11:00 PM").
nonisolated public enum RestCopy {
    // MARK: Schedule

    /// "8h in bed", "7h 30m in bed".
    public static func inBed(_ schedule: SleepSchedule) -> String {
        "\(HomeFormat.duration(minutes: schedule.minutesInBed)) in bed"
    }

    /// "8 hours in bed", for VoiceOver.
    public static func spokenInBed(_ schedule: SleepSchedule, locale: Locale) -> String {
        "\(HomeFormat.spokenDuration(minutes: schedule.minutesInBed, locale: locale)) in bed"
    }

    /// "Bed at 23:00, wake-up at 07:00".
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

    // MARK: Dial

    /// A quarter-hour label on the dial: "00", "06", "12", "18", or "12 AM", "6 AM", "12 PM", "6 PM".
    public static func dialLabel(hour: Int, locale: Locale) -> String {
        let hour = ((hour % 24) + 24) % 24
        guard HomeFormat.uses12HourClock(locale) else {
            return hour < 10 ? "0\(hour)" : "\(hour)"
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        return "\(twelve) \(hour < 12 ? calendar.amSymbol : calendar.pmSymbol)"
    }

    /// The dial's VoiceOver value: "Wind-down from 22:15. Bed at 23:00, wake-up at 07:00. 8 hours in bed. Now 21:40."
    public static func dialDescription(_ schedule: SleepSchedule, now: ClockTime?, locale: Locale) -> String {
        var sentences: [String] = []
        if schedule.windDownMinutes > 0 {
            sentences.append("Wind-down from \(HomeFormat.clock(schedule.windDownStart, locale: locale))")
        }
        sentences.append(spokenSchedule(schedule, locale: locale))
        sentences.append(spokenInBed(schedule, locale: locale))
        if let now {
            sentences.append("Now \(HomeFormat.clock(now, locale: locale))")
        }
        return sentences.joined(separator: ". ") + "."
    }

    // MARK: Wind-down mode

    /// The line under the bedside clock, and its spoken form: "38m until bed" before bedtime, "Wake-up at 07:00"
    /// once the night has started.
    public static func bedsideLine(
        at date: Date, schedule: SleepSchedule, calendar: Calendar, locale: Locale
    ) -> (text: String, spoken: String) {
        let windows = PhaseWindows(schedule: schedule)
        if NowPhase.resolve(date: date, schedule: schedule, calendar: calendar) == .night {
            let wake = HomeFormat.clock(schedule.wake, locale: locale)
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
