import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// The end of onboarding (spec §8.8, D12), the only place the Seed stage is seen:
///
/// 1. "Your sleep schedule": saving it through `ScheduleStore` earns the First-steps leaf (the Sugar maple).
/// 2. The scene with the 44 pt sprout and its neutral bud on the hill; the bud turns amber. "Your maple",
///    "Tap to open your first leaf".
/// 3. The full reveal of the Sugar maple ("For setting your sleep schedule"), at any hour.
/// 4. "Place on your maple" grafts it onto the tree, which becomes a seedling, then `onFinish` shows Home.
///
/// The first frame already shows the step `start` names (decided at launch by `ScheduleStore.resumeFirstRun`), so
/// there is no empty frame or slow fade before it. A run stopped after "Save schedule" resumes at the sprout for
/// the Sugar maple it already earned: the schedule is never asked for twice and the leaf is never awarded twice.
struct PlantYourMapleView: View {
    /// Where the run starts: `.schedule`, or `.sprout` when the Sugar maple is already earned.
    var start: FirstRunStep
    /// Called after "Place on your maple"; the app then shows Home.
    var onFinish: () -> Void

    var body: some View {
        PlantYourMapleScreen(start: start, onFinish: onFinish)
            #if DEBUG
            .revealDemoMotion()
            #endif
    }
}

private struct PlantYourMapleScreen: View {
    var onFinish: () -> Void

    @Environment(CollectionStore.self) private var collection
    @Environment(ScheduleStore.self) private var schedule
    @Environment(LeafShareStore.self) private var shares
    @Environment(\.mapleClock) private var clock
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Step: Equatable {
        case schedule, sprout, reveal, placed
    }

    /// Set from `start` before the first frame, so the screen never opens empty.
    @State private var step: Step
    @State private var budIsAmber = false
    @State private var revealMoment: RevealMoment = .closed
    @State private var openings = 0
    @State private var holdsAtEnd = false
    @State private var started = false

    init(start: FirstRunStep, onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        _step = State(initialValue: Self.step(for: start))
    }

    /// The flow's first step for the launch's first-run step. `.recordFirstLeaf` has been repaired by the time the
    /// view exists (`resumeFirstRun`), and `.finished` hands over to Home in `begin()`.
    private static func step(for start: FirstRunStep) -> Step {
        switch start {
        case .schedule, .recordFirstLeaf: .schedule
        case .sprout, .finished: .sprout
        }
    }

