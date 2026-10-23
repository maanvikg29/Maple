import Foundation
import Testing
@testable import MapleCore
@testable import MapleFocusCore

/// A deterministic generator for shuffles (a linear congruential generator).
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}

@Suite("Focus ledger")
struct FocusLedgerTests {
    private let base = at(2026, 10, 23, 14)

    /// Two sessions across two boots, as the app would write them.
    private func sample() -> [FocusEvent] {
        let s1 = UUID(uuidString: "00000000-0000-4000-8000-0000000000A1")!
        let s2 = UUID(uuidString: "00000000-0000-4000-8000-0000000000A2")!
        func stamp(_ minutes: Double, boot: String = "b1", cont: UInt64? = nil) -> EventStamp {
            FocusFixtures.stamp(base.addingTimeInterval(minutes * 60), cont: cont ?? UInt64(minutes * 60 * 1e9) + 1_000_000_000, boot: boot)
        }
        return [
            FocusFixtures.event(.sessionStarted(FocusFixtures.plan()), at: stamp(0), seq: 1, session: s1),
            FocusFixtures.event(.shieldApplied, at: stamp(0.1), seq: 2, session: s1),
            FocusFixtures.event(.shieldVerified, at: stamp(20), seq: 3, session: s1),
            FocusFixtures.event(.sessionEnded(.completed, verified: true), at: stamp(50.1), seq: 4, session: s1,
                                id: FocusEvent.derivedID(session: s1, kind: .sessionEnded(.completed, verified: true))),
            FocusFixtures.event(.sessionStarted(FocusFixtures.plan()), at: stamp(120, boot: "b2", cont: 9_000_000_000), seq: 5, session: s2),
            FocusFixtures.event(.shieldApplied, at: stamp(120.1, boot: "b2", cont: 15_000_000_000), seq: 6, session: s2),
        ]
    }

    @Test("Merging is order-free and idempotent")
    func orderFree() {
        let events = sample()
        let reference = FocusLedger(events)
        var generator = SeededGenerator(state: 7)
        for _ in 0..<20 {
            var shuffled = events
            shuffled.shuffle(using: &generator)
            var ledger = FocusLedger(Array(shuffled.prefix(3)))
            ledger.merge(Array(shuffled.dropFirst(3)))
            ledger.merge(shuffled)
            #expect(ledger == reference)
        }
        #expect(reference.events.count == 6)
    }

    @Test("Two different events under one id: the same one wins in any order")
    func sameIDDeterministic() {
        let id = FocusEvent.derivedID(session: FocusFixtures.session, kind: .sessionEnded(.completed, verified: true))
        let fromApp = FocusFixtures.event(.sessionEnded(.completed, verified: true), at: FocusFixtures.stamp(base, cont: 50), seq: 9, id: id)
        let fromMonitor = FocusFixtures.event(.sessionEnded(.completed, verified: false), at: FocusFixtures.stamp(base, cont: 40), seq: 2,
                                              writer: .monitor, id: id)
        let one = FocusLedger([fromApp, fromMonitor])
        let other = FocusLedger([fromMonitor, fromApp])
        #expect(one == other)
        #expect(one.events.count == 1)
        #expect(one.events.first?.writer == .app)
    }

    @Test("Within a boot, events are placed by continuous time, so a clock change moves nothing")
    func clockChangeInsideBoot() {
        let start = FocusFixtures.event(.sessionStarted(FocusFixtures.plan()), at: FocusFixtures.stamp(base, cont: 1_000_000_000), seq: 1)
        // The member sets the clock back a day, ten minutes later.
        let later = FocusFixtures.event(.shieldVerified,
                                        at: FocusFixtures.stamp(base.addingTimeInterval(-86400 + 600), cont: 601_000_000_000), seq: 2)
        let placed = FocusLedger([start, later]).placed()
        #expect(placed.map(\.placed) == [base, base.addingTimeInterval(600)])
    }

    @Test("A new boot is never placed before the last event of the boot before it")
    func newBootFloor() {
        let first = FocusFixtures.event(.sessionStarted(FocusFixtures.plan()), at: FocusFixtures.stamp(base, cont: 1_000_000_000), seq: 1)
        let second = FocusFixtures.event(.shieldVerified, at: FocusFixtures.stamp(base.addingTimeInterval(3600), cont: 3_601_000_000_000), seq: 2)
        // After a restart the clock reads a day earlier.
        let rebooted = FocusFixtures.event(.shieldVerified,
                                           at: FocusFixtures.stamp(base.addingTimeInterval(-86400), cont: 5_000_000_000, boot: "b2"), seq: 3)
        let placed = FocusLedger([first, second, rebooted]).placed()
        #expect(placed.last?.placed == base.addingTimeInterval(3600))
    }

    @Test("Boots are ordered by the app's own sequence numbers, not by what the clock said")
    func bootOrderBySeq() {
        // Boot b2 really came second (seq 3), though its clock was set to the day before.
        let a = FocusFixtures.event(.sessionStarted(FocusFixtures.plan()), at: FocusFixtures.stamp(base, cont: 1_000_000_000, boot: "b1"), seq: 1)
        let b = FocusFixtures.event(.shieldApplied, at: FocusFixtures.stamp(base.addingTimeInterval(10), cont: 11_000_000_000, boot: "b1"), seq: 2)
        let c = FocusFixtures.event(.shieldVerified, at: FocusFixtures.stamp(base.addingTimeInterval(-86400), cont: 5_000_000_000, boot: "b2"), seq: 3)
        let ledger = FocusLedger([c, b, a])
        #expect(ledger.events.map(\.seq) == [1, 2, 3])
        #expect(ledger.placed().last?.placed == base.addingTimeInterval(10))
    }

    @Test("A line whose sequence number didn't read (0) doesn't move its boot ahead of earlier boots")
    func unreadSeqKeepsBootOrder() {
        // Boot b2 came second. One of its lines has seq 0 (a bad seq decodes as 0), and its clock reads a day earlier.
        let a = FocusFixtures.event(.sessionStarted(FocusFixtures.plan()), at: FocusFixtures.stamp(base, cont: 1_000_000_000, boot: "b1"), seq: 1)
        let b = FocusFixtures.event(.shieldApplied, at: FocusFixtures.stamp(base.addingTimeInterval(10), cont: 11_000_000_000, boot: "b1"), seq: 2)
        let c = FocusFixtures.event(.shieldVerified, at: FocusFixtures.stamp(base.addingTimeInterval(-86400), cont: 5_000_000_000, boot: "b2"), seq: 0)
        let d = FocusFixtures.event(.shieldVerified, at: FocusFixtures.stamp(base.addingTimeInterval(-86400 + 4), cont: 9_000_000_000, boot: "b2"), seq: 4)
        let ledger = FocusLedger([d, c, b, a])
        #expect(ledger.events.map(\.seq) == [1, 2, 0, 4])
        #expect(ledger.placed().map(\.placed) == [base, base.addingTimeInterval(10), base.addingTimeInterval(10), base.addingTimeInterval(14)])
    }

    @Test("Within one boot and instant, the writer and sequence break ties")
    func ties() {
        let stamp = FocusFixtures.stamp(base, cont: 7)
        let monitor = FocusFixtures.event(.shieldVerified, at: stamp, seq: 1, writer: .monitor)
        let app = FocusFixtures.event(.shieldVerified, at: stamp, seq: 5)
        #expect(FocusLedger([monitor, app]).events.map(\.writer) == [.app, .monitor])
    }
}
