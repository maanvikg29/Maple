import Foundation
import Testing
@testable import MapleCore
@testable import MapleFocusCore

/// Sessions written the way the app writes them, on one clock, for the leaf rules. Add them in time order.
private final class EarningsFixture {
    private let clock = FocusDay(at(2026, 11, 1, 6))
    private var count = 0

    /// A session on `day` November 2026 at `hour`:00, `planned` minutes long. It runs its whole length and completes,
    /// or stops at `ranSeconds`, ended before its timer ran out for `reason`. A blocking session is confirmed half-way,
    /// so it counts as saved; with `confirmed` false the block never came up.
    @discardableResult
    func add(
        day: Int, hour: Int = 10, planned: Int = 50, ranSeconds: Int? = nil, reason: EndReason = .endedEarly,
        plain: Bool = false, confirmed: Bool = true, hide: Bool = false, ended: Bool = true
    ) -> UUID {
        count += 1
        let id = UUID(uuidString: "00000000-0000-4000-8000-\(String(format: "%012d", count))")!
        let plan = FocusFixtures.plan(
            minutes: planned, kind: plain ? .plainTimer : .blocking, selection: plain ? nil : FocusFixtures.blockSix,
            day: String(format: "2026-11-%02d", day), window: FocusFixtures.window(day, month: 11)
        )
        let length = TimeInterval(ranSeconds ?? planned * 60)
        clock.at(at(2026, 11, day, hour))
        clock.write(.sessionStarted(plan), session: id)
        if plain || !confirmed {
            clock.time.advance(length)
        } else {
            clock.write(.shieldApplied, session: id)
            clock.time.advance(length / 2)
            clock.write(.shieldVerified, session: id)
            clock.time.advance(length / 2)
        }
        if ended {
            clock.write(.sessionEnded(ranSeconds == nil ? .completed : reason, verified: !plain && confirmed), session: id)
        }
        if hide {
            clock.time.advance(60)
            clock.write(.sessionHidden, session: id)
        }
        return id
    }

    var records: [SessionRecord] { FocusLedger(clock.events).sessions() }
    var credits: [SessionCredit] { HoursCredit.credit(records, crediting: [.live], now: at(2026, 12, 1)) }

    func total(tuning: WorkshopTuning = WorkshopFixtures.small) -> Int {
        LeafEarnings.total(records, tuning: tuning)
    }
}

@Suite("Leaves from sessions")
struct LeafEarningsTests {
    private let small = WorkshopFixtures.small

    @Test("A 50-minute session that blocked apps gives a leaf for each 5 minutes at that pace")
    func blocking() {
        let fixture = EarningsFixture()
        fixture.add(day: 10)
        #expect(fixture.total() == 10)
    }

    @Test("A plain timer earns the same from its time focused, though it counts nothing as saved")
    func plainTimer() throws {
        let fixture = EarningsFixture()
        let id = fixture.add(day: 10, plain: true)
        let record = try #require(fixture.records.first { $0.id == id })
        #expect((fixture.credits.first { $0.id == id }?.seconds ?? 0) == 0)
        #expect(LeafEarnings.leaves(of: record, tuning: small) == 10)
        #expect(fixture.total() == 10)
    }

    @Test("A session whose block never came up counts nothing as saved and still earns for its time focused")
    func timeFocusedNotTimeSaved() throws {
        let fixture = EarningsFixture()
        let id = fixture.add(day: 10, confirmed: false)
        let record = try #require(fixture.records.first { $0.id == id })
        #expect((fixture.credits.first { $0.id == id }?.seconds ?? 0) == 0)
        #expect(record.focusedSeconds == 3000)
        #expect(LeafEarnings.leaves(of: record, tuning: small) == 10)
    }

    @Test("A session's leaves round up when it ends: 13 minutes at a leaf per 5 is 3")
    func roundedUp() {
        let fixture = EarningsFixture()
        fixture.add(day: 10, planned: 13)
        #expect(fixture.total() == 3)
    }

