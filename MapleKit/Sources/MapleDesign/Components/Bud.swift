import SwiftUI

/// A closed leaf bud: two overlapping teardrop scales whose tips lean together (spec §5.8, §7.3).
///
/// Draw the parts separately to light them differently, or to open the bud in the reveal (each scale turns
/// about its own base, `BudShape.pivot(of:in:)`):
///
/// ```swift
/// BudShape(.back).fill(bark)
/// BudShape(.front).fill(bark)
/// BudShape(.whole).fill(budNeutral)   // a tree bud's silhouette
/// ```
nonisolated public struct BudShape: Shape {
    public enum Part: Sendable, Hashable, CaseIterable {
        /// Both scales.
        case whole
        /// The rear, left scale.
        case back
        /// The front, right scale, which overlaps the back one.
        case front
    }

    public var part: Part

    public init(_ part: Part = .whole) {
        self.part = part
    }

    public func path(in rect: CGRect) -> Path {
        switch part {
        case .whole:
            var path = Self.scale(.back, in: rect)
            path.addPath(Self.scale(.front, in: rect))
            return path
        case .back, .front:
            return Self.scale(part, in: rect)
        }
    }

    /// Where a scale meets the twig: the point it turns about when the bud opens.
    public static func pivot(of part: Part, in rect: CGRect) -> CGPoint {
        let layout = Layout(part)
        return CGPoint(x: rect.minX + layout.centreX * rect.width, y: rect.minY + layout.base * rect.height)
    }

    /// How each scale sits in the bud's rectangle, as fractions of it.
    private struct Layout {
        var centreX: CGFloat
        var width: CGFloat
        var top: CGFloat
        var base: CGFloat
        /// Clockwise lean in degrees, about the scale's base. The scales lean together, closing the bud.
        var lean: Double

        init(_ part: Part) {
            switch part {
            // The inner scale is taller and slimmer, so its tip shows above the outer one's: two scales,
            // not one drop.
            case .back, .whole:
                self.init(centreX: 0.36, width: 0.62, top: 0.0, base: 0.97, lean: 4)
            case .front:
                self.init(centreX: 0.60, width: 0.74, top: 0.11, base: 1.0, lean: -3)
            }
        }

        init(centreX: CGFloat, width: CGFloat, top: CGFloat, base: CGFloat, lean: Double) {
            self.centreX = centreX
            self.width = width
            self.top = top
            self.base = base
            self.lean = lean
        }
    }

    /// One teardrop scale: a pointed ogive tip, widest at about two thirds of its height, a round base.
    private static func scale(_ part: Part, in rect: CGRect) -> Path {
        let layout = Layout(part)
        let width = layout.width * rect.width
        let height = (layout.base - layout.top) * rect.height
        let centre = rect.minX + layout.centreX * rect.width
        let top = rect.minY + layout.top * rect.height
        let left = centre - width / 2, right = centre + width / 2
        let bottom = top + height

        var path = Path()
        path.move(to: CGPoint(x: centre, y: top))
        path.addCurve(
            to: CGPoint(x: right, y: top + 0.64 * height),
            control1: CGPoint(x: centre + 0.16 * width, y: top + 0.16 * height),
            control2: CGPoint(x: right, y: top + 0.38 * height)
        )
        path.addCurve(
            to: CGPoint(x: centre, y: bottom),
            control1: CGPoint(x: right, y: top + 0.90 * height),
            control2: CGPoint(x: centre + 0.30 * width, y: bottom)
        )
        path.addCurve(
            to: CGPoint(x: left, y: top + 0.64 * height),
            control1: CGPoint(x: centre - 0.30 * width, y: bottom),
            control2: CGPoint(x: left, y: top + 0.90 * height)
        )
        path.addCurve(
            to: CGPoint(x: centre, y: top),
            control1: CGPoint(x: left, y: top + 0.38 * height),
            control2: CGPoint(x: centre - 0.16 * width, y: top + 0.16 * height)
        )
        path.closeSubpath()

        let pivot = pivot(of: part, in: rect)
        let lean = CGAffineTransform(translationX: pivot.x, y: pivot.y)
            .rotated(by: layout.lean * .pi / 180)
            .translatedBy(x: -pivot.x, y: -pivot.y)
        return path.applying(lean)
    }
}

