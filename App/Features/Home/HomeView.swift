import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// Home (spec §3): the maple as the hero, one number with one line, the next leaf, and at most one action.
/// No cards, no rows, no titles: the first screen is the scene, the numeral and the next leaf on black.
struct HomeView: View {
    @Environment(CollectionStore.self) private var collection
    @Environment(HealthSleepImporter.self) private var sleep
    @Environment(AppRouter.self) private var router
    @Environment(\.openURL) private var openURL
    @Environment(\.mapleClock) private var clock
    @Environment(\.theme) private var theme
    @Environment(\.season) private var season
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Namespace private var zoom
    @State private var scroll = HomeScrollState()
    /// The first screen's measured parts, from which the stage's height is fitted (`HomeLayout.firstScreen`).
    @State private var measured = HomeMeasurements()
    /// The tree caption's line height, which the scene's scale keeps inside the stage.
    @ScaledMetric(relativeTo: .footnote) private var captionTextHeight: CGFloat = 18
    @State private var sheet: HomeSheet?
    @State private var cover: HomeCover?
    @State private var pushedLeaf: String?
    /// "Show on my maple" asked while a sheet or cover was up: the Tree view opens once that has gone.
    @State private var pendingTreeFocus: String?
    /// Wind-down mode's log: whether it is on, and tonight's Goodnight (spec §3.4).
    private let bedside = BedsideLog.shared
    #if DEBUG
    @State private var demoApplied = false
    #endif

    /// The zoom-transition id of the stage, which the Tree view grows from.
    static let mapleTransitionID = "home.maple"

    var body: some View {
        // NowState refreshes every minute; the clock freezes it inside a phase for DEBUG demos.
        TimelineView(.everyMinute) { timeline in
            let now = clock.date(forTimeline: timeline.date)
            let content = HomeContent(
                collection: collection, now: now, bedside: bedside.state(at: now, collection: collection),
                lastNight: sleep.lastNightSleep(at: now), noSleepHint: sleep.showsNoSleepHint(at: now)
            )
            GeometryReader { proxy in
                screen(content, proxy: proxy)
            }
        }
        // Under a full-screen cover (the reveal, wind-down mode, the Tree view) the scene and the sky hold their frame.
        .environment(\.treeScenesPaused, cover != nil)
        .background(theme.colors.background)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .navigationDestination(item: $pushedLeaf) { speciesID in
            LeafDetailView(speciesID: speciesID)
                .navigationTransition(.zoom(sourceID: speciesID, in: zoom))
        }
        .sheet(item: $sheet, onDismiss: presentPendingTree) { sheet in
            switch sheet {
            case .profile:
                ProfileView()
                    .presentationDetents([.large])
                    .presentationBackground(theme.colors.surface2)
            case .streak:
                StreakSheet()
            case .health(let request):
                HealthPrimerSheet(speciesID: request.speciesID)
            }
        }
        .fullScreenCover(item: $cover, onDismiss: presentPendingTree) { cover in
            switch cover {
            case .tree(let speciesID):
                TreeView(focusing: speciesID)
                    .navigationTransition(.zoom(sourceID: Self.mapleTransitionID, in: zoom))
            case .reveal(let speciesID):
                RevealFlow(startingWith: speciesID)
            case .windDown:
                WindDownView()
            }
        }
        // Leaf detail's "Show on my maple", from any tab (spec §5.6).
        .onChange(of: router.treeLeafRequest, initial: true) { _, request in
            guard let request else { return }
            router.treeLeafRequest = nil
            showOnMaple(request)
        }
        #if DEBUG
        .task { applyDemoPresentation() }
        #endif
    }

    /// Opens the Tree view centred on a leaf. Whatever Home is presenting goes first; the Tree view follows from its
    /// dismissal (`presentPendingTree`), never after a guessed delay.
    private func showOnMaple(_ speciesID: String) {
        guard sheet != nil || cover != nil else {
            cover = .tree(focusing: speciesID)
            return
        }
        pendingTreeFocus = speciesID
        sheet = nil
        cover = nil
    }

    private func presentPendingTree() {
        guard let speciesID = pendingTreeFocus, sheet == nil, cover == nil else { return }
        pendingTreeFocus = nil
        cover = .tree(focusing: speciesID)
    }

    // MARK: Layout

