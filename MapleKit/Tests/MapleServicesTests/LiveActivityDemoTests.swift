#if DEBUG
import Foundation
import Testing
@testable import MapleCore
@testable import MapleServices

@Suite("Live Activity demo")
@MainActor
struct LiveActivityDemoTests {
    private let now = at(2026, 10, 23, 14, 20)

    private func options(_ arguments: [String]) -> DemoLaunchOptions {
        DemoLaunchOptions(arguments: ["Maple"] + arguments)
    }

    @Test("Running is on real dates: 18 minutes into a 50-minute Study by default, with the spec's intention")
    func running() {
        let state = FocusDemo.LiveActivity.running.state(options: options(["-MapleDemoLiveActivity", "running"]), now: now)
        #expect(state.start == at(2026, 10, 23, 14, 2))
        #expect(state.plannedEnd == at(2026, 10, 23, 14, 52))
        #expect(state.presetName == "Study")
        #expect(!state.isPlainTimer && state.breakEnd == nil)
        #expect(state.intention == "Chemistry ch. 4")
    }

    @Test("A break ends 4 minutes after launch; the preset, minutes in and intention follow their arguments")
    func breakAndArguments() {
        let arguments = ["-MapleDemoLiveActivity", "break", "-MapleDemoPreset", "deep", "-MapleDemoFocusAt", "30",
                         "-MapleDemoIntention", "Essay plan"]
        let state = FocusDemo.LiveActivity.breakTime.state(options: options(arguments), now: now)
        #expect(state.presetName == "Deep")
        #expect(state.start == at(2026, 10, 23, 13, 50))
        #expect(state.plannedEnd == at(2026, 10, 23, 15, 20))
        #expect(state.breakEnd == at(2026, 10, 23, 14, 24))
        #expect(state.intention == "Essay plan")
        #expect(FocusDemo.LiveActivity.running.state(options: options(["-MapleDemoIntention", ""]), now: now).intention == nil)
    }

    @Test("A plain timer has no leaf; ended goes stale 8 seconds after launch; every launch is a new session")
    func plainAndEnded() {
        let plain = FocusDemo.LiveActivity.plain.state(options: options(["-MapleDemoLiveActivity", "plain"]), now: now)
        #expect(plain.isPlainTimer)
        #expect(plain.described(intention: nil, tint: LeafColor(0x9CC3A4), leafID: "campestre").leafID == nil)
        let ended = FocusDemo.LiveActivity.ended.state(options: options(["-MapleDemoLiveActivity", "ended"]), now: now)
        #expect(ended.plannedEnd == now.addingTimeInterval(FocusDemo.LiveActivity.endsAfter))
        #expect(FocusDemo.LiveActivity.endsAfter == 8)
        #expect(ended.plannedEnd.timeIntervalSince(ended.start) == 50 * 60)
        #expect(ended.sessionID != plain.sessionID)
        let fixed = UUID(uuidString: "00000000-0000-4000-8000-00000000DA01")!
        #expect(FocusDemo.LiveActivity.running.state(options: options([]), now: now, session: fixed).sessionID == fixed)
    }
}
#endif
