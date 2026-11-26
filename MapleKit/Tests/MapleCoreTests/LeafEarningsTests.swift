import Foundation
import Testing
@testable import MapleCore
@testable import MapleFocusCore

/// Sessions written the way the app writes them, on one clock, for the leaf rules. Add them in time order.
private final class EarningsFixture {
    private let clock = FocusDay(at(2026, 11, 1, 6))
    private var count = 0

    /// A session on `day` November 2026 at `hour`:00, `planned` minutes long, that ran its whole length or `ranSeconds`.
    /// A blocking session is confirmed half-way, so it counts as saved; with `confirmed` false the block never came up.
    @discardableResult
    func add(
        day: Int, hour: Int = 10, planned: Int = 50, ranSeconds: Int? = nil, plain: Bool = false, confirmed: Bool = true,
        hide: Bool = false, ended: Bool = true
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
            clock.write(.sessionEnded(ranSeconds == nil ? .completed : .endedEarly, verified: !plain && confirmed), session: id)
        }
        if hide {
            clock.time.advance(60)
            clock.write(.sessionHidden, session: id)
        }
        return id
    }

    var records: [SessionRecord] { FocusLedger(clock.events).sessions() }
    var credits: [SessionCredit] { HoursCredit.credit(records, crediting: [.live], now: at(2026, 12, 1)) }

    func total(running: UUID? = nil, tuning: WorkshopTuning = WorkshopFixtures.small) -> Int {
        LeafEarnings.total(records, running: running, tuning: tuning)
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
        fixture.add(day: 10, ranSeconds: 780)
        #expect(fixture.total() == 3)
    }

    @Test("Leaves are rounded session by session: two 6-minute sessions give two each, not three between them")
    func perSession() {
        let fixture = EarningsFixture()
        fixture.add(day: 10, hour: 9, planned: 20, ranSeconds: 360, plain: true)
        fixture.add(day: 10, hour: 11, planned: 20, ranSeconds: 360, plain: true)
        #expect(fixture.total() == 4)
    }

    @Test("A start that never got going earns nothing: under a minute is no session, a minute is")
    func tooShort() {
        let short = EarningsFixture()
        short.add(day: 10, planned: 20, ranSeconds: 59, plain: true)
        #expect(short.total() == 0)
        let minute = EarningsFixture()
        minute.add(day: 10, planned: 20, ranSeconds: 60, plain: true)
        #expect(minute.total() == 1)
    }

    @Test("A session removed from History keeps the leaves it earned")
    func removed() {
        let fixture = EarningsFixture()
        fixture.add(day: 10, hide: true)
        fixture.add(day: 11, plain: true)
        #expect(fixture.total() == 20)
    }

    @Test("The running session's leaves aren't in the van until it ends, though its time so far would be 3")
    func running() {
        let fixture = EarningsFixture()
        fixture.add(day: 10)
        let now = fixture.add(day: 11, ranSeconds: 1500, ended: false)
        #expect(fixture.total(running: now) == 10)
        #expect(fixture.total(running: nil) == 13)
    }

    @Test("The pace comes from the tuning, and a pace of nothing earns nothing")
    func pace() {
        let fixture = EarningsFixture()
        fixture.add(day: 10)
        var slow = small
        slow.secondsPerLeaf = 600
        #expect(fixture.total(tuning: slow) == 5)
        slow.secondsPerLeaf = 0
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
    }

    @Test("At the app's own pace, 0.8 leaves a minute, a 50-minute session gives 40 and a 25-minute one 20")
    func ownPace() {
        #expect(LeafEarnings.leaves(forSeconds: 50 * 60) == 40)
        #expect(LeafEarnings.leaves(forSeconds: 25 * 60) == 20)
        #expect(LeafEarnings.leaves(forSeconds: 7 * 60) == 6)
    }
}
