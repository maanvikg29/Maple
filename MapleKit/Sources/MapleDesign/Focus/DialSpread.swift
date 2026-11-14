import MapleCore
import SwiftUI

/// How the start screen's marks follow the finger between lengths (F1-33). The ring is spaced for a number of marks
/// that moves continuously with the turn, so the marks close up or open out under the finger instead of jumping from
/// one length's ring to the next; the numeral and the haptic still step every 5 minutes. Pure, so it is tested as
/// values.
nonisolated public enum DialSpread {
    /// One mark to draw.
    struct Mark: Sendable, Equatable {
        /// Radians clockwise from 12 o'clock.
        let angle: Double
        /// 1, or less for the last mark while room is opening for it.
        let opacity: Double
        /// Which of the frame's marks gives it its state (the last one, for marks past the frame's own).
        let state: Int
        /// Its place round the ring: every 5th is long.
        let index: Int
    }

    /// The marks the ring is spaced for with the dial at `minutes` and the finger `fraction` of a step (-0.5…0.5)
    /// past it: the length's own marks at rest, and never past the shortest or the longest length.
    public static func marks(minutes: Int, fraction: Double) -> Double {
        let layout = DialLayout(plannedMinutes: minutes)
        let part = fraction.isFinite ? min(0.5, max(-0.5, fraction)) : 0
        let perMark = Double(layout.minutesPerMark)
        let turned = Double(layout.markCount) + part * Double(DialLayout.stepMinutes) / perMark
        let shortest = Double(DialLayout(plannedMinutes: DialLayout.minimumMinutes).markCount)
        let longest = Double(DialLayout(plannedMinutes: DialLayout.maximumMinutes).markCount)
        // Past the hour a ring holds fewer, longer marks, so the limits bound it only at the ends of the range.
        if minutes <= DialLayout.minimumMinutes { return max(shortest, turned) }
        if minutes >= DialLayout.maximumMinutes { return min(longest, turned) }
        return turned
    }

    /// The marks of a ring spaced for `spread`, drawn from a frame of `count` marks: evenly round it from 12 o'clock,
    /// the last fading in while `spread` is between two whole numbers.
    static func drawn(spread: Double, count: Int) -> [Mark] {
        guard spread.isFinite, spread > 0, count > 0 else { return [] }
        let whole = spread.rounded(.down)
        let part = spread - whole
        let total = Int(whole) + (part > 1e-9 ? 1 : 0)
        return (0..<total).map { index in
            Mark(
                angle: 2 * .pi * Double(index) / spread,
                opacity: index == total - 1 && part > 1e-9 ? part : 1,
                state: min(index, count - 1), index: index
            )
        }
    }

    /// Where a point at `angle` on a ring of `count` marks sits once the ring is spaced for `spread`: the leaf dot
    /// keeps its minute as the marks close up.
    static func angle(_ angle: Double, count: Int, spread: Double) -> Double {
        guard spread.isFinite, spread > 0, count > 0 else { return angle }
        return angle * Double(count) / spread
    }
}

/// The marks and the leaf dot of a ring spaced for `spread`. `spread` animates, so the ring glides to a new length
/// (a chip tap, the finger lifting) and follows the finger closely while it turns.
struct SpreadRing: View, Animatable {
    var spread: Double
    let frame: DialFrame
    let geometry: MinuteDialGeometry
    let theme: Theme
    let tint: Color

    var animatableData: Double {
        get { spread }
        set { spread = newValue }
    }

    var body: some View {
        let count = frame.marks.count
        let marks = DialSpread.drawn(spread: spread, count: count)
        let strokes: [(path: Path, colour: Color, style: StrokeStyle, opacity: Double)] = marks.map { mark in
            let state = frame.marks[mark.state]
            return (
                geometry.path(angle: mark.angle, index: mark.index, state: state),
                theme.dial.colour(for: state, tint: tint, brightness: 1),
                geometry.strokeStyle(for: state), mark.opacity
            )
        }
        // The dot is drawn with the marks, never placed as a view of its own: a placed view would glide in a straight
        // line to its new spot, off the ring, while the marks turn.
        let dot = frame.dot.map { dot in
            (centre: geometry.dotCentre(angle: DialSpread.angle(dot.angle, count: count, spread: spread)),
             colour: dot.reached ? theme.colors.reward : tint)
        }
        let dotRadius = geometry.dotRadius
        let markOpacity = frame.markOpacity
        // Room round the dial for the dot, which sits just outside the marks.
        let room = dotRadius * 2
        Canvas { context, _ in
            context.translateBy(x: room, y: room)
            for stroke in strokes {
                context.opacity = stroke.opacity * markOpacity
                context.stroke(stroke.path, with: .color(stroke.colour), style: stroke.style)
            }
            if let dot {
                context.opacity = 1
                let rect = CGRect(x: dot.centre.x - dotRadius, y: dot.centre.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(dot.colour))
            }
        }
        .frame(width: geometry.diameter + room * 2, height: geometry.diameter + room * 2)
        .accessibilityHidden(true)
    }
}
