import Foundation

/// The tree's two growth axes (design spec §4.1):
/// structure grows with *tended days*, and foliage shows the *species collected*.
public enum TreeGrowth {
    /// Days after which the branch structure is fully grown.
    public static let maturityDays = 540.0

    /// Structural growth `g` in 0...1. Never decreases as tended days increase, and moves visibly from day 1.
    public static func structure(tendedDays: Int) -> Double {
        guard tendedDays > 0 else { return 0 }
        return min(1, pow(Double(tendedDays) / maturityDays, 0.6))
    }

    /// Hard cap on drawn leaf instances.
    public static let maxLeafInstances = 480

    /// How many leaf instances the tree draws for `species` collected at structural growth `g` (spec §4.5).
    /// Never decreases as either input grows, and every species always shows at least 3 leaves.
    public static func leafInstances(species: Int, growth g: Double) -> Int {
        guard species > 0 else { return 0 }
        let bySpecies = species <= 10 ? 24 * species : max(240, 3 * species)
        let capacity = Int((24 + 456 * min(1, max(0, g))).rounded())
        return min(maxLeafInstances, max(3 * species, min(bySpecies, capacity)))
    }
}

/// The name of the tree's stage, from the number of species collected.
public enum TreeStage: String, Sendable, CaseIterable {
    case seed, seedling, sapling, youngMaple, spreadingMaple, oldMaple, grandMaple

    /// `seed` is only seen during onboarding, before the first leaf.
    public init(speciesCount: Int, total: Int = 155) {
        switch speciesCount {
        case ..<1: self = .seed
        case 1...4: self = .seedling
        case 5...19: self = .sapling
        case 20...49: self = .youngMaple
        case 50...99: self = .spreadingMaple
        case _ where speciesCount < total: self = .oldMaple
        default: self = .grandMaple
        }
    }

    public var displayName: String {
        switch self {
        case .seed: "Seed"
        case .seedling: "Seedling"
        case .sapling: "Sapling"
        case .youngMaple: "Young maple"
        case .spreadingMaple: "Spreading maple"
        case .oldMaple: "Old maple"
        case .grandMaple: "Grand maple"
        }
    }
}
