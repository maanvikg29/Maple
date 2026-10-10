// The MapleDesign component sheet (docs/design/spec.md §6, §7.3): every component in every state on the real
// #05070D background, at the default text size and at AX3, plus Increase Contrast.
//
//   SIMULATOR="iPhone 17" Scripts/snapshot-ios.sh Scripts/snapshot/ComponentScenes.swift [output-dir] [filter]
//   Scripts/snapshot.sh Scripts/snapshot/ComponentScenes.swift [output-dir]       (macOS: Mac type sizes)
//
// Render in the simulator to judge type: macOS maps text styles to its own sizes and has no Dynamic Type, so
// the -ax3 scenes only differ there. ImageRenderer cannot draw Liquid Glass (glass views render empty), so the
// sheet draws glass as its Reduce Transparency fallback (solid surface2, same border), and it falls back from
// SF Rounded to SF Pro. Compiled together with MapleCore + MapleDesign; not part of the app.
import Foundation
import SwiftUI

@MainActor
func snapshotScenes() -> [SnapshotScene] {
    var scenes: [SnapshotScene] = []
    for (suffix, size) in [("", DynamicTypeSize.large), ("-ax3", .accessibility3)] {
        let large = size.isAccessibilitySize
        scenes += [
            SnapshotScene("components-actions\(suffix)", size: CGSize(width: 402, height: large ? 1500 : 900)) {
                ComponentSheet { ActionsSheet() }.environment(\.dynamicTypeSize, size)
            },
            SnapshotScene("components-selection\(suffix)", size: CGSize(width: 402, height: large ? 1300 : 760)) {
                ComponentSheet { SelectionSheet() }.environment(\.dynamicTypeSize, size)
            },
            SnapshotScene("components-surfaces\(suffix)", size: CGSize(width: 402, height: large ? 1100 : 760)) {
                ComponentSheet { SurfacesSheet() }.environment(\.dynamicTypeSize, size)
            },
            SnapshotScene("components-specimens\(suffix)", size: CGSize(width: 402, height: 1420)) {
                ComponentSheet { SpecimensSheet() }.environment(\.dynamicTypeSize, size)
            },
            SnapshotScene("components-buds\(suffix)", size: CGSize(width: 402, height: 640)) {
                ComponentSheet { BudsSheet() }.environment(\.dynamicTypeSize, size)
            },
            SnapshotScene("components-membershare\(suffix)", size: CGSize(width: 402, height: large ? 3400 : 1320)) {
                ComponentSheet { MemberShareSheet() }.environment(\.dynamicTypeSize, size)
            },
            SnapshotScene("components-numbers\(suffix)", size: CGSize(width: 402, height: large ? 900 : 620)) {
                ComponentSheet { NumbersSheet() }.environment(\.dynamicTypeSize, size)
            },
        ]
    }
    scenes += [
        SnapshotScene("components-selection-contrast", size: CGSize(width: 402, height: 760)) {
            ComponentSheet { SelectionSheet() }.environment(\.theme, .mapleIncreasedContrast)
        },
        SnapshotScene("components-surfaces-contrast", size: CGSize(width: 402, height: 760)) {
            ComponentSheet { SurfacesSheet() }.environment(\.theme, .mapleIncreasedContrast)
        },
        SnapshotScene("components-specimens-winter", size: CGSize(width: 402, height: 1420)) {
            ComponentSheet { SpecimensSheet() }.environment(\.season, .winter)
        },
    ]
    return scenes
}

// MARK: - Sheet chrome

/// The black page every sheet sits on, with glass drawn as its solid fallback.
private struct ComponentSheet<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            content
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.maple.colors.background)
        .environment(\.drawsGlassAsSolid, true)
    }
}

/// A sheet annotation (review only, not a Maple style).
private struct Note: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .foregroundStyle(Color(hex: 0x5A6680))
            .dynamicTypeSize(.large)
    }
}

private struct Group2<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Note(title)
            content
        }
    }
}

private let catalog = LeafCatalog.shared
private func leaf(_ id: String) -> LeafSpecies { catalog.species(id: id)! }

// MARK: - Actions

