import Foundation
import MapleFocusCore
import Synchronization

/// Stamps, numbers and appends one process's events (F1 design §3.1). Sequence numbers carry on after the highest
/// this writer has ever written, so they keep the true append order whatever the clock says. When that number can't
/// be read yet (the ledger is locked after a restart), nothing is written until it can: a guess would start the
/// numbering over.
public final class LedgerWriter: Sendable {
    /// The store can't say what this writer's highest sequence number is right now, so nothing was written.
    public struct SequenceUnknown: Error {}

    public let deviceID: UUID
    public let writer: FocusWriter
    public let source: FocusSource
    public let time: any FocusTimeSource
    private let store: any FocusLedgerStore
    /// The highest sequence number written, or nil until the store has been able to say.
    private let lastSeq: Mutex<Int?>

    public init(store: any FocusLedgerStore, time: any FocusTimeSource, deviceID: UUID, writer: FocusWriter, source: FocusSource) {
        self.store = store
        self.time = time
        self.deviceID = deviceID
        self.writer = writer
        self.source = source
        lastSeq = Mutex(store.lastSeq(of: writer))
    }

    /// Writes `kind` for `session`, stamped now. Throws `SequenceUnknown` when the highest sequence number still
    /// can't be read, and the store's error when it can't write; either way nothing is recorded.
    @discardableResult
    public func write(_ kind: FocusEventKind, session: UUID, id: String? = nil) throws -> FocusEvent {
        try lastSeq.withLock { known in
            guard let seq = known ?? store.lastSeq(of: writer) else { throw SequenceUnknown() }
            let event = FocusEvent(
                id: id ?? UUID().uuidString.lowercased(), kind: kind, sessionID: session, deviceID: deviceID, writer: writer,
                seq: seq + 1, source: source, stamp: time.stamp()
            )
            try store.append(event)
            known = seq + 1
            return event
        }
    }
}
