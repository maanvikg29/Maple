import Foundation

/// An event and where it falls on trusted time (F1 design §3.2).
public struct PlacedEvent: Sendable, Hashable {
    public let event: FocusEvent
    /// Its boot's anchor plus the continuous time elapsed since.
    public let placed: Date

    public init(event: FocusEvent, placed: Date) {
        self.event = event
        self.placed = placed
    }
}

/// Every focus event, merged by id and put in order (F1 design §3.2). Pure and deterministic: merging in any order,
/// any number of times, gives the same ledger.
public struct FocusLedger: Sendable, Equatable {
    public private(set) var events: [FocusEvent]

    public init(_ events: [FocusEvent] = []) {
        self.events = []
        merge(events)
    }

    /// Adds events, keeping one per id. When two differ under one id (a derived id written by two processes), the
    /// one that sorts first by writer, continuous time and sequence wins, whatever order they arrive in.
    public mutating func merge(_ more: [FocusEvent]) {
        var byID: [String: FocusEvent] = Dictionary(minimumCapacity: events.count + more.count)
        for event in events + more {
            if let kept = byID[event.id], !Self.prefers(event, over: kept) { continue }
            byID[event.id] = event
        }
        events = Self.ordered(Array(byID.values))
    }

    /// The events on trusted time, in ledger order. Within a boot each is placed at the boot's first wall time plus
    /// the continuous time since, so a clock change inside a boot moves nothing; a boot's anchor is never earlier
    /// than the last placed event of the boot before it on the same device.
    public func placed() -> [PlacedEvent] {
        var result: [PlacedEvent] = []
        result.reserveCapacity(events.count)
        var lastPlaced: [UUID: Date] = [:]
        var anchorKey: BootKey?
        var anchorWall = Date.distantPast
        var anchorStamp: EventStamp?
        for event in events {
            let key = BootKey(device: event.deviceID, boot: event.stamp.boot)
            if key != anchorKey {
                anchorKey = key
                anchorWall = max(event.stamp.wall, lastPlaced[event.deviceID] ?? .distantPast)
                anchorStamp = event.stamp
            }
            let since = anchorStamp.map { event.stamp.seconds(since: $0) } ?? 0
            let placed = anchorWall.addingTimeInterval(since)
            lastPlaced[event.deviceID] = max(lastPlaced[event.deviceID] ?? .distantPast, placed)
            result.append(PlacedEvent(event: event, placed: placed))
        }
        return result
    }

    /// Every session in the ledger, in start order (F1 design §3.3).
    public func sessions() -> [SessionRecord] {
        var grouped: [UUID: [PlacedEvent]] = [:]
        for item in placed() { grouped[item.event.sessionID, default: []].append(item) }
        return grouped.values.compactMap { SessionRecord(events: $0) }
            .sorted { ($0.started.placed, $0.id.uuidString) < ($1.started.placed, $1.id.uuidString) }
    }

    // MARK: Order

    struct BootKey: Hashable {
        let device: UUID
        let boot: String
    }

    static func prefers(_ a: FocusEvent, over b: FocusEvent) -> Bool {
        if a.writer != b.writer { return a.writer < b.writer }
        if a.stamp.continuous != b.stamp.continuous { return a.stamp.continuous < b.stamp.continuous }
        if a.seq != b.seq { return a.seq < b.seq }
        if a.stamp.wall != b.stamp.wall { return a.stamp.wall < b.stamp.wall }
        if a.stamp.boot != b.stamp.boot { return a.stamp.boot < b.stamp.boot }
        return a.kind.type < b.kind.type
    }

    /// Each device's boots in order: by the app writer's first sequence number in the boot (its true append order),
    /// then by the boot's first wall time. Boots only extensions saw sort after the app's (F1-paid revisits this).
    static func bootRanks(_ events: [FocusEvent]) -> [BootKey: Int] {
        var firstAppSeq: [BootKey: Int] = [:]
        var firstWall: [BootKey: Date] = [:]
        for event in events {
            let key = BootKey(device: event.deviceID, boot: event.stamp.boot)
            // Real sequence numbers start at 1; a 0 is a line whose seq didn't read, so it says nothing about order.
            if event.writer == .app, event.seq > 0 { firstAppSeq[key] = min(firstAppSeq[key] ?? .max, event.seq) }
            firstWall[key] = min(firstWall[key] ?? .distantFuture, event.stamp.wall)
        }
        let keys = firstWall.keys.sorted { a, b in
            let sa = firstAppSeq[a] ?? .max, sb = firstAppSeq[b] ?? .max
            if sa != sb { return sa < sb }
            let wa = firstWall[a] ?? .distantFuture, wb = firstWall[b] ?? .distantFuture
            if wa != wb { return wa < wb }
            return a.boot < b.boot
        }
        return Dictionary(uniqueKeysWithValues: keys.enumerated().map { ($0.element, $0.offset) })
    }

    static func ordered(_ events: [FocusEvent]) -> [FocusEvent] {
        let ranks = bootRanks(events)
        return events.sorted { a, b in
            if a.deviceID != b.deviceID { return a.deviceID.uuidString < b.deviceID.uuidString }
            let ra = ranks[BootKey(device: a.deviceID, boot: a.stamp.boot)] ?? 0
            let rb = ranks[BootKey(device: b.deviceID, boot: b.stamp.boot)] ?? 0
            if ra != rb { return ra < rb }
            if a.stamp.continuous != b.stamp.continuous { return a.stamp.continuous < b.stamp.continuous }
            if a.writer != b.writer { return a.writer < b.writer }
            if a.seq != b.seq { return a.seq < b.seq }
            return a.id < b.id
        }
    }
}
