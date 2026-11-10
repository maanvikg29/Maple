import Foundation
import Testing
@testable import MapleCore
@testable import MapleFocusCore

/// The receipt's flow around `ReceiptModel` (F1 design §5.8, F1-20).
@Suite("Receipt flow")
struct ReceiptFlowTests {
    /// A 50-minute Study from 14:00, its block confirmed at 14:00:05, ended on time at 14:50:05.
    private func ended() throws -> SessionRecord {
        let script = SessionScript(start: at(2026, 10, 23, 14), plan: FocusFixtures.plan())
        script.after(5, .shieldApplied)
        script.after(50 * 60, .sessionEnded(.completed, verified: true))
        return try #require(script.record)
    }

    private func unlock(_ species: String, at date: Date) -> LeafUnlock {
        LeafUnlock(speciesID: species, date: date, season: .autumn, colourway: .autumn)
    }

    @Test("Again starts at once, takes a hold in Locked, or opens the start screen when it has something to say")
    func again() {
        #expect(ReceiptFlow.again(.ready(needsHold: false)) == .start)
        #expect(ReceiptFlow.again(.ready(needsHold: true)) == .hold)
        #expect(ReceiptFlow.again(.needsStartScreen(.windDown)) == .openStartScreen)
        #expect(ReceiptFlow.again(.needsStartScreen(.expiredTokens)) == .openStartScreen)
    }

    @Test("Partly and Not yet carry the intention into Again; All done drops it")
    func intention() {
        #expect(ReceiptFlow.againIntention("Chemistry ch. 4", reflection: nil) == "Chemistry ch. 4")
        #expect(ReceiptFlow.againIntention("Chemistry ch. 4", reflection: .partly) == "Chemistry ch. 4")
        #expect(ReceiptFlow.againIntention("Chemistry ch. 4", reflection: .notYet) == "Chemistry ch. 4")
        #expect(ReceiptFlow.againIntention("Chemistry ch. 4", reflection: .allDone) == nil)
        #expect(ReceiptFlow.againIntention("   ", reflection: .partly) == nil)
        #expect(ReceiptFlow.againIntention(nil, reflection: .notYet) == nil)
    }

    @Test("The leaves this session opened: its own store unlocks, plus Focus leaves dated inside it")
    func unlocks() throws {
        let session = try ended()
        let hours = species(.hoursSaved, rung: 0)
        let finished = species(.sessionsFinished, rung: 0)
        let night = species(.restedNights, rung: 0)
        let fromStore = [unlock(hours, at: session.countdownStart.addingTimeInterval(35 * 60))]
        let collection = [
            unlock(hours, at: session.countdownStart.addingTimeInterval(35 * 60)),
            unlock(finished, at: session.plannedEnd),
            unlock(night, at: session.countdownStart.addingTimeInterval(10 * 60)),
            unlock(species(.hoursSaved, rung: 1), at: session.countdownStart.addingTimeInterval(-60)),
        ]
        let both = ReceiptFlow.unlocks(store: fromStore, storeSession: session.id, collection: collection, session: session)
        #expect(both.map(\.speciesID) == [hours, finished])
        // Another session's store unlocks are left out; the collection still names this one's.
        let other = ReceiptFlow.unlocks(store: [unlock(night, at: session.plannedEnd)], storeSession: UUID(),
                                        collection: collection, session: session)
        #expect(other.map(\.speciesID) == [hours, finished])
        #expect(ReceiptFlow.unlocks(store: [], storeSession: nil, collection: [], session: session).isEmpty)
    }

    @Test("An end noticed 40 s late still names the focus-streak leaf its refresh dated, and nothing after it")
    func lateEnd() throws {
        // The planned end is 14:50:05; the refresh that noticed it 40 s later dated the streak leaf at its own now, a
        // moment before it wrote the end. The receipt shows the planned end (`endedAt`), but the leaf is still this
        // session's.
        let script = SessionScript(start: at(2026, 10, 23, 14), plan: FocusFixtures.plan())
        script.after(5, .shieldApplied)
        script.after(50 * 60 + 40, .sessionEnded(.completed, verified: true))
        let session = try #require(script.record)
        let noticed = try #require(session.end?.placed)
        #expect(session.endedAt == session.plannedEnd)
        #expect(abs(noticed.timeIntervalSince(session.plannedEnd) - 40) < 0.001)
        let streak = species(.focusStreak, rung: 0)
        let later = species(.sessionsFinished, rung: 1)
        let collection = [
            unlock(streak, at: noticed.addingTimeInterval(-0.2)),
            unlock(later, at: noticed.addingTimeInterval(5 * 60)),
        ]
        let named = ReceiptFlow.unlocks(store: [], storeSession: nil, collection: collection, session: session)
        #expect(named.map(\.speciesID) == [streak])
    }

    @Test("The centre leaf: the hours leaf this session opened, else the next one, and none when it couldn't count")
    func centreLeaf() throws {
        let session = try ended()
        let hours = species(.hoursSaved, rung: 0)
        let finished = species(.sessionsFinished, rung: 0)
        let nextRung = species(.hoursSaved, rung: 1)
        let next = progressRow(nextRung, .hoursSaved, threshold: 3, current: 1.2, estimate: nil)
        let both = [unlock(finished, at: session.plannedEnd), unlock(hours, at: session.plannedEnd)]
        #expect(ReceiptFlow.centreLeaf(unlocks: both, next: next, canCount: true)
            == ReceiptFlow.CentreLeaf(speciesID: hours, opened: true))
        #expect(ReceiptFlow.centreLeaf(unlocks: [unlock(finished, at: session.plannedEnd)], next: next, canCount: true)
            == ReceiptFlow.CentreLeaf(speciesID: nextRung, opened: false))
        #expect(ReceiptFlow.centreLeaf(unlocks: [], next: nil, canCount: true) == nil)
        #expect(ReceiptFlow.centreLeaf(unlocks: both, next: next, canCount: false) == nil)
        let nights = progressRow(species(.restedNights, rung: 0), .restedNights, threshold: 3, estimate: nil)
        #expect(ReceiptFlow.centreLeaf(unlocks: [], next: nights, canCount: true) == nil)
    }

    @Test("Only a single opened leaf can be held until morning")
    func held() throws {
        let session = try ended()
        let schedule = WeeklySleepSchedule.standard
        let one = [unlock(species(.hoursSaved, rung: 0), at: session.plannedEnd)]
        // 14:50 is daytime: nothing waits for the morning.
        #expect(!ReceiptFlow.heldUntilMorning(one, schedule: schedule, calendar: utc, at: session.plannedEnd))
        #expect(!ReceiptFlow.heldUntilMorning([], schedule: schedule, calendar: utc, at: session.plannedEnd))
        // 22:30 is wind-down (bed at 23:00): the leaf opens in the morning.
        let late = at(2026, 10, 23, 22, 30)
        let windDown = [unlock(species(.hoursSaved, rung: 0), at: late)]
        #expect(ReceiptFlow.heldUntilMorning(windDown, schedule: schedule, calendar: utc, at: late.addingTimeInterval(60)))
        let two = windDown + [unlock(species(.sessionsFinished, rung: 0), at: late)]
        #expect(!ReceiptFlow.heldUntilMorning(two, schedule: schedule, calendar: utc, at: late.addingTimeInterval(60)))
    }
}
