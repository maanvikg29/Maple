// Scenes for reviewing the locked-leaf drawing in MapleDesign/Leaves without building the app: skeletons
// (`LeafStyle.skeleton`), progress rising from the stalk (`LeafView.progressFill`), and the earned leaf, at the
// sizes docs/design/spec.md uses (32 pt next-leaf, 64 pt tile, 200 pt detail), on the dark background.
//
//   Scripts/snapshot.sh Scripts/snapshot/LeafSkeletonScenes.swift [output-dir]
//
// Colours are the spec's tokens, inlined here because they are not in Tokens.swift yet. Compiled by
// Scripts/snapshot.sh together with MapleCore + MapleDesign; not part of the app.
import Foundation
import SwiftUI

@MainActor
func snapshotScenes() -> [SnapshotScene] {
    let catalog = LeafCatalog.shared
    let background = Color(hex: 0x05070D)
    let skeleton = LeafStyle.skeleton(stroke: Color(hex: 0x8A96AD, opacity: 0.35), vein: .white.opacity(0.1))
    let detailSkeleton = LeafStyle.skeleton(
        stroke: Color(hex: 0x8A96AD, opacity: 0.55), vein: Color(hex: 0x8A96AD, opacity: 0.35),
        outlineWidth: 1.25, veinWidth: 0.75
    )
    let tint = Color(hex: 0xE8A35C)
    let ids = ["palmatum", "rubrum", "negundo", "cissifolium", "pentaphyllum", "albopurpurascens",
               "griseum", "davidii", "saccharum", "macrophyllum", "circinatum", "japonicum"]
    let species = ids.compactMap { catalog.species(id: $0) }

    return [
        // Each row: locked skeleton, next with 15 / 50 / 85 % progress, earned.
        SnapshotScene("skeleton-tiles-64pt", size: CGSize(width: 402, height: 900)) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(species) { leaf in
                    HStack(spacing: 10) {
                        LeafView(leaf, style: skeleton)
                        ForEach([0.15, 0.5, 0.85], id: \.self) { fraction in
                            LeafView(leaf, style: .skeleton(stroke: tint.opacity(0.6), vein: tint.opacity(0.35)))
                                .progressFill(fraction: fraction, colour: Color(hex: leaf.autumnColor.rgb), opacity: 0.4)
                        }
                        LeafView(leaf)
                    }
                    .frame(height: 64)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(background)
        },
        SnapshotScene("skeleton-next-32pt", size: CGSize(width: 402, height: 120)) {
            HStack(spacing: 14) {
                ForEach(species.prefix(8)) { leaf in
                    LeafView(leaf, style: .skeleton(stroke: tint.opacity(0.6), vein: tint.opacity(0.35)))
                        .progressFill(fraction: 0.4, colour: Color(hex: leaf.autumnColor.rgb), opacity: 0.4)
                        .frame(width: 32, height: 32)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(background)
        },
        SnapshotScene("skeleton-detail-200pt", size: CGSize(width: 402, height: 460)) {
            VStack(spacing: 20) {
                if let palmatum = catalog.species(id: "palmatum") {
                    LeafView(palmatum, style: detailSkeleton)
                        .progressFill(fraction: 0.6, colour: Color(hex: palmatum.autumnColor.rgb), opacity: 0.4)
                        .frame(width: 200, height: 200)
                }
                if let negundo = catalog.species(id: "negundo") {
                    LeafView(negundo, style: detailSkeleton)
                        .frame(width: 200, height: 200)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(background)
        },
    ]
}
