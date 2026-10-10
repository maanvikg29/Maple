import Foundation

/// A bud the layout should hang on the tree: one of the next leaves (spec §3.5, §4.5).
public struct TreeBudRequest: Sendable, Hashable {
    public var speciesID: String
    /// Progress toward the leaf, 0…1. The bud swells from 0.4 to 1.0 of its size with it.
    public var progress: Double

    public init(speciesID: String, progress: Double) {
        self.speciesID = speciesID
        self.progress = progress
    }
}

/// Everything needed to draw the tree at one moment of its growth, in tree space (see `TreePoint`):
/// points at the reference 402 × 560 stage, origin at the trunk base, y up. Built by `TreeLayout.generate`.
public struct TreeSkeleton: Sendable, Equatable {
    /// One grown (or growing) stretch of wood, from its parent node to `node`.
    public struct Segment: Sendable, Equatable {
        /// The node this segment ends at. Node ids are stable for a seed at every growth, so they identify a
        /// segment across growths.
        public var node: Int
        /// The node it grows from (−1 for nothing: the trunk base has no segment).
        public var parentNode: Int
        /// 1 trunk, 2 leaders, 3 their limbs, and so on up to 8.
        public var depth: Int
        public var base: TreePoint
        public var tip: TreePoint
        public var baseWidth: Double
        public var tipWidth: Double
        /// 0 (not started) … 1 (full length).
        public var emergence: Double

        public var length: Double { base.distance(to: tip) }
    }

    /// One limb drawn as a single smooth, tapering stroke: its centreline points and widths, base → tip.
    public struct Branch: Sendable, Equatable {
        /// Stable chain id.
        public var id: Int
        public var depth: Int
        public var points: [TreePoint]
        public var widths: [Double]
    }

    /// A place leaves can hang (spec §4.5): a twig's end, or a node partway along a limb inside the crown. A tip
    /// exists once its segment is at least 50% grown.
    public struct Tip: Sendable, Equatable {
        /// Stable id (the slot: a twig's chain for a twig end), the same at every growth.
        public var id: Int
        public var position: TreePoint
        /// Unit direction the twig grows in.
        public var direction: TreePoint
        /// Normalised distance from the crown's centre: around 1 on the outer shell.
        public var shell: Double
    }

    public enum RosetteKind: Sendable, Equatable {
        /// The species' permanent slot.
        case primary
        /// Extra copies near the primary; may move when the species count changes.
        case satellite
        /// The featured leaf's extra rosette at the crown's top tip.
        case featured
    }

    /// A small fan of one species' leaves at a twig end.
    public struct Rosette: Sendable, Equatable {
        public var speciesID: String
        public var kind: RosetteKind
        /// The tip the rosette belongs to; nil for a lateral position along a twig.
        public var tipID: Int?
        /// Where the leaves' stalks meet.
        public var anchor: TreePoint
        /// The direction the fan opens toward (unit).
        public var direction: TreePoint
        /// 0 for the twig's end, 1… for species sharing the twig, 8–12 pt further back each.
        public var shareRank: Int
        /// Inside the crown rather than on its outer shell: drawn first and 15% darker (spec §4.5).
        public var isInner: Bool
        /// Indices into `leaves`.
        public var leaves: Range<Int>
    }

    /// One leaf instance.
    public struct Leaf: Sendable, Equatable {
        public var speciesID: String
        /// Where the leaf's stalk ends: at the twig, or a little out from it for small leaves, which stand on long
        /// stalks from the rosette's anchor so a rosette keeps its 18 pt spread.
        public var anchor: TreePoint
        /// Radians clockwise from straight up for the leaf's axis (stalk → tip), applied on top of the species'
        /// own resting tilt, which the leaf geometry already carries.
        public var rotation: Double
        /// The side of the leaf's fitted square, in points.
        public var size: Double
        public var rosette: Int
        public var isInner: Bool
    }

    /// A closed bud: one of the next leaves, or an earned leaf waiting to be opened.
    public struct Bud: Sendable, Equatable {
        public var speciesID: String
        /// Where the bud's base meets the twig.
        public var anchor: TreePoint
        public var direction: TreePoint
        public var progress: Double
        /// The Home screen's next leaf: the largest bud, with a season-tint halo.
        public var isNext: Bool
        /// Earned and waiting to be opened: amber, at the species' future primary tip.
        public var isWaiting: Bool
        public var tipID: Int?
    }

    public var seed: UInt64
    public var growth: Double
    public var segments: [Segment]
    public var branches: [Branch]
    public var tips: [Tip]
    public var rosettes: [Rosette]
    public var leaves: [Leaf]
    public var buds: [Bud]
    /// Each species' permanent slot (`Tip.id`), in unlock order. Never changes for a seed.
    public var primaryTips: [String: Int]
    /// Trunk width at the ground.
    public var trunkBaseWidth: Double
    /// Typical leaf size at this growth, before seeded variation.
    public var leafSize: Double
    /// Crown centroid, weighted by leaf instances (spec §4.4 bloom centre).
    public var crownCentroid: TreePoint
    /// Extent of the whole tree, leaves included.
    public var height: Double
    public var minX: Double
    public var maxX: Double

    public var width: Double { maxX - minX }
}
