import Foundation
import Testing
@testable import MapleCore
@testable import MapleFocusCore

/// Sessions written the way the app writes them, on one clock, for the leaf rules. Add them in time order.
private final class EarningsFixture {
    private let clock = FocusDay(at(2026, 11, 1, 6))
    private var count = 0

    /// A session on `day` November 2026 at `hour`:00, `planned` minutes long, that ran its whole length or `ranSeconds`.
    /// A blocking session is confirmed half-way, so it counts.
    @discardableResult
    func add(
        day: Int, hour: Int = 10, planned: Int = 50, ranSeconds: Int? = nil, plain: Bool = false, hide: Bool = false,
        ended: Bool = true
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
        if plain {
            clock.time.advance(length)
        } else {
            clock.write(.shieldApplied, session: id)
            clock.time.advance(length / 2)
            clock.write(.shieldVerified, session: id)
            clock.time.advance(length / 2)
        }
        if ended {
            clock.write(.sessionEnded(ranSeconds == nil ? .completed : .endedEarly, verified: !plain), session: id)
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
        LeafEarnings.total(records, credits: credits, running: running, tuning: tuning)
    }
}

@Suite("Leaves from sessions")
struct LeafEarningsTests {
    @Test("A 50-minute session that blocked apps gives 10 leaves")
    func blocking() {
        let fixture = EarningsFixture()
        fixture.add(day: 10)
        #expect(fixture.total() == 10)
    }

    @Test("A plain timer earns from its time focused, though it counts nothing as saved")
    func plainTimer() throws {
        let fixture = EarningsFixture()
        let id = fixture.add(day: 10, plain: true)
        let record = try #require(fixture.records.first { $0.id == id })
        let credit = fixture.credits.first { $0.id == id }
        #expect((credit?.seconds ?? 0) == 0)
        #expect(LeafEarnings.seconds(of: record, credit: credit) == 3000)
        #expect(LeafEarnings.leaves(of: record, credit: credit, tuning: WorkshopFixtures.small) == 10)
        #expect(fixture.total() == 10)
    }

    @Test("A session that blocked apps earns from its counted time, never from the clock alone")
    func countedOnly() throws {
        let fixture = EarningsFixture()
        let id = fixture.add(day: 10)
        let record = try #require(fixture.records.first { $0.id == id })
        #expect(LeafEarnings.seconds(of: record, credit: nil) == 0)
        var credit = try #require(fixture.credits.first { $0.id == id })
        credit.seconds = 1500
        #expect(LeafEarnings.seconds(of: record, credit: credit) == 1500)
        credit.seconds = -40
        #expect(LeafEarnings.seconds(of: record, credit: credit) == 0)
    }

    @Test("Leaves are counted session by session: two 9-minute sessions give one each, not three between them")
    func perSession() {
        let fixture = EarningsFixture()
        fixture.add(day: 10, hour: 9, planned: 20, ranSeconds: 540, plain: true)
        fixture.add(day: 10, hour: 11, planned: 20, ranSeconds: 540, plain: true)
        #expect(fixture.total() == 2)
    }

    @Test("A session ended early keeps the leaves that had already fallen")
    func endedEarly() {
        let fixture = EarningsFixture()
        fixture.add(day: 10, ranSeconds: 780)
        #expect(fixture.total() == 2)
    }

    @Test("A session removed from History keeps the leaves it earned")
    func removed() {
        let fixture = EarningsFixture()
        fixture.add(day: 10, hide: true)
        fixture.add(day: 11, plain: true)
        #expect(fixture.total() == 20)
    }

    @Test("The running session's leaves aren't in the van until it ends")
    func running() {
        let fixture = EarningsFixture()
        fixture.add(day: 10)
        let now = fixture.add(day: 11, ranSeconds: 1500, plain: true, ended: false)
        #expect(fixture.total(running: now) == 10)
    }

    @Test("The pace comes from the tuning, and a pace of nothing earns nothing")
    func pace() {
        let fixture = EarningsFixture()
        fixture.add(day: 10)
        var slow = WorkshopFixtures.small
        slow.secondsPerLeaf = 600
        #expect(fixture.total(tuning: slow) == 5)
        slow.secondsPerLeaf = 0
        #expect(fixture.total(tuning: slow) == 0)
    }

    @Test("Seconds round down to whole leaves, and time below nothing earns nothing")
    func wholeLeaves() {
        #expect(LeafEarnings.leaves(forSeconds: 299, tuning: WorkshopFixtures.small) == 0)
        #expect(LeafEarnings.leaves(forSeconds: 300, tuning: WorkshopFixtures.small) == 1)
        #expect(LeafEarnings.leaves(forSeconds: 3299, tuning: WorkshopFixtures.small) == 10)
        #expect(LeafEarnings.leaves(forSeconds: -600, tuning: WorkshopFixtures.small) == 0)
    }
}
