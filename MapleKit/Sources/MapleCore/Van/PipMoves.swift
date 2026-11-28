import Foundation

/// Where Pip is, measured from where he sits in the fork of the maple, in the tree picture's own units
/// (`VanCanvas.tree`). Pure.
public struct PipPose: Sendable, Equatable {
    /// Across and down from his seat.
    public let x: Double
    public let y: Double
    /// Turned over by this much, in radians.
    public let turn: Double
    /// 1 is his own height; less as he lands.
    public let squash: Double

    public static let seated = PipPose(x: 0, y: 0, turn: 0, squash: 1)
}

/// The pail, once it is out of Pip's paw: its middle, moved from where it hung, and its turn about its middle.
public struct PailPose: Sendable, Equatable {
    public let x: Double
    public let y: Double
    /// Clockwise, in radians: 0 is upright with its mouth up, π upside down, 3π/2 on its side with its mouth left.
    public let turn: Double

    public static let hanging = PailPose(x: 0, y: 0, turn: 0)
}

/// A session ended early: Pip slips out of the tree, turns over once and lands softly on the grass, and his pail flies
/// off, turns over and spills its leaves, which flutter down over the grass (syrup van design §6.6). He sways a moment,
/// dazed, and sits upright: it is a tumble, never a punishment.
///
/// Everything is measured from his seat in the fork, in the tree picture's units, as `PipPose` is.
public enum PipFall {
    /// Long enough for the last leaf to land.
    public static let seconds = 3.5
    /// Where he lands, from his seat.
    public static let landingX = 200.0
    public static let landingY = 930.0

    /// The pail's middle while it hangs from his paw, and its mouth from its middle, upright: `PAIL_MIDDLE` and
    /// `PAIL_MOUTH` in the art script, in Pip's square at `PIP_SCALE`.
    public static let pailX = 115.3
    public static let pailY = 113.5
    public static let mouthX = 0.0
    public static let mouthY = -48.2
    /// Where the pail comes to rest, from where it hung: on the grass to Pip's right, on its side, mouth toward him.
    public static let pailRestX = 390.0
    public static let pailRestY = 960.0
    public static let pailRestTurn = 1.5 * Double.pi

    /// The grass the leaves land on: its top and bottom, its left and right, from his seat.
    public static let groundTop = 1040.0
    public static let groundBottom = 1210.0
    public static let grassLeft = -315.0
    public static let grassRight = 640.0

    private static let slips = 0.25
    private static let letGo = 0.34
    private static let lands = 1.05
    private static let up = 1.35
    private static let settled = 2.4
    private static let pailLands = 1.2
    private static let pailSettles = 0.45

    public static func pose(at time: Double) -> PipPose {
        guard time.isFinite, time > 0 else { return .seated }
        if time < slips {
            // A wobble before he goes.
            return PipPose(x: 0, y: 0, turn: 0.15 * sin(.pi * time / slips), squash: 1)
        }
        if time < lands {
            let u = (time - slips) / (lands - slips)
            return PipPose(x: landingX * u, y: landingY * u * u, turn: 2 * .pi * u, squash: 1)
        }
        if time < up {
            let v = (time - lands) / (up - lands)
            return PipPose(x: landingX, y: landingY, turn: 0, squash: 1 - 0.25 * sin(.pi * v))
        }
        if time < settled {
            // Dazed: he sways side to side, less and less.
            let v = (time - up) / (settled - up)
            let sway = 0.14 * sin(2 * .pi * 2.2 * (time - up)) * (1 - v) * (1 - v)
            return PipPose(x: landingX, y: landingY, turn: sway, squash: 1)
        }
        return PipPose(x: landingX, y: landingY, turn: 0, squash: 1)
    }

    // MARK: The pail

