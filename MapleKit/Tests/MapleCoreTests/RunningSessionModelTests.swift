import Foundation
import Testing
@testable import MapleCore
@testable import MapleFocusCore

/// The running session screen's words and decisions (F1 design §4.3, §4.9, §5.4).
@Suite("Running session screen")
struct RunningSessionModelTests {
    /// 14:00. The block is confirmed at 14:00:05, so a 50-minute session ends at 14:50:05.
    private static let start = at(2026, 10, 23, 14)
    /// The next hours leaf, 0.7 of its 1-hour rung on the counters: with a minute of provisional time, 17 minutes to go.
    private static let fieldMaple = RunningSessionModel.Leaf(
        speciesID: "campestre", name: "Field maple", floor: 0, threshold: 1, current: 0.7
    )

    /// A session on `FocusFixtures.plan`; a blocking one has its block confirmed 5 seconds after the tap.
    private func record(
        minutes: Int = 50, breakMinutes: Int = 0, strictness: Strictness = .steady, kind: SessionKind = .blocking,
        _ more: (SessionScript) -> Void = { _ in }
    ) throws -> SessionRecord {
        let plan = FocusFixtures.plan(minutes: minutes, breakMinutes: breakMinutes, strictness: strictness, kind: kind,
                                      selection: kind == .plainTimer ? nil : FocusFixtures.blockSix)
        let script = SessionScript(start: Self.start, plan: plan)
        if kind == .blocking { script.after(5, .shieldApplied) }
        more(script)
        return try #require(script.record)
    }

    /// The screen `minute` minutes into the countdown: 17 minutes counted, 18 shown.
    private func model(
        _ session: SessionRecord, at minute: Double, leaf: RunningSessionModel.Leaf? = RunningSessionModelTests.fieldMaple,
        opened: [RunningSessionModel.Opened] = [], counted: Int = 17 * 60, display: Int = 18 * 60, first: Bool = false,
        intention: String? = "Chemistry ch. 4"
    ) -> RunningSessionModel {
        RunningSessionModel(
            session: session, now: session.countdownStart.addingTimeInterval(minute * 60), intention: intention, leaf: leaf,
            opened: opened, countedSeconds: counted, displaySeconds: display, roomLeftToday: HoursCredit.dailyCap - display,
            isFirstSession: first, locale: enGB
        )
    }

    @Test("Minute 18 of 50: the header, 32m left of 50m, and the leaf 17 minutes away at minute 35")
    func running() throws {
        let screen = model(try record(), at: 18)
        #expect(screen.title == "Study · Chemistry ch. 4")
        #expect(screen.restingLine == "6 apps resting")
        #expect(screen.remaining == "32m")
        #expect(screen.caption == "left of 50m")
        #expect(screen.timeLine == "32m left of 50m")
        #expect(screen.centreLeaf == "campestre")
        #expect(screen.leafLine == RunningSessionModel.Line(lead: "Field maple", trail: "· 17m to go"))
        #expect(screen.leafLine?.text == "Field maple · 17m to go")
        #expect(screen.leafMinute == 35)
        #expect(!screen.leafOpened)
        #expect(screen.spoken == "32 minutes left of 50. Field maple at minute 35.")
        #expect(screen.leafAnnouncement == nil)
        #expect(screen.firstSessionLine == nil)
        #expect(screen.breakTitle == nil)
        #expect(screen.endPath == .steady)
        #expect(screen.endPath.title == "End early")
        #expect(model(try record(), at: 18, intention: nil).title == "Study")
    }

    @Test("The centre leaf fills softer for the time saved before this session, brighter for this session's share")
    func fill() throws {
        let screen = model(try record(), at: 18)
        #expect(abs(screen.fillBefore - (0.7 - 17.0 / 60)) < 1e-9)
        #expect(abs(screen.fillSession - 18.0 / 60) < 1e-9)
        let rung = RunningSessionModel.Leaf(speciesID: "saccharinum", name: "Silver maple", floor: 1, threshold: 3, current: 2)
        let higher = model(try record(), at: 18, leaf: rung, counted: 0, display: 0)
        #expect(abs(higher.fillBefore - 0.5) < 1e-9)
        #expect(higher.fillSession == 0)
    }

