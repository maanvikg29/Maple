import MapleCore
import SwiftUI

/// Composes a whole scene frame from a plan. The still frame (Reduce Motion, snapshots, paused) draws everything
/// in one pass; the animated scene composes the same drawing from pre-rasterised layers (`TreeRasterCache`).
nonisolated enum TreeSceneRenderer {
    /// What the frame should animate.
    struct Motion: Sendable {
        /// Seconds; nil is the rest pose (sway phase 0, no flutter, twinkle or particles, bloom at its mean).
        var time: Double?
        var now: Date

        static func rest(now: Date) -> Motion { Motion(time: nil, now: now) }
    }

    static func sway(_ plan: TreeScenePlan, motion: Motion) -> TreeSway {
        guard let time = motion.time else { return .still }
        return TreeSway.at(time, phase: plan.model.phase, vitality: plan.model.vitality)
    }

    /// The bloom breathes ±15% of its opacity over 10 s (spec §4.9); at rest it sits at its mean.
    static func breathe(_ motion: Motion) -> Double {
        motion.time.map { 1 + 0.15 * sin(2 * .pi * $0 / 10) } ?? 1
    }

    /// Where the moonlight reaches toward, in the reference frame.
    static func crownReference(_ plan: TreeScenePlan, frame: TreeSceneFrame) -> CGPoint {
        guard !plan.model.species.isEmpty else { return CGPoint(x: 201, y: 300) }
        let crown = frame.point(plan.skeleton.crownCentroid)
        return CGPoint(x: (crown.x - frame.origin.x) / frame.scale, y: (crown.y - frame.origin.y) / frame.scale)
    }

    static func drawSky(_ plan: TreeScenePlan, frame: TreeSceneFrame, time: Double?, stars: TreeSkyPainter.Stars, background: Color, in context: GraphicsContext) {
        TreeSkyPainter.draw(
            plan.sky, frame: frame, time: time, vitality: plan.model.vitality, crown: crownReference(plan, frame: frame),
            background: background, stars: stars, in: context
        )
    }

    /// Ground, light pool and contact shadow, then the dissolve into the background below the crest.
    static func drawGroundAndDissolve(_ plan: TreeScenePlan, frame: TreeSceneFrame, background: Color, in context: GraphicsContext) {
        TreePainter.drawGround(plan, frame: frame, in: context)
        TreePainter.drawDissolve(frame: frame, color: background, in: context)
    }

    /// The complete frame in one pass, in spec §4.4 order: sky → stars → moon → bloom → ground → shadow →
    /// branches → rosettes → buds and halos → particles.
    static func drawStill(_ plan: TreeScenePlan, frame: TreeSceneFrame, motion: Motion, includesBackdrop: Bool, background: Color, in context: GraphicsContext) {
        let sway = sway(plan, motion: motion)
        if includesBackdrop {
            drawSky(plan, frame: frame, time: motion.time, stars: .all, background: background, in: context)
        }
        TreePainter.drawBloom(plan, frame: frame, breathe: breathe(motion), in: context)
        TreePainter.drawTrophy(plan, frame: frame, in: context)
        drawGroundAndDissolve(plan, frame: frame, background: background, in: context)
        TreePainter.drawWood(plan, depths: 4...8, frame: frame, angle: sway.twigs, in: context)
        TreePainter.drawWood(plan, depths: 1...3, frame: frame, angle: sway.trunk, in: context)
        TreePainter.drawFoliage(
            plan, frame: frame, angle: sway.leaves, time: motion.time, includeFluttering: true,
            includeWaitingBuds: true, now: motion.now, in: context
        )
        if let time = motion.time {
            TreeParticles.draw(plan, frame: frame, time: time, in: context)
        }
    }

    /// The per-frame overlay of the animated scene: fluttering rosettes (from sprites), the waiting bud and
    /// the particles. Everything else is a pre-rasterised layer.
    static func drawOverlay(_ plan: TreeScenePlan, layers: TreeRasterCache.Layers, frame: TreeSceneFrame, motion: Motion, in context: GraphicsContext) {
        let sway = sway(plan, motion: motion)
        var swayed = context
        swayed.translateBy(x: frame.base.x, y: frame.base.y)
        swayed.rotate(by: .radians(sway.leaves))
        swayed.translateBy(x: -frame.base.x, y: -frame.base.y)
        for sprite in layers.sprites {
            var local = swayed
            local.translateBy(x: sprite.anchor.x, y: sprite.anchor.y)
            local.rotate(by: .radians(TreePainter.flutterAngle(plan.rosettes[sprite.rosette], time: motion.time)))
            local.draw(sprite.image, in: CGRect(x: -sprite.size.width / 2, y: -sprite.size.height / 2, width: sprite.size.width, height: sprite.size.height))
        }
        if plan.model.species.isEmpty {
            TreePainter.drawFoliage(plan, frame: frame, angle: 0, time: motion.time, includeFluttering: false, includeWaitingBuds: true, now: motion.now, in: swayed)
        } else {
            TreePainter.drawBuds(plan, frame: frame, time: motion.time, waiting: true, neutral: false, in: swayed)
        }
        if let time = motion.time {
            TreeParticles.draw(plan, frame: frame, time: time, in: context)
        }
    }

    /// The part of the scene the tree's layers cover, with room for halos, buds and roots.
    static func treeRect(_ plan: TreeScenePlan, frame: TreeSceneFrame) -> CGRect {
        let s = frame.scale
        let skeleton = plan.skeleton
        let margin = 26 * s
        let base = frame.base
        let minX = base.x + CGFloat(min(skeleton.minX, -30)) * s - margin
        let maxX = base.x + CGFloat(max(skeleton.maxX, 30)) * s + margin
        let top = base.y - CGFloat(max(skeleton.height, 60)) * s - margin
        let bottom = base.y + 10 * s
        return CGRect(x: minX, y: top, width: maxX - minX, height: bottom - top).integral
    }

    /// The square the bloom's radial gradient fills.
    static func bloomRect(_ plan: TreeScenePlan, frame: TreeSceneFrame) -> CGRect {
        let centre = frame.point(plan.skeleton.crownCentroid)
        let radius = TreePainter.bloomRadius(plan, frame: frame)
        return CGRect(x: centre.x - radius, y: centre.y - radius, width: 2 * radius, height: 2 * radius).integral
    }
}

