#if DEBUG
import SwiftUI
import MapleCore
import MapleDesign

/// The controls on the two backgrounds they really sit on: black, and Home's evening sky (spec §7.3).
struct DesignControls: View {
    @Environment(\.theme) private var theme
    @Environment(\.season) private var season

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xl) {
            VStack(alignment: .leading, spacing: theme.spacing.sm) {
                DesignGroupLabel("On black")
                DesignControlSet()
            }
            VStack(alignment: .leading, spacing: theme.spacing.sm) {
                DesignGroupLabel("On the evening sky")
                DesignControlSet()
                    .padding(theme.spacing.md)
                    .background {
                        SkyBackdrop(phase: .evening, season: season)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: theme.radius.largeTile, style: .continuous))
            }
        }
        .padding(.horizontal, theme.spacing.listMargin)
        .padding(.bottom, theme.spacing.lg)
    }
}

private struct DesignControlSet: View {
    @Environment(\.theme) private var theme
    @State private var colourway = "Pressed"
    @State private var mode = "Sleep"
    @State private var filter = "All"

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.lg) {
            sample("Primary · normal, dimmed, disabled") {
                VStack(spacing: theme.spacing.sm) {
                    Button("Open your new leaf") {}.buttonStyle(.moonlight)
                    Button("Start wind-down") {}.buttonStyle(.moonlight(dimmed: true))
                    Button("Start focus") {}.buttonStyle(.moonlight).disabled(true)
                }
            }
            sample("Glass capsule · 44 and 32 (compact)") {
                HStack(spacing: theme.spacing.sm) {
                    Button("Sleep sounds") {}.buttonStyle(.glassCapsule)
                    Button("Turn on") {}.buttonStyle(.glassCapsule(.compact))
                }
            }
            sample("Icon circle · 36 in a 44 hit area") {
                HStack(spacing: theme.spacing.xxs) {
                    Button("Back", systemImage: "chevron.left") {}.buttonStyle(.iconCircle)
                    Button("Close", systemImage: "xmark") {}.buttonStyle(.iconCircle)
                    Button("Search", systemImage: "magnifyingglass") {}.buttonStyle(.iconCircle)
                    Button("Filter", systemImage: "line.3.horizontal.decrease") {}.buttonStyle(.iconCircle(badge: 2))
                    Button("Share", systemImage: "square.and.arrow.up") {}.buttonStyle(.iconCircle)
                    Button("About rarity", systemImage: "info.circle") {}.buttonStyle(.iconCircle)
                }
            }
            sample("Chips · 32") {
                HStack(spacing: theme.spacing.xs) {
                    Chip("All", count: 155, isSelected: filter == "All") { filter = "All" }
                    Chip("Earned", count: 23, isSelected: filter == "Earned") { filter = "Earned" }
                    Chip("Locked", count: 132, isSelected: filter == "Locked") { filter = "Locked" }
                }
            }
            sample("Small chips · 22") {
                ChipFlow(spacing: theme.spacing.xs) {
                    SmallChip(tier: .common)
                    SmallChip(tier: .legendary)
                    if let inferred = SmallChip(approximate: .inferred) { inferred }
                    if let placeholder = SmallChip(approximate: .placeholder) { placeholder }
                }
            }
            sample("Segmented capsule · 32 and 36") {
                VStack(alignment: .leading, spacing: theme.spacing.xs) {
                    SegmentedCapsule(selection: $colourway, options: ["Pressed", "Summer", "Autumn"]) { $0 }
                    SegmentedCapsule(selection: $mode, options: ["Sleep", "Focus"], size: .regular, fillsWidth: true) { $0 }
                }
            }
            sample("Text link") {
                TextLink("All insights") {}
            }
            sample("Progress · 2, 3 (owned bar, the one amber bar) and 4") {
                VStack(spacing: theme.spacing.sm) {
                    ProgressHairline(fraction: 0.64)
                    ProgressHairline(fraction: 23.0 / 155, height: 3, tint: theme.colors.reward)
                    ProgressHairline(fraction: 9.0 / 14, height: 4)
                }
            }
        }
    }

    private func sample<Content: View>(_ caption: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            DesignCaption(caption)
            content()
        }
    }
}

