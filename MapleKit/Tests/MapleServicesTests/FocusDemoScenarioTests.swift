#if DEBUG
import Foundation
import MapleStorage
import Testing
@testable import MapleCore
@testable import MapleServices

@Suite("Demo Focus history")
struct DemoFocusHistoryTests {
    private let today = LocalDay(year: 2026, month: 10, day: 23)
    private let shipped = ShippedFeatures(releases: [.m1, .f1])

    private var standard: DemoData.FocusHistory {
        DemoData.FocusHistory(today: today, secondsBeforeToday: 65_100, runThroughYesterday: 11, bestRun: 21)
    }

    @Test("The history's finished days make a run of 11 through yesterday, 12 with today, and a best of 21")
    func runs() {
        let days = DemoData.focusDays(standard, calendar: utc)
        #expect(days.count == 31)
        #expect(days.allSatisfy { $0.frozen && $0.finished == 1 && $0.seconds == DemoData.focusDaySeconds && $0.zone == utc.timeZone.identifier })
        #expect(days.allSatisfy { $0.day < today })
        #expect(days.map(\.day) == days.map(\.day).sorted())
        // A rest day inside the current run, so the streak sheet's week shows a neutral dot.
        #expect(!days.contains { $0.day == today.adding(days: -4, calendar: utc) })
        let focusDays = days.map { (day: $0.day, zone: $0.zone) }
        let throughYesterday = FocusRuns(focusDays: focusDays, today: today)
        #expect(throughYesterday.current == 11)
        #expect(throughYesterday.best == 21)
        let withToday = FocusRuns(focusDays: focusDays + [(day: today, zone: utc.timeZone.identifier)], today: today)
        #expect(withToday.current == 12)
        #expect(withToday.best == 21)
    }

    @Test("A demo collection with a Focus history: counters, leaves and book agree, so nothing new unlocks")
    func collection() {
        let now = at(2026, 10, 23, 9)
        let snapshot = DemoData.snapshot(species: 23, tendedDays: 41, waiting: 0, now: now, calendar: utc, hemisphere: .northern,
                                         features: shipped, focusHistory: standard)
        #expect(snapshot.unlocks.count == 23)
        #expect(snapshot.counters[.hoursSaved] == 65_100.0 / 3600)
        #expect(snapshot.counters[.sessionsFinished] == 31)
        #expect(snapshot.counters[.focusStreak] == 21)
        #expect(snapshot.focus.totalSeconds == 65_100)
        #expect(snapshot.focus.totalFinished == 31)
        #expect(snapshot.focus.bestRun == 21)
        #expect(snapshot.focus.days.count == 31)
        for category in [RewardCategoryID.hoursSaved, .sessionsFinished, .focusStreak] {
            let rungs = RewardCatalog.shared.rungs(in: category)
            let earned = rungs.filter { rung in snapshot.unlocks.contains { $0.speciesID == rung.speciesID } }
            #expect(Array(rungs.prefix(earned.count)) == earned, "\(category)")
            let counter = snapshot.counters[category] ?? 0
            #expect(earned.last.map { $0.threshold <= counter } ?? false, "\(category)")
            #expect(rungs[earned.count].threshold > counter, "\(category)")
        }
        #expect(LeafEngine().newUnlocks(counters: snapshot.counters, existing: snapshot.unlocks, at: now, season: .autumn).isEmpty)
        let context = CollectionContext(schedule: .standard, features: shipped, calendar: utc, hemisphere: .northern)
        #expect(snapshot.currentRun(at: at(2026, 10, 23, 15), context: context) == 11)
    }

