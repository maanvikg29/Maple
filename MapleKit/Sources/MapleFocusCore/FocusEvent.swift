import Foundation

/// The process that wrote an event. Each writes its own ledger file, so no two ever write the same file (F1 design §7.3).
public enum FocusWriter: String, Codable, Sendable, CaseIterable, Comparable {
    case app, monitor, shieldAction

    private var rank: Int {
        switch self {
        case .app: 0
        case .monitor: 1
        case .shieldAction: 2
        }
    }

    public static func < (lhs: FocusWriter, rhs: FocusWriter) -> Bool { lhs.rank < rhs.rank }
}

/// Where an event came from: the real blocker, or DEBUG's preview blocker, which only the sandbox credits (§3.3).
public enum FocusSource: String, Codable, Sendable, CaseIterable {
    case live, preview
}

/// When an event happened, on the clocks Maple can trust (F1 design §3.1–3.2).
public struct EventStamp: Sendable, Hashable, Codable {
    /// The wall clock, which the member can change.
    public var wall: Date
    /// Nanoseconds on the continuous clock, which keeps counting while the phone sleeps and restarts at boot.
    public var continuous: UInt64
    /// This boot, hashed with the device id (`LiveFocusTime`), so it can't be matched across installs.
    public var boot: String
    /// The time zone in force (`TimeZone.identifier`).
    public var zone: String

    public init(wall: Date, continuous: UInt64, boot: String, zone: String) {
        self.wall = wall
        self.continuous = continuous
        self.boot = boot
        self.zone = zone
    }

    /// Seconds from `other` to this stamp on the continuous clock. Only meaningful within one boot.
    public func seconds(since other: EventStamp) -> TimeInterval {
        if continuous >= other.continuous { return TimeInterval(continuous - other.continuous) / 1e9 }
        return -TimeInterval(other.continuous - continuous) / 1e9
    }

    private enum CodingKeys: String, CodingKey {
        case wall, continuous = "cont", boot, zone
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        wall = Date(timeIntervalSince1970: try c.decode(Double.self, forKey: .wall))
        continuous = try c.decode(UInt64.self, forKey: .continuous)
        boot = try c.decode(String.self, forKey: .boot)
        zone = try c.decode(String.self, forKey: .zone)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(wall.timeIntervalSince1970, forKey: .wall)
        try c.encode(continuous, forKey: .continuous)
        try c.encode(boot, forKey: .boot)
        try c.encode(zone, forKey: .zone)
    }
}

/// How a session ended. Only `completed` can be finished (R13).
public enum EndReason: String, Codable, Sendable, CaseIterable {
    /// It reached its planned end.
    case completed
    /// Gentle's or Steady's End early.
    case endedEarly
    /// Locked's 10-second hold.
    case emergencyRelease
    /// Settings › Release all apps.
    case releaseAll
}

/// Why shields came off.
public enum ShieldClearReason: String, Codable, Sendable, CaseIterable {
    case sessionEnded
    case releaseAll
    /// The reconciler found a session past its planned end.
    case expired
    /// Shields with no running session (the app was killed mid-start).
    case orphaned
}

/// The receipt's "How did it go?" answer.
public enum Reflection: String, Codable, Sendable, CaseIterable {
    case allDone, partly, notYet
}

/// What happened (F1 design §3.1).
public enum FocusEventKind: Sendable, Hashable {
    case sessionStarted(FocusPlan)
    /// Written only after Maple read its own block back: credit starts here.
    case shieldApplied
    /// A later read-back that succeeded: a checkpoint.
    case shieldVerified
    /// A read-back that didn't find the block: credit stops at the checkpoint before it.
    case shieldLost
    case breakStarted(seconds: Int)
    case breakEnded
    /// A Gentle or Steady unlock from the shield ("Need it?"); its whole window is removed.
    case overrideStarted(seconds: Int)
    case overrideEnded
    case sessionEnded(EndReason, verified: Bool)
    case shieldCleared(ShieldClearReason)
    case reflected(Reflection)
    /// Reserved for History's delete (F2): hides a session, never its leaves.
    case sessionHidden
    /// A kind this build doesn't know, kept so the session can stop crediting at it.
    case unknown(String)

    /// The kind's name in the ledger file.
    public var type: String {
        switch self {
        case .sessionStarted: "sessionStarted"
        case .shieldApplied: "shieldApplied"
        case .shieldVerified: "shieldVerified"
        case .shieldLost: "shieldLost"
        case .breakStarted: "breakStarted"
        case .breakEnded: "breakEnded"
        case .overrideStarted: "overrideStarted"
        case .overrideEnded: "overrideEnded"
        case .sessionEnded: "sessionEnded"
        case .shieldCleared: "shieldCleared"
        case .reflected: "reflected"
        case .sessionHidden: "sessionHidden"
        case .unknown(let type): type
        }
    }

    /// Whether this kind can change credit. Reflections and hiding never do; unknown kinds are assumed to.
    public var affectsCredit: Bool {
        switch self {
        case .reflected, .sessionHidden: false
        default: true
        }
    }

    /// Ends the session. Only the first one counts.
    public var isTerminal: Bool {
        if case .sessionEnded = self { return true }
        return false
    }

