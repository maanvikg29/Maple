import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// The running session (F1 design §5.4) and its break (§5.5), drawn from the store, so a killed app comes back to the
/// same session. One view for both routes (`FocusRoute.running` and `.breakTime`), so a break starting or running out
/// keeps the screen's state; the break's own layout is `BreakView`.
///
/// - The dial samples once a second from `FocusSessionStore.now` (`TimelineView(.periodic)`): here, never at the app
///   root (P6).
/// - After 30 seconds without a touch only the bloom and the marks dim, to 50% (§4.6), never under VoiceOver or
///   Increase Contrast. While dimmed, the first touch only wakes the screen. Auto-Lock is left alone.
/// - ⌄ minimises the session, which keeps running (`FocusTabState.isMinimised`).
/// - Each leaf opening is announced once, and so is the break running out (§4.9). A break that runs out in front of
///   the member also plays a soft haptic; one that ran out while Maple was away returns to the session quietly.
/// - Magic Tap moves VoiceOver to the session's controls.
/// - The way out (Task 12): End early's sheet (Gentle, Steady), then the breath and the second question in this
///   screen's place (`EndBreathView`, F1-32); or the emergency release in this screen's place (Locked). A plain timer
///   locks nothing, so its way out is Gentle's whatever its preset (`SessionEndPath(_:)` on the plan). Settings'
///   "Release all apps" arrives here during a session (`FocusTabState.releasesAll`).
struct RunningSessionView: View {
    let sessionID: UUID

