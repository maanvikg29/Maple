import Foundation
import Testing
@testable import MapleCore

@Suite("Preset editor")
struct PresetDraftTests {
    private let today = LocalDay(year: 2026, month: 10, day: 23)
    private var tomorrow: LocalDay { today.adding(days: 1, calendar: utc) }

    private func study(_ strictness: Strictness = .steady) -> FocusPreset {
        FocusPreset(name: "Study", verb: .study, minutes: 50, hasBreak: true, appSetID: nil, strictness: strictness)
    }

    @Test("A tighter level applies now; a looser one waits for tomorrow, measured from the saved preset")
    func strictness() {
        var draft = PresetDraft(editing: study(.steady), presetCount: 4, today: today)
        draft.choose(.locked, calendar: utc)
        #expect(draft.chosenStrictness == .locked)
        #expect(draft.preset.strictness(on: today) == .locked)
        #expect(draft.pendingLine == nil)
        #expect(draft.canSave)
        draft.choose(.gentle, calendar: utc)
        #expect(draft.chosenStrictness == .gentle)
        // Not Locked today: Locked was never saved, so the change runs from the saved Steady.
        #expect(draft.preset.strictness(on: today) == .steady)
        #expect(draft.preset.strictness(on: tomorrow) == .gentle)
        #expect(draft.pendingLine == FocusCopy.pendingLine(.gentle))
        draft.choose(.steady, calendar: utc)
        #expect(draft.pendingLine == nil)
        #expect(!draft.canSave)
    }

    @Test("Locked to Steady reads Steady starts tomorrow")
    func steadyStartsTomorrow() {
        var draft = PresetDraft(editing: study(.locked), presetCount: 4, today: today)
        draft.choose(.steady, calendar: utc)
        #expect(draft.pendingLine == "Steady starts tomorrow")
        #expect(draft.preset.strictness(on: today) == .locked)
        #expect(draft.chosenStrictness == .steady)
        #expect(draft.canSave)
    }

    @Test("A saved change waiting for tomorrow shows when the editor opens, and not once it has begun")
    func savedPending() {
        var waiting = study(.locked)
        waiting.pendingStrictness = .steady
        waiting.pendingFrom = tomorrow
        let opened = PresetDraft(editing: waiting, presetCount: 4, today: today)
        #expect(opened.pendingLine == "Steady starts tomorrow")
        #expect(opened.chosenStrictness == .steady)
        let begun = PresetDraft(editing: waiting, presetCount: 4, today: tomorrow)
        #expect(begun.pendingLine == nil)
        #expect(begun.chosenStrictness == .steady)
    }

    @Test("Typing a name keeps 24 characters on one line; a Return that arrives as a newline (a field that wraps) ends it, and a newline inside stays a word break")
    func typeName() {
        var draft = PresetDraft(newOn: nil, presetCount: 4, today: today)
        var pressedReturn = draft.typeName("Writing")
        #expect(!pressedReturn && draft.name == "Writing")
        pressedReturn = draft.typeName("Writing\n")
        #expect(pressedReturn && draft.name == "Writing")
        pressedReturn = draft.typeName("Study for the chemistry exam")
        #expect(!pressedReturn && draft.name == "Study for the chemistry ")
        // A pasted name keeps its words apart: an inside newline is one space, and the ends lose theirs.
        pressedReturn = draft.typeName("Organic\nchemistry")
        #expect(pressedReturn && draft.name == "Organic chemistry")
        pressedReturn = draft.typeName("\nOrganic \r\n chemistry\n")
        #expect(pressedReturn && draft.name == "Organic chemistry")
        pressedReturn = draft.typeName("Organic  chemistry")
        #expect(!pressedReturn && draft.name == "Organic chemistry")
        // A space being typed at the end stays, so the next word can follow it.
        pressedReturn = draft.typeName("Organic ")
        #expect(!pressedReturn && draft.name == "Organic ")
    }

    @Test("A new preset: unnamed, Start focus, 50 minutes, no break, Steady; any level at once")
    func newPreset() {
        var draft = PresetDraft(newOn: nil, presetCount: 4, today: today)
        #expect(draft.isNew && draft.title == "New preset")
        #expect(draft.verb == .focus && draft.minutes == 50 && !draft.hasBreak && draft.chosenStrictness == .steady)
        draft.choose(.gentle, calendar: utc)
        #expect(draft.preset.strictness(on: today) == .gentle)
        #expect(draft.pendingLine == nil)
        #expect(!draft.canSave)
        draft.name = "Essay"
        #expect(draft.canSave)
        #expect(!draft.canDelete)
        var seventh = PresetDraft(newOn: nil, presetCount: FocusPreset.maximumCount, today: today)
        seventh.name = "Seventh"
        #expect(!seventh.canSave)
    }

