import Foundation

/// The words on the van's machines screen: what a leaf cooks into now, and for each machine its level, what it adds,
/// and what the next level costs (syrup van design §2, §7). Pure; the numbers come from the tuning.
public struct VanUpgradesModel: Sendable, Equatable {
    public struct Row: Sendable, Equatable, Identifiable {
        public let machine: WorkshopMachine
        public let name: String
        /// One line about what the machine is.
        public let about: String
        /// "Level 1 of 5", with "· the top" at the top.
        public let levelText: String
        /// What the machine adds now.
        public let nowText: String
        /// What the next level would add in all; nil at the top.
        public let nextText: String?
        /// Leaves for the next level; nil at the top.
        public let price: Int?
        public let canAfford: Bool
        public let isAtTop: Bool
        /// "Upgrade · 40 leaves" when the van can pay, "80 leaves · 35 to go" when it can't; nil at the top.
        public let buttonTitle: String?

        public var id: String { machine.rawValue }
    }

    /// "1 leaf cooks into 1.3 bottles of syrup".
    public let yieldText: String
    /// "45 leaves to spend".
    public let leavesText: String
    public let rows: [Row]

    /// - Parameters:
    ///   - leaves: `WorkshopStore.leaves`.
    ///   - levels: Each machine's level (`WorkshopStore.level(of:)`); a missing machine is at level 0.
    public init(leaves: Int, levels: [WorkshopMachine: Int], tuning: WorkshopTuning) {
        let leaves = max(0, leaves)
        yieldText = "1 leaf cooks into \(Self.bottles(tuning.tenthsPerLeaf(levels: levels))) of syrup"
        leavesText = switch leaves {
        case 0: "No leaves to spend"
        case 1: "1 leaf to spend"
        default: "\(leaves) leaves to spend"
        }
        rows = WorkshopMachine.allCases.compactMap { machine in
            guard let ladder = tuning.ladders[machine], ladder.topLevel > 0 else { return nil }
            let level = min(max(0, levels[machine] ?? 0), ladder.topLevel)
            let price = tuning.price(of: machine, after: level)
            let isAtTop = price == nil
            let button: String? = price.map { price in
                leaves >= price ? "Upgrade · \(Self.count(price))" : "\(Self.count(price)) · \(price - leaves) to go"
            }
            return Row(
                machine: machine, name: machine.name, about: machine.about,
                levelText: "Level \(level) of \(ladder.topLevel)" + (isAtTop ? " · the top" : ""),
                nowText: level == 0 ? "Not upgraded yet" : "Each leaf gives \(Self.decimal(ladder.bonusTenths[level - 1])) more syrup",
                nextText: isAtTop ? nil : "Next level: each leaf gives \(Self.decimal(ladder.bonusTenths[level])) more syrup",
                price: price, canAfford: price.map { leaves >= $0 } ?? false, isAtTop: isAtTop, buttonTitle: button
            )
        }
    }

    /// "1 bottle", "2 bottles", "1.3 bottles".
    static func bottles(_ tenths: Int) -> String {
        let tenths = max(0, tenths)
        if tenths == 10 { return "1 bottle" }
        return tenths % 10 == 0 ? "\(tenths / 10) bottles" : "\(decimal(tenths)) bottles"
    }

    /// Tenths as a number with one decimal: 5 is "0.5".
    static func decimal(_ tenths: Int) -> String {
        "\(max(0, tenths) / 10).\(max(0, tenths) % 10)"
    }

    private static func count(_ leaves: Int) -> String {
        leaves == 1 ? "1 leaf" : "\(leaves) leaves"
    }
}

extension WorkshopMachine {
    public var name: String {
        switch self {
        case .evaporator: "Evaporator"
        case .filterPress: "Filter press"
        }
    }

    /// One line about what the machine does.
    public var about: String {
        switch self {
        case .evaporator: "The pan the sap boils in"
        case .filterPress: "Strains the finished syrup"
        }
    }
}
