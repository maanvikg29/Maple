import Foundation

/// Why time didn't count, in the receipt's and Saved today's words (F1 design §3.3 step 10, §5.9; focus spec §3.3, with
/// "Couldn't confirm the block" in place of "Protection was off"). `earlierDay`: the day shown is an earlier Maple day
/// than the one being lived in, so its cap is "that day's" (F1-31).
public enum CreditWords {
    public static func reason(_ rule: CreditRule, earlierDay: Bool = false) -> String {
        switch rule {
        case .override: "Unlocked"
        case .unconfirmed: "Couldn't confirm the block"
        case .afterBedtime: "After bedtime"
        case .beforeMorning: "After bedtime"
        case .dailyCap: "Over \(capDay(earlierDay)) \(HoursCredit.dailyCap / 3600)h"
        case .overlap: "Counted in another session"
        case .plainTimer: "Plain timer"
        case .notQualifying: "Selection didn't count"
        }
    }

    /// One greyed line in Saved today: an unlock says how long ("Unlocked 5 min"); other reasons stand alone.
    public static func line(_ rule: CreditRule, seconds: Int, earlierDay: Bool = false) -> String {
        guard rule == .override else { return reason(rule, earlierDay: earlierDay) }
        return "Unlocked \(max(1, Int((Double(seconds) / 60).rounded()))) min"
    }

    /// `line(_:seconds:)` for VoiceOver: lengths in words, so it never reads a bare "min" or "h" ("Unlocked 5 minutes",
    /// "Over today's 6 hours").
    public static func spokenLine(_ rule: CreditRule, seconds: Int, earlierDay: Bool = false, locale: Locale) -> String {
        switch rule {
        case .override:
            let minutes = max(1, Int((Double(seconds) / 60).rounded()))
            return "Unlocked \(FocusTimeText.spokenLength(minutes: minutes, locale: locale))"
        case .dailyCap:
            return "Over \(capDay(earlierDay)) \(FocusTimeText.spokenLength(minutes: HoursCredit.dailyCap / 60, locale: locale))"
        default:
            return reason(rule, earlierDay: earlierDay)
        }
    }

    /// Whose cap it was: "today's", or "that day's" for an earlier Maple day.
    static func capDay(_ earlierDay: Bool) -> String {
        earlierDay ? "that day's" : "today's"
    }
}
