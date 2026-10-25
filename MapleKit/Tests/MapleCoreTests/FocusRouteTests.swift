import Foundation
import Testing
@testable import MapleCore
@testable import MapleFocusCore

/// Which screen the Focus tab shows from the store's state (F1 design §5; Review Focus 1, 2), and when the store
/// refreshes while a session runs (P6).
@Suite("Focus route")
struct FocusRouteTests {
    /// 14:00. The block is confirmed at 14:00:05, so a 50-minute session ends at 14:50:05.
    private let start = at(2026, 10, 23, 14)

    /// `minutes` into the countdown.
    private func minutes(_ minutes: Double) -> Date {
        start.addingTimeInterval(5 + minutes * 60)
    }

    /// A running 50-minute Study with one 5-minute break, taken `breakAfter` minutes into the countdown when given.
    private func running(breakAfter: Double? = nil) throws -> SessionRecord {
        let script = SessionScript(start: start, plan: FocusFixtures.plan(minutes: 50, breakMinutes: 5))
        script.after(5, .shieldApplied)
        if let breakAfter { script.after(breakAfter * 60, .breakStarted(seconds: 300)) }
        return try #require(script.record)
    }

    private func ended() throws -> SessionRecord {
        let script = SessionScript(start: start)
        script.after(5, .shieldApplied)
        script.after(50 * 60, .sessionEnded(.completed, verified: true))
        return try #require(script.record)
    }

    private func route(
        _ running: SessionRecord? = nil, at now: Date, loaded: Bool = true, receipt: UUID? = nil,
        minimised: Bool = false, canBlock: Bool = true, plainTimer: Bool = false
    ) -> FocusRoute {
        FocusRoute.resolve(isLoaded: loaded, running: running, receipt: receipt, isMinimised: minimised,
                           canBlock: canBlock, usesPlainTimer: plainTimer, now: now)
    }

    @Test("Nothing is drawn before the store's first replay, so a reopened app never flashes the start screen")
    func beforeTheFirstReplay() throws {
        #expect(route(at: start, loaded: false) == .settling)
        #expect(route(try running(), at: minutes(10), loaded: false) == .settling)
    }

    @Test("A running session shows its own screen, its break while one runs, and the start screen once minimised")
    func runningSession() throws {
        // A record holds only what has happened by its `now`, so the break is read only once it has started.
        let before = try running()
        #expect(route(before, at: minutes(10)) == .running(before.id))
        let session = try running(breakAfter: 30)
        #expect(route(session, at: minutes(31)) == .breakTime(session.id))
        #expect(route(session, at: minutes(36)) == .running(session.id))
        #expect(route(session, at: minutes(31), minimised: true) == .minimised(session.id))
        // A running session comes before an unseen receipt and before Needs Screen Time.
        #expect(route(before, at: minutes(10), receipt: UUID(), canBlock: false) == .running(before.id))
    }

    @Test("A session past its planned end is never drawn as a running dial at 0:00: the next refresh ends it")
    func pastThePlannedEnd() throws {
        let session = try running()
        #expect(route(session, at: minutes(49.9)) == .running(session.id))
        #expect(route(session, at: minutes(50)) == .settling)
        #expect(route(session, at: minutes(50).addingTimeInterval(2 * 3600)) == .settling)
        #expect(route(session, at: minutes(50), minimised: true) == .settling)
    }

    @Test("An unseen receipt comes before the start screen and Needs Screen Time")
    func receipt() {
        let id = UUID()
        #expect(route(at: start, receipt: id) == .receipt(id))
        #expect(route(at: start, receipt: id, canBlock: false) == .receipt(id))
    }

    @Test("Without blocking the tab offers Needs Screen Time, and the start screen once the plain timer is chosen")
    func withoutBlocking() throws {
        #expect(route(at: start) == .start)
        #expect(route(at: start, canBlock: false) == .needsScreenTime)
        #expect(route(at: start, canBlock: false, plainTimer: true) == .start)
        // Minimised with nothing running, and an ended session passed as running, are just the start screen.
        #expect(route(at: start, minimised: true) == .start)
        #expect(route(try ended(), at: minutes(60)) == .start)
    }

    @Test("The route changes by itself at the break's end, else at the planned end")
    func nextChange() throws {
        let session = try running(breakAfter: 30)
        #expect(FocusRoute.nextChange(running: try running(), now: minutes(10)) == minutes(50))
        #expect(FocusRoute.nextChange(running: session, now: minutes(31)) == minutes(35))
        #expect(FocusRoute.nextChange(running: nil, now: minutes(10)) == nil)
        #expect(FocusRoute.nextChange(running: try ended(), now: minutes(60)) == nil)
    }

    @Test("While a session runs the store refreshes every 15 seconds, and at the break's end and the planned end")
    func refreshCadence() throws {
        let session = try running(breakAfter: 30)
        #expect(FocusRefresh.interval == 15)
        #expect(FocusRefresh.next(after: minutes(10), running: session) == minutes(10).addingTimeInterval(15))
        #expect(FocusRefresh.next(after: minutes(35).addingTimeInterval(-6), running: session) == minutes(35))
        #expect(FocusRefresh.next(after: minutes(50).addingTimeInterval(-4), running: session) == minutes(50))
        // Past the planned end: at once.
        #expect(FocusRefresh.next(after: minutes(51), running: session) == minutes(51))
        #expect(FocusRefresh.next(after: minutes(10), running: nil) == nil)
        #expect(FocusRefresh.next(after: minutes(60), running: try ended()) == nil)
    }
}