private struct ActionsSheet: View {
    var body: some View {
        Group2(title: "MoonlightButtonStyle · normal / dimmed / disabled") {
            VStack(spacing: 12) {
                Button("Open your new leaf") {}.buttonStyle(.moonlight)
                Button("Start wind-down") {}.buttonStyle(.moonlight(dimmed: true))
                Button("Start focus") {}.buttonStyle(.moonlight).disabled(true)
            }
        }
        Group2(title: "Primary over the evening sky (dimmed)") {
            ZStack {
                LinearGradient(
                    stops: [
                        .init(color: Color(hex: 0x05070D), location: 0),
                        .init(color: Color(hex: 0x0B1426), location: 0.55),
                        .init(color: Color(hex: 0x05070D), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                Button("Start wind-down") {}.buttonStyle(.moonlight(dimmed: true)).padding(.horizontal, 0)
            }
            .frame(height: 120)
        }
        Group2(title: "GlassCapsuleStyle · regular / compact / disabled") {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { glassCapsules }
                VStack(alignment: .leading, spacing: 0) { glassCapsules }
            }
        }
        Group2(title: "IconCircleStyle · 36pt in a 44pt target; filter badge") {
            HStack(spacing: 4) {
                Button("Back", systemImage: "chevron.left") {}.buttonStyle(.iconCircle)
                Button("Close", systemImage: "xmark") {}.buttonStyle(.iconCircle)
                Button("Share", systemImage: "square.and.arrow.up") {}.buttonStyle(.iconCircle)
                Button("Search", systemImage: "magnifyingglass") {}.buttonStyle(.iconCircle)
                Button("Filter", systemImage: "line.3.horizontal.decrease") {}.buttonStyle(.iconCircle(badge: 2))
                Button("About rarity", systemImage: "info.circle") {}.buttonStyle(.iconCircle)
            }
            HStack(spacing: 4) {
                Button("Less", systemImage: "minus") {}.buttonStyle(.iconCircle)
                Text("25m")
                    .font(.system(size: 22, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.maple.colors.textPrimary)
                    .frame(width: 120, height: 44)
                    .glassSurface(in: Capsule(style: .continuous))
                Button("More", systemImage: "plus") {}.buttonStyle(.iconCircle)
                Button("Play", systemImage: "play.fill") {}.buttonStyle(.iconCircle)
            }
        }
        Group2(title: "TextLink · with and without chevron") {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) { textLinks }
                VStack(alignment: .leading, spacing: 0) { textLinks }
            }
        }
    }

    @ViewBuilder private var glassCapsules: some View {
        Button("Sleep sounds") {}.buttonStyle(.glassCapsule)
        Button("Turn on") {}.buttonStyle(.glassCapsule(.compact))
        Button("Open") {}.buttonStyle(.glassCapsule).disabled(true)
    }

    @ViewBuilder private var textLinks: some View {
        TextLink("All insights") {}
        TextLink("How it works") {}
        TextLink("Not now", chevron: false) {}
    }
}

// MARK: - Selection

private struct SelectionSheet: View {
    @State private var colourway = "Pressed"
    @State private var mode = "Sleep"

    var body: some View {
        Group2(title: "Chip · selected / unselected, with counts (ChipFlow)") {
            ChipFlow(spacing: 8, lineSpacing: 0) {
                Chip("All", count: 155, isSelected: true) {}
                Chip("Earned", count: 23, isSelected: false) {}
                Chip("Locked", count: 132, isSelected: false) {}
                Chip("East Asia", isSelected: false) {}
                Chip("Europe", isSelected: true) {}
                Chip("Himalaya", isSelected: false) {}
            }
        }
        Group2(title: "SmallChip · tiers, approximate (dashed), regions (ChipFlow)") {
            ChipFlow {
                ForEach(RewardTier.allCases, id: \.self) { SmallChip(tier: $0) }
            }
            ChipFlow {
                SmallChip(approximate: .inferred)
                SmallChip(approximate: .placeholder)
                SmallChip("North America")
                SmallChip("Mexico & Central America")
            }
            Note("Detail: tier + approximate, centred")
            ChipFlow(alignment: .center) {
                SmallChip(tier: .rare)
                SmallChip(approximate: .inferred)
            }
            .frame(maxWidth: .infinity)
        }
        Group2(title: "SegmentedCapsule · compact 32pt, each selection") {
            VStack(alignment: .center, spacing: 4) {
                ForEach(["Pressed", "Summer", "Autumn"], id: \.self) { selected in
                    SegmentedCapsule(selection: .constant(selected), options: ["Pressed", "Summer", "Autumn"]) { $0 }
                }
                Text("Pressed in autumn")
                    .font(MapleFont.footnote)
                    .foregroundStyle(Theme.maple.colors.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
        Group2(title: "SegmentedCapsule · regular 36pt, fills width") {
            SegmentedCapsule(selection: $mode, options: ["Sleep", "Focus"], size: .regular, fillsWidth: true) { $0 }
        }
    }
}

// MARK: - Surfaces and progress

private struct SurfacesSheet: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Group2(title: "Levels 0 / 1 / 2 (radius 20, 20, 40)") {
            HStack(spacing: 12) {
                tile("Level 0").surface(.level0, radius: 20)
                tile("Level 1").surface(.level1, radius: 20)
                tile("Level 2").surface(.level2, radius: 40)
            }
            tile("Level 1 · pressed").frame(maxWidth: .infinity).surface(.level1, radius: 28, pressed: true)
        }
        Group2(title: "ProgressHairline · 2pt at 0, 1/540, 0.35, 0.79, 1") {
            VStack(spacing: 14) {
                ForEach([0, 1.0 / 540, 0.35, 0.79, 1], id: \.self) { fraction in
                    ProgressHairline(fraction: fraction)
                }
            }
        }
        Group2(title: "3pt owned bar (reward) · 4pt detail · season tints") {
            VStack(spacing: 14) {
                ProgressHairline(fraction: 23.0 / 155, height: 3, tint: theme.colors.reward)
                ProgressHairline(fraction: 9.0 / 14, height: 4)
                ForEach(Season.allCases, id: \.self) { season in
                    HStack(spacing: 12) {
                        Text(season.rawValue.capitalized)
                            .font(MapleFont.contextEmphasis)
                            .foregroundStyle(theme.colors.seasonTint(season))
                            .frame(width: 70, alignment: .leading)
                        ProgressHairline(fraction: 0.6).environment(\.season, season)
                    }
                }
            }
        }
        Group2(title: "Next-leaf row composition (32pt skeleton + hairline)") {
            HStack(spacing: 12) {
                SpecimenView(species: leaf("rubrum"), colourway: .autumn, size: 32, state: .next(progress: 11.0 / 14))
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Red maple").font(MapleFont.contextEmphasis).foregroundStyle(theme.colors.textPrimary)
                        Spacer()
                        Text("3 nights").font(MapleFont.footnote.monospacedDigit()).foregroundStyle(theme.colors.textSecondary)
                    }
                    ProgressHairline(fraction: 11.0 / 14)
                }
            }
            .frame(height: 56)
        }
    }

