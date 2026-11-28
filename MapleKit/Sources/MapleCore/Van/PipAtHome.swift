import Foundation

/// Marks on home's picture, in its own pixels (`VanCanvas.home`), that Pip's acts are built around.
public enum PipHome {
    /// Where his feet stand in the picture.
    public static let standX = 1185.0
    public static let standY = 1650.0
    /// His reaching paw, from his feet: where the ladle's handle is, and where a rake is held.
    public static let pawX = 71.0
    public static let pawY = -135.0
    /// The middle of him, from his feet: what he turns about.
    public static let middleX = -7.0
    public static let middleY = -115.0
    /// The middle of his head, from his feet.
    public static let headX = 18.0
    public static let headY = -190.0
    /// Feet to ear tips.
    public static let height = 260.0
    /// The bench outside the door, and the grass beyond it.
    public static let benchX = 1265.0
    public static let benchY = 1748.0
    public static let grassX = 1560.0
    public static let grassY = 1800.0
    /// His feet when he is in the leaf basket, and his size there (he must fit).
    public static let basketX = 322.0
    public static let basketY = 1832.0
    public static let basketSize = 0.62
}

/// How Pip stands on home's picture at one moment. Pure.
///
/// He is one picture: an act can move him, lift him, turn him, squash and stretch him, flip him and make him
/// smaller, and can swing his tail and one ear, which are cut apart from him. Nothing here bends him.
public struct PipHomePose: Sendable, Equatable {
    /// Where his feet are on the ground, in the picture's pixels.
    public var x: Double
    public var y: Double
    /// Off the ground by this much; his shadow stays down.
    public var lift = 0.0
    /// Turned about his middle, in radians, clockwise.
    public var turn = 0.0
    /// Wider and taller than himself, from his feet: 1 is as drawn.
    public var stretchX = 1.0
    public var stretchY = 1.0
    /// 1 is his own size.
    public var size = 1.0
    /// The picture has him facing right.
    public var facesLeft = false
    /// His tail swung about its root, in radians, clockwise: negative is away from his back.
    public var tail = 0.0
    /// His ear turned about its root.
    public var ear = 0.0
    /// His eyes are closed.
    public var asleep = false
    /// How much of his shadow shows: 1 on the ground, 0 when he is far off it or out of sight.
    public var shadow = 1.0

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    /// As the picture has him.
    public static let rest = PipHomePose(x: PipHome.standX, y: PipHome.standY)

    /// Whether a place in the picture is on him: his tail is behind him, to the left.
    public func contains(x px: Double, y py: Double) -> Bool {
        guard px.isFinite, py.isFinite else { return false }
        let feet = y - lift
        return px >= x - 150 * size && px <= x + 90 * size && py >= feet - 265 * size && py <= feet + 12
    }
}

/// Something beside Pip in an act: a heart, a music note, a "z", a rake, a leaf.
public struct PipProp: Sendable, Equatable {
    public enum Kind: Sendable, Hashable {
        case heart
        case note
        case zed
        /// Placed by the top of its handle, where it is held.
        case rake
        /// One of the three leaf colours: 0, 1 or 2.
        case leaf(Int)
    }

    public var kind: Kind
    /// Its middle (the rake: its grip), in the picture's pixels.
    public var x: Double
    public var y: Double
    public var turn: Double
    /// 1 is its own size.
    public var size: Double
    public var opacity: Double
    /// Drawn over Pip, not behind him.
    public var inFront: Bool

    public init(_ kind: Kind, x: Double, y: Double, turn: Double = 0, size: Double = 1, opacity: Double = 1, inFront: Bool = true) {
        self.kind = kind
        self.x = x
        self.y = y
        self.turn = turn
        self.size = size
        self.opacity = min(1, max(0, opacity))
        self.inFront = inFront
    }
}

/// One frame of Pip at home: himself and whatever is with him.
public struct PipScene: Sendable, Equatable {
    public var pose: PipHomePose
    public var props: [PipProp]
    /// nil while the ladle hangs on its knob; in his paw, how far round it has turned (radians, clockwise).
    public var ladleTurn: Double?
    /// He is in the leaf basket: its front and the leaves heaped at it are drawn over him.
    public var inBasket: Bool

