import Foundation
import Testing
@testable import MapleCore
@testable import MapleFocusCore

/// End early for Gentle and Steady (F1 design §5.6).
@Suite("End early")
struct EndEarlyModelTests {
    @Test("Steady asks first: Keep going, Hold to end, and the break instead while it is unused")
    func steadyAsking() {
        let sheet = EndEarlyModel(path: .steady, countedSeconds: 18 * 60, breakAvailable: true, stage: .asking)
        #expect(sheet.title == "End this session?")
        #expect(sheet.spokenTitle == "End this session?")
        #expect(sheet.body == "18 minutes saved so far. They stay yours either way.")
        #expect(sheet.keepGoingTitle == "Keep going")
        #expect(sheet.holdTitle == "Hold to end")
        #expect(sheet.endTitle == nil)
        #expect(sheet.breakInsteadTitle == "Take a 5-minute break instead")
        #expect(sheet.ringProgress == nil)
        let noBreak = EndEarlyModel(path: .steady, countedSeconds: 18 * 60, breakAvailable: false, stage: .asking)
        #expect(noBreak.breakInsteadTitle == nil)
    }

    @Test("After the hold, a quiet 15-second countdown that Keep going still cancels")
    func steadyCountdown() {
        #expect(EndEarlyModel.countdown(for: .steady) == 15)
        let sheet = EndEarlyModel(path: .steady, countedSeconds: 18 * 60, breakAvailable: true, stage: .ending(secondsLeft: 15))
        #expect(sheet.title == "Ending in 15s")
        #expect(sheet.spokenTitle == "Ending in 15 seconds")
        #expect(sheet.keepGoingTitle == "Keep going")
        #expect(sheet.holdTitle == nil)
        #expect(sheet.breakInsteadTitle == nil)
        #expect(sheet.ringProgress == nil)
        let later = EndEarlyModel(path: .steady, countedSeconds: 18 * 60, breakAvailable: true, stage: .ending(secondsLeft: 1))
        #expect(later.title == "Ending in 1s")
        #expect(later.spokenTitle == "Ending in 1 second")
        // At the end itself the sheet is already closing: it still reads 1s, never "Ending in 0s".
        let end = at(2026, 10, 23, 14, 20)
        let closing = EndEarlyModel(path: .steady, countedSeconds: 18 * 60, breakAvailable: true,
                                    stage: .ending(secondsLeft: EndEarlyModel.secondsLeft(until: end, now: end)))
        #expect(closing.title == "Ending in 1s")
        #expect(closing.spokenTitle == "Ending in 1 second")
    }

    @Test("Gentle: End session starts a 5-second breathing ring")
    func gentle() {
        let asking = EndEarlyModel(path: .gentle, countedSeconds: 10 * 60, breakAvailable: true, stage: .asking)
        #expect(asking.title == "End this session?")
        #expect(asking.endTitle == "End session")
        #expect(asking.holdTitle == nil)
        #expect(asking.breakInsteadTitle == nil)
        #expect(EndEarlyModel.countdown(for: .gentle) == 5)
        let ring = EndEarlyModel(path: .gentle, countedSeconds: 10 * 60, breakAvailable: true, stage: .ending(secondsLeft: 3))
        #expect(ring.title == "Ending in 3s")
        #expect(abs((ring.ringProgress ?? -1) - 0.4) < 1e-9)
        #expect(ring.endTitle == nil)
        #expect(EndEarlyModel.ringScale(progress: 0, reduceMotion: false) == 0.88)
        #expect(EndEarlyModel.ringScale(progress: 0.5, reduceMotion: false) == 1)
        #expect(EndEarlyModel.ringScale(progress: 0.2, reduceMotion: true) == 1)
    }

    @Test("Nothing counted yet reads plainly")
    func nothingCounted() {
        let sheet = EndEarlyModel(path: .steady, countedSeconds: 0, breakAvailable: false, stage: .asking)
        #expect(sheet.body == "This session isn't counting toward leaves.")
    }

