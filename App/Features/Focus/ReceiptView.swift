import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// The session's final frame (F1 design §5.8): "Study · Chemistry ch. 4" over "Apps open again", with no ⌄.
///
/// - **The finish (§4.6)** plays once, when the receipt first shows, and only within 10 minutes of the end
///   (`ReceiptModel.playsFinish`, decided once at `shownAt`): the counted marks sweep gold (or every mark white when
///   nothing counted), an opened leaf grows into the centre, the glow pulses, a ring ripples out, the numeral, the
///   leaf line, then Done and Again fade in, and a soft impact plays. Later, the final frame shows still.
/// - "50m" over "saved · 2h 10m today"; tapping the dial (its numeral) opens Saved today.
/// - The leaf line, the breakdown, "How did it go?" (All done · Partly · Not yet), Done, and "Again · 50m", which
///   follows start readiness: one tap, a hold in Locked, or the start screen when it has something to say.
/// - An emergency release shows §5.7's breath and ended state instead (`EmergencyReleaseView`).
/// - Shown once: the first look marks it seen (`AppSettings.lastReceiptSeen`); the tab keeps it on screen until Done
///   (`FocusTabState.shownReceipt`). A notification tap shows it again (`FocusRequest.receipt`).
struct ReceiptView: View {
    let sessionID: UUID

    @Environment(\.theme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.focusStores) private var focusStores
    @Environment(FocusSessionStore.self) private var sessions
    @Environment(PresetStore.self) private var presets
    @Environment(AppSetStore.self) private var appSets
    @Environment(SessionNotesStore.self) private var notes
    @Environment(CollectionStore.self) private var collection
    @Environment(AppSettings.self) private var settings
    @Environment(FocusTabState.self) private var tab

    /// When the receipt first showed, on trusted time: the finish and the leaf lines are decided at this moment.
    @State private var shownAt: Date?
    /// The finish's first frame, on the wall clock that drives the timeline.
    @State private var finishStart = Date()
    /// The finish has come to rest: the timeline stops.
    @State private var isSettled = false
    /// The finish's announcement and soft impact have played for this showing, so a return to the receipt (another
    /// tab and back) never plays them again (§4.6 "it plays once", §4.9).
    @State private var finishPlayed = false
    @State private var finishImpact = 0
    @State private var againProgress = 0.0
    @State private var isStarting = false

    init(sessionID: UUID) {
        self.sessionID = sessionID
    }

