import Foundation

/// What moves in the session scene (`VanTreeSessionView`). Ordinarily all of it; with calm on, only Pip, so the screen
/// is less distracting (the owner, 28 Nov 2026: "disables the leafs falling and ... just keeps pip moving"); dimmed, or
/// with Reduce Motion, nothing.
public struct VanSessionMotion: Sendable, Equatable {
    /// The leaves coming down from the canopy.
    public let leaves: Bool
    /// The clouds drifting across the sky.
    public let clouds: Bool
    /// The string lights twinkling.
    public let lights: Bool
    /// Pip breathing, blinking and catching leaves for his basket.
    public let pip: Bool
    /// Whether the falling leaves are drawn at all. Calm takes them away altogether, so none is ever left hanging in
    /// the air; otherwise, dimmed or with Reduce Motion, they are drawn as they are, held.
    public let showsFallingLeaves: Bool

    public init(leaves: Bool, clouds: Bool, lights: Bool, pip: Bool, showsFallingLeaves: Bool? = nil) {
        self.leaves = leaves
        self.clouds = clouds
        self.lights = lights
        self.pip = pip
        self.showsFallingLeaves = showsFallingLeaves ?? leaves
    }

    public static func of(calm: Bool, dimmed: Bool, reduceMotion: Bool) -> VanSessionMotion {
        if dimmed || reduceMotion {
            return VanSessionMotion(leaves: false, clouds: false, lights: false, pip: false, showsFallingLeaves: !calm)
        }
        return VanSessionMotion(leaves: !calm, clouds: !calm, lights: !calm, pip: true)
    }

    /// Whether anything moves at all: if not, the scene's clock can stop.
    public var anything: Bool { leaves || clouds || lights || pip }
}