    @Test("The countdown's seconds round up, and stop at zero")
    func secondsLeft() {
        let end = at(2026, 10, 23, 14, 20)
        #expect(EndEarlyModel.secondsLeft(until: end, now: end.addingTimeInterval(-15)) == 15)
        #expect(EndEarlyModel.secondsLeft(until: end, now: end.addingTimeInterval(-14.2)) == 15)
        #expect(EndEarlyModel.secondsLeft(until: end, now: end) == 0)
        #expect(EndEarlyModel.secondsLeft(until: end, now: end.addingTimeInterval(3)) == 0)
    }

    @Test("No break instead when apps aren't locked: a plain timer, or a block lost mid-session")
    func noBreakWithoutLock() throws {
        let start = at(2026, 10, 23, 14)
        func record(kind: SessionKind = .blocking, _ more: (SessionScript) -> Void = { _ in }) throws -> SessionRecord {
            let plan = FocusFixtures.plan(breakMinutes: 5, kind: kind, selection: kind == .plainTimer ? nil : FocusFixtures.blockSix)
            let script = SessionScript(start: start, plan: plan)
            if kind == .blocking { script.after(5, .shieldApplied) }
            more(script)
            return try #require(script.record)
        }
        func sheet(_ session: SessionRecord, at minute: Double) -> EndEarlyModel {
            let now = session.countdownStart.addingTimeInterval(minute * 60)
            return EndEarlyModel(path: .steady, countedSeconds: 10 * 60,
                                 breakAvailable: RunningSessionModel.breakAvailable(session, at: now), stage: .asking)
        }
        #expect(sheet(try record(), at: 18).breakInsteadTitle == "Take a 5-minute break instead")
        #expect(sheet(try record(kind: .plainTimer), at: 18).breakInsteadTitle == nil)
        #expect(sheet(try record { $0.after(10 * 60, .shieldLost) }, at: 18).breakInsteadTitle == nil)
        // A used break, or no time left, offers none either.
        #expect(sheet(try record { $0.after(60, .breakStarted(seconds: 300)) }, at: 18).breakInsteadTitle == nil)
        #expect(sheet(try record(), at: 50).breakInsteadTitle == nil)
    }
}

/// Locked's emergency release (F1 design §5.7, F1-1).
@Suite("Emergency release")
struct EmergencyReleaseModelTests {
    private func model(
        _ stage: EmergencyReleaseModel.Stage, counted: Int = 18 * 60, canCount: Bool = true, reduceMotion: Bool = false
    ) -> EmergencyReleaseModel {
        EmergencyReleaseModel(presetName: "Study", countedSeconds: counted, focusedSeconds: 19 * 60 + 20, canCount: canCount,
                              stage: stage, reduceMotion: reduceMotion, locale: enGB)
    }

    @Test("The hold: 10s over hold to release, then keep holding, counting down to the release")
    func hold() {
        let rest = model(.hold(progress: 0))
        #expect(rest.title == "Emergency release")
        #expect(rest.subtitle == "Study · Locked")
        #expect(rest.centre == .countdown(numeral: "10s", caption: "hold to release"))
        #expect(rest.spoken == "10 seconds, hold to release")
        #expect(rest.body == "Ends this session now. Your 18 minutes stay yours, but it won't count as finished.")
        #expect(rest.holdTitle == "Hold to release")
        #expect(rest.keepGoingTitle == "Keep going")
        #expect(rest.doneTitle == nil)
        #expect(!rest.isEnded && !rest.isBreathing)
        let held = model(.hold(progress: 0.6))
        #expect(held.centre == .countdown(numeral: "4s", caption: "keep holding"))
        #expect(held.spoken == "4 seconds, keep holding")
        #expect(model(.hold(progress: 0.95)).spoken == "1 second, keep holding")
    }

    @Test("With nothing counted, the middle sentence is left out")
    func nothingCounted() {
        #expect(model(.hold(progress: 0), counted: 0).body == "Ends this session now. It won't count as finished.")
    }

