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

    @Test("Missing shields for a running session are applied again")
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

    @Test("Capabilities and probes")
    func capability() {
        #expect(!BlockingCapability.unavailableInBuild.canBlock)
        #expect(BlockingCapability.preview.canBlock)
        #expect(BlockingProbe.allowed.isAllowed)
        #expect(!BlockingProbe.restricted.isAllowed)
    }
}
