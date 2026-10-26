import Foundation
import MapleFocusCore

/// The words on the Focus sheets that no screen model owns (F1 design §5.9, §5.13–§5.16, focus spec §3.3): Saved
/// today and the streak sheet (their other lines are `SavedTodayModel`'s and `StreakWeek`'s), the preset editor, the
/// Blocking sheet and intention entry. Pure, so every line is tested. Sentence case, no "!", and never "fail", "quit",
/// "streak lost" or "rest days left".
public enum FocusSheetCopy {
    // MARK: Shared

    public static let save = "Save"
    public static let close = "Close"
    public static let cancel = "Cancel"

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

    // MARK: Preset editor (§5.13)

    public static let editPresetTitle = "Edit preset"
    /// VoiceOver's action on a preset chip, the same as holding it.
    public static let editPreset = "Edit preset"
    public static let nameTitle = "Name"
    /// The verb row; its choices are the start button's own words ("Start a quick session").
    public static let verbTitle = "Start button"
    public static let lengthTitle = "Length"
    public static let shorter = "Shorter"
    public static let longer = "Longer"
    public static let breakTitle = "Break"
    public static let breakNote = "Apps stay locked, and the break counts."
    public static let appsTitle = "Apps"
    public static let strictnessTitle = "Strictness"
    public static let deletePreset = "Delete preset"
    public static let deleteQuestion = "Delete this preset?"
    public static let deleteNote = "The time it saved stays yours."
    public static let couldNotSave = "This couldn't be saved. Try again in a moment."

    /// None, or one 5-minute locked break inside the session (§5.5).
    public static func breakOption(_ hasBreak: Bool) -> String {
        hasBreak ? "One 5-minute break" : "No break"
    }

    // MARK: Blocking sheet (§5.14)

    /// VoiceOver's label for the named lists.
    public static let listsLabel = "App list"
    /// VoiceOver's label for Block these · Only these.
    public static let modeLabel = "Which apps rest"
    public static let keepOneChosen = "Choose at least one app, site or category. This list stays as it was."
    /// Over the limit, Save is off: the counter's own limit note, and what to do.
    public static let overLimit = "\(SelectionText.limitNote). Choose a category to cover more."
    public static let onlyTheseNote = "Only these counts with 20 or fewer apps and sites, and no categories."
    public static let footer = "Calls and apps on iOS's Always Allowed list stay open."
    /// Where the app picker goes in a build that can't block (F1-17's words).
    public static let pickerUnavailable = "This version of Maple can't lock apps."

    public static func modeTitle(_ mode: SelectionSummary.Mode) -> String {
        switch mode {
        case .blockThese: "Block these"
        case .onlyThese: "Only these"
        }
    }

    // MARK: Intention entry (§5.16)

    /// VoiceOver's label for the field's clear button.
    public static let clearIntention = "Clear"
}
