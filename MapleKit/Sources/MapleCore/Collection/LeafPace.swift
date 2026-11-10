import Foundation

/// Every category's counter at the end of one local day.
public struct DailyCounters: Sendable, Hashable, Codable {
    public var day: LocalDay
    public var counters: [RewardCategoryID: Double]

    public init(day: LocalDay, counters: [RewardCategoryID: Double]) {
        self.day = day
        self.counters = counters
    }

    private enum CodingKeys: String, CodingKey {
        case day, counters
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        day = try container.decode(LocalDay.self, forKey: .day)
        counters = try CategoryCounterCoding.decode(container, forKey: .counters)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(day, forKey: .day)
        try CategoryCounterCoding.encode(counters, to: &container, forKey: .counters)
    }
}

/// Counters are stored as a JSON object keyed by category id. Ids this build doesn't know (from a newer build)
/// are skipped rather than failing the whole file.
enum CategoryCounterCoding {
    /// Keys from the 2026-10-10 table that carry over to the focus table (focus spec §4.1). Other old keys are
    /// dropped; earned leaves are unlocks keyed by species, so none is ever lost.
    static let renamed: [String: RewardCategoryID] = ["on_time_bedtimes": .restedNights, "first_steps": .firstLeaf]

    static func decode<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>, forKey key: Key) throws -> [RewardCategoryID: Double] {
        let raw = try container.decodeIfPresent([String: Double].self, forKey: key) ?? [:]
        var counters: [RewardCategoryID: Double] = [:]
        for (id, value) in raw {
            guard let category = renamed[id] ?? RewardCategoryID(rawValue: id) else { continue }
            counters[category] = max(counters[category] ?? 0, value)
        }
        return counters
    }

    static func encode<Key: CodingKey>(
        _ counters: [RewardCategoryID: Double], to container: inout KeyedEncodingContainer<Key>, forKey key: Key
    ) throws {
        try container.encode(Dictionary(uniqueKeysWithValues: counters.map { ($0.key.rawValue, $0.value) }), forKey: key)
    }
}

/// How fast the member is moving toward a leaf (spec §3.5).
public enum LeafPace {
    /// Days the rate looks back over.
    public static let window = 14

    /// Units gained over the last 14 days, divided by 14. The baseline is the counter at the end of the day 14 days
    /// ago (0 when the member is newer than that).
    public static func rate(
        for category: RewardCategoryID, current: Double, history: [DailyCounters], today: LocalDay, calendar: Calendar
    ) -> Double {
        let start = today.adding(days: -window, calendar: calendar)
        let baseline = history.last { $0.day <= start }?.counters[category] ?? 0
        return max(0, current - baseline) / Double(window)
    }

    /// `remaining / rate`, or the category's design pace when the rate is zero.
    public static func estimatedDays(remaining: Double, rate: Double, category: RewardCategoryID) -> Double {
        guard remaining > 0 else { return 0 }
        let pace = rate > 0 ? rate : RewardCategoryInfo(category).designPace
        return remaining / pace
    }
}
