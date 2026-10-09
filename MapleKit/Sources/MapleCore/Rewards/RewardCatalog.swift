import Foundation

/// The design rarity of a reward rung. Shown as a neutral chip, never ranked against other people.
public enum RewardTier: String, Codable, Sendable, CaseIterable, Comparable {
    case firstSteps = "first-steps"
    case common, uncommon, rare, legendary

    public var displayName: String {
        switch self {
        case .firstSteps: "First steps"
        case .common: "Common"
        case .uncommon: "Uncommon"
        case .rare: "Rare"
        case .legendary: "Legendary"
        }
    }

    public static func < (lhs: RewardTier, rhs: RewardTier) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

/// One behaviour Maple counts, with its ladder of thresholds. Decoded from `rewards.json`.
public struct RewardCategory: Codable, Sendable, Hashable, Identifiable {
    public let id: RewardCategoryID
    public let name: String
    /// Exact definition of what is counted; the engine must match it.
    public let metric: String
    public let unit: String
    public let dataSource: String
    /// Release that makes this measurable (data only; never displayed).
    public let availableFrom: String
    public let ladder: [Double]

    public var info: RewardCategoryInfo { RewardCategoryInfo(id) }

    enum CodingKeys: String, CodingKey {
        case id, name, metric, unit, ladder
        case dataSource = "data_source"
        case availableFrom = "available_from"
    }
}

/// Which species a rung awards, and the user-facing rule for earning it.
public struct RewardAssignment: Codable, Sendable, Hashable {
    public let speciesID: String
    public let categoryID: RewardCategoryID
    public let threshold: Double
    /// Short, user-facing rule, e.g. "Track 3 nights of sleep".
    public let unlockText: String
    public let tier: RewardTier
    /// Why this species fits this rung (design note, not shown in the app).
    public let rationale: String

    enum CodingKeys: String, CodingKey {
        case threshold, tier, rationale
        case speciesID = "species_id"
        case categoryID = "category_id"
        case unlockText = "unlock_text"
    }
}

/// The complete reward table: every species is exactly one rung on one category's ladder.
public final class RewardCatalog: Sendable {
    public static let shared = RewardCatalog()

    /// Categories in canonical display order.
    public let categories: [RewardCategory]
    public let assignments: [RewardAssignment]
    private let bySpecies: [String: RewardAssignment]
    private let rungsByCategory: [RewardCategoryID: [RewardAssignment]]

    public init(categories: [RewardCategory], assignments: [RewardAssignment]) {
        self.categories = categories.sorted { $0.info.order < $1.info.order }
        self.assignments = assignments
        self.bySpecies = Dictionary(uniqueKeysWithValues: assignments.map { ($0.speciesID, $0) })
        self.rungsByCategory = Dictionary(grouping: assignments, by: \.categoryID)
            .mapValues { $0.sorted { $0.threshold < $1.threshold } }
    }

    private convenience init() {
        struct File: Decodable {
            let categories: [RewardCategory]
            let assignments: [RewardAssignment]
        }
        guard let url = Bundle.module.url(forResource: "rewards", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else {
            preconditionFailure("rewards.json is missing or malformed; it ships inside MapleCore.")
        }
        self.init(categories: file.categories, assignments: file.assignments)
    }

    /// The rung that awards a species.
    public func reward(forSpecies id: String) -> RewardAssignment? {
        bySpecies[id]
    }

    public func category(_ id: RewardCategoryID) -> RewardCategory? {
        categories.first { $0.id == id }
    }

    /// A category's rungs from lowest to highest threshold.
    public func rungs(in category: RewardCategoryID) -> [RewardAssignment] {
        rungsByCategory[category] ?? []
    }
}
