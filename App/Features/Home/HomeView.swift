import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// Home (spec §3): the maple as the hero, one number with one line, the next leaf, and at most one action.
/// No cards, no rows, no titles: the first screen is the scene, the numeral and the next leaf on black.
struct HomeView: View {
    @Environment(CollectionStore.self) private var collection
    @Environment(AppRouter.self) private var router
    @Environment(\.mapleClock) private var clock
    @Environment(\.theme) private var theme
    @Environment(\.season) private var season
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Namespace private var zoom
    @State private var scroll = HomeScrollState()
    @State private var sheet: HomeSheet?
    @State private var cover: HomeCover?
    @State private var pushedLeaf: String?
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
            let content = HomeContent(collection: collection, now: now, bedside: bedside.state(at: now, collection: collection))
            GeometryReader { proxy in
                screen(content, proxy: proxy)
            }
        }
        .background(theme.colors.background)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .navigationDestination(item: $pushedLeaf) { speciesID in
            LeafDetailView(speciesID: speciesID)
                .navigationTransition(.zoom(sourceID: speciesID, in: zoom))
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .profile:
                ProfileView()
                    .presentationDetents([.large])
                    .presentationBackground(theme.colors.surface2)
            case .streak:
                StreakSheet()
            }
        }
        .fullScreenCover(item: $cover) { cover in
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

    /// Opens the Tree view centred on a leaf. Whatever Home is presenting goes first, so the cover can appear.
    private func showOnMaple(_ speciesID: String) {
        guard sheet != nil || cover != nil else {
            cover = .tree(focusing: speciesID)
            return
        }
        sheet = nil
        cover = nil
        Task {
            try? await Task.sleep(for: .seconds(0.6))
            cover = .tree(focusing: speciesID)
        }
    }

    // MARK: Layout

    private func screen(_ content: HomeContent, proxy: GeometryProxy) -> some View {
        let accessibilitySize = dynamicTypeSize.isAccessibilitySize
        let screenHeight = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
        let stageHeight = HomeLayout.stageHeight(screenHeight: screenHeight, accessibilitySize: accessibilitySize)
        let width = proxy.size.width
        let scale = HomeLayout.sceneScale(stageHeight: stageHeight, width: width)
        let state = content.state
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

                NowBlock(numeral: state.numeral.parts, caption: state.caption, spoken: state.spoken)
                    .padding(.horizontal, theme.spacing.homeMargin)
                    .contentShape(Rectangle())
                    .padding(.top, HomeLayout.numeralGap)
                    .opacity(state.contentOpacity)

                if let row = content.row {
                    nextLeafRow(row)
                        .padding(.horizontal, theme.spacing.homeMargin)
                        .padding(.top, HomeLayout.rowGap)
                        .opacity(state.contentOpacity)
                }

                if let action = state.action {
                    Button(action.title) { perform(action) }
                        .buttonStyle(.moonlight(dimmed: state.actionIsDimmed))
                        .padding(.horizontal, theme.spacing.homeMargin)
                        .padding(.top, content.row == nil ? HomeLayout.rowGap : HomeLayout.actionGap)
                        .transition(.opacity)
                } else if let secondary = state.secondaryAction {
                    Button(secondary.title) { perform(secondary) }
                        .buttonStyle(.glassCapsule)
                        .padding(.top, content.row == nil ? HomeLayout.rowGap : HomeLayout.actionGap)
                        .transition(.opacity)
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
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    @ViewBuilder
    private func nextLeafRow(_ row: NextLeafRow.Content) -> some View {
        switch row {
        case .leaf(let progress, _):
            NextLeafRow(row) { pushedLeaf = progress.speciesID }
                .zoomSource(id: progress.speciesID, in: zoom)
        case .waiting:
            NextLeafRow(row) { presentingRevealWithoutSlide { cover = .reveal(nil) } }
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
    /// `-MapleDemoPresent tree|tree:<id>|streak|leaf:<id>` on the Home tab (docs/debug-launch-arguments.md).
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
        case let value where value.hasPrefix("leaf:"):
            pushedLeaf = String(value.dropFirst("leaf:".count))
        default:
            break
        }
    }
    #endif
}

/// Home's sheets (spec §2.3): Profile `.large`, Streak `.medium`.
enum HomeSheet: String, Identifiable {
    case profile, streak

    var id: String { rawValue }
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

/// The scroll offset, observed only by the sky (so scrolling never re-renders the rest of Home).
@Observable
final class HomeScrollState {
    var offset: CGFloat = 0
}

/// The sky behind the stage (spec §3.7, §4.4): registered with the tree's scene, extended upward in its top
/// colour for overscroll, and held back by 60% of the scroll for a gentle parallax.
private struct HomeSky: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let phase: NowPhase
    let season: Season
    let vitality: Double
    let width: CGFloat
    let scale: CGFloat
    let scroll: HomeScrollState

    private let overscrollRoom: CGFloat = 600

    var body: some View {
        let palette = theme.colors.scene.sky(for: phase)
        VStack(spacing: 0) {
            Rectangle()
                .fill(palette.stops.first?.color ?? theme.colors.background)
                .frame(width: width, height: overscrollRoom)
            SkyBackdrop(phase: phase, season: season, vitality: vitality)
                .frame(width: width, height: HomeLayout.sceneSize.height * scale)
        }
        .offset(y: -overscrollRoom + HomeLayout.sceneOffset(scale: scale)
            + HomeLayout.skyCounterOffset(scrollOffset: scroll.offset, reduceMotion: reduceMotion))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