    /// Written right after a read-back that found the block (§3.3 step 2).
    public var isCheckpoint: Bool {
        switch self {
        case .shieldApplied, .shieldVerified, .breakStarted, .breakEnded, .overrideEnded: true
        case .sessionEnded(_, let verified): verified
        default: false
        }
    }
}

/// One line of the append-only focus ledger (F1 design §3.1).
public struct FocusEvent: Sendable, Hashable, Identifiable, Codable {
    public var id: String
    /// The format version, `FocusRules.schemaVersion` when written.
    public var version: Int
    public var kind: FocusEventKind
    public var sessionID: UUID
    /// A random UUID made once per install and kept in the container.
    public var deviceID: UUID
    public var writer: FocusWriter
    /// This writer's sequence number, which only ever goes up (its true append order, whatever the clock says).
    public var seq: Int
    public var source: FocusSource
    public var affectsCredit: Bool
    public var stamp: EventStamp

    public init(
        id: String, kind: FocusEventKind, sessionID: UUID, deviceID: UUID, writer: FocusWriter, seq: Int,
        source: FocusSource, stamp: EventStamp, affectsCredit: Bool? = nil, version: Int = FocusRules.schemaVersion
    ) {
        self.id = id
        self.version = version
        self.kind = kind
        self.sessionID = sessionID
        self.deviceID = deviceID
        self.writer = writer
        self.seq = seq
        self.source = source
        self.affectsCredit = affectsCredit ?? kind.affectsCredit
        self.stamp = stamp
    }

    /// The id any process gives `kind` for `session`, so the same event written twice merges as one (§3.1).
    public static func derivedID(session: UUID, kind: FocusEventKind) -> String {
        session.uuidString.lowercased() + "." + kind.type
    }

    // MARK: Codable: one flat JSON object per line

    private enum CodingKeys: String, CodingKey {
        case id, version = "v", type, sessionID = "session", deviceID = "device", writer, seq, source
        case affectsCredit = "credit", stamp = "at"
        case plan, seconds, reason, verified, answer
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        version = (try? c.decodeIfPresent(Int.self, forKey: .version)) ?? FocusRules.schemaVersion
        sessionID = try c.decode(UUID.self, forKey: .sessionID)
        deviceID = try c.decode(UUID.self, forKey: .deviceID)
        writer = (try? c.decodeIfPresent(FocusWriter.self, forKey: .writer)) ?? .app
        seq = (try? c.decodeIfPresent(Int.self, forKey: .seq)) ?? 0
        // A source this build doesn't know is never credited.
        source = (try? c.decodeIfPresent(FocusSource.self, forKey: .source)) ?? .preview
        stamp = try c.decode(EventStamp.self, forKey: .stamp)
        let type = try c.decode(String.self, forKey: .type)
        // A payload this build can't read keeps the event as `unknown` rather than dropping the line.
        let decoded: FocusEventKind? = switch type {
        case "sessionStarted": (try? c.decode(FocusPlan.self, forKey: .plan)).map { .sessionStarted($0) }
        case "shieldApplied": .shieldApplied
        case "shieldVerified": .shieldVerified
        case "shieldLost": .shieldLost
        case "breakStarted": (try? c.decode(Int.self, forKey: .seconds)).map { .breakStarted(seconds: $0) }
        case "breakEnded": .breakEnded
        case "overrideStarted": (try? c.decode(Int.self, forKey: .seconds)).map { .overrideStarted(seconds: $0) }
        case "overrideEnded": .overrideEnded
        case "sessionEnded":
            (try? c.decode(EndReason.self, forKey: .reason)).map {
                .sessionEnded($0, verified: (try? c.decodeIfPresent(Bool.self, forKey: .verified)) ?? false)
            }
        case "shieldCleared": (try? c.decode(ShieldClearReason.self, forKey: .reason)).map { .shieldCleared($0) }
        case "reflected": (try? c.decode(Reflection.self, forKey: .answer)).map { .reflected($0) }
        case "sessionHidden": .sessionHidden
        default: nil
        }
        kind = decoded ?? .unknown(type)
        affectsCredit = (try? c.decodeIfPresent(Bool.self, forKey: .affectsCredit)) ?? kind.affectsCredit
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(version, forKey: .version)
        try c.encode(kind.type, forKey: .type)
        try c.encode(sessionID, forKey: .sessionID)
        try c.encode(deviceID, forKey: .deviceID)
        try c.encode(writer, forKey: .writer)
        try c.encode(seq, forKey: .seq)
        try c.encode(source, forKey: .source)
        try c.encode(affectsCredit, forKey: .affectsCredit)
        try c.encode(stamp, forKey: .stamp)
        switch kind {
        case .sessionStarted(let plan): try c.encode(plan, forKey: .plan)
        case .breakStarted(let seconds), .overrideStarted(let seconds): try c.encode(seconds, forKey: .seconds)
        case .sessionEnded(let reason, let verified):
            try c.encode(reason, forKey: .reason)
            try c.encode(verified, forKey: .verified)
        case .shieldCleared(let reason): try c.encode(reason, forKey: .reason)
        case .reflected(let answer): try c.encode(answer, forKey: .answer)
        case .shieldApplied, .shieldVerified, .shieldLost, .breakEnded, .overrideEnded, .sessionHidden, .unknown: break
        }
    }
}
