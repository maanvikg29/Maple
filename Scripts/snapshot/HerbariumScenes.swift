// The Herbarium's presentational pieces (docs/design/spec.md §5): every LeafCell variant, Almost-there cards,
// section headers, the detail stage and specimen label, every rarity-explainer state and the share card.
//
//   SIMULATOR="iPhone Air" Scripts/snapshot-ios.sh Scripts/snapshot/HerbariumScenes.swift [output-dir] [filter]
//
// The screens themselves are judged in the real app (docs/debug-launch-arguments.md, -MapleDemoTab herbarium).
// ImageRenderer cannot draw Liquid Glass, so glass is drawn as its solid fallback here.
import Foundation
import SwiftUI

@MainActor
func snapshotScenes() -> [SnapshotScene] {
    var scenes: [SnapshotScene] = [
        SnapshotScene("herbarium-cells", size: CGSize(width: 402, height: 1120)) {
            Page { CellsSheet() }
        },
        SnapshotScene("herbarium-cells-ax3", size: CGSize(width: 402, height: 1500)) {
            Page { RowsSheet() }.environment(\.dynamicTypeSize, .accessibility3)
        },
        SnapshotScene("herbarium-almost-headers", size: CGSize(width: 402, height: 820)) {
            Page { AlmostSheet() }
        },
        SnapshotScene("herbarium-detail-parts", size: CGSize(width: 402, height: 1300)) {
            Page { DetailPartsSheet() }
        },
        SnapshotScene("herbarium-explainer", size: CGSize(width: 402, height: 2200)) {
            Page { ExplainerSheet() }.background(Theme.maple.colors.surface2)
        },
        SnapshotScene("herbarium-filter-chips", size: CGSize(width: 402, height: 360)) {
            Page { FilterChipsSheet() }.background(Theme.maple.colors.surface2)
        },
    ]
    for (name, id, colourway, share) in [
        ("rubrum", "rubrum", LeafColourway.autumn, MemberShare.value(display: "22%", asOf: .now)),
        ("amamiense", "amamiense", .autumn, .value(display: "Under 1%", asOf: .now)),
        ("zarei", "zarei", .summer, .notEnoughMembers(soFar: nil)),
        ("binzayedii", "binzayedii", .frost, .value(display: "0.4%", asOf: .now)),
    ] {
        scenes.append(SnapshotScene("herbarium-share-\(name)", size: ShareCardView.size) {
            ShareCardView(species: leaf(id), colourway: colourway,
                          pressedLine: HerbariumCopy().shareCardLine(pressedOn: day, progress: progress(id, state: .earned(unlock(id, colourway)))),
                          share: share)
        })
    }
    return scenes
}

// MARK: - Fixtures

private let catalog = LeafCatalog.shared
private func leaf(_ id: String) -> LeafSpecies { catalog.species(id: id)! }
private let day = Date(timeIntervalSince1970: 1_791_115_200) // noon UTC, 4 Oct 2026

private func unlock(_ id: String, _ colourway: LeafColourway, seen: Bool = true) -> LeafUnlock {
    LeafUnlock(speciesID: id, date: day, season: .autumn, colourway: colourway, revealed: true, seen: seen)
}

private func progress(
    _ id: String, state: LeafState = .locked, availability: LeafAvailability = .available, current: Double = 0
) -> LeafProgress {
    let rung = RewardCatalog.shared.reward(forSpecies: id)!
    return LeafProgress(speciesID: id, category: rung.categoryID, threshold: rung.threshold, tier: rung.tier,
                        current: current, availability: availability, state: state, estimatedDays: 5)
}

private func entry(
    _ id: String, state: LeafState = .locked, availability: LeafAvailability = .available, current: Double = 0,
    next: Bool = false, unseen: Bool = false, share: MemberShare = .notEnoughMembers(soFar: nil)
) -> HerbariumEntry {
    HerbariumEntry(species: leaf(id), progress: progress(id, state: state, availability: availability, current: current),
                   rule: RewardCatalog.shared.reward(forSpecies: id)!.unlockText, isNextRung: next, isUnseen: unseen,
                   share: share, opensNow: true)
}

private func cells() -> [LeafCellModel] {
    [
        entry("rubrum", state: .earned(unlock("rubrum", .autumn)), share: .value(display: "38%", asOf: .now)),
        entry("palmatum", state: .earned(unlock("palmatum", .summer)), unseen: true),
        entry("binzayedii", state: .earned(unlock("binzayedii", .frost)), share: .value(display: "0.4%", asOf: .now)),
        entry("japonicum", state: .waiting(unlock("japonicum", .autumn, seen: false))),
        entry("sieboldianum", current: 9, next: true),
        entry("zarei", current: 120, next: true),
        entry("amamiense"),
        entry("campestre", availability: .needsAppleHealth),
        entry("griseum", availability: .dormant, share: .notEarnableYet),
    ].map { LeafCellModel($0, season: .autumn) }
}