    @Test("A history with nothing in it earns no focus leaf and keeps an empty book")
    func nothing() {
        let empty = DemoData.FocusHistory(today: today, secondsBeforeToday: 0, runThroughYesterday: 0, bestRun: 0)
        let snapshot = DemoData.snapshot(species: 23, tendedDays: 41, waiting: 0, now: at(2026, 10, 23, 9), calendar: utc,
                                         hemisphere: .northern, features: shipped, focusHistory: empty)
        let focus: Set<RewardCategoryID> = [.hoursSaved, .sessionsFinished, .focusStreak]
        #expect(!snapshot.unlocks.contains { unlock in
            RewardCatalog.shared.reward(forSpecies: unlock.speciesID).map { focus.contains($0.categoryID) } ?? false
        })
        #expect(focus.allSatisfy { snapshot.counters[$0] == nil })
        #expect(snapshot.focus.days.isEmpty)
        #expect(snapshot.focus.totalSeconds == 0)
        #expect(snapshot.focus.bestRun == 0)
        #expect(snapshot.hasPlantedMaple)
    }
}

/// A Focus demo launch on Friday 23 October 2026 (UTC, the standard schedule, so the Day sample is 15:07) with F1
/// shipped, refreshed once as the app does at launch.
@MainActor
private func launch(_ arguments: [String]) async throws -> MapleStores {
    let stores = MapleStores.make(DemoLaunchOptions(arguments: ["-MapleDemoShip", "f1"] + arguments),
                                  directory: try temporaryDirectory(), calendar: utc, now: at(2026, 10, 23, 9))
    await stores.focus.sessions.refresh()
    return stores
}

@MainActor
private func demo(_ arguments: String...) async throws -> MapleStores {
    try await launch(arguments)
}

/// The 20-hour leaf the scenarios aim at.
private func twentyHoursLeaf() throws -> String {
    try #require(RewardCatalog.shared.rungs(in: .hoursSaved).first { $0.threshold == 20 }).speciesID
}

private func near(_ date: Date?, _ expected: Date, within seconds: TimeInterval = 3) -> Bool {
    date.map { abs($0.timeIntervalSince(expected)) < seconds } ?? false
}

@MainActor
private extension MapleStores {
    var now: Date { focus.sessions.now }
    var preview: PreviewBlockingService? { focus.sessions.blocking as? PreviewBlockingService }
    /// Today's Maple day.
    var today: LocalDay { collection.snapshot.focusWindow(at: now, context: collection.context).day }

    func session(_ id: UUID) -> SessionRecord? { focus.sessions.sessions.first { $0.id == id } }

    /// One session's credit, counted with every session of the replay (cap and overlap aware).
    func credit(_ id: UUID) -> SessionCredit? {
        HoursCredit.credit(focus.sessions.sessions, crediting: focus.mode.credited, now: now).first { $0.id == id }
    }

    /// Seconds still to count for the next hours leaf.
    var toNextHoursLeaf: Double? {
        collection.progress(at: now).filter { $0.category == .hoursSaved && $0.state == .locked }
            .min { $0.threshold < $1.threshold }.map { $0.remaining * 3600 }
    }
}

@Suite("Focus demo scenarios")
@MainActor
struct FocusDemoScenarioTests {
    @Test("One device, the writer's current boot: trusted time runs on from the ledger and agrees with the demo clock")
    func oneBoot() async throws {
        let stores = try await demo("-MapleDemoFocus", "running")
        let events = stores.focus.sessions.sessions.flatMap(\.events).map(\.event)
        #expect(events.count > 6)
        #expect(Set(events.map(\.deviceID)) == [FocusDemo.deviceID])
        let boot = try #require(LiveFocusTime(deviceID: FocusDemo.deviceID).boot)
        #expect(events.allSatisfy { $0.stamp.boot == boot })
        #expect(Set(events.map(\.seq)).count == events.count)
        #expect(events.allSatisfy { $0.source == .preview })
        let running = try #require(stores.focus.sessions.running)
        #expect(near(running.countdownStart, stores.now.addingTimeInterval(-18 * 60)))
        #expect(near(stores.now, stores.clock.now(), within: 1))
        #expect(near(stores.clock.now(), at(2026, 10, 23, 15, 7)))
    }

