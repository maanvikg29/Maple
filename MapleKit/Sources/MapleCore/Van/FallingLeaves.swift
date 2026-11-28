import Foundation

/// The leaves that fall from the maple while a session runs (syrup van design §6.5). Pure.
///
/// They are an animation and nothing more: how many fall, and where, is made up from the clock and never from the
/// leaves a session earns. The same moment always gives the same leaves, so a redraw never makes them jump.
public enum FallingLeaves {
    public static let defaultCount = 9

    public struct Leaf: Sendable, Equatable {
        /// Across the picture, 0 at the left edge to 1 at the right.
        public let x: Double
        /// Down its fall: 0 as it leaves the canopy, 1 as it lands.
        public let fall: Double
        /// Its turn, in radians.
        public let turn: Double
        /// How big it is beside an ordinary leaf (1).
        public let size: Double
        /// Which of the three leaf colours: 0, 1 or 2.
        public let colour: Int
        /// It fades in as it leaves the canopy and out as it lands.
        public let opacity: Double
    }

    /// How long one fall of leaf `index` lasts: 7 to 12 seconds, different for each leaf so they never fall in step.
    public static func seconds(ofLeaf index: Int) -> Double {
        7 + unit(index, 0, 1) * 5
    }

    /// The leaves in the air at `seconds` (any clock that only runs forward).
    public static func leaves(at seconds: Double, count: Int = defaultCount) -> [Leaf] {
        guard count > 0 else { return [] }
        let time = seconds.isFinite ? min(max(0, seconds), 1e9) : 0
        return (0 ..< count).map { index in
            let duration = Self.seconds(ofLeaf: index)
            let whole = (time + unit(index, 0, 2) * duration) / duration
            let cycle = Int(whole.rounded(.down))
            let progress = whole - Double(cycle)
            // Each fall is a new leaf: another place, another sway, another colour.
            let start = 0.08 + unit(index, cycle, 3) * 0.84
            let sway = 0.02 + unit(index, cycle, 4) * 0.04
            let waves = 1.5 + unit(index, cycle, 5) * 1.5
            let phase = unit(index, cycle, 6) * 2 * .pi
            let x = start + sway * sin(2 * .pi * waves * progress + phase)
            let spin = (unit(index, cycle, 7) - 0.5) * 6
            return Leaf(
                x: min(1, max(0, x)), fall: min(1, max(0, pow(progress, 1.25))),
                turn: phase + spin * progress + 0.5 * sin(2 * .pi * waves * progress),
                size: 0.7 + unit(index, cycle, 8) * 0.6, colour: min(2, Int(unit(index, cycle, 9) * 3)),
                opacity: min(1, max(0, min(progress / 0.08, (1 - progress) / 0.1)))
            )
        }
    }

    /// A number from 0 up to (not including) 1 that depends only on its three inputs.
    static func unit(_ a: Int, _ b: Int, _ salt: Int) -> Double {
        var z = UInt64(bitPattern: Int64(a)) &* 0x9E37_79B9_7F4A_7C15
        z ^= UInt64(bitPattern: Int64(b)) &* 0xBF58_476D_1CE4_E5B9
        z ^= UInt64(bitPattern: Int64(salt)) &* 0x94D0_49BB_1331_11EB
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}
