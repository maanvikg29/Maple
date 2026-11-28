import MapleCore
import SwiftUI

/// Pip on home's picture, one frame of him (`PipScene`).
///
/// The picture has him painted in. So that he can move, a patch of the van that was behind him lies over his place,
/// and he is drawn on that in his own pixels: his body, and his tail and one ear cut apart from it so they can
/// swing. Standing as `PipScene.rest` has him, the pieces lie exactly where the picture had them. The ladle hangs on
/// its knob unless he has it. Hearts, notes, z's and the rake are drawn; the leaves are the picture's own.
struct VanPipLayer: View {
    let scene: PipScene
    let canvas: VanCanvas
    let size: CGSize

    /// The square all of his pieces were cut to, in the picture's pixels (`HOME_BOX` in the art script).
    private static let box = (x: 940.0, y: 1310.0, side: 440.0)
    private static let leaves = ["VanLeafOrange", "VanLeafYellow", "VanLeafRed"]
    private static let leafWidths = [132.0, 112.0, 90.0]

    var body: some View {
        let pose = scene.pose
        ZStack {
            // What was behind him.
            sprite("VanHomeBehindPip", width: 320, height: 330, x: 1180, y: 1535)
            props(inFront: false)
            // His shadow stays on the ground, smaller the higher he is.
            let spread = pose.size * max(0.4, 1 - pose.lift / 500)
            Ellipse()
                .fill(VanPalette.outline.opacity(0.15 * pose.shadow))
                .frame(width: length(140 * spread), height: length(50 * spread))
                .position(at(pose.x + 5 * pose.size, pose.y - 8 * pose.size))
            if scene.ladleTurn == nil {
                piece("VanHomeLadle").position(at(boxMiddle.x, boxMiddle.y))
            }
            pip(pose)
            if let turn = scene.ladleTurn {
                // In his paw: it turns about where he holds the handle.
                piece("VanHomeLadle")
                    .rotationEffect(.radians(turn), anchor: unit(PipHome.standX + PipHome.pawX, PipHome.standY + PipHome.pawY))
                    .position(at(boxMiddle.x + pose.x - PipHome.standX, boxMiddle.y + pose.y - PipHome.standY - pose.lift))
            }
            if scene.inBasket {
                sprite("VanHomeBasketFront", width: 210, height: 208, x: 317, y: 1772)
            }
            props(inFront: true)
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func pip(_ pose: PipHomePose) -> some View {
        let facing = pose.facesLeft ? -1.0 : 1.0
        // What he turns about: his middle, wherever his size and facing have put it.
        let middle = unit(
            PipHome.standX + PipHome.middleX * pose.size * facing, PipHome.standY + PipHome.middleY * pose.size * pose.stretchY
        )
        return ZStack {
            piece("VanHomePipTail").rotationEffect(.radians(pose.tail), anchor: unit(1097, 1604))
            piece("VanHomePipEar").rotationEffect(.radians(pose.ear), anchor: unit(1205.4, 1419))
            piece("VanHomePip")
            if pose.asleep { piece("VanHomePipLids") }
        }
        .scaleEffect(
            x: pose.size * pose.stretchX * facing, y: pose.size * pose.stretchY, anchor: unit(PipHome.standX, PipHome.standY)
        )
        .rotationEffect(.radians(pose.turn), anchor: middle)
        .position(at(boxMiddle.x + pose.x - PipHome.standX, boxMiddle.y + pose.y - PipHome.standY - pose.lift))
    }

    private func props(inFront: Bool) -> some View {
        ForEach(Array(scene.props.enumerated()), id: \.offset) { _, prop in
            if prop.inFront == inFront { view(of: prop) }
        }
    }

    @ViewBuilder
    private func view(of prop: PipProp) -> some View {
        switch prop.kind {
        case .heart: held("VanPipHeart", width: 48, height: 44, prop)
        case .note: held("VanPipNote", width: 40, height: 52, prop)
        case .zed: held("VanPipZed", width: 36, height: 36, prop)
        case let .leaf(colour):
            let index = min(2, max(0, colour))
            Image(Self.leaves[index])
                .resizable()
                .scaledToFit()
                .frame(width: length(Self.leafWidths[index] * prop.size))
                .rotationEffect(.radians(prop.turn))
                .opacity(prop.opacity)
                .position(at(prop.x, prop.y))
        case .rake:
            // Held near the top of its handle: it swings about his paw.
            let grip = 45.0 / 300
            Image("VanPipRake")
                .resizable()
                .frame(width: length(120 * prop.size), height: length(300 * prop.size))
                .rotationEffect(.radians(prop.turn), anchor: UnitPoint(x: 0.5, y: grip))
                .opacity(prop.opacity)
                .position(at(prop.x, prop.y + 300 * prop.size * (0.5 - grip)))
        }
    }

    private func held(_ name: String, width: Double, height: Double, _ prop: PipProp) -> some View {
        Image(name)
            .resizable()
            .frame(width: length(width * prop.size), height: length(height * prop.size))
            .rotationEffect(.radians(prop.turn))
            .opacity(prop.opacity)
            .position(at(prop.x, prop.y))
    }

    // MARK: The picture's pixels

    private var boxMiddle: (x: Double, y: Double) {
        (Self.box.x + Self.box.side / 2, Self.box.y + Self.box.side / 2)
    }

    private func length(_ pixels: Double) -> CGFloat {
        pixels * canvas.scale(width: size.width, height: size.height)
    }

    private func at(_ x: Double, _ y: Double) -> CGPoint {
        canvas.point(x, y, in: size)
    }

    /// A place in the picture as a place in his pieces' square.
    private func unit(_ x: Double, _ y: Double) -> UnitPoint {
        UnitPoint(x: (x - Self.box.x) / Self.box.side, y: (y - Self.box.y) / Self.box.side)
    }

    /// One of his pieces, the size of their square.
    private func piece(_ name: String) -> some View {
        Image(name)
            .resizable()
            .frame(width: length(Self.box.side), height: length(Self.box.side))
    }

    private func sprite(_ name: String, width: Double, height: Double, x: Double, y: Double) -> some View {
        Image(name)
            .resizable()
            .frame(width: length(width), height: length(height))
            .position(at(x, y))
    }
}
