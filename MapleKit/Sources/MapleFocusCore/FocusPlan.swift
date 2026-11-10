import Foundation

/// The verb a preset's capsule uses (F1 design §5.1).
public enum FocusVerb: String, Codable, Sendable, CaseIterable {
    case study, quick, deep, reading, focus

    /// "Start study", "Start a quick session", …
    public var startTitle: String {
        switch self {
        case .study: "Start study"
        case .quick: "Start a quick session"
        case .deep: "Start a deep session"
        case .reading: "Start reading"
        case .focus: "Start focus"
        }
    }
}

/// How hard a session is to leave (focus spec §5.3).
public enum Strictness: String, Codable, Sendable, CaseIterable, Comparable {
    case gentle, steady, locked

    private var rank: Int {
        switch self {
        case .gentle: 0
        case .steady: 1
        case .locked: 2
        }
    }

    public static func < (lhs: Strictness, rhs: Strictness) -> Bool { lhs.rank < rhs.rank }
}

/// A session that locks apps, or a plain timer that counts nothing (R12).
public enum SessionKind: String, Codable, Sendable {
    case blocking, plainTimer
}

/// Where the member started the session.
public enum StartSource: String, Codable, Sendable {
    case focusTab, home, again
}

/// The part of a Maple day that can count, frozen into a session when it starts (F1 design §3.3 step 6).
public struct AwakeWindow: Codable, Sendable, Hashable {
    /// 60 minutes before last night's wake (widened for a short night).
    public var start: Date
    /// Tonight's bedtime.
    public var end: Date
    /// Tonight's wind-down start.
    public var windDown: Date

    public init(start: Date, end: Date, windDown: Date) {
        self.start = start
        self.end = end
        self.windDown = windDown
    }

    public func contains(_ date: Date) -> Bool {
        start <= date && date < end
    }

    public var interval: DateInterval {
        DateInterval(start: start, end: max(start, end))
    }
}

/// What a selection holds, without its tokens (focus spec §5.2). It decides whether a session can count (R3).
public struct SelectionSummary: Codable, Sendable, Hashable {
    public enum Mode: String, Codable, Sendable {
        /// A block list.
        case blockThese
        /// An allow list: everything else is blocked.
        case onlyThese
    }

    /// iOS blocks nothing when a store holds more than this many app or web tokens.
    public static let tokenLimit = 50
    /// "Only these" counts with at most this many apps and sites.
    public static let onlyTheseLimit = 20

    public var mode: Mode
    public var apps: Int
    public var sites: Int
    public var categories: Int

    public init(mode: Mode, apps: Int, sites: Int, categories: Int) {
        self.mode = mode
        self.apps = apps
        self.sites = sites
        self.categories = categories
    }

    public var isEmpty: Bool { apps == 0 && sites == 0 && categories == 0 }

    public var withinTokenLimit: Bool { apps <= Self.tokenLimit && sites <= Self.tokenLimit }

    /// R3 as F1-14 relaxed it: any non-empty "Block these"; "Only these" with no allowed categories and at most 20
    /// apps or sites; never over the token limit.
    public var qualifies: Bool {
        guard withinTokenLimit else { return false }
        switch mode {
        case .blockThese: return !isEmpty
        case .onlyThese: return categories == 0 && apps + sites <= Self.onlyTheseLimit
        }
    }
}

/// Everything about a session that is fixed when it starts, written into `sessionStarted` (F1 design §7.1).
/// It holds no free text beyond the preset's name; intentions live in `session-notes.json`.
public struct FocusPlan: Codable, Sendable, Hashable {
    /// The shortest and longest sessions (R8, F1-15).
    public static let minimumSeconds = 20 * 60
    public static let maximumSeconds = 3 * 3600

    public var presetID: UUID
    public var presetName: String
    public var verb: FocusVerb
    public var plannedSeconds: Int
    /// One locked break inside the planned length, or 0 (F1-11).
    public var breakSeconds: Int
    public var strictness: Strictness
    public var kind: SessionKind
    public var appSetID: UUID?
    /// Frozen at start (R3); nil for a plain timer.
    public var selection: SelectionSummary?
    public var startedFrom: StartSource
    /// The Maple day the session counts toward, as "yyyy-MM-dd" (`FocusPlan.day` in MapleCore reads it as a `LocalDay`).
    public var mapleDay: String
    public var window: AwakeWindow
    public var zone: String
    public var appBuild: String
    public var rulesVersion: Int

    public init(
        presetID: UUID, presetName: String, verb: FocusVerb, plannedSeconds: Int, breakSeconds: Int,
        strictness: Strictness, kind: SessionKind, appSetID: UUID?, selection: SelectionSummary?,
        startedFrom: StartSource, mapleDay: String, window: AwakeWindow, zone: String, appBuild: String,
        rulesVersion: Int
    ) {
        self.presetID = presetID
        self.presetName = presetName
        self.verb = verb
        self.plannedSeconds = plannedSeconds
        self.breakSeconds = breakSeconds
        self.strictness = strictness
        self.kind = kind
        self.appSetID = appSetID
        self.selection = selection
        self.startedFrom = startedFrom
        self.mapleDay = mapleDay
        self.window = window
        self.zone = zone
        self.appBuild = appBuild
        self.rulesVersion = rulesVersion
    }

    /// A blocking session whose selection qualifies: the only kind that can count (R2, R3, R12).
    public var canCount: Bool {
        kind == .blocking && (selection?.qualifies ?? false)
    }

    public var plannedMinutes: Int { plannedSeconds / 60 }
}
