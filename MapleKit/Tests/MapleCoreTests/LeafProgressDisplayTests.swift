import Foundation
import Testing
@testable import MapleCore

@Suite("Next leaf during a session")
struct LeafProgressDisplayTests {
    /// An hours leaf at 9h of 10h.
    private let field = progressRow("campestre", .hoursSaved, threshold: 10, current: 9, estimate: nil)

    @Test("An hours leaf adds the running session's provisional time, as the dial does")
    func adds() {
        let shown = field.displaying(provisionalSeconds: 1800)
        #expect(shown.current == 9.5)
        #expect(LeafRemainder(shown, phase: .day).text == "30m")
        #expect(shown.speciesID == field.speciesID)
        #expect(shown.threshold == field.threshold)
        #expect(shown.floor == field.floor)
        #expect(shown.availability == field.availability)
    }

    @Test("Only a checkpoint opens the leaf: the row stops at 1m to go")
    func stopsShort() {
        let shown = field.displaying(provisionalSeconds: 2 * 3600)
        #expect(shown.current < shown.threshold)
        #expect(LeafRemainder(shown, phase: .day).text == "1m")
    }

    @Test("No session, other categories and a reached threshold are unchanged")
    func unchanged() {
        #expect(field.displaying(provisionalSeconds: 0) == field)
        let nights = progressRow("rubrum", .restedNights, threshold: 3, current: 1, estimate: 2)
        #expect(nights.displaying(provisionalSeconds: 3600) == nights)
        let finished = progressRow("palmatum", .sessionsFinished, threshold: 5, current: 2, estimate: 3)
        #expect(finished.displaying(provisionalSeconds: 3600) == finished)
        let reached = progressRow("campestre", .hoursSaved, threshold: 10, current: 10, estimate: nil)
        #expect(reached.displaying(provisionalSeconds: 600) == reached)
    }
}