/// A leaf bud, drawn (never a symbol): bark-gradient scales lit from the moon side, with a thin `barkRim`.
///
/// - A bud that is still growing (`waiting: false`) swells from 0.4 to full size with `progress`, from its base.
/// - A waiting bud (earned, not yet opened) is full size and glows from its core in `reward` amber: the only
///   amber on a bud (D2). The glow breathes ±15% over `budPulsePeriod` (4s), or is `.still` where the spec asks
///   for a static glow (the next-leaf row, Herbarium tiles). Under Reduce Motion it never moves.
///
/// ```swift
/// BudGlyph(waiting: true, glow: .still).frame(width: 32, height: 32)   // next-leaf row
/// BudGlyph(waiting: true).frame(width: 96, height: 96)                // the reveal
/// ```
///
/// The glyph is decorative for VoiceOver; the row, tile or button holding it carries the label.
public struct BudGlyph: View {
    nonisolated public enum Glow: Sendable, Hashable {
        /// Breathes over `budPulsePeriod` (static under Reduce Motion).
        case breathing
        /// Held at its full strength.
        case still
    }

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let waiting: Bool
    private let progress: Double
    private let glow: Glow

    /// - Parameters:
    ///   - waiting: Earned and waiting to be opened: full size, with the amber core glow.
    ///   - progress: 0...1 toward the leaf, for a bud that is not waiting yet.
    public init(waiting: Bool, progress: Double = 1, glow: Glow = .breathing) {
        self.waiting = waiting
        self.progress = progress
        self.glow = glow
    }

    public var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let metrics = BudGlyphMetrics(side: side)
            ZStack(alignment: .topLeading) {
                if waiting {
                    coreGlow(metrics)
                }
                bud(metrics)
                    .scaleEffect(waiting ? 1 : Self.scale(forProgress: progress), anchor: UnitPoint(
                        x: metrics.anchor.x / max(side, 1), y: metrics.anchor.y / max(side, 1)
                    ))
            }
            .frame(width: side, height: side)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    /// The bud's size for its progress: 0.4 at the start, growing linearly to 1.0 when the leaf is earned.
    nonisolated public static func scale(forProgress progress: Double) -> Double {
        0.4 + 0.6 * ProgressHairline.clamped(progress)
    }

    /// The core glow's peak opacity for a bud `side` points tall: the full waiting-bud core (60%) at 48pt and
    /// below, easing to the reveal bud's 35% at 96pt.
    nonisolated public static func coreOpacity(side: CGFloat, cap: Double = 0.6) -> Double {
        let t = min(max((side - 48) / 48, 0), 1)
        return min(cap, 0.6 + (0.35 - 0.6) * t)
    }

    // MARK: Drawing

    private func bud(_ metrics: BudGlyphMetrics) -> some View {
        let scene = theme.colors.scene
        let bark = LinearGradient(colors: [scene.barkLight, scene.barkDark], startPoint: .leading, endPoint: .trailing)
        let backBark = LinearGradient(
            colors: [scene.barkLight.mix(with: scene.barkDark, by: 0.45), scene.barkDark],
            startPoint: .leading, endPoint: .trailing
        )
        // The rim catches the moon on the left edge only.
        let rim = LinearGradient(
            stops: [.init(color: scene.barkRim, location: 0), .init(color: scene.barkRim.opacity(0), location: 0.62)],
            startPoint: .leading, endPoint: .trailing
        )
        let rimWidth = max(0.5, min(0.75, metrics.side / 64))
        let rect = metrics.budRect
        return ZStack(alignment: .topLeading) {
            // A short, straight stub of twig under the bud.
            Path { path in
                path.move(to: CGPoint(x: rect.minX + rect.width * 0.52, y: rect.maxY - rect.height * 0.06))
                path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.52, y: metrics.stalkEnd))
            }
            .stroke(scene.barkLight, style: StrokeStyle(lineWidth: metrics.stalkWidth, lineCap: .round))

