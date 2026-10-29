import Foundation
import Testing
@testable import MapleCore

@Suite("Mark states")
struct MarkStateTests {
    @Test("Eight states, as the dial's table lists them; only gaps are drawn short")
    func states() {
        #expect(MarkState.allCases == [.plan, .ahead, .lit, .current, .rest, .gap, .hold, .off])
        #expect(MarkState.allCases.filter(\.isShort) == [.gap])
    }
}

@Suite("Focus copy")
struct FocusCopyTests {
    private let back = at(2026, 10, 23, 14, 28)

    @Test("Needs Screen Time: a card for each state, with a primary only where Maple can ask")
    func cards() {
        let notAsked = FocusCopy.card(.notAsked)
        #expect(notAsked.title == "Lock apps with Screen Time")
        #expect(notAsked.body == "Maple keeps your chosen apps resting while you focus. It never sees which apps you use.")
        #expect(notAsked.primary == "Turn on Screen Time")
        let declined = FocusCopy.card(.declined)
        #expect(declined.title == "Screen Time is off for Maple")
        #expect(declined.body == "Turn it on to count your focus time.")
        #expect(declined.primary == "Turn on Screen Time")
        let restricted = FocusCopy.card(.restricted)
        #expect(restricted.title == "Screen Time is managed on this iPhone")
        #expect(restricted.body == "A parent can allow Maple in Screen Time settings.")
        #expect(restricted.primary == nil)
        let passcode = FocusCopy.card(.noPasscode)
        #expect(passcode.title == "Set a passcode to use Screen Time")
        #expect(passcode.body == nil)
        #expect(passcode.primary == nil)
        let free = FocusCopy.card(.freeBuild)
        #expect(free.title == "This version of Maple can't lock apps")
        #expect(free.body == "The timer still runs, but it won't count.")
        #expect(free.primary == nil)
        #expect(FocusCopy.plainTimerLink == "Use a plain timer · it won't count")
        #expect(FocusCopy.turnOnScreenTime == "Turn on Screen Time")
    }

    @Test("Each probe picks its card; a build that can't block always shows the free build's")
    func cardForProbe() {
        #expect(NeedsScreenTimeState(probe: .allowed, capability: .preview) == nil)
        #expect(NeedsScreenTimeState(probe: .allowed, capability: .screenTime) == nil)
        #expect(NeedsScreenTimeState(probe: .notDetermined, capability: .screenTime) == .notAsked)
        #expect(NeedsScreenTimeState(probe: .declined, capability: .screenTime) == .declined)
        #expect(NeedsScreenTimeState(probe: .restricted, capability: .preview) == .restricted)
        #expect(NeedsScreenTimeState(probe: .noPasscode, capability: .preview) == .noPasscode)
        #expect(NeedsScreenTimeState(probe: .unavailable, capability: .screenTime) == .freeBuild)
        #expect(NeedsScreenTimeState(probe: .allowed, capability: .unavailableInBuild) == .freeBuild)
        #expect(NeedsScreenTimeState(probe: .notDetermined, capability: .unavailableInBuild) == .freeBuild)
    }

    @Test("Start lines: the hold, its hint, the first session, the failed lock and the dial's labels")
    func start() {
        #expect(FocusCopy.holdHint == "Hold to start. Locked ends early only by emergency release.")
        #expect(FocusCopy.holdHintSeconds == 4)
        #expect(FocusCopy.holdToStartSeconds == 1.5)
        #expect(FocusCopy.holdToStart(minutes: 50) == "Hold to start · 50m")
        #expect(FocusCopy.holdToStart(minutes: 90) == "Hold to start · 1h 30m")
        #expect(FocusCopy.holdToStartName(minutes: 50, locale: enGB) == "Hold to start, Locked 50 minutes")
        #expect(FocusCopy.sessionLengthLabel(minutes: 50, locale: enGB) == "Session length, 50 minutes")
        #expect(FocusCopy.firstSessionLine == "You can lock your phone. Maple keeps time.")
        #expect(FocusCopy.turnHint == "turn to set the length")
        #expect(FocusCopy.couldntLock == "Couldn't lock your apps · Start as a plain timer?")
        #expect(FocusCopy.startPlainTimer == "Start as a plain timer")
        #expect(FocusCopy.intentionPrompt == "What's this for?")
        #expect(FocusCopy.newPreset == "New preset")
        #expect(FocusCopy.chooseApps == "Choose apps")
        #expect(FocusCopy.returnToSession == "Return to session")
        #expect(FocusCopy.keepGoing == "Keep going")
        #expect(FocusCopy.done == "Done")
    }

