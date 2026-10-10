import Foundation

/// A point or vector in *tree space*: points at the reference 402 × 560 stage, origin at the trunk base,
/// x to the right and **y up**. The scene maps it to the screen with `screen = base + (x, −y) × scale`.
public struct TreePoint: Sendable, Hashable, Codable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = TreePoint(x: 0, y: 0)
    public static let up = TreePoint(x: 0, y: 1)

    public var length: Double { (x * x + y * y).squareRoot() }

    /// The unit vector in the same direction, or `fallback` for a (near) zero vector.
    public func normalized(or fallback: TreePoint = .up) -> TreePoint {
        let l = length
        return l > 1e-9 ? TreePoint(x: x / l, y: y / l) : fallback
    }

    public func dot(_ other: TreePoint) -> Double { x * other.x + y * other.y }

    public func distance(to other: TreePoint) -> Double { (self - other).length }

    /// The angle of this direction in radians, clockwise from straight up (as seen on screen).
    public var angleFromUp: Double { atan2(x, y) }

    /// The unit direction `angle` radians clockwise from straight up.
    public static func direction(angleFromUp angle: Double) -> TreePoint {
        TreePoint(x: sin(angle), y: cos(angle))
    }

    public static func + (lhs: TreePoint, rhs: TreePoint) -> TreePoint { TreePoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y) }
    public static func - (lhs: TreePoint, rhs: TreePoint) -> TreePoint { TreePoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }
    public static func * (lhs: TreePoint, rhs: Double) -> TreePoint { TreePoint(x: lhs.x * rhs, y: lhs.y * rhs) }
    public static func += (lhs: inout TreePoint, rhs: TreePoint) { lhs = lhs + rhs }

    /// Linear interpolation from `a` (t = 0) to `b` (t = 1).
    public static func lerp(_ a: TreePoint, _ b: TreePoint, _ t: Double) -> TreePoint {
        a + (b - a) * t
    }
}

/// SplitMix64: a tiny, fast, well-mixed generator with a 64-bit state. Every random choice in the tree
/// comes from one of these, so a seed always grows the same tree on every device and Swift version
/// (the standard library's `random(in:using:)` algorithms are not guaranteed stable, so they are not used).
public struct SplitMix64: RandomNumberGenerator, Sendable {
    public private(set) var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A uniform double in 0..<1 (53 random bits).
    public mutating func unit() -> Double {
        Double(next() >> 11) * 0x1.0p-53
    }

    /// A uniform double in `lower..<upper`.
    public mutating func range(_ lower: Double, _ upper: Double) -> Double {
        lower + (upper - lower) * unit()
    }

    /// −1 or +1 with equal odds.
    public mutating func sign() -> Double {
        next() & 1 == 0 ? -1 : 1
    }

    /// A seed derived from `seed` and `salt`, so independent streams never share a sequence.
    public static func derive(_ seed: UInt64, _ salt: UInt64) -> UInt64 {
        var generator = SplitMix64(seed: seed ^ (salt &* 0xD6E8_FEB8_6659_FD93))
        return generator.next()
    }

    /// A seed derived from `seed` and a string (e.g. a species id), via 64-bit FNV-1a.
    public static func derive(_ seed: UInt64, _ salt: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in salt.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return derive(seed, hash)
    }

    /// The tree seed for a profile: the UUID's 128 bits folded into 64 (spec §4.2).
    public static func seed(for uuid: UUID) -> UInt64 {
        let b = uuid.uuid
        let high = [b.0, b.1, b.2, b.3, b.4, b.5, b.6, b.7].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        let low = [b.8, b.9, b.10, b.11, b.12, b.13, b.14, b.15].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        return derive(high, low)
    }
}

/// Small easing helpers shared by the layout.
enum TreeMath {
    static func clamp(_ value: Double, _ lower: Double = 0, _ upper: Double = 1) -> Double {
        min(max(value, lower), upper)
    }

    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    static func smoothstep(_ t: Double) -> Double {
        let x = clamp(t)
        return x * x * (3 - 2 * x)
    }
}
