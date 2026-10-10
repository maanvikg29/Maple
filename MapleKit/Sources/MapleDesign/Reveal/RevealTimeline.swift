import Foundation
import MapleCore

/// Which version of the unlock ritual a leaf gets (spec §5.8, D8).
nonisolated public enum RevealRitual: Sendable, Hashable, CaseIterable {
    /// 2.8 s: the bud's scales part, the leaf unfurls from its stalk, veins draw in, the fill arrives, the amber
    /// bloom turns into the leaf's own colour and the leaf settles.
    case full
    /// 1.2 s: the bud fades, the leaf grows in with its fill, and the bloom turns from amber to the leaf's colour.
    case short
    /// Reduce Motion: the bud crossfades to the complete leaf and its text over 0.6 s.
    case crossfade

    /// The first 3 reveals ever, and every uncommon, rare and legendary leaf, get the full ritual; First-steps and
    /// common leaves after that get the short one. Under Reduce Motion every reveal is the crossfade.
    /// - Parameter revealsBefore: Reveals the member had opened before this one (`CollectionStore.revealsOpened`
    ///   plus the leaves already opened in this sitting).
    public init(tier: RewardTier, revealsBefore: Int, reduceMotion: Bool) {
        if reduceMotion {
            self = .crossfade
        } else if revealsBefore < Self.fullRitualReveals || tier >= .uncommon {
            self = .full
        } else {
            self = .short
        }
    }

    /// How many reveals ever get the full ritual whatever their tier.
    public static let fullRitualReveals = 3

    /// When the footer (and the share circle) start to fade in, in seconds after the tap.
    public var footerStart: TimeInterval {
        switch self {
        case .full: 2.6
        case .short: 0.6
        case .crossfade: 0.3
        }
    }

    /// When every part has come to rest: nothing moves after this.
    public var settledTime: TimeInterval {
        switch self {
        case .full: 3.2
        case .short: 1.2
        case .crossfade: 0.6
        }
    }
}

