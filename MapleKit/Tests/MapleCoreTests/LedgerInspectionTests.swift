#if DEBUG
import Foundation
import Testing
@testable import MapleCore
@testable import MapleFocusCore

@Suite("Ledger inspector")
struct LedgerInspectionTests {
    @Test("Newest first: the kind, the session, the writer and sequence, the source and the wall time")
    func rows() {
        let script = SessionScript(start: at(2026, 10, 23, 14, 2))
        script.after(5, .shieldApplied)
        script.after(60, .shieldVerified)
        let page = LedgerInspection.page(script.events, calendar: utc)
        #expect(page.rows.map(\.kind) == ["shieldVerified", "shieldApplied", "sessionStarted"])
        #expect(page.rows.map(\.time) == ["2026-10-23 14:03:05", "2026-10-23 14:02:05", "2026-10-23 14:02:00"])
        #expect(page.rows.first?.detail == "session 00000000 · app #3 · live")
        #expect(page.rows.map(\.id) == script.events.reversed().map(\.id))
        #expect(page.summary == "3 events · 1 session")
    }

    @Test("No content reaches a row: not the preset's name, a length or a reflection")
    func noContent() {
        var plan = FocusFixtures.plan()
        plan.presetName = "Organic chemistry"
        let script = SessionScript(start: at(2026, 10, 23, 14, 2), plan: plan)
        script.after(5, .shieldApplied)
        script.after(600, .breakStarted(seconds: 300))
        script.after(300, .breakEnded)
        script.after(1800, .sessionEnded(.completed, verified: true))
        script.after(10, .reflected(.partly))
        let page = LedgerInspection.page(script.events, calendar: utc)
        #expect(page.rows.count == 6)
        for row in page.rows {
            for text in [row.kind, row.detail, row.time] {
                #expect(!text.contains("Organic") && !text.contains("300") && !text.contains("partly") && !text.contains("completed"))
            }
        }
        #expect(page.rows.map(\.kind).first == "reflected")
    }

    @Test("Two sessions are counted apart, and one event reads in the singular")
    func summary() {
        let first = SessionScript(start: at(2026, 10, 23, 9, 0))
        let other = UUID(uuidString: "00000000-0000-4000-8000-0000000000B2")!
        let second = SessionScript(start: at(2026, 10, 23, 15, 0), session: other)
        #expect(LedgerInspection.page(first.events + second.events, calendar: utc).summary == "2 events · 2 sessions")
        #expect(LedgerInspection.page(first.events, calendar: utc).summary == "1 event · 1 session")
        #expect(LedgerInspection.page([], calendar: utc).summary == "0 events · 0 sessions")
    }
}
#endif
