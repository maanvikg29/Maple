import Foundation

/// Pip up in the maple while a session runs, collecting leaves in his wicker basket (the owner, 28 Nov 2026: "where is
/// the animation of pip collecting the leafs", "make the bucket from classic woven wicker"). Pure: the same moment
/// always gives the same frame.
///
/// Positions are in Pip's square in the tree (`PIP_BOX` in `Scripts/art/concept/session_scene.py`, 610 by 580).
public enum PipBasket {
    /// How many leaves the basket shows heaped in it when it is full (`HEAP` in the art script).
    public static let heapSlots = 8

    /// How many leaves are heaped in the basket `fraction` of the way through the session: one as it starts, all of
    /// them at its end. A picture of the time gone, never a count of the leaves earned (the timer never shows one).
    public static func heap(fraction: Double) -> Int {
        guard fraction.isFinite else { return 1 }
        let done = min(1, max(0, fraction))
        return 1 + Int((done * Double(heapSlots - 1)).rounded(.down))
    }

    /// The middle of the basket's mouth, where a caught leaf goes in.
    public static let mouth = (x: 494.0, y: 372.0)
    /// Where a leaf comes from: the canopy above and to his right.
    static let source = (x: 600.0, y: 20.0)
    /// One leaf caught every this many seconds.
    public static let period = 6.0

    public struct Leaf: Sendable, Equatable {
        public let x: Double
        public let y: Double
        public let turn: Double
        public let opacity: Double
        /// 0 as it leaves the canopy, 1 in the basket.
        public let progress: Double
    }

    public struct Catch: Sendable, Equatable {
        /// The leaf on its way down, if one is.
        public let leaf: Leaf?
        /// How far Pip leans toward it, in radians, about his feet.
        public let lean: Double
        /// How far the basket dips as the leaf lands, in his square's units.
        public let dip: Double

        /// Nothing on its way down, Pip upright, the basket still: Reduce Motion, or the screen dimmed.
        public static let still = Catch(leaf: nil, lean: 0, dip: 0)
    }

    /// The catch at `time` (seconds on any clock that only runs forward): a leaf comes swaying down from the canopy
    /// into the basket, Pip leans to meet it, and the basket dips as it lands. Then a pause, and the next.
    public static func catching(at time: Double) -> Catch {
        let t = time.isFinite ? min(max(0, time), 1e7) : 0
        let p = t / period - (t / period).rounded(.down)
        let falling = 0.5
        var leaf: Leaf?
        if p < falling {
            let q = p / falling
            let x = source.x + (mouth.x - source.x) * q + 34 * sin(2.5 * .pi * q) * (1 - q)
            let y = source.y + (mouth.y - source.y) * pow(q, 1.25)
            let opacity = min(1, q / 0.12) * min(1, (1 - q) / 0.12)
            leaf = Leaf(x: x, y: y, turn: 2.2 * q + 0.4 * sin(5 * q), opacity: opacity, progress: q)
        }
        let lean = 0.07 * smoothstep(0.28, 0.44, p) * (1 - smoothstep(0.56, 0.7, p))
        let dip = p >= 0.5 && p < 0.64 ? 7 * sin(.pi * (p - 0.5) / 0.14) : 0
        return Catch(leaf: leaf, lean: lean, dip: dip)
    }

    private static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = min(1, max(0, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }
}
