import Foundation
import MapleFocusCore
import Synchronization

/// Stamps, numbers and appends one process's events (F1 design §3.1). Sequence numbers carry on after the highest
/// this writer has ever written, so they keep the true append order whatever the clock says.
public final class LedgerWriter: Sendable {
    public let deviceID: UUID
    public let writer: FocusWriter
    public let source: FocusSource
    public let time: any FocusTimeSource
    private let store: any FocusLedgerStore
    private let lastSeq: Mutex<Int>

    public init(store: any FocusLedgerStore, time: any FocusTimeSource, deviceID: UUID, writer: FocusWriter, source: FocusSource) {
        self.store = store
        self.time = time
        self.deviceID = deviceID
        self.writer = writer
        self.source = source
        lastSeq = Mutex(store.lastSeq(of: writer))
    }

    /// Writes `kind` for `session`, stamped now. Throws when the store can't write; then nothing is recorded.
    @discardableResult
    public func write(_ kind: FocusEventKind, session: UUID, id: String? = nil) throws -> FocusEvent {
        try lastSeq.withLock { seq in
            let event = FocusEvent(
                id: id ?? UUID().uuidString.lowercased(), kind: kind, sessionID: session, deviceID: deviceID, writer: writer,
                seq: seq + 1, source: source, stamp: time.stamp()
            )
            try store.append(event)
            seq += 1
            return event
        }
    }
}
