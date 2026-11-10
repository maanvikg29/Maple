import Foundation
import Testing
@testable import MapleCore

@Suite("Focus start lines")
struct FocusStartLinesTests {
    /// Field maple, the 3h rung, with 35 minutes to go: a 50-minute session from 14:00 reaches it at minute 35.
    private let fieldMaple = progressRow("campestre", .hoursSaved, threshold: 3, current: Double(3 * 3600 - 35 * 60) / 3600, estimate: nil)
    /// Study 50m, Quick 25m, Deep 1h 30m and Read 30m, with fixed ids for this suite.
    private let presets = FocusPreset.defaults(appSetID: nil)
    private let empty = SelectionSummary(mode: .blockThese, apps: 0, sites: 0, categories: 0)

    private func model(
        strictness: Strictness = .steady, selection: SelectionSummary? = FocusFixtures.blockSix,
        blocking: FocusStatus.Blocking = .ready, first: Bool = false, stage: StartScreenModel.Stage = .choosing,
        displayToday: Int = 0
    ) -> StartScreenModel {
        var preset = presets[0]
        preset.strictness = strictness
        return StartScreenModel(
            preset: preset, minutes: 50, selection: selection, expiredTokens: false, blocking: blocking, isFirstSession: first,
            phase: .day, day: LocalDay(year: 2026, month: 10, day: 23), window: FocusFixtures.window(),
            now: at(2026, 10, 23, 14), progress: fieldMaple, displayToday: displayToday, stage: stage, hasTurned: true, locale: enGB,
            calendar: utc
        )
    }

    @Test("An ordinary start keeps the model's capsule and counts line, and marks the line that names the leaf")
    func blocking() {
        let lines = FocusStartLines(model: model(), mode: .blocking, locale: enGB)
        #expect(lines.primary == .start)
        #expect(lines.capsuleTitle == "Start study · 50m")
        #expect(lines.holdName == nil)
        #expect(lines.plainLine == nil)
        #expect(lines.detailLine == "You'll reach Field maple at minute 35")
        #expect(lines.marksLeaf)
        #expect(lines.leafMinute == 35)
        #expect(lines.showsLeaf)
        #expect(!lines.startsPlainTimer)

        // The first session's definition is a counts line, but it names no leaf.
        let first = FocusStartLines(model: model(first: true), mode: .blocking, locale: enGB)
        #expect(first.detailLine == "Time your chosen apps stayed locked while you were awake.")
        #expect(!first.marksLeaf)

        // No apps chosen: the capsule opens the Blocking sheet.
        let noApps = FocusStartLines(model: model(selection: empty), mode: .blocking, locale: enGB)
        #expect(noApps.primary == .chooseApps)
        #expect(noApps.capsuleTitle == "Choose apps")
    }

    @Test("Locked: a hold, its spoken name, and the plain-tap hint in the counts line's place")
    func locked() {
        let locked = model(strictness: .locked)
        let lines = FocusStartLines(model: locked, mode: .blocking, locale: enGB)
        #expect(lines.primary == .holdToStart)
        #expect(lines.capsuleTitle == "Hold to start · 50m")
        #expect(lines.holdName == "Hold to start, Locked 50 minutes")
        #expect(lines.detailLine == "You'll reach Field maple at minute 35")

        let hinted = FocusStartLines(model: locked, mode: .blocking, showsHoldHint: true, locale: enGB)
        #expect(hinted.detailLine == "Hold to start. Locked ends early only by emergency release.")
        #expect(!hinted.marksLeaf)
        #expect(hinted.leafMinute == 35)

        // Only a hold has a hint.
        let steady = FocusStartLines(model: model(), mode: .blocking, showsHoldHint: true, locale: enGB)
        #expect(steady.detailLine == "You'll reach Field maple at minute 35")
    }

    @Test("A plain timer: its own line instead of the Blocking line, no counts and no leaf, and it needs no apps")
    func plainTimer() {
        let lines = FocusStartLines(model: model(blocking: .needsPermission), mode: .plainTimer, locale: enGB)
        #expect(lines.plainLine == "Plain timer · apps aren't locked")
        #expect(lines.detailLine == nil)
        #expect(lines.leafMinute == nil)
        #expect(!lines.showsLeaf)
        #expect(lines.startsPlainTimer)
        #expect(lines.primary == .start)
        #expect(lines.capsuleTitle == "Start study · 50m")

        // Even with no apps chosen, a plain timer starts.
        let noApps = FocusStartLines(model: model(selection: empty), mode: .plainTimer, locale: enGB)
        #expect(noApps.primary == .start)
        #expect(noApps.capsuleTitle == "Start study · 50m")

        // A plain timer locks nothing, so it is Gentle whatever its preset: one tap starts it, with no hold and no
        // Locked line, in a build that can block and in one that can't.
        for blocking in [FocusStatus.Blocking.needsPermission, .notInThisBuild] {
            for strictness in [Strictness.locked, .steady] {
                let plain = FocusStartLines(
                    model: model(strictness: strictness, blocking: blocking), mode: .plainTimer, showsHoldHint: true, locale: enGB
                )
                #expect(plain.primary == .start)
                #expect(plain.capsuleTitle == "Start study · 50m")
                #expect(plain.capsuleSpoken == "Start study, 50 minutes")
                #expect(plain.holdName == nil)
                #expect(plain.detailLine == nil)
                #expect(plain.plainLine == "Plain timer · apps aren't locked")
            }
        }
    }