    @Test("A session's header: the preset, then the intention when there is one")
    func sessionTitle() {
        #expect(FocusCopy.sessionTitle(presetName: "Study", intention: "Chemistry ch. 4") == "Study · Chemistry ch. 4")
        #expect(FocusCopy.sessionTitle(presetName: "Study", intention: "  Chemistry ch. 4 ") == "Study · Chemistry ch. 4")
        #expect(FocusCopy.sessionTitle(presetName: "Study", intention: nil) == "Study")
        #expect(FocusCopy.sessionTitle(presetName: "Study", intention: "   ") == "Study")
    }

    @Test("Strictness: three names, one honest line each, and a looser level waits a day")
    func strictness() {
        #expect(Strictness.allCases.map { FocusCopy.strictnessName($0) } == ["Gentle", "Steady", "Locked"])
        #expect(FocusCopy.strictnessLine(.gentle) == "Unlock an app when you need it. Unlocked time doesn't count.")
        #expect(FocusCopy.strictnessLine(.steady) == "Two unlocks a session. Ending early takes a hold and 15 seconds.")
        #expect(FocusCopy.strictnessLine(.locked)
            == "No unlocks. Ending early takes a 10-second hold and a breath. Calls and Always Allowed apps keep working, and you can turn off Screen Time for Maple in Settings.")
        #expect(FocusCopy.pendingLine(.steady) == "Steady starts tomorrow")
        #expect(FocusCopy.pendingLine(.gentle) == "Gentle starts tomorrow")
    }

    @Test("Break: three suggestions taking turns, the line, and the dial read aloud")
    func breakTime() {
        #expect(FocusCopy.BreakTime.header == "Break · apps stay locked")
        #expect(FocusCopy.BreakTime.caption == "left of your break")
        #expect(FocusCopy.BreakTime.backToStudying == "Back to studying")
        #expect(FocusCopy.BreakTime.suggestions == ["Stand up and stretch.", "Look out of a window.", "Get a glass of water."])
        #expect(([0, 99, 100, 250, 300] as [TimeInterval]).map { FocusCopy.BreakTime.suggestion(secondsIntoBreak: $0) }
            == ["Stand up and stretch.", "Stand up and stretch.", "Look out of a window.", "Get a glass of water.", "Stand up and stretch."])
        #expect(FocusCopy.BreakTime.line(backAt: back, locale: enGB, calendar: utc) == "The break counts. Back to studying at 14:28.")
        #expect(FocusCopy.BreakTime.line(backAt: back, locale: enUS, calendar: utc) == "The break counts. Back to studying at 2:28 PM.")
        #expect(FocusCopy.BreakTime.dialLabel(secondsLeft: 4 * 60, backAt: back, locale: enGB, calendar: utc)
            == "4 minutes of break left. Back to studying at 14:28.")
        #expect(FocusCopy.BreakTime.dialLabel(secondsLeft: 3 * 60 + 20, backAt: back, locale: enGB, calendar: utc)
            == "4 minutes of break left. Back to studying at 14:28.")
        #expect(FocusCopy.BreakTime.dialLabel(secondsLeft: 45, backAt: back, locale: enGB, calendar: utc)
            == "45 seconds of break left. Back to studying at 14:28.")
        #expect(FocusCopy.BreakTime.dialLabel(secondsLeft: 1, backAt: back, locale: enGB, calendar: utc)
            == "1 second of break left. Back to studying at 14:28.")
    }

    @Test("End early: counted minutes only, the zero line, Steady's hold and countdown, and the break instead")
    func endEarly() {
        #expect(FocusCopy.EndEarly.title == "End this session?")
        #expect(FocusCopy.EndEarly.savedLine(countedSeconds: 18 * 60 + 40) == "18 minutes saved so far. They stay yours either way.")
        #expect(FocusCopy.EndEarly.savedLine(countedSeconds: 60) == "1 minute saved so far. It stays yours either way.")
        #expect(FocusCopy.EndEarly.savedLine(countedSeconds: 30) == "Under a minute saved so far. It stays yours either way.")
        #expect(FocusCopy.EndEarly.savedLine(countedSeconds: 0) == "This session isn't counting toward leaves.")
        #expect(FocusCopy.EndEarly.holdToEnd == "Hold to end")
        #expect(FocusCopy.EndEarly.holdSeconds == 3)
        #expect(FocusCopy.EndEarly.countdownSeconds == 15)
        #expect(FocusCopy.EndEarly.endingIn(seconds: 15) == "Ending in 15s")
        #expect(FocusCopy.EndEarly.endingIn(seconds: 9) == "Ending in 9s")
        #expect(FocusCopy.EndEarly.takeBreakInstead == "Take a 5-minute break instead")
        #expect(FocusCopy.EndEarly.gentleEnd == "End session")
        #expect(FocusCopy.EndEarly.gentleBreathSeconds == 5)
    }

    @Test("Emergency release: the hold, the honest line with and without counted minutes, the breath and the ended state")
    func emergency() {
        #expect(FocusCopy.Emergency.title == "Emergency release")
        #expect(FocusCopy.Emergency.subtitle(presetName: "Study") == "Study · Locked")
        #expect(FocusCopy.Emergency.holdToRelease == "Hold to release")
        #expect(FocusCopy.Emergency.holdSeconds == 10)
        #expect(FocusCopy.Emergency.holdCaption == "hold to release")
        #expect(FocusCopy.Emergency.keepHolding == "keep holding")
        #expect(FocusCopy.Emergency.secondsLeft(10) == "10s")
        #expect(FocusCopy.Emergency.secondsLeft(9.2) == "10s")
        #expect(FocusCopy.Emergency.secondsLeft(0) == "0s")
        #expect(FocusCopy.Emergency.body(countedSeconds: 18 * 60)
            == "Ends this session now. Your 18 minutes stay yours, but it won't count as finished.")
        #expect(FocusCopy.Emergency.body(countedSeconds: 60)
            == "Ends this session now. Your 1 minute stays yours, but it won't count as finished.")
        #expect(FocusCopy.Emergency.body(countedSeconds: 20)
            == "Ends this session now. Your time so far stays yours, but it won't count as finished.")
        #expect(FocusCopy.Emergency.body(countedSeconds: 0) == "Ends this session now. It won't count as finished.")
        #expect(FocusCopy.Emergency.breatheIn == "Breathe in")
        #expect(FocusCopy.Emergency.breatheOut == "and out")
        #expect(FocusCopy.Emergency.breathSeconds == 4)
        #expect(FocusCopy.Emergency.endedCaption(countedSeconds: 18 * 60) == "saved · they stay yours")
        #expect(FocusCopy.Emergency.endedCaption(countedSeconds: 0) == "not counted toward leaves")
        #expect(FocusCopy.Emergency.endedLine == "Session ended. It won't count as finished.")
    }

    @Test("Release all apps asks first")
    func releaseAll() {
        #expect(FocusCopy.ReleaseAll.title == "Release all apps")
        #expect(FocusCopy.ReleaseAll.question == "Release all apps?")
        #expect(FocusCopy.ReleaseAll.body == "Every app Maple is resting opens again now.")
        #expect(FocusCopy.ReleaseAll.cancel == "Cancel")
    }

    @Test("No Focus line shouts, fails, quits, loses a streak or counts rest days down")
    func voice() {
        var lines = NeedsScreenTimeState.allCases.flatMap { state -> [String] in
            let card = FocusCopy.card(state)
            return [card.title, card.body, card.primary].compactMap { $0 }
        }
        lines += Strictness.allCases.flatMap { [FocusCopy.strictnessName($0), FocusCopy.strictnessLine($0), FocusCopy.pendingLine($0)] }
        lines += [
            FocusCopy.holdHint, FocusCopy.firstSessionLine, FocusCopy.couldntLock, FocusCopy.plainTimerLink, FocusCopy.turnHint,
            FocusCopy.BreakTime.header, FocusCopy.BreakTime.caption, FocusCopy.BreakTime.backToStudying, FocusCopy.EndEarly.title,
            FocusCopy.EndEarly.takeBreakInstead, FocusCopy.Emergency.endedLine, FocusCopy.ReleaseAll.question, FocusCopy.ReleaseAll.body,
        ]
        lines += FocusCopy.BreakTime.suggestions
        lines += [0, 30, 60, 18 * 60].flatMap {
            [FocusCopy.EndEarly.savedLine(countedSeconds: $0), FocusCopy.Emergency.body(countedSeconds: $0),
             FocusCopy.Emergency.endedCaption(countedSeconds: $0)]
        }
        for line in lines {
            let lower = line.lowercased()
            #expect(!line.contains("!"), "\(line)")
            #expect(!["fail", "quit", "streak lost", "rest days left"].contains { lower.contains($0) }, "\(line)")
        }
    }
}

