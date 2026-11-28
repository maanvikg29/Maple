import MapleCore
import SwiftUI

extension VanCanvas {
    /// A point of the picture, in a view of `size`.
    func point(_ x: Double, _ y: Double, in size: CGSize) -> CGPoint {
        let at = point(x: x, y: y, width: size.width, height: size.height)
        return CGPoint(x: at.x, y: at.y)
    }
}
