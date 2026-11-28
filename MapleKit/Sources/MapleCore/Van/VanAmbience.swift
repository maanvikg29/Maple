import Foundation

/// Home's picture, alive: everything here moves pieces of the concept picture itself, or (the glows, the steam) adds
/// a little light in its colours. Positions are in the home picture's pixels (`VanCanvas.home`). Pure: the same
/// moment always gives the same frame, so a redraw never makes anything jump.
public enum VanAmbience {
    // MARK: Leaves falling from the maple

    public static let leafCount = 7
    /// Where they come from: the canopy's lower half, left of the van.
    public static let canopyLeft = 40.0
    public static let canopyRight = 1000.0
    public static let canopyTop = 330.0
    public static let canopyBottom = 720.0
    /// Where they land: the grass round the van.
    public static let groundTop = 1690.0
    public static let groundBottom = 2060.0

    public struct Leaf: Sendable, Equatable {
        public let x: Double
        public let y: Double
        public let turn: Double
        /// 1 is a leaf's own size in the picture.
        public let size: Double
        /// Which of the three leaf colours: 0, 1 or 2.
        public let colour: Int
        public let opacity: Double
    }

    /// The leaves in the air at `time` (any clock that only runs forward). They are an animation only: nothing about
    /// them comes from the member's leaves.
    public static func leaves(at time: Double) -> [Leaf] {
        FallingLeaves.leaves(at: clock(time) * 0.8, count: leafCount).enumerated().map { index, leaf in
            let lane = Double(index) / Double(leafCount)
            // Each leaf has its own place in the canopy and its own place on the grass; the wind carries it right.
            let startY = canopyTop + (canopyBottom - canopyTop) * fraction(index, 3)
            let endY = groundTop + (groundBottom - groundTop) * fraction(index, 5)
            let wind = 140 + 260 * fraction(index, 7)
            let x = canopyLeft + (canopyRight - canopyLeft) * (0.5 * leaf.x + 0.5 * lane) + wind * leaf.fall
            return Leaf(
                x: x, y: startY + (endY - startY) * leaf.fall, turn: leaf.turn, size: 0.55 + 0.35 * leaf.size / 1.3,
                colour: leaf.colour, opacity: leaf.opacity
            )
        }
    }

    // MARK: The leaves already in the sky

    /// The concept's leaves that hang in the open sky (not over the canopy), in the order of `skyLeafBoxes`.
    public static let skyLeafCount = 4

    public struct Drift: Sendable, Equatable {
        public let dx: Double
        public let dy: Double
        public let turn: Double
    }

    /// A slow, small loop about where the picture has it.
    public static func skyLeaf(_ index: Int, at time: Double) -> Drift {
        let t = clock(time)
        let i = Double(index)
        let period = 4.2 + 1.3 * i
        let phase = 1.7 * i
        let angle = 2 * .pi * t / period + phase
        return Drift(dx: 9 * sin(angle * 0.5 + i), dy: 11 * sin(angle), turn: 0.22 * sin(angle + 0.8))
    }

    // MARK: Smoke and steam

    public struct Sway: Sendable, Equatable {
        /// About the chimney's top, in radians.
        public let turn: Double
        /// 1 is as drawn; it only ever grows, so the picture's own smoke never shows from behind.
        public let scale: Double
    }

    /// The picture's smoke, leaning with the wind about the chimney's top.
    public static func smoke(at time: Double) -> Sway {
        let t = clock(time)
        return Sway(turn: 0.05 * sin(2 * .pi * t / 5.3) + 0.015 * sin(2 * .pi * t / 1.9), scale: 1.04 + 0.035 * sin(2 * .pi * t / 3.7))
    }

    public struct Puff: Sendable, Equatable {
        /// How far up its rise, 0 at its source to 1 where it has gone.
        public let rise: Double
        /// A little sideways, in pixels.
        public let drift: Double
        public let scale: Double
        public let opacity: Double
    }

    /// A puff part-way up: small and faint as it leaves, bigger and fading as it goes.
    public static func puff(rise: Double, drift: Double = 0) -> Puff {
        let u = min(1, max(0, rise))
        return Puff(rise: u, drift: drift, scale: 0.35 + 0.75 * u, opacity: min(1, u / 0.2) * (1 - pow(u, 1.6)))
    }

