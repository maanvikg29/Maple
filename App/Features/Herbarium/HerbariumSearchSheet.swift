import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// The Search sheet (spec §5.4, `.large`, its own navigation stack): finds leaves by common name, scientific name,
/// series or range words, and shows them as tiles in the Herbarium's grid. A result pushes its detail here.
struct HerbariumSearchSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.season) private var season
    @Environment(\.mapleClock) private var clock
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss
    @Environment(CollectionStore.self) private var collection
    @Environment(LeafShareStore.self) private var shares

    @State private var query: String
    /// The keyboard comes up for a new search; a search opened with a query shows its results.
    @State private var isSearching: Bool
    @State private var detail: LeafRoute?
    @Namespace private var zoom

    init(query: String = "") {
        _query = State(initialValue: query)
        _isSearching = State(initialValue: query.isEmpty)
    }

    var body: some View {
        NavigationStack {
            let entries = HerbariumEntries(collection: collection, shares: shares, at: clock.now()).entries
            let results = HerbariumSearch.results(entries, query: query)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        hint("Search all \(entries.count) leaves by name, series or place.")
                    } else if results.isEmpty {
                        hint("No leaves match “\(query)”.")
                    } else {
                        Text(results.count == 1 ? "1 leaf" : "\(results.count) leaves")
                            .font(MapleFont.footnote)
                            .foregroundStyle(theme.colors.textSecondary)
                            .padding(.bottom, theme.spacing.sm)
                            .accessibilityAddTraits(.isHeader)
                        grid(results)
                    }
                }
                .padding(.horizontal, theme.spacing.gridMargin)
                .padding(.top, theme.spacing.md)
                .padding(.bottom, theme.spacing.xl)
            }
            .scrollDismissesKeyboard(.immediately)
            .background(theme.colors.background)
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .searchable(text: $query, isPresented: $isSearching, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Name, series or place")
            .navigationDestination(item: $detail) { route in
                LeafDetailView(speciesID: route.speciesID)
                    .navigationTransition(.zoom(sourceID: route.id, in: zoom))
            }
        }
        .presentationDetents([.large])
        .presentationBackground(theme.colors.background)
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(MapleFont.callout)
            .foregroundStyle(theme.colors.textSecondary)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(.top, theme.spacing.xl)
    }

    @ViewBuilder
    private func grid(_ results: [HerbariumEntry]) -> some View {
        let columns = HerbariumColumns(dynamicTypeSize).count
        if columns == 1 {
            LazyVStack(spacing: theme.spacing.gutter) {
                ForEach(results) { cell($0, layout: .row) }
            }
        } else {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: theme.spacing.gutter, alignment: .top), count: columns),
                spacing: theme.spacing.gutter
            ) {
                ForEach(results) { cell($0, layout: .tile) }
            }
        }
    }

    private func cell(_ entry: HerbariumEntry, layout: LeafCell.Layout) -> some View {
        Button {
            detail = LeafRoute(speciesID: entry.id, source: "search")
        } label: {
            LeafCell(LeafCellModel(entry, season: season), layout: layout)
        }
        .buttonStyle(.leafCell)
        .matchedTransitionSource(id: "search/\(entry.id)", in: zoom)
    }
}