    @Test("A lock that failed offers the plain timer, which starts with one tap whatever the preset's strictness")
    func lockFailed() {
        let lines = FocusStartLines(model: model(), mode: .lockFailed, locale: enGB)
        #expect(lines.detailLine == "Couldn't lock your apps · Start as a plain timer?")
        #expect(lines.capsuleTitle == "Start as a plain timer")
        #expect(lines.primary == .start)
        #expect(lines.plainLine == nil)
        #expect(lines.leafMinute == nil)
        #expect(lines.showsLeaf)
        #expect(lines.startsPlainTimer)
        #expect(!lines.marksLeaf)

        // The start it offers is a plain timer, so Locked's hold doesn't apply to it, nor its line.
        let locked = FocusStartLines(model: model(strictness: .locked), mode: .lockFailed, showsHoldHint: true, locale: enGB)
        #expect(locked.primary == .start)
        #expect(locked.capsuleTitle == "Start as a plain timer")
        #expect(locked.capsuleSpoken == "Start as a plain timer")
        #expect(locked.holdName == nil)
        #expect(locked.detailLine == "Couldn't lock your apps · Start as a plain timer?")
        // A blocking start of the same preset is still a hold.
        #expect(FocusStartLines(model: model(strictness: .locked), mode: .blocking, locale: enGB).primary == .holdToStart)
    }

    @Test("A start the ledger couldn't record says so, under the hint and over everything else")
    func notice() {
        let lines = FocusStartLines(model: model(), mode: .blocking, notice: FocusStartLines.couldntStart, locale: enGB)
        #expect(lines.detailLine == "Couldn't start the session. Try again in a moment.")
        #expect(!lines.marksLeaf)
        let failed = FocusStartLines(model: model(), mode: .lockFailed, notice: FocusStartLines.couldntStart, locale: enGB)
        #expect(failed.detailLine == "Couldn't start the session. Try again in a moment.")
        let hinted = FocusStartLines(model: model(strictness: .locked), mode: .blocking, showsHoldHint: true,
                                     notice: FocusStartLines.couldntStart, locale: enGB)
        #expect(hinted.detailLine == "Hold to start. Locked ends early only by emergency release.")
    }

    @Test("Locking keeps its capsule waiting; a minimised session is the model's own, whatever the mode")
    func stages() {
        let locking = FocusStartLines(model: model(stage: .locking), mode: .blocking, locale: enGB)
        #expect(locking.primary == .locking)
        #expect(locking.capsuleTitle == "Locking 6 apps…")
        let plainLocking = FocusStartLines(model: model(blocking: .needsPermission, stage: .locking), mode: .plainTimer, locale: enGB)
        #expect(plainLocking.primary == .locking)
        #expect(plainLocking.capsuleTitle == "Start study · 50m")

        let running = FocusStartLines(model: model(stage: .running), mode: .lockFailed, showsHoldHint: true, locale: enGB)
        #expect(running.primary == .returnToSession)
        #expect(running.capsuleTitle == "Return to session")
        #expect(running.detailLine == nil)
        #expect(running.leafMinute == nil)
        #expect(running.plainLine == nil)
        #expect(!running.startsPlainTimer)
    }

    @Test("VoiceOver reads the capsule's and the counts line's lengths in words, never 50m or 6h (§4.9)")
    func spoken() {
        let start = FocusStartLines(model: model(), mode: .blocking, locale: enGB)
        #expect(start.capsuleSpoken == "Start study, 50 minutes")
        // A line with no length reads as it is shown.
        #expect(start.detailSpoken == "You'll reach Field maple at minute 35")

        let cap = FocusStartLines(model: model(displayToday: HoursCredit.dailyCap), mode: .blocking, locale: enGB)
        #expect(cap.detailLine == "6h counted today · more won't add")
        #expect(cap.detailSpoken == "6 hours counted today, more won't add")
        let toward = FocusStartLines(model: model(displayToday: HoursCredit.dailyCap - 20 * 60), mode: .blocking, locale: enGB)
        #expect(toward.detailLine == "Counts toward Field maple · 35m to go")
        #expect(toward.detailSpoken == "Counts toward Field maple, 35 minutes to go")

        // A plain timer's start has its length too; the failed lock's and the other capsules have none.
        #expect(FocusStartLines(model: model(blocking: .needsPermission), mode: .plainTimer, locale: enGB).capsuleSpoken
            == "Start study, 50 minutes")
        let failed = FocusStartLines(model: model(), mode: .lockFailed, locale: enGB)
        #expect(failed.capsuleSpoken == "Start as a plain timer")
        #expect(failed.detailSpoken == "Couldn't lock your apps · Start as a plain timer?")
        #expect(FocusStartLines(model: model(selection: empty), mode: .blocking, locale: enGB).capsuleSpoken == "Choose apps")
        #expect(FocusStartLines(model: model(stage: .running), mode: .blocking, locale: enGB).capsuleSpoken == "Return to session")
        #expect(FocusStartLines(model: model(stage: .running), mode: .blocking, locale: enGB).detailSpoken == nil)
        // Locked's hold reads its own name.
        let locked = FocusStartLines(model: model(strictness: .locked), mode: .blocking, showsHoldHint: true, locale: enGB)
        #expect(locked.capsuleSpoken == "Hold to start, Locked 50 minutes")
        #expect(locked.detailSpoken == "Hold to start. Locked ends early only by emergency release.")

