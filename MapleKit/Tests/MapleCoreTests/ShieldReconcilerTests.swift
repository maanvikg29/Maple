import Foundation
import Testing
@testable import MapleCore

@Suite("Shield reconciler")
struct ShieldReconcilerTests {
    private let start = at(2026, 10, 23, 14)

    private func running() throws -> SessionRecord {
        let script = SessionScript(start: start)
        script.after(5, .shieldApplied)
        return try #require(script.record)
    }

    @Test("An unknown store state never leads to an action")
    func unknown() throws {
        #expect(ShieldReconciler.ops(running: try running(), store: .unknown, now: start.addingTimeInterval(60)).isEmpty)
        #expect(ShieldReconciler.ops(running: nil, store: .unknown, now: start).isEmpty)
    }

    @Test("A running session's shields stay as they are")
    func steady() throws {
        let session = try running()
        #expect(ShieldReconciler.ops(running: session, store: .applied(session: session.id), now: start.addingTimeInterval(60)).isEmpty)
    }

    @Test("Missing shields for a running session are reported as missing")
    func reapply() throws {
        let session = try running()
        #expect(ShieldReconciler.ops(running: session, store: .empty, now: start.addingTimeInterval(60)) == [.apply(session: session.id)])
    }

    @Test("Past the planned end, the session's shields are cleared")
    func expired() throws {
        let session = try running()
        #expect(ShieldReconciler.ops(running: session, store: .applied(session: session.id), now: start.addingTimeInterval(3006))
            == [.clear(session: session.id)])
    }

    @Test("Shields with no running session are cleared")
    func orphan() {
        let stray = UUID()
        #expect(ShieldReconciler.ops(running: nil, store: .applied(session: stray), now: start) == [.clear(session: stray)])
    }

    @Test("A plain timer never wants shields")
    func plain() throws {
        let script = SessionScript(start: start, plan: FocusFixtures.plan(kind: .plainTimer, selection: nil))
        let session = try #require(script.record)
        #expect(ShieldReconciler.ops(running: session, store: .empty, now: start.addingTimeInterval(60)).isEmpty)
    }

    @Test("Applying the answer and asking again gives nothing")
    func idempotent() throws {
        let session = try running()
        for store in [ShieldStoreState.empty, .applied(session: session.id), .applied(session: UUID())] {
            for now in [start.addingTimeInterval(60), start.addingTimeInterval(4000)] {
                let after = ShieldReconciler.applying(ShieldReconciler.ops(running: session, store: store, now: now), to: store)
                #expect(ShieldReconciler.ops(running: session, store: after, now: now).isEmpty)
            }
        }
    }

    /// Confirmed at 14:00:05, then lost at 14:01:00 by `kind`; still running.
    private func lost(by kind: FocusEventKind) throws -> SessionRecord {
        let script = SessionScript(start: start)
        script.after(5, .shieldApplied)
        script.after(55, kind)
        return try #require(script.record)
    }

    @Test("A session that lost proof keeps the shields it has")
    func lostKeepsShields() throws {
        let session = try lost(by: .shieldLost)
        #expect(ShieldReconciler.ops(running: session, store: .applied(session: session.id), now: start.addingTimeInterval(120)).isEmpty)
    }

    @Test("A session that lost proof is not given missing shields again")
    func lostNotReapplied() throws {
        let session = try lost(by: .shieldLost)
        #expect(ShieldReconciler.ops(running: session, store: .empty, now: start.addingTimeInterval(120)).isEmpty)
    }

    @Test("An unknown credit-affecting event keeps the shields a session has")
    func unknownKeepsShields() throws {
        let session = try lost(by: .unknown("futureKind"))
        #expect(ShieldReconciler.ops(running: session, store: .applied(session: session.id), now: start.addingTimeInterval(120)).isEmpty)
    }

    @Test("An unknown credit-affecting event is not given missing shields again")
    func unknownNotReapplied() throws {
        let session = try lost(by: .unknown("futureKind"))
        #expect(ShieldReconciler.ops(running: session, store: .empty, now: start.addingTimeInterval(120)).isEmpty)
    }

    @Test("An ended session's shields are cleared before its planned end")
    func ended() throws {
        let script = SessionScript(start: start)
        script.after(5, .shieldApplied)
        script.after(60, .sessionEnded(.completed, verified: true))
        let session = try #require(script.record)
        #expect(ShieldReconciler.ops(running: session, store: .applied(session: session.id), now: start.addingTimeInterval(120))
            == [.clear(session: session.id)])
    }

    @Test("Capabilities and probes")
    func capability() {
        #expect(!BlockingCapability.unavailableInBuild.canBlock)
        #expect(BlockingCapability.preview.canBlock)
        #expect(BlockingProbe.allowed.isAllowed)
        #expect(!BlockingProbe.restricted.isAllowed)
    }
}
