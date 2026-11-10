#if DEBUG
import Foundation
import MapleCore

/// DEBUG only: what the fake app picker offers, and how it stores a choice (F1 design §5.14). An `AppSet` keeps this
/// choice's JSON as its opaque selection; F1-paid's Apple picker keeps its own selection there instead.
nonisolated public struct PickerChoice: Codable, Sendable, Equatable {
    nonisolated public enum Kind: String, Codable, Sendable, CaseIterable {
        case app, site, category

        public var title: String {
            switch self {
            case .app: "Apps"
            case .site: "Sites"
            case .category: "Categories"
            }
        }
    }

    nonisolated public struct Sample: Sendable, Hashable, Identifiable {
        public let id: String
        public let name: String
        public let kind: Kind
    }

    /// 12 apps, 3 sites and 3 categories, in the order the picker lists them.
    public static let samples: [Sample] = [
        Sample(id: "app.shorts", name: "Short videos", kind: .app),
        Sample(id: "app.photos", name: "Photo feed", kind: .app),
        Sample(id: "app.chat", name: "Group chat", kind: .app),
        Sample(id: "app.streaming", name: "Video streaming", kind: .app),
        Sample(id: "app.forum", name: "Forum", kind: .app),
        Sample(id: "app.puzzle", name: "Puzzle game", kind: .app),
        Sample(id: "app.battle", name: "Battle game", kind: .app),
        Sample(id: "app.shopping", name: "Shopping", kind: .app),
        Sample(id: "app.news", name: "News", kind: .app),
        Sample(id: "app.music", name: "Music", kind: .app),
        Sample(id: "app.messages", name: "Messages", kind: .app),
        Sample(id: "app.maps", name: "Maps", kind: .app),
        Sample(id: "site.video", name: "video.example", kind: .site),
        Sample(id: "site.social", name: "social.example", kind: .site),
        Sample(id: "site.news", name: "news.example", kind: .site),
        Sample(id: "category.social", name: "Social", kind: .category),
        Sample(id: "category.games", name: "Games", kind: .category),
        Sample(id: "category.entertainment", name: "Entertainment", kind: .category),
    ]

    /// The one row that counts as this many apps, to try the 50-app limit.
    public static let bulkApps = 45
    public static let bulkTitle = "45 more sample apps"

    /// "12 other apps": apps a stored list counts beyond the samples.
    public static func othersTitle(_ count: Int) -> String {
        "\(count) other \(count == 1 ? "app" : "apps")"
    }

    public var picked: Set<String>
    public var bulk: Bool
    /// Apps a stored list counts that the samples can't show (a seeded demo list of 24), as one row until unticked.
    public var otherApps: Int

    public init(picked: Set<String> = [], bulk: Bool = false, otherApps: Int = 0) {
        self.picked = picked
        self.bulk = bulk
        self.otherApps = otherApps
    }

    /// A stored choice; or, for a selection the picker didn't write (a seeded demo list), the first samples of each
    /// kind its summary counts, so the counter matches the list.
    public init(data: Data, summary: SelectionSummary) {
        if let stored = try? JSONDecoder().decode(PickerChoice.self, from: data) {
            self = stored
            return
        }
        let apps = Self.samples.filter { $0.kind == .app }
        let sites = Self.samples.filter { $0.kind == .site }
        let categories = Self.samples.filter { $0.kind == .category }
        picked = Set(apps.prefix(max(0, summary.apps)).map(\.id) + sites.prefix(max(0, summary.sites)).map(\.id)
            + categories.prefix(max(0, summary.categories)).map(\.id))
        bulk = false
        otherApps = max(0, summary.apps - apps.count)
    }

    public func summary(mode: SelectionSummary.Mode) -> SelectionSummary {
        func count(_ kind: Kind) -> Int { Self.samples.filter { $0.kind == kind && picked.contains($0.id) }.count }
        return SelectionSummary(
            mode: mode, apps: count(.app) + (bulk ? Self.bulkApps : 0) + otherApps, sites: count(.site),
            categories: count(.category)
        )
    }

    /// The opaque selection: this choice as JSON, ids sorted, so an unchanged choice is the same bytes.
    public var data: Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)) ?? Data()
    }

    /// Whether saving this choice in `mode` would leave the list as saved. A list the picker didn't write (a seeded
    /// one) is stored in other bytes than this choice would be, so it compares choices, never bytes.
    public func isUnchanged(from data: Data, summary: SelectionSummary, mode: SelectionSummary.Mode) -> Bool {
        mode == summary.mode && self == PickerChoice(data: data, summary: summary)
    }

    public mutating func toggle(_ id: String) {
        if picked.contains(id) { picked.remove(id) } else { picked.insert(id) }
    }

    // MARK: Codable (ids as a sorted array, so the bytes are stable)

    private enum CodingKeys: String, CodingKey {
        case picked, bulk, otherApps
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        picked = Set(try c.decode([String].self, forKey: .picked))
        bulk = try c.decode(Bool.self, forKey: .bulk)
        otherApps = try c.decode(Int.self, forKey: .otherApps)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(picked.sorted(), forKey: .picked)
        try c.encode(bulk, forKey: .bulk)
        try c.encode(otherApps, forKey: .otherApps)
    }
}
#endif
