import Foundation
@testable import MapleCore
@testable import MapleFocusCore

/// Writes one session's events with a manual clock, as the app would: `after(60, .shieldVerified)` advances the
/// clocks a minute and writes a read-back.
final class SessionScript {
    let time: ManualFocusTime
    let session: UUID
    let source: FocusSource
    private(set) var events: [FocusEvent] = []
    private var seq: Int

    init(start: Date, session: UUID = FocusFixtures.session, plan: FocusPlan = FocusFixtures.plan(), source: FocusSource = .live,
         time: ManualFocusTime? = nil, firstSeq: Int = 0) {
        self.time = time ?? ManualFocusTime(wall: start)
        self.session = session
        self.source = source
        seq = firstSeq
        if time != nil { self.time.setWall(start) }
        write(.sessionStarted(plan))
    }

    func write(_ kind: FocusEventKind, writer: FocusWriter = .app, id: String? = nil) {
        seq += 1
        events.append(FocusEvent(id: id ?? "\(session.uuidString.prefix(8))-\(seq)", kind: kind, sessionID: session,
                                 deviceID: FocusFixtures.device, writer: writer, seq: seq, source: source, stamp: time.stamp()))
    }

    func after(_ seconds: TimeInterval, _ kind: FocusEventKind) {
        time.advance(seconds)
        write(kind)
    }

    var ledger: FocusLedger { FocusLedger(events) }
    var record: SessionRecord? { ledger.sessions().first }
}
