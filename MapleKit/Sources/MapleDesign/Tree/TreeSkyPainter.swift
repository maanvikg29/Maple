import MapleCore
import SwiftUI

/// Draws the sky (spec §4.4): gradient, dawn wash, light pools, stars, the crescent moon and its moonlight.
nonisolated enum TreeSkyPainter {
    /// Stars are the same for everyone: 48 fixed points of the reference frame.
    struct Star: Sendable {
        var position: CGPoint
        var radius: CGFloat
        var level: Double
        var period: Double
        var phase: Double
    }

    static let stars: [Star] = {
        var rng = SplitMix64(seed: 0x5EED_57A2)
        var result: [Star] = []
        let moon = SkyPalette.moonCenter
        while result.count < 48 {
            // Thinner toward the horizon.
            let y = 12 + pow(rng.unit(), 1.35) * 360
            let x = rng.range(10, 392)
            let p = CGPoint(x: x, y: y)
            if hypot(p.x - moon.x, p.y - moon.y) < 34 { continue }
            if result.contains(where: { hypot($0.position.x - x, $0.position.y - y) < 18 }) { continue }
            result.append(Star(
                position: p, radius: rng.range(0.45, 0.95), level: rng.unit(),
                period: rng.range(6, 12), phase: rng.range(0, 2 * .pi)
            ))
        }
        return result
    }()

    /// Which stars to draw: all of them, only the steady ones (for a pre-rendered sky), or only the twinkling
    /// ones (drawn per frame over it).
    enum Stars: Sendable {
        case all, steady, twinkling
    }

    /// The whole sky. `time` drives twinkle; nil draws every star at its resting (mean) level.
    /// `crown` is where the moonlight reaches toward (reference frame).
    static func draw(
        _ palette: SkyPalette, frame: TreeSceneFrame, time: Double?, vitality: Double, crown: CGPoint, background: Color,
        stars: Stars = .all, in context: GraphicsContext
    ) {
        let bounds = CGRect(origin: .zero, size: frame.size)
        context.fill(Path(bounds), with: .color(background))
        let top = frame.scene(0, 0).y, bottom = frame.scene(0, 560).y
        context.fill(
            Path(CGRect(x: 0, y: 0, width: frame.size.width, height: bottom)),
            with: .linearGradient(Gradient(stops: palette.stops), startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: bottom))
        )

        if let pool = palette.pool {
            let centre = frame.scene(pool.center.x, pool.center.y)
            let r = pool.radius * frame.scale
            context.fill(Path(bounds), with: .radialGradient(
                Gradient(stops: [
                    .init(color: pool.color, location: 0),
                    .init(color: pool.color.opacity(0.5), location: 0.4),
                    .init(color: pool.color.opacity(0), location: 1),
                ]),
                center: centre, startRadius: 0, endRadius: r
            ))
        }
        if let wash = palette.dawnWash {
            let a = frame.scene(0, 380).y, b = frame.scene(0, 480).y
            context.fill(
                Path(CGRect(x: 0, y: a, width: frame.size.width, height: b - a)),
                with: .linearGradient(
                    Gradient(stops: [.init(color: wash.opacity(0), location: 0), .init(color: wash, location: 0.7), .init(color: wash.opacity(0), location: 1)]),
                    startPoint: CGPoint(x: 0, y: a), endPoint: CGPoint(x: 0, y: b)
                )
            )
        }

        drawStars(palette, frame: frame, time: time, vitality: vitality, selection: stars, in: context)

        if palette.showsMoon {
            drawMoon(frame: frame, palette: palette, crown: crown, in: context)
        }
    }

    /// How many stars twinkle for this palette and vitality (none in a quiet week, spec §4.8).
    static func twinkling(_ palette: SkyPalette, vitality: Double) -> Int {
        vitality >= 0.6 ? min(palette.twinklingStars, palette.starCount) : 0
    }

    static func drawStars(_ palette: SkyPalette, frame: TreeSceneFrame, time: Double?, vitality: Double, selection: Stars, in context: GraphicsContext) {
        guard palette.starCount > 0 else { return }
        let twinkles = twinkling(palette, vitality: vitality)
        for (index, star) in stars.prefix(palette.starCount).enumerated() {
            let twinkles = index < twinkles
            switch selection {
            case .all: break
            case .steady: if twinkles { continue }
            case .twinkling: if !twinkles { continue }
            }
            let range = palette.starOpacity
            var opacity = range.lowerBound + (range.upperBound - range.lowerBound) * star.level
            if twinkles {
                // Around 80% of its level; at rest it sits at that mean.
                opacity *= 0.8 + 0.2 * (time.map { sin(2 * .pi * $0 / star.period + star.phase) } ?? 0)
            }
            let p = frame.scene(star.position.x, star.position.y)
            let r = star.radius * frame.scale
            context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(palette.moonDisc.opacity(opacity)))
        }
    }

    private static func drawMoon(frame: TreeSceneFrame, palette: SkyPalette, crown: CGPoint, in context: GraphicsContext) {
        let moon = SkyPalette.moonCenter
        let centre = frame.scene(moon.x, moon.y)
        let s = frame.scale

        // Moonlight: a long soft pool from the moon toward the crown.
        let target = frame.scene(crown.x, crown.y)
        let dx = target.x - centre.x, dy = target.y - centre.y
        let distance = hypot(dx, dy)
        let mid = CGPoint(x: centre.x + dx * 0.55, y: centre.y + dy * 0.55)
        TreePainter.drawEllipticalGlow(
            at: mid, width: distance * 1.3, height: 250 * s, color: palette.moonlight,
            opacity: palette.moonlightPool, angle: atan2(dy, dx), in: context
        )

        // Halo: 60 pt across at 6%.
        let halo = 30 * s
        context.fill(
            Path(ellipseIn: CGRect(x: centre.x - halo, y: centre.y - halo, width: 2 * halo, height: 2 * halo)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: palette.moonDisc.opacity(0.06), location: 0),
                    .init(color: palette.moonDisc.opacity(0.035), location: 0.4),
                    .init(color: palette.moonDisc.opacity(0), location: 1),
                ]),
                center: centre, startRadius: 0, endRadius: halo
            )
        )

        // The crescent: a 12 pt disc with an offset disc taken away, lit toward the lower left.
        let r = 6 * s
        let disc = Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: 2 * r, height: 2 * r))
        let bite = Path(ellipseIn: CGRect(x: centre.x - r + 3.4 * s, y: centre.y - r - 2.2 * s, width: 2 * r * 0.98, height: 2 * r * 0.98))
        context.fill(disc.subtracting(bite), with: .color(palette.moonDisc.opacity(0.55)))
    }
}

