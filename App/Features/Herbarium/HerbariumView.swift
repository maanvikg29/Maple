import SwiftUI
import MapleCore
import MapleDesign

/// Scaffold: replaced by the Herbarium from docs/design/spec.md §5. Shows every species, drawn natively.
struct HerbariumView: View {
    @Environment(\.theme) private var theme
    @Environment(\.season) private var season
    private let species = LeafCatalog.shared.species

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: theme.spacing.gutter), count: 3),
                      spacing: theme.spacing.gutter) {
                ForEach(species) { species in
                    VStack(spacing: theme.spacing.xs) {
                        LeafView(species, fill: .colourway(.autumn))
                            .frame(width: 64, height: 64)
                        Text(species.displayName)
                            .font(species.common.isEmpty ? MapleFont.scientific(.footnote) : MapleFont.tileName)
                            .foregroundStyle(theme.colors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .padding(.vertical, theme.spacing.sm)
                }
            }
            .padding(.horizontal, theme.spacing.gridMargin)
        }
        .background(theme.colors.background)
        .navigationTitle("Herbarium")
    }
}
