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
/// - The leaf opening and the break running out are announced once each (§4.9). A break that runs out in front of
///   the member also plays a soft haptic; one that ran out while Maple was away returns to the session quietly.
/// - Magic Tap moves VoiceOver to the session's controls.
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
    /// The leaf whose opening was announced, so it is announced once.
    @State private var announcedLeaf: String?
    /// Bumped when the break runs out in front of the member: one soft haptic.
    @State private var breakRanOut = 0
    @AccessibilityFocusState private var controlsFocused: Bool
    // The way out (Task 12 replaces this with End early and the emergency release).
    @State private var showsEndPath = false

    init(sessionID: UUID) {
        self.sessionID = sessionID
    }

    var body: some View {
        sessionScreen
            // Task 12 replaces this with End early and the emergency release.
            .sheet(isPresented: $showsEndPath) {
                FocusPlaceholder(endPath.title)
                    .presentationDetents([.medium])
                    .presentationBackground(theme.colors.surface2)
            }
    }

    // MARK: The screen

    /// The running session this screen shows; nil in the moment after it ends, before the route moves on.
    private var session: SessionRecord? {
        sessions.running.flatMap { $0.id == sessionID ? $0 : nil }
    }

    private var endPath: SessionEndPath {
        SessionEndPath(session?.plan.strictness ?? .steady)
    }

    /// The break while one runs, otherwise the running dial, sampled once a second.
    private var sessionScreen: some View {
        let session = self.session
        return TimelineView(.periodic(from: .now, by: 1)) { _ in
            if let session {
                screen(session, now: sessions.now)
            } else {
                Color.clear
            }
        }
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
        Group {
            if inBreak, let model = BreakScreenModel(
                session: session, now: now, intention: notes.intention(for: session.id), locale: locale,
                calendar: collection.context.calendar
            ) {
                BreakView(
                    model: model, isEndingBreak: isEndingBreak, onMinimise: minimise, onBackToStudying: backToStudying,
                    onEndPath: takeEndPath, controlsFocused: $controlsFocused
                )
            } else {
                running(model(session, now: now), session: session, now: now)
            }
        }
        .onChange(of: inBreak) { wasInBreak, isInBreak in
            guard wasInBreak, !isInBreak, BreakScreenModel.ranOutJustNow(session, at: now) else { return }
            breakRanOut += 1
            AccessibilityNotification.Announcement(BreakScreenModel.endedAnnouncement).post()
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
                Text(leafText(line))
                    .font(MapleFont.callout)
                    .foregroundStyle(theme.colors.textPrimary)
                    .contentTransition(.opacity)
                    .mapleAnimation(theme.motion.gentle, value: model.leafOpened)
                    .accessibilityLabel(Text(line.text))
            }
            if let first = model.firstSessionLine {
                Text(first)
                    .font(MapleFont.footnote)
                    .foregroundStyle(theme.colors.textSecondary)
            }
        } controls: {
            if let breakTitle = model.breakTitle {
                Button(breakTitle, action: takeBreak)
                    .buttonStyle(.glassCapsule)
                    .disabled(isTakingBreak)
                    .accessibilityFocused($controlsFocused)
                TextLink(model.endPath.title, chevron: false, action: takeEndPath)
            } else {
                TextLink(model.endPath.title, chevron: false, action: takeEndPath)
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
        .simultaneousGesture(TapGesture().onEnded(wake))
        .onChange(of: model.leafAnnouncement) { _, text in
            announceLeaf(text, leaf: model.centreLeaf)
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

    /// "Field maple" in the primary colour, "· 17m to go" in the secondary.
    private func leafText(_ line: RunningSessionModel.Line) -> AttributedString {
        var text = AttributedString(line.lead)
        if let trail = line.trail {
            var rest = AttributedString(" \(trail)")
            rest.foregroundColor = theme.colors.textSecondary
            text.append(rest)
        }
        return text
    }

    // MARK: The model

    private func model(_ session: SessionRecord, now: Date) -> RunningSessionModel {
        let schedule = collection.schedule
        let calendar = collection.context.calendar
        let opened = RunningSessionModel.opened(sessions.sessionUnlocks, session: session) { unlock in
            RevealSchedule.isHeld(unlock, at: now, schedule: schedule, calendar: calendar)
        }
        return RunningSessionModel(
            session: session, now: now, intention: notes.intention(for: session.id),
            leaf: RunningSessionModel.Leaf(next: collection.progress(at: now)), opened: opened,
            countedSeconds: sessions.credit(for: session.id)?.seconds ?? 0, displaySeconds: sessions.countedSoFar(session.id),
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
        guard !isEndingBreak else { return }
        isEndingBreak = true
        Task {
            await sessions.endBreak()
            isEndingBreak = false
        }
    }

    private func takeEndPath() {
        wake()
        showsEndPath = true
    }

    /// The leaf's opening, announced once (a milestone, §4.9).
    private func announceLeaf(_ text: String?, leaf: String?) {
        guard let text, let leaf, announcedLeaf != leaf else { return }
        announcedLeaf = leaf
        AccessibilityNotification.Announcement(text).post()
    }

    #if DEBUG
    /// Applied once per launch, so a demo's state doesn't come back after the member changes it.
    private static var demoApplied = false

    /// `-MapleDemoFocus dimmed`: the screen as it is 30 seconds after the last touch.
    private func applyDemo() {
        guard !Self.demoApplied else { return }
        Self.demoApplied = true
        let options = DemoLaunchOptions.current
        if options.focus == .dimmed {
            lastTouch = sessions.now.addingTimeInterval(-FocusDimming.delay)
        }
    }
    #endif
}
