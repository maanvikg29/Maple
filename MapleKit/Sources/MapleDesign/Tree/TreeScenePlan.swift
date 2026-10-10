import Foundation
import MapleCore
import Synchronization
import SwiftUI

/// Maps tree space and the 402 × 560 reference scene into a view of any size: the reference frame is scaled
/// to fit and centred, so the trunk base sits at (201, 470) on an iPhone 17 stage.
nonisolated struct TreeSceneFrame: Sendable, Equatable {
    static let reference = CGSize(width: 402, height: 560)
    static let trunkBase = CGPoint(x: 201, y: 470)

    var size: CGSize
    var scale: CGFloat
    var origin: CGPoint

    init(size: CGSize) {
        self.size = size
        scale = max(0.01, min(size.width / Self.reference.width, size.height / Self.reference.height))
        origin = CGPoint(
            x: (size.width - Self.reference.width * scale) / 2,
            y: (size.height - Self.reference.height * scale) / 2
        )
    }

    /// A point of the 402 × 560 reference frame.
    func scene(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
    }

    var base: CGPoint { scene(Self.trunkBase.x, Self.trunkBase.y) }

    /// A tree-space point (y up, origin at the trunk base).
    func point(_ p: TreePoint) -> CGPoint {
        CGPoint(x: base.x + p.x * scale, y: base.y - p.y * scale)
    }

    /// A tree-space direction as a screen vector (y down).
    func vector(_ v: TreePoint) -> CGVector {
        CGVector(dx: v.x, dy: -v.y)
    }
}

