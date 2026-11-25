import Foundation
@testable import MapleCore

enum WorkshopFixtures {
    /// A small tuning for the rule tests, so retuning the app's own numbers never changes them.
    /// Evaporator: level 1 for 5 leaves (+0.2 bottles a leaf), level 2 for 8 (+0.5). Filter press: level 1 for 3 (+0.1).
    static let small = WorkshopTuning(
        secondsPerLeaf: 300, baseTenthsPerLeaf: 10,
        ladders: [
            .evaporator: WorkshopTuning.Ladder(prices: [5, 8], bonusTenths: [2, 5]),
            .filterPress: WorkshopTuning.Ladder(prices: [3], bonusTenths: [1]),
        ]
    )
}