/// The animated scene's static layers, rasterised once per data change at screen scale (spec §4.9): the sky
/// with its steady stars, the bloom (breathing by opacity), the ground, L1 twigs (depth 4–8), L0 trunk and limbs
/// (depth 1–3), L2 rosettes and buds, and a sprite per fluttering rosette. A frame only composes images.
@MainActor
final class TreeRasterCache {
    static let shared = TreeRasterCache()

    /// A fluttering rosette, pre-rendered, centred on its twig end.
    nonisolated struct Sprite {
        var image: Image
        var anchor: CGPoint
        var size: CGSize
        var rosette: Int
    }

    nonisolated struct Layers {
        /// Nil when the scene draws without its backdrop.
        var sky: Image?
        var bloom: Image?
        var bloomRect: CGRect
        /// The Grand maple ring, only at 155 of 155.
        var trophy: Image?
        var trophyRect: CGRect
        var ground: Image
        var groundRect: CGRect
        var twigs: Image
        var trunk: Image
        var foliage: Image
        /// Where the tree layers sit in the scene.
        var rect: CGRect
        /// The trunk base inside `rect`, the anchor every tree layer sways about.
        var anchor: UnitPoint
        var sprites: [Sprite]

        /// The bloom is rendered at its breathing peak, and each frame dims it by opacity.
        static let bloomPeak = 1.15
    }

    private struct Key: Hashable {
        var plan: TreeSceneModel.PlanKey
        var width: CGFloat
        var height: CGFloat
        var scale: CGFloat
        var backdrop: Bool
        /// New-leaf halos fade over 24 h; the layers are redrawn every 5% of that.
        var haloStep: Int
    }

    private var entries: [Key: Layers] = [:]
    private var order: [Key] = []

