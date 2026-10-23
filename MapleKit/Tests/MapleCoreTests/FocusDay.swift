import Foundation
@testable import MapleCore

/// A day of sessions written on one clock, as the app would write them.
final class FocusDay {
    let time: ManualFocusTime
    private(set) var events: [FocusEvent] = []
    private var seq = 0

    init(_ start: Date) {
        time = ManualFocusTime(wall: start)
    }

    /// Moves the clocks forward to `date`.
    func at(_ date: Date) {
        time.advance(date.timeIntervalSince(time.now))
    }

    func write(_ kind: FocusEventKind, session: UUID, source: FocusSource = .live) {
        seq += 1
        events.append(FocusEvent(id: "\(session.uuidString.prefix(8))-\(seq)", kind: kind, sessionID: session,
                                 deviceID: FocusFixtures.device, writer: .app, seq: seq, source: source, stamp: time.stamp()))
    }

    /// A session from now: the block is confirmed 5 seconds after the tap, overrides happen at the given minutes, and
    /// after `minutes` it ends with a verified `reason` (nil leaves it running).
    @discardableResult
    func session(
        minutes: Int, planned: Int? = nil, reason: EndReason? = .completed, plan: FocusPlan? = nil,
        overrides: [(minute: Int, seconds: Int)] = [], source: FocusSource = .live
    ) -> UUID {
        let id = UUID()
        write(.sessionStarted(plan ?? FocusFixtures.plan(minutes: planned ?? minutes)), session: id, source: source)
        time.advance(5)
        write(.shieldApplied, session: id, source: source)
        var elapsed = 0
        for override in overrides.sorted(by: { $0.minute < $1.minute }) {
            time.advance(TimeInterval(override.minute * 60 - elapsed))
            write(.overrideStarted(seconds: override.seconds), session: id, source: source)
            time.advance(TimeInterval(override.seconds))
            write(.overrideEnded, session: id, source: source)
            elapsed = override.minute * 60 + override.seconds
        }
        time.advance(TimeInterval(minutes * 60 - elapsed))
        if let reason { write(.sessionEnded(reason, verified: true), session: id, source: source) }
        return id
    }

    var ledger: FocusLedger { FocusLedger(events) }

    func credits(now: Date? = nil, sources: Set<FocusSource> = [.live]) -> [SessionCredit] {
        HoursCredit.credit(ledger.sessions(), crediting: sources, now: now ?? time.now)
    }
}
