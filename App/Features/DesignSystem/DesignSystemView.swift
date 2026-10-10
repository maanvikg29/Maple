#if DEBUG
import SwiftUI
import MapleCore
import MapleDesign

/// The sections of the design system screen, in page order.
enum DesignSystemSection: String, CaseIterable, Identifiable {
    case colours, surfaces, type, controls, specimens, rarity, cells, trees, species

    var id: String { rawValue }

    var title: String {
        switch self {
        case .colours: "Colours"
        case .surfaces: "Surfaces"
        case .type: "Type"
        case .controls: "Controls"
        case .specimens: "Specimens and buds"
        case .rarity: "Rarity"
        case .cells: "Leaf cells"
        case .trees: "Trees"
        case .species: "Species"
        }
    }

    var caption: String {
        switch self {
        case .colours: "Every token in the current theme, with its value and the one job it does."
        case .surfaces: "Black does the work. Level 2 is for the share card alone."
        case .type: "SF Rounded for headings and numbers, SF Pro for reading, New York italic for scientific names."
        case .controls: "On black and on the evening sky, where they live."
        case .specimens: "One specimen grammar for every leaf larger than 40pt."
        case .rarity: "Every MemberShare state in the detail, tile and inline layouts."
        case .cells: "Every Herbarium tile variant."
        case .trees: "0 to 155 species in each season and phase, then quiet. Still frames at one seed."
        case .species: "All 155, in summer, autumn, spring and frost. ≈ marks approximate drawings."
        }
    }

    /// `-MapleDemoDesignSection <section>` scrolls here when the screen opens (docs/debug-launch-arguments.md).
    static var launchTarget: DesignSystemSection? {
        UserDefaults.standard.string(forKey: "MapleDemoDesignSection").flatMap(Self.init(rawValue:))
    }
}

/// DEBUG only: Maple's design system on one page (spec §8.10). Sections are separated by hairlines, never boxed.
/// The page is lazy, so the tree matrix and the 155 species are drawn only as they scroll in.
struct DesignSystemView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    DesignSystemIntro { section in
                        withAnimation(theme.motion.gentle) { proxy.scrollTo(section, anchor: .top) }
                    }
                    ForEach(DesignSystemSection.allCases) { section in
                        DesignSectionHeader(section: section)
                            .id(section)
                        content(section)
                    }
                }
                .padding(.bottom, theme.spacing.hero)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .task {
                guard let target = DesignSystemSection.launchTarget else { return }
                try? await Task.sleep(for: .milliseconds(600))
                proxy.scrollTo(target, anchor: .top)
            }
        }
        .background(theme.colors.background)
        .navigationTitle("Design system")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(removing: .title)
    }

    @ViewBuilder
    private func content(_ section: DesignSystemSection) -> some View {
        switch section {
        case .colours: DesignColours()
        case .surfaces: DesignSurfaces()
        case .type: DesignType()
        case .controls: DesignControls()
        case .specimens: DesignSpecimens()
        case .rarity: DesignRarity()
        case .cells: DesignLeafCells()
        case .trees:
            ForEach(DesignTreeRow.all) { row in
                DesignTreeRowView(row: row)
            }
        case .species:
            DesignSpeciesHeader()
            ForEach(LeafCatalog.shared.species) { species in
                DesignSpeciesRow(species: species)
            }
        }
    }
}

/// The page title, a line about the screen, and chips that jump to each section.
private struct DesignSystemIntro: View {
    @Environment(\.theme) private var theme
    let jump: (DesignSystemSection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xxs) {
            Text("Design system")
                .font(MapleFont.screenTitle)
                .tracking(-0.3)
                .foregroundStyle(theme.colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("DEBUG builds only. Tokens and components from the design spec, drawn live.")
                .font(MapleFont.footnote)
                .foregroundStyle(theme.colors.textSecondary)
            ChipFlow(spacing: theme.spacing.xs, lineSpacing: 0) {
                ForEach(DesignSystemSection.allCases) { section in
                    Chip(section.title, isSelected: false) { jump(section) }
                }
            }
            .padding(.top, theme.spacing.md)
        }
        .padding(.horizontal, theme.spacing.listMargin)
        .padding(.top, theme.spacing.xs)
        .padding(.bottom, theme.spacing.md)
    }
}

/// A 0.5pt hairline, then the section's title and what it shows.
struct DesignSectionHeader: View {
    @Environment(\.theme) private var theme
    let section: DesignSystemSection

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xxs) {
            Rectangle()
                .fill(theme.colors.divider)
                .frame(height: 0.5)
                .padding(.bottom, theme.spacing.xl)
            Text(section.title)
                .font(MapleFont.sectionTitle)
                .foregroundStyle(theme.colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(section.caption)
                .font(MapleFont.footnote)
                .foregroundStyle(theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, theme.spacing.listMargin)
        .padding(.top, theme.spacing.lg)
        .padding(.bottom, theme.spacing.lg)
    }
}

/// A small sentence-case label above a group of samples inside a section.
struct DesignGroupLabel: View {
    @Environment(\.theme) private var theme
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(MapleFont.contextEmphasis)
            .foregroundStyle(theme.colors.textPrimary)
    }
}

/// A caption under a sample: what it is and its token or size.
struct DesignCaption: View {
    @Environment(\.theme) private var theme
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(MapleFont.tileMeta)
            .foregroundStyle(theme.colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
#endif