            scalePart(.back, in: rect, fill: backBark, rim: rim, rimWidth: rimWidth)
            if waiting {
                // The folded leaf's light falls on the inner scale, strongest at the seam.
                BudShape(.back)
                    .fill(innerLight(in: rect))
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
            }
            scalePart(.front, in: rect, fill: bark, rim: rim, rimWidth: rimWidth)
            if waiting {
                // And leaks out along the seam, the outer scale's inner edge.
                BudShape(.front)
                    .stroke(seam, lineWidth: rimWidth * 1.4)
                    .mask {
                        LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: UnitPoint(x: 0.6, y: 0.5))
                    }
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
            }
        }
    }

    /// Amber light on the inner scale, centred on the seam low in the bud.
    private func innerLight(in rect: CGRect) -> RadialGradient {
        let reward = theme.colors.reward
        return RadialGradient(
            stops: [
                .init(color: reward.opacity(0.42), location: 0),
                .init(color: reward.opacity(0.12), location: 0.55),
                .init(color: reward.opacity(0), location: 1),
            ],
            center: UnitPoint(x: 0.36, y: 0.62), startRadius: 0, endRadius: rect.height * 0.5
        )
    }

    /// The seam: the outer scale's left edge, warm low down and fading towards the tip and the right.
    private var seam: LinearGradient {
        let reward = theme.colors.reward
        return LinearGradient(
            stops: [
                .init(color: reward.opacity(0), location: 0.15),
                .init(color: reward.opacity(0.6), location: 0.55),
                .init(color: reward.opacity(0.6), location: 0.75),
                .init(color: reward.opacity(0), location: 0.95),
            ],
            startPoint: UnitPoint(x: 0.4, y: 0), endPoint: UnitPoint(x: 0.2, y: 1)
        )
    }

    private func scalePart(
        _ part: BudShape.Part, in rect: CGRect, fill: LinearGradient, rim: LinearGradient, rimWidth: CGFloat
    ) -> some View {
        BudShape(part)
            .fill(fill)
            .overlay { BudShape(part).stroke(rim, lineWidth: rimWidth) }
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
    }

    @ViewBuilder
    private func coreGlow(_ metrics: BudGlyphMetrics) -> some View {
        let peak = Self.coreOpacity(side: metrics.side, cap: theme.elevation.waitingBudCoreCap)
        let reward = theme.colors.reward
        let radius = metrics.glowRadius
        let halo = RadialGradient(
            stops: [
                .init(color: reward.opacity(peak), location: 0),
                .init(color: reward.opacity(peak * 0.55), location: 0.28),
                .init(color: reward.opacity(peak * 0.2), location: 0.6),
                .init(color: reward.opacity(0), location: 1),
            ],
            center: .center, startRadius: 0, endRadius: radius
        )
        let glowView = Circle()
            .fill(halo)
            .frame(width: radius * 2, height: radius * 2)
            .position(metrics.glowCentre)
            .allowsHitTesting(false)
        if glow == .breathing && !reduceMotion {
            // ±15% around 87% of the peak, so the breath never passes the 60% cap.
            glowView.phaseAnimator([1.0, 0.74]) { content, strength in
                content.opacity(strength)
            } animation: { _ in
                .easeInOut(duration: theme.motion.budPulsePeriod / 2)
            }
        } else {
            glowView
        }
    }
}

/// Where everything in a `BudGlyph` sits for a square of `side` points.
nonisolated struct BudGlyphMetrics {
    let side: CGFloat

    /// The two scales: 78% of the square tall, aspect about 0.64, leaving room for the stub below.
    var budRect: CGRect {
        let height = side * 0.78
        let width = height * 0.64
        return CGRect(x: (side - width) / 2, y: side * 0.06, width: width, height: height)
    }

    var stalkEnd: CGFloat { side * 0.9 }
    var stalkWidth: CGFloat { max(1, side * 0.035) }

    /// The bud grows from its base, where the stalk meets it.
    var anchor: CGPoint { CGPoint(x: budRect.midX, y: budRect.maxY) }

    /// The amber light sits low in the bud, where the leaf is folded.
    var glowCentre: CGPoint { CGPoint(x: budRect.midX, y: budRect.minY + budRect.height * 0.58) }
    var glowRadius: CGFloat { side * 0.62 }
}
