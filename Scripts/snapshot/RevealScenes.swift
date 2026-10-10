// The unlock reveal (docs/design/spec.md §5.8) without building the app: the ritual as filmstrips (full, short and
// the Reduce Motion crossfade), "Open all" rows, the caption for documented, approximate and uncharted leaves in
// several rarity states, and the consent sheet's content.
//
//   SIMULATOR="iPhone 17" Scripts/snapshot-ios.sh Scripts/snapshot/RevealScenes.swift [output-dir] [filter]
//   Scripts/snapshot.sh Scripts/snapshot/RevealScenes.swift [output-dir]       (macOS: Mac type sizes)
//
// ImageRenderer draws only what SwiftUI draws itself, so scroll views, glass and share links stay empty here: the
// whole cover is checked in the app (`-MapleDemoPresent reveal`, docs/debug-launch-arguments.md). Compiled together
// with MapleCore + MapleDesign; not part of the app.
import Foundation
import SwiftUI

@MainActor
func snapshotScenes() -> [SnapshotScene] {
    let catalog = LeafCatalog.shared
    func leaf(_ id: String, _ colourway: LeafColourway, share: MemberShare = .notEnoughMembers(soFar: nil)) -> RevealLeaf? {
        RevealLeaf(unlock: LeafUnlock(speciesID: id, date: .now, season: .autumn, colourway: colourway), share: share)
    }
    let legendary = leaf("laevigatum", .summer, share: .value(display: "Under 1%", asOf: .now))
    let common = leaf("macrophyllum", .autumn, share: .value(display: "38%", asOf: .now))
    let sugar = leaf("saccharum", .autumn)
    let approximate = leaf("sycopseoides", .spring, share: .stale(display: "4%", asOf: .now.addingTimeInterval(-6 * 86_400)))
    let uncharted = catalog.species.first { $0.confidence == .placeholder }.flatMap { leaf($0.id, .frost, share: .loading) }

    var scenes: [SnapshotScene] = []
    let times: [TimeInterval] = [0, 0.3, 0.6, 0.9, 1.2, 1.6, 2.0, 2.4, 3.2]
    for (name, ritual, subject) in [
        ("full", RevealRitual.full, legendary), ("full-sugar", .full, sugar), ("short", .short, common),
        ("crossfade", .crossfade, common),
    ] {
        guard let subject else { continue }
        let ritualTimes = ritual == .full ? times : [0, 0.15, 0.3, 0.45, 0.6, 0.8, 1.0, 1.2]
        scenes.append(SnapshotScene("reveal-ritual-\(name)", size: CGSize(width: 900, height: 900)) {
            RitualStrip(leaf: subject, ritual: ritual, times: ritualTimes)
        })
    }
    if let legendary, let common, let approximate, let uncharted {
        scenes.append(SnapshotScene("reveal-captions", size: CGSize(width: 402, height: 1180)) {
            VStack(spacing: 48) {
                RevealHeader(position: (1, 3), detail: legendary.categoryName)
                RevealCaption(legendary)
                RevealCaption(common)
                RevealCaption(approximate)
                RevealCaption(uncharted)
            }
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(hex: 0x05070D))
        })
        scenes.append(SnapshotScene("reveal-captions-ax3", size: CGSize(width: 402, height: 1500)) {
            VStack(spacing: 48) {
                RevealHeader(position: (1, 3), detail: legendary.categoryName)
                RevealCaption(legendary)
                RevealCaption(uncharted)
            }
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(hex: 0x05070D))
            .environment(\.dynamicTypeSize, .accessibility3)
        })
        let row = [legendary, common, approximate]
        scenes.append(SnapshotScene("reveal-open-all-row", size: CGSize(width: 402, height: 700)) {
            VStack(spacing: 40) {
                ForEach([0.0, 0.3, 0.6, 1.0, 2.0], id: \.self) { time in
                    HStack(spacing: 16) {
                        ForEach(Array(row.enumerated()), id: \.offset) { index, item in
                            let schedule = RevealOpenAllSchedule(count: row.count, reduceMotion: false)
                            RevealStage(species: item.species, colourway: item.colourway,
                                        frame: schedule.frame(of: index, at: time), leafSize: 56, budSize: 56)
                                .frame(width: 56, height: 56)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(hex: 0x05070D))
        })
        scenes.append(SnapshotScene("reveal-open-all-list", size: CGSize(width: 402, height: 420)) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(row + [uncharted]) { item in
                    RevealListRow(leaf: item)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(hex: 0x05070D))
        })
    }
    return scenes
}

/// The stage at each time of a ritual, labelled, on the cover's black.
private struct RitualStrip: View {
    let leaf: RevealLeaf
    let ritual: RevealRitual
    let times: [TimeInterval]

    var body: some View {
        let columns = [GridItem(.fixed(280)), GridItem(.fixed(280)), GridItem(.fixed(280))]
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(times, id: \.self) { time in
                VStack(spacing: 4) {
                    RevealStage(species: leaf.species, colourway: leaf.colourway,
                                frame: time == 0 ? nil : .at(time, ritual: ritual), leafSize: 200, budSize: 96)
                        .frame(width: 200, height: 200)
                        .frame(width: 280, height: 250)
                        .clipped()
                    Text(time == 0 ? "closed" : String(format: "%.2fs", time))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(hex: 0x05070D))
    }
}
