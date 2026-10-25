import MapleCore
import SwiftUI

/// The minute-marks dial (F1 design §4): the start screen, the running session, the break, holds and the receipt
/// are all this one object. It draws a `DialFrame` on a `Canvas` with the proportions of `DialLayout`'s 200-unit
/// box: marks clockwise from 12 o'clock, every 5th long, gaps shorter, the current mark thicker; the leaf dot just
/// outside the marks; and the bloom behind it, which reaches past the dial and is never clipped. The centre is the
/// caller's (usually a `DialCentre`).
///
/// ```swift
/// MinuteDial(frame: .preview(layout: layout, leafMinute: model.leafMinute, fill: fill), diameter: diameter, theme: theme) {
///     DialCentre(leaf: DialLeaf(species: leaf, fill: fill), numeral: DialCentre.numeralParts("50m"),
///                caption: "turn to set the length", diameter: diameter)
/// }
/// .dialTurning(minutes: $minutes, enabled: true)
/// ```
///
/// Its drawing is hidden from VoiceOver: the screen gives the dial its reading (§4.9).
public struct MinuteDial<Centre: View>: View {
    @Environment(\.season) private var season
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let frame: DialFrame
    private let diameter: CGFloat
    private let theme: Theme
    private let centre: Centre

    /// - Parameters:
    ///   - diameter: The dial's side in points: `MinuteDialMetrics.preferredDiameter(forWidth:)`, shrinking with
    ///     `HeroFit` down to `MinuteDialMetrics.minimumDiameter`. Never scaled with `scaleEffect`.
    ///   - theme: The screen's theme (`@Environment(\.theme)`): its `dial` colours, Increase Contrast included.
    public init(frame: DialFrame, diameter: CGFloat, theme: Theme, @ViewBuilder centre: () -> Centre) {
        self.frame = frame
        self.diameter = diameter
        self.theme = theme
        self.centre = centre()
    }

    public var body: some View {
        let geometry = MinuteDialGeometry(diameter: diameter)
        let tint = theme.colors.seasonTint(season)
        let fading = reduceMotion ? nil : frame.newestLit
        ZStack {
            ZStack {
                marks(geometry, tint: tint, skipping: fading)
                if let fading {
                    // The mark that has just lit fades in over 0.3 s (§4.6).
                    MarkShape(geometry: geometry, index: fading, count: frame.marks.count, state: .lit)
                        .stroke(theme.dial.lit, style: geometry.strokeStyle(for: .lit))
                        .id(fading)
                        .transition(.asymmetric(insertion: .opacity, removal: .identity))
                }
            }
            .opacity(frame.markOpacity)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: fading)
            .mapleAnimation(theme.motion.gentle, value: frame.markOpacity)
            .accessibilityHidden(true)
            if let dot = frame.dot {
                dotView(dot, geometry: geometry, tint: tint)
            }
            centre
        }
        .frame(width: diameter, height: diameter)
        .background {
            DialBloomLayer(bloom: frame.bloom, tint: tint, dial: theme.dial, side: diameter * MinuteDialMetrics.bloomScale)
                .opacity(frame.markOpacity)
                .mapleAnimation(theme.motion.gentle, value: frame.bloom)
                .mapleAnimation(theme.motion.gentle, value: frame.markOpacity)
        }
        .accessibilityElement(children: .contain)
    }

    /// Every mark but `skipping`, each stroked in its state's colour. Under Reduce Motion the current mark is drawn
    /// at its full tint, so the marks step once a minute.
    private func marks(_ geometry: MinuteDialGeometry, tint: Color, skipping: Int?) -> some View {
        let brightness = reduceMotion ? 1 : frame.currentBrightness
        let count = frame.marks.count
        let strokes: [(path: Path, colour: Color, style: StrokeStyle)] = frame.marks.enumerated().compactMap { index, state in
            guard index != skipping else { return nil }
            return (
                geometry.path(index: index, count: count, state: state),
                theme.dial.colour(for: state, tint: tint, brightness: brightness),
                geometry.strokeStyle(for: state)
            )
        }
        return Canvas { context, _ in
            for stroke in strokes {
                context.stroke(stroke.path, with: .color(stroke.colour), style: stroke.style)
            }
        }
        .frame(width: diameter, height: diameter)
    }

    /// The leaf dot: season tint, cross-fading to amber over 0.6 s when the leaf opens.
    private func dotView(_ dot: DialDot, geometry: MinuteDialGeometry, tint: Color) -> some View {
        let side = geometry.dotRadius * 2
        return ZStack {
            Circle().fill(tint).opacity(dot.reached ? 0 : 1)
            Circle().fill(theme.colors.reward).opacity(dot.reached ? 1 : 0)
        }
        .frame(width: side, height: side)
        .mapleAnimation(theme.motion.gentle, value: dot.reached)
        .position(geometry.dotCentre(angle: dot.angle))
        .accessibilityHidden(true)
    }
}

