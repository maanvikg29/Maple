import Foundation
import MapleCore
import SwiftUI

/// One moment of the finish (F1 design §4.6), as plain numbers: what the dial, its centre and the lines under it
/// draw `t` seconds after the finish begins.
nonisolated public struct FinishFrame: Sendable, Equatable {
    /// Gold when the session counted something; white when it counted nothing (F1-18).
    public enum Tone: Sendable, Equatable {
        case gold
        case white
    }

    public var tone: Tone
    /// Per mark, 0…1: how strongly the sweep shows over it. Marks that didn't count stay 0 in a gold finish.
    public var sweep: [Double]
    /// 0…1: the opened leaf growing into the centre (`DialCentre.grown(_:)`); 0 when no leaf opened.
    public var leafGrow: Double
    /// The leaf's glow pulsing once: its scale (1 → 1.25 → 1) and strength (1, dipping to 0.75, back to 1).
    public var glowScale: Double
    public var glowOpacity: Double
    /// The ring rippling out from the marks: its scale of the dial (0.55 → 1.3) and its opacity (0.7 → 0).
    public var rippleScale: Double
    public var rippleOpacity: Double
    /// The receipt's numeral fading in, rising this many points into place.
    public var numeralOpacity: Double
    public var numeralRise: Double
    /// The leaf line, then Done and Again, fading in from below (points still to rise).
    public var lineOpacity: Double
    public var lineRise: Double
    public var actionsOpacity: Double
    public var actionsRise: Double
}

