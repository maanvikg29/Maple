import Foundation

/// The van's saved state (`workshop.json`, syrup van design §2): what the member has earned, cooked and spent, and each
/// machine's level. Pure.
///
/// No balance is stored. Leaves in the van are `earned - cooked - spentOnUpgrades`. `earned` grows by however much the
/// session ledger's total (`LeafEarnings.total`) has grown since the van last looked (`ledgerSeen`), so a leaf can't be
/// counted twice or lost to a missed delivery, and a short read of the ledger can't take leaves away.
///
/// The ledger's total depends on the pace and the earning rules it is counted with. The van remembers both, and when
/// either changes it starts a new count from the ledger as it now reads: leaves already earned stay, the same sessions
/// are never paid twice, and the next session earns as usual.
public struct WorkshopBank: Sendable, Codable {
    /// No count is ever above this, so a damaged file can't overflow the sums.
    public static let limit = 1_000_000_000

    /// Leaves ever earned. It only goes up.
    public private(set) var earned = 0
    /// The ledger's total when the van last looked, counted at `ledgerPace` and `ledgerRules`.
    public private(set) var ledgerSeen = 0
    /// Seconds per leaf `ledgerSeen` was counted at; nil until the first leaves arrive.
    public private(set) var ledgerPace: Int?
    /// The earning rules (`LeafEarnings.rulesVersion`) `ledgerSeen` was counted under; nil until the first leaves arrive.
    public private(set) var ledgerRules: Int?
    /// Leaves cooked into syrup.
    public private(set) var cooked = 0
    /// Leaves spent on upgrades.
    public private(set) var spentOnUpgrades = 0
    /// Syrup ever made, in tenths of a bottle.
    public private(set) var syrupMadeTenths = 0
    /// Each machine's level, by its raw name. A machine this build doesn't know is kept as it is.
    public private(set) var levels: [String: Int] = [:]
    /// Decoding met a number it had to repair. Not saved, and not part of equality.
    public private(set) var decodedWithLosses = false

    public init() {}

    /// Leaves in the van now, waiting to be cooked or spent.
    public var leaves: Int { max(0, earned - cooked - spentOnUpgrades) }
    /// Syrup in the van now, in tenths of a bottle.
    public var syrupTenths: Int { syrupMadeTenths }

    /// A machine's level, never above the top of its ladder in `tuning`.
    public func level(of machine: WorkshopMachine, tuning: WorkshopTuning = .starting) -> Int {
        min(max(0, levels[machine.rawValue] ?? 0), tuning.topLevel(of: machine))
    }

    /// Leaves for the machine's next level; nil at the top.
    public func price(of machine: WorkshopMachine, tuning: WorkshopTuning = .starting) -> Int? {
        tuning.price(of: machine, after: level(of: machine, tuning: tuning))
    }

    /// Tenths of a bottle a leaf cooks into now.
    public func tenthsPerLeaf(tuning: WorkshopTuning = .starting) -> Int {
        var current: [WorkshopMachine: Int] = [:]
        for machine in WorkshopMachine.allCases { current[machine] = level(of: machine, tuning: tuning) }
        return tuning.tenthsPerLeaf(levels: current)
    }

    /// Tells the van the ledger's total (`LeafEarnings.total`), counted with `tuning`'s pace under `rules`. A total at
    /// or below the one the van last saw changes nothing. A total counted at another pace or under other rules can't be
    /// compared with the last one, so the van starts counting again from it and adds nothing this time.
    /// - Returns: The leaves newly in the van.
    @discardableResult
    public mutating func noteEarned(
        _ total: Int, tuning: WorkshopTuning = .starting, rules: Int = LeafEarnings.rulesVersion
    ) -> Int {
        let total = min(max(0, total), Self.limit)
        let pace = tuning.secondsPerLeaf
        guard (ledgerPace ?? pace) == pace, (ledgerRules ?? rules) == rules else {
            ledgerSeen = total
            ledgerPace = pace
            ledgerRules = rules
            return 0
        }
        guard total > ledgerSeen else { return 0 }
        let new = min(total - ledgerSeen, max(0, Self.limit - earned))
        ledgerSeen = total
        ledgerPace = pace
        ledgerRules = rules
        earned += new
        return new
    }

