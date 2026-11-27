import Foundation

/// The playful things Pip does at home. Each is a little film: `scene(at:)` is its frame at a moment, and every one
/// begins and ends with him standing as the picture has him. Pure.
public enum PipAct: String, CaseIterable, Sendable {
    /// Tapped: he hops and hearts pop.
    case hop
    /// Three leaves go round above his paws.
    case juggle
    /// He runs out and jumps for a falling leaf.
    case leafJump
    /// He flops over by the cat and sleeps.
    case nap
    /// He leaps into the leaf basket and pops up with a leaf on his head.
    case basket
    /// He spins his ladle.
    case ladleTwirl
    /// Syrup was cooked, or a session finished: a happy dance.
    case dance
    /// He rakes the fallen leaves into a pile.
    case rake

    /// The ones he does by himself, now and then. The hop and the dance wait for their cue.
    public static let unprompted: [PipAct] = [.juggle, .leafJump, .nap, .basket, .ladleTwirl, .rake]

    public var seconds: Double {
        switch self {
        case .hop: 1.4
        case .juggle: 4.6
        case .leafJump: 5.6
        case .nap: 14
        case .basket: 6.4
        case .ladleTwirl: 2.8
        case .dance: 3.4
        case .rake: 8.4
        }
    }

    /// The nap can be cut short: from here on he is getting up.
    public var wakesAt: Double? {
        self == .nap ? seconds - 1.3 : nil
    }

    public func scene(at time: Double) -> PipScene {
        guard time.isFinite, time > 0, time < seconds else { return .rest }
        switch self {
        case .hop: return Self.hop(time)
        case .juggle: return Self.juggle(time)
        case .leafJump: return Self.leafJump(time)
        case .nap: return Self.nap(time, wakes: seconds - 1.3)
        case .basket: return Self.basket(time)
        case .ladleTwirl: return Self.ladleTwirl(time)
        case .dance: return Self.dance(time, seconds: seconds)
        case .rake: return Self.rake(time)
        }
    }
}

// MARK: - The films

private typealias Spot = (x: Double, y: Double)

private let stand: Spot = (PipHome.standX, PipHome.standY)
private let bench: Spot = (PipHome.benchX, PipHome.benchY)

/// How far `t` is through the stretch from `from` to `to`: 0 before it, 1 after.
private func part(_ t: Double, _ from: Double, _ to: Double) -> Double {
    min(1, max(0, (t - from) / (to - from)))
}

/// Slow out of 0 and slow into 1.
private func ease(_ u: Double) -> Double {
    u * u * (3 - 2 * u)
}

private func mix(_ a: Double, _ b: Double, _ u: Double) -> Double {
    a + (b - a) * u
}

/// 0, up to 1 in the middle, 0 again: the height of a hop.
private func arc(_ u: Double) -> Double {
    4 * u * (1 - u)
}

/// 0, up to 1, 0 again, rounded: a squash, a nod.
private func bump(_ u: Double) -> Double {
    sin(.pi * u)
}

private func frac(_ value: Double) -> Double {
    value - value.rounded(.down)
}

extension PipHomePose {
    /// Part-way through one hop between two spots.
    fileprivate mutating func hop(from: Spot, to: Spot, _ u: Double, height: Double) {
        x = mix(from.x, to.x, u)
        y = mix(from.y, to.y, u)
        lift = height * arc(u)
        stretchY = 1 + 0.05 * arc(u)
        stretchX = 1 - 0.03 * arc(u)
    }

    /// The squash of a landing, or the crouch before a jump.
    fileprivate mutating func squash(_ u: Double, by amount: Double = 0.09) {
        stretchY = 1 - amount * bump(u)
        stretchX = 1 + amount * 0.6 * bump(u)
    }

    /// His paw, in the picture: on the other side of him when he faces left.
    fileprivate var paw: Spot {
        (x + (facesLeft ? -PipHome.pawX : PipHome.pawX) * size, y - lift + PipHome.pawY * size)
    }
}