    private func tile(_ title: String) -> some View {
        Text(title)
            .font(MapleFont.tileName)
            .foregroundStyle(theme.colors.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 96)
    }
}

// MARK: - Specimens

private struct SpecimensSheet: View {
    @Environment(\.theme) private var theme

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        Group2(title: "64pt in Level-1 tiles · earned (autumn, summer, spring, frost) / waiting") {
            LazyVGrid(columns: columns, spacing: 10) {
                cell(leaf("rubrum"), .autumn, .earned, meta: "22% have it")
                cell(leaf("palmatum"), .summer, .earned, meta: "4 Oct")
                cell(leaf("griseum"), .spring, .earned, meta: "38% have it")
                cell(leaf("saccharum"), .frost, .earned, meta: "12 Jan")
                cell(leaf("negundo"), .autumn, .earned, meta: "Under 1% have it")
                cell(leaf("davidii"), .autumn, .waiting, meta: "Waiting")
            }
        }
        Group2(title: "64pt on black · next 0.15 / 0.5 / 0.85 · locked / needs permission / dormant") {
            LazyVGrid(columns: columns, spacing: 10) {
                bare(leaf("circinatum"), .next(progress: 0.15), meta: "1 of 7")
                bare(leaf("macrophyllum"), .next(progress: 0.5), meta: "9 of 18")
                bare(leaf("japonicum"), .next(progress: 0.85), meta: "11 of 13")
                bare(leaf("cissifolium"), .locked, meta: "60 on time")
                bare(leaf("pentaphyllum"), .needsPermission, meta: "Needs Screen Time")
                bare(leaf("albopurpurascens"), .dormant, meta: "Not earnable yet")
            }
        }
        Group2(title: "120pt (detail scale) · earned / next 0.6 / locked · then 200pt") {
            HStack(alignment: .top, spacing: 0) {
                SpecimenView(species: leaf("rubrum"), colourway: .autumn, size: 120)
                SpecimenView(species: leaf("palmatum"), colourway: .autumn, size: 120, state: .next(progress: 0.6))
                SpecimenView(species: leaf("negundo"), colourway: .autumn, size: 120, state: .locked)
            }
            .frame(maxWidth: .infinity)
            SpecimenView(species: leaf("saccharum"), colourway: .autumn, size: 200)
                .frame(maxWidth: .infinity)
                .frame(height: 300)
        }
    }

    private func cell(_ species: LeafSpecies, _ colourway: LeafColourway, _ state: SpecimenState, meta: String) -> some View {
        VStack(spacing: 0) {
            SpecimenView(species: species, colourway: colourway, size: 64, state: state)
                .frame(height: 100)
            Text(state == .waiting ? "New leaf" : species.displayName)
                .font(species.common.isEmpty && state != .waiting ? MapleFont.scientific(.footnote) : MapleFont.tileName)
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.85)
            Text(meta)
                .font(MapleFont.tileMeta)
                .foregroundStyle(theme.colors.textSecondary)
                .lineLimit(1)
                .padding(.top, 4)
        }
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .surface(.level1, radius: 20)
    }

    private func bare(_ species: LeafSpecies, _ state: SpecimenState, meta: String) -> some View {
        VStack(spacing: 0) {
            SpecimenView(species: species, colourway: .autumn, size: 64, state: state)
                .frame(height: 100)
            Text(species.displayName)
                .font(species.common.isEmpty ? MapleFont.scientific(.footnote) : MapleFont.tileName)
                .foregroundStyle(theme.colors.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.85)
            Text(meta)
                .font(MapleFont.tileMeta)
                .foregroundStyle(theme.colors.textSecondary)
                .lineLimit(1)
                .padding(.top, 4)
            if case .next(let progress) = state {
                ProgressHairline(fraction: progress).frame(width: 56).padding(.top, 6)
            }
        }
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Buds

private struct BudsSheet: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Group2(title: "BudGlyph growing · progress 0 / 0.33 / 0.66 / 1 (48pt)") {
            HStack(spacing: 20) {
                ForEach([0, 0.33, 0.66, 1], id: \.self) { progress in
                    BudGlyph(waiting: false, progress: progress).frame(width: 48, height: 48)
                }
            }
        }
        Group2(title: "Waiting · 32pt row (still) · 48pt tile (still) · 96pt reveal") {
            HStack(alignment: .center, spacing: 28) {
                BudGlyph(waiting: true, glow: .still).frame(width: 32, height: 32)
                BudGlyph(waiting: true, glow: .still).frame(width: 48, height: 48)
                BudGlyph(waiting: true).frame(width: 96, height: 96)
            }
            .padding(.vertical, 12)
        }
        Group2(title: "Next-leaf row, waiting variant") {
            HStack(spacing: 12) {
                BudGlyph(waiting: true, glow: .still).frame(width: 32, height: 32)
                Text("A new leaf is waiting")
                    .font(MapleFont.contextEmphasis)
                    .foregroundStyle(theme.colors.textPrimary)
            }
            .frame(height: 56)
        }
        Group2(title: "BudShape parts · back / front / whole in budNeutral") {
            HStack(spacing: 28) {
                BudShape(.back).fill(theme.colors.textSecondary.opacity(0.5)).frame(width: 30, height: 48)
                BudShape(.front).fill(theme.colors.textSecondary.opacity(0.5)).frame(width: 30, height: 48)
                BudShape(.whole).fill(theme.colors.budNeutral).frame(width: 30, height: 48)
                BudShape(.whole).fill(theme.colors.budNeutral).frame(width: 6, height: 9)
            }
        }
    }
}