    @Test("Leaves are rounded session by session: two 6-minute sessions give two each, not three between them")
    func perSession() {
        let fixture = EarningsFixture()
        fixture.add(day: 10, hour: 9, planned: 6, plain: true)
        fixture.add(day: 10, hour: 11, planned: 6, plain: true)
        #expect(fixture.total() == 4)
    }

    @Test("A session ended before its timer ran out earns nothing, even a minute from the end, and is still in the record as ended early")
    func endedEarly() throws {
        let fixture = EarningsFixture()
        fixture.add(day: 10)
        let id = fixture.add(day: 11, ranSeconds: 49 * 60)
        let record = try #require(fixture.records.first { $0.id == id })
        #expect(record.endReason == .endedEarly)
        #expect(record.focusedSeconds == 49 * 60)
        #expect(LeafEarnings.leaves(of: record, tuning: small) == 0)
        #expect(fixture.total() == 10)
    }

    @Test("Every way out before the timer ends loses the session's leaves", arguments: [
        EndReason.endedEarly, .emergencyRelease, .releaseAll,
    ])
    func everyWayOut(reason: EndReason) {
        let fixture = EarningsFixture()
        fixture.add(day: 10, ranSeconds: 1800, reason: reason)
        fixture.add(day: 10, hour: 14, ranSeconds: 1800, reason: reason, plain: true)
        #expect(fixture.total() == 0)
    }

    @Test("A session removed from History keeps the leaves it earned")
    func removed() {
        let fixture = EarningsFixture()
        fixture.add(day: 10, hide: true)
        fixture.add(day: 11, plain: true)
        #expect(fixture.total() == 20)
    }

    @Test("A session that hasn't ended has earned nothing yet")
    func running() throws {
        let fixture = EarningsFixture()
        fixture.add(day: 10)
        let now = fixture.add(day: 11, ranSeconds: 1500, ended: false)
        let record = try #require(fixture.records.first { $0.id == now })
        #expect(record.focusedSeconds > 0)
        #expect(LeafEarnings.leaves(of: record, tuning: small) == 0)
        #expect(fixture.total() == 10)
    }

    @Test("The pace comes from the tuning, and a pace of nothing earns nothing")
    func pace() {
        let fixture = EarningsFixture()
        fixture.add(day: 10)
        var slow = small
        slow.leavesPerHour = 6
        #expect(fixture.total(tuning: slow) == 5)
        slow.leavesPerHour = 0
        #expect(fixture.total(tuning: slow) == 0)
    }

    @Test("Any part of a leaf counts as one, and no time earns none")
    func rounding() {
        #expect(LeafEarnings.leaves(forSeconds: 0, tuning: small) == 0)
        #expect(LeafEarnings.leaves(forSeconds: 1, tuning: small) == 1)
        #expect(LeafEarnings.leaves(forSeconds: 300, tuning: small) == 1)
        #expect(LeafEarnings.leaves(forSeconds: 301, tuning: small) == 2)
        #expect(LeafEarnings.leaves(forSeconds: 3000, tuning: small) == 10)
        #expect(LeafEarnings.leaves(forSeconds: -600, tuning: small) == 0)
        #expect(LeafEarnings.leaves(forSeconds: .max, tuning: small) == WorkshopBank.limit)
    }

    @Test("At the app's own pace, 0.9 leaves a minute, 50 minutes gives 45, 20 gives 18 and 25 gives 23 (22.5, rounded up)")
    func ownPace() {
        #expect(LeafEarnings.leaves(forSeconds: 50 * 60) == 45)
        #expect(LeafEarnings.leaves(forSeconds: 20 * 60) == 18)
        #expect(LeafEarnings.leaves(forSeconds: 25 * 60) == 23)
        #expect(LeafEarnings.leaves(forSeconds: 180 * 60) == 162)
    }
}