// MARK: - Sheets

private struct Page<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.maple.colors.background)
        .environment(\.drawsGlassAsSolid, true)
        .environment(\.season, .autumn)
    }
}

private struct CellsSheet: View {
    var body: some View {
        HerbariumSectionHeader(title: "On-time bedtimes", count: "2 of 15",
                               definition: RewardCategoryInfo(.onTimeBedtimes).definition)
            .padding(.horizontal, -16)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(cells()) { model in
                LeafCell(model)
            }
        }
        HerbariumSectionHeader(title: "Steady mornings", count: "0 of 11",
                               definition: RewardCategoryInfo(.steadyMornings).definition,
                               permission: .needsAppleHealth, turnOn: {})
            .padding(.horizontal, -16)
        Text("Show 9 more")
            .font(.system(.subheadline, design: .rounded, weight: .medium))
            .foregroundStyle(Theme.maple.colors.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 44)
    }
}

private struct RowsSheet: View {
    var body: some View {
        VStack(spacing: 10) {
            ForEach(cells().prefix(7)) { model in
                LeafCell(model, layout: .row)
            }
        }
    }
}

private struct AlmostSheet: View {
    var body: some View {
        Text("Almost there")
            .font(MapleFont.sectionTitle)
            .foregroundStyle(Theme.maple.colors.textPrimary)
        // The rail scrolls in the app; ImageRenderer can't draw a ScrollView, so the cards sit in two rows here.
        HStack(spacing: 12) {
            AlmostThereCard(species: leaf("sieboldianum"), fraction: 9.0 / 14, colourway: .autumn, remainder: "5 nights to go")
            AlmostThereCard(species: leaf("triflorum"), fraction: 4.0 / 7, colourway: .autumn, remainder: "Tonight")
        }
        HStack(spacing: 12) {
            AlmostThereCard(species: leaf("crassum"), fraction: 0.4, colourway: .summer, remainder: "2 weeks to go")
            AlmostThereCard(species: leaf("zarei"), fraction: 0.5, colourway: .autumn, remainder: "4 months to go")
        }

        HerbariumSectionHeader(title: "Scarlet", count: "4 of 31", dot: LeafSpecies.AutumnColor.scarlet.color)
            .padding(.horizontal, -16)
        HerbariumSectionHeader(title: "Dormant", count: "82 leaves", definition: "These can't be earned in Maple yet.")
            .padding(.horizontal, -16)
    }
}

private struct DetailPartsSheet: View {
    var body: some View {
        SpecimenStage(species: leaf("rubrum"), colourway: .autumn, state: .earned)
        SpecimenStage(species: leaf("sieboldianum"), colourway: .autumn, state: .next(progress: 0.64))
        SpecimenLabel(species: leaf("amamiense"))
    }
}

private struct ExplainerSheet: View {
    var body: some View {
        let week = Date(timeIntervalSince1970: 1_790_640_000)
        ForEach(Array([
            RarityExplainer(share: .value(display: "22%", asOf: .now), memberCount: 12_400, weekStart: week, included: true),
            RarityExplainer(share: .notEnoughMembers(soFar: 640), memberCount: nil, weekStart: nil, included: false),
            RarityExplainer(share: .notEnoughMembers(soFar: nil), memberCount: nil, weekStart: nil, included: false),
            RarityExplainer(share: .stale(display: "22%", asOf: week), memberCount: 12_400, weekStart: week, included: true),
            RarityExplainer(share: .neverFetched, memberCount: nil, weekStart: nil, included: false),
        ].enumerated()), id: \.offset) { _, explainer in
            RarityExplainerView(explainer)
            Rectangle().fill(.white.opacity(0.1)).frame(height: 1)
        }
    }
}

private struct FilterChipsSheet: View {
    var body: some View {
        ChipFlow {
            FilterChip("East Asia", isSelected: true) {}
            FilterChip("Himalaya", isSelected: false) {}
            FilterChip("Europe", isSelected: false) {}
            FilterChip("North America", isSelected: true) {}
        }
        ChipFlow {
            ForEach(LeafSpecies.AutumnColor.allCases, id: \.self) { colour in
                FilterChip(colour.displayName, dot: colour.color, isSelected: colour == .scarlet) {}
            }
        }
    }
}
