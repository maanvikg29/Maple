import MapleCore
import SwiftUI

/// The layers of one of the van's drawings, filling the space they are given. Every layer is drawn on the same
/// canvas, so they stack exactly. `motion` lets a caller move one layer (Pip's bob, the smoke's drift).
struct VanLayers<Moved: View>: View {
    let canvas: VanCanvas
    let names: [String]
    @ViewBuilder let motion: (String, Image) -> Moved

    var body: some View {
        GeometryReader { proxy in
            let scale = canvas.scale(width: proxy.size.width, height: proxy.size.height)
            ZStack {
                ForEach(names, id: \.self) { name in
                    motion(name, Image(name).resizable())
                        .frame(width: canvas.width * scale, height: canvas.height * scale)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .accessibilityHidden(true)
    }
}

extension VanCanvas {
    /// A point of the drawing, in a view of `size`.
    func point(_ x: Double, _ y: Double, in size: CGSize) -> CGPoint {
        let at = point(x: x, y: y, width: size.width, height: size.height)
        return CGPoint(x: at.x, y: at.y)
    }
}