/// Everything resolved for drawing one tree: the layout plus every colour, so frames never compute layout.
/// Built once per data change (growth, species, season, phase, vitality) and cached.
nonisolated struct TreeScenePlan: Sendable {
    struct LeafPaint: Sendable {
        var geometry: LeafGeometry
        /// The blade's longest side in placed leaf space: a leaf of `size` points has blades this long.
        var span: CGFloat
        var anchor: TreePoint
        var rotation: Double
        var size: Double
        var fill: Color
        var vein: Color
        /// Frost rim opacity (drawn at 14 pt and up).
        var frostRim: Double
        var rosette: Int
    }

    struct RosettePaint: Sendable {
        var leaves: Range<Int>
        var anchor: TreePoint
        var direction: TreePoint
        var isInner: Bool
        /// Ambient flutter (spec §4.9): seeded period in seconds, or nil when this rosette stays still.
        var flutterPeriod: Double?
        var flutterPhase: Double
        /// Flutter swing either way, radians: ±3° scaled by vitality, so a quiet tree is stiller (spec §4.8).
        var flutterAmplitude: Double
        /// When an amber new-leaf halo started its 24 h fade, if this rosette carries one.
        var haloPlacedAt: Date?
    }

    let model: TreeSceneModel
    let skeleton: TreeSkeleton
    let sky: SkyPalette
    let leaves: [LeafPaint]
    let rosettes: [RosettePaint]
    /// Leaf indices in drawing order: inner rosettes first, then the shell.
    let leafOrder: [Int]
    let bloomColor: Color
    let bloomOpacity: Double
    /// Twig ends carrying spring flowers (first 21 days of spring).
    let flowerTips: [TreePoint]
    let bark: BarkPalette
    let budNeutral: Color
    let reward: Color
    let seasonTint: Color
    let cotyledon: Color
    let scene: Theme.SceneColors
    /// Leaf scale from vitality (0.94 → 1.0, spec §4.8).
    let leafScale: Double
    /// Vitality v clamped to 0.4…1 (spec §4.8): scales the bloom, its ground pool, sway and flutter.
    let vitality: Double
    var hasFlutter: Bool { rosettes.contains { $0.flutterPeriod != nil } }

    struct BarkPalette: Sendable {
        var dark: Color
        var light: Color
        var tip: Color
        var rim: Color
        var snow: Color?
    }

    init(model: TreeSceneModel, theme: Theme) {
        self.model = model
        let colors = theme.colors
        scene = colors.scene
        sky = colors.scene.sky(for: model.phase)
        budNeutral = colors.budNeutral
        reward = colors.reward
        seasonTint = switch model.season {
        case .spring: colors.seasonTints.spring
        case .summer: colors.seasonTints.summer
        case .autumn: colors.seasonTints.autumn
        case .winter: colors.seasonTints.winter
        }
        cotyledon = colors.scene.cotyledon
        let vitality = min(1, max(0.4, model.vitality))
        self.vitality = vitality
        let brightness = sky.treeBrightness
        let catalog = LeafCatalog.shared

        let skeleton = TreeLayout.generate(
            seed: model.seed,
            growth: model.growth,
            species: model.species.map(\.speciesID).filter { catalog.species(id: $0) != nil },
            buds: model.buds.filter { catalog.species(id: $0.speciesID) != nil }
                .map { TreeBudRequest(speciesID: $0.speciesID, progress: $0.progress) },
            featured: model.featured,
            waiting: model.waiting
        )
        self.skeleton = skeleton

        // Colours (spec §4.7, §6.1, §4.8): season tone, −10% saturation, vitality saturation, phase brightness;
        // inner rosettes 15% darker; a little seeded variation per leaf so the crown never looks flat.
        let saturationFactor = 0.9 * (0.8 + 0.2 * (vitality - 0.4) / 0.6)
        leafScale = 0.94 + 0.06 * (vitality - 0.4) / 0.6
        var tones: [String: TreeFoliage.Tone] = [:]
        var spans: [String: CGFloat] = [:]
        var paints: [LeafPaint] = []
        paints.reserveCapacity(skeleton.leaves.count)
        var bloomSum = (r: 0.0, g: 0.0, b: 0.0)
        for (index, leaf) in skeleton.leaves.enumerated() {
            guard let species = catalog.species(id: leaf.speciesID) else { continue }
            let tone = tones[leaf.speciesID] ?? TreeFoliage.tone(
                for: species, season: model.season, seasonDay: model.seasonDay, seed: model.seed
            )
            tones[leaf.speciesID] = tone
            var rng = SplitMix64(seed: SplitMix64.derive(model.seed, UInt64(index) &+ 0x51_7EAF))
            let base = tone.fill.desaturated(by: 1 - saturationFactor)
            bloomSum.r += Double(base.red)
            bloomSum.g += Double(base.green)
            bloomSum.b += Double(base.blue)
            var fill = base.lightened(by: rng.range(-0.035, 0.035))
            fill = fill.scaled(by: brightness * (leaf.isInner ? 0.85 : 1))
            let geometry = LeafGeometry.of(species)
            let span = spans[leaf.speciesID] ?? {
                let bounds = geometry.silhouettePath.boundingRect
                return max(bounds.width, bounds.height, 1)
            }()
            spans[leaf.speciesID] = span
            paints.append(LeafPaint(
                geometry: geometry,
                span: span,
                anchor: leaf.anchor,
                rotation: leaf.rotation,
                size: leaf.size,
                fill: .tree(fill),
                vein: .tree(fill.veinColor),
                frostRim: tone.frostRim,
                rosette: leaf.rosette
            ))
        }
        leaves = paints

        // Bloom: the hue of the instance-weighted average leaf colour, saturation clamped to 0.45, as light.
        bloomColor = .tree(Self.bloomColor(averageOf: bloomSum, count: paints.count))
        bloomOpacity = min(0.18, sky.bloomOpacity * vitality)

        // Rosettes: flutter for at most the 40 nearest the crown front, and only on smaller crowns.
        let flutterAllowed = skeleton.rosettes.count <= 60
        let front = skeleton.rosettes.indices
            .filter { !skeleton.rosettes[$0].isInner }
            .sorted { skeleton.rosettes[$0].anchor.y < skeleton.rosettes[$1].anchor.y }
            .prefix(40)
        let fluttering = flutterAllowed ? Set(front) : []
        var haloSpecies: [String: Date] = [:]
        for halo in model.newLeafHalos {
            haloSpecies[halo.speciesID] = halo.placedAt
        }
        rosettes = skeleton.rosettes.enumerated().map { index, rosette in
            var rng = SplitMix64(seed: SplitMix64.derive(model.seed, "flutter.\(index)"))
            let period = rng.range(5, 7)
            return RosettePaint(
                leaves: rosette.leaves,
                anchor: rosette.anchor,
                direction: rosette.direction,
                isInner: rosette.isInner,
                flutterPeriod: fluttering.contains(index) ? period : nil,
                flutterPhase: rng.range(0, 2 * .pi),
                flutterAmplitude: 3 * .pi / 180 * vitality,
                haloPlacedAt: rosette.kind == .primary ? haloSpecies[rosette.speciesID] : nil
            )
        }
        leafOrder = skeleton.rosettes.indices
            .sorted { a, b in
                let ra = skeleton.rosettes[a], rb = skeleton.rosettes[b]
                return ra.isInner != rb.isInner ? ra.isInner : a < b
            }
            .flatMap { Array(skeleton.rosettes[$0].leaves) }

        // Spring flowers: 2 pt dots on 20% of tips, first 21 days of spring.
        if model.season == .spring, model.seasonDay < TreeFoliage.springFlowerDays {
            flowerTips = skeleton.tips.filter { tip in
                var rng = SplitMix64(seed: SplitMix64.derive(model.seed, "flower.\(tip.id)"))
                return rng.unit() < 0.2
            }.map(\.position)
        } else {
            flowerTips = []
        }

        let scene = colors.scene
        bark = BarkPalette(
            dark: scene.barkDark.scaled(by: brightness),
            light: scene.barkLight.scaled(by: brightness),
            tip: scene.barkTip.scaled(by: brightness),
            rim: scene.barkRim,
            snow: model.season == .winter ? Color.white.opacity(0.35) : nil
        )
    }

    /// The canopy bloom's colour (spec §4.4): the hue of the instance-weighted average leaf colour, with
    /// saturation clamped to 0.45, at the lightness of light rather than of pigment.
    ///
    /// The plain average of autumn reds, oranges and golds is a mid-dark brown (lightness about 0.45). Added
    /// onto the navy sky it cancels the sky's blue into a flat grey-brown, which reads as a dark smudge inside
    /// the crown, not as light. Lifted to `bloomLightness` the same hue adds evenly across the channels: the sky
    /// stays blue and the crown's middle simply glows a little warmer.
    static func bloomColor(averageOf sum: (r: Double, g: Double, b: Double), count: Int) -> LeafColor {
        guard count > 0 else { return LeafColor(0x9DB4E6) }
        let n = Double(count)
        let average = LeafColor(red: Int(sum.r / n), green: Int(sum.g / n), blue: Int(sum.b / n))
        let hsl = average.hsl
        return LeafColor(hue: hsl.hue, saturation: min(0.45, hsl.saturation), lightness: max(bloomLightness, hsl.lightness))
    }

    /// The bloom's lightness floor.
    static let bloomLightness = 0.8

    // MARK: Cache

    private static let cache = Mutex<[CacheKey: TreeScenePlan]>([:])

    private struct CacheKey: Hashable {
        var model: TreeSceneModel.PlanKey
    }

    /// The plan for a model, built once per distinct data and reused for every frame.
    static func cached(for model: TreeSceneModel, theme: Theme) -> TreeScenePlan {
        let key = CacheKey(model: model.planKey)
        if let plan = cache.withLock({ $0[key] }) {
            return plan
        }
        let plan = TreeScenePlan(model: model, theme: theme)
        cache.withLock { storage in
            if storage.count >= 24 {
                storage.removeAll()
            }
            storage[key] = plan
        }
        return plan
    }
}

