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
    @Environment(\.mapleClock) private var clock
    @Environment(\.theme) private var theme
    @Environment(\.season) private var season
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @Environment(AppSettings.self) private var settings
    /// This launch's Focus stores: Home's focus status and its one-tap start (F1 design §5.10).
    @Environment(\.focusStores) private var focusStores

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
    /// True while a session runs: the timeline ticks every second (`NowState.refreshesEverySecond`), so the time left
    /// turns over on the session's own minutes and counts seconds in the last one.
    @State private var everySecond = false
    /// Both cadences tick from this whole minute, so a minute tick lands where `.everyMinute`'s would.
    @State private var timelineStart = HomeView.minuteStart(of: .now)
    /// The Locked hold's progress (F1 design §5.2).
    @State private var holdProgress = 0.0
    /// Wind-down mode's log: whether it is on, and tonight's Goodnight (spec §3.4).
    private let bedside = BedsideLog.shared
    #if DEBUG
    @State private var demoApplied = false
    #endif

    /// The zoom-transition id of the stage, which the Tree view grows from.
    static let mapleTransitionID = "home.maple"

    var body: some View {
        // NowState refreshes every minute, and every second while a session runs (F1 design §5.10); the clock freezes
        // it inside a phase for DEBUG demos.
        TimelineView(.periodic(from: timelineStart, by: everySecond ? 1 : 60)) { timeline in
            let now = clock.date(forTimeline: timeline.date)
            let content = HomeContent(
                collection: collection, now: now, bedside: bedside.state(at: now, collection: collection),
                lastNight: sleep.lastNightSleep(at: now), noSleepHint: sleep.showsNoSleepHint(at: now),
                focus: focusStatus(), provisionalSeconds: provisionalSeconds()
            )
            GeometryReader { proxy in
                screen(content, proxy: proxy)
            }
            .onChange(of: content.state.refreshesEverySecond, initial: true) { _, running in
                everySecond = running
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
            case .health(let request):
                HealthPrimerSheet(speciesID: request.speciesID)
            case .savedToday:
                SavedTodaySheet()
                    #if DEBUG
                    .revealDemoMotion()
                    #endif
            case .streak:
                StreakSheet()
                    #if DEBUG
                    .revealDemoMotion()
                    #endif
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
        // A Focus request made from inside one of Home's presentations (Settings in the Profile sheet) shows the Focus
        // tab, so whatever Home is presenting closes.
        .onChange(of: router.focusRequest) { _, request in
            guard request != nil else { return }
            sheet = nil
            cover = nil
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
            // While a session runs Home refreshes every second, so the numeral changes crisply instead of rolling (F1
            // design §4.6).
            NowBlock(numeral: state.numeral.parts, caption: state.caption, spoken: state.spoken,
                     rolls: !state.refreshesEverySecond)
                .padding(.horizontal, theme.spacing.homeMargin)
                .contentShape(Rectangle())
                // Today's saved time opens Saved today (focus spec §5.9).
                .onTapGesture { if opensSavedToday(state) { sheet = .savedToday } }
                .accessibilityAddTraits(opensSavedToday(state) ? .isButton : [])
                .accessibilityHint(opensSavedToday(state) ? Text(FocusSheetCopy.savedTodayHint) : Text(""))
                .accessibilityAction { if opensSavedToday(state) { sheet = .savedToday } }
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

    /// The numeral opens Saved today once Focus ships, while it shows today's saved time.
    private func opensSavedToday(_ state: NowState) -> Bool {
        collection.context.features.focus && state.content == .savedToday
    }

    /// The one primary capsule: a hold for a Locked start that can go straight ahead (F1 design §5.2), the moonlight
    /// capsule otherwise, or night's glass capsule once sleep sounds ship; nothing when there is no action.
    @ViewBuilder
    private func action(_ state: NowState) -> some View {
        if case .startFocus(let start) = state.action, start.needsHold {
            HoldButton(
                title: start.title, duration: FocusCopy.holdToStartSeconds, accessibilityName: start.spokenTitle(locale: locale),
                progress: $holdProgress, frozenProgress: Self.frozenHold
            ) {
                Task { await begin(start) }
            }
            .disabled(isStarting)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measured.action = $0 }
            .padding(.horizontal, theme.spacing.homeMargin)
            .transition(.opacity)
        } else if let action = state.action {
            // A limit on the label wins over the capsule's two lines: at accessibility sizes "Start a quick session ·
            // 25m" needs a third (§5.17).
            Button { perform(action) } label: { Text(action.title).lineLimit(nil) }
                .buttonStyle(.moonlight(dimmed: state.actionIsDimmed))
                // "Start study, 50 minutes": VoiceOver never reads a length as "50m".
                .accessibilityLabel(action.spokenTitle(locale: locale))
                .disabled(isStarting)
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
                                 showHealthPrimer: { sheet = .health($0) }, router: router)
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
        case .startFocus(let start):
            switch start.readiness {
            case .ready(needsHold: false):
                Task { await begin(start) }
            case .ready(needsHold: true):
                // Locked never starts with one tap (F1 design §5.2): its capsule is a hold, which begins it itself.
                break
            case .needsStartScreen:
                // The start screen has something to say first (F1-20).
                router.showFocus(.selectPreset(start.presetID))
            }
        case .returnToSession:
            router.showFocus(.returnToSession)
        case .turnOnBlocking:
            router.showFocus(.needsScreenTime)
        }
    }

    private func perform(_ action: NowState.SecondaryAction) {
        switch action {
        case .sleepSounds:
            // Sleep sounds ship in F2 (`ShippedFeatures.sleepSounds`), so Home never offers this yet: nothing opens.
            break
        }
    }

    /// Home's one-tap start (a completed hold for Locked): the preset as Start shows it, started from Home. A start
    /// the store refuses opens the Focus tab with that preset, where the start screen says why.
    private func begin(_ start: FocusStart) async {
        defer { holdProgress = 0 }
        guard let focusStores, let preset = focusStores.presets.preset(id: start.presetID) else {
            router.showFocus(.selectPreset(start.presetID))
            return
        }
        let appSet = preset.appSetID.flatMap { focusStores.appSets.set(id: $0) }
        let request = FocusSessionStore.StartRequest(preset: preset, minutes: start.minutes, appSet: appSet, from: .home)
        switch await focusStores.start(request, intention: nil, settings: settings) {
        case .started:
            break    // Home now shows the session: "50m" · "left in this session" · "Return to session".
        case .alreadyRunning:
            router.showFocus(.returnToSession)
        case .ledgerUnavailable, .blockingFailed, .notRecorded:
            router.showFocus(.selectPreset(start.presetID))
        }
    }

    /// A start is on its way: Start waits for it (the store refuses a second one anyway).
    private var isStarting: Bool { focusStores?.sessions.isStarting ?? false }

    /// Today's focus on the session store's trusted time, once Focus ships; nil before, when Home ignores it.
    private func focusStatus() -> FocusStatus? {
        guard collection.context.features.focus, let focusStores else { return nil }
        return focusStores.status(at: focusStores.sessions.now, collection: collection, settings: settings)
    }

    /// A running session's provisional seconds (display credit less what is counted), which the next-leaf row adds so
    /// it agrees with the dial (F1 design §4.3).
    private func provisionalSeconds() -> Int {
        guard collection.context.features.focus, let sessions = focusStores?.sessions, sessions.running != nil else { return 0 }
        return max(0, sessions.displayCredit(at: sessions.now).total - collection.focus.totalSeconds)
    }

    /// DEBUG `-MapleDemoHoldAt 0…1`: the hold's fill frozen for a screenshot (Task 7's `frozenProgress`); nil otherwise.
    private static let frozenHold: Double? = {
        #if DEBUG
        DemoLaunchOptions.current.holdAt
        #else
        nil
        #endif
    }()

    /// The whole minute `date` falls in.
    private static func minuteStart(of date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
    }

    #if DEBUG
    /// `-MapleDemoPresent tree|tree:<id>|saved|streak|leaf:<id>|health` on the Home tab (docs/debug-launch-arguments.md).
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
        case "health":
            sheet = .health(HealthPrimerRequest())
        case "saved":
            sheet = .savedToday
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

/// Home's sheets (spec §2.3): Profile `.large`, the Apple Health primer `.medium` from the needs-permission row, and
/// the Focus sheets: Saved today from the numeral, the streak from the header (F1 design §5.9, §5.15).
enum HomeSheet: Identifiable, Hashable {
    case profile
    case health(HealthPrimerRequest)
    case savedToday
    case streak

    var id: String {
        switch self {
        case .profile: "profile"
        case .health(let request): request.id
        case .savedToday: "savedToday"
        case .streak: "streak"
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
