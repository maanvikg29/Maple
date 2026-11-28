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

/// A session ended early: Pip slips out of the tree, turns over once and lands softly on the grass, and the pail's
/// leaves scatter (syrup van design §6.6). He ends upright: it is a tumble, never a punishment.
public enum PipFall {
    public static let seconds = 1.8
    /// Where he lands, from his seat.
    public static let landingX = 200.0
    public static let landingY = 930.0
    public static let scatterCount = 6

    private static let slips = 0.25
    private static let lands = 1.05
    private static let up = 1.35

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
        return PipPose(x: landingX, y: landingY, turn: 0, squash: 1)
    }

    /// One of the pail's leaves, from Pip's seat like his own pose.
    public struct Scattered: Sendable, Equatable {
        public let x: Double
        public let y: Double
        public let turn: Double
        /// Which of the three leaf colours.
        public let colour: Int
        public let opacity: Double
    }

    public static func scatter(at time: Double) -> [Scattered] {
        let t = time.isFinite ? time : 0
        let flown = min(1, max(0, (t - slips) / 1.2))
        return (0 ..< scatterCount).map { index in
            let i = Double(index)
            // Out of the pail by his paw, each to its own place on the grass.
            let fromX = 110.0
            let fromY = 60.0
            let toX = landingX - 330 + i * 130 + (index.isMultiple(of: 2) ? 22 : -14)
            let toY = landingY - 60 + Double((index * 53) % 150)
            let eased = 1 - (1 - flown) * (1 - flown)
            return Scattered(
                x: fromX + (toX - fromX) * eased,
                y: fromY + (toY - fromY) * flown * flown - 160 * sin(.pi * flown) * (1 - flown),
                turn: i * 1.3 + 5 * flown, colour: index % 3, opacity: t < slips ? 0 : 1
            )
        }
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
