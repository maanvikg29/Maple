import Foundation
import Testing
@testable import MapleCore
@testable import MapleFocusCore

/// Where Maple opens as the member arrives (F1 design §5.4, §5.8; final review Important 1): the Focus tab for a
/// relaunch mid-session and for a receipt that waits, never for a return mid-session, and never over the first run, a
/// reveal, a sheet or a cover.
@Suite("Focus landing")
struct FocusLandingTests {
    /// 14:00. The block is confirmed at 14:00:05, so a 50-minute session ends at 14:50:05.
    private let start = at(2026, 10, 23, 14)

    /// `minutes` into the countdown.
    private func minutes(_ minutes: Double) -> Date {
        start.addingTimeInterval(5 + minutes * 60)
    }

    private func running() throws -> SessionRecord {
        let script = SessionScript(start: start)
        script.after(5, .shieldApplied)
        return try #require(script.record)
    }

    /// A session that ended on time while Maple was closed.
    private func ended() throws -> SessionRecord {
        let script = SessionScript(start: start)
        script.after(5, .shieldApplied)
        script.after(50 * 60, .sessionEnded(.completed, verified: true))
        return try #require(script.record)
    }

    private func opens(
        _ arrival: FocusLanding.Arrival, running: SessionRecord? = nil, sessions: [SessionRecord] = [], seen: UUID? = nil,
        onboarding: Bool = false, presenting: Bool = false, at now: Date
    ) -> Bool {
        FocusLanding.opensFocus(arrival, running: running, sessions: sessions, seen: seen, isOnboarding: onboarding,
                                isPresenting: presenting, now: now)
    }

    @Test("A relaunch mid-session opens on the running session; a return to the foreground mid-session moves no one")
    func midSession() throws {
        let session = try running()
        #expect(opens(.launch, running: session, sessions: [session], at: minutes(18)))
        #expect(!opens(.foreground, running: session, sessions: [session], at: minutes(18)))
    }

    @Test("A receipt that waits opens the Focus tab, at launch and on a return to the foreground, until it is seen")
    func waitingReceipt() throws {
        let session = try ended()
        // Ended while away, 2 hours ago: shown once, when the member next opens Maple.
        #expect(opens(.launch, sessions: [session], at: minutes(170)))
        #expect(opens(.foreground, sessions: [session], at: minutes(170)))
        // Seen, or over a day old: nothing waits.
        #expect(!opens(.launch, sessions: [session], seen: session.id, at: minutes(170)))
        #expect(!opens(.foreground, sessions: [session], seen: session.id, at: minutes(170)))
        #expect(!opens(.launch, sessions: [session], at: minutes(50 + 24 * 60 + 1)))
    }

    @Test("With nothing running and nothing waiting, Maple opens where it would anyway")
    func nothing() {
        #expect(!opens(.launch, at: start))
        #expect(!opens(.foreground, at: start))
    }

    @Test("Never over the first run, a reveal, a sheet or a cover: the receipt waits on the Focus tab")
    func neverMidTask() throws {
        let session = try running()
        let receipt = try ended()
        for arrival in [FocusLanding.Arrival.launch, .foreground] {
            #expect(!opens(arrival, running: session, sessions: [session], onboarding: true, at: minutes(18)))
            #expect(!opens(arrival, running: session, sessions: [session], presenting: true, at: minutes(18)))
            #expect(!opens(arrival, sessions: [receipt], onboarding: true, at: minutes(170)))
            #expect(!opens(arrival, sessions: [receipt], presenting: true, at: minutes(170)))
        }
    }
}