/// The finish as a pure function of time (F1 design §4.6). It plays once, when the session ends, and only if the
/// member sees it within 10 minutes (`ReceiptModel.ending`).
/// - The counted marks sweep gold one after another, 14 ms apart and 0.9 s each: each rises to full in its first
///   quarter and fades back to the receipt's mark. Marks that didn't count stay gaps. A session that counted
///   nothing sweeps every mark white.
/// - An opened leaf grows into the centre over 0.8 s, with an ease-out and no overshoot.
/// - The leaf's glow pulses once, and a ring ripples out from the marks (1.5 s from 0.15 s).
/// - The numeral starts fading in at once, the leaf line at 0.4 s, and Done and Again at 0.6 s, each over 0.6 s
///   with `gentle`'s ease-in-out, rising into place as they fade.
/// - A soft impact haptic plays at `hapticTime`.
///
/// Under Reduce Motion there is no sweep, ripple, pulse or rise. The leaf is at its final size at once, and the
/// words cross-fade in on the same timings.
///
/// ```swift
/// TimelineView(.animation(minimumInterval: 1 / 30, paused: elapsed > FinishTimeline.settledTime(markCount: n, reduceMotion: rm))) { context in
///     let finish = FinishTimeline.frame(at: context.date.timeIntervalSince(shownAt), counted: dial.gold,
///                                       leafOpened: dial.fill.opened > 0, reduceMotion: rm)
///     MinuteDial(frame: dial, diameter: d, theme: theme) { DialCentre(…).finishing(finish) }
///         .finishing(finish)
/// }
/// ```
/// Pass `DialFrame.receipt(…).gold` as `counted`. It is all false when the receipt isn't gold, and that makes the
/// finish white. A still frame (`-MapleDemoFinishAt`, or a finish seen too late to play) is `frame(at:)` at that
/// time, or at `settledTime(markCount:reduceMotion:)`.
nonisolated public enum FinishTimeline {
    public static let sweepStagger: TimeInterval = 0.014
    public static let sweepDuration: TimeInterval = 0.9
    /// Where in its 0.9 s each mark's sweep is at full strength.
    public static let sweepPeak = 0.25
    /// The sweep's stroke on the dial's 200-unit box, along each mark's own length.
    public static let sweepStroke = 2.6
    public static let leafGrowDuration: TimeInterval = 0.8
    public static let rippleStart: TimeInterval = 0.15
    public static let rippleDuration: TimeInterval = 1.5
    public static let glowStart: TimeInterval = 0.1
    public static let glowDuration: TimeInterval = 1.6
    public static let lineStart: TimeInterval = 0.4
    public static let actionsStart: TimeInterval = 0.6
    /// Every fade-in lasts this long: nothing moves faster than `gentle` except press feedback (spec §1).
    public static let fadeDuration: TimeInterval = 0.6
    /// When the soft impact haptic plays: as the ring sets off.
    public static let hapticTime: TimeInterval = 0.15

    /// Gold when any mark counted, white when none did.
    public static func tone(counted: [Bool]) -> FinishFrame.Tone {
        counted.contains(true) ? .gold : .white
    }

    /// When everything has come to rest for a dial of `markCount` marks: nothing moves after this.
    public static func settledTime(markCount: Int, reduceMotion: Bool) -> TimeInterval {
        if reduceMotion { return actionsStart + fadeDuration }
        let sweep = Double(max(0, markCount - 1)) * sweepStagger + sweepDuration
        return max(sweep, rippleStart + rippleDuration, glowStart + glowDuration, leafGrowDuration, actionsStart + fadeDuration)
    }

    /// The finish `t` seconds in. Times before 0 are the first frame; NaN and times past the end are the last.
    /// - Parameters:
    ///   - counted: One entry per mark: whether it counted (`DialFrame.gold`).
    ///   - leafOpened: A leaf opened in this session, so it grows into the centre.
    public static func frame(at t: Double, counted: [Bool], leafOpened: Bool, reduceMotion: Bool) -> FinishFrame {
        let time = t.isNaN ? .infinity : t
        let tone = tone(counted: counted)
        let sweeping = tone == .white ? counted.map { _ in true } : counted
        let sweep: [Double] = sweeping.enumerated().map { index, sweeps in
            reduceMotion || !sweeps ? 0 : sweepOpacity(time - Double(index) * sweepStagger)
        }
        let grow: Double
        if !leafOpened || time < 0 {
            grow = 0
        } else {
            grow = reduceMotion ? 1 : easeOut(progress(time, from: 0, to: leafGrowDuration))
        }
        let pulse = reduceMotion
            ? (scale: 1.0, opacity: 1.0)
            : glow(progress(time, from: glowStart, to: glowStart + glowDuration))
        let ripple = easeOut(progress(time, from: rippleStart, to: rippleStart + rippleDuration))
        let rippling = !reduceMotion && time >= rippleStart && time < rippleStart + rippleDuration
        let numeral = fadeIn(progress(time, from: 0, to: fadeDuration))
        let line = fadeIn(progress(time, from: lineStart, to: lineStart + fadeDuration))
        let actions = fadeIn(progress(time, from: actionsStart, to: actionsStart + fadeDuration))
        let rise = reduceMotion ? 0.0 : 1.0
        return FinishFrame(
            tone: tone, sweep: sweep, leafGrow: grow, glowScale: pulse.scale, glowOpacity: pulse.opacity,
            rippleScale: 0.55 + 0.75 * ripple, rippleOpacity: rippling ? 0.7 * (1 - ripple) : 0,
            numeralOpacity: numeral, numeralRise: 8 * (1 - numeral) * rise,
            lineOpacity: line, lineRise: 10 * (1 - line) * rise,
            actionsOpacity: actions, actionsRise: 10 * (1 - actions) * rise
        )
    }

    // MARK: Curves

    /// The finish's ease-out, `cubic-bezier(0.2, 0.8, 0.2, 1)`: quick to start, settling gently, never past 1.
    static func easeOut(_ x: Double) -> Double {
        RevealEasing.cubicBezier(x, 0.2, 0.8, 0.2, 1)
    }

    /// The fade-ins' curve, and their rises': `easeInOut`, the shape of the 0.6 s `gentle` token, so each fade is
    /// seen across its whole 0.6 s (spec §1, F1 design §4.6). The ease-out above is two-thirds in by 0.12 s.
    static func fadeIn(_ x: Double) -> Double {
        RevealEasing.easeInOut(x)
    }

    /// One mark's sweep `local` seconds after it starts: up to full in the first quarter, back to nothing by 0.9 s.
    static func sweepOpacity(_ local: TimeInterval) -> Double {
        guard local > 0, local < sweepDuration else { return 0 }
        let peak = sweepDuration * sweepPeak
        if local < peak { return easeOut(local / peak) }
        return 1 - easeOut((local - peak) / (sweepDuration - peak))
    }

    /// The glow's pulse `through` (0…1) its 1.6 s: out to 1.25 by 45%, back by the end; its strength dips to 0.75
    /// at 70%.
    static func glow(_ through: Double) -> (scale: Double, opacity: Double) {
        guard through > 0, through < 1 else { return (1, 1) }
        let scale = through < 0.45
            ? 1 + 0.25 * RevealEasing.easeInOut(through / 0.45)
            : 1.25 - 0.25 * RevealEasing.easeInOut((through - 0.45) / 0.55)
        let opacity: Double
        if through < 0.45 {
            opacity = 1
        } else if through < 0.7 {
            opacity = 1 - 0.25 * RevealEasing.easeInOut((through - 0.45) / 0.25)
        } else {
            opacity = 0.75 + 0.25 * RevealEasing.easeInOut((through - 0.7) / 0.3)
        }
        return (scale, opacity)
    }

    /// 0…1 through the window `start…end`.
    static func progress(_ t: TimeInterval, from start: TimeInterval, to end: TimeInterval) -> Double {
        guard !t.isNaN else { return 1 }
        guard end > start else { return t >= end ? 1 : 0 }
        return min(1, max(0, (t - start) / (end - start)))
    }
}

