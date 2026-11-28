import MapleCore
import SwiftUI

/// Home's picture, alive (`VanAmbience`): the picture's own smoke, flag, bunting, sky leaves, fire, lantern flame and
/// cat and the steam over the pot, moving where the picture has them, and the maple's leaves coming down. Drawn by
/// Maple and not the picture's: the glow of the fire, the lantern and the string lights.
///
/// Pieces that swing over the sky are laid on their "gap" (the piece's shape in the sky's colour there), so the
/// picture's still copy never shows behind them. `.behind` goes under Pip; `.front`, the falling leaves, over him.
struct VanAmbientLayer: View {
    enum Part {
        case behind
        case front
    }

    let part: Part
    /// Seconds since home appeared.
    let time: Double
    let canvas: VanCanvas
    let size: CGSize

    private typealias Box = (x0: Double, y0: Double, x1: Double, y1: Double)

    // Where each piece was cut from, in the picture's pixels (`AMBIENT_BOXES` in the art script).
    private static let smoke: Box = (1004, 334, 1200, 538)
    /// The wisp's cloud, without the trail down to the chimney, and its middle.
    private static let smokeCloud: Box = (1040, 334, 1200, 466)
    private static let smokeCloudMiddle = (x: 1124.0, y: 400.0)
    private static let flag: Box = (1167, 512, 1292, 594)
    /// The leaves painted in mid-air, in the order of `VanAmbience.paintedLeaf`: four over the sky, three over the canopy.
    private static let paintedLeaves: [(name: String, box: Box)] = [
        ("VanAmbSkyLeaf0", (1290, 262, 1406, 372)), ("VanAmbSkyLeaf1", (1490, 420, 1610, 540)),
        ("VanAmbSkyLeaf2", (1640, 770, 1740, 880)), ("VanAmbSkyLeaf3", (40, 925, 200, 1075)),
        ("VanAmbCanopyLeaf0", (546, 82, 672, 200)), ("VanAmbCanopyLeaf1", (64, 155, 200, 298)),
        ("VanAmbCanopyLeaf2", (276, 255, 415, 402)),
    ]
    /// A stray stroke near the canopy's top, painted out (`CANOPY_MARK`).
    private static let canopyMark: Box = (286, 6, 386, 88)
    private static let pennants: [Box] = [(550, 696, 616, 773), (622, 724, 690, 795), (700, 736, 770, 805), (779, 723, 847, 796), (854, 697, 919, 774)]
    private static let fire: Box = (808, 1366, 888, 1438)
    private static let flame: Box = (1132, 1198, 1164, 1236)
    private static let cat: Box = (782, 1572, 992, 1700)
    /// The steam puffs painted over the pot (`STEAM_SEEDS`).
    private static let steam: [Box] = [(738, 1101, 779, 1151), (805, 1120, 836, 1148), (771, 1088, 787, 1107)]
    /// The string lights round the trunk and along to the van.
    private static let bulbs: [(Double, Double)] = [(240, 876), (300, 920), (380, 937), (450, 932), (530, 940)]
    /// Where the smoke leaves the chimney, and the pot's middle.
    private static let chimneyTop = (x: 1016.0, y: 536.0)
    private static let potTop = (x: 765.0, y: 1178.0)

    private static let leafNames = ["VanLeafOrange", "VanLeafYellow", "VanLeafRed"]
    private static let leafWidths = [132.0, 112.0, 90.0]