extension PipAct {
    // MARK: Hop

    private static func hop(_ t: Double) -> PipScene {
        var pose = PipHomePose.rest
        if t < 0.16 {
            pose.squash(part(t, 0, 0.16), by: 0.08)
        } else if t < 0.66 {
            pose.hop(from: stand, to: stand, part(t, 0.16, 0.66), height: 85)
        } else if t < 0.86 {
            pose.squash(part(t, 0.66, 0.86), by: 0.1)
        }
        var props: [PipProp] = []
        let places: [Spot] = [(70, -215), (-62, -235), (38, -275)]
        for (index, place) in places.enumerated() {
            let i = Double(index)
            let born = 0.22 + 0.16 * i
            let u = (t - born) / 0.82
            guard u > 0, u < 1 else { continue }
            props.append(PipProp(
                .heart, x: stand.x + place.x + 6 * sin(6 * u + i), y: stand.y + place.y - 75 * (1 - (1 - u) * (1 - u)),
                turn: 0.15 * sin(5 * u + i), size: (0.75 + 0.12 * i) * min(1, u / 0.18),
                opacity: min(1, u / 0.15) * (1 - ease(part(u, 0.55, 1)))
            ))
        }
        return PipScene(pose: pose, props: props)
    }

    // MARK: Dance

    private static func dance(_ t: Double, seconds: Double) -> PipScene {
        var pose = PipHomePose.rest
        let swing = ease(part(t, 0, 0.3)) * (1 - ease(part(t, seconds - 0.45, seconds - 0.05)))
        let beat = 2 * .pi * t / 0.7
        pose.turn = 0.16 * swing * sin(beat)
        pose.x = stand.x + 20 * swing * sin(beat)
        pose.lift = 16 * swing * abs(sin(beat))
        pose.tail = -0.02 * swing * sin(2 * beat)
        var props: [PipProp] = []
        let places: [Spot] = [(108, -230), (-150, -250), (92, -290)]
        for (index, place) in places.enumerated() {
            let i = Double(index)
            let u = (t - (0.3 + 0.85 * i)) / 1.3
            guard u > 0, u < 1 else { continue }
            props.append(PipProp(
                .note, x: stand.x + place.x + 10 * sin(5 * u + 2 * i), y: stand.y + place.y - 55 * u,
                turn: 0.2 * sin(4 * u + i), size: 0.8 + 0.15 * i,
                opacity: min(1, u / 0.15) * (1 - ease(part(u, 0.6, 1)))
            ))
        }
        return PipScene(pose: pose, props: props)
    }

    // MARK: Ladle

    private static func ladleTwirl(_ t: Double) -> PipScene {
        var pose = PipHomePose.rest
        let busy = ease(part(t, 0, 0.3)) * (1 - ease(part(t, 2.2, 2.5)))
        pose.turn = 0.04 * busy * sin(2 * .pi * t / 0.9)
        pose.lift = 14 * bump(part(t, 2.35, 2.7))
        return PipScene(pose: pose, ladleTurn: 4 * .pi * ease(part(t, 0.3, 2.3)))
    }

    // MARK: Juggle

    private static func juggle(_ t: Double) -> PipScene {
        var pose = PipHomePose.rest
        let busy = ease(part(t, 0.2, 0.5)) * (1 - ease(part(t, 4.0, 4.3)))
        let round = 1.2
        pose.stretchY = 1 + 0.015 * busy * sin(2 * .pi * t / (round / 3))
        pose.turn = 0.03 * busy * sin(2 * .pi * t / round)
        let shown = part(t, 0.3, 0.6) * (1 - part(t, 3.9, 4.2))
        guard shown > 0 else { return PipScene(pose: pose) }
        let middle = stand.x + 8
        let paws = stand.y - 120
        let props = (0 ..< 3).map { index -> PipProp in
            let phase = frac(t / round + Double(index) / 3)
            var x: Double
            var y: Double
            if phase < 0.72 {
                // Thrown: up over his head and down to the other paw.
                let angle = .pi * phase / 0.72
                x = middle - 62 * cos(angle)
                y = paws - 175 * sin(angle)
            } else {
                // Passed back low, paw to paw.
                let v = (phase - 0.72) / 0.28
                x = middle + 62 - 124 * v
                y = paws + 8 * sin(.pi * v)
            }
            // They come out of his paws and go back to them.
            x = mix(middle, x, min(1, shown * 2))
            y = mix(paws, y, min(1, shown * 2))
            return PipProp(.leaf(index), x: x, y: y, turn: 3 * t + 2 * Double(index), size: 0.62, opacity: shown)
        }
        return PipScene(pose: pose, props: props)
    }

