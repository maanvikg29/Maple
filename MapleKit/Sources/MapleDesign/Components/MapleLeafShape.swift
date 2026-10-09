import SwiftUI

/// A stylised maple leaf: three main lobes, two lower lobes and a short stem.
/// Drawn from normalised points so it scales to any frame.
/// `nonisolated` because SwiftUI may ask a `Shape` for its path off the main actor.
nonisolated public struct MapleLeafShape: Shape {
    public init() {}

    /// The right half of the outline, from the top tip down to the stem (x ≥ 0.5, y grows downward).
    /// The left half is the mirror image.
    private static let rightHalf: [CGPoint] = [
        CGPoint(x: 0.500, y: 0.000),
        CGPoint(x: 0.575, y: 0.165),
        CGPoint(x: 0.655, y: 0.125),
        CGPoint(x: 0.625, y: 0.385),
        CGPoint(x: 0.790, y: 0.255),
        CGPoint(x: 0.830, y: 0.335),
        CGPoint(x: 1.000, y: 0.305),
        CGPoint(x: 0.925, y: 0.470),
        CGPoint(x: 0.965, y: 0.520),
        CGPoint(x: 0.720, y: 0.680),
        CGPoint(x: 0.760, y: 0.765),
        CGPoint(x: 0.545, y: 0.735),
        CGPoint(x: 0.530, y: 0.770),
        CGPoint(x: 0.520, y: 1.000),
    ]

    public func path(in rect: CGRect) -> Path {
        let mirrored = Self.rightHalf.reversed().map { CGPoint(x: 1 - $0.x, y: $0.y) }
        let outline = Self.rightHalf + mirrored.dropLast() // drop the duplicated top tip
        let side = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)

        var path = Path()
        for (index, point) in outline.enumerated() {
            let scaled = CGPoint(x: origin.x + point.x * side, y: origin.y + point.y * side)
            if index == 0 {
                path.move(to: scaled)
            } else {
                path.addLine(to: scaled)
            }
        }
        path.closeSubpath()
        return path
    }
}

/// A filled maple leaf with a soft inner highlight, used for rewards, the herbarium and the tree.
public struct LeafGlyph: View {
    private let color: Color
    private let size: CGFloat

    public init(color: Color, size: CGFloat = 28) {
        self.color = color
        self.size = size
    }

    public var body: some View {
        MapleLeafShape()
            .fill(
                LinearGradient(
                    colors: [color.opacity(0.95), color.opacity(0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                MapleLeafShape().stroke(Color.white.opacity(0.18), lineWidth: max(0.5, size / 60))
            }
            .shadow(color: color.opacity(0.25), radius: size / 6)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
