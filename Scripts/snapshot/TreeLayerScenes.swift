// Diagnostic for anything dark or boxy in the crown, at 1 and 23 species:
// - the animated scene's pre-rasterised layers (TreeRasterCache), each alone over magenta, so opaque or dark pixels
//   a layer carries outside its wood and leaves show at once, then the live (animated, at rest) and still scenes;
// - the still frame built up one pass at a time (sky, bloom, ground, twigs, trunk and limbs, foliage), to see which
//   pass changes what. This is how the old "dark patch" was traced to the bloom's brown cast over a hollow crown.
//
//   SIMULATOR="iPhone Air" Scripts/snapshot-ios.sh Scripts/snapshot/TreeLayerScenes.swift [output-dir]
//   Scripts/snapshot.sh Scripts/snapshot/TreeLayerScenes.swift [output-dir]
//
// Not part of the app.
import Foundation
import SwiftUI

private let layerSeed: UInt64 = 0x00C0_FFEE_0A1E_5EED
private let layerTime = Date(timeIntervalSinceReferenceDate: 812_000_013)
private let layerSize = CGSize(width: 402, height: 560)

@MainActor
private func layerModel(species count: Int, growth: Double, time: Date? = nil, vitality: Double = 1) -> TreeSceneModel {
    let ids = LeafCatalog.shared.species.map(\.id)
    return TreeSceneModel(
        seed: layerSeed, growth: growth,
        species: ids.prefix(count).map { TreeSceneModel.Leaf(speciesID: $0, pressed: .autumn) },
        buds: [TreeSceneModel.Bud(speciesID: ids[count + 1], progress: 0.6)],
        featured: count > 3 ? ids[2] : nil,
        season: .autumn, seasonDay: 40, phase: .evening, vitality: vitality, time: time
    )
}

@MainActor
private func layerScenes(_ name: String, species: Int, growth: Double) -> [SnapshotScene] {
    let model = layerModel(species: species, growth: growth)
    let plan = TreeScenePlan.cached(for: model, theme: .maple)
    let frame = TreeSceneFrame(size: layerSize)
    guard let layers = TreeRasterCache.shared.layers(for: plan, frame: frame, displayScale: 2, now: layerTime) else {
        return []
    }
    func on(_ image: Image?, _ rect: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            Color(red: 1, green: 0, blue: 1)
            if let image {
                image.resizable().frame(width: rect.width, height: rect.height).offset(x: rect.minX, y: rect.minY)
            }
        }
        .frame(width: layerSize.width, height: layerSize.height, alignment: .topLeading)
    }
    let full = CGRect(origin: .zero, size: layerSize)
    var scenes = [
        SnapshotScene("\(name)-a-twigs", size: layerSize) { on(layers.twigs, layers.rect) },
        SnapshotScene("\(name)-b-trunk", size: layerSize) { on(layers.trunk, layers.rect) },
        SnapshotScene("\(name)-c-foliage", size: layerSize) { on(layers.foliage, layers.rect) },
        SnapshotScene("\(name)-d-bloom", size: layerSize) { on(layers.bloom, layers.bloomRect) },
        SnapshotScene("\(name)-e-ground", size: layerSize) { on(layers.ground, layers.groundRect) },
        SnapshotScene("\(name)-f-sky", size: layerSize) { on(layers.sky, full) },
    ]
    scenes.append(SnapshotScene("\(name)-g-animated-rest", size: layerSize) {
        MapleTreeScene(model: model)
    })
    let still = layerModel(species: species, growth: growth, time: layerTime)
    scenes.append(SnapshotScene("\(name)-h-still", size: layerSize) {
        MapleTreeScene(model: still)
    })
    return scenes
}

/// The still frame built up one pass at a time, to find which pass darkens what.
@MainActor
private func passScenes(_ name: String, species: Int, growth: Double) -> [SnapshotScene] {
    let model = layerModel(species: species, growth: growth, time: layerTime)
    let plan = TreeScenePlan.cached(for: model, theme: .maple)
    let background = Theme.maple.colors.background
    func pass(_ suffix: String, _ upTo: Int) -> SnapshotScene {
        SnapshotScene("\(name)-p\(upTo)-\(suffix)", size: layerSize) {
            Canvas { context, size in
                let frame = TreeSceneFrame(size: size)
                TreeSceneRenderer.drawSky(plan, frame: frame, time: nil, stars: .all, background: background, in: context)
                if upTo >= 1 { TreePainter.drawBloom(plan, frame: frame, breathe: 1, in: context) }
                if upTo >= 2 { TreeSceneRenderer.drawGroundAndDissolve(plan, frame: frame, background: background, in: context) }
                if upTo >= 3 { TreePainter.drawWood(plan, depths: 4...8, frame: frame, angle: 0, in: context) }
                if upTo >= 4 { TreePainter.drawWood(plan, depths: 1...3, frame: frame, angle: 0, in: context) }
                if upTo >= 5 {
                    TreePainter.drawFoliage(
                        plan, frame: frame, angle: 0, time: nil, includeFluttering: true, includeWaitingBuds: true,
                        now: layerTime, in: context
                    )
                }
            }
        }
    }
    return [pass("sky", 0), pass("bloom", 1), pass("ground", 2), pass("twigs", 3), pass("trunk", 4), pass("foliage", 5)]
}

@MainActor
func snapshotScenes() -> [SnapshotScene] {
    let g23 = TreeGrowth.structure(tendedDays: 41)
    return layerScenes("s001", species: 1, growth: 0) + layerScenes("s023", species: 23, growth: g23)
        + passScenes("s001", species: 1, growth: 0) + passScenes("s023", species: 23, growth: g23)
}
