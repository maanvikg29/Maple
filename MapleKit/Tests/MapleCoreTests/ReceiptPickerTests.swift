import Foundation
import Testing
@testable import MapleCore

@Suite("Session display")
struct SessionDisplayTests {
    @Test("Ended at is the planned end for an on-time session noticed late, and the end itself otherwise")
    func endedAt() throws {
        let late = FocusDay(at(2026, 10, 23, 14))
        let lateID = late.session(minutes: 0, planned: 50, reason: nil)
        late.at(at(2026, 10, 23, 16))                                       // the relaunch noticed it at 16:00
        late.write(.sessionEnded(.completed, verified: true), session: lateID)
        let onTime = try #require(late.ledger.sessions().first)
        #expect(onTime.end?.placed == at(2026, 10, 23, 16))
        #expect(onTime.endedAt == onTime.plannedEnd)

        let early = FocusDay(at(2026, 10, 23, 14))
        early.session(minutes: 18, planned: 50, reason: .endedEarly)
        let ended = try #require(early.ledger.sessions().first)
        #expect(ended.endedAt == ended.countdownStart.addingTimeInterval(18 * 60))

        let released = FocusDay(at(2026, 10, 23, 14))
        released.session(minutes: 18, planned: 50, reason: .emergencyRelease)
        let release = try #require(released.ledger.sessions().first)
        #expect(release.endedAt == release.end?.placed)

        let running = FocusDay(at(2026, 10, 23, 14))
        running.session(minutes: 10, planned: 50, reason: nil)
        #expect(try #require(running.ledger.sessions().first).endedAt == nil)
    }

    @Test("Time left is the planned end less now, never below zero, and nothing once the session has ended")
    func secondsLeft() throws {
        let day = FocusDay(at(2026, 10, 23, 14))
        let id = day.session(minutes: 18, planned: 50, reason: nil)
        let running = try #require(day.ledger.sessions().first)
        let minute18 = running.countdownStart.addingTimeInterval(18 * 60)
        #expect(running.secondsLeft(at: minute18) == 32 * 60)
        #expect(running.secondsLeft(at: running.plannedEnd) == 0)
        #expect(running.secondsLeft(at: running.plannedEnd.addingTimeInterval(90)) == 0)
        day.write(.sessionEnded(.endedEarly, verified: true), session: id)
        #expect(try #require(day.ledger.sessions().first).secondsLeft(at: minute18) == 0)
    }

    @Test("A break runs 5 minutes from its start, ends early on Back to studying, and stops at the planned end")
    func breaks() throws {
        let day = FocusDay(at(2026, 10, 23, 14))
        let id = day.session(minutes: 30, planned: 50, reason: nil)
        day.write(.breakStarted(seconds: 300), session: id)                 // minute 30
        let inBreak = try #require(day.ledger.sessions().first)
        let start = inBreak.countdownStart
        #expect(inBreak.isInBreak(at: start.addingTimeInterval(31 * 60)))
        #expect(inBreak.breakSecondsLeft(at: start.addingTimeInterval(31 * 60)) == TimeInterval(4 * 60))
        #expect(!inBreak.isInBreak(at: start.addingTimeInterval(35 * 60)))
        #expect(inBreak.breakSecondsLeft(at: start.addingTimeInterval(35 * 60)) == nil)

        day.time.advance(60)
        day.write(.breakEnded, session: id)                                 // Back to studying at minute 31
        let back = try #require(day.ledger.sessions().first)
        #expect(!back.isInBreak(at: start.addingTimeInterval(31 * 60 + 10)))
        #expect(back.breakSecondsLeft(at: start.addingTimeInterval(31 * 60 + 10)) == nil)

        let late = FocusDay(at(2026, 10, 23, 14))
        let lateID = late.session(minutes: 48, planned: 50, reason: nil)
        late.write(.breakStarted(seconds: 300), session: lateID)            // 2 minutes before the end
        let cut = try #require(late.ledger.sessions().first)
        #expect(cut.breakSecondsLeft(at: cut.countdownStart.addingTimeInterval(49 * 60)) == 60)
        #expect(!cut.isInBreak(at: cut.plannedEnd))
    }
}

@Suite("Receipt picker")
struct ReceiptPickerTests {
    /// Study 10:00–10:50, then Quick 12:00–12:25.
    private func twoSessions() -> (day: FocusDay, first: UUID, second: UUID) {
        let day = FocusDay(at(2026, 10, 23, 10))
        let first = day.session(minutes: 50)
        day.at(at(2026, 10, 23, 12))
        let second = day.session(minutes: 25)
        return (day, first, second)
    }

    @Test("The newest ended session's receipt shows until it is seen; an older unseen one never comes back")
    func once() {
        let (day, first, second) = twoSessions()
        let sessions = day.ledger.sessions()
        let now = at(2026, 10, 23, 13)
        #expect(ReceiptPicker.pending(sessions, seen: nil, now: now)?.id == second)
        #expect(ReceiptPicker.pending(sessions, seen: first, now: now)?.id == second)
        #expect(ReceiptPicker.pending(sessions, seen: second, now: now) == nil)
        #expect(ReceiptPicker.pending([], seen: nil, now: now) == nil)
    }