    public static let chimneyPuffCount = 3

    /// New smoke rising from the chimney, over the picture's own.
    public static func chimneyPuffs(at time: Double) -> [Puff] {
        let t = clock(time)
        return (0 ..< chimneyPuffCount).map { index in
            let u = frac(t / 4.5 + Double(index) / Double(chimneyPuffCount))
            return puff(rise: u, drift: 40 * u + 12 * sin(4 * u + Double(index)))
        }
    }

    public static let steamCount = 4

    /// New steam off the pot: puffs of the picture's own steam leave the pot, rise, swell and fade.
    public static func steam(at time: Double) -> [Puff] {
        let t = clock(time)
        return (0 ..< steamCount).map { index in
            let u = frac(t / 2.8 + Double(index) / Double(steamCount))
            let side = index.isMultiple(of: 2) ? 1.0 : -1.0
            return puff(rise: u, drift: side * (14 * u + 6 * sin(5 * u + Double(index))))
        }
    }

    /// The steam puffs the picture has painted over the pot (`STEAM_SEEDS` in the art script).
    public static let paintedSteamCount = 3

    /// How big one of the picture's own steam puffs is drawn now: it swells and settles, and only ever grows from how
    /// it is drawn, so the still puff under it never shows.
    public static func steamSwell(_ index: Int, at time: Double) -> Double {
        let t = clock(time)
        let i = Double(index)
        return 1.12 + 0.07 * sin(2 * .pi * t / (2.2 + 0.45 * i) + 2.3 * i) + 0.02 * sin(2 * .pi * t / 0.9 + i)
    }

    // MARK: Flags

    public struct Flap: Sendable, Equatable {
        /// About where the cloth meets the pole.
        public let turn: Double
        /// Along the cloth: it shortens a little as it ripples.
        public let stretch: Double
    }

    public static func flag(at time: Double) -> Flap {
        let t = clock(time)
        return Flap(
            turn: 0.06 * sin(2 * .pi * t / 2.1) + 0.025 * sin(2 * .pi * t / 0.7),
            stretch: 0.96 + 0.035 * sin(2 * .pi * t / 0.9 + 0.5)
        )
    }

    public static let buntingCount = 5

    /// Each pennant on the line, swinging about its top.
    public static func bunting(_ index: Int, at time: Double) -> Double {
        let t = clock(time)
        let i = Double(index)
        return 0.055 * sin(2 * .pi * t / (2.4 + 0.3 * i) + 1.3 * i) + 0.015 * sin(2 * .pi * t / 0.8 + i)
    }

    // MARK: Light

    /// A flame's brightness, 0 to 1: a few slow waves and a quicker one, so it never strobes.
    public static func flicker(at time: Double, seed: Int) -> Double {
        let t = clock(time)
        let s = Double(seed) * 1.37
        let wave = 0.45 * sin(2 * .pi * t / 1.7 + s) + 0.3 * sin(2 * .pi * t / 0.63 + 2 * s) + 0.25 * sin(2 * .pi * t / 0.41 + 3 * s)
        return min(1, max(0, 0.5 + 0.5 * wave))
    }

    public static let bulbCount = 5

    /// A string light's brightness: steady most of the time, swelling now and then.
    public static func bulb(_ index: Int, at time: Double) -> Double {
        let t = clock(time)
        let i = Double(index)
        let slow = 0.5 + 0.5 * sin(2 * .pi * t / (3.1 + 0.7 * i) + 2.1 * i)
        return 0.25 + 0.75 * pow(slow, 1.5)
    }

    // MARK: The cat

    /// The sleeping cat's breath: it grows a little from how it is drawn, and back.
    public static func catBreath(at time: Double) -> Double {
        let t = clock(time)
        return 1 + 0.012 * (1 + sin(2 * .pi * t / 3.8))
    }

    // MARK: Helpers

    private static func clock(_ time: Double) -> Double {
        time.isFinite ? min(max(0, time), 1e7) : 0
    }

    private static func frac(_ value: Double) -> Double {
        value - value.rounded(.down)
    }

    /// A fixed number from 0 to 1 for each leaf and purpose.
    private static func fraction(_ index: Int, _ salt: Int) -> Double {
        frac(sin(Double(index * 7919 + salt * 104_729) * 12.9898) * 43758.5453)
    }
}
