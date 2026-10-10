// The maple hero (MapleDesign/Tree) as a snapshot matrix, rendered without the app:
//
//   Scripts/snapshot.sh Scripts/snapshot/TreeScenes.swift [output-dir]
//   xcrun swift Scripts/snapshot/TreeContactSheet.swift [output-dir] [output-dir]/00-contact-sheet.png
//
// Species counts 0 (seed sprout), 1, 5, 15, 40, 90, 155 at the growth spec §4.5 pairs them with, in autumn
// evening; 40 species in each season; each phase at 40 species; a quiet tree; a waiting bud; and a Reduce Motion
// still. Every scene uses the same seed and a fixed instant, so renders are reproducible. Compiled by
// Scripts/snapshot.sh together with MapleCore + MapleDesign; not part of the app.
import Foundation
import SwiftUI

/// Species in a plausible unlock order: each rung's estimated day at the category's design pace.
@MainActor
private let unlockOrder: [String] = {
    let catalog = RewardCatalog.shared
    return catalog.assignments
        .sorted { a, b in
            let da = a.threshold / RewardCategoryInfo(a.categoryID).designPace
            let db = b.threshold / RewardCategoryInfo(b.categoryID).designPace
            return da != db ? da < db : RewardCategoryInfo(a.categoryID).order < RewardCategoryInfo(b.categoryID).order
        }
        .map(\.speciesID)
}()

private let sceneSeed: UInt64 = 0x00C0_FFEE_0A1E_5EED
/// A fixed instant chosen so an autumn samara is mid-fall and the sway sits slightly off rest.
private let sceneTime = Date(timeIntervalSinceReferenceDate: 812_000_013)
private let sceneSize = CGSize(width: 402, height: 560)

@MainActor
private func model(
    species count: Int, growth: Double, season: Season = .autumn, phase: NowPhase = .evening,
    vitality: Double = 1, waiting: Int = 0, seasonDay: Int = 40, featured: Bool = true, halo: Bool = false
) -> TreeSceneModel {
    let ids = Array(unlockOrder.prefix(count))
    let next = Array(unlockOrder.dropFirst(count + waiting).prefix(3))
    let waitingIDs = Array(unlockOrder.dropFirst(count).prefix(waiting))
    return TreeSceneModel(
        seed: sceneSeed,
        growth: growth,
        species: ids.map { TreeSceneModel.Leaf(speciesID: $0, pressed: .autumn) },
        buds: zip(next, [0.72, 0.4, 0.15]).map { TreeSceneModel.Bud(speciesID: $0, progress: $1) },
        waiting: waitingIDs,
        featured: featured && count > 3 ? ids[2] : nil,
        season: season,
        seasonDay: seasonDay,
        phase: phase,
        vitality: vitality,
        newLeafHalos: halo && !ids.isEmpty ? [TreeSceneModel.NewLeafHalo(speciesID: ids[ids.count - 1], placedAt: sceneTime.addingTimeInterval(-3 * 3600))] : [],
        time: sceneTime
    )
}

@MainActor
private func scene(_ name: String, _ model: TreeSceneModel) -> SnapshotScene {
    SnapshotScene(name, size: sceneSize) {
        MapleTreeScene(model: model, onOpenWaitingLeaf: {})
    }
}

@MainActor
func snapshotScenes() -> [SnapshotScene] {
    // (species, growth) pairs from spec §4.5 and the reward pacing.
    let sizes: [(Int, Double)] = [(0, 0), (1, 0), (5, 0.05), (15, 0.14), (40, 0.34), (90, 0.70), (155, 1.0)]
    var scenes = sizes.enumerated().map { index, pair in
        scene(String(format: "%02d-species-%03d-autumn-evening", index + 1, pair.0), model(species: pair.0, growth: pair.1, waiting: pair.0 == 0 ? 0 : 0))
    }
    let seasons: [(Season, NowPhase, String)] = [(.spring, .day, "spring-day"), (.summer, .evening, "summer-evening"), (.autumn, .evening, "autumn-evening"), (.winter, .night, "winter-night")]
    for (offset, entry) in seasons.enumerated() {
        let day = entry.0 == .spring ? 12 : 40
        scenes.append(scene(String(format: "%02d-season-%@", 8 + offset, entry.2), model(species: 40, growth: 0.34, season: entry.0, phase: entry.1, seasonDay: day)))
    }
    let phases: [(NowPhase, String)] = [(.morning, "morning"), (.day, "day"), (.evening, "evening"), (.windDown, "wind-down"), (.night, "night")]
    for (offset, entry) in phases.enumerated() {
        scenes.append(scene(String(format: "%02d-phase-%@", 12 + offset, entry.1), model(species: 40, growth: 0.34, phase: entry.0)))
    }
    scenes.append(scene("17-quiet", model(species: 40, growth: 0.34, vitality: 0.45)))
    scenes.append(scene("18-waiting-bud", model(species: 15, growth: 0.14, waiting: 1, halo: true)))
    // Reduce Motion: the rest pose (sway phase 0, no flutter, twinkle or particles, bloom at its mean).
    let still = model(species: 40, growth: 0.34)
    scenes.append(SnapshotScene("19-reduce-motion-still", size: sceneSize) {
        Canvas { context, size in
            let plan = TreeScenePlan.cached(for: still, theme: .maple)
            TreeSceneRenderer.drawStill(
                plan, frame: TreeSceneFrame(size: size), motion: .rest(now: sceneTime), includesBackdrop: true,
                background: Theme.maple.colors.background, in: context
            )
        }
    })
    scenes.append(scene("20-seed-waiting", model(species: 0, growth: 0, waiting: 1)))
    return scenes
}