    @Test("A receipt waits until 24 hours after its session ended")
    func window() throws {
        let (day, _, second) = twoSessions()
        let sessions = day.ledger.sessions()
        let ended = try #require(sessions.last?.endedAt)
        #expect(ReceiptPicker.window == 24 * 3600)
        #expect(ReceiptPicker.pending(sessions, seen: nil, now: ended.addingTimeInterval(24 * 3600 - 1))?.id == second)
        #expect(ReceiptPicker.pending(sessions, seen: nil, now: ended.addingTimeInterval(24 * 3600)) == nil)
    }

    @Test("A session that ended while away is dated at its planned end, so its 24 hours run from there")
    func endedAway() throws {
        let day = FocusDay(at(2026, 10, 23, 14))
        let id = day.session(minutes: 0, planned: 50, reason: nil)
        day.at(at(2026, 10, 24, 13))                                        // noticed the next day
        day.write(.sessionEnded(.completed, verified: true), session: id)
        let sessions = day.ledger.sessions()
        let session = try #require(sessions.first)
        #expect(ReceiptPicker.pending(sessions, seen: nil, now: at(2026, 10, 24, 13))?.id == id)
        // 24 hours after the planned end, though the end was written less than two hours ago.
        #expect(ReceiptPicker.pending(sessions, seen: nil, now: session.plannedEnd.addingTimeInterval(24 * 3600)) == nil)
    }

    @Test("A running session has no receipt; the one before it still waits")
    func running() {
        let day = FocusDay(at(2026, 10, 23, 10))
        let first = day.session(minutes: 50)
        day.at(at(2026, 10, 23, 12))
        day.session(minutes: 10, planned: 25, reason: nil)
        #expect(ReceiptPicker.pending(day.ledger.sessions(), seen: nil, now: at(2026, 10, 23, 12, 10))?.id == first)
    }

    @Test("A start written only halfway and a hidden session never show; a plain timer does")
    func skipped() {
        let day = FocusDay(at(2026, 10, 23, 10))
        let real = day.session(minutes: 50)
        day.at(at(2026, 10, 23, 11))
        // The block was applied but the start couldn't be written whole: ended at once, never confirmed.
        let ghost = UUID()
        day.write(.sessionStarted(FocusFixtures.plan()), session: ghost)
        day.write(.sessionEnded(.endedEarly, verified: false), session: ghost)
        #expect(ReceiptPicker.pending(day.ledger.sessions(), seen: nil, now: at(2026, 10, 23, 11, 5))?.id == real)

        day.at(at(2026, 10, 23, 12))
        let hidden = day.session(minutes: 25)
        day.write(.sessionHidden, session: hidden)
        #expect(ReceiptPicker.pending(day.ledger.sessions(), seen: nil, now: at(2026, 10, 23, 12, 30))?.id == real)

        day.at(at(2026, 10, 23, 13))
        let plain = day.session(minutes: 25, plan: FocusFixtures.plan(minutes: 25, kind: .plainTimer, selection: nil))
        #expect(ReceiptPicker.pending(day.ledger.sessions(), seen: nil, now: at(2026, 10, 23, 13, 30))?.id == plain)
    }

    @Test("A tapped session end shows its receipt only when nothing else runs and, once the ledger is read, the session is known")
    func tapped() {
        let day = FocusDay(at(2026, 10, 23, 10))
        let old = day.session(minutes: 50)
        day.at(at(2026, 10, 23, 12))
        let ended = day.session(minutes: 25)
        let unknown = UUID()
        let sessions = day.ledger.sessions()
        // Nothing runs: a known session shows; one the ledger doesn't hold never does, so the tab can't wait on it.
        #expect(ReceiptPicker.canShow(old, isLoaded: true, running: nil, sessions: sessions))
        #expect(ReceiptPicker.canShow(ended, isLoaded: true, running: nil, sessions: sessions))
        #expect(!ReceiptPicker.canShow(unknown, isLoaded: true, running: nil, sessions: sessions))
        // Before the first replay nothing is known yet: it may show, and is decided again once the ledger is read.
        #expect(ReceiptPicker.canShow(unknown, isLoaded: false, running: nil, sessions: []))

        // Another session runs: an old end's tap never shows, so the running session's end shows its own receipt.
        day.at(at(2026, 10, 23, 13))
        let current = day.session(minutes: 10, planned: 25, reason: nil)
        let withRunning = day.ledger.sessions()
        let running = withRunning.first { $0.id == current }
        #expect(running?.isEnded == false)
        #expect(!ReceiptPicker.canShow(old, isLoaded: true, running: running, sessions: withRunning))
        #expect(!ReceiptPicker.canShow(unknown, isLoaded: true, running: running, sessions: withRunning))
        // The running session's own end, tapped just before the refresh that ends it, still shows.
        #expect(ReceiptPicker.canShow(current, isLoaded: true, running: running, sessions: withRunning))
    }
}