@Suite("Selection text")
struct SelectionTextTests {
    private func block(_ apps: Int, sites: Int = 0, categories: Int = 0) -> SelectionSummary {
        SelectionSummary(mode: .blockThese, apps: apps, sites: sites, categories: categories)
    }

    private func allow(_ apps: Int, sites: Int = 0, categories: Int = 0) -> SelectionSummary {
        SelectionSummary(mode: .onlyThese, apps: apps, sites: sites, categories: categories)
    }

    private func line(_ selection: SelectionSummary?, _ strictness: Strictness = .steady, expired: Bool = false) -> SelectionText.BlockingLine {
        SelectionText.blockingLine(selection, strictness: strictness, expired: expired)
    }

    @Test("The Blocking line names what the selection holds, then the strictness (§5.1's table)")
    func blockingLines() {
        #expect(line(block(6)).printed == "Blocking 6 apps · Steady ›")
        #expect(line(block(2, categories: 1)).printed == "Blocking 1 category and 2 apps · Steady ›")
        #expect(line(allow(6)).printed == "Allowing 6 apps · Steady ›")
        #expect(line(allow(24)).printed == "Allowing 24 apps · 20 or fewer count ›")
        #expect(line(block(1), .gentle).printed == "Blocking 1 app · Gentle ›")
        #expect(line(block(2, sites: 1, categories: 1)).text == "Blocking 1 category, 2 apps and 1 site")
        #expect(line(block(6, sites: 1)).text == "Blocking 6 apps and 1 site")
        #expect(!line(block(6)).needsAttention)
    }

