import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// The first run (spec §8.8, D12), full screen, and the only place the Seed stage is seen:
///
/// 1. Four questions, one per screen (`OnboardingQuestionView`): the weekday wake, the weekend wake, the sleep need
///    (which becomes Settings › Sleep goal) and the wind-down length.
/// 2. "Your sleep schedule", opening on the schedule proposed from the answers. Saving it through `ScheduleStore`
///    earns the First-steps leaf (the Sugar maple).
/// 3. The Apple Health primer ("Not now" allowed), then the reminders primer (`OnboardingNotificationsStep`,
///    skipped once iOS has been asked).
/// 4. The scene with the 44 pt sprout and its neutral bud on the hill; the bud turns amber. "Your maple",
///    "Tap to open your first leaf".
/// 5. The full reveal of the Sugar maple ("For setting your sleep schedule"), at any hour.
/// 6. "Place on your maple" grafts it onto the tree, which becomes a seedling, then `onFinish` shows Home.
///
/// Every step is saved as it happens (`OnboardingStore`, `ScheduleStore`, the collection), and the first frame shows
/// the step those files name, so a run stopped anywhere resumes on the same screen: the schedule is never asked for
/// twice once saved, and the leaf is never awarded twice.
struct PlantYourMapleView: View {
    /// Where the run starts: `.schedule` (the questions and schedule), or `.sprout` when the Sugar maple is earned.
    var start: FirstRunStep
    /// Called after "Place on your maple"; the app then shows Home.
    var onFinish: () -> Void

    var body: some View {
        PlantYourMapleScreen(onFinish: onFinish)
            #if DEBUG
            .revealDemoMotion()
            #endif
    }
}

private struct PlantYourMapleScreen: View {
    var onFinish: () -> Void

    @Environment(CollectionStore.self) private var collection
    @Environment(ScheduleStore.self) private var schedule
    @Environment(OnboardingStore.self) private var onboarding
    @Environment(AppSettings.self) private var settings
    @Environment(LeafShareStore.self) private var shares
    @Environment(\.mapleClock) private var clock
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Step: Equatable {
        /// The questions, the schedule and the primers: `OnboardingStore` says which.
        case setup
        case sprout, reveal, placed
    }

    /// Nil until the first frame, which takes it from the saved files (`initialStep`), so the screen never opens
    /// empty or on the wrong step.
    @State private var stepOverride: Step?
    @State private var budIsAmber = false
    @State private var revealMoment: RevealMoment = .closed
    @State private var openings = 0
    @State private var holdsAtEnd = false
    @State private var started = false

    private var step: Step { stepOverride ?? initialStep }

    /// The questions and primers until they are done, then the sprout.
    private var initialStep: Step {
        setupStep == .sprout || setupStep == nil ? .sprout : .setup
    }

    /// The setup screen the files name (`OnboardingProgress.resume`); nil once the Sugar maple is placed.
    private var setupStep: OnboardingStep? {
        onboarding.step(schedule: schedule, collection: collection)
    }

    /// The First-steps leaf: the Sugar maple.
    private var firstLeafID: String { FirstRunStep.firstLeafID }

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()
            switch step {
            case .setup:
                if let current = setupStep {
                    setup(current)
                        .id(current)
                        .transition(.opacity)
                }
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

    // MARK: Setup: questions, schedule, primers

    @ViewBuilder
    private func setup(_ current: OnboardingStep) -> some View {
        switch current {
        case .weekdayWake, .weekendWake, .sleepNeed, .windDown:
            OnboardingQuestionView(
                step: current, onBack: current.previous.map { previous in { go(to: previous) } },
                onContinue: { go(to: current.next) }
            )
        case .schedule:
            SleepScheduleStep(
                proposal: onboarding.answers.proposedSchedule, start: onboarding.scheduleShown,
                onChange: { onboarding.setScheduleDraft($0) },
                onBack: { go(to: .windDown) },
                onSave: save
            )
        case .health:
            OnboardingHealthStep { answered(.health) }
        case .notifications:
            OnboardingNotificationsStep { answered(.notifications) }
        case .sprout:
            Color.clear
        }
    }

    /// Continue or back: a calm crossfade to the next screen, which is saved at once.
    private func go(to next: OnboardingStep) {
        withAnimation(theme.motion.gentle) { onboarding.go(to: next) }
    }

    /// A primer was answered; after the last one the sprout appears.
    private func answered(_ primer: OnboardingStep) {
        withAnimation(theme.motion.gentle) { onboarding.answered(primer) }
        if setupStep == .sprout { showSprout() }
    }

    private func save(_ newSchedule: WeeklySleepSchedule) {
        let now = clock.now()
        // The sleep need answer is the sleep goal behind Full nights (rewards.json `full_nights`).
        settings.sleepGoalMinutes = onboarding.answers.sleepNeedMinutes
        schedule.save(newSchedule, at: now)
        // Saving the first schedule earns the Sugar maple; `resumeFirstRun` repairs a save that didn't record it.
        guard schedule.resumeFirstRun(at: now) == .sprout else { return onFinish() }
        go(to: .health)
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
        stepOverride = initialStep
        // A sprout with no leaf behind it would be a dead end, so ask for the schedule instead.
        if step == .sprout, collection.firstLeaf == nil {
            onboarding.go(to: .schedule)
            stepOverride = .setup
        }
        if step == .sprout { ripenBud() }
        #if DEBUG
        applyDemo()
        autoplay()
        #endif
    }

    /// The questions and primers are done: the scene with the sprout, whose bud then ripens.
    private func showSprout() {
        guard step == .setup else { return }
        withAnimation(theme.motion.calm) { stepOverride = .sprout }
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
        withAnimation(theme.motion.gentle) { stepOverride = .reveal }
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
        withAnimation(theme.motion.graft) { stepOverride = .placed }
        guard !holdsAtEnd else { return }
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            onFinish()
        }
    }