    @Environment(\.theme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(FocusSessionStore.self) private var sessions
    @Environment(SessionNotesStore.self) private var notes
    @Environment(CollectionStore.self) private var collection
    @Environment(FocusTabState.self) private var tab

    /// The last touch, on the store's trusted time: the screen dims 30 seconds after it.
    @State private var lastTouch: Date?
    @State private var isTakingBreak = false
    @State private var isEndingBreak = false
    /// How many of this session's leaf openings have been announced, so each is announced once.
    @State private var announcedLeaves = 0
    /// Bumped when the break runs out in front of the member: one soft haptic.
    @State private var breakRanOut = 0
    @AccessibilityFocusState private var controlsFocused: Bool
    /// End early's sheet over the session (Gentle, Steady, §5.6).
    @State private var showsEndEarly = false
    /// Locked's emergency release, in this screen's place (§5.7).
    @State private var showsEmergency = false
    /// When the emergency hold completed, on trusted time: the breath starts at once, before the store has ended the
    /// session and the receipt has taken over.
    @State private var releasedAt: Date?
    /// The sheet's way out was taken: the breath starts once the sheet has gone.
    @State private var breathesWhenDismissed = false
    /// When the breath began, on trusted time: it and the second question take this screen's place (F1-32).
    @State private var breathStartedAt: Date?
    /// "End session" was tapped after the breath: the store is ending the session.
    @State private var isEnding = false
    /// Settings' "Release all apps" came this way: completing the way out also clears every store (§5.12).
    @State private var releasesAll = false

    init(sessionID: UUID) {
        self.sessionID = sessionID
    }

    var body: some View {
        Group {
            if showsEmergency, let session {
                EmergencyReleaseView(
                    session: session, stage: emergencyStage, frozenSeconds: frozenBreath,
                    onKeepGoing: keepGoing, onRelease: release, onDone: releaseDone
                )
            } else if let breathStartedAt, let session {
                EndBreathView(
                    session: session, path: endPath, subtitle: model(session, now: sessions.now).restingLine,
                    startedAt: breathStartedAt, frozenSecondsLeft: frozenBreathLeft,
                    isEnding: isEnding, onKeepGoing: keepGoingAfterBreath, onEnd: endAfterBreath
                )
            } else {
                sessionScreen
            }
        }
        .sheet(isPresented: $showsEndEarly, onDismiss: endEarlyDismissed) {
            if let session {
                EndEarlySheet(
                    session: session, path: endPath,
                    onKeepGoing: { showsEndEarly = false },
                    onBreakInstead: breakInstead,
                    onContinue: {
                        breathesWhenDismissed = true
                        showsEndEarly = false
                    }
                )
                #if DEBUG
                .revealDemoMotion()
                #endif
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Leaving the foreground cancels the way out, as it cancels a hold (§5.7): back to the session.
            if phase != .active, breathStartedAt != nil, !isEnding, frozenBreathLeft == nil { keepGoingAfterBreath() }
        }
        .onChange(of: tab.releasesAll, initial: true) { _, asked in
            // Settings' "Release all apps" during this session (`FocusReleaseRouter`).
            guard asked else { return }
            tab.releasesAll = false
            releasesAll = true
            takeEndPath()
        }
    }

    /// The release's stage: the hold, or the breath from the moment the hold completed.
    private var emergencyStage: EmergencyReleaseView.Stage {
        if let frozenBreath { return .released(endedAt: sessions.now.addingTimeInterval(-frozenBreath)) }
        return releasedAt.map { .released(endedAt: $0) } ?? .holding
    }

    /// DEBUG still frames: `-MapleDemoFinishAt <s>` with `-MapleDemoFocus emergency` freezes the release's breath that
    /// many seconds in, while the demo's session keeps running behind it.
    private var frozenBreath: Double? {
        #if DEBUG
        let options = DemoLaunchOptions.current
        return options.focus == .emergency ? options.finishAt : nil
        #else
        return nil
        #endif
    }

    /// DEBUG still frames: `-MapleDemoEndCountdown <s>` freezes the breath with that many seconds left (0 is the
    /// second question). It never ends the session by itself.
    private var frozenBreathLeft: Double? {
        #if DEBUG
        return DemoLaunchOptions.current.endCountdown.map(Double.init)
        #else
        return nil
        #endif
    }

    // MARK: The screen

    /// The running session this screen shows; nil in the moment after it ends, before the route moves on.
    private var session: SessionRecord? {
        sessions.running.flatMap { $0.id == sessionID ? $0 : nil }
    }

    /// By the strictness that applies to the session: a plain timer's is Gentle's whatever its preset.
    private var endPath: SessionEndPath {
        session.map { SessionEndPath($0.plan) } ?? .steady
    }

    /// The break while one runs, otherwise the running dial, sampled once a second. Past the planned end it keeps its
    /// last frame, never 0:00, until the refresh that ends the session brings the receipt (`FocusRoute.frameTime`).
    private var sessionScreen: some View {
        let session = self.session
        return TimelineView(.periodic(from: .now, by: 1)) { _ in
            if let session {
                screen(session, now: FocusRoute.frameTime(session, now: sessions.now))
            } else {
                Color.clear
            }
        }
        // Any touch counts, on the break too (§4.6).
        .simultaneousGesture(TapGesture().onEnded(wake))
        .onAppear(perform: appeared)
        .onChange(of: scenePhase) { _, phase in
            // Coming back to Maple counts as a touch.
            if phase == .active { wake() }
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.5), trigger: breakRanOut)
        .accessibilityAction(.magicTap) { controlsFocused = true }
    }

    @ViewBuilder
    private func screen(_ session: SessionRecord, now: Date) -> some View {
        let inBreak = session.isInBreak(at: now)
        // Read during the break too, so a leaf that opens while it runs is announced as it opens.
        let model = model(session, now: now)
        Group {
            if inBreak, let breakModel = BreakScreenModel(
                session: session, now: now, intention: notes.intention(for: session.id), locale: locale,
                calendar: collection.context.calendar
            ) {
                BreakView(
                    model: breakModel, isEndingBreak: isEndingBreak, onMinimise: minimise, onBackToStudying: backToStudying,
                    onEndPath: takeEndPath, controlsFocused: $controlsFocused
                )
            } else {
                running(model, session: session, now: now)
            }
        }
        .onChange(of: inBreak) { wasInBreak, isInBreak in
            guard wasInBreak, !isInBreak, BreakScreenModel.ranOutJustNow(session, at: now) else { return }
            breakRanOut += 1
            AccessibilityNotification.Announcement(BreakScreenModel.endedAnnouncement).post()
        }
        .onChange(of: model.openedCount) { _, count in
            announceLeaf(model.leafAnnouncement, count: count)
        }
    }

    private func running(_ model: RunningSessionModel, session: SessionRecord, now: Date) -> some View {
        let dimmed = FocusDimming.isDimmed(
            idleFor: now.timeIntervalSince(lastTouch ?? now), voiceOver: voiceOver, increasedContrast: contrast == .increased
        )
        return SessionScreen(title: model.title, subtitle: model.restingLine, onMinimise: minimise) { diameter in
            dial(model, session: session, now: now, diameter: diameter, dimmed: dimmed)
        } lines: {
            if dynamicTypeSize.isAccessibilitySize {
                // The dial's centre stops growing at xxLarge, so the time is repeated where it can grow (§5.17).
                Text(model.timeLine)
                    .font(MapleFont.headline)
                    .foregroundStyle(theme.colors.textPrimary)
                    .accessibilityHidden(true)
            }
            if let line = model.leafLine {
                // Cross-fades by opacity alone only as the leaf opens, the opened line bringing in the amber bud as the leaf
                // turns gold (§4.6); the minutes to go change at once, so the line never pulses.
                FadingLine(LeafLineWords(line: line, opened: model.leafOpened), key: model.leafOpened) { words in
                    LeafLineRow(words: words)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(model.leafSpoken ?? line.text))
            }
            if let first = model.firstSessionLine {
                Text(first)
                    .font(MapleFont.footnote)
                    .foregroundStyle(theme.colors.textSecondary)
            }
        } controls: {
            if let breakTitle = model.breakTitle {
                SessionActionRow {
                    Button(breakTitle, action: takeBreak)
                        .buttonStyle(.glassCapsule)
                        .disabled(isTakingBreak)
                        .accessibilityFocused($controlsFocused)
                } second: {
                    Button(model.endPath.title, action: takeEndPath)
                        .buttonStyle(.glassCapsule)
                }
            } else {
                Button(model.endPath.title, action: takeEndPath)
                    .buttonStyle(.glassCapsule)
                    .accessibilityFocused($controlsFocused)
            }
        }
        .overlay {
            if dimmed {
                // While dimmed, the first touch only wakes the screen (§4.6).
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: wake)
                    .accessibilityHidden(true)
            }
        }
    }

