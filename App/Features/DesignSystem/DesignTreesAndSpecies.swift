#if DEBUG
import SwiftUI
import MapleCore
import MapleDesign

// MARK: - Trees

/// One row of the tree matrix: a season and phase (or the quiet tree) across 0, 1, 5, 15, 40, 90 and 155 species.
struct DesignTreeRow: Identifiable, Hashable {
    let season: Season
    let phase: NowPhase
    let vitality: Double

    var id: String { "\(season.rawValue)-\(phase.rawValue)-\(vitality)" }

    var title: String {
        let base = "\(season.rawValue.capitalized) · \(DesignTreeRow.phaseName(phase))"
        return vitality < 0.55 ? "Quiet · \(base.lowercased())" : base
    }

    /// Every season in every phase, then the quiet tree (vitality 0.45, spec §4.8).
    static let all: [DesignTreeRow] = Season.allCases.flatMap { season in
        NowPhase.allCases.map { DesignTreeRow(season: season, phase: $0, vitality: 1) }
    } + [DesignTreeRow(season: .autumn, phase: .evening, vitality: 0.45)]

    /// Species counts and the structural growth the reward pacing pairs them with (spec §4.5).
    static let sizes: [(species: Int, growth: Double)] = [(0, 0), (1, 0), (5, 0.05), (15, 0.14), (40, 0.34), (90, 0.70), (155, 1.0)]

    static func phaseName(_ phase: NowPhase) -> String {
        switch phase {
        case .morning: "morning"
        case .day: "day"
        case .evening: "evening"
        case .windDown: "wind-down"
        case .night: "night"
        }
    }

    /// Species in a plausible unlock order: each rung's day at its category's design pace.
    static let unlockOrder: [String] = RewardCatalog.shared.assignments
        .sorted { a, b in
            let da = a.threshold / RewardCategoryInfo(a.categoryID).designPace
            let db = b.threshold / RewardCategoryInfo(b.categoryID).designPace
            return da != db ? da < db : RewardCategoryInfo(a.categoryID).order < RewardCategoryInfo(b.categoryID).order
        }
        .map(\.speciesID)

    /// A fixed seed and instant, so every frame is reproducible and still (no timeline runs).
    static let seed: UInt64 = 0x00C0_FFEE_0A1E_5EED
    static let time = Date(timeIntervalSinceReferenceDate: 812_000_013)

    func model(species count: Int, growth: Double) -> TreeSceneModel {
        let ids = Array(Self.unlockOrder.prefix(count))
        let next = Array(Self.unlockOrder.dropFirst(count).prefix(3))
        return TreeSceneModel(
            seed: Self.seed,
            growth: growth,
            species: ids.map { TreeSceneModel.Leaf(speciesID: $0, pressed: .autumn) },
            buds: zip(next, [0.72, 0.4, 0.15]).map { TreeSceneModel.Bud(speciesID: $0, progress: $1) },
            featured: count > 3 ? ids[2] : nil,
            season: season,
            seasonDay: season == .spring ? 12 : 40,
            phase: phase,
            vitality: vitality,
            time: Self.time
        )
    }
}

struct DesignTreeRowView: View {
    @Environment(\.theme) private var theme
    let row: DesignTreeRow
    private static let tileWidth: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            DesignGroupLabel(row.title)
                .padding(.horizontal, theme.spacing.listMargin)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: theme.spacing.gutter) {
                    ForEach(DesignTreeRow.sizes, id: \.species) { size in
                        VStack(spacing: theme.spacing.xxs) {
                            // The 402 × 560 scene at 120pt wide, cropped to y 100–520, where the tallest crown
                            // and the ground sit, so each tile is mostly tree rather than sky.
                            MapleTreeScene(model: row.model(species: size.species, growth: size.growth))
                                .frame(width: Self.tileWidth, height: Self.tileWidth * 560 / 402)
                                .padding(.top, -Self.tileWidth * 100 / 402)
                                .frame(width: Self.tileWidth, height: Self.tileWidth * 420 / 402, alignment: .top)
                                .clipShape(RoundedRectangle(cornerRadius: theme.radius.tile, style: .continuous))
                            DesignCaption(size.species == 1 ? "1 species" : "\(size.species) species")
                        }
                    }
                }
            }
            .contentMargins(.horizontal, theme.spacing.listMargin, for: .scrollContent)
            .scrollIndicators(.hidden)
        }
        .padding(.bottom, theme.spacing.lg)
    }
}

// MARK: - Species

/// The colourway names above the species list.
struct DesignSpeciesHeader: View {
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            ForEach(DesignSpeciesRow.colourways, id: \.self) { colourway in
                DesignCaption(colourway.displayName)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(width: DesignSpeciesRow.columnWidth)
            }
        }
        .padding(.horizontal, theme.spacing.listMargin)
        .padding(.bottom, theme.spacing.xs)
    }
}

/// One species: its names, an "≈" chip for approximate drawings (i and u), and the leaf in four colourways.
struct DesignSpeciesRow: View {
    @Environment(\.theme) private var theme
    let species: LeafSpecies

    static let colourways: [LeafColourway] = [.summer, .autumn, .spring, .frost]
    static let leafSize: CGFloat = 40
    /// Each colourway's column: the leaf centred, with room for its label above.
    static let columnWidth: CGFloat = 52

    var body: some View {
        HStack(alignment: .center, spacing: theme.spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(species.displayName)
                    .font(species.common.isEmpty ? MapleFont.scientific(.footnote) : MapleFont.tileName)
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if !species.common.isEmpty {
                    Text(species.name)
                        .font(MapleFont.scientific(.caption))
                        .foregroundStyle(theme.colors.textSecondary)
                        .lineLimit(1)
                }
                if let chip = SmallChip(approximate: species.confidence) {
                    chip.padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 0) {
                ForEach(Self.colourways, id: \.self) { colourway in
                    leaf(colourway)
                        .frame(width: Self.columnWidth)
                }
            }
        }
        .padding(.horizontal, theme.spacing.listMargin)
        .padding(.vertical, theme.spacing.xs)
    }

    private func leaf(_ colourway: LeafColourway) -> some View {
        LeafView(species, fill: .colourway(colourway))
            .frame(width: Self.leafSize, height: Self.leafSize)
            .overlay {
                if colourway.hasFrostRim(for: species) {
                    LeafView(species, style: .skeleton(stroke: .white.opacity(0.4), vein: .clear, outlineWidth: 0.75))
                        .frame(width: Self.leafSize, height: Self.leafSize)
                }
            }
            .accessibilityHidden(true)
    }
}
#endif