/// Everything the reveal draws at one moment of a ritual, as plain numbers (spec §5.8 timeline).
///
/// The reveal is a pure function of the time since the tap, so any instant can be drawn exactly: the live cover
/// samples it from a timeline, snapshots and DEBUG still frames (`-MapleDemoRevealAt`) pass a fixed time.
///
/// ```swift
/// let frame = RevealFrame.at(0.9, ritual: .full)   // scales parting, leaf half unfurled
/// ```
nonisolated public struct RevealFrame: Sendable, Equatable {
    // The bud.
    /// 0…1: the closed bud's opacity.
    public var budOpacity: Double
    /// Degrees each scale has turned away from the other (0 closed, 35 fully parted).
    public var budSpread: Double
    /// 0…1: the bud's amber core glow, relative to its resting strength.
    public var budGlow: Double

    // The leaf.
    /// The leaf's scale about its centre.
    public var leafScale: Double
    /// Degrees added to the resting tilt (−25 at the start of the full ritual, 0 at rest).
    public var leafTurn: Double
    /// 0…1: how far the unfurling mask has swept from the stalk to the tip.
    public var unfurl: Double
    /// 0…1: how much of each vein is drawn.
    public var veins: Double
    /// 0…1: the blade's colour.
    public var fill: Double
    /// 0…1: the whole leaf's opacity (the short ritual and the crossfade fade it in).
    public var leafOpacity: Double
    /// Points the leaf has drifted down from the bud's centre (12 at rest).
    public var drop: Double
    /// 0…1: the contact shadow under the leaf.
    public var shadow: Double

    // Light.
    /// Opacity of the amber reveal bloom (never above 30%, spec §6.5).
    public var amberBloom: Double
    /// 0…1: the amber bloom's radius, as a fraction of its full 200 pt.
    public var amberReach: Double
    /// Opacity of the leaf's own-colour bloom (never above 22%).
    public var leafBloom: Double

    // Words and actions.
    /// 0…1: the name, chips, earned line and rarity.
    public var textOpacity: Double
    /// Points the text still has to rise (8 → 0).
    public var textRise: Double
    /// 0…1: the footer's buttons and the share circle.
    public var footerOpacity: Double
    /// 0…1: the closed state's "Tap to open" prompt, which leaves with the bud.
    public var promptOpacity: Double

    /// The closed bud, before the tap.
    public static let closed = RevealFrame(
        budOpacity: 1, budSpread: 0, budGlow: 1, leafScale: 0.2, leafTurn: -25, unfurl: 0, veins: 0, fill: 0,
        leafOpacity: 0, drop: 0, shadow: 0, amberBloom: 0, amberReach: 0, leafBloom: 0, textOpacity: 0, textRise: 8,
        footerOpacity: 0, promptOpacity: 1
    )

    /// The opened leaf at rest, whatever ritual brought it there.
    public static let opened = RevealFrame(
        budOpacity: 0, budSpread: 35, budGlow: 0, leafScale: 1, leafTurn: 0, unfurl: 1, veins: 1, fill: 1,
        leafOpacity: 1, drop: restingDrop, shadow: 1, amberBloom: 0, amberReach: 1, leafBloom: leafBloomCap,
        textOpacity: 1, textRise: 0, footerOpacity: 1, promptOpacity: 0
    )

    /// The settled leaf sits this far below the bud's centre.
    public static let restingDrop = 12.0
    /// The §6.5 caps for the reveal's two blooms.
    public static let amberBloomCap = 0.30
    public static let leafBloomCap = 0.22

    /// The frame `time` seconds after the tap. Negative times are the closed bud; times past the ritual are the
    /// opened leaf.
    public static func at(_ time: TimeInterval, ritual: RevealRitual) -> RevealFrame {
        guard time.isFinite else { return time > 0 ? .opened : .closed }
        guard time > 0 else { return .closed }
        switch ritual {
        case .full: return full(time)
        case .short: return short(time)
        case .crossfade: return crossfade(time)
        }
    }

    // MARK: Rituals

    /// The full ritual's table, row by row (spec §5.8).
    private static func full(_ t: TimeInterval) -> RevealFrame {
        // 0–0.6 s: the scales rotate ±35° apart and fade (easeOut).
        let bud = RevealEasing.easeOut(progress(t, from: 0, to: 0.6))
        // 0.2–1.6 s: the leaf scales 0.2 → 1, turns from −25° to its resting tilt and unfurls (`reveal` curve).
        let unfurl = RevealEasing.reveal(progress(t, from: 0.2, to: 1.6))
        // 0.4–1.6 s: veins draw in.
        let veins = RevealEasing.reveal(progress(t, from: 0.4, to: 1.6))
        // 1.0–1.8 s: the fill fades in.
        let fill = RevealEasing.easeInOut(progress(t, from: 1.0, to: 1.8))
        // 0–1.6 s: the amber bloom grows to 30%; 1.6–2.4 s: it crossfades to the leaf's colour at 22%.
        let grow = RevealEasing.easeOut(progress(t, from: 0, to: 1.6))
        let turn = RevealEasing.easeInOut(progress(t, from: 1.6, to: 2.4))
        // 1.8–2.8 s: the leaf drifts 12 pt down and settles, with no overshoot.
        let settle = RevealEasing.easeInOut(progress(t, from: 1.8, to: 2.8))
        // 2.0–2.6 s: the text fades in, rising 8 pt.
        let text = RevealEasing.easeOut(progress(t, from: 2.0, to: 2.6))
        // From 2.6 s: the footer and share circle, over `gentle`.
        let footer = RevealEasing.easeInOut(progress(t, from: 2.6, to: 3.2))
        return RevealFrame(
            budOpacity: 1 - bud, budSpread: 35 * bud, budGlow: 1 - bud,
            leafScale: 0.2 + 0.8 * unfurl, leafTurn: -25 * (1 - unfurl), unfurl: unfurl, veins: veins, fill: fill,
            leafOpacity: 1, drop: restingDrop * settle, shadow: fill,
            amberBloom: amberBloomCap * grow * (1 - turn), amberReach: 0.6 + 0.4 * grow, leafBloom: leafBloomCap * turn,
            textOpacity: text, textRise: 8 * (1 - text), footerOpacity: footer,
            promptOpacity: 1 - RevealEasing.easeOut(progress(t, from: 0, to: 0.3))
        )
    }

    /// The short ritual: 1.2 s in all.
    private static func short(_ t: TimeInterval) -> RevealFrame {
        // The bud fades over 0.3 s.
        let bud = RevealEasing.easeInOut(progress(t, from: 0, to: 0.3))
        // The leaf scales 0.6 → 1 while its fill appears over 0.8 s.
        let grow = RevealEasing.reveal(progress(t, from: 0.1, to: 0.9))
        let fill = RevealEasing.easeInOut(progress(t, from: 0.1, to: 0.9))
        let appear = RevealEasing.easeOut(progress(t, from: 0.1, to: 0.4))
        // The bloom goes amber → leaf colour over 1.0 s.
        let amber = RevealEasing.easeOut(progress(t, from: 0, to: 0.3))
        let turn = RevealEasing.easeInOut(progress(t, from: 0.2, to: 1.2))
        // Text (and the footer) at 0.6 s.
        let text = RevealEasing.easeOut(progress(t, from: 0.6, to: 1.2))
        return RevealFrame(
            budOpacity: 1 - bud, budSpread: 0, budGlow: 1 - bud,
            leafScale: 0.6 + 0.4 * grow, leafTurn: 0, unfurl: 1, veins: 1, fill: fill,
            leafOpacity: appear, drop: restingDrop, shadow: fill,
            amberBloom: amberBloomCap * amber * (1 - turn), amberReach: 0.8 + 0.2 * amber, leafBloom: leafBloomCap * turn,
            textOpacity: text, textRise: 8 * (1 - text), footerOpacity: text,
            promptOpacity: 1 - bud
        )
    }

    /// Reduce Motion: one 0.6 s crossfade from the bud to the complete leaf, its text and its footer. "Tap to
    /// open" leaves in the first half and the footer, which takes its place, arrives in the second.
    private static func crossfade(_ t: TimeInterval) -> RevealFrame {
        let p = RevealEasing.easeInOut(progress(t, from: 0, to: 0.6))
        return RevealFrame(
            budOpacity: 1 - p, budSpread: 0, budGlow: 1 - p,
            leafScale: 1, leafTurn: 0, unfurl: 1, veins: 1, fill: 1,
            leafOpacity: p, drop: restingDrop, shadow: p,
            amberBloom: 0, amberReach: 1, leafBloom: leafBloomCap * p,
            textOpacity: p, textRise: 0,
            footerOpacity: RevealEasing.easeInOut(progress(t, from: 0.3, to: 0.6)),
            promptOpacity: 1 - RevealEasing.easeInOut(progress(t, from: 0, to: 0.3))
        )
    }

    /// 0…1 through the window `start…end`.
    static func progress(_ t: TimeInterval, from start: TimeInterval, to end: TimeInterval) -> Double {
        guard end > start else { return t >= end ? 1 : 0 }
        return min(1, max(0, (t - start) / (end - start)))
    }
}

