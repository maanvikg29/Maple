import Foundation

/// A machine in the van that leaves can upgrade (syrup van design §2, §7). Saved by its raw name.
public enum WorkshopMachine: String, Sendable, CaseIterable, Codable {
    /// The pan the sap boils in.
    case evaporator
    /// Strains the finished syrup.
    case filterPress
}

/// Every number in the van's economy, in one place (syrup van design §2). The pace is tuned in its own pass (§14), by
/// editing `starting` and nothing else. The rules take a tuning, so their tests bring their own.
public struct WorkshopTuning: Sendable, Equatable {
    /// One machine's upgrade steps. Level 0 is the machine as it comes.
    public struct Ladder: Sendable, Equatable {
        /// Leaves for each step: `prices[0]` buys level 1.
        public var prices: [Int]
        /// Extra syrup a leaf gives at each level, in tenths of a bottle: `bonusTenths[0]` is level 1's whole bonus.
        public var bonusTenths: [Int]

        public init(prices: [Int], bonusTenths: [Int]) {
            self.prices = prices
            self.bonusTenths = bonusTenths
        }

        public var topLevel: Int { min(prices.count, bonusTenths.count) }
    }

    /// Seconds of a session for one leaf.
    public var secondsPerLeaf: Int
    /// Syrup one leaf cooks into before any upgrade, in tenths of a bottle.
    public var baseTenthsPerLeaf: Int
    public var ladders: [WorkshopMachine: Ladder]

    public init(secondsPerLeaf: Int, baseTenthsPerLeaf: Int, ladders: [WorkshopMachine: Ladder]) {
        self.secondsPerLeaf = secondsPerLeaf
        self.baseTenthsPerLeaf = baseTenthsPerLeaf
        self.ladders = ladders
    }

    /// The app's numbers. A leaf every 5 minutes and one bottle a leaf are the design's (§2); the ladders are starting
    /// values for the tuning pass.
    public static let starting = WorkshopTuning(
        secondsPerLeaf: 300, baseTenthsPerLeaf: 10,
        ladders: [
            .evaporator: Ladder(prices: [10, 25, 50, 100, 200], bonusTenths: [2, 5, 10, 15, 20]),
            .filterPress: Ladder(prices: [20, 60, 150], bonusTenths: [1, 3, 5]),
        ]
    )

    public func topLevel(of machine: WorkshopMachine) -> Int {
        ladders[machine]?.topLevel ?? 0
    }

    /// Leaves for the level after `level`; nil at the top.
    public func price(of machine: WorkshopMachine, after level: Int) -> Int? {
        guard let ladder = ladders[machine] else { return nil }
        let level = max(0, level)
        return level < ladder.topLevel ? ladder.prices[level] : nil
    }

    /// Tenths of a bottle one leaf cooks into with the machines at `levels`. A level outside a ladder reads as its
    /// nearest end.
    public func tenthsPerLeaf(levels: [WorkshopMachine: Int]) -> Int {
        ladders.reduce(baseTenthsPerLeaf) { sum, entry in
            let level = min(max(0, levels[entry.key] ?? 0), entry.value.topLevel)
            return level > 0 ? sum + entry.value.bonusTenths[level - 1] : sum
        }
    }
}
