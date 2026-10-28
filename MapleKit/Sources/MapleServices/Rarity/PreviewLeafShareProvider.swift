#if DEBUG
import Foundation
import MapleCore

/// DEBUG only: plausible rarity for previews and `-MapleDemoRarity YES`. Shares follow the design tier (the sugar
/// maple about 93%, first-steps rungs 55–85%, common 18–50%, uncommon 4–16%, rare 0.8–3.5%, legendary 0.05–0.6%),
/// jittered per species but identical on every run, over 12,480 members.
nonisolated public struct PreviewLeafShareProvider: LeafShareProvider {
    public static let members = 12_480

    public init() {}

    public var identifier: String { "preview" }

    public func fetchCounts() async throws -> LeafShareCounts {
        Self.counts
    }

    public static var counts: LeafShareCounts {
        var counts: [String: Int] = [:]
        for rung in RewardCatalog.shared.assignments {
            var rng = SplitMix64(seed: SplitMix64.derive(0x5EED_0F_1EAF, rung.speciesID))
            let range: ClosedRange<Double> = switch rung.tier {
            case .firstSteps where rung.categoryID == .firstLeaf: 0.92...0.94
            case .firstSteps: 0.55...0.85
            case .common: 0.18...0.50
            case .uncommon: 0.04...0.16
            case .rare: 0.008...0.035
            case .legendary: 0.0005...0.006
            }
            let share = rng.range(range.lowerBound, range.upperBound)
            counts[rung.speciesID] = Int((share * Double(members)).rounded())
        }
        let calendar = Calendar(identifier: .iso8601)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start
        return LeafShareCounts(members: members, counts: counts, weekStart: weekStart.flatMap { calendar.date(byAdding: .day, value: -7, to: $0) })
    }
}
#endif