    // MARK: Leaf jump

    private static func leafJump(_ t: Double) -> PipScene {
        let grass: Spot = (PipHome.grassX, PipHome.grassY)
        var pose = PipHomePose.rest
        pose.facesLeft = t >= 3.95 && t <= 5.15
        switch t {
        case ..<0.45:
            pose.hop(from: stand, to: bench, part(t, 0, 0.45), height: 50)
        case ..<0.95:
            pose.hop(from: bench, to: grass, part(t, 0.45, 0.95), height: 60)
        case ..<2.0:
            pose.x = grass.x
            pose.y = grass.y
            // He leans back to watch it come down, then crouches.
            pose.turn = -0.06 * ease(part(t, 1.0, 1.4)) * (1 - ease(part(t, 1.6, 1.8)))
            if t > 1.8 { pose.squash(part(t, 1.8, 2.0), by: 0.08) }
        case ..<2.7:
            pose.hop(from: grass, to: grass, part(t, 2.0, 2.7), height: 150)
        case ..<4.1:
            pose.x = grass.x
            pose.y = grass.y
            if t < 2.9 { pose.squash(part(t, 2.7, 2.9), by: 0.1) }
            // Got it: a wiggle.
            let glad = ease(part(t, 2.95, 3.1)) * (1 - ease(part(t, 3.7, 3.85)))
            let beat = 2 * .pi * (t - 2.95) / 0.45
            pose.turn = 0.12 * glad * sin(beat)
            pose.lift = 10 * glad * abs(sin(beat))
        case ..<4.6:
            pose.hop(from: grass, to: bench, part(t, 4.1, 4.6), height: 60)
        case ..<5.1:
            pose.hop(from: bench, to: stand, part(t, 4.6, 5.1), height: 50)
        default:
            if t < 5.3 { pose.squash(part(t, 5.1, 5.3), by: 0.06) }
        }
        let caught = 2.35
        let shown = part(t, 0.5, 0.8) * (1 - part(t, 5.0, 5.4))
        var props: [PipProp] = []
        if shown > 0 {
            if t < caught {
                // Down through the air to where his paw will be at the top of the jump.
                let fall = part(t, 0.5, caught)
                let meetY = grass.y + PipHome.pawY - 10 - 150
                props.append(PipProp(
                    .leaf(0), x: grass.x + PipHome.pawX + 34 * sin(5 * fall) * (1 - fall), y: mix(grass.y - 620, meetY, pow(fall, 1.1)),
                    turn: 0.6 * sin(5 * fall) + 0.4, size: 0.7, opacity: shown
                ))
            } else {
                let paw = pose.paw
                props.append(PipProp(.leaf(0), x: paw.x, y: paw.y - 10, turn: 0.4 + pose.turn, size: 0.7, opacity: shown))
            }
        }
        return PipScene(pose: pose, props: props)
    }

    // MARK: Rake