    /// Cooks up to `count` leaves into syrup at today's yield.
    /// - Returns: The leaves cooked: fewer than `count` when the van holds fewer.
    @discardableResult
    public mutating func cook(_ count: Int, tuning: WorkshopTuning = .starting) -> Int {
        let cooking = min(max(0, count), leaves)
        guard cooking > 0 else { return 0 }
        cooked += cooking
        syrupMadeTenths += cooking * tenthsPerLeaf(tuning: tuning)
        return cooking
    }

    public enum UpgradeOutcome: Sendable, Equatable {
        case upgraded(level: Int)
        /// The van holds this many leaves too few. Nothing changed.
        case short(by: Int)
        case atTop
    }

    /// Spends leaves on the machine's next level.
    @discardableResult
    public mutating func upgrade(_ machine: WorkshopMachine, tuning: WorkshopTuning = .starting) -> UpgradeOutcome {
        let current = self.level(of: machine, tuning: tuning)
        guard let price = tuning.price(of: machine, after: current) else { return .atTop }
        guard leaves >= price else { return .short(by: price - leaves) }
        spentOnUpgrades += price
        levels[machine.rawValue] = current + 1
        return .upgraded(level: current + 1)
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case earned, cooked, spentOnUpgrades, syrupMadeTenths, levels, ledgerSeen, ledgerPace, ledgerRules
    }

    /// Reads what it can. A missing number is 0; a number that is unreadable, negative or above `limit` is repaired and
    /// `decodedWithLosses` is set, so the store copies the file aside before saving over it.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var losses = false
        func amount(_ key: CodingKeys) -> Int {
            guard c.contains(key) else { return 0 }
            guard let value = try? c.decode(Int.self, forKey: key) else {
                losses = true
                return 0
            }
            if value < 0 || value > Self.limit { losses = true }
            return min(max(0, value), Self.limit)
        }
        cooked = amount(.cooked)
        spentOnUpgrades = amount(.spentOnUpgrades)
        syrupMadeTenths = amount(.syrupMadeTenths)
        let saved = amount(.earned)
        earned = max(saved, cooked + spentOnUpgrades)
        if earned != saved { losses = true }
        // A van saved before the count was kept apart had seen the ledger at exactly what it had earned.
        ledgerSeen = c.contains(.ledgerSeen) ? amount(.ledgerSeen) : earned
        func measure(_ key: CodingKeys) -> Int? {
            guard c.contains(key) else { return nil }
            guard let value = try? c.decode(Int.self, forKey: key) else {
                losses = true
                return nil
            }
            return value
        }
        ledgerPace = measure(.ledgerPace)
        ledgerRules = measure(.ledgerRules)
        if c.contains(.levels) {
            if let saved = try? c.decode([String: Int].self, forKey: .levels) {
                if saved.values.contains(where: { $0 < 0 }) { losses = true }
                levels = saved.mapValues { max(0, $0) }
            } else {
                losses = true
            }
        }
        decodedWithLosses = losses
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(earned, forKey: .earned)
        try c.encode(cooked, forKey: .cooked)
        try c.encode(spentOnUpgrades, forKey: .spentOnUpgrades)
        try c.encode(syrupMadeTenths, forKey: .syrupMadeTenths)
        try c.encode(levels, forKey: .levels)
        try c.encode(ledgerSeen, forKey: .ledgerSeen)
        try c.encodeIfPresent(ledgerPace, forKey: .ledgerPace)
        try c.encodeIfPresent(ledgerRules, forKey: .ledgerRules)
    }
}

extension WorkshopBank: Equatable {
    public static func == (a: WorkshopBank, b: WorkshopBank) -> Bool {
        a.earned == b.earned && a.cooked == b.cooked && a.spentOnUpgrades == b.spentOnUpgrades
            && a.syrupMadeTenths == b.syrupMadeTenths && a.levels == b.levels && a.ledgerSeen == b.ledgerSeen
            && a.ledgerPace == b.ledgerPace && a.ledgerRules == b.ledgerRules
    }
}