    @Test("The last preset can't be deleted")
    func delete() {
        #expect(!PresetDraft(editing: study(), presetCount: 1, today: today).canDelete)
        #expect(PresetDraft(editing: study(), presetCount: 2, today: today).canDelete)
        #expect(PresetDraft(editing: study(), presetCount: 2, today: today).title == "Edit preset")
    }

    @Test("Names keep 24 characters and can't be blank; lengths step by 5 between 20 minutes and 3 hours")
    func fields() {
        var draft = PresetDraft(editing: study(), presetCount: 4, today: today)
        draft.name = "Deep work, the long kind of session"
        #expect(draft.name == "Deep work, the long kind")
        draft.name = "   "
        #expect(!draft.canSave)
        draft.name = "Study"
        #expect(!draft.canSave)
        draft.lengthen()
        #expect(draft.minutes == 55 && draft.lengthText == "55m" && draft.canSave)
        for _ in 0..<20 { draft.shorten() }
        #expect(draft.minutes == 20 && !draft.canShorten && draft.canLengthen)
        for _ in 0..<40 { draft.lengthen() }
        #expect(draft.minutes == 180 && !draft.canLengthen && draft.lengthText == "3h")
        draft.hasBreak = false
        draft.verb = .reading
        draft.appSetID = UUID()
        #expect(!draft.preset.hasBreak && draft.preset.verb == .reading && draft.preset.appSetID != nil)
    }

    @Test("The stepper keeps room for its widest length, so its minus never moves")
    func widestLength() {
        let widest = PresetDraft.widestLengthText
        #expect(widest.count == 6)
        for minutes in stride(from: DialLayout.minimumMinutes, through: DialLayout.maximumMinutes, by: DialLayout.stepMinutes) {
            #expect(FocusTimeText.length(minutes: minutes).count <= widest.count, "\(minutes)")
        }
    }

    @Test("VoiceOver reads the length in words, never \"m\" or \"h\", as it steps")
    func spokenLength() {
        var draft = PresetDraft(editing: study(), presetCount: 4, today: today)
        #expect(draft.spokenLength(locale: enUS) == "50 minutes")
        draft.lengthen()
        #expect(draft.spokenLength(locale: enUS) == "55 minutes")
        for _ in 0..<40 { draft.lengthen() }
        #expect(draft.spokenLength(locale: enUS) == "3 hours")
        draft.shorten()
        #expect(draft.spokenLength(locale: enUS) == "2 hours, 55 minutes")
    }
}

@Suite("Blocking sheet")
struct BlockingSheetModelTests {
    private let six = SelectionSummary(mode: .blockThese, apps: 6, sites: 1, categories: 0)
    private let empty = SelectionSummary(mode: .blockThese, apps: 0, sites: 0, categories: 0)

    @Test("The counter counts this list with every other list in place")
    func counter() {
        let model = BlockingSheetModel(draft: six, saved: empty, others: [empty, empty])
        #expect(model.totalTokens == 6)
        #expect(model.counter == SelectionText.counter(six, totalTokens: 6))
        #expect(model.problem == nil && model.problemLine == nil && model.note == nil && model.canSave)
        #expect(BlockingSheetModel(draft: empty, saved: empty, others: []).counter.text == "No apps chosen yet")
    }

    @Test("An empty selection never replaces a full one")
    func neverEmptyOverFull() {
        let model = BlockingSheetModel(draft: empty, saved: six, others: [])
        #expect(model.problem == .wouldEmpty)
        #expect(!model.canSave)
        #expect(model.problemLine == "Choose at least one app, site or category. This list stays as it was.")
        // Empty over empty replaces nothing.
        #expect(BlockingSheetModel(draft: empty, saved: empty, others: []).canSave)
    }

