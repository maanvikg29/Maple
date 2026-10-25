import Foundation

/// Why time didn't count, in the receipt's and Saved today's words (F1 design §3.3 step 10, §5.9; focus spec §3.3, with
/// "Couldn't confirm the block" in place of "Protection was off").
public enum CreditWords {
    public static func reason(_ rule: CreditRule) -> String {
        switch rule {
        case .override: "Unlocked"
        case .unconfirmed: "Couldn't confirm the block"
        case .afterBedtime: "After bedtime"
        case .beforeMorning: "After bedtime"
        case .dailyCap: "Over today's \(HoursCredit.dailyCap / 3600)h"
        case .overlap: "Counted in another session"
        case .plainTimer: "Plain timer"
        case .notQualifying: "Selection didn't count"
        }
    }

    /// One greyed line in Saved today: an unlock says how long ("Unlocked 5 min"); other reasons stand alone.
    public static func line(_ rule: CreditRule, seconds: Int) -> String {
        guard rule == .override else { return reason(rule) }
        return "Unlocked \(max(1, Int((Double(seconds) / 60).rounded()))) min"
    }
}
