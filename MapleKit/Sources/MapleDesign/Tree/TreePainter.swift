import MapleCore
import SwiftUI

/// The sway of each layer at one instant (spec §4.9), in radians about the trunk base.
nonisolated struct TreeSway: Sendable, Equatable {
    var trunk: Double = 0
    var twigs: Double = 0
    var leaves: Double = 0

    static let still = TreeSway()

    /// The layered sine sway at time `t`: 8 s (10 s at night) about the trunk base, ±0.6° / ±1.0° / ±1.4°,
    /// lagging 0.8 s and 1.2 s, scaled by vitality.
    static func at(_ t: Double, phase: NowPhase, vitality: Double) -> TreeSway {
        let period = phase == .night ? 10.0 : 8.0
        let amplitude = min(1, max(0.4, vitality)) * .pi / 180
        func wave(_ lag: Double) -> Double { sin(2 * .pi * (t - lag) / period) }
        return TreeSway(trunk: 0.6 * amplitude * wave(0), twigs: 1.0 * amplitude * wave(0.8), leaves: 1.4 * amplitude * wave(1.2))
    }
}

/// Draws the maple scene into a `GraphicsContext`. Pure functions of a plan, a frame and a time, callable from any
/// `Canvas` or `ImageRenderer`, so the still frame, the snapshot harness and the pre-rasterised layers all share
/// exactly the same drawing.
nonisolated enum TreePainter {
    // MARK: Layers

    /// Trunk and limbs (depth 1–3) or twigs (depth 4–8), rotated by `angle` about the trunk base.
    static func drawWood(_ plan: TreeScenePlan, depths: ClosedRange<Int>, frame: TreeSceneFrame, angle: Double, in context: GraphicsContext) {
        guard !plan.model.species.isEmpty else {
            if depths.contains(1) {
                drawSprout(plan, frame: frame, in: context)
            }
            return
        }
        var context = context
        rotate(&context, by: angle, about: frame.base)
        // Finer wood first, so every limb covers the base of the twigs growing from it.
        let branches = plan.skeleton.branches.filter { depths.contains($0.depth) }.sorted { $0.depth > $1.depth }
        for branch in branches {
            drawBranch(branch, plan: plan, frame: frame, in: context)
        }
        if depths.contains(1) {
            drawRoots(plan, frame: frame, in: context)
        }
    }

    /// Rosettes, flowers, halos and buds, rotated by `angle` about the trunk base. `flutter` gives each fluttering
    /// rosette's extra angle; pass nil to skip fluttering rosettes entirely (they are drawn per frame elsewhere).
    static func drawFoliage(
        _ plan: TreeScenePlan, frame: TreeSceneFrame, angle: Double, time: Double?, includeFluttering: Bool,
        includeWaitingBuds: Bool, now: Date, in context: GraphicsContext
    ) {
        guard !plan.model.species.isEmpty else {
            if includeWaitingBuds {
                drawSproutBud(plan, frame: frame, time: time, in: context)
            }
            return
        }
        var context = context
        rotate(&context, by: angle, about: frame.base)
        drawHalos(plan, frame: frame, now: now, in: context)
        context.drawLayer { layer in
            for index in plan.leafOrder {
                let leaf = plan.leaves[index]
                let rosette = plan.rosettes[leaf.rosette]
                if rosette.flutterPeriod != nil && !includeFluttering { continue }
                let extra = flutterAngle(rosette, time: time)
                drawLeaf(leaf, rosette: rosette, extraAngle: extra, plan: plan, frame: frame, in: layer)
            }
            shadeCanopy(plan, frame: frame, in: layer)
        }
        drawFlowers(plan, frame: frame, in: context)
        drawBuds(plan, frame: frame, time: time, waiting: includeWaitingBuds, neutral: true, in: context)
    }

    /// One rosette's leaves, lit as part of the crown, for its flutter sprite.
    static func drawRosette(_ plan: TreeScenePlan, index: Int, frame: TreeSceneFrame, in context: GraphicsContext) {
        let rosette = plan.rosettes[index]
        context.drawLayer { layer in
            for leaf in rosette.leaves where leaf < plan.leaves.count {
                drawLeaf(plan.leaves[leaf], rosette: rosette, extraAngle: 0, plan: plan, frame: frame, in: layer)
            }
            shadeCanopy(plan, frame: frame, in: layer)
        }
    }

    /// Only the fluttering rosettes, each turned by its own flutter at `time`.
    static func drawFlutter(_ plan: TreeScenePlan, frame: TreeSceneFrame, angle: Double, time: Double, in context: GraphicsContext) {
        var context = context
        rotate(&context, by: angle, about: frame.base)
        for index in plan.leafOrder {
            let leaf = plan.leaves[index]
            let rosette = plan.rosettes[leaf.rosette]
            guard rosette.flutterPeriod != nil else { continue }
            drawLeaf(leaf, rosette: rosette, extraAngle: flutterAngle(rosette, time: time), plan: plan, frame: frame, in: context)
        }
    }

    static func flutterAngle(_ rosette: TreeScenePlan.RosettePaint, time: Double?) -> Double {
        guard let time, let period = rosette.flutterPeriod else { return 0 }
        return 3 * .pi / 180 * sin(2 * .pi * time / period + rosette.flutterPhase)
    }

    private static func rotate(_ context: inout GraphicsContext, by angle: Double, about point: CGPoint) {
        guard angle != 0 else { return }
        context.translateBy(x: point.x, y: point.y)
        context.rotate(by: .radians(angle))
        context.translateBy(x: -point.x, y: -point.y)
    }

    // MARK: Bloom, ground, shadow

    static func drawBloom(_ plan: TreeScenePlan, frame: TreeSceneFrame, breathe: Double, in context: GraphicsContext) {
        guard plan.bloomOpacity > 0, !plan.model.species.isEmpty else { return }
        let centre = frame.point(plan.skeleton.crownCentroid)
        let radius = bloomRadius(plan, frame: frame)
        let opacity = min(0.18, plan.bloomOpacity * breathe)
        var context = context
        context.blendMode = .plusLighter
        let gradient = Gradient(stops: [
            .init(color: plan.bloomColor.opacity(opacity), location: 0),
            .init(color: plan.bloomColor.opacity(opacity * 0.5), location: 0.3),
            .init(color: plan.bloomColor.opacity(opacity * 0.15), location: 0.65),
            .init(color: plan.bloomColor.opacity(0), location: 1),
        ])
        let rect = CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: rect), with: .radialGradient(gradient, center: centre, startRadius: 0, endRadius: radius))
    }

    /// 0.75 × crown width (spec §4.4).
    static func bloomRadius(_ plan: TreeScenePlan, frame: TreeSceneFrame) -> CGFloat {
        0.75 * max(80, plan.skeleton.width) * frame.scale
    }

    static func drawGround(_ plan: TreeScenePlan, frame: TreeSceneFrame, in context: GraphicsContext) {
        let s = frame.scale
        let mound = CGRect(x: frame.scene(201 - 310, 0).x, y: frame.scene(0, 560 - 90).y, width: 620 * s, height: 180 * s)
        context.fill(Path(ellipseIn: mound), with: .color(plan.scene.ground))

        // The crest rim: brightest in the middle, gone at the sides.
        var rim = Path()
        rim.addArc(
            center: CGPoint(x: mound.midX, y: mound.midY), radius: 1, startAngle: .degrees(180), endAngle: .degrees(360),
            clockwise: false, transform: CGAffineTransform(translationX: mound.midX, y: mound.midY)
                .scaledBy(x: mound.width / 2, y: mound.height / 2).translatedBy(x: -mound.midX, y: -mound.midY)
        )
        let rimGradient = Gradient(stops: [
            .init(color: plan.scene.groundRim.opacity(0), location: 0.08),
            .init(color: plan.scene.groundRim, location: 0.5),
            .init(color: plan.scene.groundRim.opacity(0), location: 0.92),
        ])
        context.stroke(
            rim,
            with: .linearGradient(rimGradient, startPoint: CGPoint(x: mound.minX, y: 0), endPoint: CGPoint(x: mound.maxX, y: 0)),
            lineWidth: max(0.5, s)
        )

        // Light pool under the crown, in the bloom colour.
        if !plan.model.species.isEmpty {
            let poolCentre = frame.scene(201, 476)
            let poolWidth = 260 * s * (0.55 + 0.45 * plan.model.growth)
            drawEllipticalGlow(
                at: poolCentre, width: poolWidth, height: 40 * s, color: plan.bloomColor, opacity: 0.08, in: context
            )
        }

        // Contact shadow, sized to the trunk.
        let shadowWidth = 120 * s * (0.5 + 0.5 * min(1, plan.model.growth * 1.4 + 0.15))
        let shadowCentre = frame.scene(201, 472)
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 8 * s))
            layer.fill(
                Path(ellipseIn: CGRect(x: shadowCentre.x - shadowWidth / 2, y: shadowCentre.y - 7 * s, width: shadowWidth, height: 14 * s)),
                with: .color(plan.scene.contactShadow)
            )
        }
    }

    /// The scene dissolving into the background below the ground crest (spec §4.3: y 460–540).
    static func drawDissolve(frame: TreeSceneFrame, color: Color, in context: GraphicsContext) {
        let top = frame.scene(0, 460).y, bottom = frame.scene(0, 540).y
        let rect = CGRect(x: 0, y: top, width: frame.size.width, height: max(0, frame.size.height - top))
        let gradient = Gradient(stops: [
            .init(color: color.opacity(0), location: 0),
            .init(color: color, location: (bottom - top) / max(1, rect.height)),
            .init(color: color, location: 1),
        ])
        context.fill(Path(rect), with: .linearGradient(gradient, startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: rect.maxY)))
    }

    static func drawEllipticalGlow(at centre: CGPoint, width: CGFloat, height: CGFloat, color: Color, opacity: Double, angle: Double = 0, in context: GraphicsContext) {
        guard width > 0, height > 0 else { return }
        var context = context
        context.translateBy(x: centre.x, y: centre.y)
        context.rotate(by: .radians(angle))
        context.scaleBy(x: 1, y: height / width)
        let r = width / 2
        let gradient = Gradient(stops: [
            .init(color: color.opacity(opacity), location: 0),
            .init(color: color.opacity(opacity * 0.5), location: 0.45),
            .init(color: color.opacity(0), location: 1),
        ])
        context.fill(
            Path(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r)),
            with: .radialGradient(gradient, center: .zero, startRadius: 0, endRadius: r)
        )
    }

    // MARK: Wood

    private struct Sample {
        var point: CGPoint
        var width: CGFloat
        var tangent: CGVector
    }

    /// Catmull-Rom through the branch's nodes, a few samples per segment, widths interpolated.
    private static func samples(of branch: TreeSkeleton.Branch, frame: TreeSceneFrame) -> [Sample] {
        let points = branch.points.map(frame.point)
        let widths = branch.widths.map { CGFloat($0) * frame.scale }
        guard points.count >= 2 else { return [] }
        var result: [Sample] = []
        for i in 0..<(points.count - 1) {
            let p0 = points[max(0, i - 1)], p1 = points[i], p2 = points[i + 1], p3 = points[min(points.count - 1, i + 2)]
            let length = hypot(p2.x - p1.x, p2.y - p1.y)
            let steps = max(1, min(8, Int(length / (2.5 * max(frame.scale, 0.5)))))
            for k in 0..<steps {
                let t = CGFloat(k) / CGFloat(steps)
                let point = catmullRom(p0, p1, p2, p3, t)
                let width: CGFloat = widths[i] + (widths[i + 1] - widths[i]) * t
                result.append(Sample(point: point, width: width, tangent: .zero))
            }
        }
        result.append(Sample(point: points[points.count - 1], width: widths[widths.count - 1], tangent: .zero))
        for i in result.indices {
            let a = result[max(0, i - 1)].point, b = result[min(result.count - 1, i + 1)].point
            var dx = b.x - a.x, dy = b.y - a.y
            let l = hypot(dx, dy)
            if l > 1e-6 {
                dx /= l
                dy /= l
            } else {
                dx = 0
                dy = -1
            }
            result[i].tangent = CGVector(dx: dx, dy: dy)
        }
        return result
    }

    /// Uniform Catmull-Rom between p1 and p2 at t.
    private static func catmullRom(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ t: CGFloat) -> CGPoint {
        let t2: CGFloat = t * t
        let t3: CGFloat = t2 * t
        func axis(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) -> CGFloat {
            let linear: CGFloat = (c - a) * t
            let quadratic: CGFloat = (2 * a - 5 * b + 4 * c - d) * t2
            let cubic: CGFloat = (3 * b - a - 3 * c + d) * t3
            return 0.5 * (2 * b + linear + quadratic + cubic)
        }
        return CGPoint(x: axis(p0.x, p1.x, p2.x, p3.x), y: axis(p0.y, p1.y, p2.y, p3.y))
    }

    /// A closed, tapering ribbon along the samples with a rounded end.
    private static func ribbon(_ samples: [Sample], widthScale: CGFloat = 1, shift: (Sample) -> CGVector = { _ in .zero }, roundEnd: Bool = true) -> Path {
        var left: [CGPoint] = [], right: [CGPoint] = []
        for s in samples {
            let n = CGVector(dx: -s.tangent.dy, dy: s.tangent.dx)
            let h = s.width * widthScale / 2
            let o = shift(s)
            left.append(CGPoint(x: s.point.x + o.dx + n.dx * h, y: s.point.y + o.dy + n.dy * h))
            right.append(CGPoint(x: s.point.x + o.dx - n.dx * h, y: s.point.y + o.dy - n.dy * h))
        }
        var path = Path()
        guard let first = left.first, let last = samples.last else { return path }
        path.move(to: first)
        for p in left.dropFirst() { path.addLine(to: p) }
        if roundEnd {
            let o = shift(last)
            let h = last.width * widthScale / 2
            let end = CGPoint(x: last.point.x + o.dx + last.tangent.dx * h, y: last.point.y + o.dy + last.tangent.dy * h)
            path.addQuadCurve(to: end, control: CGPoint(x: left[left.count - 1].x + last.tangent.dx * h, y: left[left.count - 1].y + last.tangent.dy * h))
            path.addQuadCurve(to: right[right.count - 1], control: CGPoint(x: right[right.count - 1].x + last.tangent.dx * h, y: right[right.count - 1].y + last.tangent.dy * h))
        } else if let r = right.last {
            path.addLine(to: r)
        }
        for p in right.reversed().dropFirst() { path.addLine(to: p) }
        path.closeSubpath()
        return path
    }

    private static func drawBranch(_ branch: TreeSkeleton.Branch, plan: TreeScenePlan, frame: TreeSceneFrame, in context: GraphicsContext) {
        var samples = samples(of: branch, frame: frame)
        guard samples.count >= 2 else { return }
        let light = plan.sky.lightDirection
        let maxWidth = samples.map(\.width).max() ?? 0
        if branch.depth == 1 {
            // Flare the trunk into the ground.
            let base = samples[0].point
            let w0 = samples[0].width
            for i in samples.indices {
                let rise = hypot(samples[i].point.x - base.x, samples[i].point.y - base.y)
                samples[i].width *= 1 + 0.55 * exp(-rise / max(1, w0 * 0.75))
            }
        }
        // Twig ends taper to a point rather than stopping blunt.
        let n = samples.count
        for (offset, factor) in [(1, 0.35), (2, 0.62), (3, 0.85)] where n - offset > 0 {
            samples[n - offset].width *= factor
        }
        // Thin wood is lifted toward the tip colour so twigs read against the sky.
        let thinness = Double(min(1, max(0, (2.2 * frame.scale - maxWidth) / (1.8 * frame.scale))))
        let baseColor = thinness > 0 ? mix(plan.bark.dark, plan.bark.tip, thinness * 0.4) : plan.bark.dark
        context.fill(ribbon(samples), with: .color(baseColor))
        guard maxWidth >= 1.1 * frame.scale else { return }

        // The lit side: narrower bands shifted toward the light (fading where the limb points at it), stepped to
        // approximate a soft cylindrical gradient across the limb.
        let litTone = thinness > 0 ? mix(plan.bark.light, plan.bark.tip, thinness * 0.6) : plan.bark.light
        let bands: [(width: CGFloat, shift: CGFloat, amount: Double)] = maxWidth >= 3 * frame.scale
            ? [(0.7, 0.14, 0.4), (0.48, 0.26, 0.72), (0.26, 0.36, 1)]
            : [(0.46, 0.25, 0.8)]
        for band in bands {
            let path = ribbon(samples, widthScale: band.width) { s in
                let along = light.dx * s.tangent.dx + light.dy * s.tangent.dy
                return CGVector(dx: (light.dx - s.tangent.dx * along) * s.width * band.shift, dy: (light.dy - s.tangent.dy * along) * s.width * band.shift)
            }
            context.fill(path, with: .color(mix(baseColor, litTone, band.amount)))
        }

        // Moonlit rim along the light-facing edge of the trunk and limbs (no outlines anywhere).
        if branch.depth <= 3, maxWidth >= 2.2 * frame.scale {
            var rim = Path()
            var drawing = false
            for s in samples {
                let along = light.dx * s.tangent.dx + light.dy * s.tangent.dy
                var nx = light.dx - s.tangent.dx * along, ny = light.dy - s.tangent.dy * along
                let strength = hypot(nx, ny)
                guard strength > 0.35, s.width >= 1.8 * frame.scale else {
                    drawing = false
                    continue
                }
                nx /= strength
                ny /= strength
                let inset = min(0.45 * frame.scale, s.width * 0.2)
                let p = CGPoint(x: s.point.x + nx * (s.width / 2 - inset), y: s.point.y + ny * (s.width / 2 - inset))
                if drawing { rim.addLine(to: p) } else { rim.move(to: p) }
                drawing = true
            }
            context.stroke(rim, with: .color(plan.bark.rim), style: StrokeStyle(lineWidth: 0.75 * frame.scale, lineCap: .round, lineJoin: .round))

            // Winter: a line of snow along the top of the trunk and limbs where they run out sideways.
            if let snow = plan.bark.snow {
                var line = Path()
                var on = false
                for s in samples {
                    guard abs(s.tangent.dx) > 0.5 else {
                        on = false
                        continue
                    }
                    var nx = -s.tangent.dy, ny = s.tangent.dx
                    if ny > 0 {
                        nx = -nx
                        ny = -ny
                    }
                    let p = CGPoint(x: s.point.x + nx * s.width * 0.42, y: s.point.y + ny * s.width * 0.42)
                    if on { line.addLine(to: p) } else { line.move(to: p) }
                    on = true
                }
                context.stroke(line, with: .color(snow), style: StrokeStyle(lineWidth: frame.scale, lineCap: .round, lineJoin: .round))
            }
        }
    }

    /// Two small root flares sinking into the ground on either side of the trunk.
    private static func drawRoots(_ plan: TreeScenePlan, frame: TreeSceneFrame, in context: GraphicsContext) {
        let w = CGFloat(plan.skeleton.trunkBaseWidth) * frame.scale
        let base = frame.base
        var rng = SplitMix64(seed: SplitMix64.derive(plan.model.seed, "roots"))
        for side in [-1.0, 1.0] {
            let reach = w * CGFloat(rng.range(0.95, 1.35)) + 3 * frame.scale
            let rise = w * 0.75
            var root = Path()
            root.move(to: CGPoint(x: base.x + side * w * 0.2, y: base.y - rise))
            root.addQuadCurve(
                to: CGPoint(x: base.x + side * (w * 0.5 + reach), y: base.y + 2.5 * frame.scale),
                control: CGPoint(x: base.x + side * w * 0.62, y: base.y - w * 0.1)
            )
            root.addQuadCurve(
                to: CGPoint(x: base.x, y: base.y + 3 * frame.scale),
                control: CGPoint(x: base.x + side * w * 0.6, y: base.y + 3.5 * frame.scale)
            )
            root.closeSubpath()
            let litSide = (side > 0) == (plan.sky.lightDirection.dx > 0)
            context.fill(root, with: .color(litSide ? mix(plan.bark.dark, plan.bark.light, 0.55) : plan.bark.dark))
        }
    }

    // MARK: Leaves

    private static func leafTransform(_ leaf: TreeScenePlan.LeafPaint, scale leafScale: Double, rosette: TreeScenePlan.RosettePaint, extraAngle: Double, frame: TreeSceneFrame) -> CGAffineTransform {
        let geometry = leaf.geometry
        let stalkEnd = geometry.petiole.end.applying(geometry.placement)
        let k = leaf.size * leafScale * frame.scale / leaf.span
        var anchor = frame.point(leaf.anchor)
        if extraAngle != 0 {
            // Flutter turns the whole rosette about its twig end.
            let pivot = frame.point(rosette.anchor)
            let dx = anchor.x - pivot.x, dy = anchor.y - pivot.y
            let c = cos(extraAngle), s = sin(extraAngle)
            anchor = CGPoint(x: pivot.x + dx * c - dy * s, y: pivot.y + dx * s + dy * c)
        }
        return CGAffineTransform(translationX: anchor.x, y: anchor.y)
            .rotated(by: leaf.rotation + extraAngle)
            .scaledBy(x: k, y: k)
            .translatedBy(x: -stalkEnd.x, y: -stalkEnd.y)
    }

    private static func drawLeaf(_ leaf: TreeScenePlan.LeafPaint, rosette: TreeScenePlan.RosettePaint, extraAngle: Double, plan: TreeScenePlan, frame: TreeSceneFrame, in context: GraphicsContext) {
        let transform = leafTransform(leaf, scale: plan.leafScale, rosette: rosette, extraAngle: extraAngle, frame: frame)
        let pointSize = leaf.size * plan.leafScale
        LeafRenderer.draw(leaf.geometry, in: context, transform: transform, style: LeafStyle(fill: leaf.fill, vein: leaf.vein, detail: .fillOnly))
        if pointSize >= 14 {
            // Veins at a fixed hairline width so the larger leaves read as real specimens.
            let veins = leaf.geometry.veinPaths.reduce(into: Path()) { $0.addPath($1.applying(transform)) }
            context.stroke(veins, with: .color(leaf.vein.opacity(0.55)), lineWidth: 0.4 * frame.scale)
        }
        if leaf.frostRim > 0, pointSize >= 14 {
            context.stroke(
                leaf.geometry.silhouettePath.applying(transform),
                with: .color(.white.opacity(leaf.frostRim)),
                style: StrokeStyle(lineWidth: 0.75 * frame.scale, lineJoin: .round)
            )
        }
    }

    /// Light across the whole crown as one dome: a lift on the side facing the light and shade on the far side,
    /// applied only where leaves are (source-atop), so the canopy reads as a volume rather than a scatter.
    private static func shadeCanopy(_ plan: TreeScenePlan, frame: TreeSceneFrame, in context: GraphicsContext) {
        let skeleton = plan.skeleton
        guard !skeleton.leaves.isEmpty else { return }
        let centre = frame.point(skeleton.crownCentroid)
        let radius = max(60, skeleton.width * 0.55) * frame.scale
        let light = plan.sky.lightDirection
        var context = context
        context.blendMode = .sourceAtop
        let lit = CGPoint(x: centre.x + light.dx * radius, y: centre.y + light.dy * radius)
        let shade = CGPoint(x: centre.x - light.dx * radius, y: centre.y - light.dy * radius)
        let bounds = CGRect(origin: .zero, size: frame.size)
        context.fill(Path(bounds), with: .linearGradient(
            Gradient(stops: [
                .init(color: .white.opacity(0.10), location: 0),
                .init(color: .white.opacity(0), location: 0.42),
                .init(color: .black.opacity(0), location: 0.55),
                .init(color: .black.opacity(0.26), location: 1),
            ]),
            startPoint: lit, endPoint: shade
        ))
    }

    private static func drawFlowers(_ plan: TreeScenePlan, frame: TreeSceneFrame, in context: GraphicsContext) {
        guard !plan.flowerTips.isEmpty else { return }
        let r = 1 * frame.scale
        let color = Color.treeHex(0xB3312B, opacity: 0.7)
        for tip in plan.flowerTips {
            let p = frame.point(tip)
            context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(color))
        }
    }

    private static func drawHalos(_ plan: TreeScenePlan, frame: TreeSceneFrame, now: Date, in context: GraphicsContext) {
        for rosette in plan.rosettes {
            guard let placed = rosette.haloPlacedAt else { continue }
            let age = now.timeIntervalSince(placed)
            let strength = max(0, min(1, 1 - age / 86_400))
            guard strength > 0 else { continue }
            let centre = frame.point(rosette.anchor + rosette.direction * (plan.skeleton.leafSize * 0.45))
            let r = 16 * frame.scale
            context.fill(
                Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: 2 * r, height: 2 * r)),
                with: .radialGradient(
                    Gradient(colors: [plan.reward.opacity(0.30 * strength), plan.reward.opacity(0)]),
                    center: centre, startRadius: 0, endRadius: r
                )
            )
        }
    }

    // MARK: Buds

    /// A closed teardrop bud of two overlapping scales, base at the origin, pointing up (−y), `length` long.
    static func budPath(length: CGFloat, width: CGFloat) -> Path {
        var path = Path()
        path.move(to: .zero)
        path.addCurve(to: CGPoint(x: 0, y: -length), control1: CGPoint(x: -width * 0.75, y: -length * 0.2), control2: CGPoint(x: -width * 0.32, y: -length * 0.8))
        path.addCurve(to: .zero, control1: CGPoint(x: width * 0.32, y: -length * 0.8), control2: CGPoint(x: width * 0.75, y: -length * 0.2))
        path.closeSubpath()
        return path
    }

    static func drawBuds(_ plan: TreeScenePlan, frame: TreeSceneFrame, time: Double?, waiting: Bool, neutral: Bool, in context: GraphicsContext) {
        for bud in plan.skeleton.buds where bud.isWaiting ? waiting : neutral {
            drawBud(bud.anchor, direction: bud.direction, progress: bud.progress, isNext: bud.isNext, isWaiting: bud.isWaiting, plan: plan, frame: frame, time: time, in: context)
        }
    }

    static func drawBud(_ anchor: TreePoint, direction: TreePoint, progress: Double, isNext: Bool, isWaiting: Bool, plan: TreeScenePlan, frame: TreeSceneFrame, time: Double?, in context: GraphicsContext) {
        let s = frame.scale
        let swell = isWaiting ? 1 : 0.4 + 0.6 * min(1, max(0, progress))
        let length = 9 * s * swell * (isWaiting ? 1.1 : 1), width = 6 * s * swell * (isWaiting ? 1.1 : 1)
        let base = frame.point(anchor)
        let angle = direction.angleFromUp
        let centre = CGPoint(x: base.x + sin(angle) * length * 0.5, y: base.y - cos(angle) * length * 0.5)
        if isWaiting {
            // Amber core and halo, breathing ±15% over 4 s (static at rest under Reduce Motion).
            let breathe = time.map { 1 + 0.15 * sin(2 * .pi * $0 / 4) } ?? 1
            let r = 18 * s
            context.fill(
                Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: 2 * r, height: 2 * r)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: plan.reward.opacity(0.25 * breathe), location: 0),
                        .init(color: plan.reward.opacity(0.1 * breathe), location: 0.45),
                        .init(color: plan.reward.opacity(0), location: 1),
                    ]),
                    center: centre, startRadius: 0, endRadius: r
                )
            )
        } else if isNext {
            let r = 10 * s
            context.fill(
                Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: 2 * r, height: 2 * r)),
                with: .radialGradient(Gradient(colors: [plan.seasonTint.opacity(0.12), plan.seasonTint.opacity(0)]), center: centre, startRadius: 0, endRadius: r)
            )
        }
        var local = context
        local.translateBy(x: base.x, y: base.y)
        local.rotate(by: .radians(angle))
        // The back scale, a little turned, then the front scale.
        let back = budPath(length: length * 0.92, width: width * 0.9).applying(CGAffineTransform(rotationAngle: 0.22))
        let front = budPath(length: length, width: width)
        let body = isWaiting ? plan.reward.opacity(0.6) : plan.budNeutral
        local.fill(back, with: .color(isWaiting ? plan.reward.opacity(0.4) : plan.budNeutral.opacity(0.6)))
        local.fill(front, with: .color(body))
        local.stroke(front, with: .color(.white.opacity(isWaiting ? 0.28 : 0.2)), lineWidth: 0.5 * s)
        // A short stalk joins the bud to its twig.
        var stalk = Path()
        stalk.move(to: CGPoint(x: 0, y: 1.2 * s))
        stalk.addLine(to: .zero)
        local.stroke(stalk, with: .color(plan.bark.tip), lineWidth: 0.8 * s)
    }

    // MARK: Seed sprout (onboarding only)

    static func sproutTop(frame: TreeSceneFrame) -> (CGPoint, Double) {
        (frame.point(TreePoint(x: 2.5, y: 44)), 0.08)
    }

    private static func drawSprout(_ plan: TreeScenePlan, frame: TreeSceneFrame, in context: GraphicsContext) {
        let s = frame.scale
        let base = frame.base
        var stem = Path()
        stem.move(to: CGPoint(x: base.x - 0.8 * s, y: base.y))
        stem.addCurve(to: CGPoint(x: base.x + 2.5 * s, y: base.y - 44 * s), control1: CGPoint(x: base.x - 4 * s, y: base.y - 16 * s), control2: CGPoint(x: base.x + 5 * s, y: base.y - 28 * s))
        context.stroke(stem, with: .color(plan.bark.tip), style: StrokeStyle(lineWidth: 1.8 * s, lineCap: .round))
        // Two cotyledons, one each side, below the bud.
        let node = CGPoint(x: base.x + 1.6 * s, y: base.y - 30 * s)
        for (side, tilt) in [(-1.0, -1.05), (1.0, 0.95)] {
            var leaf = Path(ellipseIn: CGRect(x: -2.6 * s, y: -11 * s, width: 5.2 * s, height: 11 * s))
            leaf = leaf.applying(CGAffineTransform(rotationAngle: tilt)).applying(CGAffineTransform(translationX: node.x + side * 0.6 * s, y: node.y))
            context.fill(leaf, with: .color(plan.cotyledon))
        }
        if !plan.model.waiting.isEmpty { return }
        let (top, angle) = sproutTop(frame: frame)
        drawBud(frame.treePoint(top), direction: TreePoint.direction(angleFromUp: angle), progress: 1, isNext: false, isWaiting: false, plan: plan, frame: frame, time: nil, in: context)
    }

    private static func drawSproutBud(_ plan: TreeScenePlan, frame: TreeSceneFrame, time: Double?, in context: GraphicsContext) {
        guard !plan.model.waiting.isEmpty else { return }
        let (top, angle) = sproutTop(frame: frame)
        drawBud(frame.treePoint(top), direction: TreePoint.direction(angleFromUp: angle), progress: 1, isNext: false, isWaiting: true, plan: plan, frame: frame, time: time, in: context)
    }

    // MARK: Helpers

    static func mix(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let ra = a.resolve(in: EnvironmentValues()), rb = b.resolve(in: EnvironmentValues())
        let t = Float(min(1, max(0, t)))
        return Color(
            .sRGB,
            red: Double(ra.red + (rb.red - ra.red) * t),
            green: Double(ra.green + (rb.green - ra.green) * t),
            blue: Double(ra.blue + (rb.blue - ra.blue) * t),
            opacity: Double(ra.opacity + (rb.opacity - ra.opacity) * t)
        )
    }
}

nonisolated extension TreeSceneFrame {
    /// The tree-space point for a screen point.
    func treePoint(_ p: CGPoint) -> TreePoint {
        TreePoint(x: (p.x - base.x) / scale, y: (base.y - p.y) / scale)
    }
}
