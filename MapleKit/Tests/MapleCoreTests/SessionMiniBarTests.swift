import Foundation
import Testing
@testable import MapleCore
@testable import MapleFocusCore

@Suite("Session mini bar")
struct SessionMiniBarTests {
    private let start = at(2026, 10, 23, 14)

    /// Study 50m with its 5-minute break, the block confirmed 5 seconds after 14:00.
    private func confirmed() -> SessionScript {
        let script = SessionScript(start: start, plan: FocusFixtures.plan(breakMinutes: 5))
        script.after(5, .shieldApplied)
        return script
    }

    @Test("Calm minutes left with the preset's name, seconds only in the last minute")
    func timeLeft() throws {
        let record = try #require(confirmed().record)
        let applied = start.addingTimeInterval(5)
        let bar = try #require(SessionMiniBar(session: record, now: applied.addingTimeInterval(18 * 60), calendar: utc, locale: enGB))
        #expect(bar.title == "Study · 32m left")
        #expect(bar.spoken == "Study, 32 minutes left. Return to session.")
        let last = try #require(SessionMiniBar(session: record, now: applied.addingTimeInterval(49 * 60 + 15), calendar: utc, locale: enGB))
        #expect(last.title == "Study · 0:45 left")
        #expect(last.spoken == "Study, 45 seconds left. Return to session.")
    }

    @Test("At 0 seconds left the bar hides until the refresh ends the session: never \"Study · 0:00 left\"")
    func hidesAtTheEnd() throws {
        let record = try #require(confirmed().record)
        let end = record.plannedEnd
        let lastSecond = try #require(SessionMiniBar(session: record, now: end.addingTimeInterval(-0.5), calendar: utc, locale: enGB))
        #expect(lastSecond.title == "Study · 0:01 left")
        #expect(SessionMiniBar(session: record, now: end, calendar: utc, locale: enGB) == nil)
        #expect(SessionMiniBar(session: record, now: end.addingTimeInterval(0.3), calendar: utc, locale: enGB) == nil)
    }

    @Test("During the break: when it ends, in the member's clock style")
    func breakTime() throws {
        let script = confirmed()
        script.after(20 * 60, .breakStarted(seconds: 300))    // 14:20:05, so back at 14:25:05
        let record = try #require(script.record)
        let now = at(2026, 10, 23, 14, 22)
        let bar = try #require(SessionMiniBar(session: record, now: now, calendar: utc, locale: enGB))
        #expect(bar.title == "Break · back at 14:25")
        #expect(bar.spoken == "Break, back at 14:25. Return to session.")
        #expect(SessionMiniBar(session: record, now: now, calendar: utc, locale: enUS)?.title == "Break · back at 2:25 PM")
        // Once the break is over the session's own time comes back.
        let after = try #require(SessionMiniBar(session: record, now: at(2026, 10, 23, 14, 26), calendar: utc, locale: enGB))
        #expect(after.title.hasPrefix("Study · "))
    }

    @Test("Its words are calm, and never show the intention")
    func calm() throws {
        let record = try #require(confirmed().record)
        let bar = try #require(SessionMiniBar(session: record, now: start.addingTimeInterval(600), calendar: utc, locale: enGB))
        for line in [bar.title, bar.spoken] {
            #expect(!line.contains("!"))
            #expect(line.first?.isUppercase == true)
            #expect(!line.lowercased().contains("leaf") && !line.lowercased().contains("streak"))
        }
    }
}