    private static func rake(_ t: Double) -> PipScene {
        let spot: Spot = (1500, 1790)
        var pose = PipHomePose.rest
        pose.facesLeft = t >= 6.5 && t <= 7.65
        let sweeps = (from: 1.3, each: 1.1, count: 4.0)
        let sweeping = t >= sweeps.from && t < sweeps.from + sweeps.each * sweeps.count
        let sweep = sweeping ? frac((t - sweeps.from) / sweeps.each) : 0
        switch t {
        case ..<0.45:
            pose.hop(from: stand, to: bench, part(t, 0, 0.45), height: 50)
        case ..<0.95:
            pose.hop(from: bench, to: spot, part(t, 0.45, 0.95), height: 60)
        case ..<6.6:
            pose.x = spot.x + 5 * sin(2 * .pi * sweep)
            pose.y = spot.y
            pose.turn = 0.04 * sin(2 * .pi * sweep)
            // Done: a proud little hop.
            if t > 5.8, t < 6.2 { pose.lift = 36 * arc(part(t, 5.8, 6.2)) }
        case ..<7.1:
            pose.hop(from: spot, to: bench, part(t, 6.6, 7.1), height: 60)
        case ..<7.55:
            pose.hop(from: bench, to: stand, part(t, 7.1, 7.55), height: 50)
        default:
            if t < 7.75 { pose.squash(part(t, 7.55, 7.75), by: 0.06) }
        }
        var props: [PipProp] = []
        // The leaves were lying about; each pull of the rake brings them a quarter of the way to the pile.
        let lying = part(t, 0, 0.6) * (1 - part(t, 7.4, 8.2))
        if lying > 0 {
            let done = floor((t - sweeps.from) / sweeps.each)
            let pulled = t < sweeps.from ? 0 : sweeping ? (done + ease(part(sweep, 0.05, 0.5))) / sweeps.count : 1
            let from: [Spot] = [(150, 20), (205, 40), (175, 70), (215, 78), (135, 62), (190, 5)]
            let pile: [Spot] = [(104, 62), (130, 58), (118, 74), (134, 76), (100, 78), (122, 66)]
            for index in from.indices {
                props.append(PipProp(
                    .leaf(index % 3), x: spot.x + mix(from[index].x, pile[index].x, pulled), y: spot.y + mix(from[index].y, pile[index].y, pulled),
                    turn: Double(index) * 1.1 + 1.5 * pulled, size: 0.55, opacity: lying
                ))
            }
        }
        let held = ease(part(t, 0.95, 1.2)) * (1 - ease(part(t, 6.2, 6.45)))
        if held > 0.02 {
            // Reached out at the start of each sweep, pulled in by the middle of it.
            let paw = pose.paw
            props.append(PipProp(.rake, x: paw.x, y: paw.y, turn: -0.39 - 0.17 * cos(2 * .pi * sweep), size: held))
        }
        return PipScene(pose: pose, props: props)
    }

    // MARK: Nap

    private static func nap(_ t: Double, wakes: Double) -> PipScene {
        var pose = PipHomePose.rest
        // A yawn of a stretch, then over he goes.
        if t < 0.7 { pose.stretchY = 1 + 0.06 * bump(part(t, 0, 0.7)) }
        let down = t < wakes ? ease(part(t, 0.7, 1.5)) : 1 - ease(part(t, wakes + 0.15, wakes + 0.85))
        pose.asleep = t >= 0.5 && t < wakes + 0.2
        pose.turn = -1.36 * down
        pose.x = stand.x - 28 * down
        pose.y = stand.y + 40 * down
        pose.shadow = 1 - 0.35 * down
        if t > 1.5, t < wakes {
            let settled = part(t, 1.5, 2.0) * (1 - part(t, wakes - 0.3, wakes))
            pose.stretchY = 1 + 0.03 * settled * sin(2 * .pi * (t - 1.5) / 3.6)
        }
        if t > wakes + 0.9 { pose.lift = 28 * arc(part(t, wakes + 0.9, wakes + 1.25)) }
        var props: [PipProp] = []
        if t > 1.8, t < wakes {
            for index in 0 ..< 3 {
                let since = t - 1.8 - 0.5 * Double(index)
                guard since > 0 else { continue }
                let u = frac(since / 1.5)
                props.append(PipProp(
                    .zed, x: 1070 - 26 * u - 8 * sin(4 * u), y: 1490 - 95 * u, turn: -0.15, size: 0.55 + 0.6 * u,
                    opacity: min(1, u / 0.15) * (1 - part(u, 0.7, 1)) * (1 - part(t, wakes - 0.2, wakes))
                ))
            }
        }
        return PipScene(pose: pose, props: props)
    }

