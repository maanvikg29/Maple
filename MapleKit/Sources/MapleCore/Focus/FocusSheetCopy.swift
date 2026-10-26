import Foundation
import MapleFocusCore

/// The words on the Focus sheets that no screen model owns (F1 design §5.9, §5.13–§5.16): Saved today and the streak
/// sheet here (their other lines are `SavedTodayModel`'s and `StreakWeek`'s); the preset editor, the Blocking sheet
/// and intention entry with Task 15. Pure, so every line is tested. Sentence case, no "!", and never "fail", "quit",
/// "streak lost" or "rest days left".
public enum FocusSheetCopy {
    // MARK: Saved today (§5.9, focus spec §3.3)

    /// VoiceOver's hint on a numeral that opens Saved today (Home's, the receipt's).
    public static let savedTodayHint = "Opens Saved today"
    /// The heading over `SavedTodayModel.howWeCount`.
    public static let howWeCountTitle = "How we count"

    // MARK: Streak sheet (§5.15)

    /// The weekday under each of the week's 7 dots, from the calendar's first weekday (ruling P8): "M T W T F S S"
    /// in en-GB, "S M T W T F S" in en-US. `StreakWeek.days` starts on the same weekday.
    public static func weekdayInitials(calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        guard symbols.count == 7 else { return Array(repeating: "", count: 7) }
        let first = min(max(calendar.firstWeekday, 1), 7) - 1
        return (0..<7).map { symbols[(first + $0) % 7] }
    }
}
