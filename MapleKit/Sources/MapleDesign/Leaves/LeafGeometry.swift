import CoreGraphics
import Foundation
import MapleCore
import SwiftUI
import Synchronization

/// The drawing of one species' leaf: a native port of `leafShapes()` in `Catalog/leaf-generator.js`,
/// the code that drew every leaf in the catalogue exports.
///
/// Coordinates are in the generator's *leaf space*: a -100...100 box, y pointing down, petiole pointing down.
/// `outlines`, `veins` and `petiole` are exactly what the generator returned, before the per-form vertical
/// offset and the species' resting tilt. The paths are *placed*: offset and tilted, as the exported SVGs
/// were (`rotate(tilt) translate(0 offset)`), so drawing a leaf only needs a scale and a translation.
///
/// Building a geometry samples a few hundred points (about 15 µs), so it is cached per species: use
/// `LeafGeometry.of(_:)`, which is thread-safe and cheap enough to call per leaf per frame, rather than `init`.
nonisolated public struct LeafGeometry: Sendable {
    /// A straight line in leaf space.
    public struct Segment: Sendable, Hashable {
        public var start: CGPoint
        public var end: CGPoint

        public init(start: CGPoint, end: CGPoint) {
            self.start = start
            self.end = end
        }
    }

    /// Stroke widths and vein styling of the original drawings, in leaf-space units.
    public enum Stroke {
        /// Blade outline (round joins).
        public static let outline: CGFloat = 0.8
        /// Each vein (butt caps), drawn at `veinOpacity`.
        public static let vein: CGFloat = 0.9
        /// The leaf stalk (round caps).
        public static let petiole: CGFloat = 2.4
        public static let veinOpacity: Double = 0.55
        /// Veins stop short of the edge: each is drawn over this fraction of its full length.
        public static let veinDrawnFraction: CGFloat = 0.86
    }

    // MARK: Generator output (leaf space, before offset and tilt)

    /// The species this geometry was built for.
    public let speciesID: String
    /// Closed outline of each blade in drawing order: one for simple leaves, one per leaflet for compound leaves.
    /// The last point joins back to the first.
    public let outlines: [[CGPoint]]
    /// Full-length veins, as the generator returned them. Palmate leaves have one per lobe, from the base to the tip.
    public let veins: [Segment]
    /// The stalk, drawn as a quadratic curve that bows 3 units to the right of `start`.
    public let petiole: Segment
    /// Vertical shift applied before the tilt (the generator's per-form `y`).
    public let verticalOffset: CGFloat
    /// The species' resting tilt in degrees, clockwise (y points down), as the generator drew it:
    /// `LeafSpecies.restingTiltDegrees` rounded to 0.1° (`rot.toFixed(1)` in the SVG transform).
    public let tiltDegrees: Double
    /// How far the blades reach along the leaf's axis, in leaf space (before offset and tilt): from the top
    /// (the tip, the smallest y) to the bottom (the stalk end, the largest y). Progress fills rise along it.
    public let bladeExtent: ClosedRange<CGFloat>

    // MARK: Placed, ready to draw

    /// Leaf space → placed space: `rotate(tilt) translate(0, verticalOffset)`, as in the SVG export.
    public let placement: CGAffineTransform
    /// One path per blade, placed, in drawing order (later blades overlap earlier ones).
    public let bladePaths: [Path]
    /// All blades in one path, for single-fill silhouettes (non-zero winding).
    public let silhouettePath: Path
    /// One path per vein, placed and already shortened to `Stroke.veinDrawnFraction`.
    public let veinPaths: [Path]
    /// The placed stalk curve (stroke it; it has no area).
    public let petiolePath: Path
    /// Tight bounds of the placed drawing, stroke widths included.
    public let bounds: CGRect
    /// The square each catalogue export used as its fitted `viewBox`, in placed space: the untilted drawing's
    /// bounding box, turned by the tilt, boxed again, then squared up at 1.12 × its longer side around the
    /// same centre. `LeafView` fits this square into its frame, so leaves sit exactly as in the catalogue.
    public let frame: CGRect

    /// Builds the geometry from the generator traits. Prefer the cached `LeafGeometry.of(_:)`.
    public init(species: LeafSpecies) {
        self.init(
            id: species.id,
            form: species.form,
            lobes: species.lobes,
            depth: species.depth,
            margin: species.margin,
            evergreen: species.evergreen
        )
    }

    init(id: String, form: LeafSpecies.Form, lobes: Int, depth: Double, margin: LeafSpecies.Margin, evergreen: Bool) {
        let marginLevel: Int = switch margin {
        case .smooth: 0
        case .toothed: 1
        case .doubleToothed: 2
        }
        let raw = LeafGenerator.shapes(
            id: id, form: form, lobes: lobes, depth: depth, margin: marginLevel, evergreen: evergreen
        )
        speciesID = id
        outlines = raw.outlines
        veins = raw.veins
        petiole = raw.petiole
        verticalOffset = raw.verticalOffset
        tiltDegrees = LeafGenerator.tiltDegrees(id: id)
        let bladeYs = raw.outlines.joined().map(\.y)
        bladeExtent = (bladeYs.min() ?? 0)...(bladeYs.max() ?? 0)

        let placement = CGAffineTransform(rotationAngle: tiltDegrees * .pi / 180)
            .translatedBy(x: 0, y: raw.verticalOffset)
        self.placement = placement

        let blades = raw.outlines.map { outline in
            Path { path in
                path.addLines(outline)
                path.closeSubpath()
            }
            .applying(placement)
        }
        bladePaths = blades
        silhouettePath = Path { path in
            for blade in blades {
                path.addPath(blade)
            }
        }
        veinPaths = raw.veins.map { vein in
            Path { path in
                path.move(to: vein.start)
                path.addLine(to: Self.veinDrawnEnd(vein))
            }
            .applying(placement)
        }
        let control = Self.petioleControl(raw.petiole)
        petiolePath = Path { path in
            path.move(to: raw.petiole.start)
            path.addQuadCurve(to: raw.petiole.end, control: control)
        }
        .applying(placement)

        // Tight bounds of the stroked drawing: a polygon stroked with round joins grows by half the width
        // around its vertices, the stalk has round caps, and veins sit inside the blades.
        let stalk = Self.sampleQuad(raw.petiole.start, control, raw.petiole.end, steps: 48)
        let drawnVeins = raw.veins.map { [$0.start, Self.veinDrawnEnd($0)] }
        var stroked = BoundingBox()
        for outline in raw.outlines {
            stroked.add(outline.map { $0.applying(placement) }, inflatedBy: Stroke.outline / 2)
        }
        stroked.add(stalk.map { $0.applying(placement) }, inflatedBy: Stroke.petiole / 2)
        for vein in drawnVeins {
            stroked.add(vein.map { $0.applying(placement) }, inflatedBy: Stroke.vein / 2)
        }
        bounds = stroked.rect

        // The export's framing (browser `getBBox()` of the tilted group): geometry only, no strokes,
        // boxed before the tilt, and that box's corners tilted and boxed again.
        let rotation = CGAffineTransform(rotationAngle: tiltDegrees * .pi / 180)
        let offset = CGAffineTransform(translationX: 0, y: raw.verticalOffset)
        var untilted = BoundingBox()
        for points in raw.outlines + [stalk] + drawnVeins {
            untilted.add(points.map { $0.applying(offset) }, inflatedBy: 0)
        }
        var tilted = BoundingBox()
        tilted.add(untilted.rect.corners.map { $0.applying(rotation) }, inflatedBy: 0)
        frame = Self.exportFrame(around: tilted.rect)
    }

    /// Where a vein's drawn stroke ends (`Stroke.veinDrawnFraction` of the way from start to end).
    static func veinDrawnEnd(_ vein: Segment) -> CGPoint {
        CGPoint(
            x: vein.start.x + (vein.end.x - vein.start.x) * Stroke.veinDrawnFraction,
            y: vein.start.y + (vein.end.y - vein.start.y) * Stroke.veinDrawnFraction
        )
    }

    /// The stalk's control point: 3 units right of its start, halfway down (`Q x0+3 (y0+y1)/2`).
    static func petioleControl(_ petiole: Segment) -> CGPoint {
        CGPoint(x: petiole.start.x + 3, y: (petiole.start.y + petiole.end.y) / 2)
    }

    /// A square centred on `box`, `exportFramePadding` × its longer side, as the exports' `viewBox`.
    static func exportFrame(around box: CGRect) -> CGRect {
        let side = max(box.width, box.height) * exportFramePadding
        return CGRect(x: box.midX - side / 2, y: box.midY - side / 2, width: side, height: side)
    }

    /// Measured from the 155 exported `viewBox`es: with it, every `frame` reproduces its export's viewBox
    /// within 0.15 units, the rounding of the export's 0.1-unit coordinates and viewBox numbers.
    static let exportFramePadding: CGFloat = 1.12

    private static func sampleQuad(_ p0: CGPoint, _ c: CGPoint, _ p1: CGPoint, steps: Int) -> [CGPoint] {
        [p0] + LeafGenerator.qpts(p0, c, p1, steps)
    }
}