    @Test("Idle: a ready Study on six apps, two sessions today, a run of 12, a best of 21, the next leaf 35 minutes off")
    func idle() async throws {
        let stores = try await demo("-MapleDemoFocus", "idle")
        let sessions = stores.focus.sessions
        #expect(sessions.running == nil)
        #expect(sessions.lastEnded == nil)
        #expect(sessions.probe == .allowed)
        #expect(stores.collection.context.permissions.contains(.screenTime))
        #expect(sessions.sessions.map(\.id) == [FocusDemo.historyID(1), FocusDemo.historyID(2)])
        #expect(sessions.sessions.allSatisfy { $0.endReason == .completed && $0.endVerified })
        #expect(stores.focus.presets.lastUsed?.name == "Study")
        #expect(stores.focus.appSets.set(id: AppSet.distractionsID)?.summary
            == SelectionSummary(mode: .blockThese, apps: 6, sites: 0, categories: 0))
        #expect(stores.preview?.store == .empty)
        #expect(sessions.displayCredit(at: stores.now).today == 80 * 60)
        #expect(stores.collection.currentRun(at: stores.now) == 12)
        #expect(stores.collection.focus.bestRun == 21)
        let toLeaf = try #require(stores.toNextHoursLeaf)
        #expect(abs(toLeaf - 35 * 60) < 1)
        #expect(stores.collection.waiting.isEmpty)
        #expect(!stores.clock.isFixed)
    }

    @Test("App-set states: none chosen, a selection that doesn't qualify, apps that need choosing again")
    func appSets() async throws {
        let none = try await demo("-MapleDemoFocus", "noSet")
        #expect(none.focus.appSets.set(id: AppSet.distractionsID)?.summary.isEmpty == true)
        let small = try await demo("-MapleDemoFocus", "smallSet")
        let summary = try #require(small.focus.appSets.set(id: AppSet.distractionsID)?.summary)
        #expect(summary == SelectionSummary(mode: .onlyThese, apps: 24, sites: 0, categories: 0))
        #expect(!summary.qualifies)
        let expired = try await demo("-MapleDemoFocus", "expired")
        #expect(expired.focus.appSets.set(id: AppSet.distractionsID)?.tokensExpired == true)
        for stores in [none, small, expired] { #expect(stores.focus.sessions.running == nil) }
    }

    @Test("Running: Study at minute 18 of 50 on six apps, proven to 20 seconds ago, with its intention")
    func running() async throws {
        let stores = try await demo("-MapleDemoFocus", "running")
        let running = try #require(stores.focus.sessions.running)
        #expect(running.id == FocusDemo.subjectID)
        #expect(running.plan.presetName == "Study")
        #expect(running.plan.plannedSeconds == 50 * 60)
        #expect(running.plan.breakSeconds == FocusPreset.breakSeconds)
        #expect(running.plan.strictness == .steady)
        #expect(running.plan.kind == .blocking)
        #expect(running.plan.selection == SelectionSummary(mode: .blockThese, apps: 6, sites: 0, categories: 0))
        #expect(running.breaks.isEmpty)
        #expect(running.lostAt == nil)
        #expect(near(running.plannedEnd, stores.now.addingTimeInterval(32 * 60)))
        #expect(stores.preview?.store == .applied(session: running.id))
        let credit = try #require(stores.credit(running.id))
        #expect(abs(credit.seconds - (18 * 60 - 20)) <= 2)
        #expect(credit.stretches.last?.rule == .unconfirmed)
        #expect(stores.focus.notes.intention(for: running.id) == "Chemistry ch. 4")
        #expect(stores.focus.sessions.lastEnded == nil)
        #expect(stores.collection.currentRun(at: stores.now) == 12)
        let toLeaf = try #require(stores.toNextHoursLeaf)
        #expect(abs(toLeaf - Double(17 * 60 + 20)) <= 2)
    }

    @Test("Dimmed, minimised and end early run Steady; emergency runs Locked", arguments: [
        (FocusDemo.State.dimmed, Strictness.steady), (.minimised, .steady), (.endEarly, .steady), (.emergency, .locked),
    ])
    func runningVariants(state: FocusDemo.State, strictness: Strictness) async throws {
        let stores = try await demo("-MapleDemoFocus", state.rawValue)
        let running = try #require(stores.focus.sessions.running)
        #expect(running.id == FocusDemo.subjectID)
        #expect(running.plan.strictness == strictness)
        #expect(stores.focus.presets.lastUsed?.strictness == strictness)
    }

    @Test("End early takes Gentle when asked and never Locked; the emergency release is always Locked")
    func strictnessRules() async throws {
        let gentle = try await demo("-MapleDemoFocus", "endEarly", "-MapleDemoStrictness", "gentle")
        #expect(gentle.focus.sessions.running?.plan.strictness == .gentle)
        let locked = try await demo("-MapleDemoFocus", "endEarly", "-MapleDemoStrictness", "locked")
        #expect(locked.focus.sessions.running?.plan.strictness == .steady)
        let emergency = try await demo("-MapleDemoFocus", "emergency", "-MapleDemoStrictness", "gentle")
        #expect(emergency.focus.sessions.running?.plan.strictness == .locked)
        let countdown = try await demo("-MapleDemoEndCountdown", "9")
        #expect(countdown.focus.sessions.running?.plan.strictness == .steady)
    }

    @Test("Break: Study at minute 31, a minute into its break, with 4 minutes of it left")
    func breakTime() async throws {
        let stores = try await demo("-MapleDemoFocus", "break")
        let running = try #require(stores.focus.sessions.running)
        #expect(running.breaks.count == 1)
        #expect(near(running.breaks.first?.start, stores.now.addingTimeInterval(-60)))
        #expect(near(running.breakEnd(at: stores.now), stores.now.addingTimeInterval(4 * 60)))
        #expect(near(running.plannedEnd, stores.now.addingTimeInterval(19 * 60)))
    }

    @Test("Running past minute 35 has opened the next leaf mid-session")
    func leafMidSession() async throws {
        let stores = try await demo("-MapleDemoFocus", "running", "-MapleDemoFocusAt", "40")
        let running = try #require(stores.focus.sessions.running)
        let leaf = try twentyHoursLeaf()
        let unlock = try #require(stores.collection.unlocks.first { $0.speciesID == leaf })
        #expect(unlock.date >= running.countdownStart)
        #expect(unlock.date <= stores.now)
    }

    @Test("Ended: an on-time Study with one break, ended by the launch's refresh: 2h 10m today, the leaf 1h 10m off")
    func ended() async throws {
        for arguments in [["-MapleDemoFocus", "ended"], ["-MapleDemoReceipt", "clean"]] {
            let stores = try await launch(arguments)
            let sessions = stores.focus.sessions
            #expect(sessions.running == nil)
            let ended = try #require(sessions.lastEnded)
            #expect(ended.id == FocusDemo.subjectID)
            #expect(ended.endReason == .completed)
            #expect(ended.endVerified)
            #expect(ended.breaks.count == 1)
            #expect(near(ended.plannedEnd, stores.now.addingTimeInterval(-5)))
            let credit = try #require(stores.credit(ended.id))
            #expect(credit.seconds == 50 * 60)
            #expect(credit.finished)
            #expect(sessions.displayCredit(at: stores.now).today == 130 * 60)
            let toLeaf = try #require(stores.toNextHoursLeaf)
            #expect(abs(toLeaf - 70 * 60) < 1)
            #expect(stores.preview?.store == .empty)
            #expect(stores.collection.waiting.isEmpty)
        }
    }

    @Test("Ended away: the same session ended 2 hours before launch, and the launch's refresh records it")
    func endedAway() async throws {
        let stores = try await demo("-MapleDemoFocus", "endedAway")
        let ended = try #require(stores.focus.sessions.lastEnded)
        #expect(ended.id == FocusDemo.subjectID)
        #expect(ended.endReason == .completed)
        #expect(near(ended.plannedEnd, stores.now.addingTimeInterval(-2 * 3600)))
        #expect(near(ended.end?.placed, stores.now))
        #expect(stores.credit(ended.id)?.seconds == 50 * 60)
    }

    @Test("First: nothing ever focused: no sessions, no streak, no focus leaf, no last-used preset")
    func first() async throws {
        let stores = try await demo("-MapleDemoFocus", "first")
        #expect(stores.focus.sessions.sessions.isEmpty)
        #expect(stores.focus.sessions.probe == .allowed)
        #expect(stores.collection.focus.days.isEmpty)
        #expect(stores.collection.focus.totalSeconds == 0)
        #expect(stores.collection.focus.bestRun == 0)
        #expect(stores.collection.currentRun(at: stores.now) == 0)
        #expect((stores.collection.snapshot.counters[.hoursSaved] ?? 0) == 0)
        #expect(stores.focus.presets.lastUsedID == nil)
        #expect(stores.focus.appSets.set(id: AppSet.distractionsID)?.summary.qualifies == true)
    }

    @Test("Screen Time states set what the preview blocker answers", arguments: [
        (FocusDemo.ScreenTime.approved, BlockingProbe.allowed), (.notDetermined, .notDetermined), (.declined, .declined),
        (.restricted, .restricted), (.noPasscode, .noPasscode),
    ])
    func screenTime(value: FocusDemo.ScreenTime, probe: BlockingProbe) async throws {
        let stores = try await demo("-MapleDemoScreenTime", value.rawValue)
        #expect(stores.focus.sessions.probe == probe)
        #expect(stores.focus.sessions.running == nil)
        #expect(stores.collection.context.permissions.contains(.screenTime) == (probe == .allowed))
        #expect(stores.collection.context.blocking == .preview)
    }

    @Test("A free build: no blocker, Screen Time not in this build, no Focus history, and only plain timers")
    func freeBuild() async throws {
        let stores = try await demo("-MapleDemoScreenTime", "unavailable")
        #expect(stores.focus.sessions.blocking.capability == .unavailableInBuild)
        #expect(stores.focus.sessions.probe == .unavailable)
        #expect(stores.collection.context.blocking == .unavailableInBuild)
        #expect(stores.collection.availability(of: .hoursSaved) == .notInThisBuild)
        #expect(stores.collection.focus.totalSeconds == 0)
        #expect(stores.focus.sessions.sessions.isEmpty)
        let running = try await demo("-MapleDemoScreenTime", "unavailable", "-MapleDemoFocus", "running")
        #expect(running.focus.sessions.running?.plan.kind == .plainTimer)
    }

    @Test("Revoked: the running session lost its block at minute 10 and carries on as a plain timer")
    func revokedRunning() async throws {
        let stores = try await demo("-MapleDemoScreenTime", "revoked")
        let running = try #require(stores.focus.sessions.running)
        #expect(running.plan.kind == .blocking)
        #expect(running.lostAt != nil)
        #expect(near(running.lastCheckpoint, running.countdownStart.addingTimeInterval(10 * 60), within: 0.01))
        #expect(stores.focus.sessions.probe == .allowed)
        #expect(stores.preview?.failures.contains(.revoked) == true)
        #expect(stores.preview?.store == .empty)
        #expect(stores.credit(running.id)?.seconds == 10 * 60)
    }

    @Test("Plain: a plain timer runs while Screen Time is declined")
    func plainRunning() async throws {
        let stores = try await demo("-MapleDemoScreenTime", "plain")
        let running = try #require(stores.focus.sessions.running)
        #expect(running.plan.kind == .plainTimer)
        #expect(running.plan.selection == nil)
        #expect(running.applied == nil)
        #expect(stores.focus.sessions.probe == .declined)
        #expect(stores.credit(running.id)?.stretches.map(\.rule) == [.plainTimer])
        #expect(near(running.plannedEnd, stores.now.addingTimeInterval(32 * 60)))
    }

    @Test("Fail start: idle, with a blocker that fails every apply")
    func failStart() async throws {
        let stores = try await demo("-MapleDemoScreenTime", "failStart")
        #expect(stores.focus.sessions.running == nil)
        #expect(stores.preview?.failures == [.applyFails])
        let preset = try #require(stores.focus.presets.lastUsed)
        let request = FocusSessionStore.StartRequest(preset: preset, minutes: preset.minutes,
                                                     appSet: stores.focus.appSets.set(id: AppSet.distractionsID), from: .focusTab)
        #expect(await stores.focus.sessions.start(request) == .blockingFailed(.applyFailed))
    }

    @Test("Each receipt is a session that ended just now, with the credit its receipt describes",
          arguments: FocusDemo.Receipt.allCases)
    func receipts(receipt: FocusDemo.Receipt) async throws {
        let stores = try await demo("-MapleDemoReceipt", receipt.rawValue)
        let sessions = stores.focus.sessions
        #expect(sessions.running == nil)
        let subject = try #require(stores.session(FocusDemo.subjectID))
        let end = try #require(subject.end?.placed)
        #expect((sessions.lastEnded?.id == subject.id) == (receipt != .early))
        let credit = try #require(stores.credit(subject.id))
        let rules = Set(credit.stretches.compactMap(\.rule))
        let leaf = try twentyHoursLeaf()
        let opened = stores.collection.unlocks.first { $0.speciesID == leaf }
        switch receipt {
        case .clean:
            #expect(subject.breaks.count == 1)
            #expect(credit.seconds == 50 * 60)
            #expect(rules.isEmpty)
        case .unlocked:
            #expect(subject.overrides.count == 1)
            #expect(credit.seconds == 45 * 60)
            #expect(rules == [.override])
        case .early:
            #expect(subject.endReason == .endedEarly)
            #expect(near(end, subject.countdownStart.addingTimeInterval(18 * 60)))
            #expect(credit.seconds == 18 * 60)
            #expect(!credit.finished)
        case .plain:
            #expect(subject.plan.kind == .plainTimer)
            #expect(credit.seconds == 0)
            #expect(rules == [.plainTimer])
        case .revoked:
            #expect(subject.lostAt != nil)
            #expect(near(subject.lastCheckpoint, subject.countdownStart.addingTimeInterval(10 * 60), within: 0.01))
            #expect(!subject.endVerified)
            #expect(credit.seconds == 10 * 60)
            #expect(rules == [.unconfirmed])
        case .bedtime:
            let bedtime = PhaseWindows(schedule: .standard).day(LocalDay(year: 2026, month: 10, day: 23), calendar: utc).night
            #expect(subject.countdownStart > bedtime)
            #expect(credit.seconds == 0)
            #expect(rules == [.beforeMorning])
        case .capped:
            #expect(credit.seconds == 0)
            #expect(rules == [.dailyCap])
            #expect(stores.collection.focus.seconds(on: stores.today) == HoursCredit.dailyCap)
        case .leaf, .leafNight:
            let unlock = try #require(opened)
            #expect(unlock.date >= subject.countdownStart && unlock.date <= end)
            let held = stores.collection.held(at: stores.now).contains { $0.speciesID == leaf }
            #expect(held == (receipt == .leafNight))
        case .notQualifying:
            #expect(subject.plan.selection?.qualifies == false)
            #expect(credit.seconds == 0)
            #expect(rules == [.notQualifying])
        }
        if receipt != .leaf, receipt != .leafNight { #expect(opened == nil) }
    }

    @Test("Saved today: typical has a session with an unlock; capped passes 6 hours; empty has nothing and no streak")
    func saved() async throws {
        let typical = try await demo("-MapleDemoSaved", "typical")
        let study = try #require(typical.credit(FocusDemo.historyID(1)))
        let read = try #require(typical.credit(FocusDemo.historyID(2)))
        #expect(study.seconds == 50 * 60)
        #expect(typical.session(FocusDemo.historyID(1))?.breaks.count == 1)
        #expect(read.seconds == 30 * 60)
        #expect(read.stretches.contains { $0.rule == .override && abs($0.interval.duration - 300) < 0.01 })
        #expect(typical.focus.notes.intention(for: FocusDemo.historyID(2)) == "Essay")
        #expect(typical.focus.sessions.reflections[FocusDemo.historyID(2)] == .partly)
        #expect(typical.focus.sessions.reflections[FocusDemo.historyID(1)] == .allDone)

        let capped = try await demo("-MapleDemoSaved", "capped")
        #expect(capped.focus.sessions.sessions.count == 4)
        #expect(capped.collection.focus.seconds(on: capped.today) == HoursCredit.dailyCap)
        let over = try #require(capped.credit(FocusDemo.historyID(4)))
        #expect(over.seconds == 0)
        #expect(Set(over.stretches.compactMap(\.rule)) == [.dailyCap])

        let empty = try await demo("-MapleDemoSaved", "empty")
        #expect(empty.focus.sessions.sessions.isEmpty)
        #expect(empty.collection.focus.days.isEmpty)
        #expect(empty.collection.focus.bestRun == 0)
        #expect(empty.collection.currentRun(at: empty.now) == 0)
        // A lifetime total still: "saved in all · none yet today" (F1-25).
        #expect(empty.collection.focus.totalSeconds > 0)
        let toLeaf = try #require(empty.toNextHoursLeaf)
        #expect(abs(toLeaf - 35 * 60) < 1)
    }

    @Test("-MapleDemoPreset, -MapleDemoStrictness and -MapleDemoIntention reach the preset and the session")
    func choices() async throws {
        let quick = try await demo("-MapleDemoFocus", "running", "-MapleDemoPreset", "quick", "-MapleDemoStrictness", "locked",
                                   "-MapleDemoIntention", "Essay draft")
        let running = try #require(quick.focus.sessions.running)
        #expect(running.plan.verb == .quick)
        #expect(running.plan.plannedSeconds == 25 * 60)
        #expect(running.plan.breakSeconds == 0)
        #expect(running.plan.strictness == .locked)
        #expect(quick.focus.presets.lastUsed?.verb == .quick)
        #expect(quick.focus.presets.lastUsed?.strictness == .locked)
        #expect(quick.focus.notes.intention(for: running.id) == "Essay draft")
        let none = try await demo("-MapleDemoFocus", "running", "-MapleDemoIntention", "")
        #expect(none.focus.notes.intention(for: FocusDemo.subjectID) == nil)
        let idle = try await demo("-MapleDemoStrictness", "gentle")
        #expect(idle.focus.presets.lastUsed?.strictness == .gentle)
        #expect(idle.focus.sessions.running == nil)
    }

    @Test("Live Activity and frozen-finish arguments imply their session")
    func implied() async throws {
        let running = try await demo("-MapleDemoLiveActivity", "running")
        #expect(running.focus.sessions.running?.plan.kind == .blocking)
        let inBreak = try await demo("-MapleDemoLiveActivity", "break")
        #expect(inBreak.focus.sessions.running?.breakEnd(at: inBreak.now) != nil)
        let plain = try await demo("-MapleDemoLiveActivity", "plain")
        #expect(plain.focus.sessions.running?.plan.kind == .plainTimer)
        let ended = try await demo("-MapleDemoLiveActivity", "ended")
        #expect(ended.focus.sessions.lastEnded?.endReason == .completed)
        let finish = try await demo("-MapleDemoFinishAt", "0.5")
        #expect(finish.focus.sessions.lastEnded?.id == FocusDemo.subjectID)
    }

    @Test("A fresh first run seeds nothing, and a launch with no Focus argument starts empty")
    func unseeded() async throws {
        let fresh = MapleStores.make(DemoLaunchOptions(arguments: ["-MapleDemoShip", "f1", "-MapleDemoFresh", "YES"]),
                                     directory: try temporaryDirectory(), calendar: utc, now: at(2026, 10, 23, 9))
        await fresh.focus.sessions.refresh()
        #expect(fresh.focus.sessions.sessions.isEmpty)
        let plain = MapleStores.make(DemoLaunchOptions(arguments: ["-MapleDemoSpecies", "23"]),
                                     directory: try temporaryDirectory(), calendar: utc, now: at(2026, 10, 23, 9))
        await plain.focus.sessions.refresh()
        #expect(plain.focus.sessions.sessions.isEmpty)
        #expect(plain.focus.appSets.set(id: AppSet.distractionsID)?.summary.isEmpty == true)
        #expect(plain.preview?.store == .empty)
    }
}
#endif