    public init(pose: PipHomePose = .rest, props: [PipProp] = [], ladleTurn: Double? = nil, inBasket: Bool = false) {
        self.pose = pose
        self.props = props
        self.ladleTurn = ladleTurn
        self.inBasket = inBasket
    }

    /// As the picture has it.
    public static let rest = PipScene()
}

/// Pip is never quite still: he breathes, his tail swishes and one ear flicks. Pure: the same moment is always
/// the same frame.
public enum PipIdle {
    public static func pose(at time: Double) -> PipHomePose {
        let t = clock(time)
        var pose = PipHomePose.rest
        let breath = sin(2 * .pi * t / 3.4)
        pose.stretchY = 1 + 0.012 * breath
        pose.stretchX = 1 - 0.006 * breath
        pose.tail = tail(t)
        pose.ear = ear(t)
        return pose
    }

    /// His tail and ear go on while he does something else.
    public static func liven(_ pose: inout PipHomePose, at time: Double) {
        let t = clock(time)
        pose.tail += tail(t) * (pose.asleep ? 0.4 : 1)
        pose.ear += pose.asleep ? 0 : ear(t)
    }

    private static func clock(_ time: Double) -> Double {
        time.isFinite ? min(max(0, time), 1e9) : 0
    }

    /// A slow swish with a quicker one on top. Small: the tail's edge behind his back is painted, not his.
    private static func tail(_ t: Double) -> Double {
        0.034 * sin(2 * .pi * t / 2.7) + 0.012 * sin(2 * .pi * t / 0.95 + 1)
    }

    /// Two quick flicks, then stillness.
    private static func ear(_ t: Double) -> Double {
        let phase = t.truncatingRemainder(dividingBy: 5.6)
        for start in [0.8, 1.15] where phase > start && phase < start + 0.2 {
            return 0.12 * sin(.pi * (phase - start) / 0.2)
        }
        return 0
    }
}

/// Which act comes next unprompted, and how long he waits first. Pure: the dice are the caller's.
public enum PipDirector {
    public static func next(after last: PipAct?, roll: UInt64) -> (wait: Double, act: PipAct) {
        let acts = PipAct.unprompted.filter { $0 != last }
        let wait = 20 + Double(roll % 2001) / 100
        return (wait, acts[Int((roll / 2001) % UInt64(acts.count))])
    }
}

/// What Pip is doing at home, on any clock that only runs forward (seconds). Pure.
public struct PipStage: Sendable, Equatable {
    private var playing: PipAct?
    private var began = 0.0

    public init() {}

    /// The act he is in the middle of.
    public func act(at now: Double) -> PipAct? {
        guard let playing, now.isFinite, now >= began, now - began < playing.seconds else { return nil }
        return playing
    }

    public func isBusy(at now: Double) -> Bool {
        act(at: now) != nil
    }

    /// He starts an act, unless he is in the middle of one (`cuttingIn` starts it anyway).
    public mutating func play(_ act: PipAct, at now: Double, cuttingIn: Bool = false) {
        guard now.isFinite, cuttingIn || !isBusy(at: now) else { return }
        playing = act
        began = now
    }

    /// He was tapped: idle, he hops; napping, he wakes; in the middle of anything else, he carries on.
    public mutating func tapped(at now: Double) {
        guard let act = act(at: now) else {
            play(.hop, at: now)
            return
        }
        if let wakes = act.wakesAt, now - began < wakes {
            began = now - wakes
        }
    }

    /// The frame to draw. `still` (Reduce Motion) is the picture as it is.
    public func scene(at now: Double, still: Bool = false) -> PipScene {
        if still { return .rest }
        guard let act = act(at: now) else { return PipScene(pose: PipIdle.pose(at: now)) }
        var scene = act.scene(at: now - began)
        PipIdle.liven(&scene.pose, at: now)
        return scene
    }
}