    var body: some View {
        Group {
            if let session, let shownAt {
                receipt(session, shownAt: shownAt)
            } else {
                Color.clear
            }
        }
        .onAppear(perform: appeared)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.5), trigger: finishImpact)
    }

    private var session: SessionRecord? {
        sessions.sessions.first { $0.id == sessionID }
    }

    // MARK: The receipt

    @ViewBuilder
    private func receipt(_ session: SessionRecord, shownAt: Date) -> some View {
        let unlocks = ReceiptFlow.unlocks(
            store: sessions.sessionUnlocks, storeSession: sessions.lastEnded?.id, collection: collection.unlocks,
            session: session
        )
        let next = focusStores?.nextHoursLeaf(at: shownAt, collection: collection)
        let model = ReceiptModel(
            session: session, credit: sessions.credit(for: session.id), unlocks: unlocks,
            heldUntilMorning: ReceiptFlow.heldUntilMorning(
                unlocks, schedule: collection.schedule, calendar: collection.context.calendar, at: shownAt
            ),
            next: next, todaySeconds: collection.focus.seconds(on: session.plan.day), reflection: session.reflection,
            now: shownAt, locale: locale, calendar: collection.context.calendar
        )
        if model.ending == .emergency {
            EmergencyReleaseView(
                session: session, stage: .released(endedAt: session.endedAt ?? shownAt), receipt: model,
                frozenSeconds: frozenFinish, onDone: done
            )
        } else {
            let centre = ReceiptFlow.centreLeaf(unlocks: unlocks, next: next, canCount: session.plan.canCount)
            let fill = centreFill(centre, next: next, countedSeconds: model.countedSeconds)
            let frame = DialFrame.receipt(marks: model.marks, isGold: model.isGold, fill: fill)
            let plays = model.playsFinish && frozenFinish == nil
            // Once a minute, so Again follows start readiness as the clock moves on (wind-down starting while the
            // receipt is open sends Again to the start screen). It is read here, not in the finish's frames.
            TimelineView(.everyMinute) { _ in
                let again = model.again == nil ? nil : againAction(session)
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !plays || isSettled)) { context in
                    let time = frozenFinish ?? (plays
                        ? context.date.timeIntervalSince(finishStart)
                        : FinishTimeline.settledTime(markCount: frame.marks.count, reduceMotion: reduceMotion))
                    // The counted (lit) marks sweep: gold when the receipt is gold, white otherwise. Only a session
                    // that counted nothing sweeps every mark, in white (§4.6).
                    let finish = FinishTimeline.frame(
                        at: time, counted: frame.marks.map { $0 == .lit }, gold: model.isGold, leafOpened: fill.opened > 0,
                        reduceMotion: reduceMotion
                    )
                    screen(model, session: session, frame: frame, centre: centre, finish: finish, again: again)
                }
            }
            .task(id: plays) { await playFinish(plays, markCount: frame.marks.count, announcing: model.dialLabel) }
        }
    }

    private func screen(
        _ model: ReceiptModel, session: SessionRecord, frame: DialFrame, centre: ReceiptFlow.CentreLeaf?,
        finish: FinishFrame, again: AgainAction?
    ) -> some View {
        let title = FocusCopy.sessionTitle(presetName: session.plan.presetName, intention: notes.intention(for: session.id))
        return SessionScreen(title: title, subtitle: model.subtitle) { diameter in
            VStack(spacing: theme.spacing.xs) {
                if let note = model.note {
                    // "Ended at 18 of 50m", over the counted time.
                    Text(note)
                        .font(MapleFont.footnote)
                        .foregroundStyle(theme.colors.textSecondary)
                        .accessibilityLabel(Text(model.noteSpoken ?? note))
                }
                dial(model, frame: frame, centre: centre, finish: finish, diameter: diameter)
            }
        } lines: {
            if let parts = model.leafLineParts {
                // The running screen's line, so its look doesn't change at the handover: the name, then the rest in
                // the secondary colour; the amber bud before a line that says a leaf is yours (§4.3).
                LeafLineRow(words: LeafLineWords(line: parts, opened: model.leafLineOpened))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(model.leafSpoken ?? parts.text))
                    .opacity(finish.lineOpacity)
                    .offset(y: finish.lineRise)
            }
            if let breakdown = model.breakdown {
                Text(breakdown)
                    .font(MapleFont.footnote)
                    .foregroundStyle(theme.colors.textSecondary)
                    .accessibilityLabel(Text(model.breakdownSpoken ?? breakdown))
                    .opacity(finish.lineOpacity)
                    .offset(y: finish.lineRise)
            }
            if let prompt = model.reflectionPrompt {
                reflection(prompt, choices: model.choices)
                    .opacity(finish.actionsOpacity)
                    .offset(y: finish.actionsRise)
            }
        } controls: {
            Button(FocusCopy.done, action: done)
                .buttonStyle(.moonlight)
                .opacity(finish.actionsOpacity)
                .offset(y: finish.actionsRise)
            if let title = model.again, let again {
                againControl(title, spoken: model.againSpoken ?? title, again: again, session: session)
                    .opacity(finish.actionsOpacity)
                    .offset(y: finish.actionsRise)
            }
        }
    }

    /// The dial as the session counted it, with the finish over it. Tapping it (its numeral) opens Saved today.
    private func dial(
        _ model: ReceiptModel, frame: DialFrame, centre: ReceiptFlow.CentreLeaf?, finish: FinishFrame, diameter: CGFloat
    ) -> some View {
        let leaf = centre.flatMap { LeafCatalog.shared.species(id: $0.speciesID) }
        return MinuteDial(frame: frame, diameter: diameter, theme: theme) {
            DialCentre(
                leaf: leaf.map { DialLeaf(species: $0, fill: frame.fill) }, numeral: model.numeralParts,
                caption: model.caption, diameter: diameter
            )
            .finishing(finish)
        }
        .finishing(finish)
        .contentShape(Circle())
        .onTapGesture(perform: openSavedToday)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(model.dialLabel))
        .accessibilityHint(Text(FocusSheetCopy.savedTodayHint))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, openSavedToday)
    }

    /// "How did it go?" with one tap: All done · Partly · Not yet. "Partly" and "Not yet" put the intention first
    /// among the next start's chips; "All done" drops it (§5.8, through `FocusSessionStore.reflections`).
    private func reflection(_ prompt: String, choices: [ReceiptModel.Choice]) -> some View {
        VStack(spacing: theme.spacing.xs) {
            Text(prompt)
                .font(MapleFont.footnote)
                .foregroundStyle(theme.colors.textSecondary)
            ChipFlow(spacing: theme.spacing.xs, lineSpacing: theme.spacing.xs, alignment: .center) {
                ForEach(choices, id: \.reflection) { choice in
                    Chip(choice.title, isSelected: choice.isSelected) {
                        reflect(choice.reflection)
                    }
                }
            }
        }
        .padding(.top, theme.spacing.sm)
        .accessibilityElement(children: .contain)
    }

    /// "Again · 50m": one tap when the start screen has nothing to say, a 1.5-second hold in Locked (§5.2), and
    /// otherwise the start screen with the preset and length selected (F1-20). VoiceOver reads the link's length in
    /// words ("Again, 50 minutes"); Locked's hold is named "Hold to start, Locked 50 minutes".
    @ViewBuilder
    private func againControl(_ title: String, spoken: String, again: AgainAction, session: SessionRecord) -> some View {
        let preset = again.preset
        switch again.action {
        case .hold:
            HoldButton(
                title: title, duration: FocusCopy.holdToStartSeconds,
                accessibilityName: FocusCopy.holdToStartName(minutes: session.plan.plannedMinutes, locale: locale),
                progress: $againProgress, frozenProgress: frozenHold
            ) {
                startAgain(preset, session: session)
            }
        case .start:
            TextLink(title, chevron: false) { startAgain(preset, session: session) }
                .disabled(isStarting)
                .accessibilityLabel(Text(spoken))
        case .openStartScreen:
            TextLink(title, chevron: false) { openStartScreen(preset, session: session, lockFailed: false) }
                .accessibilityLabel(Text(spoken))
        }
    }

    // MARK: Inputs

    /// The centre leaf's fill: gold once this session opened it; otherwise the next leaf's rung, split into what
    /// was saved before and this session's counted share.
    private func centreFill(_ centre: ReceiptFlow.CentreLeaf?, next: LeafProgress?, countedSeconds: Int) -> DialFill {
        guard let centre else { return DialFill() }
        if centre.opened { return DialFill(before: 1, session: 0, opened: 1) }
        guard let next else { return DialFill() }
        return DialFill(rung: next, sessionHours: Double(countedSeconds) / 3600)
    }

    /// Again's preset and what it does now, from its start readiness; nil hides Again (the preset is gone, or there are
    /// no Focus stores, as in a bare preview).
    private func againAction(_ session: SessionRecord) -> AgainAction? {
        guard let preset = presets.preset(id: session.plan.presetID),
              let readiness = againReadiness(preset, session: session) else { return nil }
        return AgainAction(preset: preset, action: ReceiptFlow.again(readiness))
    }

    /// The start readiness of the session's preset at its planned length, now (F1-20): Task 9's start-screen model,
    /// the one the start screen and Home read.
    private func againReadiness(_ preset: FocusPreset, session: SessionRecord) -> StartReadiness? {
        focusStores?.startScreen(
            preset: preset, minutes: session.plan.plannedMinutes, at: sessions.now, collection: collection,
            settings: settings, locale: locale
        ).readiness
    }

    // MARK: Actions

    private func appeared() {
        guard shownAt == nil else { return }
        // A receipt the store no longer holds (an old notification): nothing to show, so the tab moves on.
        guard session != nil else {
            tab.shownReceipt = nil
            return
        }
        let now = sessions.now
        shownAt = now
        finishStart = .now
        // Shown once (P5): mark it seen only when it is the receipt the tab would pick, so opening an older one from
        // its notification doesn't hide a newer one.
        if ReceiptPicker.pending(sessions.sessions, seen: settings.lastReceiptSeen, now: now)?.id == sessionID {
            settings.lastReceiptSeen = sessionID
        }
    }

    /// The finish's haptic as the ring sets off, the session's end announced, and the timeline stopped once
    /// everything has come to rest. The task starts again each time the receipt reappears (another tab and back): the
    /// announcement and the haptic play only the first time, and a return mid-finish waits out only what is left.
    private func playFinish(_ plays: Bool, markCount: Int, announcing reading: String) async {
        guard plays, !isSettled else { return }
        if !finishPlayed {
            finishPlayed = true
            // The session ending is a milestone (§4.9).
            AccessibilityNotification.Announcement(reading).post()
            try? await Task.sleep(for: .seconds(FinishTimeline.hapticTime))
            guard !Task.isCancelled else { return }
            finishImpact += 1
        }
        let settled = FinishTimeline.settledTime(markCount: markCount, reduceMotion: reduceMotion)
        let rest = settled - Date.now.timeIntervalSince(finishStart)
        if rest > 0 { try? await Task.sleep(for: .seconds(rest)) }
        guard !Task.isCancelled else { return }
        isSettled = true
    }

    private func openSavedToday() {
        tab.sheet = .saved
    }

    private func reflect(_ reflection: Reflection) {
        Task { await sessions.reflect(reflection, on: sessionID) }
    }

    /// Done: the tab moves on to the start screen.
    private func done() {
        tab.shownReceipt = nil
    }

    /// Again, straight away: the same preset and length, with the intention unless the member said "All done". A
    /// start the store refuses opens the start screen with the preset selected, where Start says why.
    private func startAgain(_ preset: FocusPreset, session: SessionRecord) {
        guard !isStarting, let focusStores else { return }
        isStarting = true
        let intention = ReceiptFlow.againIntention(notes.intention(for: session.id), reflection: session.reflection)
        let appSet = preset.appSetID.flatMap { appSets.set(id: $0) }
        let request = FocusSessionStore.StartRequest(
            preset: preset, minutes: session.plan.plannedMinutes, appSet: appSet, from: .again
        )
        Task {
            let outcome = await focusStores.start(request, intention: intention, settings: settings)
            isStarting = false
            switch outcome {
            case .started(let id):
                // The new session's screen takes over (`FocusView` clears the receipt as it starts), with the soft
                // haptic as its block is confirmed, as from the start screen (§5.1).
                tab.lastStarted = id
            case .alreadyRunning:
                break
            case .blockingFailed:
                openStartScreen(preset, session: session, lockFailed: true)
            case .ledgerUnavailable, .notRecorded:
                openStartScreen(preset, session: session, lockFailed: false)
            }
        }
    }

    /// The start screen, with Again's preset, length and intention selected.
    private func openStartScreen(_ preset: FocusPreset, session: SessionRecord, lockFailed: Bool) {
        tab.selectedPresetID = preset.id
        tab.minutes = session.plan.plannedMinutes
        tab.intention = ReceiptFlow.againIntention(notes.intention(for: session.id), reflection: session.reflection)
        if lockFailed { tab.plainTimer = .lockFailed }
        againProgress = 0
        done()
    }

    // MARK: DEBUG still frames

    /// `-MapleDemoFinishAt <s>`: the finish (or an emergency release's breath) frozen that many seconds in.
    private var frozenFinish: Double? {
        #if DEBUG
        return DemoLaunchOptions.current.finishAt
        #else
        return nil
        #endif
    }

    /// `-MapleDemoHoldAt 0…1`: Locked's Again frozen at that fill.
    private var frozenHold: Double? {
        #if DEBUG
        return DemoLaunchOptions.current.holdAt
        #else
        return nil
        #endif
    }
}

/// Again's preset and what it does now (`ReceiptFlow.again`), read once a minute.
private struct AgainAction {
    let preset: FocusPreset
    let action: ReceiptFlow.Again
}
