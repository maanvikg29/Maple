import Foundation

/// Whether the member has agreed to count their leaves in the rarity stats (D5: opt-in, asked once).
public enum RarityConsent: String, Codable, Sendable {
    /// Never asked. The consent sheet follows the first morning reveal.
    case notAsked
    case included
    case declined
}

/// One night's outcome for the tree's vitality (spec §4.8). A nil field means that data isn't available
/// (for example no Screen Time), and its weight goes to the others.
public struct NightRecord: Codable, Sendable, Hashable {
    /// The local day the night began on.
    public var day: LocalDay
    public var onTime: Bool?
    public var fullNight: Bool?
    public var scrollFree: Bool?

    public init(day: LocalDay, onTime: Bool?, fullNight: Bool?, scrollFree: Bool?) {
        self.day = day
        self.onTime = onTime
        self.fullNight = fullNight
        self.scrollFree = scrollFree
    }
}

/// Everything Maple remembers about the member's collection, saved as one JSON file.
/// The domain rules that change it live in `CollectionSnapshot+Rules.swift`; `CollectionStore` persists it.
public struct CollectionSnapshot: Sendable, Equatable, Codable {
    public static let currentVersion = 1

    public var version: Int
    /// Created on first launch; seeds the tree, so the member's silhouette is personal and stable (spec §4.2).
    public var profileID: UUID
    public var createdAt: Date
    /// Earned leaves in unlock order, opened or not.
    public var unlocks: [LeafUnlock]
    /// When each opened leaf was opened (placed on the tree); drives the 24-hour new-leaf halo.
    public var revealedAt: [String: Date]
    /// Each category's counter: monotonic, never lowered.
    public var counters: [RewardCategoryID: Double]
    /// Closing counters per local day, for the 14-day pace. About a month is kept.
    public var history: [DailyCounters]
    /// Days on which a counter other than First steps or Community challenges rose (spec §4.1), ascending.
    public var tendedDays: [LocalDay]
    /// The last 14 nights, oldest first, for vitality.
    public var recentNights: [NightRecord]
    /// Pinned from leaf detail as the next leaf.
    public var pinnedSpeciesID: String?
    /// Chosen in leaf detail; nil means "the newest earned leaf".
    public var featuredSpeciesID: String?
    public var rarityConsent: RarityConsent
    /// Reveals ever opened; the first 3 get the full ritual (D8).
    public var revealsOpened: Int
    /// Apple Health's nights, pending and settled: the source of the sleep categories (spec §5.1, D9).
    public var nights: NightLedger

    public init(
        profileID: UUID, createdAt: Date, unlocks: [LeafUnlock] = [], revealedAt: [String: Date] = [:],
        counters: [RewardCategoryID: Double] = [:], history: [DailyCounters] = [], tendedDays: [LocalDay] = [],
        recentNights: [NightRecord] = [], pinnedSpeciesID: String? = nil, featuredSpeciesID: String? = nil,
        rarityConsent: RarityConsent = .notAsked, revealsOpened: Int = 0,
        nights: NightLedger = NightLedger()
    ) {
        self.version = Self.currentVersion
        self.profileID = profileID
        self.createdAt = createdAt
        self.unlocks = unlocks
        self.revealedAt = revealedAt
        self.counters = counters
        self.history = history
        self.tendedDays = tendedDays
        self.recentNights = recentNights
        self.pinnedSpeciesID = pinnedSpeciesID
        self.featuredSpeciesID = featuredSpeciesID
        self.rarityConsent = rarityConsent
        self.revealsOpened = revealsOpened
        self.nights = nights
    }

    /// A first-run collection: nothing earned yet.
    public static func empty(profileID: UUID, createdAt: Date) -> CollectionSnapshot {
        CollectionSnapshot(profileID: profileID, createdAt: createdAt)
    }

    /// The tree's seed (`SplitMix64.seed(for:)` of the profile id).
    public var treeSeed: UInt64 {
        SplitMix64.seed(for: profileID)
    }

    // MARK: Codable (tolerant: missing fields take their defaults)

    private enum CodingKeys: String, CodingKey {
        case version, profileID, createdAt, unlocks, revealedAt, counters, history, tendedDays, recentNights
        case pinnedSpeciesID, featuredSpeciesID, rarityConsent, revealsOpened, nights
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        profileID = try c.decode(UUID.self, forKey: .profileID)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        unlocks = try c.decodeIfPresent([LeafUnlock].self, forKey: .unlocks) ?? []
        revealedAt = try c.decodeIfPresent([String: Date].self, forKey: .revealedAt) ?? [:]
        counters = try CategoryCounterCoding.decode(c, forKey: .counters)
        history = try c.decodeIfPresent([DailyCounters].self, forKey: .history) ?? []
        tendedDays = try c.decodeIfPresent([LocalDay].self, forKey: .tendedDays) ?? []
        recentNights = try c.decodeIfPresent([NightRecord].self, forKey: .recentNights) ?? []
        pinnedSpeciesID = try c.decodeIfPresent(String.self, forKey: .pinnedSpeciesID)
        featuredSpeciesID = try c.decodeIfPresent(String.self, forKey: .featuredSpeciesID)
        rarityConsent = try c.decodeIfPresent(RarityConsent.self, forKey: .rarityConsent) ?? .notAsked
        revealsOpened = try c.decodeIfPresent(Int.self, forKey: .revealsOpened) ?? 0
        nights = try c.decodeIfPresent(NightLedger.self, forKey: .nights) ?? NightLedger()
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(profileID, forKey: .profileID)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(unlocks, forKey: .unlocks)
        try c.encode(revealedAt, forKey: .revealedAt)
        try CategoryCounterCoding.encode(counters, to: &c, forKey: .counters)
        try c.encode(history, forKey: .history)
        try c.encode(tendedDays, forKey: .tendedDays)
        try c.encode(recentNights, forKey: .recentNights)
        try c.encodeIfPresent(pinnedSpeciesID, forKey: .pinnedSpeciesID)
        try c.encodeIfPresent(featuredSpeciesID, forKey: .featuredSpeciesID)
        try c.encode(rarityConsent, forKey: .rarityConsent)
        try c.encode(revealsOpened, forKey: .revealsOpened)
        try c.encode(nights, forKey: .nights)
    }
}