    @Test("Seconds only in the last minute, and a long session's length reads as a plain minute count")
    func time() throws {
        let last = model(try record(), at: 49.25)
        #expect(last.remaining == "0:45")
        #expect(last.spoken.hasPrefix("45 seconds left of 50."))
        let long = model(try record(minutes: 90), at: 18)
        #expect(long.caption == "left of 1h 30m")
        #expect(long.remaining == "1h 12m")
        let spokenLeft = FocusTimeText.spokenRemaining(72 * 60, locale: enGB)
        #expect(long.spoken.hasPrefix("\(spokenLeft) of 90."))
    }

    @Test("A plain timer and a lost block run on without counting: no leaf, no leaf line and no dot")
    func notCounting() throws {
        let plain = model(try record(kind: .plainTimer), at: 18, counted: 0, display: 0)
        #expect(plain.restingLine == "Plain timer · apps aren't locked")
        #expect(plain.centreLeaf == nil)
        #expect(plain.leafLine == nil)
        #expect(plain.leafMinute == nil)
        #expect(plain.spoken == "32 minutes left of 50.")
        let lost = model(try record { $0.after(10 * 60, .shieldLost) }, at: 18, counted: 10 * 60, display: 10 * 60)
        #expect(lost.restingLine == "Plain timer · apps aren't locked")
        #expect(lost.centreLeaf == nil)
        #expect(lost.leafLine == nil)
        #expect(lost.leafMinute == nil)
        let allEarned = model(try record(), at: 18, leaf: nil)
        #expect(allEarned.centreLeaf == nil)
        #expect(allEarned.leafLine == nil)
        #expect(allEarned.spoken == "32 minutes left of 50.")
    }

    @Test("Once a checkpoint opens the leaf, the line says so, and the dot stays where it opened")
    func opened() throws {
        let session = try record()
        let field = RunningSessionModel.Opened(speciesID: "campestre", name: "Field maple", minute: 35, heldUntilMorning: false)
        let screen = model(session, at: 36, opened: [field])
        #expect(screen.leafOpened)
        #expect(screen.centreLeaf == "campestre")
        #expect(screen.leafLine == RunningSessionModel.Line(lead: "Field maple is yours · it opens after this session"))
        #expect(screen.leafMinute == 35)
        #expect(screen.fillBefore == 1 && screen.fillSession == 0)
        #expect(screen.leafAnnouncement == "Field maple is yours. It opens after this session.")
        #expect(screen.spoken == "14 minutes left of 50.")
        let held = RunningSessionModel.Opened(speciesID: "campestre", name: "Field maple", minute: 35, heldUntilMorning: true)
        #expect(model(session, at: 36, opened: [held]).leafLine?.lead == "Field maple is yours · it opens in the morning")
        #expect(model(session, at: 36, opened: [held]).leafAnnouncement == "Field maple is yours. It opens in the morning.")
        let silver = RunningSessionModel.Opened(speciesID: "saccharinum", name: "Silver maple", minute: 44, heldUntilMorning: false)
        #expect(model(session, at: 45, opened: [field, silver]).leafLine?.lead == "2 new leaves are yours")
    }

    @Test("The opened leaves are this session's hours leaves, at the minute each opened")
    func openedLeaves() throws {
        let session = try record()
        let hours = species(.hoursSaved, rung: 0)
        let night = species(.restedNights, rung: 0)
        let unlocks = [
            LeafUnlock(speciesID: night, date: session.countdownStart.addingTimeInterval(60), season: .autumn, colourway: .autumn),
            LeafUnlock(speciesID: hours, date: session.countdownStart.addingTimeInterval(34 * 60 + 30), season: .autumn,
                       colourway: .autumn),
        ]
        let opened = RunningSessionModel.opened(unlocks, session: session, held: { _ in false })
        #expect(opened.map(\.speciesID) == [hours])
        #expect(opened.first?.minute == 35)
        #expect(opened.first?.name == LeafCatalog.shared.species(id: hours)?.displayName)
        #expect(RunningSessionModel.opened(unlocks, session: session, held: { _ in true }).first?.heldUntilMorning == true)
    }

