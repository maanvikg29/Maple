import Foundation
import Testing
@testable import MapleCore

@Suite("Needs Screen Time model")
struct NeedsScreenTimeModelTests {
    /// Study 50m, Quick 25m, Deep 1h 30m and Read 30m.
    private let presets = FocusPreset.defaults(appSetID: nil)

    @Test("Each probe's card, with a primary only where Maple can ask")
    func cards() throws {
        let study = presets[0]
        let notAsked = try #require(NeedsScreenTimeModel(probe: .notDetermined, capability: .screenTime, preset: study))
        #expect(notAsked.state == .notAsked)
        #expect(notAsked.card.title == "Lock apps with Screen Time")
        #expect(notAsked.card.body == "Maple keeps your chosen apps resting while you focus. It never sees which apps you use.")
        #expect(notAsked.card.primary == "Turn on Screen Time")

        let declined = try #require(NeedsScreenTimeModel(probe: .declined, capability: .preview, preset: study))
        #expect(declined.state == .declined)
        #expect(declined.card.title == "Screen Time is off for Maple")
        #expect(declined.card.body == "Turn it on to count your focus time.")
        #expect(declined.card.primary == "Turn on Screen Time")

        let restricted = try #require(NeedsScreenTimeModel(probe: .restricted, capability: .screenTime, preset: study))
        #expect(restricted.card.title == "Screen Time is managed on this iPhone")
        #expect(restricted.card.body == "A parent can allow Maple in Screen Time settings.")
        #expect(restricted.card.primary == nil)

        let passcode = try #require(NeedsScreenTimeModel(probe: .noPasscode, capability: .screenTime, preset: study))
        #expect(passcode.card.title == "Set a passcode to use Screen Time")
        #expect(passcode.card.body == nil)
        #expect(passcode.card.primary == nil)
    }

    @Test("A build that can't block shows the free build's card whatever the probe says, with no prompt and no leaf")
    func freeBuild() throws {
        for probe in BlockingProbe.allCases {
            let free = try #require(NeedsScreenTimeModel(probe: probe, capability: .unavailableInBuild, preset: presets[0]))
            #expect(free.state == .freeBuild)
            #expect(free.card.title == "This version of Maple can't lock apps")
            #expect(free.card.body == "The timer still runs, but it won't count.")
            #expect(free.card.primary == nil)
            #expect(!free.showsLeaf)
        }
        let unavailable = try #require(NeedsScreenTimeModel(probe: .unavailable, capability: .screenTime, preset: presets[0]))
        #expect(unavailable.state == .freeBuild)
    }

    @Test("While blocking is allowed there is no Needs Screen Time: the start screen shows")
    func allowed() {
        #expect(NeedsScreenTimeModel(probe: .allowed, capability: .preview, preset: presets[0]) == nil)
        #expect(NeedsScreenTimeModel(probe: .allowed, capability: .screenTime, preset: presets[0]) == nil)
    }

    @Test("The dial shows the preset's length and name, and the leaf while Screen Time could still count; the link is always there")
    func dial() throws {
        let deep = try #require(NeedsScreenTimeModel(probe: .notDetermined, capability: .screenTime, preset: presets[2]))
        #expect(deep.lengthText == "1h 30m")
        #expect(deep.caption == "Deep")
        #expect(deep.plainTimerLink == "Use a plain timer · it won't count")
        for probe: BlockingProbe in [.notDetermined, .declined, .restricted, .noPasscode] {
            let model = try #require(NeedsScreenTimeModel(probe: probe, capability: .preview, preset: presets[0]))
            #expect(model.showsLeaf)
            #expect(model.lengthText == "50m")
            #expect(model.caption == "Study")
            #expect(model.plainTimerLink == "Use a plain timer · it won't count")
        }
    }
}
