import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// The 155-leaf collection (spec §5.3): the count and owned bar, "Your rarest", the Almost-there rail, the All /
/// Earned / Locked chips with the Group menu, and the grid in pinned sections. Every species is always drawn, so
/// a new member sees the whole collection as skeletons from the first day (§8.9).
struct HerbariumView: View {
    @Environment(\.theme) private var theme
    @Environment(\.season) private var season
    @Environment(\.mapleClock) private var clock
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @Environment(CollectionStore.self) private var collection
    @Environment(LeafShareStore.self) private var shares
    @Environment(AppRouter.self) private var router

    @State private var scope: HerbariumScope = .all
    @State private var grouping: HerbariumGrouping = .category
    @State private var sort: HerbariumSort = .nextToEarn
    @State private var filters = HerbariumFilters()
    /// Sections opened with "Show more", remembered for the session.
    @State private var expanded: Set<String> = []
    @State private var sheet: HerbariumSheet?
    @State private var detail: LeafRoute?
    @State private var reveal: LeafRoute?
    /// The grid has scrolled under the status bar, which then gets the pinned headers' backing.
    @State private var isScrolled = false
    @Namespace private var zoom
    @Namespace private var rotor

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = clock.date(forTimeline: context.date)
            content(HerbariumEntries(collection: collection, shares: shares, at: now))
        }
        .herbariumBackdrop()
        .overlay(alignment: .top) { statusBarBacking }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .navigationDestination(item: $detail) { route in
            LeafDetailView(speciesID: route.speciesID, opening: route.opening)
                .navigationTransition(.zoom(sourceID: route.id, in: zoom))
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .filter: HerbariumFilterSheet(filters: $filters)
            case .search(let query): HerbariumSearchSheet(query: query)
            }
        }
        .fullScreenCover(item: $reveal) { route in
            RevealFlow(startingWith: route.speciesID)
        }
        .onAppear(perform: applyRouterRequest)
        .onChange(of: router.herbariumEarnedOnlyRequest) { applyRouterRequest() }
        #if DEBUG
        .task { presentDemo() }
        #endif
    }

    // MARK: Screen

    private func content(_ model: HerbariumEntries) -> some View {
        let sections = HerbariumLayout.sections(model.entries, grouping: grouping, sort: sort, scope: scope,
                                                filters: filters, expanded: expanded)
        let almost = collection.almostThere(at: model.now)
        return ScrollViewReader { proxy in
            ScrollView {
                page(model, almost: almost, sections: sections)
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 120
            } action: { _, scrolled in
                isScrolled = scrolled
            }
            #if DEBUG
            .task { await HerbariumDemo.scroll(proxy) }
            #endif
        }
        .accessibilityRotor("Earned leaves") {
            ForEach(model.entries.filter(\.isEarned)) { entry in
                AccessibilityRotorEntry(Text(entry.species.displayName), id: entry.id, in: rotor)
            }
        }
        .accessibilityRotor("Almost there") {
            ForEach(almost) { progress in
                AccessibilityRotorEntry(Text(LeafCatalog.shared.species(id: progress.speciesID)?.displayName ?? ""),
                                        id: "almost-\(progress.speciesID)", in: rotor)
            }
        }
    }

    private func page(_ model: HerbariumEntries, almost: [LeafProgress], sections: [HerbariumSection]) -> some View {
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
            header
                .padding(.horizontal, theme.spacing.gridMargin)
            count(model)
                .padding(.horizontal, theme.spacing.gridMargin)
                .padding(.top, theme.spacing.xs)
            almostThere(almost, phase: model.phase)
            controls(model)
                .padding(.horizontal, theme.spacing.gridMargin)
                .padding(.top, theme.spacing.xl)
                .padding(.bottom, theme.spacing.sm)
            if sections.isEmpty {
                noMatches
            } else {
                ForEach(sections) { section in
                    Section {
                        sectionBody(section)
                    } header: {
                        HerbariumSectionHeader(section, turnOn: turnOnAction(for: section.permission))
                    }
                }
            }
        }
        .padding(.bottom, theme.spacing.xl)
    }

    /// Above a pinned header, tiles would show through the status bar; once scrolled, the status bar gets the same
    /// backing as the headers. At rest it stays clear, so the season bloom reaches the top of the screen.
    private var statusBarBacking: some View {
        GeometryReader { proxy in
            let inset = proxy.safeAreaInsets.top
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                theme.colors.background.opacity(0.92)
            }
            .frame(height: inset)
            .offset(y: -inset)
        }
        .frame(height: 0)
        .opacity(isScrolled ? 1 : 0)
        .mapleAnimation(theme.motion.press, value: isScrolled)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 0) {
            Text("Herbarium")
                .font(MapleFont.screenTitle)
                .tracking(-0.3)
                .foregroundStyle(theme.colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 12)
            HStack(spacing: 0) {
                Button("Search", systemImage: "magnifyingglass") { sheet = .search("") }
                    .buttonStyle(.iconCircle)
                Button("Filter", systemImage: "line.3.horizontal.decrease") { sheet = .filter }
                    .buttonStyle(.iconCircle(badge: filters.activeCount))
            }
            // 36pt circles 8pt apart, inside their 44pt hit areas; the last one sits on the margin.
            .padding(.trailing, -4)
        }
        .frame(minHeight: 44)
    }

    private func count(_ model: HerbariumEntries) -> some View {
        let total = model.entries.count
        let owned = model.ownedCount
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                StatNumber("\(owned)", size: .stat)
                Text("of \(total)")
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(theme.colors.textSecondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(owned) of \(total) leaves")
            ProgressHairline(fraction: Double(owned) / Double(max(total, 1)), height: 3, tint: theme.colors.reward)
            if let rarest = model.rarest, case .value(let display, _) = rarest.share {
                Button {
                    detail = LeafRoute(speciesID: rarest.id, source: "rarest")
                } label: {
                    Text("Your rarest: \(rarest.species.displayName) · \(display)")
                        .font(MapleFont.footnote)
                        .foregroundStyle(theme.colors.textSecondary)
                        .frame(minHeight: 28)
                }
                .buttonStyle(.plain)
                .matchedTransitionSource(id: "rarest/\(rarest.id)", in: zoom)
                .padding(.top, -4)
            }
        }
    }

    // MARK: Almost there

    @ViewBuilder
    private func almostThere(_ leaves: [LeafProgress], phase: NowPhase) -> some View {
        // Hidden below 2 candidates (spec §5.3).
        if leaves.count >= 2 {
            VStack(alignment: .leading, spacing: theme.spacing.sm) {
                Text("Almost there")
                    .font(MapleFont.sectionTitle)
                    .foregroundStyle(theme.colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, theme.spacing.gridMargin)
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 10) {
                        ForEach(leaves) { almostCard($0, phase: phase, layout: .row) }
                    }
                    .padding(.horizontal, theme.spacing.gridMargin)
                } else {
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: theme.spacing.sm) {
                            ForEach(leaves) { almostCard($0, phase: phase, layout: .card) }
                        }
                        .padding(.horizontal, theme.spacing.gridMargin)
                    }
                    .scrollIndicators(.hidden)
                    .scrollClipDisabled()
                }
            }
            .padding(.top, theme.spacing.xl)
        }
    }

    @ViewBuilder
    private func almostCard(_ progress: LeafProgress, phase: NowPhase, layout: AlmostThereCard.Layout) -> some View {
        if let species = LeafCatalog.shared.species(id: progress.speciesID) {
            let source = "almost"
            Button {
                detail = LeafRoute(speciesID: species.id, source: source)
            } label: {
                AlmostThereCard(
                    species: species, fraction: progress.fraction,
                    colourway: LeafColourway.pressed(in: season, evergreen: species.evergreen),
                    remainder: HerbariumCopy.toGo(LeafRemainder(progress, phase: phase)), layout: layout
                )
            }
            .buttonStyle(.leafCell)
            .matchedTransitionSource(id: "\(source)/\(species.id)", in: zoom)
            .accessibilityRotorEntry(id: "almost-\(species.id)", in: rotor)
        }
    }

    // MARK: Controls

    @ViewBuilder
    private func controls(_ model: HerbariumEntries) -> some View {
        // One row up to the default text size; beyond it the chips wrap and the menu takes its own line.
        if dynamicTypeSize <= .large {
            HStack(spacing: theme.spacing.xs) {
                scopeChips(model)
                Spacer(minLength: 0)
                groupMenu
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ChipFlow(lineSpacing: 0) { scopeChips(model) }
                groupMenu
            }
        }
    }

    @ViewBuilder
    private func scopeChips(_ model: HerbariumEntries) -> some View {
        ForEach(HerbariumScope.allCases) { option in
            Chip(option.title, count: model.count(option), isSelected: scope == option) {
                withAnimation(reduceMotion ? nil : theme.motion.gentle) { scope = option }
            }
        }
    }

    private var groupMenu: some View {
        Menu {
            Section("Group by") {
                Picker("Group by", selection: $grouping.animation(reduceMotion ? nil : theme.motion.gentle)) {
                    ForEach(HerbariumGrouping.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section("Sort") {
                Picker("Sort", selection: $sort.animation(reduceMotion ? nil : theme.motion.gentle)) {
                    ForEach(HerbariumSort.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        } label: {
            HStack(spacing: 5) {
                Text("Group")
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .font(MapleFont.tileName)
            .foregroundStyle(theme.colors.textPrimary)
            .padding(.horizontal, 14)
            .frame(minHeight: 32)
            .glassSurface(in: Capsule(style: .continuous))
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Group and sort")
        .accessibilityValue("\(grouping.title), \(sort.title)")
    }

    // MARK: Sections

    private func sectionBody(_ section: HerbariumSection) -> some View {
        VStack(spacing: 0) {
            grid(section)
            if let expandTitle = section.expandTitle {
                Button {
                    withAnimation(reduceMotion ? nil : theme.motion.gentle) { _ = expanded.insert(section.id) }
                } label: {
                    Text(expandTitle)
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(theme.colors.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: theme.spacing.minimumHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, theme.spacing.xxs)
                .accessibilityHint("\(section.hiddenCount) more leaves in \(section.title)")
            }
        }
        .padding(.horizontal, theme.spacing.gridMargin)
        .padding(.top, theme.spacing.sm)
        .padding(.bottom, theme.spacing.sm)
    }

    @ViewBuilder
    private func grid(_ section: HerbariumSection) -> some View {
        let columns = HerbariumColumns(dynamicTypeSize)
        if columns.count == 1 {
            LazyVStack(spacing: theme.spacing.gutter) {
                ForEach(section.entries) { cell($0, in: section, layout: .row) }
            }
        } else {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: theme.spacing.gutter, alignment: .top), count: columns.count),
                spacing: theme.spacing.gutter
            ) {
                ForEach(section.entries) { cell($0, in: section, layout: .tile) }
            }
        }
    }

    private func cell(_ entry: HerbariumEntry, in section: HerbariumSection, layout: LeafCell.Layout) -> some View {
        let model = LeafCellModel(entry, season: season, showsRarity: sort == .rarestFirst)
        return Button {
            open(entry, source: section.id)
        } label: {
            LeafCell(model, layout: layout)
        }
        .buttonStyle(.leafCell)
        .matchedTransitionSource(id: "\(section.id)/\(entry.id)", in: zoom)
        .accessibilityRotorEntry(id: entry.id, in: rotor)
    }

    private var noMatches: some View {
        VStack(spacing: theme.spacing.xs) {
            Text("No leaves match these filters.")
                .font(MapleFont.callout)
                .foregroundStyle(theme.colors.textSecondary)
            TextLink("Reset filters", chevron: false) {
                withAnimation(reduceMotion ? nil : theme.motion.gentle) {
                    filters = HerbariumFilters()
                    scope = .all
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, theme.spacing.xl)
    }

    // MARK: Actions

    private func open(_ entry: HerbariumEntry, source: String) {
        if entry.isWaiting, entry.opensNow {
            reveal = LeafRoute(speciesID: entry.id, source: source)
        } else {
            detail = LeafRoute(speciesID: entry.id, source: source)
        }
    }

    private func turnOnAction(for permission: LeafAvailability?) -> (() -> Void)? {
        guard let permission, HerbariumCopy.turnOnTitle(permission) != nil else { return nil }
        return { openPermissionSettings(openURL) }
    }

    /// The Tree view's "See all leaves" asks for the earned leaves only (spec §8.4); apply it once, then clear it.
    private func applyRouterRequest() {
        guard router.herbariumEarnedOnlyRequest else { return }
        scope = .earned
        filters = HerbariumFilters()
        detail = nil
        router.herbariumEarnedOnlyRequest = false
    }

    #if DEBUG
    /// `-MapleDemoPresent leaf:<id>|share:<id>|rarity|filter|search[:<query>]` with `-MapleDemoTab herbarium`.
    private func presentDemo() {
        guard let request = HerbariumDemo.take() else { return }
        switch request {
        case .leaf(let id):
            detail = LeafRoute(speciesID: id, source: "demo")
        case .share(let id):
            detail = LeafRoute(speciesID: id, source: "demo", opening: .shareCard)
        case .rarity:
            let model = HerbariumEntries(collection: collection, shares: shares, at: clock.now())
            let id = model.rarest?.id ?? collection.featuredLeaf ?? "saccharum"
            detail = LeafRoute(speciesID: id, source: "demo", opening: .rarityExplainer)
        case .filter:
            sheet = .filter
        case .search(let query):
            sheet = .search(query)
        }
    }
    #endif
}

/// The sheets the Herbarium presents (spec §2.3): Filter `.medium`, Search `.large`.
enum HerbariumSheet: Identifiable, Hashable {
    case filter
    case search(String)

    var id: String {
        switch self {
        case .filter: "filter"
        case .search: "search"
        }
    }
}

/// Grid columns for the text size (spec §9): 3 up to xLarge, 2 up to xxxLarge, a 1-column list beyond.
struct HerbariumColumns {
    let count: Int

    init(_ size: DynamicTypeSize) {
        count = size <= .xLarge ? 3 : size.isAccessibilitySize ? 1 : 2
    }
}
