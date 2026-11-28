import Foundation

/// How the van's picture is being looked at: how far in, and moved how far from the middle (in points). Pure.
///
/// The picture fills the screen when `zoom` is 1. Pinching zooms about the fingers, dragging moves it, and letting go
/// brings it back inside its limits: never smaller than the screen, never more than `maxZoom`, never showing past
/// its own edge.
public struct VanView: Sendable, Equatable {
    public var zoom: Double
    public var x: Double
    public var y: Double

    public init(zoom: Double, x: Double, y: Double) {
        self.zoom = zoom
        self.x = x
        self.y = y
    }

    public static let fit = VanView(zoom: 1, x: 0, y: 0)
    public static let maxZoom = 3.0
    /// Below this the picture counts as not zoomed, and settles back to fit.
    private static let barely = 1.05
    /// How much of a pull past a limit shows while the fingers are down.
    private static let give = 1.0 / 3

    public var isFit: Bool { zoom < Self.barely }

    /// Zoomed by `factor` so the place under (aroundX, y) on a screen of that size stays under it.
    public func zoomed(by factor: Double, aroundX ax: Double, y ay: Double, width: Double, height: Double) -> VanView {
        guard factor.isFinite, factor > 0, zoom > 0, ax.isFinite, ay.isFinite else { return self }
        let next = min(10, max(0.2, zoom * factor))
        let ratio = next / zoom
        let fromX = ax - width / 2
        let fromY = ay - height / 2
        return VanView(zoom: next, x: fromX - (fromX - x) * ratio, y: fromY - (fromY - y) * ratio)
    }

    public func moved(byX dx: Double, y dy: Double) -> VanView {
        guard dx.isFinite, dy.isFinite else { return self }
        return VanView(zoom: zoom, x: x + dx, y: y + dy)
    }

    /// Where it comes to rest when the fingers lift.
    public func settled(width: Double, height: Double) -> VanView {
        let inside = min(Self.maxZoom, max(1, zoom))
        guard inside >= Self.barely, width > 0, height > 0 else { return .fit }
        let limitX = (inside - 1) * width / 2
        let limitY = (inside - 1) * height / 2
        return VanView(zoom: inside, x: min(limitX, max(-limitX, x)), y: min(limitY, max(-limitY, y)))
    }

    /// What is drawn while the fingers are down: past a limit it follows a third of the way, so the edge can be felt.
    public func shown(width: Double, height: Double) -> VanView {
        let inside = min(Self.maxZoom, max(1, zoom))
        let limitX = (inside - 1) * max(0, width) / 2
        let limitY = (inside - 1) * max(0, height) / 2
        func soft(_ value: Double, _ limit: Double) -> Double {
            if value > limit { return limit + (value - limit) * Self.give }
            if value < -limit { return -limit + (value + limit) * Self.give }
            return value
        }
        let shownZoom = zoom < 1 ? 1 - (1 - zoom) * 0.3 : zoom > Self.maxZoom ? Self.maxZoom + (zoom - Self.maxZoom) * 0.3 : zoom
        return VanView(zoom: shownZoom, x: soft(x, limitX), y: soft(y, limitY))
    }
}

/// What a tap on home's picture does, by where it lands in the picture's own pixels.
public enum VanHomeTarget: Sendable, Equatable {
    /// The pot on the stove: cooks a leaf.
    case pot
    /// The boiler: the machines.
    case machines
    /// The van: the timer.
    case timer
    /// The maple: the tree and its leaves.
    case maple

    public static func at(x: Double, y: Double) -> VanHomeTarget? {
        guard x.isFinite, y.isFinite else { return nil }
        func within(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> Bool { x >= x0 && x <= x1 && y >= y0 && y <= y1 }
        // Small things first: the pot and the boiler stand inside the van.
        if within(659, 1130, 869, 1310) { return .pot }
        if within(895, 980, 1085, 1280) { return .machines }
        if within(180, 1060, 1580, 2060) { return .timer }
        if within(0, 110, 1000, 1010) { return .maple }
        return nil
    }
}