// MARK: - Member share

private struct MemberShareSheet: View {
    private static let asOf = Date(timeIntervalSince1970: 1_791_000_000) // early Oct 2026
    private static let pressed = Date(timeIntervalSince1970: 1_791_100_000)

    private let states: [(String, MemberShare)] = [
        ("loading", .loading),
        ("value", .value(display: "22%", asOf: asOf)),
        ("value (bound)", .value(display: "Under 1%", asOf: asOf)),
        ("stale", .stale(display: "22%", asOf: asOf)),
        ("notEnoughMembers(nil)", .notEnoughMembers(soFar: nil)),
        ("notEnoughMembers(640)", .notEnoughMembers(soFar: 640)),
        ("neverFetched", .neverFetched),
        ("newSpecies", .newSpecies),
        ("notEarnableYet", .notEarnableYet),
    ]

    var body: some View {
        ForEach(states, id: \.0) { name, share in
            VStack(alignment: .leading, spacing: 8) {
                Note(name)
                MemberShareLabel(share: share, layout: .detail)
                    .frame(maxWidth: .infinity)
                MemberShareLabel(share: share, layout: .inline)
                    .frame(maxWidth: .infinity)
                MemberShareLabel(share: share, layout: .tile, pressedOn: Self.pressed)
            }
        }
        .environment(\.locale, Locale(identifier: "en_GB"))
    }
}

// MARK: - Numbers

private struct NumbersSheet: View {
    var body: some View {
        Group2(title: "StatNumber .hero 64 (units 32) · clock time") {
            HStack(alignment: .firstTextBaseline, spacing: 28) {
                StatNumber([.value("1"), .unit("h"), .value("20"), .unit("m")], size: .hero,
                           accessibilityText: "One hour twenty minutes")
                StatNumber("07:00", size: .hero)
            }
        }
        Group2(title: ".score 48 · .stat 34 · .total 28 · .inline 17") {
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                StatNumber("72", size: .score)
                StatNumber("23", size: .stat)
                StatNumber([.value("41"), .unit("h")], size: .total)
                StatNumber("14", size: .inline)
            }
        }
    }
}
