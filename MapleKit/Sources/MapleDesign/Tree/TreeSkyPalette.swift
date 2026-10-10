import MapleCore
import SwiftUI

/// The sky and scene light for one phase of the day (spec §4.4), as data. Built from the theme's scene colours.
nonisolated public struct SkyPalette: Sendable {
    /// Gradient stops over the 560 pt scene, top to bottom (locations 0…1).
    public var stops: [Gradient.Stop]
    /// The warm dawn wash over y 380–480 (morning only), or nil.
    public var dawnWash: Color?
    /// A soft pool of light: colour, centre (in the 402 × 560 reference frame) and radius.
    public var pool: (color: Color, center: CGPoint, radius: CGFloat)?
    public var showsMoon: Bool
    /// Peak opacity of the moonlight pool reaching from the moon toward the crown (0 = none).
    public var moonlightPool: Double
    /// How many of the 48 stars show, and at what opacity range.
    public var starCount: Int
    public var starOpacity: ClosedRange<Double>
    /// How many stars twinkle (all of them when equal to `starCount`).
    public var twinklingStars: Int
    /// Multiplies every on-tree colour (spec §6.1: wind-down 0.9, night 0.75).
    public var treeBrightness: Double
    /// Canopy bloom base opacity before vitality (spec §4.4).
    public var bloomOpacity: Double
    /// The moon disc and star colour (opaque; opacities are applied where drawn).
    public var moonDisc: Color
    /// Moonlight pools.
    public var moonlight: Color
    /// Unit vector toward the light that models the bark and canopy, in screen space (y down).
    public var lightDirection: CGVector
    /// Where the moon sits, in the 402 × 560 reference frame.
    public static let moonCenter = CGPoint(x: 322, y: 128)
}

extension Theme.SceneColors {
    /// The §4.4 table for `phase`. No other sky hues exist.
    nonisolated public func sky(for phase: NowPhase) -> SkyPalette {
        let moonward = CGVector(dx: 0.58, dy: -0.81)
        let disc = moonDisc.opacity(1 / 0.55)
        switch phase {
        case .morning:
            return SkyPalette(
                stops: [.init(color: skyNavy, location: 0), .init(color: skyDay, location: 0.55), .init(color: skyNight, location: 1)],
                dawnWash: dawnWash,
                pool: (dawnPool, CGPoint(x: 40, y: 40), 360),
                showsMoon: false, moonlightPool: 0,
                starCount: 12, starOpacity: 0.10...0.10, twinklingStars: 0,
                treeBrightness: 1, bloomOpacity: 0.14,
                moonDisc: disc, moonlight: moonlight,
                lightDirection: CGVector(dx: -0.66, dy: -0.75)
            )
        case .day:
            return SkyPalette(
                stops: [.init(color: skyNavy, location: 0), .init(color: skyDay, location: 0.5), .init(color: skyNight, location: 1)],
                dawnWash: nil,
                pool: (moonlight.opacity(0.06), CGPoint(x: 201, y: 0), 380),
                showsMoon: false, moonlightPool: 0,
                starCount: 0, starOpacity: 0...0, twinklingStars: 0,
                treeBrightness: 1, bloomOpacity: 0.12,
                moonDisc: disc, moonlight: moonlight,
                lightDirection: CGVector(dx: -0.22, dy: -0.97)
            )
        case .evening, .windDown:
            return SkyPalette(
                stops: [.init(color: skyNight, location: 0), .init(color: skyNavy, location: 0.55), .init(color: skyNight, location: 1)],
                dawnWash: nil, pool: nil,
                showsMoon: true, moonlightPool: 0.07,
                starCount: 48, starOpacity: 0.15...0.50, twinklingStars: 48,
                treeBrightness: phase == .windDown ? 0.9 : 1, bloomOpacity: phase == .windDown ? 0.12 : 0.14,
                moonDisc: disc, moonlight: moonlight,
                lightDirection: moonward
            )
        case .night:
            return SkyPalette(
                stops: [.init(color: skyNight, location: 0), .init(color: skyDeep, location: 1)],
                dawnWash: nil, pool: nil,
                showsMoon: true, moonlightPool: 0.05,
                starCount: 48, starOpacity: 0.45...0.45, twinklingStars: 2,
                treeBrightness: 0.75, bloomOpacity: 0.08,
                moonDisc: disc, moonlight: moonlight,
                lightDirection: moonward
            )
        }
    }
}
