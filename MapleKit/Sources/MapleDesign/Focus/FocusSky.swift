import MapleCore
import SwiftUI

/// The stars of the Focus tab's sky (F1-34): the same for everyone and on every launch, as Home's are.
nonisolated public enum FocusSkyField {
    public struct Star: Sendable, Equatable {
        /// 0…1 across and down the screen.
        public let x: Double
        public let y: Double
        /// Points.
        public let radius: Double
        public let opacity: Double
    }

    public static let count = 72
    public static let stars: [Star] = make()

    static func make() -> [Star] {
        var rng = SplitMix64(seed: 0xF0C5_5EED)
        var result: [Star] = []
        while result.count < count {
            let x = rng.unit(), y = rng.unit()
            // Never two in one spot.
            if result.contains(where: { hypot($0.x - x, ($0.y - y) * 2) < 0.06 }) { continue }
            // Most are faint; a few stand out.
            let level = pow(rng.unit(), 2.2)
            result.append(Star(x: x, y: y, radius: 0.4 + 0.9 * level, opacity: 0.12 + 0.48 * level))
        }
        return result
    }
}

/// The sky behind the Focus tab (F1-34): still stars over the background, and a low glow in the season's tint rising
/// from the foot of the screen, so a running session isn't a dial on an empty page. It is one still frame, drawn
/// once: a session can stay on screen for hours, and nothing here costs it a redraw.
///
/// ```swift
/// destination(route).background { FocusSky().ignoresSafeArea() }
/// ```
public struct FocusSky: View {
    @Environment(\.theme) private var theme
    @Environment(\.season) private var season

    public init() {}

    public var body: some View {
        let star = theme.colors.textPrimary
        let tint = theme.colors.seasonTint(season)
        let background = theme.colors.background
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(background))
            // The glow: widest at the foot, gone by two fifths of the way up.
            let centre = CGPoint(x: size.width / 2, y: size.height * 1.08)
            let radius = max(size.width, size.height * 0.5)
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: tint.opacity(0.34), location: 0),
                        .init(color: tint.opacity(0.13), location: 0.5),
                        .init(color: tint.opacity(0), location: 1),
                    ]),
                    center: centre, startRadius: 0, endRadius: radius
                )
            )
            for point in FocusSkyField.stars {
                let centre = CGPoint(x: point.x * size.width, y: point.y * size.height)
                let rect = CGRect(x: centre.x - point.radius, y: centre.y - point.radius, width: point.radius * 2, height: point.radius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(star.opacity(point.opacity)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