/// `SpecimenView` in every state and `BudGlyph` as it swells, on black.
struct DesignSpecimens: View {
    @Environment(\.theme) private var theme
    private let rubrum = LeafCatalog.shared.species(id: "rubrum") ?? LeafCatalog.shared.species[0]
    private let palmatum = LeafCatalog.shared.species(id: "palmatum") ?? LeafCatalog.shared.species[1]

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xl) {
            grid([
                ("Earned", SpecimenView(species: rubrum, colourway: .autumn, size: 64)),
                ("Next · 60%", SpecimenView(species: palmatum, colourway: .autumn, size: 64, state: .next(progress: 0.6))),
                ("Locked", SpecimenView(species: palmatum, colourway: .autumn, size: 64, state: .locked)),
                ("Waiting", SpecimenView(species: rubrum, colourway: .autumn, size: 64, state: .waiting)),
                ("Needs permission", SpecimenView(species: rubrum, colourway: .autumn, size: 64, state: .needsPermission)),
                ("Dormant", SpecimenView(species: rubrum, colourway: .autumn, size: 64, state: .dormant)),
            ])
            HStack(alignment: .bottom, spacing: theme.spacing.lg) {
                VStack(spacing: theme.spacing.xs) {
                    SpecimenView(species: rubrum, colourway: .frost, size: 96)
                    DesignCaption("96 · frost (Profile)")
                }
                VStack(spacing: theme.spacing.xs) {
                    SpecimenView(species: palmatum, colourway: .summer, size: 140)
                    DesignCaption("140 · detail scale")
                }
            }
            .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: theme.spacing.sm) {
                DesignGroupLabel("Buds")
                HStack(alignment: .bottom, spacing: theme.spacing.lg) {
                    bud(BudGlyph(waiting: false, progress: 0), "0%")
                    bud(BudGlyph(waiting: false, progress: 0.5), "50%")
                    bud(BudGlyph(waiting: false, progress: 1), "100%")
                    bud(BudGlyph(waiting: true, glow: .still), "Waiting")
                    bud(BudGlyph(waiting: true), "Breathing")
                }
            }
        }
        .padding(.horizontal, theme.spacing.listMargin)
        .padding(.bottom, theme.spacing.lg)
    }

    private func grid(_ items: [(String, SpecimenView)]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: theme.spacing.gutter), count: 3),
                  spacing: theme.spacing.lg) {
            ForEach(items.indices, id: \.self) { index in
                VStack(spacing: theme.spacing.xs) {
                    items[index].1
                    DesignCaption(items[index].0)
                }
            }
        }
    }

    private func bud(_ glyph: BudGlyph, _ caption: String) -> some View {
        VStack(spacing: theme.spacing.xs) {
            glyph.frame(width: 48, height: 48)
            DesignCaption(caption)
        }
    }
}

/// Every `MemberShare` state in its three layouts (spec §5.7).
struct DesignRarity: View {
    @Environment(\.theme) private var theme
    @Environment(\.mapleClock) private var clock

    var body: some View {
        let now = clock.now()
        let states: [(String, MemberShare)] = [
            ("loading", .loading),
            ("value", .value(display: "22%", asOf: now)),
            ("value · a bound", .value(display: "Under 1%", asOf: now)),
            ("stale", .stale(display: "38%", asOf: now.addingTimeInterval(-7 * 86_400))),
            ("notEnoughMembers", .notEnoughMembers(soFar: nil)),
            ("notEnoughMembers · 640 so far", .notEnoughMembers(soFar: 640)),
            ("neverFetched", .neverFetched),
            ("newSpecies", .newSpecies),
            ("notEarnableYet", .notEarnableYet),
        ]
        VStack(alignment: .leading, spacing: theme.spacing.xl) {
            ForEach(states.indices, id: \.self) { index in
                let (name, share) = states[index]
                VStack(alignment: .leading, spacing: theme.spacing.sm) {
                    DesignGroupLabel(name)
                    MemberShareLabel(share: share, layout: .detail)
                        .frame(maxWidth: .infinity)
                    HStack(alignment: .firstTextBaseline) {
                        DesignCaption("tile")
                        Spacer()
                        MemberShareLabel(share: share, layout: .tile, pressedOn: now.addingTimeInterval(-6 * 86_400))
                    }
                    HStack(alignment: .firstTextBaseline) {
                        DesignCaption("inline")
                        Spacer()
                        MemberShareLabel(share: share, layout: .inline)
                    }
                }
            }
        }
        .padding(.horizontal, theme.spacing.listMargin)
        .padding(.bottom, theme.spacing.lg)
    }
}

