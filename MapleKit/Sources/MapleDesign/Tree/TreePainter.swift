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
        context.drawLayer { layer in
            // Finer wood first, so every limb covers the base of the twigs growing from it.
            let all = plan.skeleton.branches
            let trunk = depths.contains(1) ? all.first { $0.depth == 1 } : nil
            // The leaders rising straight out of the trunk top are drawn with it, as one piece of wood.
            let leaders = trunk.map { trunk in
                all.filter { branch in
                    guard branch.depth == 2, let start = branch.points.first, let top = trunk.points.last else { return false }
                    return hypot(start.x - top.x, start.y - top.y) < 0.01
                }
            } ?? []
            let leaderIDs = Set(leaders.map(\.id))
            let branches = all
                .filter { depths.contains($0.depth) && $0.depth != 1 && !leaderIDs.contains($0.id) }
                .sorted { $0.depth > $1.depth }
            for branch in branches {
                drawBranch(branch, plan: plan, frame: frame, in: layer)
            }
            // The roots go under the trunk, so its flared foot runs smoothly out into them.
            if depths.contains(1) {
                drawRoots(plan, frame: frame, in: layer)
            }
            if let trunk {
                drawTrunk(trunk, leaders: leaders, plan: plan, frame: frame, in: layer)
            }
            shadeUnderCanopy(plan, frame: frame, in: layer)
        }
    }

    /// Wood inside the crown sits in the canopy's shade: darkest at the crown's heart, clear at its rim and on the
    /// trunk below, so the limbs recede behind the leaves while the trunk keeps its moonlit modelling.
    private static func shadeUnderCanopy(_ plan: TreeScenePlan, frame: TreeSceneFrame, in context: GraphicsContext) {
        let skeleton = plan.skeleton
        guard !skeleton.leaves.isEmpty else { return }
        let centre = frame.point(skeleton.crownCentroid)
        let halfWidth = CGFloat(max(40, skeleton.width * 0.5)) * frame.scale
        let halfHeight = CGFloat(max(30, (skeleton.height - skeleton.crownCentroid.y) * 1.25)) * frame.scale
        var layer = context
        layer.blendMode = .sourceAtop
        layer.translateBy(x: centre.x, y: centre.y)
        layer.scaleBy(x: 1, y: halfHeight / halfWidth)
        // Gentle: the limbs recede, but never turn darker than the sky they cross.
        let gradient = Gradient(stops: [
            .init(color: .black.opacity(0.18), location: 0),
            .init(color: .black.opacity(0.13), location: 0.45),
            .init(color: .black.opacity(0), location: 1),
        ])
        layer.fill(
            Path(ellipseIn: CGRect(x: -halfWidth, y: -halfWidth, width: 2 * halfWidth, height: 2 * halfWidth)),
            with: .radialGradient(gradient, center: .zero, startRadius: 0, endRadius: halfWidth)
        )
    }

    /// Rosettes, flowers, halos and buds, rotated by `angle` about the trunk base. `flutter` gives each fluttering
    /// rosette's extra angle; pass nil to skip fluttering rosettes entirely (they are drawn per frame elsewhere).
    static func drawFoliage(
        _ plan: TreeScenePlan, frame: TreeSceneFrame, angle: Double, time: Double?, includeFluttering: Bool,
        includeWaitingBuds: Bool, includeHalos: Bool = true, now: Date, in context: GraphicsContext
    ) {
        guard !plan.model.species.isEmpty else {
            if includeWaitingBuds {
                drawSproutBud(plan, frame: frame, time: time, in: context)
            }
            return
        }
        var context = context
        rotate(&context, by: angle, about: frame.base)
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
        // Over the rosettes (spec §4.4 order), so a new leaf's glow still shows in a full crown.
        if includeHalos {
            drawHalos(plan, frame: frame, now: now, in: context)
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
        return rosette.flutterAmplitude * sin(2 * .pi * time / period + rosette.flutterPhase)
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
        // A smooth, bell-shaped falloff: no core or rim the eye could read as a shape.
        let gradient = Gradient(stops: [0, 0.2, 0.4, 0.6, 0.8, 1].map { t in
            .init(color: plan.bloomColor.opacity(opacity * exp(-4.2 * t * t) * (1 - t * t * t)), location: t)
        })
        let rect = CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: rect), with: .radialGradient(gradient, center: centre, startRadius: 0, endRadius: radius))
    }

    /// Whether the tree carries the Grand maple trophy: every species collected (spec §4.4).
    static func hasTrophy(_ plan: TreeScenePlan) -> Bool {
        plan.skeleton.primaryTips.count >= LeafCatalog.shared.species.count
    }

    /// The ring the trophy draws in: radius 0.62 × crown width around the crown centroid, kept 8 pt inside the
    /// 402 pt scene so it never reads as cut off.
    static func trophyRect(_ plan: TreeScenePlan, frame: TreeSceneFrame) -> CGRect {
        let centre = frame.point(plan.skeleton.crownCentroid)
        let radius = min(0.62 * plan.skeleton.width, TreeSceneFrame.reference.width / 2 - 8) * frame.scale
        return CGRect(x: centre.x - radius, y: centre.y - radius, width: 2 * radius, height: 2 * radius)
    }

    /// The Grand maple trophy: a faint ring of moonlight behind the crown, half sunk behind the hill.
    static func drawTrophy(_ plan: TreeScenePlan, frame: TreeSceneFrame, in context: GraphicsContext) {
        guard hasTrophy(plan) else { return }
        let ring = Path(ellipseIn: trophyRect(plan, frame: frame))
        context.stroke(ring, with: .color(plan.scene.moonlight.opacity(0.025)), lineWidth: 5 * frame.scale)
        context.stroke(ring, with: .color(plan.scene.moonlight.opacity(0.08)), lineWidth: frame.scale)
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

        // Light pool under the crown: the bloom's light on the ground, so it dims with it (spec §4.8).
        if !plan.model.species.isEmpty {
            let poolCentre = frame.scene(201, 476)
            let poolWidth = 260 * s * (0.55 + 0.45 * plan.model.growth)
            drawEllipticalGlow(
                at: poolCentre, width: poolWidth, height: 40 * s, color: plan.bloomColor, opacity: 0.08 * plan.vitality, in: context
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
    private static func ribbon(_ samples: [Sample], widthScale: CGFloat = 1, roundEnd: Bool = true, shift: (Sample) -> CGVector = { _ in .zero }) -> Path {
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

    /// Draws one limb: its fill and lit bands, then its rim, furrows and snow.
    private static func drawBranch(_ branch: TreeSkeleton.Branch, plan: TreeScenePlan, frame: TreeSceneFrame, in context: GraphicsContext) {
        let samples = shaped(samples(of: branch, frame: frame), flare: branch.depth == 1, taper: true)
        guard samples.count >= 2 else { return }
        fillWood(samples, roundEnd: true, plan: plan, frame: frame, in: context)
        detailWood(samples, depth: branch.depth, seed: plan.model.seed &+ UInt64(branch.id), plan: plan, frame: frame, in: context)
    }

    /// The trunk and the leaders it forks into. Each leader is filled as one ribbon running up the trunk and on
    /// into the leader, so the fork reads as one piece of wood rather than limbs set on a post. The leader facing
    /// the light goes last: its lit band and rim carry the trunk's straight on up into it, and the others pick up
    /// their own once they are clear of the crotch.
    private static func drawTrunk(
        _ trunk: TreeSkeleton.Branch, leaders: [TreeSkeleton.Branch], plan: TreeScenePlan, frame: TreeSceneFrame, in context: GraphicsContext
    ) {
        let trunkSamples = shaped(samples(of: trunk, frame: frame), flare: true, taper: false)
        guard trunkSamples.count >= 2 else { return }
        let fork = trunkSamples.count - 1
        let light = plan.sky.lightDirection
        func facing(_ leader: TreeSkeleton.Branch) -> Double {
            guard leader.points.count >= 2 else { return -.infinity }
            let a = leader.points[0], b = leader.points[leader.points.count - 1]
            let dx = b.x - a.x, dy = a.y - b.y
            return (dx * light.dx + dy * light.dy) / max(1e-6, hypot(dx, dy))
        }
        var parts: [(samples: [Sample], id: Int)] = []
        for leader in leaders.sorted(by: { facing($0) < facing($1) }) {
            var joined = leader
            joined.points = trunk.points + leader.points.dropFirst()
            joined.widths = trunk.widths + leader.widths.dropFirst()
            let samples = shaped(samples(of: joined, frame: frame), flare: true, taper: true)
            guard samples.count > fork + 1 else { continue }
            fillWood(samples, roundEnd: true, plan: plan, frame: frame, in: context)
            parts.append((samples, leader.id))
        }
        guard let lit = parts.last else {
            fillWood(trunkSamples, roundEnd: true, plan: plan, frame: frame, in: context)
            detailWood(trunkSamples, depth: 1, seed: plan.model.seed &+ UInt64(trunk.id), plan: plan, frame: frame, in: context)
            return
        }
        let crotch = trunkSamples[fork]
        for part in parts.dropLast() {
            let clear = part.samples.indices.dropFirst(fork).first { i in
                hypot(part.samples[i].point.x - crotch.point.x, part.samples[i].point.y - crotch.point.y) > crotch.width
            }
            guard let clear, part.samples.count - clear >= 2 else { continue }
            detailWood(Array(part.samples[clear...]), depth: 2, seed: plan.model.seed &+ UInt64(part.id), plan: plan, frame: frame, in: context)
        }
        detailWood(lit.samples, depth: 1, seed: plan.model.seed &+ UInt64(trunk.id), plan: plan, frame: frame, in: context)
    }

    /// Flares the trunk into the ground and tapers twig ends to a point rather than stopping blunt.
    private static func shaped(_ samples: [Sample], flare: Bool, taper: Bool) -> [Sample] {
        var samples = samples
        guard samples.count >= 2 else { return samples }
        if flare {
            let base = samples[0].point
            let w0 = samples[0].width
            for i in samples.indices {
                let rise = hypot(samples[i].point.x - base.x, samples[i].point.y - base.y)
                samples[i].width *= 1 + 0.55 * exp(-rise / max(1, w0 * 0.75))
            }
        }
        if taper {
            let n = samples.count
            for (offset, factor) in [(1, 0.35), (2, 0.62), (3, 0.85)] where n - offset > 0 {
                samples[n - offset].width *= factor
            }
        }
        return samples
    }

    /// The wood itself: a base ribbon, then narrower bands shifted toward the light (fading where the limb points
    /// at it), stepped to approximate a soft cylindrical gradient across the limb.
    private static func fillWood(_ samples: [Sample], roundEnd: Bool, plan: TreeScenePlan, frame: TreeSceneFrame, in context: GraphicsContext) {
        let light = plan.sky.lightDirection
        let maxWidth = samples.map(\.width).max() ?? 0
        // Thin wood is lifted toward the tip colour so twigs read against the sky.
        let thinness = Double(min(1, max(0, (2.2 * frame.scale - maxWidth) / (1.8 * frame.scale))))
        let baseColor = thinness > 0 ? mix(plan.bark.dark, plan.bark.tip, thinness * 0.4) : plan.bark.dark
        context.fill(ribbon(samples, roundEnd: roundEnd), with: .color(baseColor))
        guard maxWidth >= 1.1 * frame.scale else { return }
        let litTone = thinness > 0 ? mix(plan.bark.light, plan.bark.tip, thinness * 0.6) : plan.bark.light
        let bands: [(width: CGFloat, shift: CGFloat, amount: Double)] = maxWidth >= 3 * frame.scale
            ? [(0.7, 0.14, 0.4), (0.48, 0.26, 0.72), (0.26, 0.36, 1)]
            : [(0.46, 0.25, 0.8)]
        for band in bands {
            let path = ribbon(samples, widthScale: band.width, roundEnd: roundEnd) { s in
                let along = light.dx * s.tangent.dx + light.dy * s.tangent.dy
                return CGVector(dx: (light.dx - s.tangent.dx * along) * s.width * band.shift, dy: (light.dy - s.tangent.dy * along) * s.width * band.shift)
            }
            context.fill(path, with: .color(mix(baseColor, litTone, band.amount)))
        }
    }

    /// The moonlit rim along the light-facing edge of the trunk and limbs (no outlines anywhere), furrows in the
    /// old bark of the trunk and leaders, and in winter a line of snow along the top of limbs running sideways.
    private static func detailWood(_ samples: [Sample], depth: Int, seed: UInt64, plan: TreeScenePlan, frame: TreeSceneFrame, in context: GraphicsContext) {
        let maxWidth = samples.map(\.width).max() ?? 0
        guard depth <= 3, maxWidth >= 2.2 * frame.scale else { return }
        let light = plan.sky.lightDirection
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

        if depth <= 2, maxWidth >= 6 * frame.scale {
            drawFurrows(samples, seed: seed, frame: frame, in: context)
        }

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

    /// Three broken lines running with the limb, darkest where they cross the lit band.
    private static func drawFurrows(_ samples: [Sample], seed: UInt64, frame: TreeSceneFrame, in context: GraphicsContext) {
        var rng = SplitMix64(seed: SplitMix64.derive(seed, "furrows"))
        let first = Int(Double(samples.count) * 0.04), last = Int(Double(samples.count) * 0.9)
        guard last - first >= 3 else { return }
        for offset in [-0.3, 0.02, 0.28] {
            var path = Path()
            let jitter = rng.range(-0.04, 0.04)
            for (k, s) in samples[first..<last].enumerated() {
                let n = CGVector(dx: -s.tangent.dy, dy: s.tangent.dx)
                let o = CGFloat(offset + jitter) * s.width
                let p = CGPoint(x: s.point.x + n.dx * o, y: s.point.y + n.dy * o)
                if k == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            let dash = [rng.range(5, 10), rng.range(2, 4), rng.range(3, 7), rng.range(2, 5)].map { CGFloat($0) * frame.scale }
            context.stroke(
                path, with: .color(.black.opacity(0.26)),
                style: StrokeStyle(lineWidth: 0.7 * frame.scale, lineCap: .round, dash: dash, dashPhase: CGFloat(rng.range(0, 8)))
            )
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
            context.fill(root, with: .color(litSide ? mix(plan.bark.dark, plan.bark.light, 0.4) : plan.bark.dark))
        }
    }

    // MARK: Leaves

    /// Where a leaf's stalk ends on screen: its anchor, turned with the rosette's flutter about the twig end.
    private static func stalkEnd(_ leaf: TreeScenePlan.LeafPaint, rosette: TreeScenePlan.RosettePaint, extraAngle: Double, frame: TreeSceneFrame) -> CGPoint {
        let anchor = frame.point(leaf.anchor)
        guard extraAngle != 0 else { return anchor }
        // Flutter turns the whole rosette about its twig end.
        let pivot = frame.point(rosette.anchor)
        let dx = anchor.x - pivot.x, dy = anchor.y - pivot.y
        let c = cos(extraAngle), s = sin(extraAngle)
        return CGPoint(x: pivot.x + dx * c - dy * s, y: pivot.y + dx * s + dy * c)
    }

    private static func leafTransform(_ leaf: TreeScenePlan.LeafPaint, scale leafScale: Double, rosette: TreeScenePlan.RosettePaint, extraAngle: Double, frame: TreeSceneFrame) -> CGAffineTransform {
        let geometry = leaf.geometry
        let stalkEnd = geometry.petiole.end.applying(geometry.placement)
        let k = leaf.size * leafScale * frame.scale / leaf.span
        let anchor = Self.stalkEnd(leaf, rosette: rosette, extraAngle: extraAngle, frame: frame)
        return CGAffineTransform(translationX: anchor.x, y: anchor.y)
            .rotated(by: leaf.rotation + extraAngle)
            .scaledBy(x: k, y: k)
            .translatedBy(x: -stalkEnd.x, y: -stalkEnd.y)
    }

    private static func drawLeaf(_ leaf: TreeScenePlan.LeafPaint, rosette: TreeScenePlan.RosettePaint, extraAngle: Double, plan: TreeScenePlan, frame: TreeSceneFrame, in context: GraphicsContext) {
        let transform = leafTransform(leaf, scale: plan.leafScale, rosette: rosette, extraAngle: extraAngle, frame: frame)
        let pointSize = leaf.size * plan.leafScale
        // Small leaves stand out from the twig on long stalks (TreeLayout): draw the stalk back to the twig.
        let twig = frame.point(rosette.anchor), end = stalkEnd(leaf, rosette: rosette, extraAngle: extraAngle, frame: frame)
        if hypot(end.x - twig.x, end.y - twig.y) > 0.8 * frame.scale {
            var stalk = Path()
            stalk.move(to: twig)
            stalk.addLine(to: end)
            context.stroke(stalk, with: .color(leaf.vein), style: StrokeStyle(lineWidth: 0.45 * frame.scale, lineCap: .round))
        }
        LeafRenderer.draw(leaf.geometry, in: context, transform: transform, style: LeafStyle(fill: leaf.fill, vein: leaf.vein, detail: .fillOnly))
        if pointSize >= 9 {
            foldShade(leaf, transform: transform, light: plan.sky.lightDirection, in: context)
        }
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

    /// A leaf is never quite flat: the half of the blade on the light's side of the midrib is a touch lighter and
    /// the other half a touch darker, so each leaf reads as gently creased.
    private static func foldShade(_ leaf: TreeScenePlan.LeafPaint, transform: CGAffineTransform, light: CGVector, in context: GraphicsContext) {
        let geometry = leaf.geometry
        // The midrib runs along x = 0 of the generator's leaf space, from the stalk to the tip.
        let toScreen = geometry.placement.concatenating(transform)
        let right = Path(CGRect(x: 0, y: -220, width: 220, height: 440)).applying(toScreen)
        let left = Path(CGRect(x: -220, y: -220, width: 220, height: 440)).applying(toScreen)
        let length = max(1e-6, hypot(toScreen.a, toScreen.b))
        let facing = (toScreen.a * light.dx + toScreen.b * light.dy) / length
        let strength = 0.35 + 0.65 * abs(facing)
        var clipped = context
        clipped.clip(to: geometry.silhouettePath.applying(transform))
        clipped.fill(facing >= 0 ? right : left, with: .color(.white.opacity(0.07 * strength)))
        clipped.fill(facing >= 0 ? left : right, with: .color(.black.opacity(0.1 * strength)))
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

    /// The amber glow over each newly placed species' primary rosette, fading over 24 h (spec §4.5).
    static func drawHalos(_ plan: TreeScenePlan, frame: TreeSceneFrame, now: Date, in context: GraphicsContext) {
        guard !plan.model.newLeafHalos.isEmpty else { return }
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
        // The Home next leaf is always the largest bud, however far along the other two are.
        let furthest = plan.skeleton.buds.filter { !$0.isWaiting }.map(\.progress).max() ?? 0
        for bud in plan.skeleton.buds where bud.isWaiting ? waiting : neutral {
            let progress = bud.isNext ? max(bud.progress, furthest) : bud.progress
            drawBud(bud.anchor, direction: bud.direction, progress: progress, isNext: bud.isNext, isWaiting: bud.isWaiting, plan: plan, frame: frame, time: time, in: context)
        }
    }

    static func drawBud(_ anchor: TreePoint, direction: TreePoint, progress: Double, isNext: Bool, isWaiting: Bool, plan: TreeScenePlan, frame: TreeSceneFrame, time: Double?, in context: GraphicsContext) {
        let s = frame.scale
        let swell = isWaiting ? 1 : (0.4 + 0.6 * min(1, max(0, progress))) * (isNext ? 1.15 : 1)
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