    #if DEBUG
    /// `-MapleDemoOnboardingStep` and, for the reveal, `-MapleDemoRevealAt` (docs/debug-launch-arguments.md). Demo
    /// launches keep every store in memory, so the saves here never reach the member's files.
    private func applyDemo() {
        guard let demo = RevealDemoOptions.onboardingStep, step == .setup || step == .sprout else { return }
        var answers = onboarding.answers
        switch demo {
        case "wake":
            onboarding.go(to: .weekdayWake)
        case "weekend", "weekend:later":
            if demo == "weekend:later" { answers.weekendWake = answers.suggestedWeekendWake }
            onboarding.answers = answers
            onboarding.go(to: .weekendWake)
        case "sleep":
            onboarding.go(to: .sleepNeed)
        case "winddown":
            onboarding.go(to: .windDown)
        case "schedule", "schedule:weekend":
            if demo == "schedule:weekend" { answers.weekendWake = ClockTime(hour: 9) }
            onboarding.answers = answers
            onboarding.go(to: .schedule)
        case "health", "notifications":
            if !schedule.hasSavedSchedule { schedule.save(onboarding.scheduleShown, at: clock.now()) }
            if demo == "notifications" { onboarding.answered(.health) }
            onboarding.go(to: demo == "health" ? .health : .notifications)
            stepOverride = .setup
        case "seed", "sprout", "reveal", "placed":
            if !schedule.hasSavedSchedule { schedule.save(.standard, at: clock.now()) }
            onboarding.answered(.health)
            onboarding.answered(.notifications)
            applyEndDemo(demo)
        default:
            break
        }
    }

    /// The onboarding end's demo steps: `seed`, `sprout`, `reveal`, `placed`.
    private func applyEndDemo(_ demo: String) {
        switch demo {
        case "seed":
            stepOverride = .sprout
        case "sprout":
            stepOverride = .sprout
            ripenBud()
        case "reveal":
            budIsAmber = true
            stepOverride = .reveal
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

    /// `-MapleDemoFirstRunAutoplay <seconds>`: taps through the first run on its own, pausing that long on each
    /// screen: Continue on each question (keeping its default answer), "Save schedule" on the proposal, "Not now" on
    /// the Apple Health primer (Apple's own sheet needs a real tap), then the amber bud and "Place on your maple".
    /// Unlike the other onboarding arguments it acts on a live launch: it writes the member's files exactly as the
    /// taps would (docs/debug-launch-arguments.md).
    private func autoplay() {
        let pause = UserDefaults.standard.double(forKey: "MapleDemoFirstRunAutoplay")
        guard pause > 0 else { return }
        Task {
            while step == .setup, let current = setupStep, current != .sprout {
                switch current {
                case .weekdayWake, .weekendWake, .sleepNeed, .windDown:
                    try? await Task.sleep(for: .seconds(pause))
                    if setupStep == current { go(to: current.next) }
                case .schedule:
                    try? await Task.sleep(for: .seconds(pause))
                    if setupStep == .schedule { save(onboarding.scheduleShown) }
                case .health:
                    try? await Task.sleep(for: .seconds(pause))
                    if setupStep == .health { answered(.health) }
                case .notifications:
                    // "Not now" on the reminders primer (iOS's own prompt needs a real tap).
                    try? await Task.sleep(for: .seconds(pause))
                    if setupStep == .notifications { answered(.notifications) }
                case .sprout:
                    try? await Task.sleep(for: .seconds(0.3))
                }
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