    /// The First-steps leaf: the Sugar maple.
    private var firstLeafID: String { FirstRunStep.firstLeafID }

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()
            switch step {
            case .schedule:
                SleepScheduleStep(onSave: save)
                    .transition(.opacity)
            case .sprout, .placed:
                scene
                    .transition(.opacity)
            case .reveal:
                if let leaf = firstLeaf {
                    RevealView(
                        leaf: leaf,
                        ritual: RevealRitual(tier: leaf.tier, revealsBefore: collection.revealsOpened, reduceMotion: reduceMotion),
                        moment: revealMoment,
                        footer: .place,
                        actions: RevealView.Actions(open: open, place: place)
                    )
                    .transition(.opacity)
                }
            }
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.5), trigger: openings)
        .task { begin() }
    }

    private var firstLeaf: RevealLeaf? {
        collection.unlock(for: firstLeafID).flatMap { RevealLeaf(unlock: $0, share: shares.share(for: $0.speciesID)) }
    }

    // MARK: The sprout and the seedling

    private var scene: some View {
        let now = clock.now()
        let inputs = collection.treeInputs(at: now)
        let phase = collection.phase(at: now)
        let planted = step == .placed
        let model = TreeSceneModel(
            seed: inputs.seed,
            growth: inputs.growth,
            species: planted ? inputs.species.map { .init(speciesID: $0.speciesID, pressed: $0.pressed) } : [],
            buds: planted ? inputs.buds.map { .init(speciesID: $0.speciesID, progress: $0.progress) } : [],
            waiting: !planted && budIsAmber ? [firstLeafID] : [],
            featured: planted ? inputs.featured : nil,
            season: inputs.season,
            seasonDay: inputs.seasonDay,
            phase: phase,
            vitality: 1,
            newLeafHalos: planted ? inputs.newLeafHalos.map { .init(speciesID: $0.speciesID, placedAt: $0.placedAt) } : [],
            unlockOrder: planted ? inputs.unlockOrder : []
        )
        return GeometryReader { proxy in
            sceneLayout(model: model, planted: planted, size: proxy.size, top: proxy.safeAreaInsets.top)
        }
    }

    private func sceneLayout(model: TreeSceneModel, planted: Bool, size: CGSize, top: CGFloat) -> some View {
        // The scene's 402 × 560 frame, scaled to the width, behind the status bar, as on Home.
        let sceneHeight = (size.width * 560 / 402).rounded()
        let onOpen: (() -> Void)? = planted ? nil : { openFromSprout() }
        let label = planted ? "Your maple. \(collection.stage.displayName), \(collection.leafCount.spoken)." : "Your maple. A seed, just planted."
        let value = !planted && budIsAmber ? "A new leaf is waiting." : ""
        return ZStack(alignment: .top) {
            MapleTreeScene(model: model, accessibilityLabel: Text(label), accessibilityValue: Text(value), onOpenWaitingLeaf: onOpen)
                .frame(width: size.width, height: sceneHeight)
                .offset(y: -top)

            VStack(spacing: theme.spacing.xs) {
                Text("Your maple")
                    .font(MapleFont.screenTitle)
                    .foregroundStyle(theme.colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                caption(planted: planted)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, theme.spacing.homeMargin)
            .padding(.top, sceneHeight * Self.captionTop - top)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { if !planted { openFromSprout() } }
    }

    /// Where the words sit: just below the hill's crest (y 470 of 560), where Home's caption sits.
    private static let captionTop: CGFloat = 500 / 560

    @ViewBuilder
    private func caption(planted: Bool) -> some View {
        if planted {
            Text("\(collection.stage.displayName) · \(collection.leafCount.text)")
                .font(MapleFont.footnote)
                .foregroundStyle(theme.colors.textSecondary)
        } else {
            // A visible button too, for Switch Control.
            Button(action: openFromSprout) {
                Text("Tap to open your first leaf")
                    .font(MapleFont.footnote)
                    .foregroundStyle(theme.colors.textSecondary)
                    .frame(minHeight: theme.spacing.minimumHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open your first leaf")
            .opacity(budIsAmber ? 1 : 0)
            .disabled(!budIsAmber)
        }
    }

    // MARK: Flow

    /// Runs once, after the first frame (which already shows `step`): the sprout's bud starts to ripen, and a run
    /// whose leaf is already on the tree hands over to Home.
    private func begin() {
        guard !started else { return }
        started = true
        if collection.hasPlacedFirstLeaf {
            onFinish()
            return
        }
        // A sprout with no leaf behind it would be a dead end, so ask for the schedule instead.
        if step == .sprout, collection.firstLeaf == nil { step = .schedule }
        if step == .sprout { ripenBud() }
        #if DEBUG
        applyDemo()
        autoplay()
        #endif
    }

    private func save(_ newSchedule: SleepSchedule) {
        schedule.save(newSchedule, at: clock.now())
        // Saving the first schedule earns the Sugar maple; `resumeFirstRun` repairs a save that didn't record it.
        guard schedule.resumeFirstRun(at: clock.now()) == .sprout else { return onFinish() }
        withAnimation(theme.motion.calm) { step = .sprout }
        ripenBud()
    }

    /// The neutral bud turns amber once the scene has settled in.
    private func ripenBud() {
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard step == .sprout else { return }
            budIsAmber = true
        }
    }

    /// The tap on the amber bud: the world dims to the bud, which opens on its own: the tap was the opening.
    private func openFromSprout() {
        guard step == .sprout, budIsAmber else { return }
        revealMoment = .closed
        withAnimation(theme.motion.gentle) { step = .reveal }
        Task {
            try? await Task.sleep(for: .seconds(0.6))
            open()
        }
    }

    private func open() {
        guard step == .reveal, revealMoment == .closed else { return }
        revealMoment = .opened(at: Date())
        openings += 1
    }

    /// "Place on your maple": the Sugar maple goes onto the tree, the sprout becomes a seedling, then Home.
    private func place() {
        let placed = collection.openReveals([firstLeafID], at: clock.now())
        if let name = placed.first.flatMap({ LeafCatalog.shared.species(id: $0.speciesID)?.displayName }) {
            AccessibilityNotification.Announcement("\(name) placed on your maple.").post()
        }
        withAnimation(theme.motion.graft) { step = .placed }
        guard !holdsAtEnd else { return }
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            onFinish()
        }
    }

    #if DEBUG
    /// `-MapleDemoOnboardingStep` and, for the reveal, `-MapleDemoRevealAt`.
    private func applyDemo() {
        guard let demo = RevealDemoOptions.onboardingStep, step == .schedule || step == .sprout else { return }
        if !schedule.hasSavedSchedule { schedule.save(.standard, at: clock.now()) }
        switch demo {
        case "seed":
            step = .sprout
        case "sprout":
            step = .sprout
            ripenBud()
        case "reveal":
            budIsAmber = true
            step = .reveal
            if let time = RevealDemoOptions.openAt {
                revealMoment = .still(time)
            } else {
                Task {
                    try? await Task.sleep(for: .seconds(0.6))
                    open()
                }
            }
        case "placed":
            holdsAtEnd = true
            place()
        default:
            break
        }
    }

    /// `-MapleDemoFirstRunAutoplay <seconds>`: taps through the first run on its own, pausing that long on each step
    /// (the schedule, the amber bud, the settled reveal), so a fresh install's real first run can be screenshotted
    /// without touching the simulator. Unlike the other onboarding arguments it acts on a live launch: it saves the
    /// schedule shown (the standard one) and places the Sugar maple, writing the member's files exactly as the taps
    /// would (docs/debug-launch-arguments.md).
    private func autoplay() {
        let pause = UserDefaults.standard.double(forKey: "MapleDemoFirstRunAutoplay")
        guard pause > 0 else { return }
        Task {
            if step == .schedule {
                try? await Task.sleep(for: .seconds(pause))
                save(.standard)
            }
            // The bud turns amber 1.2 s after the sprout appears.
            try? await Task.sleep(for: .seconds(1.2 + pause))
            openFromSprout()
            // The bud opens 0.6 s after the tap; the Sugar maple's first reveal is the full ritual.
            let ritual = RevealRitual(tier: firstLeaf?.tier ?? .common, revealsBefore: 0, reduceMotion: reduceMotion)
            try? await Task.sleep(for: .seconds(0.6 + ritual.settledTime + pause))
            if step == .reveal { place() }
        }
    }
    #endif
}
