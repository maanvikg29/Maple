import Foundation
import Testing
@testable import MapleCore
@testable import MapleFocusCore

@Suite("Session replay")
struct SessionRecordTests {
    private let start = at(2026, 10, 23, 14)

    /// Started at 14:00, with the block confirmed 5 seconds later.
    private func confirmed(plan: FocusPlan = FocusFixtures.plan()) -> SessionScript {
        let script = SessionScript(start: start, plan: plan)
        script.after(5, .shieldApplied)
        return script
    }

    @Test("Credit runs from the confirmed block to the last checkpoint, and the countdown starts at the block")
    func provenToEnd() throws {
        let script = confirmed()
        script.after(20 * 60, .shieldVerified)
        script.after(30 * 60, .sessionEnded(.completed, verified: true))
        let record = try #require(script.record)
        let applied = start.addingTimeInterval(5)
        #expect(record.countdownStart == applied)
        #expect(record.plannedEnd == applied.addingTimeInterval(3000))
        #expect(record.provenIntervals == [DateInterval(start: applied, end: applied.addingTimeInterval(3000))])
        #expect(record.endReason == .completed)
        #expect(record.endVerified)
        #expect(record.lastCheckpoint == applied.addingTimeInterval(3000))
    }

    @Test("A killed app reopened after the end credits up to the planned end")
    func reopenedLate() throws {
        let script = confirmed()
        script.after(2 * 3600, .shieldVerified)
        script.write(.sessionEnded(.completed, verified: true))
        let record = try #require(script.record)
        let applied = start.addingTimeInterval(5)
        #expect(record.provenIntervals == [DateInterval(start: applied, duration: 3000)])
    }

    @Test("Credit never crosses a boot: after a restart it starts again at the first read-back")
    func reboot() throws {
        let script = confirmed()
        script.after(10 * 60, .shieldVerified)                       // 14:10:05
        script.time.reboot("b2", wall: start.addingTimeInterval(12 * 60))
        script.after(60, .shieldVerified)                            // 14:13:00 in the new boot
        script.time.advance(37 * 60 + 5)                             // 14:50:05, the planned end
        script.write(.sessionEnded(.completed, verified: true))
        let record = try #require(script.record)
        let applied = start.addingTimeInterval(5)
        #expect(record.provenIntervals == [
            DateInterval(start: applied, end: applied.addingTimeInterval(600)),
            DateInterval(start: start.addingTimeInterval(13 * 60), end: applied.addingTimeInterval(3000)),
        ])
    }

    @Test("A failed read-back stops credit at the checkpoint before it")
    func lost() throws {
        let script = confirmed()
        script.after(10 * 60, .shieldVerified)
        script.after(10 * 60, .shieldLost)
        script.after(10 * 60, .shieldVerified)
        script.after(20 * 60, .sessionEnded(.completed, verified: true))
        let record = try #require(script.record)
        let applied = start.addingTimeInterval(5)
        #expect(record.provenIntervals == [DateInterval(start: applied, duration: 600)])
        #expect(record.lastCheckpoint == applied.addingTimeInterval(600))
        #expect(record.lostAt == applied.addingTimeInterval(1200))
        #expect(record.endReason == .completed)
        #expect(record.isEnded)
    }

    @Test("An event this build doesn't know, that affects credit, stops credit the same way")
    func unknownStops() throws {
        let script = confirmed()
        script.after(10 * 60, .shieldVerified)
        script.after(5 * 60, .unknown("phoneBreakStarted"))
        script.after(35 * 60, .sessionEnded(.completed, verified: true))
        let record = try #require(script.record)
        #expect(record.provenIntervals.map(\.duration) == [600])
    }

    @Test("Overrides are kept as whole windows")
    func overrides() throws {
        let script = confirmed()
        script.after(10 * 60, .overrideStarted(seconds: 60))
        script.after(2 * 60, .overrideEnded)
        script.after(38 * 60, .sessionEnded(.completed, verified: true))
        let record = try #require(script.record)
        let applied = start.addingTimeInterval(5)
        #expect(record.overrides == [DateInterval(start: applied.addingTimeInterval(600), duration: 120)])
        #expect(record.provenIntervals == [DateInterval(start: applied, duration: 3000)])
    }

    @Test("A break never moves the end, and a late break stops at it (F1-11)")
    func breakInside() throws {
        let script = confirmed()
        script.after(47 * 60, .breakStarted(seconds: 300))
        let record = try #require(script.record)
        let applied = start.addingTimeInterval(5)
        #expect(record.plannedEnd == applied.addingTimeInterval(3000))
        #expect(record.breakEnd(at: applied.addingTimeInterval(47 * 60 + 30)) == applied.addingTimeInterval(3000))
        #expect(record.breakUsed)
        script.after(60, .breakEnded)
        #expect(script.record?.breakEnd(at: applied.addingTimeInterval(48 * 60 + 30)) == nil)
    }

    @Test("Only the first end counts")
    func secondTerminal() throws {
        let script = confirmed()
        script.after(10 * 60, .sessionEnded(.endedEarly, verified: true))
        script.after(60, .sessionEnded(.completed, verified: true))
        let record = try #require(script.record)
        #expect(record.endReason == .endedEarly)
        #expect(record.provenIntervals.map(\.duration) == [600])
    }

    @Test("A plain timer has no proof, and its countdown starts at the tap")
    func plainTimer() throws {
        let script = SessionScript(start: start, plan: FocusFixtures.plan(kind: .plainTimer, selection: nil))
        script.after(50 * 60, .sessionEnded(.completed, verified: false))
        let record = try #require(script.record)
        #expect(record.provenIntervals.isEmpty)
        #expect(record.plannedEnd == start.addingTimeInterval(3000))
    }

    @Test("Reflections and hiding are read after the end without changing credit")
    func afterTheEnd() throws {
        let script = confirmed()
        script.after(50 * 60, .sessionEnded(.completed, verified: true))
        script.after(30, .reflected(.partly))
        script.after(30, .sessionHidden)
        let record = try #require(script.record)
        #expect(record.reflection == .partly)
        #expect(record.isHidden)
        #expect(record.provenIntervals.map(\.duration) == [3000])
    }

    @Test("Sessions come back in start order")
    func sessionsInOrder() {
        let a = SessionScript(start: at(2026, 10, 23, 9), session: UUID())
        let b = SessionScript(start: at(2026, 10, 23, 8), session: UUID(), time: ManualFocusTime(wall: at(2026, 10, 23, 8), boot: "b0"))
        let ledger = FocusLedger(a.events + b.events)
        #expect(ledger.sessions().map(\.id) == [b.session, a.session])
    }
}