    @Test("No more than 50 apps rest across every list")
    func tokenLimit() {
        let others = [SelectionSummary(mode: .blockThese, apps: 45, sites: 0, categories: 0)]
        let over = BlockingSheetModel(draft: six, saved: empty, others: others)
        #expect(over.totalTokens == 51)
        #expect(over.problem == .overLimit && !over.canSave)
        #expect(over.problemLine == "Up to 50 apps can rest at once. Choose a category to cover more.")
        // The problem's line takes the place of the counter's limit note, so the limit is said once.
        #expect(over.note == over.problemLine)
        let five = SelectionSummary(mode: .blockThese, apps: 5, sites: 0, categories: 0)
        let atLimit = BlockingSheetModel(draft: five, saved: empty, others: others)
        #expect(atLimit.totalTokens == 50 && atLimit.problem == nil && atLimit.canSave)
        #expect(atLimit.note == SelectionText.counter(five, totalTokens: 50).limitNote)
        #expect(atLimit.note != nil)
        let sites = SelectionSummary(mode: .blockThese, apps: 0, sites: 51, categories: 0)
        #expect(BlockingSheetModel(draft: sites, saved: empty, others: []).problem == .overLimit)
    }

    @Test("Save is off while nothing would change, as the editor's is")
    func nothingToSave() {
        let unchanged = BlockingSheetModel(draft: six, saved: six, others: [], isChange: false)
        #expect(unchanged.problem == nil && !unchanged.canSave)
        #expect(BlockingSheetModel(draft: six, saved: six, others: [], isChange: true).canSave)
        // A problem keeps Save off, whatever changed.
        #expect(!BlockingSheetModel(draft: empty, saved: six, others: [], isChange: true).canSave)
    }

    @Test("Only these with a category, or over 20, saves and says it won't count")
    func onlyThese() {
        let category = SelectionSummary(mode: .onlyThese, apps: 6, sites: 0, categories: 1)
        let model = BlockingSheetModel(draft: category, saved: empty, others: [])
        #expect(model.problem == .onlyTheseWontCount && model.canSave)
        #expect(model.problemLine == "Only these counts with 20 or fewer apps and sites, and no categories.")
        let wide = SelectionSummary(mode: .onlyThese, apps: 21, sites: 0, categories: 0)
        #expect(BlockingSheetModel(draft: wide, saved: empty, others: []).problem == .onlyTheseWontCount)
        let small = SelectionSummary(mode: .onlyThese, apps: 6, sites: 0, categories: 0)
        #expect(BlockingSheetModel(draft: small, saved: empty, others: []).problem == nil)
    }
}

@Suite("Intention entry")
struct IntentionDraftTests {
    @Test("At most 60 characters as typed; Return saves it trimmed; a cleared field removes it")
    func typing() {
        var draft = IntentionDraft(nil)
        #expect(draft.text.isEmpty && draft.saved == nil && draft.isCleared)
        draft.type(String(repeating: "a", count: 70))
        #expect(draft.text.count == RecentIntentions.maximumLength)
        draft.type("  Chemistry ch. 4  ")
        #expect(draft.saved == "Chemistry ch. 4" && !draft.isCleared)
        draft.type("   ")
        #expect(draft.saved == nil && draft.isCleared)
        #expect(IntentionDraft("Essay").text == "Essay")
    }

    @Test("Swiped away or tapped outside without Return, the field saves what Return would: trimmed, at most 60, none when blank")
    func dismissedWithoutReturn() {
        var draft = IntentionDraft("Essay")
        // Opened and closed again untouched: the intention it opened with.
        #expect(draft.savedOnDismiss == "Essay")
        draft.type("  Chemistry ch. 4  ")
        #expect(draft.savedOnDismiss == "Chemistry ch. 4")
        #expect(draft.savedOnDismiss == draft.saved)
        draft.type(String(repeating: "b", count: 70))
        #expect(draft.savedOnDismiss == String(repeating: "b", count: RecentIntentions.maximumLength))
        draft.type("   ")
        #expect(draft.savedOnDismiss == nil)
        // A field that was cleared has already removed the intention; closing it keeps it removed.
        draft.type("")
        #expect(draft.isCleared && draft.savedOnDismiss == nil)
    }

    @Test("A field that wraps (accessibility sizes) gets Return as a newline: it isn't kept, and it saves")
    func returnInAWrappingField() {
        var draft = IntentionDraft("Chemistry")
        let typing = draft.type("Chemistry ch. 4")
        #expect(!typing)
        let atEnd = draft.type("Chemistry ch. 4\n")
        #expect(atEnd)
        #expect(draft.text == "Chemistry ch. 4" && draft.saved == "Chemistry ch. 4")
        // Return with the cursor mid-line.
        let midLine = draft.type("Chemistry\n ch. 4")
        #expect(midLine)
        #expect(draft.text == "Chemistry ch. 4")
    }
}
