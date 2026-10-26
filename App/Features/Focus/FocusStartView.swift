import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// The Focus tab's start screen (F1 design §5.1, §5.2, §4.5, §5.17), and its "Session running, minimised" state.
///
/// - **Choosing:** the dial previews the length in plan marks, with the leaf dot where the next hours leaf would open
///   and that leaf in the centre; turning it sets this session's length. Under it are the preset chips, "What's this
///   for?", the Blocking line and the counts line, then the primary capsule.
/// - **Locked** starts with a 1.5-second hold, whose progress fills the dial's marks. A plain tap shows "Hold to start.
///   Locked ends early only by emergency release." for 4 seconds in the counts line's place (§5.2).
/// - **After Start** the capsule reads "Locking 6 apps…" until the store has read the block back. The session's own
///   screen then takes over (`FocusView`, with a soft haptic). A block that can't be applied offers the plain timer
///   (`PlainTimerReason.lockFailed`); a start the ledger can't record says so.
/// - **A plain timer** (`PlainTimerReason.chosen`, from Needs Screen Time) replaces the Blocking line with "Plain timer
///   · apps aren't locked", and shows no leaf and no counts line.
/// - **Minimised** (`minimised`): the dial is live and can't be turned, the chips and lines are hidden, and the capsule
///   reads "Return to session".
///
/// Every word comes from `StartScreenModel` (`FocusStores.startScreen`) and `FocusStartLines`. The first start ever
/// asks for notification permission once it has started, if iOS hasn't asked yet (F1-23).
struct FocusStartView: View {
    /// The running session, shown minimised; nil to choose and start one.
    var minimised: UUID? = nil