    public static func pail(at time: Double) -> PailPose {
        guard time.isFinite, time > 0 else { return .hanging }
        if time < letGo { return carried(at: time) }
        if time < pailLands {
            // Flung up and out to the right as he slips, turning over as it goes (upside down halfway), and down onto
            // its side.
            let start = carried(at: letGo)
            let u = (time - letGo) / (pailLands - letGo)
            let toss = 420.0
            return PailPose(
                x: start.x + (pailRestX - start.x) * u,
                y: start.y + (pailRestY - start.y) * u - 4 * toss * u * (1 - u),
                turn: start.turn + (pailRestTurn - start.turn) * u
            )
        }
        // A little bounce and a rock, and it lies still.
        let w = min(1, (time - pailLands) / pailSettles)
        return PailPose(
            x: pailRestX, y: pailRestY - 34 * sin(.pi * w) * (1 - w), turn: pailRestTurn + 0.18 * sin(2 * .pi * 1.6 * w) * (1 - w)
        )
    }

    /// In his paw: it turns with him, about his middle.
    private static func carried(at time: Double) -> PailPose {
        let pip = pose(at: time)
        let c = cos(pip.turn)
        let s = sin(pip.turn)
        return PailPose(
            x: pailX * c - pailY * s + pip.x - pailX, y: pailX * s + pailY * c + pip.y - pailY, turn: pip.turn
        )
    }

    /// The middle of the pail's mouth, from his seat.
    public static func mouth(at time: Double) -> (x: Double, y: Double) {
        let pail = pail(at: time)
        let c = cos(pail.turn)
        let s = sin(pail.turn)
        return (pailX + pail.x + mouthX * c - mouthY * s, pailY + pail.y + mouthX * s + mouthY * c)
    }

    // MARK: The spilled leaves

    /// Leaves that pour out while the pail is upside down, and more that jump out as it lands.
    private static let pourCount = 16
    private static let jumpCount = 6
    public static let spillCount = pourCount + jumpCount

    /// One of the pail's leaves, from Pip's seat like his own pose.
    public struct Spilled: Sendable, Equatable {
        public let x: Double
        public let y: Double
        public let turn: Double
        /// Beside a leaf of the picture (1).
        public let size: Double
        /// Which of the three leaf colours.
        public let colour: Int
        public let opacity: Double
    }

    /// The pail's leaves at `time`: none until the pail tips, then each out of its mouth, fluttering down to its own
    /// place on the grass, where it stays.
    public static func spill(at time: Double) -> [Spilled] {
        let t = time.isFinite ? time : 0
        return (0 ..< spillCount).map { leaf($0, at: t) }
    }

    private static func leaf(_ index: Int, at time: Double) -> Spilled {
        let throwing = launch(index)
        let size = 0.65 + 0.4 * unit(index, 11)
        let colour = min(2, Int(unit(index, 12) * 3))
        let startTurn = (unit(index, 13) - 0.5) * 2 * .pi
        guard time >= throwing.time else {
            return Spilled(x: throwing.x, y: throwing.y, turn: startTurn, size: size, colour: colour, opacity: 0)
        }
        // Air holds a leaf back: it slows sideways, and falls no faster than its own steady speed.
        let drag = 2.6
        let glide = 2.4
        let steady = 380 + 140 * unit(index, 4)
        let swing = 36 + 24 * unit(index, 5)
        let beat = 6 + 3 * unit(index, 6)
        let phase = 2 * .pi * unit(index, 7)
        let spin = (unit(index, 8) - 0.5) * 3
        let ground = groundTop + (groundBottom - groundTop) * unit(index, 9)
        // How far it drifts sideways in all, kept so it lands on the grass.
        let reach = min(max(throwing.dx / glide, grassLeft + swing + 20 - throwing.x), grassRight - swing - 20 - throwing.x)
        func x(_ s: Double) -> Double {
            throwing.x + reach * (1 - exp(-glide * s)) + swing * sin(beat * s + phase) * (1 - exp(-3 * s))
        }
        func y(_ s: Double) -> Double {
            throwing.y + steady * s + (throwing.dy - steady) * (1 - exp(-drag * s)) / drag
        }
        func turn(_ s: Double) -> Double {
            startTurn + spin * (1 - exp(-2 * s)) + 0.55 * cos(beat * s + phase) * (1 - exp(-3 * s))
        }
        // When it lands: after the top of its rise, the moment it comes down to its ground.
        var low = throwing.dy < 0 ? log((steady - throwing.dy) / steady) / drag : 0
        var high = 12.0
        if y(low) >= ground { high = low } else {
            for _ in 0 ..< 40 {
                let middle = (low + high) / 2
                if y(middle) < ground { low = middle } else { high = middle }
            }
        }
        let s = min(time - throwing.time, high)
        return Spilled(x: x(s), y: min(y(s), ground), turn: turn(s), size: size, colour: colour, opacity: 1)
    }

