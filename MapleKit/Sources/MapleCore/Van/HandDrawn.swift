import Foundation

/// Outlines that look drawn by hand rather than ruled: the line wanders a little either side of the true edge, and the
/// ink thickens and thins along it (the owner, 28 Nov 2026: "the lines they are not perfect they feel like they have
/// been drawn they are a bit rough it gives a nice look"). Pure: the same seed always draws the same line, so nothing
/// shimmers from one frame to the next.
///
/// Every outline is closed: a list of points going round once, the last joining back to the first.
public enum HandDrawn {
    public struct Point: Sendable, Equatable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    /// Points round a box with rounded corners, `width` by `height` with its corner at the origin, about `step` apart,
    /// clockwise from the end of the top-left corner. A radius too big for the box makes a capsule.
    public static func roundedRect(width: Double, height: Double, radius: Double, step: Double) -> [Point] {
        guard width.isFinite, height.isFinite, radius.isFinite, step.isFinite, width > 0, height > 0, step > 0 else { return [] }
        let r = max(0, min(radius, width / 2, height / 2))
        let straightX = width - 2 * r
        let straightY = height - 2 * r
        let corner = Double.pi * r / 2
        let length = 2 * straightX + 2 * straightY + 4 * corner
        let count = max(8, Int((length / step).rounded()))
        return (0 ..< count).map { index in
            var s = length * Double(index) / Double(count)
            // Top, top-right corner, right, bottom-right, bottom, bottom-left, left, top-left.
            let pieces: [(Double, (Double) -> Point)] = [
                (straightX, { Point(x: r + $0, y: 0) }),
                (corner, { arc(width - r, r, r, -.pi / 2 + $0 / max(r, 1e-9)) }),
                (straightY, { Point(x: width, y: r + $0) }),
                (corner, { arc(width - r, height - r, r, $0 / max(r, 1e-9)) }),
                (straightX, { Point(x: width - r - $0, y: height) }),
                (corner, { arc(r, height - r, r, .pi / 2 + $0 / max(r, 1e-9)) }),
                (straightY, { Point(x: 0, y: height - r - $0) }),
                (corner, { arc(r, r, r, .pi + $0 / max(r, 1e-9)) }),
            ]
            for (piece, point) in pieces {
                if s <= piece { return point(s) }
                s -= piece
            }
            return Point(x: r, y: 0)
        }
    }

    /// Points round an ellipse filling a `width` by `height` box with its corner at the origin, about `step` apart.
    public static func ellipse(width: Double, height: Double, step: Double) -> [Point] {
        guard width.isFinite, height.isFinite, step.isFinite, width > 0, height > 0, step > 0 else { return [] }
        let a = width / 2
        let b = height / 2
        // Ramanujan's length of an ellipse.
        let length = Double.pi * (3 * (a + b) - ((3 * a + b) * (a + 3 * b)).squareRoot())
        let count = max(8, Int((length / step).rounded()))
        return (0 ..< count).map { index in
            let angle = 2 * Double.pi * Double(index) / Double(count) - .pi / 2
            return Point(x: a + a * cos(angle), y: b + b * sin(angle))
        }
    }

    /// The line drawn by a hand: each point pushed out or in along the outline's normal by a gentle wave, at most
    /// `wobble` from where it was. The wave goes round a whole number of times, so the line closes without a step.
    public static func wobbled(_ points: [Point], seed: Int, wobble: Double) -> [Point] {
        guard points.count >= 3, wobble.isFinite, wobble != 0 else { return points }
        let normals = Self.normals(points)
        let wave = Self.wave(points, seed: seed, salt: 0)
        return points.indices.map { index in
            let push = wobble * wave[index]
            return Point(x: points[index].x + push * normals[index].x, y: points[index].y + push * normals[index].y)
        }
    }

    /// The ink along a closed line: a ribbon `width` wide on average, thicker and thinner by up to `variation` of
    /// that along the way, with the line down its middle. Fill the space between `outer` and `inner`.
    public static func ink(_ points: [Point], seed: Int, width: Double, variation: Double) -> (outer: [Point], inner: [Point]) {
        guard points.count >= 3, width.isFinite, variation.isFinite else { return ([], []) }
        let normals = Self.normals(points)
        let wave = Self.wave(points, seed: seed, salt: 40)
        var outer: [Point] = []
        var inner: [Point] = []
        outer.reserveCapacity(points.count)
        inner.reserveCapacity(points.count)
        for index in points.indices {
            let half = width * (1 + variation * wave[index]) / 2
            let point = points[index]
            let normal = normals[index]
            outer.append(Point(x: point.x + half * normal.x, y: point.y + half * normal.y))
            inner.append(Point(x: point.x - half * normal.x, y: point.y - half * normal.y))
        }
        return (outer, inner)
    }

    // MARK: Helpers

    private static func arc(_ cx: Double, _ cy: Double, _ r: Double, _ angle: Double) -> Point {
        Point(x: cx + r * cos(angle), y: cy + r * sin(angle))
    }

    /// Each point's outward normal (for a clockwise outline on a screen, whose y grows downward), from its
    /// neighbours.
    private static func normals(_ points: [Point]) -> [Point] {
        let count = points.count
        return points.indices.map { index in
            let before = points[(index + count - 1) % count]
            let after = points[(index + 1) % count]
            let dx = after.x - before.x
            let dy = after.y - before.y
            let length = max(1e-9, hypot(dx, dy))
            return Point(x: dy / length, y: -dx / length)
        }
    }

    /// A smooth wave round the closed line, between -1 and 1: one long swell about every 90 points of its length, and
    /// two smaller ripples on it.
    private static func wave(_ points: [Point], seed: Int, salt: Int) -> [Double] {
        let count = points.count
        var length = 0.0
        for index in points.indices {
            let next = points[(index + 1) % count]
            length += hypot(next.x - points[index].x, next.y - points[index].y)
        }
        let cycles = max(2, Int((length / 90).rounded()))
        let parts: [(cycles: Int, size: Double)] = [(cycles, 0.65), (2 * cycles, 0.25), (3 * cycles, 0.1)]
        let phases = parts.indices.map { FallingLeaves.unit(seed, $0 + salt, 77) * 2 * Double.pi }
        return (0 ..< count).map { index in
            let u = Double(index) / Double(count)
            return parts.indices.reduce(0) { sum, part in
                sum + parts[part].size * sin(2 * Double.pi * Double(parts[part].cycles) * u + phases[part])
            }
        }
    }
}
