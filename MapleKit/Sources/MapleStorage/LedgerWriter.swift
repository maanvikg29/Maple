import Foundation
import MapleFocusCore
import Synchronization

/// Stamps, numbers and appends one process's events (F1 design §3.1). Sequence numbers carry on after the highest
/// this writer has ever written, so they keep the true append order whatever the clock says. The sequence number and
/// the device id are both read when first needed: until they can be (the ledger and the device id's file are locked
/// after a restart), nothing is written. A guess would start the numbering over, and a stand-in device id would carry
/// events apart from the session they belong to.
public final class LedgerWriter: Sendable {
    /// The store can't say what this writer's highest sequence number is right now, so nothing was written.
    public struct SequenceUnknown: Error {}
    /// This install's device id can't be read right now, so nothing was written.
    public struct DeviceUnknown: Error {}

    public let writer: FocusWriter
    public let source: FocusSource
    public let time: any FocusTimeSource
    private let device: DeviceIDSource
    private let store: any FocusLedgerStore
    /// The highest sequence number written, or nil until the store has been able to say.
    private let lastSeq: Mutex<Int?>

    /// - Parameter device: The device id, read when first needed. Pass the same source to `LiveFocusTime`, so each
    ///   stamp's boot is hashed with the id its event carries.
    public init(store: any FocusLedgerStore, time: any FocusTimeSource, device: DeviceIDSource, writer: FocusWriter, source: FocusSource) {
        self.store = store
        self.time = time
        self.device = device
        self.writer = writer
        self.source = source
        lastSeq = Mutex(store.lastSeq(of: writer))
    }

    /// A writer whose device id is known up front: demos and tests.
    public convenience init(store: any FocusLedgerStore, time: any FocusTimeSource, deviceID: UUID, writer: FocusWriter, source: FocusSource) {
        self.init(store: store, time: time, device: DeviceIDSource(deviceID), writer: writer, source: source)
    }

    /// This install's device id; nil while it can't be read.
    public var deviceID: UUID? { device.id }

    /// Writes `kind` for `session`, stamped now. Throws `DeviceUnknown` or `SequenceUnknown` while the device id or the
    /// highest sequence number still can't be read, and the store's error when it can't write; either way nothing is
    /// recorded.
    @discardableResult
    public func write(_ kind: FocusEventKind, session: UUID, id: String? = nil) throws -> FocusEvent {
        try lastSeq.withLock { known in
            guard let deviceID = device.id else { throw DeviceUnknown() }
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
