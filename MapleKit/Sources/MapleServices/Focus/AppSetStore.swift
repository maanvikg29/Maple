import Foundation
import MapleCore
import Observation

/// A named selection of apps, sites and categories (F1 design §5.14). The selection itself is opaque: the blocking
/// service encodes it (Apple's `FamilyActivitySelection` in F1-paid, the DEBUG fake picker's choices in F1).
nonisolated public struct AppSet: Codable, Sendable, Equatable, Identifiable {
    public static let distractionsID = UUID(uuidString: "6D61706C-6500-4153-4554-000000000001")!
    public static let studyAppsID = UUID(uuidString: "6D61706C-6500-4153-4554-000000000002")!
    public static let bedtimeID = UUID(uuidString: "6D61706C-6500-4153-4554-000000000003")!

    public var id: UUID
    public var name: String
    public var selection: Data
    public var summary: SelectionSummary
    /// iOS no longer recognises some of its tokens: "Some apps need choosing again".
    public var tokensExpired: Bool

    public init(id: UUID, name: String, selection: Data = Data(), summary: SelectionSummary, tokensExpired: Bool = false) {
        self.id = id
        self.name = name
        self.selection = selection
        self.summary = summary
        self.tokensExpired = tokensExpired
    }

    /// Distractions, Study apps and Bedtime, empty.
    public static func starters() -> [AppSet] {
        let empty = SelectionSummary(mode: .blockThese, apps: 0, sites: 0, categories: 0)
        return [
            AppSet(id: distractionsID, name: "Distractions", summary: empty),
            AppSet(id: studyAppsID, name: "Study apps", summary: empty),
            AppSet(id: bedtimeID, name: "Bedtime", summary: empty),
        ]
    }
}

nonisolated public struct AppSetsFile: Codable, Sendable, Equatable {
    public var sets: [AppSet]

    public init(sets: [AppSet]) {
        self.sets = sets
    }
}

public enum AppSetSaveResult: Sendable, Equatable {
    case saved
    /// An empty selection is never saved over a non-empty one.
    case wouldEmpty
    /// More than 50 app or 50 web tokens across every set: iOS would silently block nothing.
    case overTokenLimit
    case unknownSet
    /// The saved sets still can't be read (before the first unlock after a restart): nothing was saved.
    case unavailable
}

@Observable
public final class AppSetStore {
    nonisolated public static let file = "app-sets.json"

    public private(set) var sets: [AppSet]
    public private(set) var isAvailable: Bool

    @ObservationIgnored private let storage: JSONStorage<AppSetsFile>

    public init(storage: JSONStorage<AppSetsFile>) {
        self.storage = storage
        let loaded = Self.contents(of: storage.read())
        sets = loaded ?? AppSet.starters()
        isAvailable = loaded != nil
    }

    /// Reads the sets again if they couldn't be read at launch. Every change does this first, so it lands on the
    /// member's real sets, and the empty-over-full and 50-token checks run against them.
    /// - Returns: Whether the store now holds the member's real sets (or knows there are none).
    @discardableResult
    public func reloadIfUnavailable() -> Bool {
        guard !isAvailable else { return false }
        guard let loaded = Self.contents(of: storage.read()) else { return false }
        sets = loaded
        isAvailable = true
        return true
    }

    public func set(id: UUID) -> AppSet? {
        sets.first { $0.id == id }
    }

    /// App and web tokens across every set (the larger of the two counts against the 50-token cap).
    public var totalTokens: Int {
        max(sets.reduce(0) { $0 + $1.summary.apps }, sets.reduce(0) { $0 + $1.summary.sites })
    }

    public func save(selection: Data, summary: SelectionSummary, to id: UUID) -> AppSetSaveResult {
        guard isAvailable || reloadIfUnavailable() else { return .unavailable }
        guard let index = sets.firstIndex(where: { $0.id == id }) else { return .unknownSet }
        if summary.isEmpty, !sets[index].summary.isEmpty { return .wouldEmpty }
        let others = sets.enumerated().filter { $0.offset != index }.map(\.element.summary)
        let apps = others.reduce(summary.apps) { $0 + $1.apps }
        let sites = others.reduce(summary.sites) { $0 + $1.sites }
        guard apps <= SelectionSummary.tokenLimit, sites <= SelectionSummary.tokenLimit else { return .overTokenLimit }
        sets[index].selection = selection
        sets[index].summary = summary
        sets[index].tokensExpired = false
        persist()
        return .saved
    }

    public func markExpired(_ id: UUID, _ expired: Bool) {
        guard isAvailable || reloadIfUnavailable(),
              let index = sets.firstIndex(where: { $0.id == id }), sets[index].tokensExpired != expired else { return }
        sets[index].tokensExpired = expired
        persist()
    }

    /// The saved sets, or the starters when there are none; nil while the file can't be read.
    private static func contents(of read: StorageRead<AppSetsFile>) -> [AppSet]? {
        switch read {
        case .value(let saved) where !saved.sets.isEmpty: saved.sets
        case .value, .absent: AppSet.starters()
        case .unavailable: nil
        }
    }

    private func persist() {
        guard isAvailable else { return }
        storage.save(AppSetsFile(sets: sets))
    }
}
