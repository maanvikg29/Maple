import Foundation
import Testing
@testable import MapleCore

@Suite("Live Activity state")
struct FocusActivityStateTests {
    private func state(
        isPlainTimer: Bool = false, breakEnd: Date? = nil, intention: String? = nil, leafID: String? = nil
    ) -> FocusActivityState {
        FocusActivityState(
            sessionID: FocusFixtures.session, presetName: "Study", start: at(2026, 10, 23, 14, 2),
            plannedEnd: at(2026, 10, 23, 14, 52), isPlainTimer: isPlainTimer, breakEnd: breakEnd, intention: intention,
            leafID: leafID
        )
    }

    @Test("The Lock Screen shows the preset and the planned end; only the expanded view shows the intention")
    func lockScreenAndExpanded() {
        let lines = state(intention: "Chemistry ch. 4").lines(locale: enGB, calendar: utc)
        #expect(lines.title == "Study")
        #expect(lines.lockLine == "until 14:52 · Study")
        #expect(lines.expandedLine == "Study · Chemistry ch. 4")
        #expect(!lines.lockLine.contains("Chemistry") && !lines.title.contains("Chemistry"))
        #expect(lines.complete == "Session complete")
        #expect(state().lines(locale: enGB, calendar: utc).expandedLine == "Study")
        #expect(state().lines(locale: enUS, calendar: utc).lockLine == "until 2:52 PM · Study")
    }

    @Test("An intention is trimmed and capped at 40 characters")
    func intentionCap() {
        let long = "Organic chemistry chapter four, the long revision before Friday"
        #expect(state(intention: long).intention == "Organic chemistry chapter four, the lon…")
        #expect(state(intention: long).intention?.count == FocusActivityState.intentionLimit)
        let forty = String(repeating: "a", count: 40)
        #expect(FocusActivityState.capped(forty) == forty)
        #expect(state(intention: "  Essay plan \n").intention == "Essay plan")
        #expect(state(intention: "   ").intention == nil)
    }

    @Test("A break names the preset and when the break ends, so the line stays true once it has run out")
    func breakLine() {
        let lines = state(breakEnd: at(2026, 10, 23, 14, 28), intention: "Chemistry ch. 4").lines(locale: enGB, calendar: utc)
        #expect(lines.lockLine == "Study · break until 14:28")
        #expect(lines.expandedLine == "Study · break until 14:28")
        #expect(lines.breakSpoken == "Study, break until 14:28")
        #expect(!lines.expandedLine.contains("Chemistry"))
        let twelveHour = state(breakEnd: at(2026, 10, 23, 14, 28)).lines(locale: enUS, calendar: utc)
        #expect(twelveHour.lockLine == "Study · break until 2:28 PM")
        #expect(twelveHour.expandedLine == "Study · break until 2:28 PM")
        #expect(twelveHour.breakSpoken == "Study, break until 2:28 PM")
        // Outside a break the lines read as they are shown.
        #expect(state(intention: "Chemistry ch. 4").lines(locale: enGB, calendar: utc).breakSpoken == nil)
    }

    @Test("A plain timer is named as one and never shows a leaf")
    func plainTimer() {
        let plain = state(isPlainTimer: true, leafID: "campestre")
        #expect(plain.leafID == nil)
        #expect(plain.described(intention: nil, tint: LeafColor(0x9CC3A4), leafID: "campestre").leafID == nil)
        let lines = plain.lines(locale: enGB, calendar: utc)
        #expect(lines.title == "Plain timer")
        #expect(lines.lockLine == "until 14:52 · Plain timer")
        #expect(lines.expandedLine == "Plain timer")
    }

    @Test("Built from a session, then described with the intention, the season tint and the next leaf")
    func fromSession() throws {
        let script = SessionScript(start: at(2026, 10, 23, 14, 2))
        script.after(5, .shieldApplied)
        let record = try #require(script.record)
        let state = FocusActivityState(session: record, now: at(2026, 10, 23, 14, 20))
        #expect(state.sessionID == FocusFixtures.session)
        #expect(state.presetName == "Study")
        #expect(state.start == at(2026, 10, 23, 14, 2, 5))
        #expect(state.plannedEnd == at(2026, 10, 23, 14, 52, 5))
        #expect(state.intention == nil && state.tint == nil && state.leafID == nil && state.breakEnd == nil)
        let described = state.described(intention: "Chemistry ch. 4", tint: LeafColor(0xE3A49E), leafID: "campestre")
        #expect(described.intention == "Chemistry ch. 4")
        #expect(described.tint == LeafColor(0xE3A49E))
        #expect(described.leafID == "campestre")
        #expect(described.start == state.start && described.plannedEnd == state.plannedEnd && described.sessionID == state.sessionID)
        #expect(described == state.described(intention: "Chemistry ch. 4", tint: LeafColor(0xE3A49E), leafID: "campestre"))
    }
}