/// "Open all" (spec §5.8): the remaining buds open one after another, 0.35 s apart, each with the short ritual;
/// then the list of opened leaves follows. Under Reduce Motion it goes straight to the list.
nonisolated public struct RevealOpenAllSchedule: Sendable, Equatable {
    /// The gap between one bud starting to open and the next.
    public static let stagger: TimeInterval = 0.35
    /// The pause after the last leaf settles before the list replaces the row.
    public static let listPause: TimeInterval = 0.4
    /// The row-to-list crossfade (`gentle`).
    public static let listFade: TimeInterval = 0.6

    /// How many buds open in the row.
    public let count: Int
    public let reduceMotion: Bool

    public init(count: Int, reduceMotion: Bool) {
        self.count = max(0, count)
        self.reduceMotion = reduceMotion
    }

    /// When bud `index` starts its short ritual.
    public func start(of index: Int) -> TimeInterval {
        Double(max(0, index)) * Self.stagger
    }

    /// Bud `index` at `time` seconds after "Open all".
    public func frame(of index: Int, at time: TimeInterval) -> RevealFrame {
        RevealFrame.at(time - start(of: index), ritual: .short)
    }

    /// When the list starts to replace the row.
    public var listStart: TimeInterval {
        guard !reduceMotion else { return 0 }
        return start(of: count - 1) + RevealRitual.short.settledTime + Self.listPause
    }

    /// 0…1: the list's opacity.
    public func listOpacity(at time: TimeInterval) -> Double {
        RevealEasing.easeInOut(RevealFrame.progress(time, from: listStart, to: listStart + Self.listFade))
    }

    /// 0…1: the row's opacity. It leaves in the first half of the list's fade, so the two never stack up;
    /// under Reduce Motion there is no row.
    public func rowOpacity(at time: TimeInterval) -> Double {
        guard !reduceMotion else { return 0 }
        return 1 - RevealEasing.easeInOut(RevealFrame.progress(time, from: listStart, to: listStart + Self.listFade / 2))
    }

    /// Nothing moves after this.
    public var settledTime: TimeInterval {
        listStart + Self.listFade
    }
}