    @Test("After the release: Breathe in for 4 seconds, then and out, while the bloom swells and settles")
    func breath() {
        let inhale = model(.released(seconds: 1))
        #expect(inhale.centre == .breath("Breathe in"))
        #expect(inhale.isBreathing)
        #expect(inhale.spoken == "Breathe in")
        #expect(inhale.holdTitle == nil)
        #expect(inhale.keepGoingTitle == nil)
        #expect(inhale.doneTitle == nil)
        #expect(inhale.body == nil)
        #expect(model(.released(seconds: 5)).centre == .breath("and out"))
        #expect(abs(model(.released(seconds: 0)).bloomScale - 0.8) < 1e-9)
        #expect(abs(model(.released(seconds: 4)).bloomScale - 1.25) < 1e-9)
        #expect(model(.released(seconds: 4), reduceMotion: true).bloomScale == 1)
        #expect(EmergencyReleaseModel.breathSeconds == 8)
    }

    @Test("Then the ended state: the minutes saved stay yours, and the line and Done fade in")
    func ended() {
        let ended = model(.released(seconds: 8.3))
        #expect(ended.isEnded)
        #expect(ended.centre == .ended(numeral: "18m", caption: "saved · they stay yours"))
        // Its numeral and caption in words, as the dial shows them (§4.9).
        #expect(ended.spoken == "18 minutes saved, they stay yours.")
        #expect(ended.body == "Session ended. It won't count as finished.")
        #expect(ended.doneTitle == "Done")
        #expect(abs(ended.endedOpacity - 0.5) < 1e-9)
        #expect(model(.released(seconds: 20)).endedOpacity == 1)
        // Nothing counted: the receipt's "0m" and "not counted toward leaves".
        #expect(model(.released(seconds: 20), counted: 0).centre == .ended(numeral: "0m", caption: "not counted toward leaves"))
        // A plain timer couldn't count: the minutes focused.
        #expect(model(.released(seconds: 20), counted: 0, canCount: false).centre
            == .ended(numeral: "19m", caption: "not counted toward leaves"))
        #expect(model(.released(seconds: 20), counted: 0).spoken == "0 minutes, not counted toward leaves.")
        #expect(model(.released(seconds: 20), counted: 0, canCount: false).spoken == "19 minutes, not counted toward leaves.")
    }

    @Test("At accessibility sizes the time repeats under the dial: the hold's seconds, then the minutes that stay (§5.17)")
    func timeLine() {
        #expect(model(.hold(progress: 0)).timeLine == "10s hold to release")
        #expect(model(.hold(progress: 0.6)).timeLine == "4s keep holding")
        // The breath has no time to repeat.
        #expect(model(.released(seconds: 1)).timeLine == nil)
        #expect(model(.released(seconds: 20)).timeLine == "18m saved · they stay yours")
        #expect(model(.released(seconds: 20), counted: 0).timeLine == "0m not counted toward leaves")
    }
}

/// Settings' "Release all apps" during a session goes through that session's own way out (F1 design §5.12), which
/// `FocusReleaseRouter` opens and `RunningSessionView` picks by the strictness that applies to it.
@Suite("Release all path")
struct ReleaseAllPathTests {
    @Test("Each strictness's way out: Gentle and Steady end early, Locked is the emergency release")
    func paths() throws {
        let cases: [(Strictness, SessionEndPath, EndReason)] = [
            (.gentle, .gentle, .endedEarly), (.steady, .steady, .endedEarly), (.locked, .emergency, .emergencyRelease),
        ]
        for (strictness, path, reason) in cases {
            let script = SessionScript(start: at(2026, 10, 23, 14), plan: FocusFixtures.plan(strictness: strictness))
            script.after(5, .shieldApplied)
            let running = try #require(script.record)
            #expect(!running.isEnded)
            #expect(SessionEndPath(running.plan) == path)
            #expect(SessionEndPath(running.plan).reason == reason)
        }
    }

    @Test("During a plain timer, whatever its preset's strictness, the way out is Gentle's End early")
    func plainTimer() throws {
        for strictness in Strictness.allCases {
            let plan = FocusFixtures.plan(strictness: strictness, kind: .plainTimer, selection: nil)
            let running = try #require(SessionScript(start: at(2026, 10, 23, 14), plan: plan).record)
            #expect(!running.isEnded)
            #expect(SessionEndPath(running.plan) == .gentle)
            #expect(SessionEndPath(running.plan).reason == .endedEarly)
        }
    }
}