// MARK: - Cache

nonisolated extension LeafGeometry {
    /// The geometry for a species, built once and then served from a process-wide cache (one small entry
    /// per species drawn). Safe to call from any thread, and cheap enough to call per leaf per frame.
    public static func of(_ species: LeafSpecies) -> LeafGeometry {
        let key = CacheKey(species)
        if let cached = cache.withLock({ $0[key] }) {
            return cached
        }
        let built = LeafGeometry(species: species)
        return cache.withLock { storage in
            if let raced = storage[key] {
                return raced
            }
            storage[key] = built
            return built
        }
    }

    /// Everything the drawing depends on, so an edited species never reuses a stale drawing.
    private struct CacheKey: Hashable, Sendable {
        let id: String
        let form: LeafSpecies.Form
        let lobes: Int
        let depth: Double
        let margin: LeafSpecies.Margin
        let evergreen: Bool

        init(_ species: LeafSpecies) {
            id = species.id
            form = species.form
            lobes = species.lobes
            depth = species.depth
            margin = species.margin
            evergreen = species.evergreen
        }
    }

    private static let cache = Mutex<[CacheKey: LeafGeometry]>([:])
}

// MARK: - Bounding box helper

nonisolated private struct BoundingBox {
    private var minX = CGFloat.infinity
    private var minY = CGFloat.infinity
    private var maxX = -CGFloat.infinity
    private var maxY = -CGFloat.infinity

    mutating func add(_ points: [CGPoint], inflatedBy inset: CGFloat) {
        for point in points {
            minX = min(minX, point.x - inset)
            minY = min(minY, point.y - inset)
            maxX = max(maxX, point.x + inset)
            maxY = max(maxY, point.y + inset)
        }
    }

    var rect: CGRect {
        guard minX <= maxX, minY <= maxY else { return .zero }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

nonisolated private extension CGRect {
    var corners: [CGPoint] {
        [CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: minY), CGPoint(x: maxX, y: maxY), CGPoint(x: minX, y: maxY)]
    }
}

// MARK: - The generator

/// Line-by-line port of `leaf-generator.js`. Names and constants follow the JavaScript so the two can be
/// read side by side; see the comments for each original function.
nonisolated enum LeafGenerator {
    struct Output {
        var outlines: [[CGPoint]]
        var veins: [LeafGeometry.Segment]
        var petiole: LeafGeometry.Segment
        var verticalOffset: CGFloat
    }

    typealias Segment = LeafGeometry.Segment

    /// `hash(s)`: 32-bit FNV-1a over the string, mapped to 0...1. JavaScript's `for (const c of s)` walks
    /// code points and `charCodeAt(0)` keeps the first UTF-16 unit of each, so this does the same.
    static func hash(_ string: String) -> Double {
        var hash: UInt32 = 2_166_136_261
        for scalar in string.unicodeScalars {
            let unit = scalar.value > 0xFFFF ? UInt32(UTF16.leadSurrogate(scalar)) : scalar.value
            hash ^= unit
            hash = hash &* 16_777_619
        }
        return Double(hash) / 4_294_967_295
    }

    /// `rot` in `leafSVG()`, rounded as the SVG transform printed it (`toFixed(1)`, halves away from zero).
    static func tiltDegrees(id: String) -> Double {
        let degrees = (hash(id + "r") - 0.5) * 16
        return (degrees * 10).rounded(.toNearestOrAwayFromZero) / 10
    }

    /// `pol(a, r)`: polar point, angle measured clockwise from straight up.
    static func pol(_ angle: Double, _ radius: Double) -> CGPoint {
        CGPoint(x: sin(angle) * radius, y: -cos(angle) * radius)
    }

    /// `qpts(p0, c, p1, n)`: `n` samples of a quadratic Bézier at t = 1/n ... 1 (p0 itself excluded).
    static func qpts(_ p0: CGPoint, _ c: CGPoint, _ p1: CGPoint, _ n: Int) -> [CGPoint] {
        (1...n).map { i in
            let t = Double(i) / Double(n), u = 1 - t
            return CGPoint(
                x: u * u * p0.x + 2 * u * t * c.x + t * t * p1.x,
                y: u * u * p0.y + 2 * u * t * c.y + t * t * p1.y
            )
        }
    }

    /// `cpts(p0, c1, c2, p1, n)`: `n` samples of a cubic Bézier at t = 1/n ... 1.
    static func cpts(_ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p1: CGPoint, _ n: Int) -> [CGPoint] {
        (1...n).map { i in
            let t = Double(i) / Double(n), u = 1 - t
            return CGPoint(
                x: u * u * u * p0.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * p1.x,
                y: u * u * u * p0.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * p1.y
            )
        }
    }

    /// `serrate(pts, cx, cy, amp, double, from)`: pushes every odd point (between `from` and 0.97 of the way
    /// along the edge) away from `centre` by `amp`, or `amp × 1.8` on every other tooth for double teeth.
    static func serrate(_ points: [CGPoint], centre: CGPoint, amp: Double, double: Bool, from: Double) -> [CGPoint] {
        let last = Double(points.count - 1)
        return points.enumerated().map { i, p in
            let t = Double(i) / last
            guard i % 2 == 1, t > from, t < 0.97 else { return p }
            let dx = p.x - centre.x, dy = p.y - centre.y
            let length = hypot(dx, dy)
            let d = length == 0 ? 1 : length
            let a = amp * (double && i % 4 == 1 ? 1.8 : 1)
            return CGPoint(x: p.x + dx / d * a, y: p.y + dy / d * a)
        }
    }

    /// `blade(bx, by, a, L, w, margin)`: one simple blade from `base`, pointing at angle `a`, length `L`,
    /// half-width `w`. Returns the closed outline and its midrib.
    static func blade(
        base: CGPoint, angle a: Double, length L: Double, halfWidth w: Double, margin: Int
    ) -> (outline: [CGPoint], vein: Segment) {
        let tip = CGPoint(x: base.x + sin(a) * L, y: base.y - cos(a) * L)
        let nx = cos(a), ny = sin(a) // perpendicular
        func along(_ f: Double) -> CGPoint {
            CGPoint(x: base.x + sin(a) * L * f, y: base.y - cos(a) * L * f)
        }
        let b0 = along(0.02)
        let near = along(0.15), far = along(0.7)
        let sideL = cpts(
            b0,
            CGPoint(x: near.x - nx * w * 1.1, y: near.y - ny * w * 1.1),
            CGPoint(x: far.x - nx * w * 0.9, y: far.y - ny * w * 0.9),
            tip, 26
        )
        let sideR = cpts(
            tip,
            CGPoint(x: far.x + nx * w * 0.9, y: far.y + ny * w * 0.9),
            CGPoint(x: near.x + nx * w * 1.1, y: near.y + ny * w * 1.1),
            b0, 26
        )
        var left = sideL, right = sideR
        if margin != 0 {
            let c = along(0.45)
            let amp = margin == 2 ? 2.2 : 1.4
            left = serrate(sideL, centre: c, amp: amp, double: margin == 2, from: 0.12)
            right = serrate(sideR, centre: c, amp: amp, double: margin == 2, from: 0.03)
        }
        return ([b0] + left + right, Segment(start: b0, end: tip))
    }

    /// `leafShapes(sp)`.
    static func shapes(
        id: String, form: LeafSpecies.Form, lobes: Int, depth: Double, margin: Int, evergreen: Bool
    ) -> Output {
        switch form {
        case .palmate where lobes >= 2:
            return palmate(lobes: lobes, depth: depth, margin: margin)
        case .palmate, .unlobed:
            // The generator has no single-lobed palmate leaf (its lobe spacing divides by n - 1);
            // a one-lobed palmate leaf is drawn as the unlobed leaf it effectively is.
            return unlobed(id: id, margin: margin, evergreen: evergreen)
        case .trifoliate:
            return trifoliate(margin: margin)
        case .palmcompound:
            return palmcompound(margin: margin)
        case .pinnate:
            return pinnate(margin: margin)
        }
    }

    private static func palmate(lobes n: Int, depth: Double, margin: Int) -> Output {
        let radius = 72.0
        let span: Double = [3: 1.25, 5: 1.95, 7: 2.3, 9: 2.55, 11: 2.7][n] ?? 2
        let angles = (0..<n).map { i in -span + 2 * span * Double(i) / Double(n - 1) }
        let lens = angles.map { a in radius * (0.62 + 0.38 * pow(cos(a * 0.55), 2)) * (n >= 7 ? 0.98 : 1) }
        let baseR = 6.0
        let gap = (2 * span) / Double(n - 1)
        func sinusR(_ i: Int) -> Double {
            min(lens[i], lens[i + 1]) * (1 - depth) * 0.92 + 4
        }
        func radiusOf(_ p: CGPoint) -> Double { hypot(p.x, p.y) }

        var veins: [Segment] = []
        let start = pol(.pi * 0.999, baseR * 0.4)
        // Edge before the first lobe: from the petiole notch out to the first sinus.
        let firstOuter = pol(angles[0] - gap * 0.55, max(lens[0] * (1 - depth) * 0.75, 14))
        var pts = [start]
        var prev = firstOuter
        pts += qpts(start, pol(angles[0] - gap * 0.7, lens[0] * 0.35), firstOuter, 8)
        for i in 0..<n {
            let a = angles[i], length = lens[i], tip = pol(a, length)
            let w = gap * (0.32 - 0.18 * depth)
            let shL = pol(a - w, radiusOf(prev) + (length - radiusOf(prev)) * 0.62)
            var edge = qpts(prev, shL, tip, 18)
            let nextS = i < n - 1
                ? pol((a + angles[i + 1]) / 2, sinusR(i))
                : pol(a + gap * 0.55, max(length * (1 - depth) * 0.75, 14))
            let shR = pol(a + w, radiusOf(nextS) + (length - radiusOf(nextS)) * 0.62)
            let smoothEdge2 = qpts(tip, shR, nextS, 18)
            var edge2 = smoothEdge2
            if margin != 0 {
                let c = pol(a, length * 0.35), amp = margin == 2 ? 2.6 : 1.7
                edge = serrate(edge, centre: c, amp: amp, double: margin == 2, from: 0.25)
                let toothed = serrate(smoothEdge2, centre: c, amp: amp, double: margin == 2, from: 0.0)
                // The last stretch into the sinus stays smooth.
                let last = Double(toothed.count - 1)
                edge2 = toothed.indices.map { j in Double(j) / last > 0.78 ? smoothEdge2[j] : toothed[j] }
            }
            pts += edge
            pts += edge2
            veins.append(Segment(start: .zero, end: tip))
            prev = nextS
        }
        let end = pol(-.pi * 0.999, baseR * 0.4)
        pts += qpts(prev, pol(angles[n - 1] + gap * 0.7, lens[n - 1] * 0.35), end, 8)
        return Output(
            outlines: [pts], veins: veins,
            petiole: Segment(start: .zero, end: CGPoint(x: 2, y: 30)), verticalOffset: -10
        )
    }

    private static func unlobed(id: String, margin: Int, evergreen: Bool) -> Output {
        let jitter = hash(id)
        let length = 118.0, w = evergreen ? 24 : 34 + jitter * 6
        let b = blade(base: CGPoint(x: 0, y: 48), angle: 0, length: length, halfWidth: w, margin: margin)
        var veins = [b.vein]
        // Side veins.
        for i in 1...5 {
            let y = 48 - length * 0.15 * Double(i)
            veins.append(Segment(start: CGPoint(x: 0, y: y), end: CGPoint(x: -w * 0.7, y: y - 14)))
            veins.append(Segment(start: CGPoint(x: 0, y: y), end: CGPoint(x: w * 0.7, y: y - 14)))
        }
        return Output(
            outlines: [b.outline], veins: veins,
            petiole: Segment(start: CGPoint(x: 0, y: 48), end: CGPoint(x: 2, y: 74)), verticalOffset: -6
        )
    }

    private static func trifoliate(margin: Int) -> Output {
        let base = CGPoint(x: 0, y: 30)
        let parts: [(angle: Double, length: Double, width: Double)] = [(0, 84, 26), (-1.05, 62, 20), (1.05, 62, 20)]
        var outlines: [[CGPoint]] = [], veins: [Segment] = []
        for part in parts {
            let b = blade(
                base: CGPoint(x: base.x + sin(part.angle) * 6, y: base.y - cos(part.angle) * 6),
                angle: part.angle, length: part.length, halfWidth: part.width, margin: margin
            )
            outlines.append(b.outline)
            veins.append(b.vein)
        }
        return Output(
            outlines: outlines, veins: veins,
            petiole: Segment(start: CGPoint(x: 0, y: 30), end: CGPoint(x: 2, y: 72)), verticalOffset: -8
        )
    }

    private static func palmcompound(margin: Int) -> Output {
        let base = CGPoint(x: 0, y: 34)
        var outlines: [[CGPoint]] = [], veins: [Segment] = []
        for (i, a) in [-1.35, -0.68, 0, 0.68, 1.35].enumerated() {
            let length: Double = i == 2 ? 88 : (i % 4 == 0 ? 62 : 78)
            let b = blade(base: base, angle: a, length: length, halfWidth: 11, margin: margin)
            outlines.append(b.outline)
            veins.append(b.vein)
        }
        return Output(
            outlines: outlines, veins: veins,
            petiole: Segment(start: CGPoint(x: 0, y: 34), end: CGPoint(x: 2, y: 74)), verticalOffset: -8
        )
    }

    private static func pinnate(margin: Int) -> Output {
        let top = -78.0, bottom = 50.0
        var veins = [Segment(start: CGPoint(x: 0, y: bottom), end: CGPoint(x: 0, y: top + 36))]
        let terminal = blade(base: CGPoint(x: 0, y: top + 38), angle: 0, length: 46, halfWidth: 15, margin: margin)
        var outlines = [terminal.outline]
        veins.append(terminal.vein)
        for (y, a) in [(-14.0, 1.25), (24.0, 1.3)] {
            for side in [-1.0, 1.0] {
                let b = blade(base: CGPoint(x: 0, y: y), angle: side * a, length: 48, halfWidth: 14, margin: margin)
                outlines.append(b.outline)
                veins.append(b.vein)
            }
        }
        return Output(
            outlines: outlines, veins: veins,
            petiole: Segment(start: CGPoint(x: 0, y: bottom - 8), end: CGPoint(x: 2, y: 80)), verticalOffset: -4
        )
    }
}
