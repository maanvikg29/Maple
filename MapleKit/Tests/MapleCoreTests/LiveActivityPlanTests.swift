import Foundation
import Testing
@testable import MapleCore

@Suite("Live Activity upkeep")
struct LiveActivityPlanTests {
    private let running = UUID(uuidString: "00000000-0000-4000-8000-0000000000A1")!
    private let other = UUID(uuidString: "00000000-0000-4000-8000-0000000000B2")!

    private func shown(_ session: UUID) -> LiveActivityPlan.Listed { .init(session: session, isShown: true) }
    private func gone(_ session: UUID) -> LiveActivityPlan.Listed { .init(session: session, isShown: false) }

    @Test("With nothing running, every activity still showing ends")
    func nothingRunning() {
        let plan = LiveActivityPlan.make(
            activities: [shown(running), gone(other), shown(other)], wanted: nil, contentChanged: true, mayRequest: true
        )
        #expect(plan == LiveActivityPlan(end: [0, 2], next: .clear))
        #expect(LiveActivityPlan.make(activities: [], wanted: nil, contentChanged: false, mayRequest: false)
            == LiveActivityPlan(end: [], next: .clear))
    }

    @Test("A relaunch reconnects to the running session's activity and sends it fresh content")
    func reconnects() {
        #expect(LiveActivityPlan.make(activities: [shown(running)], wanted: running, contentChanged: true, mayRequest: true)
            == LiveActivityPlan(end: [], next: .update(0)))
        #expect(LiveActivityPlan.make(activities: [shown(running)], wanted: running, contentChanged: false, mayRequest: false)
            == LiveActivityPlan(end: [], next: .unchanged))
    }

    @Test("An activity Maple doesn't recognise ends, and so does a second copy of the running one")
    func endsUnknown() {
        let plan = LiveActivityPlan.make(
            activities: [shown(other), shown(running), shown(running)], wanted: running, contentChanged: true, mayRequest: true
        )
        #expect(plan == LiveActivityPlan(end: [0, 2], next: .update(1)))
        #expect(LiveActivityPlan.make(activities: [shown(other)], wanted: running, contentChanged: true, mayRequest: true)
            == LiveActivityPlan(end: [0], next: .request))
    }

    @Test("A dismissed activity isn't asked for again, and a session is asked for once per launch")
    func asksOnce() {
        #expect(LiveActivityPlan.make(activities: [gone(running)], wanted: running, contentChanged: true, mayRequest: true)
            == LiveActivityPlan(end: [], next: .dismissed))
        #expect(LiveActivityPlan.make(activities: [], wanted: running, contentChanged: true, mayRequest: true)
            == LiveActivityPlan(end: [], next: .request))
        #expect(LiveActivityPlan.make(activities: [], wanted: running, contentChanged: true, mayRequest: false)
            == LiveActivityPlan(end: [], next: .notAsked))
        #expect(LiveActivityPlan.make(activities: [gone(running), shown(running)], wanted: running, contentChanged: true,
                                      mayRequest: false)
            == LiveActivityPlan(end: [], next: .update(1)))
    }
}