// MARK: - Drawing

extension MinuteDial {
    /// The dial with the finish over its marks: each swept mark in gold (or white) at its strength, and the ring
    /// rippling out. Nil draws the dial as it is.
    public func finishing(_ finish: FinishFrame?) -> MinuteDial {
        var dial = self
        dial.finish = finish
        return dial
    }
}

extension DialCentre {
    /// The centre at a moment of the finish: the leaf growing in with its glow pulsing, and the numeral fading in.
    public func finishing(_ finish: FinishFrame) -> DialCentre {
        var centre = grown(finish.leafGrow)
        centre.glowScale = finish.glowScale
        centre.glowOpacity = finish.glowOpacity
        centre.numeralOpacity = finish.numeralOpacity
        centre.numeralRise = finish.numeralRise
        return centre
    }
}

/// The finish over the dial's marks (F1 design §4.6): every swept mark stroked again in the finish's tone at its
/// sweep strength, 2.6 units wide, and a 1.5pt ring at the dial's edge that scales out as it fades. Transform and
/// opacity only.
struct FinishLayer: View {
    let finish: FinishFrame
    let marks: [MarkState]
    let geometry: MinuteDialGeometry
    let theme: Theme

    var body: some View {
        let colour = finish.tone == .gold ? theme.dial.gold : theme.colors.textPrimary
        let style = StrokeStyle(lineWidth: CGFloat(FinishTimeline.sweepStroke) * geometry.scale, lineCap: .round)
        let strokes: [(path: Path, opacity: Double)] = marks.indices.compactMap { index in
            let opacity = index < finish.sweep.count ? finish.sweep[index] : 0
            guard opacity > 0 else { return nil }
            return (geometry.path(index: index, count: marks.count, state: marks[index]), opacity)
        }
        ZStack {
            Canvas { context, _ in
                for stroke in strokes {
                    var layer = context
                    layer.opacity = stroke.opacity
                    layer.stroke(stroke.path, with: .color(colour), style: style)
                }
            }
            Circle()
                .stroke(colour, lineWidth: 1.5)
                .scaleEffect(finish.rippleScale)
                .opacity(finish.rippleOpacity)
        }
        .frame(width: geometry.diameter, height: geometry.diameter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