/// Every Herbarium tile variant (spec §5.5), drawn by the Herbarium's own `LeafCell` in its 3-column grid at the
/// real cell size, then the 72pt row the grid switches to at accessibility text sizes.
struct DesignLeafCells: View {
    @Environment(\.theme) private var theme
    @Environment(\.season) private var season

    var body: some View {
        let cells = DesignCellFixtures.cells(season: season)
        VStack(alignment: .leading, spacing: theme.spacing.xl) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: theme.spacing.gutter, alignment: .top), count: 3),
                      spacing: theme.spacing.lg) {
                ForEach(cells, id: \.caption) { cell in
                    VStack(spacing: theme.spacing.xs) {
                        LeafCell(cell.model)
                        DesignCaption(cell.caption)
                    }
                }
            }
            VStack(alignment: .leading, spacing: theme.spacing.sm) {
                DesignGroupLabel("Row · accessibility sizes")
                VStack(spacing: theme.spacing.gutter) {
                    ForEach(cells.prefix(3), id: \.caption) { cell in
                        LeafCell(cell.model, layout: .row)
                    }
                }
            }
        }
        .padding(.horizontal, theme.spacing.gridMargin)
        .padding(.bottom, theme.spacing.lg)
    }
}

/// Fixed leaves in each tile state, so the section never depends on the member's own collection.
private enum DesignCellFixtures {
    struct Cell {
        let caption: String
        let model: LeafCellModel
    }

    static func cells(season: Season) -> [Cell] {
        let day = Date(timeIntervalSince1970: 1_791_115_200) // 4 Oct 2026
        let fixtures: [(String, HerbariumEntry?)] = [
            ("Earned · share", entry("rubrum", state: .earned(unlock("rubrum", .autumn, day)),
                                    share: .value(display: "38%", asOf: .now))),
            ("Earned · unseen", entry("palmatum", state: .earned(unlock("palmatum", .summer, day, seen: false)),
                                     unseen: true)),
            ("Earned · ≈", entry("binzayedii", state: .earned(unlock("binzayedii", .frost, day)),
                                share: .value(display: "0.4%", asOf: .now))),
            ("Waiting", entry("japonicum", state: .waiting(unlock("japonicum", .autumn, day)))),
            ("Next", entry("sieboldianum", current: 9, next: true)),
            ("Next · ≈", entry("zarei", current: 120, next: true)),
            ("Locked", entry("amamiense")),
            ("Needs permission", entry("campestre", availability: .needsAppleHealth)),
            ("Dormant", entry("griseum", availability: .dormant, share: .notEarnableYet)),
        ]
        return fixtures.compactMap { caption, entry in
            entry.map { Cell(caption: caption, model: LeafCellModel($0, season: season)) }
        }
    }

    private static func unlock(_ id: String, _ colourway: LeafColourway, _ day: Date, seen: Bool = true) -> LeafUnlock {
        LeafUnlock(speciesID: id, date: day, season: .autumn, colourway: colourway, revealed: true, seen: seen)
    }

    private static func entry(
        _ id: String, state: LeafState = .locked, availability: LeafAvailability = .available, current: Double = 0,
        next: Bool = false, unseen: Bool = false, share: MemberShare = .notEnoughMembers(soFar: nil)
    ) -> HerbariumEntry? {
        guard let species = LeafCatalog.shared.species(id: id),
              let rung = RewardCatalog.shared.reward(forSpecies: id) else { return nil }
        let progress = LeafProgress(speciesID: id, category: rung.categoryID, threshold: rung.threshold, tier: rung.tier,
                                    current: current, availability: availability, state: state, estimatedDays: 5)
        return HerbariumEntry(species: species, progress: progress, rule: rung.unlockText, isNextRung: next,
                              isUnseen: unseen, share: share, opensNow: true)
    }
}
#endif