    @Test("Locked draws its lock before the name; the line reads aloud without the chevron")
    func locked() {
        let locked = line(block(6), .locked)
        #expect(locked.text == "Blocking 6 apps")
        #expect(locked.strictness == .locked)
        #expect(locked.showsLock)
        #expect(locked.strictnessName == "Locked")
        #expect(locked.printed == "Blocking 6 apps · Locked ›")
        #expect(locked.spoken == "Blocking 6 apps, Locked")
        #expect(!line(block(6), .steady).showsLock)
    }

    @Test("No apps, a selection that can't count, and expired tokens take the whole line")
    func attention() {
        let none = line(nil, .locked)
        #expect(none.printed == "Choose apps to block ›")
        #expect(none.strictness == nil)
        #expect(!none.showsLock)
        #expect(none.needsAttention)
        #expect(none.spoken == "Choose apps to block")
        #expect(line(block(0)).printed == "Choose apps to block ›")
        #expect(line(block(6), expired: true).printed == "Some apps need choosing again ›")
        #expect(line(block(6), expired: true).needsAttention)
        #expect(line(allow(20, sites: 4)).printed == "Allowing 20 apps and 4 sites · 20 or fewer count ›")
        #expect(line(allow(6, categories: 1)).printed == "Allowing 1 category and 6 apps · allow apps, not categories ›")
        #expect(line(block(51)).printed == "Blocking 51 apps · 50 or fewer count ›")
        // The order StartReadiness checks: an empty selection, then one that can't count, then expired tokens.
        #expect(line(allow(24), expired: true).printed == "Allowing 24 apps · 20 or fewer count ›")
    }

