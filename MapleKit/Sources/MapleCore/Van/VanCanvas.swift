import Foundation

/// One of the van's drawings, and where its points land on a screen (syrup van design §10). Pure.
///
/// Every layer of a view is drawn on the same canvas, so the layers stack without any layout. The canvas fills the
/// screen like a photo set to fill: scaled by whichever side needs more, centred, the rest cut off.
public struct VanCanvas: Sendable, Equatable {
    public let width: Double
    public let height: Double
    /// The canvas's left and top edges in the drawing's own units: the drawings keep their coordinates, and the canvas
    /// is a window onto them.
    public let originX: Double
    public let originY: Double

    public init(width: Double, height: Double, originX: Double, originY: Double) {
        self.width = width
        self.height = height
        self.originX = originX
        self.originY = originY
    }

    /// The home view: `Scripts/art/vanart/build.py`, `HOME_BOX`.
    public static let home = VanCanvas(width: 1600, height: 3460, originX: 0, originY: -1000)
    /// The workshop, the same room from the front: `Scripts/art/vanart/inside.py`, `BOX`.
    public static let workshop = VanCanvas(width: 852, height: 1846, originX: 0, originY: 0)

    public func scale(width screenWidth: Double, height screenHeight: Double) -> Double {
        guard width > 0, height > 0, screenWidth > 0, screenHeight > 0 else { return 0 }
        return max(screenWidth / width, screenHeight / height)
    }

    /// Where the drawing's point (x, y) is on a screen of that size.
    public func point(x: Double, y: Double, width screenWidth: Double, height screenHeight: Double) -> (x: Double, y: Double) {
        let scale = scale(width: screenWidth, height: screenHeight)
        guard scale > 0 else { return (0, 0) }
        return ((screenWidth - width * scale) / 2 + (x - originX) * scale, (screenHeight - height * scale) / 2 + (y - originY) * scale)
    }

    /// A length in the drawing's units, on that screen.
    public func length(_ value: Double, width screenWidth: Double, height screenHeight: Double) -> Double {
        value * scale(width: screenWidth, height: screenHeight)
    }
}
