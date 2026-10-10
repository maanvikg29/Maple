import MapleCore
import SwiftUI

/// The reveal's hero, drawn for one `RevealFrame`: the bud that opens, the leaf that unfurls out of it, the amber
/// bloom that turns into the leaf's own colour, and the contact shadow it settles above (spec §5.8). Never boxed.
///
/// The view is the leaf's square (`leafSize`, 200 pt in the cover), centred on the bud; blooms and the shadow
/// spill past it. Pass `frame: nil` for the closed bud, whose glow breathes (still under Reduce Motion).
///
/// ```swift
/// RevealStage(species: rubrum, colourway: .autumn, frame: .at(t, ritual: .full))
/// ```
public struct RevealStage: View {
    @Environment(\.theme) private var theme

    private let species: LeafSpecies
    private let colourway: LeafColourway
    private let frame: RevealFrame?
    private let leafSize: CGFloat
    private let budSize: CGFloat

    /// - Parameters:
    ///   - frame: The ritual's state; nil for the closed, breathing bud.
    ///   - leafSize: The settled leaf's square: 200 in the cover, 56 in the "Open all" row.
    ///   - budSize: The closed bud: 96 in the cover, 56 in the row.
    public init(species: LeafSpecies, colourway: LeafColourway, frame: RevealFrame?, leafSize: CGFloat = 200, budSize: CGFloat = 96) {
        self.species = species
        self.colourway = colourway
        self.frame = frame
        self.leafSize = leafSize
        self.budSize = budSize
    }

    public var body: some View {
        let state = frame ?? .closed
        let scale = leafSize / 200
        let drop = state.drop * scale
        ZStack {
            blooms(state, drop: drop)
            if state.shadow > 0 {
                contactShadow(opacity: state.shadow)
                    .offset(y: drop)
            }
            if state.leafOpacity > 0, state.unfurl > 0 {
                RevealLeafCanvas(species: species, colourway: colourway, unfurl: state.unfurl, veins: state.veins, fill: state.fill)
                    .frame(width: leafSize, height: leafSize)
                    .rotationEffect(.degrees(state.leafTurn))
                    .scaleEffect(state.leafScale)
                    .opacity(state.leafOpacity)
                    .offset(y: drop)
            }
            if state.budOpacity > 0 {
                RevealBud(spread: state.budSpread, glow: state.budGlow, breathing: frame == nil)
                    .frame(width: budSize, height: budSize)
                    .opacity(state.budOpacity)
            }
        }
        .frame(width: leafSize, height: leafSize)
        .accessibilityHidden(true)
    }

    // MARK: Light

    @ViewBuilder
    private func blooms(_ state: RevealFrame, drop: CGFloat) -> some View {
        let scale = leafSize / 200
        if state.amberBloom > 0 {
            let radius = 200 * scale * state.amberReach
            bloom(theme.colors.reward, opacity: state.amberBloom, radius: radius)
                .offset(y: drop)
        }
        if state.leafBloom > 0 {
            // The specimen grammar's bloom: r 180 around a 200 pt leaf (`SpecimenMetrics`).
            let radius = 0.809 * leafSize + 18.2
            bloom(Color(colourway.color(for: species)), opacity: state.leafBloom, radius: radius)
                .offset(y: drop)
        }
    }

    private func bloom(_ colour: Color, opacity: Double, radius: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(
                stops: [
                    .init(color: colour.opacity(opacity), location: 0),
                    .init(color: colour.opacity(opacity * 0.62), location: 0.3),
                    .init(color: colour.opacity(opacity * 0.22), location: 0.65),
                    .init(color: colour.opacity(0), location: 1),
                ],
                center: .center, startRadius: 0, endRadius: max(1, radius)
            ))
            .frame(width: max(2, radius * 2), height: max(2, radius * 2))
            .allowsHitTesting(false)
    }

    /// The specimen's contact shadow: 120 × 10, black 45%, blur 10 under a 200 pt leaf (spec §5.6, §6.5).
    private func contactShadow(opacity: Double) -> some View {
        let width = max(8, 0.588 * leafSize + 2.35)
        let height = max(3, 0.0368 * leafSize + 2.65)
        let blur = min(10, max(6, 0.0294 * leafSize + 4.12))
        return Ellipse()
            .fill(Color.black.opacity((leafSize >= 120 ? 0.45 : 0.5) * opacity))
            .frame(width: width, height: height)
            .blur(radius: blur)
            // Just below the leaf's square, where the stalk ends.
            .offset(y: leafSize * 0.52)
            .allowsHitTesting(false)
    }
}

