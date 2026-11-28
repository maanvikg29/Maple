import MapleCore
import SwiftUI

/// The land round the maple while a session runs, and after it (`Scripts/art/concept/session_scene.py`): the drawn
/// backdrop (sky, hills, a row of autumn trees, a meadow running off every edge), clouds drifting slowly across the sky,
/// and the concept's maple in front of them.
struct VanTreeLandscape: View {
    let canvas: VanCanvas
    let size: CGSize
    /// Seconds since the scene appeared: the clouds drift with it.
    let time: Double

    /// The clouds: where each starts across the canvas, its height, how fast it drifts, and its picture's size.
    private static let clouds: [(x: Double, y: Double, speed: Double, width: Double, height: Double)] = [
        (640, 420, 9, 340, 170), (980, 880, 6.5, 260, 140), (420, 1130, 5, 210, 120),
    ]

    var body: some View {
        let scale = canvas.scale(width: size.width, height: size.height)
        ZStack {
            picture("VanTreeBackdrop", scale: scale)
            Canvas { context, size in
                let span = canvas.width + 800
                for (index, cloud) in Self.clouds.enumerated() {
                    // Rightward, slowly, coming back in on the left once past the right edge.
                    let travelled = (cloud.x + 400 + cloud.speed * time).truncatingRemainder(dividingBy: span) - 400
                    let corner = canvas.point(x: travelled - cloud.width / 2, y: cloud.y - cloud.height / 2, width: size.width, height: size.height)
                    context.draw(
                        Image("VanTreeCloud\(index)"),
                        in: CGRect(x: corner.x, y: corner.y, width: cloud.width * scale, height: cloud.height * scale)
                    )
                }
            }
            picture("VanTreeMaple", scale: scale)
        }
        .frame(width: size.width, height: size.height)
    }

    private func picture(_ name: String, scale: Double) -> some View {
        Image(name)
            .resizable()
            .frame(width: canvas.width * scale, height: canvas.height * scale)
            .position(x: size.width / 2, y: size.height / 2)
    }
}

/// Pip up in the maple with his wicker basket, collecting leaves (`PipBasket`): the basket fills as the session goes
/// on, a leaf comes down into it every few seconds, he leans to meet it, and the basket dips as it lands. Drawn in his
/// square, at his place on the tree's canvas.
struct VanTreePipCollecting: View {
    /// How far through the session, 0 to 1.
    let fraction: Double
    let time: Double
    /// Reduce Motion, or the screen dimmed: no catching, just Pip and his basket.
    let still: Bool
    let idle: PipHomePose
    let scale: Double

    private static let leaves = ["VanLeafOrange", "VanLeafYellow", "VanLeafRed"]
    /// The concept's three leaves' widths, in its pixels.
    private static let leafWidths = [132.0, 112.0, 90.0]
    /// The leaves heaped in the basket, in his square, in the order they come (`HEAP` in the art script, less
    /// `PIP_BOX`'s corner): x, y, turn in degrees, size, which leaf.
    private static let heap: [(x: Double, y: Double, turn: Double, size: Double, leaf: Int)] = [
        (460, 387, -24, 0.55, 0), (526, 385, 28, 0.55, 1), (494, 379, 6, 0.6, 2), (440, 371, -46, 0.58, 1),
        (548, 371, 50, 0.55, 0), (474, 359, -12, 0.64, 2), (516, 357, 22, 0.64, 0), (494, 343, 0, 0.7, 1),
    ]

    var body: some View {
        let width = VanTreePip.width * scale
        let height = VanTreePip.height * scale
        // His square's units to points.
        let unit = width / 610
        let now = still ? PipBasket.Catch.still : PipBasket.catching(at: time)
        let count = PipBasket.heap(fraction: fraction)
        ZStack {
            Group {
                Image("VanTreeBasketBack").resizable()
                Canvas { context, _ in
                    for spot in Self.heap.prefix(count) {
                        draw(context, leaf: spot.leaf, x: spot.x, y: spot.y, turn: .degrees(spot.turn), size: spot.size, unit: unit)
                    }
                }
            }
            .offset(y: now.dip * unit)
            // The leaf on its way down goes in behind the basket's front rim.
            if let leaf = now.leaf {
                Canvas { context, _ in
                    var falling = context
                    falling.opacity = leaf.opacity
                    let which = Int(time / PipBasket.period) % Self.leaves.count
                    draw(falling, leaf: which, x: leaf.x, y: leaf.y, turn: .radians(leaf.turn), size: 0.62, unit: unit)
                }
            }
            Image("VanTreeBasketFront").resizable().offset(y: now.dip * unit)
            Image("VanTreePipAlone").resizable()
            if idle.asleep {
                Image("VanTreePipLids").resizable()
            }
        }
        .frame(width: width, height: height)
        .scaleEffect(x: idle.stretchX, y: idle.stretchY, anchor: VanTreePip.feet)
        .rotationEffect(.radians(now.lean), anchor: VanTreePip.feet)
    }

    private func draw(_ context: GraphicsContext, leaf: Int, x: Double, y: Double, turn: Angle, size: Double, unit: Double) {
        var drawing = context
        let image = drawing.resolve(Image(Self.leaves[leaf]))
        let width = Self.leafWidths[leaf] * size * unit
        let height = width * image.size.height / max(1, image.size.width)
        drawing.translateBy(x: x * unit, y: y * unit)
        drawing.rotate(by: turn)
        drawing.draw(image, in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
    }
}