    @Test("The running header's resting line")
    func resting() {
        #expect(SelectionText.restingLine(block(6), isPlainTimer: false) == "6 apps resting")
        #expect(SelectionText.restingLine(block(1), isPlainTimer: false) == "1 app resting")
        #expect(SelectionText.restingLine(block(6, sites: 1), isPlainTimer: false) == "6 apps and 1 site resting")
        #expect(SelectionText.restingLine(block(0, sites: 2), isPlainTimer: false) == "2 sites resting")
        #expect(SelectionText.restingLine(block(2, categories: 1), isPlainTimer: false) == "Apps resting")
        #expect(SelectionText.restingLine(allow(6), isPlainTimer: false) == "Apps resting")
        #expect(SelectionText.restingLine(nil, isPlainTimer: true) == "Plain timer · apps aren't locked")
        #expect(SelectionText.restingLine(block(6), isPlainTimer: true) == "Plain timer · apps aren't locked")
    }

    @Test("Locking, until the read-back confirms the block")
    func locking() {
        #expect(SelectionText.locking(block(6)) == "Locking 6 apps…")
        #expect(SelectionText.locking(block(6, sites: 1)) == "Locking 6 apps and 1 site…")
        #expect(SelectionText.locking(block(2, categories: 1)) == "Locking apps…")
        #expect(SelectionText.locking(allow(6)) == "Locking apps…")
        #expect(SelectionText.locking(nil) == "Locking apps…")
    }

    @Test("The Blocking sheet's counter, with the 50-app limit named from 40 tokens")
    func counter() {
        let counter = SelectionText.counter(block(6, sites: 1), totalTokens: 7)
        #expect(counter.text == "6 apps · 1 site")
        #expect(counter.limitNote == nil)
        #expect(SelectionText.counter(block(2, categories: 1), totalTokens: 2).text == "1 category · 2 apps")
        #expect(SelectionText.counter(allow(1), totalTokens: 1).text == "1 app")
        #expect(SelectionText.counter(block(0), totalTokens: 0).text == "No apps chosen yet")
        #expect(SelectionText.counter(block(39), totalTokens: 39).limitNote == nil)
        #expect(SelectionText.counter(block(40), totalTokens: 40).limitNote == "Up to 50 apps can rest at once")
        #expect(SelectionText.counter(block(1, sites: 1), totalTokens: 45).limitNote == "Up to 50 apps can rest at once")
    }
}

@Suite("Start screen model")
struct StartScreenModelTests {
    /// Field maple, the 3h rung, with 35 minutes to go.
    static let fieldMaple = progressRow("campestre", .hoursSaved, threshold: 3, current: Double(3 * 3600 - 35 * 60) / 3600, estimate: nil)
    private let today = LocalDay(year: 2026, month: 10, day: 23)
    private let study = FocusPreset.defaults(appSetID: nil)[0]

    private func model(
        preset: FocusPreset? = nil, minutes: Int = 50, selection: SelectionSummary? = FocusFixtures.blockSix, expired: Bool = false,
        blocking: FocusStatus.Blocking = .ready, first: Bool = false, phase: NowPhase = .day, day: LocalDay? = nil,
        window: AwakeWindow = FocusFixtures.window(), now: Date = at(2026, 10, 23, 14),
        progress: LeafProgress? = StartScreenModelTests.fieldMaple, displayToday: Int = 0,
        stage: StartScreenModel.Stage = .choosing, hasTurned: Bool = false, locale: Locale = enGB
    ) -> StartScreenModel {
        StartScreenModel(
            preset: preset ?? study, minutes: minutes, selection: selection, expiredTokens: expired, blocking: blocking,
            isFirstSession: first, phase: phase, day: day ?? today, window: window, now: now, progress: progress,
            displayToday: displayToday, stage: stage, hasTurned: hasTurned, locale: locale, calendar: utc
        )
    }

