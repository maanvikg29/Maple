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

    /// How long one fall of leaf `index` lasts: 12 to 18 seconds, different for each leaf so they never fall in step.
    /// Slow, so they drift rather than rain (the owner, 28 Nov 2026: "slow down the leafs falling").
    public static func seconds(ofLeaf index: Int) -> Double {
        12 + unit(index, 0, 1) * 6
    }

    /// The leaves in the air at `seconds` (any clock that only runs forward).
    public static func leaves(at seconds: Double, count: Int = defaultCount) -> [Leaf] {
        guard count > 0 else { return [] }
        let time = clock(seconds)
        let blown = drift(at: time)
        return (0 ..< count).map { index in
            let duration = Self.seconds(ofLeaf: index)
            let whole = (time + unit(index, 0, 2) * duration) / duration
            let cycle = Int(whole.rounded(.down))
            let progress = whole - Double(cycle)
            // Each fall is a new leaf: another place, another swing, another colour.
            let start = 0.08 + unit(index, cycle, 3) * 0.84
            let sway = 0.04 + unit(index, cycle, 4) * 0.035
            // Two to three and a half swings on the way down: a swing every five or six seconds.
            let waves = 2 + unit(index, cycle, 5) * 1.5
            let phase = unit(index, cycle, 6) * 2 * .pi
            let angle = 2 * .pi * waves * progress + phase
            // Carried by any gust since it left the canopy, a little more the further it has come.
            let wind = 0.045 * (blown - drift(at: time - progress * duration))
            let x = start + sway * sin(angle) + wind
            // Slow at each end of its swing and quick through the middle, as a leaf falls: its speed down the
            // screen goes with the square of its speed across it.
            let lilt = 0.6 * (sin(2 * angle) - sin(2 * phase)) / (4 * .pi * waves) * min(1, progress / 0.15)
            let spin = (unit(index, cycle, 7) - 0.5) * 3
            return Leaf(
                x: min(1, max(0, x)), fall: min(1, max(0, pow(progress, 1.25) + lilt)),
                // It tips toward the way it is swinging.
                turn: phase + spin * progress + 0.6 * cos(angle),
                size: 0.7 + unit(index, cycle, 8) * 0.6, colour: min(2, Int(unit(index, cycle, 9) * 3)),
                opacity: min(1, max(0, min(progress / 0.08, (1 - progress) / 0.1)))
            )
        }
    }

    // MARK: Gusts

    /// A gust comes once in each stretch of this many seconds, somewhere in its middle, and blows for `gustSeconds`.
    private static let gustEvery = 17.0
    private static let gustSeconds = 3.5

    private static func gustStart(_ stretch: Int) -> Double {
        Double(stretch) * gustEvery + 4 + unit(stretch, 0, 20) * 8
    }

    /// How hard the wind blows at `seconds`, 0 (calm) to 1: now and then it builds, blows and dies away.
    public static func gust(at seconds: Double) -> Double {
        guard seconds.isFinite else { return 0 }
        let time = clock(seconds)
        let stretch = Int((time / gustEvery).rounded(.down))
        let s = time - gustStart(stretch)
        guard s > 0, s < gustSeconds else { return 0 }
        let rise = sin(.pi * s / gustSeconds)
        return rise * rise
    }

    /// All the wind there has been until `seconds` (the sum of every gust's strength over time): a leaf is carried by
    /// the difference between now and when it left the canopy, so a gust pushes it along and never pulls it back.
    public static func drift(at seconds: Double) -> Double {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        let time = clock(seconds)
        let stretch = Int((time / gustEvery).rounded(.down))
        // Each whole gust before this stretch's adds half its length.
        var total = Double(stretch) * gustSeconds / 2
        let s = min(gustSeconds, max(0, time - gustStart(stretch)))
        total += s / 2 - gustSeconds * sin(2 * .pi * s / gustSeconds) / (4 * .pi)
        return total
    }

    private static func clock(_ seconds: Double) -> Double {
        seconds.isFinite ? min(max(0, seconds), 1e9) : 0
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