    var body: some View {
        Canvas { context, size in
            let scale = canvas.scale(width: size.width, height: size.height)
            let origin = canvas.point(x: 0, y: 0, width: size.width, height: size.height)
            let paint = Painter(context: context, scale: scale, origin: CGPoint(x: origin.x, y: origin.y))
            switch part {
            case .behind: drawBehind(paint)
            case .front: drawFront(paint)
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Under Pip

    private func drawBehind(_ paint: Painter) {
        // The leaves painted in mid-air, over the sky and over the canopy, swing where they hang; now and then one lets
        // go and falls, and later it is back.
        paint.image("VanAmbCanopyMarkGap", in: Self.canopyMark)
        for (index, leaf) in Self.paintedLeaves.enumerated() {
            let now = VanAmbience.paintedLeaf(index, at: time)
            let box = leaf.box
            paint.image(leaf.name + "Gap", in: box)
            let middle = (x: (box.x0 + box.x1) / 2, y: (box.y0 + box.y1) / 2)
            paint.image(leaf.name, in: box, about: middle, turn: now.turn, offset: (now.dx, now.dy), opacity: now.opacity)
        }

        // Smoke: the picture's own wisp leans with the wind about the chimney's top, and puffs of its cloud (the
        // wisp's top) break off and rise away, growing and fading.
        paint.image("VanAmbSmokeGap", in: Self.smoke)
        let sway = VanAmbience.smoke(at: time)
        paint.image("VanAmbSmoke", in: Self.smoke, about: Self.chimneyTop, turn: sway.turn, scale: (sway.scale, sway.scale))
        for puff in VanAmbience.chimneyPuffs(at: time) {
            paint.image(
                "VanAmbSmoke", in: Self.smoke, part: Self.smokeCloud, about: Self.smokeCloudMiddle, turn: sway.turn,
                scale: (puff.scale, puff.scale), offset: (puff.drift, -130 * puff.rise), opacity: 0.9 * puff.opacity
            )
        }

        // The flag flaps about the pole, and each pennant swings from the line.
        paint.image("VanAmbFlagGap", in: Self.flag)
        let flap = VanAmbience.flag(at: time)
        paint.image("VanAmbFlag", in: Self.flag, about: (Self.flag.x0, (Self.flag.y0 + Self.flag.y1) / 2), turn: flap.turn, scale: (flap.stretch, 1))
        for (index, box) in Self.pennants.enumerated() {
            paint.image("VanAmbPennant\(index)Gap", in: box)
            paint.image("VanAmbPennant\(index)", in: box, about: ((box.x0 + box.x1) / 2, box.y0 + 3), turn: VanAmbience.bunting(index, at: time))
        }

        // The string lights twinkle.
        for (index, bulb) in Self.bulbs.enumerated() {
            paint.glow(at: bulb, radius: 46, colour: Color(red: 1, green: 0.93, blue: 0.62), strength: 0.15 + 0.55 * VanAmbience.bulb(index, at: time))
        }

        // The stove's fire and the lantern's flame flicker, and light the room round them.
        let fire = VanAmbience.flicker(at: time, seed: 0)
        paint.glow(at: (848, 1404), radius: 95, colour: Color(red: 1, green: 0.62, blue: 0.25), strength: 0.2 + 0.3 * fire)
        paint.image("VanAmbFire", in: Self.fire, about: (848, Self.fire.y1 - 4), scale: (1 + 0.025 * fire, 1 + 0.09 * fire))
        let lantern = VanAmbience.flicker(at: time, seed: 1)
        paint.glow(at: (1148, 1214), radius: 80, colour: Color(red: 1, green: 0.85, blue: 0.45), strength: 0.2 + 0.3 * lantern)
        paint.image("VanAmbFlame", in: Self.flame, about: (1148, Self.flame.y1 - 3), scale: (1 + 0.04 * lantern, 1 + 0.14 * lantern))

        // Steam off the pot: the picture's own puffs swell and settle where it painted them, and copies of one rise off
        // the pot, growing and fading.
        for (index, box) in Self.steam.enumerated() {
            let swell = VanAmbience.steamSwell(index, at: time)
            paint.image("VanAmbSteam\(index)", in: box, about: ((box.x0 + box.x1) / 2, (box.y0 + box.y1) / 2), scale: (swell, swell))
        }
        for (index, puff) in VanAmbience.steam(at: time).enumerated() {
            let x = Self.potTop.x + Double(index) * 12 - 18 + puff.drift
            let y = Self.potTop.y - 6 - 118 * puff.rise
            paint.centred("VanAmbSteam1", at: (x, y), width: 30 * (0.5 + puff.scale), turn: 0.3 * puff.rise * (index.isMultiple(of: 2) ? 1 : -1), opacity: 0.85 * puff.opacity)
        }

        // The cat breathes.
        let breath = VanAmbience.catBreath(at: time)
        paint.image("VanAmbCat", in: Self.cat, about: ((Self.cat.x0 + Self.cat.x1) / 2, Self.cat.y1 - 6), scale: (1 + (breath - 1) * 0.4, breath))
    }

    // MARK: Over Pip

    private func drawFront(_ paint: Painter) {
        for leaf in VanAmbience.leaves(at: time) where leaf.opacity > 0.01 {
            let width = Self.leafWidths[leaf.colour] * leaf.size
            paint.centred(Self.leafNames[leaf.colour], at: (leaf.x, leaf.y), width: width, turn: leaf.turn, opacity: leaf.opacity)
        }
    }
}

/// Draws the picture's pieces where the picture has them, on a canvas laid over it.
private struct Painter {
    let context: GraphicsContext
    /// Points per picture pixel, and where the picture's corner is.
    let scale: Double
    let origin: CGPoint

    func point(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
    }

    /// An image cut from `box`, turned and scaled about `about` (a point of the picture), and moved by `offset`.
    /// With `part`, only that piece of it (a box of the picture, inside `box`) is drawn.
    func image(
        _ name: String, in box: (x0: Double, y0: Double, x1: Double, y1: Double),
        part: (x0: Double, y0: Double, x1: Double, y1: Double)? = nil, about: (Double, Double)? = nil,
        turn: Double = 0, scale stretch: (Double, Double) = (1, 1), offset: (Double, Double) = (0, 0), opacity: Double = 1
    ) {
        guard opacity > 0.005 else { return }
        var drawing = context
        drawing.opacity = opacity
        let anchor = about ?? (box.x0, box.y0)
        let pivot = point(anchor.0 + offset.0, anchor.1 + offset.1)
        drawing.translateBy(x: pivot.x, y: pivot.y)
        drawing.rotate(by: .radians(turn))
        drawing.scaleBy(x: stretch.0, y: stretch.1)
        // Picture boxes, in the turned and scaled drawing's own space.
        func local(_ b: (x0: Double, y0: Double, x1: Double, y1: Double)) -> CGRect {
            let corner = point(b.x0 + offset.0, b.y0 + offset.1)
            return CGRect(x: corner.x - pivot.x, y: corner.y - pivot.y, width: (b.x1 - b.x0) * scale, height: (b.y1 - b.y0) * scale)
        }
        if let part { drawing.clip(to: Path(local(part))) }
        drawing.draw(drawing.resolve(Image(name)), in: local(box))
    }

    /// A leaf (or anything) placed by its middle.
    func centred(_ name: String, at: (Double, Double), width: Double, turn: Double, opacity: Double) {
        var drawing = context
        drawing.opacity = opacity
        let resolved = drawing.resolve(Image(name))
        let height = width * resolved.size.height / max(1, resolved.size.width)
        let middle = point(at.0, at.1)
        drawing.translateBy(x: middle.x, y: middle.y)
        drawing.rotate(by: .radians(turn))
        drawing.draw(resolved, in: CGRect(x: -width * scale / 2, y: -height * scale / 2, width: width * scale, height: height * scale))
    }

    /// Soft light: brightest in the middle, gone at `radius` picture pixels.
    func glow(at: (Double, Double), radius: Double, colour: Color, strength: Double, blend: GraphicsContext.BlendMode = .screen) {
        guard strength > 0.005 else { return }
        var drawing = context
        drawing.blendMode = blend
        drawing.opacity = min(1, strength)
        let middle = point(at.0, at.1)
        let r = radius * scale
        let rect = CGRect(x: middle.x - r, y: middle.y - r, width: 2 * r, height: 2 * r)
        drawing.fill(
            Path(ellipseIn: rect),
            with: .radialGradient(
                Gradient(colors: [colour, colour.opacity(0.5), colour.opacity(0)]), center: middle, startRadius: 0, endRadius: r
            )
        )
    }
}