    @Test("Steady: the verb capsule, the Blocking line with its strictness, the leaf minute and the hint")
    func steady() {
        let start = model()
        #expect(start.capsuleTitle == "Start study · 50m")
        #expect(start.primary == .start)
        #expect(start.strictness == .steady)
        #expect(start.blockingLine.printed == "Blocking 6 apps · Steady ›")
        #expect(start.countsLine == "You'll reach Field maple at minute 35")
        #expect(start.leafMinute == 35)
        #expect(start.forecast.leafMinute == 35)
        #expect(start.leafName == "Field maple")
        #expect(start.hint == "turn to set the length")
        #expect(start.caption == "turn to set the length")
        #expect(start.lengthText == "50m")
        #expect(start.dialLabel == "Session length, 50 minutes")
        #expect(start.readiness == .ready(needsHold: false))
        #expect(start.holdName == nil)
        #expect(start.plainTapHint == nil)
        #expect(start.showsDetails)
        #expect(start.canTurn)
        #expect(!start.capsuleIsDimmed)
        let turned = model(hasTurned: true)
        #expect(turned.hint == nil)
        #expect(turned.caption == "Study")
    }

    @Test("Each verb has its own capsule, and lengths read as on the dial")
    func verbs() {
        let titles = FocusPreset.defaults(appSetID: nil).map { model(preset: $0, minutes: $0.minutes).capsuleTitle }
        #expect(titles == ["Start study · 50m", "Start a quick session · 25m", "Start a deep session · 1h 30m", "Start reading · 30m"])
        #expect(model(minutes: 15).capsuleTitle == "Start study · 20m")
        #expect(model(minutes: 240).lengthText == "3h")
    }

    @Test("Locked: Hold to start · 50m, the lock in the Blocking line, its spoken name and the plain-tap hint")
    func locked() {
        var preset = study
        preset.strictness = .locked
        let start = model(preset: preset)
        #expect(start.capsuleTitle == "Hold to start · 50m")
        #expect(start.primary == .holdToStart)
        #expect(start.blockingLine.printed == "Blocking 6 apps · Locked ›")
        #expect(start.blockingLine.showsLock)
        #expect(start.holdName == "Hold to start, Locked 50 minutes")
        #expect(start.plainTapHint == "Hold to start. Locked ends early only by emergency release.")
        #expect(start.readiness == .ready(needsHold: true))
    }

    @Test("A looser strictness waits for the next Maple day; a tighter one applies now")
    func pendingStrictness() {
        var preset = study
        preset.changeStrictness(to: .locked, on: today, calendar: utc)
        preset.changeStrictness(to: .gentle, on: today, calendar: utc)
        let now = model(preset: preset)
        #expect(now.strictness == .locked)
        #expect(now.capsuleTitle == "Hold to start · 50m")
        let tomorrow = model(preset: preset, day: LocalDay(year: 2026, month: 10, day: 24), window: FocusFixtures.window(24),
                             now: at(2026, 10, 24, 14))
        #expect(tomorrow.strictness == .gentle)
        #expect(tomorrow.capsuleTitle == "Start study · 50m")
        #expect(tomorrow.blockingLine.printed == "Blocking 6 apps · Gentle ›")
    }

    // §5.1's states table, row by row.

    @Test("No app set: Choose apps to block ›, and the capsule reads Choose apps")
    func noAppSet() {
        for selection in [nil, SelectionSummary(mode: .blockThese, apps: 0, sites: 0, categories: 0)] {
            let start = model(selection: selection)
            #expect(start.blockingLine.printed == "Choose apps to block ›")
            #expect(start.capsuleTitle == "Choose apps")
            #expect(start.primary == .chooseApps)
            #expect(start.countsLine == nil)
            #expect(start.leafMinute == nil)
            #expect(start.readiness == .needsStartScreen(.noAppSet))
        }
        var locked = study
        locked.strictness = .locked
        #expect(model(preset: locked, selection: nil).capsuleTitle == "Choose apps")
    }

