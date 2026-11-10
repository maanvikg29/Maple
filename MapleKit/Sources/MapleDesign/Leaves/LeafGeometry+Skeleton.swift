import CoreGraphics
import Foundation

nonisolated extension LeafGeometry {
    /// A leaf's lines placed and ready to copy to a surface that can't draw `LeafView` (the Live Activity's sketch,
    /// F1 design §5.11): each blade's outline, each vein as drawn (shortened to `Stroke.veinDrawnFraction`), the
    /// stalk sampled along its curve, and the catalogue's framing square. All in placed space, as `frame` is.
    public struct PlacedSkeleton: Sendable, Equatable {
        public var outlines: [[CGPoint]]
        public var veins: [[CGPoint]]
        public var stalk: [CGPoint]
        public var frame: CGRect
    }

    /// This leaf's skeleton, placed (offset and tilted) as `LeafView` draws it.
    public var placedSkeleton: PlacedSkeleton {
        let control = Self.petioleControl(petiole)
        let stalk = (0...6).map { step -> CGPoint in
            let t = CGFloat(step) / 6
            let (a, b, c) = ((1 - t) * (1 - t), 2 * (1 - t) * t, t * t)
            return CGPoint(
                x: a * petiole.start.x + b * control.x + c * petiole.end.x,
                y: a * petiole.start.y + b * control.y + c * petiole.end.y
            )
        }
        return PlacedSkeleton(
            outlines: outlines.map { outline in outline.map { $0.applying(placement) } },
            veins: veins.map { vein in [vein.start, Self.veinDrawnEnd(vein)].map { $0.applying(placement) } },
            stalk: stalk.map { $0.applying(placement) },
            frame: frame
        )
    }
}