    func layers(for plan: TreeScenePlan, frame: TreeSceneFrame, displayScale: CGFloat, includesBackdrop: Bool = true, background: Color = Theme.maple.colors.background, now: Date) -> Layers? {
        let haloStep = plan.model.newLeafHalos.map { Int(min(1, max(0, now.timeIntervalSince($0.placedAt) / 86_400)) * 20) }.reduce(0) { $0 * 21 + $1 }
        let key = Key(
            plan: plan.model.planKey, width: frame.size.width, height: frame.size.height, scale: displayScale,
            backdrop: includesBackdrop, haloStep: haloStep
        )
        if let cached = entries[key] {
            return cached
        }
        let full = CGRect(origin: .zero, size: frame.size)
        let rect = TreeSceneRenderer.treeRect(plan, frame: frame)
        let groundTop = max(0, frame.scene(0, 440).y)
        let groundRect = CGRect(x: 0, y: groundTop, width: frame.size.width, height: max(1, frame.size.height - groundTop))
        let bloomRect = TreeSceneRenderer.bloomRect(plan, frame: frame)
        guard rect.width > 1, rect.height > 1 else { return nil }

        func render(_ area: CGRect, scale: CGFloat = displayScale, _ draw: @escaping @Sendable (GraphicsContext) -> Void) -> CGImage? {
            let content = Canvas { context, _ in
                var context = context
                context.translateBy(x: -area.minX, y: -area.minY)
                draw(context)
            }
            .frame(width: area.width, height: area.height)
            let renderer = ImageRenderer(content: content)
            renderer.scale = scale
            return renderer.cgImage
        }
        func image(_ cgImage: CGImage?, scale: CGFloat = displayScale) -> Image? {
            cgImage.map { Image(decorative: $0, scale: scale) }
        }

        // Soft gradients and pinpoint stars hold up at 2× even on 3× screens, at less than half the memory.
        let skyScale = min(displayScale, 2)
        let sky = includesBackdrop ? image(render(full, scale: skyScale) { context in
            TreeSceneRenderer.drawSky(plan, frame: frame, time: nil, stars: .steady, background: background, in: context)
        }, scale: skyScale) : nil
        let bloom = plan.model.species.isEmpty || plan.bloomOpacity <= 0 ? nil : image(render(bloomRect, scale: skyScale) { context in
            TreePainter.drawBloom(plan, frame: frame, breathe: Layers.bloomPeak, in: context)
        }, scale: skyScale)
        let trophyRect = TreePainter.trophyRect(plan, frame: frame).insetBy(dx: -4, dy: -4).integral
        let trophy = TreePainter.hasTrophy(plan) ? image(render(trophyRect, scale: skyScale) { context in
            TreePainter.drawTrophy(plan, frame: frame, in: context)
        }, scale: skyScale) : nil
        guard
            let ground = image(render(groundRect) { TreeSceneRenderer.drawGroundAndDissolve(plan, frame: frame, background: background, in: $0) }),
            let twigs = image(render(rect) { TreePainter.drawWood(plan, depths: 4...8, frame: frame, angle: 0, in: $0) }),
            let trunk = image(render(rect) { TreePainter.drawWood(plan, depths: 1...3, frame: frame, angle: 0, in: $0) }),
            let foliage = image(render(rect) {
                TreePainter.drawFoliage(plan, frame: frame, angle: 0, time: nil, includeFluttering: false, includeWaitingBuds: false, now: now, in: $0)
            })
        else { return nil }

        let base = frame.base
        let layers = Layers(
            sky: sky, bloom: bloom, bloomRect: bloomRect, trophy: trophy, trophyRect: trophyRect, ground: ground, groundRect: groundRect,
            twigs: twigs, trunk: trunk, foliage: foliage, rect: rect,
            anchor: UnitPoint(x: (base.x - rect.minX) / rect.width, y: (base.y - rect.minY) / rect.height),
            sprites: sprites(plan, frame: frame, displayScale: displayScale)
        )
        entries[key] = layers
        order.append(key)
        if order.count > 4 {
            entries[order.removeFirst()] = nil
        }
        return layers
    }

    /// Every fluttering rosette drawn once into one atlas, then cut into sprites centred on their twig ends.
    private func sprites(_ plan: TreeScenePlan, frame: TreeSceneFrame, displayScale: CGFloat) -> [Sprite] {
        let fluttering = plan.rosettes.indices.filter { plan.rosettes[$0].flutterPeriod != nil }
        guard !fluttering.isEmpty else { return [] }
        let reach = ceil(CGFloat(plan.skeleton.leafSize) * 1.45 * frame.scale + 3)
        let cell = reach * 2
        let columns = Int(ceil(Double(fluttering.count).squareRoot()))
        let rows = (fluttering.count + columns - 1) / columns
        let anchors = fluttering.map { frame.point(plan.rosettes[$0].anchor) }
        let content = Canvas { context, _ in
            for (k, rosette) in fluttering.enumerated() {
                let centre = CGPoint(x: CGFloat(k % columns) * cell + reach, y: CGFloat(k / columns) * cell + reach)
                var local = context
                local.clip(to: Path(CGRect(x: centre.x - reach, y: centre.y - reach, width: cell, height: cell)))
                local.translateBy(x: centre.x - anchors[k].x, y: centre.y - anchors[k].y)
                TreePainter.drawRosette(plan, index: rosette, frame: frame, in: local)
            }
        }
        .frame(width: CGFloat(columns) * cell, height: CGFloat(rows) * cell)
        let renderer = ImageRenderer(content: content)
        renderer.scale = displayScale
        guard let atlas = renderer.cgImage else { return [] }
        return fluttering.enumerated().compactMap { k, rosette in
            let pixels = CGRect(
                x: CGFloat(k % columns) * cell * displayScale, y: CGFloat(k / columns) * cell * displayScale,
                width: cell * displayScale, height: cell * displayScale
            ).integral
            guard let piece = atlas.cropping(to: pixels) else { return nil }
            return Sprite(image: Image(decorative: piece, scale: displayScale), anchor: anchors[k], size: CGSize(width: cell, height: cell), rosette: rosette)
        }
    }
}