/// The curves the reveal uses, evaluated as numbers so a frame can be computed for any instant.
nonisolated public enum RevealEasing {
    /// The `reveal` token's curve: `timingCurve(0.2, 0, 0, 1)`.
    public static func reveal(_ x: Double) -> Double {
        cubicBezier(x, 0.2, 0, 0, 1)
    }

    /// SwiftUI's `easeOut`: (0, 0, 0.58, 1).
    public static func easeOut(_ x: Double) -> Double {
        cubicBezier(x, 0, 0, 0.58, 1)
    }

    /// SwiftUI's `easeInOut`: (0.42, 0, 0.58, 1).
    public static func easeInOut(_ x: Double) -> Double {
        cubicBezier(x, 0.42, 0, 0.58, 1)
    }

    /// The y of a CSS-style cubic Bézier timing curve through (0, 0), (x1, y1), (x2, y2), (1, 1) at `x`.
    public static func cubicBezier(_ x: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        guard x.isFinite else { return x > 0 ? 1 : 0 }
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        func curve(_ s: Double, _ p1: Double, _ p2: Double) -> Double {
            let u = 1 - s
            return 3 * u * u * s * p1 + 3 * u * s * s * p2 + s * s * s
        }
        func slope(_ s: Double, _ p1: Double, _ p2: Double) -> Double {
            let u = 1 - s
            return 3 * u * u * p1 + 6 * u * s * (p2 - p1) + 3 * s * s * (1 - p2)
        }
        // Newton's method from x, falling back to bisection where the slope is flat.
        var s = x
        for _ in 0..<8 {
            let error = curve(s, x1, x2) - x
            if abs(error) < 1e-7 { return curve(s, y1, y2) }
            let d = slope(s, x1, x2)
            if abs(d) < 1e-6 { break }
            s = min(1, max(0, s - error / d))
        }
        var low = 0.0, high = 1.0
        s = x
        for _ in 0..<40 {
            let value = curve(s, x1, x2)
            if abs(value - x) < 1e-7 { break }
            if value < x { low = s } else { high = s }
            s = (low + high) / 2
        }
        return curve(s, y1, y2)
    }
}
