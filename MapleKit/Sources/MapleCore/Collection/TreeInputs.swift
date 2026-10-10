import Foundation

/// The member's data as the maple scene needs it (spec §4). Map it onto `TreeSceneModel` together with the phase
/// from `NowState`; see docs/core-api.md.
public struct TreeInputs: Sendable, Equatable {
    /// A placed (earned and opened) species, with the colourway it was pressed in.
    public struct Leaf: Sendable, Hashable {
        public var speciesID: String
        public var pressed: LeafColourway

        public init(speciesID: String, pressed: LeafColourway) {
            self.speciesID = speciesID
            self.pressed = pressed
        }
    }

    /// One of the next leaves, as a neutral bud that swells with progress (0…1).
    public struct Bud: Sendable, Hashable {
        public var speciesID: String
        public var progress: Double

        public init(speciesID: String, progress: Double) {
            self.speciesID = speciesID
            self.progress = progress
        }
    }

    /// A leaf opened in the last 24 hours, which carries the amber halo.
    public struct Halo: Sendable, Hashable {
        public var speciesID: String
        public var placedAt: Date

        public init(speciesID: String, placedAt: Date) {
            self.speciesID = speciesID
            self.placedAt = placedAt
        }
    }

    /// How long a new leaf's halo lasts.
    public static let haloLifetime: TimeInterval = 24 * 3600

    public var seed: UInt64
    public var tendedDays: Int
    /// Structural growth g = `TreeGrowth.structure(tendedDays:)`.
    public var growth: Double
    /// From the number of placed species.
    public var stage: TreeStage
    /// Placed species in unlock order.
    public var species: [Leaf]
    /// The next leaves (up to 3), Home's next leaf first.
    public var buds: [Bud]
    /// Leaves that can be opened now, oldest first; the first is the tappable amber bud. Empty in wind-down and
    /// at night, when nothing is revealed.
    public var waiting: [String]
    /// The member's featured leaf, or the newest one.
    public var featured: String?
    public var season: Season
    public var seasonDay: Int
    /// 0.4…1 from the last seven nights.
    public var vitality: Double
    public var newLeafHalos: [Halo]

    public init(
        seed: UInt64, tendedDays: Int, growth: Double, stage: TreeStage, species: [Leaf], buds: [Bud], waiting: [String],
        featured: String?, season: Season, seasonDay: Int, vitality: Double, newLeafHalos: [Halo]
    ) {
        self.seed = seed
        self.tendedDays = tendedDays
        self.growth = growth
        self.stage = stage
        self.species = species
        self.buds = buds
        self.waiting = waiting
        self.featured = featured
        self.season = season
        self.seasonDay = seasonDay
        self.vitality = vitality
        self.newLeafHalos = newLeafHalos
    }
}

/// The Profile sheet's numbers (spec §8.3). A total is nil until its category exists for this member, and is then
/// shown even at 0.
public struct ProfileTotals: Sendable, Equatable {
    public var leaves: Int
    public var tendedDays: Int
    public var stage: TreeStage
    public var nightsOnTime: Int?
    public var focusHours: Double?
    public var windDowns: Int?
    public var mornings: Int?

    public init(leaves: Int, tendedDays: Int, stage: TreeStage, nightsOnTime: Int?, focusHours: Double?, windDowns: Int?, mornings: Int?) {
        self.leaves = leaves
        self.tendedDays = tendedDays
        self.stage = stage
        self.nightsOnTime = nightsOnTime
        self.focusHours = focusHours
        self.windDowns = windDowns
        self.mornings = mornings
    }
}