    @Test("The next leaf is the lowest locked hours rung")
    func nextLeaf() throws {
        let hours = species(.hoursSaved, rung: 0)
        let rows = [
            progressRow(species(.restedNights, rung: 0), .restedNights, threshold: 3, current: 1, estimate: nil),
            progressRow(species(.hoursSaved, rung: 1), .hoursSaved, threshold: 3, current: 0.7, estimate: nil),
            progressRow(hours, .hoursSaved, threshold: 1, current: 0.7, estimate: nil),
        ]
        let leaf = try #require(RunningSessionModel.Leaf(next: rows))
        #expect(leaf.speciesID == hours)
        #expect(leaf.threshold == 1 && leaf.current == 0.7 && leaf.floor == 0)
        #expect(RunningSessionModel.Leaf(next: [rows[0]]) == nil)
    }

    @Test("Provisional time that covers the rest never reads 0m to go: the leaf waits for a checkpoint")
    func waitingForCheckpoint() throws {
        let nearly = RunningSessionModel.Leaf(speciesID: "campestre", name: "Field maple", floor: 0, threshold: 1, current: 0.99)
        let screen = model(try record(), at: 18, leaf: nearly, counted: 0, display: 300)
        #expect(screen.leafLine?.trail == "· 1m to go")
        #expect(!screen.leafOpened)
    }

    @Test("The first session's line, the preset's break, and each strictness's way out")
    func controls() throws {
        #expect(model(try record(), at: 18, first: true).firstSessionLine == "You can lock your phone. Maple keeps time.")
        #expect(model(try record(breakMinutes: 5), at: 18).breakTitle == "Take a break")
        let used = try record(breakMinutes: 5) {
            $0.after(10 * 60, .breakStarted(seconds: 300))
            $0.after(60, .breakEnded)
        }
        #expect(model(used, at: 18).breakTitle == nil)
        #expect(model(try record(breakMinutes: 5), at: 50).breakTitle == nil)
        let locked = model(try record(strictness: .locked), at: 18).endPath
        #expect(locked == .emergency)
        #expect(locked.title == "Emergency release")
        #expect(locked.reason == .emergencyRelease)
        #expect(SessionEndPath(.gentle) == .gentle)
        #expect(SessionEndPath(.gentle).title == "End early")
        #expect(SessionEndPath(.gentle).reason == .endedEarly)
        #expect(SessionEndPath(.steady).reason == .endedEarly)
        #expect(RunningSessionModel.minimiseLabel == "Minimise session")
    }

    @Test("Only the member's first session ever shows the first-session line")
    func firstSession() throws {
        let session = try record()
        #expect(RunningSessionModel.isFirstSession(session, among: [session], book: FocusBook()))
        let earlier = try #require(SessionScript(
            start: at(2026, 10, 22, 9), session: UUID(uuidString: "00000000-0000-4000-8000-0000000000A2")!
        ).record)
        #expect(!RunningSessionModel.isFirstSession(session, among: [earlier, session], book: FocusBook()))
        #expect(!RunningSessionModel.isFirstSession(session, among: [session],
                                                    book: FocusBook(baseline: FocusTotals(seconds: 3600, finished: 1))))
        let yesterday = DayCredit(day: LocalDay(year: 2026, month: 10, day: 22), zone: "UTC", firstCountedAt: at(2026, 10, 22, 15),
                                  dayEnd: at(2026, 10, 22, 23))
        #expect(!RunningSessionModel.isFirstSession(session, among: [session], book: FocusBook(days: [yesterday])))
        let today = DayCredit(day: LocalDay(year: 2026, month: 10, day: 23), zone: "UTC", firstCountedAt: at(2026, 10, 23, 14, 10),
                              dayEnd: at(2026, 10, 23, 23))
        #expect(RunningSessionModel.isFirstSession(session, among: [session], book: FocusBook(days: [today])))
    }
}

/// The break screen (F1 design §5.5, §4.9).
@Suite("Break screen")
struct BreakScreenModelTests {
    private static let start = at(2026, 10, 23, 14)

    /// A 50-minute Study with its 5-minute break; the block confirmed at 14:00:05, the break taken `minute` minutes in.
    private func record(breakAt minute: Double = 18, seconds: Int = 300, _ more: (SessionScript) -> Void = { _ in }) throws -> SessionRecord {
        let script = SessionScript(start: Self.start, plan: FocusFixtures.plan(minutes: 50, breakMinutes: 5))
        script.after(5, .shieldApplied)
        script.after(minute * 60, .breakStarted(seconds: seconds))
        more(script)
        return try #require(script.record)
    }

