import Foundation
import MapleCore

/// Everything the maple scene shows. Value type: build one from the member's data and hand it to
/// `MapleTreeScene`. Changing anything re-lays out and re-renders the tree once; motion never re-lays it out.
nonisolated public struct TreeSceneModel: Sendable, Equatable {
    /// A placed leaf: an earned and opened species.
    public struct Leaf: Sendable, Hashable {
        public var speciesID: String
        /// The colourway it was pressed in (the season it was earned). The tree itself always shows the real
        /// season; this is kept for the Tree view and share surfaces.
        public var pressed: LeafColourway

        public init(speciesID: String, pressed: LeafColourway) {
            self.speciesID = speciesID
            self.pressed = pressed
        }
    }

    /// One of the next leaves, hanging as a neutral bud that swells with progress.
    public struct Bud: Sendable, Hashable {
        public var speciesID: String
        /// 0…1.
        public var progress: Double

        public init(speciesID: String, progress: Double) {
            self.speciesID = speciesID
            self.progress = progress
        }
    }

    /// The amber halo a newly placed leaf carries for 24 hours (spec §4.5).
    public struct NewLeafHalo: Sendable, Hashable {
        public var speciesID: String
        public var placedAt: Date

        public init(speciesID: String, placedAt: Date) {
            self.speciesID = speciesID
            self.placedAt = placedAt
        }
    }

    /// The profile seed (`SplitMix64.seed(for:)`): the silhouette is personal and stable.
    public var seed: UInt64
    /// Structural growth g (`TreeGrowth.structure(tendedDays:)`).
    public var growth: Double
    /// Placed species in unlock order.
    public var species: [Leaf]
    /// The next leaves (up to 3), the Home next leaf first.
    public var buds: [Bud]
    /// Earned leaves waiting to be opened, in order. The first one's bud is tappable.
    public var waiting: [String]
    /// The featured leaf; it gets an extra rosette at the crown's top.
    public var featured: String?
    public var season: Season
    /// Days into the season (`TreeFoliage.seasonDay(for:hemisphere:)`): drives the autumn turning,
    /// winter frost and spring flowers.
    public var seasonDay: Int
    public var phase: NowPhase
    /// 0.4…1 from the last seven nights (spec §4.8). Below 0.55 the tree is quiet.
    public var vitality: Double
    public var newLeafHalos: [NewLeafHalo]
    /// Freezes the scene at this instant: no timeline, every ambient effect evaluated at this time.
    /// For snapshots and previews. Nil runs the live, sleepy idle motion.
    public var time: Date?

    public init(
        seed: UInt64,
        growth: Double,
        species: [Leaf],
        buds: [Bud] = [],
        waiting: [String] = [],
        featured: String? = nil,
        season: Season,
        seasonDay: Int = 45,
        phase: NowPhase,
        vitality: Double = 1,
        newLeafHalos: [NewLeafHalo] = [],
        time: Date? = nil
    ) {
        self.seed = seed
        self.growth = growth
        self.species = species
        self.buds = buds
        self.waiting = waiting
        self.featured = featured
        self.season = season
        self.seasonDay = seasonDay
        self.phase = phase
        self.vitality = vitality
        self.newLeafHalos = newLeafHalos
        self.time = time
    }

    /// Quiet after a rough week (spec §4.8): no copy changes, VoiceOver adds "Resting."
    public var isQuiet: Bool { vitality < 0.55 }

    /// What the layout and the static layers depend on (not the clock, not the halos' age).
    var layoutKey: LayoutKey {
        LayoutKey(
            seed: seed, growth: growth, species: species.map(\.speciesID), buds: buds, waiting: waiting,
            featured: featured
        )
    }

    struct LayoutKey: Hashable, Sendable {
        var seed: UInt64
        var growth: Double
        var species: [String]
        var buds: [Bud]
        var waiting: [String]
        var featured: String?
    }
}