extension TreeSceneModel {
    /// Everything a plan depends on: all data, but not the clock.
    nonisolated struct PlanKey: Hashable, Sendable {
        var layout: LayoutKey
        var season: Season
        var seasonDay: Int
        var phase: NowPhase
        var vitality: Double
        var halos: [NewLeafHalo]
    }

    nonisolated var planKey: PlanKey {
        PlanKey(layout: layoutKey, season: season, seasonDay: seasonDay, phase: phase, vitality: vitality, halos: newLeafHalos)
    }
}

nonisolated extension LeafColor {
    /// Every channel multiplied by `factor` (phase brightness, inner shade).
    func scaled(by factor: Double) -> LeafColor {
        LeafColor(
            red: Int((Double(red) * factor).rounded()),
            green: Int((Double(green) * factor).rounded()),
            blue: Int((Double(blue) * factor).rounded())
        )
    }
}

nonisolated extension Color {
    /// A 0xRRGGBB colour, usable off the main actor (the tree draws from any thread).
    static func treeHex(_ hex: UInt32, opacity: Double = 1) -> Color {
        Color(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// A catalogue colour, usable off the main actor.
    static func tree(_ color: LeafColor, opacity: Double = 1) -> Color {
        treeHex(color.rgb, opacity: opacity)
    }

    /// The colour with its RGB multiplied by `factor`, keeping opacity.
    func scaled(by factor: Double) -> Color {
        guard factor != 1 else { return self }
        let resolved = resolve(in: EnvironmentValues())
        return Color(
            .sRGB,
            red: Double(resolved.red) * factor,
            green: Double(resolved.green) * factor,
            blue: Double(resolved.blue) * factor,
            opacity: Double(resolved.opacity)
        )
    }
}