    /// When and where a leaf leaves the pail, and how fast (from his seat, per second).
    private static func launch(_ index: Int) -> (time: Double, x: Double, y: Double, dx: Double, dy: Double) {
        if index < pourCount {
            // Poured: out of the mouth while it faces down, thrown along it and spread across it.
            let time = 0.58 + 0.37 * (Double(index) / Double(pourCount - 1)) * 0.8 + 0.37 * 0.2 * unit(index, 1)
            let mouth = mouth(at: time)
            let before = self.mouth(at: time - 1.0 / 240)
            let after = self.mouth(at: time + 1.0 / 240)
            let turn = pail(at: time).turn
            let along = 300 + 400 * unit(index, 2)
            let across = -600 + 1200 * unit(index, 3)
            let dx = 0.3 * (after.x - before.x) * 120 + sin(turn) * along + cos(turn) * across
            let dy = 0.3 * (after.y - before.y) * 120 - cos(turn) * along + sin(turn) * across
            return (time, mouth.x, mouth.y, dx, dy)
        }
        // Jumped: up out of the mouth as the pail hits the grass, mostly back toward Pip.
        let mouth = mouth(at: pailLands)
        let jump = index - pourCount
        return (pailLands + 0.02 * Double(jump), mouth.x, mouth.y, -620 + 900 * unit(index, 2), -600 + 260 * unit(index, 3))
    }

    // MARK: Dust

    /// A soft puff of dust, from his seat.
    public struct Dust: Sendable, Equatable {
        public let x: Double
        public let y: Double
        public let radius: Double
        public let opacity: Double
    }

    /// Dust rising where he lands, and a little where the pail lands.
    public static func dust(at time: Double) -> [Dust] {
        let t = time.isFinite ? time : 0
        let his = (0 ..< 6).map { index in
            puff(at: t, from: lands, lasting: 0.75, x: landingX - 110 + 44 * Double(index), y: landingY + 150, side: Double(index) - 2.5)
        }
        let pails = (0 ..< 4).map { index in
            puff(
                at: t, from: pailLands, lasting: 0.6, x: pailX + pailRestX - 70 + 46 * Double(index), y: pailY + pailRestY + 50,
                side: Double(index) - 1.5
            )
        }
        return his + pails
    }

    private static func puff(at time: Double, from start: Double, lasting: Double, x: Double, y: Double, side: Double) -> Dust {
        let u = (time - start) / lasting
        guard u > 0, u < 1 else { return Dust(x: x, y: y, radius: 14, opacity: 0) }
        return Dust(
            x: x + side * 24 * u, y: y - 40 * u, radius: 14 + 34 * u, opacity: 0.55 * (1 - u) * (1 - u) * min(1, u / 0.1)
        )
    }

    private static func unit(_ index: Int, _ salt: Int) -> Double {
        FallingLeaves.unit(index, 101, salt)
    }
}

/// A session ran to its end: Pip hops down with his pail and walks off across the grass toward the van (§6.7).
public enum PipWalk {
    public static let seconds = 3.0
    /// The grass, from his seat.
    public static let groundY = 930.0

    private static let hop = 0.7
    private static let hopX = 130.0
    private static let endX = 1000.0

    public static func pose(at time: Double) -> PipPose {
        guard time.isFinite, time > 0 else { return .seated }
        if time < hop {
            let u = time / hop
            return PipPose(x: hopX * u, y: groundY * u * u - 60 * sin(.pi * u) * (1 - u), turn: 0, squash: 1)
        }
        let w = min(1, (time - hop) / (seconds - hop))
        let step = w * .pi * 9
        return PipPose(x: hopX + (endX - hopX) * w, y: groundY - 16 * abs(sin(step)), turn: 0.07 * sin(step), squash: 1)
    }
}