    // MARK: Basket

    private static func basket(_ t: Double) -> PipScene {
        let small = PipHome.basketSize
        let inside: Spot = (PipHome.basketX, PipHome.basketY)
        let ducked: Spot = (inside.x, inside.y + 45)
        var pose = PipHomePose.rest
        var isInside = false
        // A whole turn in the leap there; it is undone in the leap home.
        var over = 0.0
        switch t {
        case ..<0.2:
            pose.squash(part(t, 0, 0.2), by: 0.08)
        case ..<1.35:
            let u = part(t, 0.2, 1.35)
            pose.hop(from: stand, to: inside, u, height: 330)
            over = ease(u)
            pose.size = mix(1, small, ease(part(u, 0.35, 0.9)))
            pose.shadow = 1 - part(u, 0.1, 0.6)
            isInside = u >= 0.94
        case ..<4.95:
            isInside = true
            over = 1
            pose.size = small
            pose.shadow = 0
            pose.x = inside.x
            if t < 1.6 {
                pose.y = mix(inside.y, ducked.y, ease(part(t, 1.35, 1.6)))
            } else if t < 2.0 {
                pose.y = ducked.y
            } else if t < 2.5 {
                // Up he pops, a little too far, and settles.
                pose.y = mix(ducked.y, inside.y, ease(part(t, 2.0, 2.3))) - 14 * bump(part(t, 2.2, 2.5))
            } else if t < 4.4 {
                pose.y = inside.y
                let looking = ease(part(t, 2.5, 2.7)) * (1 - ease(part(t, 4.2, 4.4)))
                pose.turn = 0.14 * looking * sin(2 * .pi * (t - 2.5) / 1.0)
            } else {
                pose.y = mix(inside.y, ducked.y, ease(part(t, 4.4, 4.7)))
            }
        case ..<6.1:
            let u = part(t, 4.95, 6.1)
            pose.hop(from: ducked, to: stand, u, height: 330)
            over = 1 - ease(u)
            pose.size = mix(small, 1, ease(part(u, 0.1, 0.65)))
            pose.shadow = part(u, 0.4, 0.9)
            isInside = u <= 0.06
        default:
            if t < 6.3 { pose.squash(part(t, 6.1, 6.3), by: 0.1) }
        }
        pose.turn -= 2 * .pi * over
        var props: [PipProp] = []
        // Leaves fly up as he lands in them.
        let since = t - 1.35
        if since > 0, since < 1.0 {
            let speeds: [Spot] = [(-150, -260), (-70, -340), (10, -380), (90, -330), (160, -250)]
            for (index, speed) in speeds.enumerated() {
                props.append(PipProp(
                    .leaf(index % 3), x: inside.x + speed.x * since, y: 1735 + speed.y * since + 350 * since * since,
                    turn: 4 * since + Double(index), size: 0.6, opacity: 1 - part(since, 0.6, 1.0)
                ))
            }
        }
        // And one stays on his head.
        let wearing = part(t, 2.0, 2.2) * (1 - part(t, 4.4, 4.6))
        if wearing > 0 {
            let look = pose.turn + 2 * .pi
            let reach = (PipHome.headY - PipHome.middleY) * small
            props.append(PipProp(
                .leaf(0), x: pose.x + PipHome.headX * small - reach * sin(look), y: pose.y - (PipHome.height - 6) * small,
                turn: 0.3 + look, size: 0.5, opacity: wearing
            ))
        }
        return PipScene(pose: pose, props: props, inBasket: isInside)
    }
}
