import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// One leaf, up close (spec §5.6): the specimen stage, the colourway switch for an earned leaf, its names and
/// chips, how many members have it, what it stands for (earned) or how to earn it (locked), and its specimen label.
/// Pushed from a tile, the next-leaf row, an Almost-there card or a rosette in the Tree view.
///
/// A leaf still waiting to be opened keeps its secret: the stage shows the bud and the page offers "Open".
struct LeafDetailView: View {
    /// Something to open on arrival: the rarity explainer, or in DEBUG the share card (`-MapleDemoPresent`).
    enum Opening: Hashable {
        case plain
        case rarityExplainer
        case shareCard
    }

    @Environment(\.theme) private var theme
    @Environment(\.season) private var season
    @Environment(\.mapleClock) private var clock
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone
    @Environment(CollectionStore.self) private var collection
    @Environment(LeafShareStore.self) private var shares
    @Environment(AppRouter.self) private var router

    let speciesID: String
    @State private var colourway: ColourwayChoice = .pressed
    @State private var showsExplainer: Bool
    @State private var showsReveal = false
    @State private var showsWindDown = false
    @State private var shareImage: ShareCardImage?
    @State private var showsShareCard: Bool

    init(speciesID: String, opening: Opening = .plain) {
        self.speciesID = speciesID
        _showsExplainer = State(initialValue: opening == .rarityExplainer)
        _showsShareCard = State(initialValue: opening == .shareCard)
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = clock.date(forTimeline: context.date)
            if let species = LeafCatalog.shared.species(id: speciesID),
               let progress = collection.progress(for: speciesID, at: now) {
                page(species: species, progress: progress, now: now)
            } else {
                Text("This leaf isn't in Maple's catalogue.")
                    .font(MapleFont.callout)
                    .foregroundStyle(theme.colors.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .herbariumBackdrop(bloom: false)
        .overlay(alignment: .top) { topBar }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .sheet(isPresented: $showsExplainer) { RarityExplainerSheet(speciesID: speciesID) }
        .fullScreenCover(isPresented: $showsReveal) { RevealFlow(startingWith: speciesID) }
        .fullScreenCover(isPresented: $showsWindDown) { WindDownView() }
        #if DEBUG
        .fullScreenCover(isPresented: $showsShareCard) { ShareCardInspector(image: shareImage) }
        #endif
        .onAppear {
            if collection.unlock(for: speciesID)?.revealed == true { collection.markSeen(speciesID) }
        }
        .task(id: shareCardKey) { renderShareCard() }
    }

    // MARK: Page

    private func page(species: LeafSpecies, progress: LeafProgress, now: Date) -> some View {
        let entry = HerbariumEntry(
            species: species, progress: progress, rule: RewardCatalog.shared.reward(forSpecies: speciesID)?.unlockText ?? "",
            isNextRung: collection.nextRungIDs(at: now).contains(speciesID), share: shares.share(for: speciesID),
            opensNow: collection.revealable(at: now).contains { $0.speciesID == speciesID }
        )
        let phase = collection.phase(at: now)
        return ScrollView {
            VStack(spacing: 0) {
                SpecimenStage(species: species, colourway: shownColourway(entry), state: stageState(entry))
                    .id(shownColourway(entry))
                    .transition(.opacity)
                    .padding(.top, 44)
                if case .earned(let unlock) = entry.status {
                    colourwayControl(species: species, unlock: unlock)
                        .padding(.top, theme.spacing.xs)
                }
                names(entry)
                    .padding(.top, theme.spacing.lg)
                if !entry.isWaiting {
                    ChipFlow(alignment: .center) {
                        SmallChip(tier: progress.tier)
                        if let chip = SmallChip(approximate: species.confidence) { chip }
                    }
                    .padding(.top, theme.spacing.sm)
                }
                if showsRarity(entry) {
                    rarity
                        .padding(.top, 28)
                }
                StatusTile(entry: entry, phase: phase, rate: paceRate(progress, now: now),
                           isPinned: collection.pinnedSpeciesID == speciesID, actions: statusActions(species))
                    .padding(.top, theme.spacing.xl)
                if !entry.isWaiting {
                    SpecimenLabel(species: species)
                        .padding(.top, theme.spacing.sm)
                    Text(HerbariumCopy.source)
                        .font(.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, theme.spacing.lg)
                        .padding(.horizontal, theme.spacing.md)
                }
                if entry.isEarned {
                    featureButton
                        .padding(.top, theme.spacing.lg)
                }
            }
            .padding(.horizontal, theme.spacing.gridMargin)
            .padding(.bottom, theme.spacing.xl)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    private var topBar: some View {
        HStack {
            Button("Back", systemImage: "chevron.left") { dismiss() }
                .buttonStyle(.iconCircle)
            Spacer()
            if let shareImage {
                ShareLink(item: shareImage, preview: SharePreview(shareImage.name, image: shareImage.image)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.iconCircle)
            }
        }
        .padding(.horizontal, theme.spacing.gridMargin - 4)
    }

    // MARK: Parts

    private func colourwayControl(species: LeafSpecies, unlock: LeafUnlock) -> some View {
        VStack(spacing: 6) {
            if species.evergreen {
                Text("Evergreen · stays green")
                    .font(MapleFont.footnote)
                    .foregroundStyle(theme.colors.textSecondary)
                    .frame(minHeight: 32)
            } else {
                SegmentedCapsule(selection: $colourway.animation(theme.motion.gentle), options: ColourwayChoice.allCases) {
                    $0.title
                }
                .accessibilityLabel("Colour")
                Text(HerbariumCopy.pressedIn(unlock.season))
                    .font(MapleFont.footnote)
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func names(_ entry: HerbariumEntry) -> some View {
        let species = entry.species
        VStack(spacing: 4) {
            if entry.isWaiting {
                Text(HerbariumCopy.waitingName)
                    .font(MapleFont.leafTitle)
                    .tracking(-0.3)
                    .foregroundStyle(theme.colors.textPrimary)
                Text(RewardCatalog.shared.category(entry.progress.category)?.name ?? "")
                    .font(MapleFont.callout)
                    .foregroundStyle(theme.colors.textSecondary)
            } else if species.common.isEmpty {
                Text(latin(species.name))
                    .font(MapleFont.scientific(.title, weight: .semibold))
                    .foregroundStyle(theme.colors.textPrimary)
                Text("Series \(species.series)")
                    .font(MapleFont.callout)
                    .foregroundStyle(theme.colors.textSecondary)
            } else {
                Text(species.common)
                    .font(MapleFont.leafTitle)
                    .tracking(-0.3)
                    .foregroundStyle(theme.colors.textPrimary)
                Text(latin(species.name))
                    .font(MapleFont.scientific(.body))
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// "22%" over "of members have this leaf", with the explainer's info button after the caption.
    private var rarity: some View {
        let share = shares.share(for: speciesID)
        return Button {
            showsExplainer = true
        } label: {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                // Balances the info button, so the label stays centred.
                Color.clear.frame(width: 20, height: 1)
                MemberShareLabel(share: share, layout: .detail)
                Image(systemName: "info.circle")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(theme.colors.textSecondary)
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: theme.spacing.minimumHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(RarityButtonStyle())
        .accessibilityHint("Explains how rarity is counted.")
    }

    private var featureButton: some View {
        let isFeatured = collection.snapshot.featuredSpeciesID == speciesID
        return Button(isFeatured ? "Featured on your maple" : "Feature on your maple") {
            collection.feature(speciesID)
        }
        .buttonStyle(.glassCapsule)
        .disabled(isFeatured)
    }

    // MARK: State

    private func stageState(_ entry: HerbariumEntry) -> SpecimenState {
        switch entry.status {
        case .earned: .earned
        case .waiting: .waiting
        case .next: .next(progress: entry.progress.fraction)
        case .locked: .locked
        case .needsPermission: .needsPermission
        case .dormant: .dormant
        }
    }

    private func shownColourway(_ entry: HerbariumEntry) -> LeafColourway {
        if case .earned(let unlock) = entry.status {
            return colourway.colourway(pressed: unlock.colourway)
        }
        return LeafColourway.pressed(in: season, evergreen: entry.species.evergreen)
    }

    /// Rarity shows on earned and locked leaves; a waiting leaf keeps its secret, and an unshipped one says
    /// "Not earnable yet" in its status tile.
    private func showsRarity(_ entry: HerbariumEntry) -> Bool {
        switch entry.status {
        case .waiting, .dormant: false
        case .earned, .next, .locked, .needsPermission: true
        }
    }

    /// The member's own pace over the last 14 days; 0 without one, so detail never guesses (spec §5.6).
    private func paceRate(_ progress: LeafProgress, now: Date) -> Double {
        let calendar = collection.context.calendar
        let snapshot = collection.snapshot
        return LeafPace.rate(for: progress.category, current: snapshot.counters[progress.category] ?? 0,
                             history: snapshot.history, today: LocalDay(now, calendar: calendar), calendar: calendar)
    }

    private func statusActions(_ species: LeafSpecies) -> StatusTile.Actions {
        StatusTile.Actions(
            showOnMaple: { router.showOnMaple(speciesID) },
            open: { showsReveal = true },
            startWindDown: { showsWindDown = true },
            turnOn: { openPermissionSettings(openURL) },
            togglePin: {
                if collection.pinnedSpeciesID == speciesID { collection.unpin() } else { collection.pin(speciesID) }
            }
        )
    }

    private func latin(_ text: String) -> AttributedString {
        var name = AttributedString(text)
        name.languageIdentifier = "la"
        return name
    }

    // MARK: Share card

    /// Re-render when anything on the card changes.
    private var shareCardKey: String {
        guard let unlock = collection.unlock(for: speciesID), unlock.revealed else { return "none" }
        return "\(speciesID)|\(unlock.colourway)|\(MemberShareCopy.shareCard(shares.share(for: speciesID)) ?? "")|\(season)"
    }

    private func renderShareCard() {
        guard let species = LeafCatalog.shared.species(id: speciesID), let unlock = collection.unlock(for: speciesID),
              unlock.revealed, let progress = collection.progress(for: speciesID, at: clock.now()) else {
            shareImage = nil
            return
        }
        let copy = HerbariumCopy(locale: locale, timeZone: timeZone)
        shareImage = ShareCardImage.render(
            species: species, colourway: unlock.colourway,
            pressedLine: copy.shareCardLine(pressedOn: unlock.date, progress: progress),
            share: shares.share(for: speciesID), theme: theme, season: season
        )
    }
}

/// The colourway switch on an earned leaf: as pressed, or as it looks in summer and autumn.
enum ColourwayChoice: String, CaseIterable, Hashable {
    case pressed, summer, autumn

    var title: String {
        switch self {
        case .pressed: "Pressed"
        case .summer: "Summer"
        case .autumn: "Autumn"
        }
    }

    func colourway(pressed: LeafColourway) -> LeafColourway {
        switch self {
        case .pressed: pressed
        case .summer: .summer
        case .autumn: .autumn
        }
    }
}

/// The rarity block dims slightly while pressed, like a text link.
private struct RarityButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
    }
}