    private func screen(_ content: HomeContent, proxy: GeometryProxy) -> some View {
        let accessibilitySize = dynamicTypeSize.isAccessibilitySize
        let screenHeight = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
        let state = content.state
        // The first screen fits above the floating tab bar at every text size: the stage yields height, and when
        // even the smallest stage leaves no room the capsule is pinned above the tab bar (spec §3.1, §9).
        let fit = HomeLayout.firstScreen(
            stageHeight: HomeLayout.stageHeight(screenHeight: screenHeight, accessibilitySize: accessibilitySize),
            visibleHeight: proxy.size.height - measured.header, belowStage: measured.belowStage,
            action: measured.action, hasAction: state.action != nil || state.secondaryAction != nil,
            hasRow: content.row != nil || content.showsNoSleepHint
        )
        let stageHeight = fit.heroHeight
        let width = proxy.size.width
        let scale = HomeLayout.sceneScale(stageHeight: stageHeight, width: width, captionTextHeight: captionTextHeight)
        return ScrollView {
            VStack(spacing: 0) {
                HomeTreeStage(
                    content: content, width: width, height: stageHeight, scale: scale,
                    openTree: { cover = .tree(focusing: nil) },
                    openWaitingLeaf: { presentingRevealWithoutSlide { cover = .reveal(content.waitingBudID) } },
                    openHerbarium: { router.showHerbarium() },
                    showLeaf: { pushedLeaf = $0 }
                )
                .matchedTransitionSource(id: Self.mapleTransitionID, in: zoom)

                belowStage(content)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measured.belowStage = $0 }

                if !fit.pinsAction {
                    let hasRow = content.row != nil || content.showsNoSleepHint
                    action(state)
                        .padding(.top, hasRow ? HomeLayout.actionGap : HomeLayout.rowGap)
                }
            }
            .padding(.bottom, HomeLayout.closingPadding)
            .background(alignment: .top) {
                HomeSky(phase: state.phase, season: content.tree.season, vitality: content.tree.vitality,
                        width: width, scale: scale, scroll: scroll)
            }
            .mapleAnimation(theme.motion.gentle, value: state)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            scroll.offset = offset
        }
        .safeAreaBar(edge: .top) {
            HomeHeader(
                season: season, date: content.now, streak: content.streak, avatar: content.avatar,
                onStreak: { sheet = .streak }, onAvatar: { sheet = .profile }
            )
            .opacity(state.contentOpacity)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measured.header = $0 }
        }
        .safeAreaBar(edge: .bottom) {
            // Only at the largest text sizes: the capsule stays on the first screen, just above the tab bar,
            // and the numeral, caption and next leaf scroll under it.
            if fit.pinsAction {
                action(state)
                    .padding(.top, theme.spacing.sm)
                    .padding(.bottom, HeroFit.minimumBottomGap)
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        // At night the sky's twinkle and the tree hold still together after a minute without a tap (spec §4.9).
        .nightIdleFreeze(phase: state.phase)
    }

    /// The numeral with its caption, and the next-leaf row: everything between the stage and the capsule.
    private func belowStage(_ content: HomeContent) -> some View {
        let state = content.state
        return VStack(spacing: 0) {
            NowBlock(numeral: state.numeral.parts, caption: state.caption, spoken: state.spoken)
                .padding(.horizontal, theme.spacing.homeMargin)
                .contentShape(Rectangle())
                .padding(.top, HomeLayout.numeralGap)
                .opacity(state.contentOpacity)

            if content.showsNoSleepHint {
                NoSleepHint()
                    .padding(.horizontal, theme.spacing.homeMargin)
                    .padding(.top, HomeLayout.rowGap)
                    .opacity(state.contentOpacity)
            } else if let row = content.row {
                nextLeafRow(row)
                    .padding(.horizontal, theme.spacing.homeMargin)
                    .padding(.top, HomeLayout.rowGap)
                    .opacity(state.contentOpacity)
            }
        }
    }

    /// The one primary capsule, or night's glass capsule once sleep sounds ship; nothing when there is no action.
    @ViewBuilder
    private func action(_ state: NowState) -> some View {
        if let action = state.action {
            Button(action.title) { perform(action) }
                .buttonStyle(.moonlight(dimmed: state.actionIsDimmed))
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measured.action = $0 }
                .padding(.horizontal, theme.spacing.homeMargin)
                .transition(.opacity)
        } else if let secondary = state.secondaryAction {
            Button(secondary.title) { perform(secondary) }
                .buttonStyle(.glassCapsule)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measured.action = $0 }
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private func nextLeafRow(_ row: NextLeafRow.Content) -> some View {
        switch row {
        case .leaf(let progress, _):
            NextLeafRow(row) { pushedLeaf = progress.speciesID }
                .zoomSource(id: progress.speciesID, in: zoom)
        case .waiting:
            NextLeafRow(row) { presentingRevealWithoutSlide { cover = .reveal(nil) } }
        case .needsPermission(let progress):
            NextLeafRow(row) {
                pushedLeaf = progress.speciesID
            } turnOn: {
                turnOnPermission(progress.availability, speciesID: progress.speciesID,
                                 showHealthPrimer: { sheet = .health($0) }, openURL: openURL)
            }
            .zoomSource(id: progress.speciesID, in: zoom)
        }
    }

    // MARK: Actions

    private func perform(_ action: NowState.Action) {
        switch action {
        case .startWindDown, .returnToWindDown:
            cover = .windDown
        case .openReveals:
            presentingRevealWithoutSlide { cover = .reveal(nil) }
        case .startFocus, .returnToFocus:
            // Focus lives in Rest (spec §2.2); Home offers it only once it ships.
            router.selectedTab = .rest
        case .checkIn:
            // Check-ins are absent until they ship; NowState never asks for one before then.
            break
        }
    }

    private func perform(_ action: NowState.SecondaryAction) {
        switch action {
        case .sleepSounds:
            router.selectedTab = .rest
        }
    }

    #if DEBUG
    /// `-MapleDemoPresent tree|tree:<id>|streak|leaf:<id>|health` on the Home tab (docs/debug-launch-arguments.md).
    private func applyDemoPresentation() {
        guard !demoApplied else { return }
        demoApplied = true
        let defaults = UserDefaults.standard
        guard (defaults.string(forKey: "MapleDemoTab") ?? AppTab.home.rawValue) == AppTab.home.rawValue,
              let request = defaults.string(forKey: "MapleDemoPresent") else { return }
        switch request {
        case "tree":
            cover = .tree(focusing: nil)
        case let value where value.hasPrefix("tree:"):
            cover = .tree(focusing: String(value.dropFirst("tree:".count)))
        case "streak":
            sheet = .streak
        case "health":
            sheet = .health(HealthPrimerRequest())
        case let value where value.hasPrefix("leaf:"):
            pushedLeaf = String(value.dropFirst("leaf:".count))
        default:
            break
        }
    }
    #endif
}