    @Environment(\.theme) private var theme
    @Environment(\.season) private var season
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.focusStores) private var focusStores
    @Environment(FocusTabState.self) private var tab
    @Environment(FocusSessionStore.self) private var sessions
    @Environment(PresetStore.self) private var presets
    @Environment(AppSetStore.self) private var appSets
    @Environment(CollectionStore.self) private var collection
    @Environment(AppSettings.self) private var settings
    @Environment(NotificationScheduler.self) private var reminders

    /// The Locked hold's fill, shown on the dial's marks while it is held.
    @State private var holdProgress = 0.0
    /// When the plain-tap hint appeared; it goes after `FocusCopy.holdHintSeconds`.
    @State private var hintShownAt: Date?
    /// A start the ledger couldn't record, until the next start or chip.
    @State private var notice: String?

    var body: some View {
        // Once a minute, so the phase, the window and the counts line follow the clock.
        TimelineView(.everyMinute) { _ in
            if let focusStores, let preset = selectedPreset {
                screen(focusStores, preset: preset, now: sessions.now)
            }
        }
        .task(id: hintShownAt) { await hideHint() }
    }

    // MARK: Screen

    private func screen(_ stores: FocusStores, preset: FocusPreset, now: Date) -> some View {
        let running = runningSession
        let model = stores.startScreen(
            preset: running.flatMap { presets.preset(id: $0.plan.presetID) } ?? preset,
            minutes: running?.plan.plannedMinutes ?? tab.minutes ?? preset.minutes, at: now, collection: collection,
            settings: settings, stage: running != nil ? .running : sessions.isStarting ? .locking : .choosing,
            hasTurned: tab.hasTurnedDial, locale: locale
        )
        let lines = FocusStartLines(model: model, mode: mode, showsHoldHint: hintShownAt != nil, notice: notice, locale: locale)
        // A plain timer, chosen or running, can't count toward a leaf, so none is drawn.
        let showsLeaf = lines.showsLeaf && running?.plan.kind != .plainTimer
        let leaf = showsLeaf ? stores.nextHoursLeaf(at: now, collection: collection) : nil
        return FocusHeroPage { diameter in
            dial(model, lines: lines, leaf: leaf, session: running, diameter: diameter)
        } below: {
            details(model, lines: lines, session: running)
        } primary: {
            primary(model, lines: lines)
        }
    }

    // MARK: Dial

    @ViewBuilder
    private func dial(
        _ model: StartScreenModel, lines: FocusStartLines, leaf: LeafProgress?, session: SessionRecord?, diameter: CGFloat
    ) -> some View {
        let species = leaf.flatMap { LeafCatalog.shared.species(id: $0.speciesID) }
        // The rung as the counters have it: the softer gold for what was saved before.
        let fill = leaf.map { DialFill(rung: $0, sessionHours: 0) } ?? DialFill()
        if let session {
            // Minimised: live, once a second, on the store's trusted time; its last frame held past the planned end.
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let now = FocusRoute.frameTime(session, now: sessions.now)
                let planned = session.plan.plannedMinutes
                let left = max(0, session.plannedEnd.timeIntervalSince(now))
                MinuteDial(
                    frame: .running(layout: DialLayout(plannedMinutes: planned), elapsed: now.timeIntervalSince(session.countdownStart),
                                    leafMinute: nil, fill: fill),
                    diameter: diameter, theme: theme
                ) {
                    DialCentre(leaf: species.map { DialLeaf(species: $0, fill: fill) },
                               numeral: DialCentre.numeralParts(FocusTimeText.remaining(left)),
                               caption: FocusStartLines.minimisedCaption(plannedMinutes: planned), diameter: diameter)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(FocusStartLines.minimisedDialLabel(secondsLeft: left, plannedMinutes: planned, locale: locale))
            }
        } else {
            let layout = DialLayout(plannedMinutes: model.minutes)
            let preview = DialFrame.preview(layout: layout, leafMinute: lines.leafMinute, fill: fill)
            // While Locked's hold is pressed, its progress fills the marks clockwise (§4.7).
            MinuteDial(frame: holdProgress > 0 ? .hold(progress: holdProgress, layout: layout, base: preview) : preview,
                       diameter: diameter, theme: theme) {
                DialCentre(leaf: species.map { DialLeaf(species: $0, fill: fill) },
                           numeral: DialCentre.numeralParts(model.lengthText), caption: model.caption, diameter: diameter)
            }
            .dialTurning(minutes: length(of: model.preset), enabled: model.canTurn) {
                tab.hasTurnedDial = true
            }
        }
    }

    /// This session's length: the dial's turn, or the preset's own. Turning changes only this session (§4.5).
    private func length(of preset: FocusPreset) -> Binding<Int> {
        Binding(get: { tab.minutes ?? preset.minutes }, set: { tab.minutes = $0 })
    }

    // MARK: Under the dial

    private func details(_ model: StartScreenModel, lines: FocusStartLines, session: SessionRecord?) -> some View {
        VStack(spacing: 0) {
            if dynamicTypeSize.isAccessibilitySize {
                timeLine(model, session: session)
            }
            if model.showsDetails {
                PresetChips(selectedID: model.preset.id) { choose($0) }
                    .padding(.top, theme.spacing.md)
                intentionLine
                    .padding(.top, theme.spacing.xs)
                if let plainLine = lines.plainLine {
                    Text(plainLine)
                        .font(MapleFont.callout)
                        .foregroundStyle(theme.colors.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: theme.spacing.minimumHitTarget, alignment: .leading)
                } else {
                    blockingLine(model.blockingLine)
                }
                detailLine(lines)
            }
        }
    }

    /// §5.17: the centre numeral caps at xxLarge, so at accessibility sizes the time is repeated under the dial.
    private func timeLine(_ model: StartScreenModel, session: SessionRecord?) -> some View {
        Group {
            if let session {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(FocusTimeText.remaining(session.plannedEnd.timeIntervalSince(FocusRoute.frameTime(session, now: sessions.now))))
                }
            } else {
                Text(model.lengthText)
            }
        }
        .font(MapleFont.headline)
        .monospacedDigit()
        .foregroundStyle(theme.colors.textPrimary)
        .padding(.top, theme.spacing.sm)
        // The dial already reads the time to VoiceOver.
        .accessibilityHidden(true)
    }

    /// "What's this for?", or the intention once written (§5.16), over a dashed rule; it opens intention entry.
    private var intentionLine: some View {
        let intention = tab.intention.flatMap { RecentIntentions.normalized($0) }
        return Button { tab.sheet = .intention } label: {
            Text(intention ?? FocusCopy.intentionPrompt)
                .font(MapleFont.callout)
                .foregroundStyle(intention == nil ? theme.colors.textSecondary : theme.colors.textPrimary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, theme.spacing.sm)
                .overlay(alignment: .bottom) {
                    DashedRule()
                        .stroke(theme.colors.borderHighlight, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .frame(height: 1)
                }
                .frame(minHeight: theme.spacing.minimumHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// "Blocking 6 apps · Steady ›" (§5.1, §5.2), and every prompt in its place; it opens the Blocking sheet.
    private func blockingLine(_ line: SelectionText.BlockingLine) -> some View {
        Button { tab.sheet = .blocking } label: {
            blockingText(line)
                .font(MapleFont.callout)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: theme.spacing.minimumHitTarget, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(line.spoken)
    }

    /// What is blocked in `textPrimary`; the strictness and the chevron in `textSecondary`, with Locked's lock.
    private func blockingText(_ line: SelectionText.BlockingLine) -> Text {
        let parts = FocusStartLines.blockingParts(line)
        let lock = parts.showsLock ? Text(Image(systemName: "lock.fill")) : Text(verbatim: "")
        let rest = Text("\(Text(verbatim: parts.separator ?? ""))\(lock)\(Text(verbatim: parts.trailing))")
        return Text("\(Text(verbatim: parts.main).foregroundStyle(theme.colors.textPrimary))\(rest.foregroundStyle(theme.colors.textSecondary))")
    }

    /// The one line under the Blocking line: the counts line, the hint, a notice or the failed lock's prompt
    /// (`DetailLine`). While the primary is a hold, the line keeps room for the plain-tap hint, which runs to two lines
    /// where the counts line takes one. So a tap showing the hint moves nothing, and the dial stays put (§5.2).
    private func detailLine(_ lines: FocusStartLines) -> some View {
        DetailLine(
            words: lines.detailLine.map { DetailWords(text: $0, spoken: lines.detailSpoken ?? $0, marksLeaf: lines.marksLeaf) },
            reserving: lines.primary == .holdToStart
                ? DetailWords(text: FocusCopy.holdHint, spoken: FocusCopy.holdHint, marksLeaf: false) : nil
        )
    }

    // MARK: Primary

    @ViewBuilder
    private func primary(_ model: StartScreenModel, lines: FocusStartLines) -> some View {
        switch lines.primary {
        case .start:
            Button { start(model, lines: lines) } label: { capsuleWords(lines) }
                .buttonStyle(.moonlight(dimmed: model.capsuleIsDimmed))
                // "Start study, 50 minutes": VoiceOver never reads a length as "50m" (§4.9).
                .accessibilityLabel(lines.capsuleSpoken)
        case .holdToStart:
            HoldButton(
                title: lines.capsuleTitle, duration: FocusCopy.holdToStartSeconds,
                accessibilityName: lines.holdName ?? lines.capsuleTitle, progress: $holdProgress,
                frozenProgress: frozenHold, onTap: { hintShownAt = Date() }
            ) {
                start(model, lines: lines)
            }
        case .chooseApps:
            Button { tab.sheet = .blocking } label: { capsuleWords(lines) }
                .buttonStyle(.moonlight(dimmed: model.capsuleIsDimmed))
        case .locking:
            Button {} label: { capsuleWords(lines) }
                .buttonStyle(.moonlight)
                .disabled(true)
        case .returnToSession:
            Button { tab.isMinimised = false } label: { capsuleWords(lines) }
                .buttonStyle(.moonlight)
        }
    }

    /// The capsule's words, whole at any size: at accessibility sizes "Start a quick session · 25m" needs a third
    /// line, which the capsule's own two-line limit would cut off (§5.17). A limit set on the label itself wins over
    /// it; at other sizes it keeps the capsule's one line.
    private func capsuleWords(_ lines: FocusStartLines) -> some View {
        Text(lines.capsuleTitle).lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
    }

    /// DEBUG `-MapleDemoHoldAt`: the hold frozen part-way, for screenshots.
    private var frozenHold: Double? {
        #if DEBUG
        DemoLaunchOptions.current.holdAt
        #else
        nil
        #endif
    }

    // MARK: Actions

    private var mode: FocusStartLines.Mode {
        switch tab.plainTimer {
        case nil: .blocking
        case .chosen: .plainTimer
        case .lockFailed: .lockFailed
        }
    }

    /// The chip picked (or asked for by Home's Start), else Quick for the first session (P4), else the last used.
    private var selectedPreset: FocusPreset? {
        FocusStartLines.preset(selected: tab.selectedPresetID, presets: presets.presets, lastUsedID: presets.lastUsedID,
                               isFirstSession: !settings.hasStartedFocus)
    }

    /// The minimised session, while it still runs.
    private var runningSession: SessionRecord? {
        guard let minimised, let running = sessions.running, running.id == minimised else { return nil }
        return running
    }

    private func choose(_ preset: FocusPreset) {
        tab.selectedPresetID = preset.id
        tab.minutes = nil
        notice = nil
        // Another choice tries the block again.
        if tab.plainTimer == .lockFailed { tab.plainTimer = nil }
    }

    private func start(_ model: StartScreenModel, lines: FocusStartLines) {
        guard let focusStores, !sessions.isStarting else { return }
        let preset = model.preset
        let request = FocusSessionStore.StartRequest(
            preset: preset, minutes: model.minutes,
            appSet: lines.startsPlainTimer ? nil : preset.appSetID.flatMap { appSets.set(id: $0) },
            plainTimer: lines.startsPlainTimer, from: .focusTab
        )
        let intention = tab.intention.flatMap { RecentIntentions.normalized($0) }
        let isFirstStart = !settings.hasStartedFocus
        notice = nil
        hintShownAt = nil
        Task {
            let outcome = await focusStores.start(request, intention: intention, settings: settings)
            await settle(outcome, isFirstStart: isFirstStart)
        }
    }

    /// What follows a start. By `.started` the session's own screen has already replaced this one; the tab's state
    /// carries what is left to do.
    private func settle(_ outcome: FocusSessionStore.StartOutcome, isFirstStart: Bool) async {
        holdProgress = 0
        switch outcome {
        case .started(let id):
            tab.lastStarted = id
            tab.minutes = nil
            tab.intention = nil
            // F1-23: asked once, at the first start, if iOS hasn't asked yet; never on a demo launch.
            if isFirstStart, reminders.schedulesReminders, reminders.authorization == .notDetermined {
                await reminders.requestAuthorization()
            }
        case .alreadyRunning:
            break
        case .blockingFailed:
            tab.plainTimer = .lockFailed
        case .ledgerUnavailable, .notRecorded:
            notice = FocusStartLines.couldntStart
        }
    }

    private func hideHint() async {
        guard hintShownAt != nil else { return }
        try? await Task.sleep(for: .seconds(FocusCopy.holdHintSeconds))
        guard !Task.isCancelled else { return }
        hintShownAt = nil
    }
}

/// The detail line's words, how VoiceOver reads them (lengths in words), and whether they name the leaf (and so carry
/// the dot's mark). A change of the words or the mark cross-fades the line.
private struct DetailWords: Hashable {
    let text: String
    let spoken: String
    let marksLeaf: Bool
}

/// The start screen's line under the Blocking line (§5.1, §5.2): the counts line, the hint, a notice or the failed
/// lock's prompt.
///
/// - **Layout:** the words, and a hidden copy of `reserving` (the hint, under a hold), give the line its height, so it
///   changes at once and never animates (§4.6). The words fading out sit in an overlay, which takes no room.
/// - **The cross-fade:** new words fade in over the old ones fading out, by opacity alone (§4.6). It is stepped by
///   hand, 30 times a second from a task, as `HoldButton` steps its fill, not by a SwiftUI animation or transition. On
///   device, the transition a plain tap on the hold started (from inside the hold gesture's `onEnded`) never ran, so
///   the counts line stayed on screen though the hint had replaced it. The new words are drawn from `words` itself,
///   so whatever happens to the fade, the line always says what the screen decided.
private struct DetailLine: View {
    /// `theme.motion.gentle`'s length.
    private static let fadeSeconds = 0.6

    @Environment(\.theme) private var theme
    @Environment(\.season) private var season

    let words: DetailWords?
    let reserving: DetailWords?

    /// The words the last cross-fade went to, and the ones it is fading out.
    @State private var settled: DetailWords?
    @State private var leaving: DetailWords?
    /// 0…1 through the cross-fade.
    @State private var progress = 1.0
    @State private var fade: Task<Void, Never>?

    init(words: DetailWords?, reserving: DetailWords?) {
        self.words = words
        self.reserving = reserving
        _settled = State(initialValue: words)
    }

    var body: some View {
        // Before `onChange` has started the fade for new words, they show as they are.
        let fading = words == settled
        let eased = progress * progress * (3 - 2 * progress)
        ZStack(alignment: .topLeading) {
            if let reserving {
                row(reserving)
                    .hidden()
                    .accessibilityHidden(true)
            }
            if let words {
                row(words)
                    .opacity(fading ? eased : 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .overlay(alignment: .topLeading) {
            if fading, let leaving {
                row(leaving)
                    .opacity(1 - eased)
                    .accessibilityHidden(true)
            }
        }
        .padding(.top, words != nil || reserving != nil ? theme.spacing.xxs : 0)
        .onChange(of: words) { _, new in crossFade(to: new) }
        .onDisappear {
            fade?.cancel()
            fade = nil
            leaving = nil
            settled = words
            progress = 1
        }
    }

    /// The words, and the dot's mark before a line naming the leaf.
    private func row(_ words: DetailWords) -> some View {
        HStack(spacing: 7) {
            if words.marksLeaf {
                Circle()
                    .fill(theme.colors.seasonTint(season))
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
            }
            Text(words.text)
                .font(MapleFont.footnote)
                .foregroundStyle(theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(words.spoken)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Fades from what is on screen to `new`, by stepping `progress` (no SwiftUI animation).
    private func crossFade(to new: DetailWords?) {
        fade?.cancel()
        leaving = settled == new ? nil : settled
        settled = new
        progress = 0
        fade = Task {
            let start = Date()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.0 / 30))
                guard !Task.isCancelled else { return }
                let step = min(1, Date().timeIntervalSince(start) / Self.fadeSeconds)
                progress = step
                if step >= 1 {
                    leaving = nil
                    fade = nil
                    return
                }
            }
        }
    }
}

/// A horizontal line through the middle of its frame: the intention line's dashed rule.
nonisolated private struct DashedRule: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}