    /// The live dial: the passed minutes lit, the current mark tinted, the leaf dot, and in the centre the leaf, the
    /// time left and "left of 50m". VoiceOver reads it as one element (§4.9).
    private func dial(
        _ model: RunningSessionModel, session: SessionRecord, now: Date, diameter: CGFloat, dimmed: Bool
    ) -> some View {
        let layout = DialLayout(plannedMinutes: session.plan.plannedMinutes)
        let fill = DialFill(before: model.fillBefore, session: model.fillSession, opened: model.leafOpened ? 1 : 0)
        let frame = DialFrame.running(
            layout: layout, elapsed: now.timeIntervalSince(session.countdownStart), leafMinute: model.leafMinute, fill: fill
        )
        let leaf = model.centreLeaf.flatMap { LeafCatalog.shared.species(id: $0) }
        return MinuteDial(frame: frame.dimmed(dimmed), diameter: diameter, theme: theme) {
            DialCentre(
                leaf: leaf.map { DialLeaf(species: $0, fill: fill) }, numeral: DialCentre.numeralParts(model.remaining),
                caption: model.caption, diameter: diameter
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(model.spoken))
    }

    // MARK: The model

    private func model(_ session: SessionRecord, now: Date) -> RunningSessionModel {
        let schedule = collection.schedule
        let calendar = collection.context.calendar
        // The counters' hours already hold this session's counted seconds.
        let counted = RunningSessionModel.CountedTime(
            sessions.credit(for: session.id), hoursSaved: collection.snapshot.counters[.hoursSaved] ?? 0, session: session
        )
        let opened = RunningSessionModel.opened(sessions.sessionUnlocks, session: session, counted: counted) { unlock in
            RevealSchedule.isHeld(unlock, at: now, schedule: schedule, calendar: calendar)
        }
        return RunningSessionModel(
            session: session, now: now, intention: notes.intention(for: session.id),
            leaf: RunningSessionModel.Leaf(next: collection.progress(at: now)), opened: opened,
            counted: counted, displaySeconds: sessions.countedSoFar(session.id),
            roomLeftToday: max(0, HoursCredit.dailyCap - sessions.displayCredit(at: now).today),
            isFirstSession: RunningSessionModel.isFirstSession(session, among: sessions.sessions, book: collection.focus),
            locale: locale
        )
    }

    // MARK: Actions

    private func appeared() {
        wake()
        #if DEBUG
        applyDemo()
        #endif
    }

    private func wake() {
        lastTouch = sessions.now
    }

    private func minimise() {
        tab.isMinimised = true
    }

    private func takeBreak() {
        wake()
        guard !isTakingBreak else { return }
        isTakingBreak = true
        Task {
            // False when the block couldn't be read back first: the session carries on, and the button stays.
            _ = await sessions.startBreak()
            isTakingBreak = false
        }
    }

    private func backToStudying() {
        wake()
        guard !isEndingBreak else { return }
        isEndingBreak = true
        Task {
            await sessions.endBreak()
            isEndingBreak = false
        }
    }

    /// "End early" or "Emergency release", by the strictness that applies to the session.
    private func takeEndPath() {
        wake()
        switch endPath {
        case .emergency: showsEmergency = true
        case .gentle, .steady: showsEndEarly = true
        }
    }

    /// The sheet has gone: the breath starts if its way out was taken; otherwise the member kept going.
    private func endEarlyDismissed() {
        wake()
        guard breathesWhenDismissed else {
            releasesAll = false
            return
        }
        breathesWhenDismissed = false
        isEnding = false
        breathStartedAt = sessions.now
    }

    /// "Keep going", during the breath or at the second question: back to the session, nothing changed.
    private func keepGoingAfterBreath() {
        releasesAll = false
        breathStartedAt = nil
        isEnding = false
        wake()
    }

    /// "End session" at the second question (F1-32): only now does the session end. The breath's screen stays until
    /// the receipt takes over; if the store couldn't end it, the question is there to answer again.
    private func endAfterBreath() {
        guard !isEnding else { return }
        isEnding = true
        let clearsAll = releasesAll
        releasesAll = false
        Task {
            // Through Release all apps the store ends the session as `.releaseAll` while it clears every store (R4).
            if clearsAll {
                await sessions.releaseAll()
            } else {
                await sessions.end(.endedEarly)
            }
            isEnding = false
        }
    }

    /// "Take a 5-minute break instead": the sheet closes and the break starts, cut short at the planned end.
    private func breakInstead() {
        releasesAll = false
        showsEndEarly = false
        takeBreak()
    }

    /// The emergency release's "Keep going": back to the session, nothing changed.
    private func keepGoing() {
        releasesAll = false
        showsEmergency = false
        wake()
    }

    /// The 10-second hold completed: the release happens now, so the breath can't trap anyone (§5.7). Each use is
    /// logged as `sessionEnded(emergencyRelease)`; through Release all apps every store is cleared after it.
    private func release() {
        guard releasedAt == nil else { return }
        releasedAt = sessions.now
        let clearsAll = releasesAll
        releasesAll = false
        Task {
            await sessions.end(.emergencyRelease)
            if clearsAll { await sessions.releaseAll() }
        }
    }

    /// The ended state's "Done" while this screen still shows it: the store didn't end the session (`end` can fail
    /// quietly), so the member goes back to the session with its tab bar, never kept on a screen with no way out
    /// (§5.7).
    private func releaseDone() {
        showsEmergency = false
        releasedAt = nil
        wake()
    }

    /// Each leaf opening, announced once as it happens (a milestone, §4.9), on the break too: "Field maple is yours. It
    /// opens after this session.", and "2 new leaves are yours." when a second opens. `count` is how many have opened.
    private func announceLeaf(_ text: String?, count: Int) {
        guard let text, count > announcedLeaves else { return }
        announcedLeaves = count
        AccessibilityNotification.Announcement(text).post()
    }

    #if DEBUG
    /// Applied once per launch, so a demo's state doesn't come back after the member changes it.
    private static var demoApplied = false

    /// `-MapleDemoFocus dimmed`: the screen as it is 30 seconds after the last touch. `-MapleDemoFocus endEarly`: End
    /// early's sheet over it. `-MapleDemoEndCountdown <s>`: the breath after it, frozen with that many seconds left.
    /// `-MapleDemoFocus emergency`: the emergency release.
    private func applyDemo() {
        guard !Self.demoApplied else { return }
        Self.demoApplied = true
        let options = DemoLaunchOptions.current
        if options.focus == .dimmed {
            lastTouch = sessions.now.addingTimeInterval(-FocusDimming.delay)
        }
        if options.endCountdown != nil {
            breathStartedAt = sessions.now
        } else if options.focus == .endEarly {
            showsEndEarly = true
        }
        if options.focus == .emergency {
            showsEmergency = true
        }
    }
    #endif
}