    @Test("A selection that doesn't qualify names the limit and hides the counts line")
    func notQualifying() {
        let start = model(selection: SelectionSummary(mode: .onlyThese, apps: 24, sites: 0, categories: 0))
        #expect(start.blockingLine.printed == "Allowing 24 apps · 20 or fewer count ›")
        #expect(start.countsLine == nil)
        #expect(start.leafMinute == nil)
        #expect(start.readiness == .needsStartScreen(.notQualifying))
        #expect(start.capsuleTitle == "Start study · 50m")
    }

    @Test("Expired tokens: Some apps need choosing again ›")
    func expired() {
        let start = model(expired: true)
        #expect(start.blockingLine.printed == "Some apps need choosing again ›")
        #expect(start.readiness == .needsStartScreen(.expiredTokens))
    }

    @Test("The first session ever: the counts line is the definition")
    func firstEver() {
        let start = model(first: true)
        #expect(start.countsLine == "Time your chosen apps stayed locked while you were awake.")
        #expect(start.countsLine == RewardCategoryInfo(.hoursSaved).definition)
        #expect(start.readiness == .needsStartScreen(.firstSession))
    }

    @Test("Wind-down: the capsule is dimmed but still starts")
    func windDown() {
        let start = model(minutes: 25, phase: .windDown, now: at(2026, 10, 23, 22, 20))
        #expect(start.capsuleIsDimmed)
        #expect(start.primary == .start)
        #expect(start.capsuleTitle == "Start study · 25m")
        #expect(start.countsLine == "Counts toward Field maple · 35m to go")
        #expect(start.readiness == .needsStartScreen(.windDown))
    }

    @Test("Crossing bedtime: Counts until bed at 23:00")
    func crossesBedtime() {
        let start = model(minutes: 90, phase: .evening, now: at(2026, 10, 23, 22))
        #expect(start.countsLine == "Counts until bed at 23:00")
        #expect(start.leafMinute == 35)
        #expect(!start.capsuleIsDimmed)
        #expect(start.readiness == .needsStartScreen(.crossesBedtime))
        #expect(model(minutes: 90, phase: .evening, now: at(2026, 10, 23, 22), locale: enUS).countsLine == "Counts until bed at 11:00 PM")
    }

    @Test("After bedtime: this won't count, with no leaf dot")
    func afterBedtime() {
        let start = model(phase: .night, day: LocalDay(year: 2026, month: 10, day: 24), window: FocusFixtures.window(24),
                          now: at(2026, 10, 23, 23, 10))
        #expect(start.countsLine == "After bedtime · this won't count")
        #expect(start.leafMinute == nil)
        #expect(start.capsuleIsDimmed)
        #expect(start.readiness == .needsStartScreen(.windDown))
    }

    @Test("Today's cap reached: 6h counted today · more won't add")
    func capReached() {
        let start = model(displayToday: HoursCredit.dailyCap)
        #expect(start.countsLine == "6h counted today · more won't add")
        #expect(start.leafMinute == nil)
        #expect(start.readiness == .needsStartScreen(.capReached))
    }

    @Test("Display credit leaves less room: the leaf moves out of reach")
    func roomLeft() {
        let start = model(displayToday: HoursCredit.dailyCap - 20 * 60)
        #expect(start.leafMinute == nil)
        #expect(start.countsLine == "Counts toward Field maple · 35m to go")
        #expect(model(progress: nil).countsLine == nil)
        #expect(model(progress: nil).leafMinute == nil)
        let notHours = progressRow("buergerianum", .sessionsFinished, threshold: 1, current: 0, estimate: nil)
        #expect(model(progress: notHours).leafName == nil)
    }

