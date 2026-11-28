import MapleCore
import SwiftUI

/// The van's hand-drawn line (`HandDrawn`): an outline that wanders a little and ink that thickens and thins, so a
/// button looks drawn rather than ruled (the owner, 28 Nov 2026: "the lines they are not perfect they feel like they
/// have been drawn"). Everything sits inside its frame, as `strokeBorder` did.
nonisolated struct VanInked: Shape {
    enum Outline {
        case roundedRect(radius: CGFloat)
        case ellipse
    }

    enum Part {
        /// The area inside the line, for the fill.
        case fill
        /// The ink itself: fill it with the outline colour, even-odd.
        case ink
    }

    var outline: Outline
    var part: Part
    /// The ink's width, on average.
    var lineWidth: CGFloat = 2.6
    /// How far the line wanders either side of the true edge, at most.
    var wobble: CGFloat = 1.1

    func path(in rect: CGRect) -> Path {
        let inset = lineWidth * 0.65 + wobble
        let box = rect.insetBy(dx: inset, dy: inset)
        guard box.width > 1, box.height > 1 else { return Path() }
        // The same box always draws the same line; boxes of other sizes are drawn a little differently.
        let seed = Int((box.width * 7 + box.height * 13).rounded())
        let base: [HandDrawn.Point] = switch outline {
        case .roundedRect(let radius):
            HandDrawn.roundedRect(width: box.width, height: box.height, radius: max(0, radius - inset), step: 3)
        case .ellipse:
            HandDrawn.ellipse(width: box.width, height: box.height, step: 3)
        }
        let line = HandDrawn.wobbled(base, seed: seed, wobble: wobble).map {
            HandDrawn.Point(x: $0.x + box.minX, y: $0.y + box.minY)
        }
        switch part {
        case .fill:
            return Self.closed(line)
        case .ink:
            let ink = HandDrawn.ink(line, seed: seed, width: lineWidth, variation: 0.35)
            var path = Self.closed(ink.outer)
            path.addPath(Self.closed(ink.inner))
            return path
        }
    }

    /// A smooth closed curve through the points: through the middle of each pair, bending at each point.
    private static func closed(_ points: [HandDrawn.Point]) -> Path {
        var path = Path()
        guard points.count >= 3 else { return path }
        func cg(_ point: HandDrawn.Point) -> CGPoint { CGPoint(x: point.x, y: point.y) }
        func middle(_ a: HandDrawn.Point, _ b: HandDrawn.Point) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        path.move(to: middle(points[points.count - 1], points[0]))
        for index in points.indices {
            path.addQuadCurve(to: middle(points[index], points[(index + 1) % points.count]), control: cg(points[index]))
        }
        path.closeSubpath()
        return path
    }
}

extension View {
    /// This view on a drawn shape: `fill` inside a hand-drawn outline in the picture's dark line.
    func vanInked(_ outline: VanInked.Outline, fill: some ShapeStyle, lineWidth: CGFloat = 2.6) -> some View {
        background(VanInked(outline: outline, part: .fill, lineWidth: lineWidth).fill(fill))
            .overlay(
                VanInked(outline: outline, part: .ink, lineWidth: lineWidth)
                    .fill(VanPalette.outline, style: FillStyle(eoFill: true))
                    .allowsHitTesting(false)
            )
    }
}