/// Home's sheets (spec §2.3): Profile `.large`, Streak `.medium`, and the Apple Health primer `.medium` from the
/// needs-permission row.
enum HomeSheet: Identifiable, Hashable {
    case profile, streak
    case health(HealthPrimerRequest)

    var id: String {
        switch self {
        case .profile: "profile"
        case .streak: "streak"
        case .health(let request): request.id
        }
    }
}

/// Home's full-screen covers: the Tree view, the reveal and wind-down mode.
enum HomeCover: Identifiable, Hashable {
    /// The Tree view, optionally zoomed onto one species.
    case tree(focusing: String?)
    /// Opens the waiting queue, starting with this leaf when given.
    case reveal(String?)
    case windDown

    var id: String {
        switch self {
        case .tree(let speciesID): "tree.\(speciesID ?? "")"
        case .reveal(let speciesID): "reveal.\(speciesID ?? "")"
        case .windDown: "windDown"
        }
    }
}

/// Heights Home measures on its first screen; none of them depends on the stage's height, so fitting the stage
/// settles in one pass.
struct HomeMeasurements: Equatable {
    /// The header, which grows with the text size.
    var header: CGFloat = HomeLayout.headerHeight
    /// The numeral, caption and next-leaf row with their gaps; nil until measured.
    var belowStage: CGFloat?
    /// The capsule; nil until measured.
    var action: CGFloat?
}

/// The scroll offset, observed only by the sky (so scrolling never re-renders the rest of Home).
@Observable
final class HomeScrollState {
    var offset: CGFloat = 0
}

/// The sky behind the stage (spec §3.7, §4.4): registered with the tree's scene, extended upward for overscroll
/// (`SkyBackdropExtension`), and held back by 60% of the scroll for a gentle parallax.
private struct HomeSky: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let phase: NowPhase
    let season: Season
    let vitality: Double
    let width: CGFloat
    let scale: CGFloat
    let scroll: HomeScrollState

    private let overscrollRoom: CGFloat = 600

    var body: some View {
        let backdrop = CGSize(width: width, height: HomeLayout.sceneSize.height * scale)
        VStack(spacing: 0) {
            // Carries the sky's light pools upward, so the backdrop's top edge never shows as a seam: it comes into
            // view under the header when the stage is shrunk for large text.
            SkyBackdropExtension(phase: phase, backdropSize: backdrop)
                .frame(width: width, height: overscrollRoom)
            SkyBackdrop(phase: phase, season: season, vitality: vitality)
                .frame(width: backdrop.width, height: backdrop.height)
        }
        .offset(y: -overscrollRoom + HomeLayout.sceneOffset(scale: scale)
            + HomeLayout.skyCounterOffset(scrollOffset: scroll.offset, reduceMotion: reduceMotion))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