/// One seasonal particle system at a time (spec §4.7), as pure functions of time.
nonisolated enum TreeParticles {
    static func draw(_ plan: TreeScenePlan, frame: TreeSceneFrame, time: Double, in context: GraphicsContext) {
        guard plan.model.vitality >= 0.6, !plan.model.species.isEmpty else { return }
        switch plan.model.season {
        case .autumn: drawSamara(plan, frame: frame, time: time, in: context)
        case .winter: drawSnow(plan, frame: frame, time: time, in: context)
        case .spring: drawPollen(plan, frame: frame, time: time, in: context)
        case .summer:
            if [.evening, .windDown, .night].contains(plan.model.phase) {
                drawFireflies(plan, frame: frame, time: time, in: context)
            }
        }
    }

    /// Samaras: one every 30–45 s from an outer rosette, spinning once per 0.8 s, falling for 14 s.
    private static func drawSamara(_ plan: TreeScenePlan, frame: TreeSceneFrame, time: Double, in context: GraphicsContext) {
        let cycle = 37.5
        let index = Int((time / cycle).rounded(.down))
        let outer = plan.skeleton.rosettes.filter { !$0.isInner }
        guard !outer.isEmpty else { return }
        for k in [index - 1, index] {
            var rng = SplitMix64(seed: SplitMix64.derive(plan.model.seed, UInt64(bitPattern: Int64(k)) &+ 0x5A3A))
            let spawn = Double(k) * cycle + rng.range(-3.75, 3.75)
            let age = time - spawn
            guard age >= 0, age < 14 else { continue }
            let source = outer[Int(rng.unit() * Double(outer.count)) % outer.count].anchor
            let start = frame.point(source)
            let groundY = frame.scene(0, 470).y + CGFloat(rng.range(-2, 6)) * frame.scale
            let p = age / 14
            let drift = CGFloat(rng.range(18, 34) * rng.sign()) * frame.scale
            let x = start.x + drift * p + CGFloat(sin(age * 1.3 + rng.range(0, 6))) * 9 * frame.scale
            let y = start.y + (groundY - start.y) * (0.15 * p + 0.85 * p * p * (3 - 2 * p)) * 0.98 + CGFloat(p) * 0
            let fade = min(1, age / 0.6) * min(1, (14 - age) / 2.5)
            var local = context
            local.translateBy(x: x, y: y)
            local.rotate(by: .radians(2 * .pi * age / 0.8))
            local.opacity = fade
            let s = frame.scale
            var wing = Path()
            wing.move(to: .zero)
            wing.addQuadCurve(to: CGPoint(x: 5.6 * s, y: -0.6 * s), control: CGPoint(x: 2.6 * s, y: -2.6 * s))
            wing.addQuadCurve(to: .zero, control: CGPoint(x: 3.2 * s, y: 0.9 * s))
            let colour = plan.scene.samara
            local.fill(wing, with: .color(colour))
            local.fill(Path(ellipseIn: CGRect(x: -1.2 * s, y: -1.1 * s, width: 2.4 * s, height: 2.2 * s)), with: .color(colour))
        }
    }

    /// 14 snow motes, 1–2 pt, falling over 18 s.
    private static func drawSnow(_ plan: TreeScenePlan, frame: TreeSceneFrame, time: Double, in context: GraphicsContext) {
        for i in 0..<14 {
            var rng = SplitMix64(seed: SplitMix64.derive(0x5_70_0E, UInt64(i)))
            let x0 = rng.range(20, 382), phase = rng.unit(), size = rng.range(1, 2), wobble = rng.range(5, 9)
            let p = (time / 18 + phase).truncatingRemainder(dividingBy: 1)
            let y = -10 + 480 * p
            let x = x0 + 9 * sin(2 * .pi * time / wobble + phase * 6)
            let fade = min(1, p / 0.08) * min(1, (1 - p) / 0.1)
            let point = frame.scene(x, y)
            let r = size / 2 * frame.scale
            context.fill(Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: 2 * r, height: 2 * r)), with: .color(.white.opacity(0.35 * fade)))
        }
    }

    /// 6 pollen motes drifting up through the crown over 20 s.
    private static func drawPollen(_ plan: TreeScenePlan, frame: TreeSceneFrame, time: Double, in context: GraphicsContext) {
        let crown = frame.point(plan.skeleton.crownCentroid)
        let half = CGFloat(plan.skeleton.width) * 0.5 * frame.scale
        for i in 0..<6 {
            var rng = SplitMix64(seed: SplitMix64.derive(plan.model.seed, UInt64(i) &+ 0x9011E9))
            let x0 = rng.range(-1, 1), phase = rng.unit()
            let p = (time / 20 + phase).truncatingRemainder(dividingBy: 1)
            let x = crown.x + CGFloat(x0) * half + CGFloat(sin(2 * .pi * (time / 9 + phase))) * 8 * frame.scale
            let y = frame.base.y - CGFloat(20 + 300 * p) * frame.scale
            let fade = sin(.pi * p)
            let r = 1.2 * frame.scale
            context.fill(
                Path(ellipseIn: CGRect(x: x - r * 2, y: y - r * 2, width: r * 4, height: r * 4)),
                with: .radialGradient(Gradient(colors: [plan.scene.pollen.opacity(fade), plan.scene.pollen.opacity(0)]), center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r * 2)
            )
        }
    }

    /// 4 fireflies around the lower crown, each glowing for 3 s then resting.
    private static func drawFireflies(_ plan: TreeScenePlan, frame: TreeSceneFrame, time: Double, in context: GraphicsContext) {
        let crown = plan.skeleton.crownCentroid
        let half = plan.skeleton.width * 0.5
        for i in 0..<4 {
            let cycle = 7.0 + Double(i) * 0.9
            let shifted = time + Double(i) * 2.3
            let k = Int((shifted / cycle).rounded(.down))
            let age = shifted - Double(k) * cycle
            guard age < 3 else { continue }
            var rng = SplitMix64(seed: SplitMix64.derive(plan.model.seed, UInt64(bitPattern: Int64(k * 4 + i)) &+ 0xF12E))
            let p = TreePoint(x: crown.x + rng.range(-1, 1) * half, y: rng.range(18, max(30, crown.y)))
            let drift = TreePoint(x: rng.range(-6, 6) * age / 3, y: rng.range(-2, 5) * age / 3)
            let point = frame.point(p + drift)
            let glow = pow(sin(.pi * age / 3), 2)
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 2 * frame.scale))
                let r = 1 * frame.scale
                layer.fill(Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: 2 * r, height: 2 * r)), with: .color(plan.scene.firefly.opacity(glow)))
            }
        }
    }
}