// MARK: - The unfurling leaf

/// A leaf as the reveal draws it: first sketched in light along its outline and veins, behind a mask that sweeps
/// from the stalk to the tip, then filled with its pressed colour, ending exactly as `LeafView` draws it.
struct RevealLeafCanvas: View {
    let species: LeafSpecies
    let colourway: LeafColourway
    /// 0…1: the mask's sweep from the stalk to the tip.
    let unfurl: Double
    /// 0…1: how much of each vein is drawn.
    let veins: Double
    /// 0…1: the blade's colour (the sketch fades as it arrives).
    let fill: Double

    var body: some View {
        let geometry = LeafGeometry.of(species)
        let leafColour = colourway.color(for: species)
        let style = LeafStyle(fill: leafColour)
        let frost = colourway.hasFrostRim(for: species)
        let unfurl = unfurl, veins = veins, fill = fill
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let transform = LeafRenderer.transform(fitting: geometry.frame, into: rect)
            context.drawLayer { layer in
                if fill < 1 {
                    Self.drawSketch(geometry, style: style, transform: transform, veins: veins, opacity: 1 - fill, in: layer)
                }
                if fill > 0 {
                    var filled = layer
                    filled.opacity = fill
                    Self.drawLeaf(geometry, style: style, frost: frost, transform: transform, veins: veins, in: filled)
                }
                if unfurl < 1 {
                    Self.applyUnfurlMask(geometry, transform: transform, unfurl: unfurl, in: rect, layer: layer)
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// The light sketch: outline and stalk, then the veins as far as they have drawn, in the leaf's colour lifted
    /// toward white so it reads on black. Line widths are in points.
    private static func drawSketch(
        _ geometry: LeafGeometry, style: LeafStyle, transform: CGAffineTransform, veins: Double, opacity: Double,
        in context: GraphicsContext
    ) {
        var context = context
        context.opacity *= opacity
        let light = style.fill.mix(with: .white, by: 0.35)
        let outline = StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round)
        context.drawLayer { lines in
            for blade in geometry.bladePaths {
                lines.stroke(blade.applying(transform), with: .color(light.opacity(0.85)), style: outline)
            }
            lines.stroke(geometry.petiolePath.applying(transform), with: .color(light.opacity(0.85)), style: outline)
            if veins > 0 {
                for vein in geometry.veinPaths {
                    lines.stroke(
                        vein.trimmedPath(from: 0, to: veins).applying(transform),
                        with: .color(light.opacity(0.55)), style: StrokeStyle(lineWidth: 0.75, lineCap: .round)
                    )
                }
            }
        }
    }

    /// The finished leaf, as `LeafRenderer` draws it in full detail, with the veins trimmed to `veins`.
    private static func drawLeaf(
        _ geometry: LeafGeometry, style: LeafStyle, frost: Bool, transform: CGAffineTransform, veins: Double,
        in context: GraphicsContext
    ) {
        var context = context
        context.concatenate(transform)
        let lineShading = GraphicsContext.Shading.color(style.vein)
        context.stroke(
            geometry.petiolePath, with: lineShading,
            style: StrokeStyle(lineWidth: LeafGeometry.Stroke.petiole, lineCap: .round)
        )
        let outline = StrokeStyle(lineWidth: LeafGeometry.Stroke.outline, lineJoin: .round)
        for blade in geometry.bladePaths {
            context.fill(blade, with: .color(style.fill))
            context.stroke(blade, with: lineShading, style: outline)
        }
        if veins > 0 {
            let veinShading = GraphicsContext.Shading.color(style.vein.opacity(LeafGeometry.Stroke.veinOpacity))
            for vein in geometry.veinPaths {
                context.stroke(vein.trimmedPath(from: 0, to: veins), with: veinShading, lineWidth: LeafGeometry.Stroke.vein)
            }
        }
        if frost {
            // Frost leaves carry a thin white rim (spec §6.1), 0.75 pt at any size.
            let scale = hypot(transform.a, transform.b)
            for blade in geometry.bladePaths {
                context.stroke(blade, with: .color(.white.opacity(0.4)), lineWidth: 0.75 / max(scale, 0.01))
            }
        }
    }

    /// Keeps only what the sweep has passed: everything from the stalk up to `unfurl` of the leaf's length, with a
    /// soft edge, measured along the leaf's own axis.
    private static func applyUnfurlMask(
        _ geometry: LeafGeometry, transform: CGAffineTransform, unfurl: Double, in rect: CGRect, layer: GraphicsContext
    ) {
        let edges = RevealUnfurl.edges(geometry: geometry, unfurl: unfurl)
        let toScreen = geometry.placement.concatenating(transform)
        // Clear on the tip side of the edge, opaque on the stalk side (y points down, toward the stalk).
        let clear = CGPoint(x: 0, y: edges.clear).applying(toScreen)
        let opaque = CGPoint(x: 0, y: edges.opaque).applying(toScreen)
        var mask = layer
        mask.blendMode = .destinationIn
        mask.fill(
            Path(rect.insetBy(dx: -rect.width, dy: -rect.height)),
            with: .linearGradient(Gradient(colors: [.clear, .black]), startPoint: clear, endPoint: opaque)
        )
    }
}

/// Where the unfurling mask's soft edge sits, in leaf space (before placement), for a sweep of `unfurl`.
nonisolated enum RevealUnfurl {
    /// The soft edge's width, as a fraction of the leaf's length.
    static let feather: CGFloat = 0.14

    /// The edge runs from `clear` (tip side) to `opaque` (stalk side); both move from below the stalk's end to
    /// past the tip as `unfurl` goes 0 → 1.
    static func edges(geometry: LeafGeometry, unfurl: Double) -> (clear: CGFloat, opaque: CGFloat) {
        let tip = geometry.bladeExtent.lowerBound
        let stalkEnd = max(geometry.bladeExtent.upperBound, geometry.petiole.start.y, geometry.petiole.end.y)
        let length = max(1, stalkEnd - tip)
        let soft = feather * length
        // At 0 the whole edge sits below the stalk's end; at 1 it has passed the tip.
        let start = stalkEnd + soft
        let end = tip - soft
        let level = start + CGFloat(min(1, max(0, unfurl))) * (end - start)
        return (level - soft / 2, level + soft / 2)
    }
}

// MARK: - The opening bud

/// The reveal's bud, drawn as `BudGlyph(waiting: true)` draws it (two bark scales lit from the moon side, a thin
/// `barkRim`, amber light inside), except that its two scales can turn apart about their bases as it opens.
struct RevealBud: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Degrees each scale has turned away from the other.
    let spread: Double
    /// 0…1 of the resting core glow.
    let glow: Double
    /// The closed bud breathes ±15% over `budPulsePeriod` (still under Reduce Motion).
    let breathing: Bool

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let metrics = BudGlyphMetrics(side: side)
            ZStack(alignment: .topLeading) {
                coreGlow(metrics)
                bud(metrics)
            }
            .frame(width: side, height: side)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func bud(_ metrics: BudGlyphMetrics) -> some View {
        let scene = theme.colors.scene
        let bark = LinearGradient(colors: [scene.barkLight, scene.barkDark], startPoint: .leading, endPoint: .trailing)
        let backBark = LinearGradient(
            colors: [scene.barkLight.mix(with: scene.barkDark, by: 0.45), scene.barkDark],
            startPoint: .leading, endPoint: .trailing
        )
        let rim = LinearGradient(
            stops: [.init(color: scene.barkRim, location: 0), .init(color: scene.barkRim.opacity(0), location: 0.62)],
            startPoint: .leading, endPoint: .trailing
        )
        let rimWidth = max(0.5, min(0.75, metrics.side / 64))
        let rect = metrics.budRect
        return ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: CGPoint(x: rect.minX + rect.width * 0.52, y: rect.maxY - rect.height * 0.06))
                path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.52, y: metrics.stalkEnd))
            }
            .stroke(scene.barkLight, style: StrokeStyle(lineWidth: metrics.stalkWidth, lineCap: .round))

            scale(.back, in: rect, turn: -spread) {
                BudShape(.back).fill(backBark)
                    .overlay { BudShape(.back).stroke(rim, lineWidth: rimWidth) }
                    .overlay { BudShape(.back).fill(innerLight(in: rect)).opacity(glow) }
            }
            scale(.front, in: rect, turn: spread) {
                BudShape(.front).fill(bark)
                    .overlay { BudShape(.front).stroke(rim, lineWidth: rimWidth) }
                    .overlay {
                        BudShape(.front)
                            .stroke(seam, lineWidth: rimWidth * 1.4)
                            .mask {
                                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: UnitPoint(x: 0.6, y: 0.5))
                            }
                            .opacity(glow)
                    }
            }
        }
    }

    /// One scale, placed in the bud's rectangle and turned `turn` degrees about its base.
    private func scale<Content: View>(_ part: BudShape.Part, in rect: CGRect, turn: Double, @ViewBuilder content: () -> Content) -> some View {
        let local = CGRect(origin: .zero, size: rect.size)
        let pivot = BudShape.pivot(of: part, in: local)
        return content()
            .frame(width: rect.width, height: rect.height)
            .rotationEffect(
                .degrees(turn),
                anchor: UnitPoint(x: pivot.x / max(rect.width, 1), y: pivot.y / max(rect.height, 1))
            )
            .offset(x: rect.minX, y: rect.minY)
    }

    private func innerLight(in rect: CGRect) -> RadialGradient {
        let reward = theme.colors.reward
        return RadialGradient(
            stops: [
                .init(color: reward.opacity(0.42), location: 0),
                .init(color: reward.opacity(0.12), location: 0.55),
                .init(color: reward.opacity(0), location: 1),
            ],
            center: UnitPoint(x: 0.36, y: 0.62), startRadius: 0, endRadius: rect.height * 0.5
        )
    }

    private var seam: LinearGradient {
        let reward = theme.colors.reward
        return LinearGradient(
            stops: [
                .init(color: reward.opacity(0), location: 0.15),
                .init(color: reward.opacity(0.6), location: 0.55),
                .init(color: reward.opacity(0.6), location: 0.75),
                .init(color: reward.opacity(0), location: 0.95),
            ],
            startPoint: UnitPoint(x: 0.4, y: 0), endPoint: UnitPoint(x: 0.2, y: 1)
        )
    }

    /// The `reward` core glow: 35% at r 60 on the 96 pt reveal bud (spec §5.8), breathing ±15% over 4 s.
    @ViewBuilder
    private func coreGlow(_ metrics: BudGlyphMetrics) -> some View {
        let peak = BudGlyph.coreOpacity(side: metrics.side, cap: theme.elevation.waitingBudCoreCap) * glow
        let reward = theme.colors.reward
        let radius = metrics.glowRadius
        let halo = Circle()
            .fill(RadialGradient(
                stops: [
                    .init(color: reward.opacity(peak), location: 0),
                    .init(color: reward.opacity(peak * 0.55), location: 0.28),
                    .init(color: reward.opacity(peak * 0.2), location: 0.6),
                    .init(color: reward.opacity(0), location: 1),
                ],
                center: .center, startRadius: 0, endRadius: radius
            ))
            .frame(width: radius * 2, height: radius * 2)
            .position(metrics.glowCentre)
            .allowsHitTesting(false)
        if breathing && !reduceMotion && peak > 0 {
            halo.phaseAnimator([1.0, 0.74]) { content, strength in
                content.opacity(strength)
            } animation: { _ in
                .easeInOut(duration: theme.motion.budPulsePeriod / 2)
            }
        } else {
            halo
        }
    }
}