    @Test("A session running, minimised: the dial can't turn, the lines hide, and the capsule returns to it")
    func running() {
        let start = model(stage: .running)
        #expect(start.capsuleTitle == "Return to session")
        #expect(start.primary == .returnToSession)
        #expect(!start.showsDetails)
        #expect(!start.canTurn)
        #expect(start.countsLine == nil)
        #expect(start.hint == nil)
        #expect(start.leafMinute == nil)
        #expect(!model(phase: .windDown, stage: .running).capsuleIsDimmed)
    }

    @Test("Locking: Locking 6 apps… until the read-back confirms the block")
    func locking() {
        let start = model(stage: .locking)
        #expect(start.capsuleTitle == "Locking 6 apps…")
        #expect(start.primary == .locking)
        #expect(!start.canTurn)
        #expect(start.showsDetails)
        #expect(start.hint == nil)
    }

    @Test("Shields couldn't be applied: the prompt offers a plain timer")
    func couldntLock() {
        #expect(FocusCopy.couldntLock == "Couldn't lock your apps · Start as a plain timer?")
        #expect(FocusCopy.startPlainTimer == "Start as a plain timer")
    }

    @Test("Without blocking: nothing to count, no Choose apps, and readiness sends Home to the Focus tab")
    func withoutBlocking() {
        let start = model(selection: nil, blocking: .needsPermission)
        #expect(start.capsuleTitle == "Start study · 50m")
        #expect(start.countsLine == nil)
        #expect(start.leafMinute == nil)
        #expect(start.readiness == .needsStartScreen(.blockingUnavailable))
        #expect(model(blocking: .notInThisBuild).readiness == .needsStartScreen(.blockingUnavailable))
    }

    @Test("Without blocking a start is a plain timer, so a Locked or Steady preset applies Gentle: one tap, no hold, no hint")
    func plainTimerStrictness() {
        for strictness in [Strictness.locked, .steady] {
            var preset = study
            preset.strictness = strictness
            for blocking in [FocusStatus.Blocking.needsPermission, .notInThisBuild] {
                let start = model(preset: preset, blocking: blocking)
                #expect(start.strictness == .gentle)
                #expect(start.primary == .start)
                #expect(start.capsuleTitle == "Start study · 50m")
                #expect(start.holdName == nil)
                #expect(start.plainTapHint == nil)
                // Home's Start reads the same model.
                let home = FocusStart(model: start)
                #expect(home.strictness == .gentle)
                #expect(!home.needsHold)
            }
            // With blocking, the session locks apps: its preset's own strictness applies, Locked's hold included.
            #expect(model(preset: preset).strictness == strictness)
        }
        var locked = study
        locked.strictness = .locked
        #expect(model(preset: locked).readiness == .ready(needsHold: true))
        #expect(ReceiptFlow.again(model(preset: locked).readiness) == .hold)
    }

    @Test("Home's Start is built from the same model, so a hold on one is a hold on the other")
    func homeAgrees() {
        var locked = study
        locked.strictness = .locked
        let ready = FocusStart(model: model(preset: locked))
        #expect(ready.presetID == locked.id)
        #expect(ready.verb == .study)
        #expect(ready.minutes == 50)
        #expect(ready.strictness == .locked)
        #expect(ready.readiness == .ready(needsHold: true))
        #expect(ready.needsHold)
        #expect(ready.title == "Hold to start · Locked 50m")
        #expect(NowState.Action.startFocus(ready).title == "Hold to start · Locked 50m")
        // In wind-down the start screen has something to say: Home's tap opens it, and the hold happens there.
        let windDown = model(preset: locked, phase: .windDown, now: at(2026, 10, 23, 22, 20))
        let home = FocusStart(model: windDown)
        #expect(home.readiness == .needsStartScreen(.windDown))
        #expect(!home.needsHold)
        #expect(home.title == "Start study · 50m")
        #expect(windDown.capsuleTitle == "Hold to start · 50m")
        let steady = FocusStart(model: model())
        #expect(steady.title == "Start study · 50m")
        #expect(!steady.needsHold)
    }
}