extension MinuteDial where Centre == EmptyView {
    /// The dial with nothing in its centre.
    public init(frame: DialFrame, diameter: CGFloat, theme: Theme) {
        self.init(frame: frame, diameter: diameter, theme: theme) { EmptyView() }
    }
}

/// The dial's sizes (F1 design §4.1).
nonisolated public enum MinuteDialMetrics {
    /// About 75% of the screen width: 295pt on a 393pt screen.
    public static func preferredDiameter(forWidth width: CGFloat) -> CGFloat {
        (width * 0.75).rounded()
    }

    /// `HeroFit` shrinks the dial no further than this.
    public static let minimumDiameter: CGFloat = 220
    /// The bloom behind the dial, as a multiple of its diameter (the mockup's 380 over 236).
    public static let bloomScale: CGFloat = 1.61
}

/// Where everything sits on a dial `diameter` points across: `DialLayout`'s 200-unit box, scaled.
nonisolated struct MinuteDialGeometry: Sendable, Equatable {
    let diameter: CGFloat

    /// Points per unit.
    var scale: CGFloat { diameter / CGFloat(DialLayout.box) }
    var centre: CGPoint { CGPoint(x: diameter / 2, y: diameter / 2) }

    /// The point `radius` units from the centre at `angle` radians clockwise from 12 o'clock (y points down).
    func point(angle: Double, radius: Double) -> CGPoint {
        let length = radius * Double(scale)
        return CGPoint(x: Double(centre.x) + length * sin(angle), y: Double(centre.y) - length * cos(angle))
    }

    /// Mark `index` of `count`: long marks run from radius 80, short ones from 84, gaps from 86, all out to 92.
    func segment(index: Int, count: Int, state: MarkState) -> (inner: CGPoint, outer: CGPoint) {
        let angle = 2 * Double.pi * Double(index) / Double(max(count, 1))
        let inner = state == .gap
            ? DialLayout.gapInnerRadius
            : index % 5 == 0 ? DialLayout.longInnerRadius : DialLayout.shortInnerRadius
        return (point(angle: angle, radius: inner), point(angle: angle, radius: DialLayout.outerRadius))
    }

    func path(index: Int, count: Int, state: MarkState) -> Path {
        let segment = segment(index: index, count: count, state: state)
        var path = Path()
        path.move(to: segment.inner)
        path.addLine(to: segment.outer)
        return path
    }

    /// 1.6 units with round caps, and 2.2 for the current mark.
    func strokeStyle(for state: MarkState) -> StrokeStyle {
        let width = state == .current ? DialLayout.currentStroke : DialLayout.stroke
        return StrokeStyle(lineWidth: CGFloat(width) * scale, lineCap: .round)
    }

    /// The leaf dot's radius: 2.6 units.
    var dotRadius: CGFloat { CGFloat(DialLayout.dotSize) * scale }

    /// The leaf dot's centre, 99 units out.
    func dotCentre(angle: Double) -> CGPoint {
        point(angle: angle, radius: DialLayout.dotRadius)
    }
}

/// One mark as a shape, for the mark that fades in as it lights.
nonisolated struct MarkShape: Shape {
    let geometry: MinuteDialGeometry
    let index: Int
    let count: Int
    let state: MarkState

    func path(in rect: CGRect) -> Path {
        geometry.path(index: index, count: count, state: state)
    }
}

/// The bloom behind the dial: season tint, gold and the cool rest colour, each a radial glow fading to clear at
/// its edge, at `bloom`'s strengths. Content light, never a container's glow (spec §6.5).
private struct DialBloomLayer: View {
    let bloom: DialBloom
    let tint: Color
    let dial: Theme.Dial
    let side: CGFloat

    var body: some View {
        ZStack {
            glow(tint.opacity(dial.bloom)).opacity(bloom.tint)
            glow(dial.goldBloom).opacity(bloom.gold)
            glow(dial.restBloom).opacity(bloom.cool)
        }
        .frame(width: side, height: side)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func glow(_ colour: Color) -> some View {
        Circle().fill(EllipticalGradient(
            colors: [colour, colour.opacity(0)], center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5
        ))
    }
}
