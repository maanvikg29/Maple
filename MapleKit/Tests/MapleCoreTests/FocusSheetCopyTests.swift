import Foundation
import Testing
@testable import MapleCore

@Suite("Focus sheet copy")
struct FocusSheetCopyTests {
    @Test("Saved today's heading and hint; its lines are Task 5's")
    func savedToday() {
        #expect(FocusSheetCopy.savedTodayHint == "Opens Saved today")
        #expect(FocusSheetCopy.howWeCountTitle == "How we count")
    }

    @Test("The week starts on the calendar's first weekday (P8)")
    func weekdayInitials() {
        var monday = utc
        monday.firstWeekday = 2
        #expect(FocusSheetCopy.weekdayInitials(calendar: monday) == ["M", "T", "W", "T", "F", "S", "S"])
        var sunday = utc
        sunday.locale = enUS
        sunday.firstWeekday = 1
        #expect(FocusSheetCopy.weekdayInitials(calendar: sunday) == ["S", "M", "T", "W", "T", "F", "S"])
        var saturday = utc
        saturday.firstWeekday = 7
        #expect(FocusSheetCopy.weekdayInitials(calendar: saturday).first == "S")
        #expect(FocusSheetCopy.weekdayInitials(calendar: saturday).count == 7)
    }

    @Test("The editor, Blocking sheet and intention words, in the spec's own where it has them")
    func sheetWords() {
        #expect(FocusSheetCopy.modeTitle(.blockThese) == "Block these")
        #expect(FocusSheetCopy.modeTitle(.onlyThese) == "Only these")
        #expect(FocusSheetCopy.footer == "Calls and apps on iOS's Always Allowed list stay open.")
        #expect(FocusSheetCopy.editPresetTitle == "Edit preset")
        // Task 4's words, reused rather than copied.
        #expect(SelectionText.needsChoosingAgain == "Some apps need choosing again")
        #expect(SelectionText.limitNote == "Up to \(SelectionSummary.tokenLimit) apps can rest at once")
        #expect(FocusSheetCopy.overLimit == "\(SelectionText.limitNote). Choose a category to cover more.")
        #expect(FocusSheetCopy.pickerUnavailable == "This version of Maple can't lock apps.")
        #expect(FocusSheetCopy.breakOption(false) == "No break")
        #expect(FocusSheetCopy.breakOption(true) == "One 5-minute break")
    }

    @Test("Every fixed line is sentence case, with no exclamation and none of the words Maple never uses")
    func voice() {
        let lines: [String] = [
            FocusSheetCopy.savedTodayHint, FocusSheetCopy.howWeCountTitle, FocusSheetCopy.save, FocusSheetCopy.close,
            FocusSheetCopy.cancel, FocusSheetCopy.editPresetTitle, FocusSheetCopy.editPreset, FocusSheetCopy.nameTitle,
            FocusSheetCopy.verbTitle, FocusSheetCopy.lengthTitle, FocusSheetCopy.shorter, FocusSheetCopy.longer,
            FocusSheetCopy.breakTitle, FocusSheetCopy.breakNote, FocusSheetCopy.appsTitle, FocusSheetCopy.strictnessTitle,
            FocusSheetCopy.deletePreset, FocusSheetCopy.deleteQuestion, FocusSheetCopy.deleteNote,
            FocusSheetCopy.couldNotSave, FocusSheetCopy.listsLabel, FocusSheetCopy.modeLabel,
            FocusSheetCopy.keepOneChosen, FocusSheetCopy.overLimit,
            FocusSheetCopy.onlyTheseNote, FocusSheetCopy.footer, FocusSheetCopy.pickerUnavailable,
            FocusSheetCopy.clearIntention,
        ] + [false, true].map(FocusSheetCopy.breakOption)
            + [SelectionSummary.Mode.blockThese, .onlyThese].map(FocusSheetCopy.modeTitle)
        for line in lines {
            #expect(line.first?.isUppercase == true, "\(line)")
            #expect(!line.contains("!"), "\(line)")
            let lower = line.lowercased()
            for word in ["fail", "quit", "streak lost", "rest days left", "missed", "demo"] {
                #expect(!lower.contains(word), "\(line)")
            }
        }
    }
}