    private func model(_ session: SessionRecord, after seconds: TimeInterval) -> BreakScreenModel? {
        let breakStart = session.breaks.last?.start ?? session.countdownStart
        return BreakScreenModel(session: session, now: breakStart.addingTimeInterval(seconds), intention: "Chemistry ch. 4",
                                locale: enGB, calendar: utc)
    }

    @Test("A minute into the break: 4m left of your break, and back to studying at 14:23")
    func breakTime() throws {
        let screen = try #require(model(try record(), after: 60))
        #expect(BreakScreenModel.endedAnnouncement == "Back to studying.")
        #expect(screen.subtitle == "Study · Chemistry ch. 4")
        #expect(screen.remaining == "4m")
        #expect(screen.timeLine == "4m left of your break")
        #expect(screen.breakSeconds == 300)
        #expect(screen.backLine == "The break counts. Back to studying at 14:23.")
        #expect(screen.spoken == "4 minutes of break left. Back to studying at 14:23.")
        #expect(screen.endPath == .steady)
    }

    @Test("The suggestion rotates through the break, one at a time")
    func suggestion() throws {
        let session = try record()
        #expect(try #require(model(session, after: 10)).suggestion == "Stand up and stretch.")
        #expect(try #require(model(session, after: 150)).suggestion == "Look out of a window.")
        #expect(try #require(model(session, after: 250)).suggestion == "Get a glass of water.")
    }

    @Test("A break near the end is cut short at the planned end")
    func cutShort() throws {
        let session = try record(breakAt: 47, seconds: 180)
        let screen = try #require(model(session, after: 30))
        #expect(screen.breakSeconds == 180)
        #expect(screen.remaining == "3m")
        #expect(screen.backLine == "The break counts. Back to studying at 14:50.")
    }

    @Test("No break screen before the break, once it ran out, or after Back to studying")
    func noBreak() throws {
        let session = try record()
        // Before the break: a record that doesn't hold it yet.
        let unbroken = SessionScript(start: Self.start, plan: FocusFixtures.plan(minutes: 50, breakMinutes: 5))
        unbroken.after(5, .shieldApplied)
        let before = try #require(unbroken.record)
        #expect(BreakScreenModel(session: before, now: before.countdownStart.addingTimeInterval(60), intention: nil,
                                 locale: enGB, calendar: utc) == nil)
        #expect(model(session, after: 300) == nil)
        let back = try record { $0.after(120, .breakEnded) }
        #expect(model(back, after: 130) == nil)
    }

    @Test("The session screen returns with a haptic only when the break runs out in front of the member")
    func ranOut() throws {
        let session = try record()
        let end = session.countdownStart.addingTimeInterval(18 * 60 + 300)
        #expect(BreakScreenModel.ranOutJustNow(session, at: end.addingTimeInterval(0.5)))
        #expect(!BreakScreenModel.ranOutJustNow(session, at: end.addingTimeInterval(-1)))
        // Back from the background long after it ran out: no haptic.
        #expect(!BreakScreenModel.ranOutJustNow(session, at: end.addingTimeInterval(10)))
        let back = try record { $0.after(120, .breakEnded) }
        #expect(!BreakScreenModel.ranOutJustNow(back, at: end.addingTimeInterval(0.5)))
        // A break cut short at the planned end ends with the session: the finish has its own haptic.
        let last = try record(breakAt: 47, seconds: 180)
        #expect(!BreakScreenModel.ranOutJustNow(last, at: last.plannedEnd.addingTimeInterval(0.5)))
    }
}

/// Dimming the running screen (F1 design §4.6).
@Suite("Focus dimming")
struct FocusDimmingTests {
    @Test("After 30 seconds without a touch, and never under VoiceOver or Increase Contrast")
    func dims() {
        #expect(!FocusDimming.isDimmed(idleFor: 29.9, voiceOver: false, increasedContrast: false))
        #expect(FocusDimming.isDimmed(idleFor: 30, voiceOver: false, increasedContrast: false))
        #expect(!FocusDimming.isDimmed(idleFor: 600, voiceOver: true, increasedContrast: false))
        #expect(!FocusDimming.isDimmed(idleFor: 600, voiceOver: false, increasedContrast: true))
    }
}