        #expect(FocusCopy.startName(.deep, minutes: 90, locale: enGB) == "Start a deep session, 1 hour, 30 minutes")
        #expect(FocusCopy.countsLineSpoken(.capReached, locale: enGB) == "6 hours counted today, more won't add")
        #expect(FocusCopy.countsLineSpoken(.toward(leaf: "Field maple", minutesToGo: 80), locale: enGB)
            == "Counts toward Field maple, 1 hour, 20 minutes to go")
        #expect(FocusCopy.countsLineSpoken(.reaches(leaf: "Field maple", minute: 35), locale: enGB) == nil)
        #expect(FocusCopy.countsLineSpoken(.definition, locale: enGB) == nil)
    }

    @Test("The preset: the chip picked, then Quick for the first session, then the last used, then the first")
    func preset() {
        let study = presets[0], quick = presets[1], deep = presets[2], read = presets[3]
        #expect(FocusStartLines.preset(selected: deep.id, presets: presets, lastUsedID: read.id, isFirstSession: true)?.id == deep.id)
        #expect(FocusStartLines.preset(selected: nil, presets: presets, lastUsedID: read.id, isFirstSession: true)?.id == quick.id)
        // A chip whose preset was deleted falls back.
        #expect(FocusStartLines.preset(selected: UUID(), presets: presets, lastUsedID: read.id, isFirstSession: false)?.id == read.id)
        #expect(FocusStartLines.preset(selected: nil, presets: presets, lastUsedID: nil, isFirstSession: false)?.id == study.id)
        let noQuick = presets.filter { $0.verb != .quick }
        #expect(FocusStartLines.preset(selected: nil, presets: noQuick, lastUsedID: deep.id, isFirstSession: true)?.id == deep.id)
        #expect(FocusStartLines.preset(selected: nil, presets: [], lastUsedID: nil, isFirstSession: true) == nil)
    }

    @Test("The title, the chips and the minimised dial, in words")
    func words() {
        #expect(FocusStartLines.title == "Focus")
        #expect(FocusStartLines.chipLabel(presets[0], locale: enGB) == "Study, 50 minutes")
        #expect(FocusStartLines.chipLabel(presets[3], locale: enGB) == "Read, 30 minutes")
        #expect(FocusStartLines.addChip == "+")
        #expect(FocusStartLines.addChipTitle(isAccessibilitySize: false) == "+")
        #expect(FocusStartLines.addChipTitle(isAccessibilitySize: true) == "New preset")
        #expect(FocusStartLines.minimisedCaption(plannedMinutes: 50) == "left of 50m")
        #expect(FocusStartLines.minimisedCaption(plannedMinutes: 90) == "left of 1h 30m")
        #expect(FocusStartLines.minimisedDialLabel(secondsLeft: 32 * 60, plannedMinutes: 50, locale: enGB) == "32 minutes left of 50.")
        #expect(FocusStartLines.minimisedDialLabel(secondsLeft: 45, plannedMinutes: 50, locale: enGB) == "45 seconds left of 50.")
    }

    @Test("The Blocking line in two tones, with Locked's lock between the dot and its name")
    func blockingParts() {
        let steady = FocusStartLines.blockingParts(SelectionText.blockingLine(FocusFixtures.blockSix, strictness: .steady, expired: false))
        #expect(steady.main == "Blocking 6 apps")
        #expect(steady.separator == " · ")
        #expect(!steady.showsLock)
        #expect(steady.trailing == "Steady ›")
        #expect(steady.main + (steady.separator ?? "") + steady.trailing == "Blocking 6 apps · Steady ›")

        let locked = FocusStartLines.blockingParts(SelectionText.blockingLine(FocusFixtures.blockSix, strictness: .locked, expired: false))
        #expect(locked.separator == " · ")
        #expect(locked.showsLock)
        #expect(locked.trailing == " Locked ›")

        let none = FocusStartLines.blockingParts(SelectionText.blockingLine(nil, strictness: .steady, expired: false))
        #expect(none.main == "Choose apps to block")
        #expect(none.separator == nil)
        #expect(!none.showsLock)
        #expect(none.trailing == " ›")
    }
}
