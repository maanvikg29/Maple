import Foundation
import MapleFocusCore

/// The Focus start screen as values (F1 design §5.1, §5.2, §4.5): the capsule, the Blocking and counts lines, the dial's
/// caption and leaf dot, the forecast, and whether a start can go straight ahead. Home's Start is built from the same
/// model (`FocusStart(model:)`), so Home and the start screen always agree (F1-20).
///
/// When `blocking` isn't `.ready` the Focus tab shows Needs Screen Time instead (§5.3); the model still answers, for
/// Home's `FocusStart`. In `.running`, ignore `forecast` and `readiness`: the live dial reads the running session.
public struct StartScreenModel: Sendable, Equatable {
    /// Where the start screen is.
    public enum Stage: Sendable, Hashable {
        /// Choosing a preset and a length.
        case choosing
        /// After Start, until the read-back confirms the block.
        case locking
        /// A session runs, minimised: the dial is live and can't be turned, and the chips and lines are hidden.
        case running
    }

    /// What the primary capsule does.
    public enum Primary: Sendable, Hashable {
        /// One tap starts the session.
        case start
        /// Locked: a 1.5-second hold starts it, and a plain tap shows `plainTapHint` for 4 seconds (§5.2).
        case holdToStart
        /// No app set yet: the capsule opens the Blocking sheet.
        case chooseApps
        /// Waiting for the read-back: the capsule does nothing.
        case locking
        case returnToSession
    }

    public let preset: FocusPreset
    /// This session's length, kept to 20 minutes–3 hours.
    public let minutes: Int
    public let stage: Stage
    /// The level a session started now uses: a looser change waits for the next Maple day.
    public let strictness: Strictness
    public let forecast: SessionForecast
    public let readiness: StartReadiness
    public let primary: Primary
    /// "Start study · 50m", "Hold to start · 50m", "Choose apps", "Locking 6 apps…", "Return to session".
    public let capsuleTitle: String
    /// Wind-down and night dim the capsule; it still works (§5.1).
    public let capsuleIsDimmed: Bool
    public let blockingLine: SelectionText.BlockingLine
    /// "You'll reach Field maple at minute 35", the first session's definition, or a bedtime or cap line; nil when
    /// hidden.
    public let countsLine: String?
    /// "turn to set the length" until the dial has been turned once (§4.5).
    public let hint: String?
    /// Under the numeral: the hint, then the preset's name.
    public let caption: String
    /// The leaf dot's minute; nil hides it.
    public let leafMinute: Int?
    /// The next hours leaf, "Field maple"; nil when there is none.
    public let leafName: String?
    /// The dial's numeral: "50m", "1h 30m".
    public let lengthText: String
    /// "Session length, 50 minutes" (§4.9), with an adjustable action of ±5 minutes.
    public let dialLabel: String
    /// The hold button's VoiceOver name and named action: "Hold to start, Locked 50 minutes" (§4.9, F1-22).
    public let holdName: String?
    /// What a plain tap on the hold shows.
    public let plainTapHint: String?
    /// The chips, the intention, the Blocking line and the counts line show.
    public let showsDetails: Bool
    /// The dial can be turned to set the length.
    public let canTurn: Bool

    /// - Parameters:
    ///   - preset: The selected preset. `minutes` is the dial's length, which can differ from the preset's.
    ///   - selection: The preset's app set's summary; nil without one.
    ///   - expiredTokens: iOS no longer recognises some of the set's apps (`AppSet.tokensExpired`).
    ///   - blocking: Whether Maple can block now.
    ///   - isFirstSession: No session has ever started (`!AppSettings.hasStartedFocus`, P4).
    ///   - phase: The phase now (wind-down and night dim the capsule and send Home's Start to this screen).
    ///   - day: The Maple day a start now counts toward (`focusWindow(at: now, context:).day`).
    ///   - window: The frozen awake window for a start now (`focusWindow(at: now, context:).window`).
    ///   - now: Trusted time (`FocusSessionStore.now`).
    ///   - progress: The next hours leaf (counters only); anything that isn't a locked hours rung is ignored.
    ///   - displayToday: Seconds saved today, counted plus a running session's provisional time.
    ///   - stage: Choosing, locking, or a session running behind the minimised screen.
    ///   - hasTurned: The member has turned the dial once.
    public init(
        preset: FocusPreset, minutes: Int, selection: SelectionSummary?, expiredTokens: Bool, blocking: FocusStatus.Blocking,
        isFirstSession: Bool, phase: NowPhase, day: LocalDay, window: AwakeWindow, now: Date, progress: LeafProgress?,
        displayToday: Int, stage: Stage = .choosing, hasTurned: Bool = false, locale: Locale = .current,
        calendar: Calendar = .current
    ) {
        let minutes = DialLayout.stepped(minutes, by: 0)
        let strictness = preset.strictness(on: day)
        let canBlock = blocking == .ready
        let leaf = progress.flatMap { $0.category == .hoursSaved && $0.state == .locked && $0.remaining > 0 ? $0 : nil }
        let leafName = leaf.flatMap { LeafCatalog.shared.species(id: $0.speciesID)?.displayName }
        let forecast = SessionForecast(
            start: now, plannedSeconds: minutes * 60, window: window, now: now,
            canCount: canBlock && (selection?.qualifies ?? false),
            // Counters hold whole seconds, so the rounding is exact.
            secondsToLeaf: leaf.map { Int(($0.remaining * 3600).rounded()) }, leafName: leafName,
            roomLeftToday: max(0, HoursCredit.dailyCap - displayToday), firstEver: isFirstSession
        )

        let primary: Primary
        switch stage {
        case .running:
            primary = .returnToSession
        case .locking:
            primary = .locking
        case .choosing:
            if canBlock && (selection?.isEmpty ?? true) {
                primary = .chooseApps
            } else {
                primary = strictness == .locked ? .holdToStart : .start
            }
        }
        let length = FocusTimeText.length(minutes: minutes)
        let hint = stage == .choosing && !hasTurned ? FocusCopy.turnHint : nil

        self.preset = preset
        self.minutes = minutes
        self.stage = stage
        self.strictness = strictness
        self.forecast = forecast
        readiness = StartReadiness.check(
            strictness: strictness, blockingAllowed: canBlock, selection: selection, expiredTokens: expiredTokens,
            isFirstSession: isFirstSession, phase: phase, countsLine: forecast.countsLine
        )
        self.primary = primary
        switch primary {
        case .start: capsuleTitle = "\(preset.verb.startTitle) · \(length)"
        case .holdToStart: capsuleTitle = FocusCopy.holdToStart(minutes: minutes)
        case .chooseApps: capsuleTitle = FocusCopy.chooseApps
        case .locking: capsuleTitle = SelectionText.locking(selection)
        case .returnToSession: capsuleTitle = FocusCopy.returnToSession
        }
        capsuleIsDimmed = stage == .choosing && (phase == .windDown || phase == .night)
        blockingLine = SelectionText.blockingLine(selection, strictness: strictness, expired: expiredTokens)
        countsLine = stage == .running ? nil : forecast.countsLine.text(locale: locale, calendar: calendar)
        self.hint = hint
        caption = hint ?? preset.name
        leafMinute = stage == .running ? nil : forecast.leafMinute
        self.leafName = leafName
        lengthText = length
        dialLabel = FocusCopy.sessionLengthLabel(minutes: minutes, locale: locale)
        holdName = primary == .holdToStart ? FocusCopy.holdToStartName(minutes: minutes, locale: locale) : nil
        plainTapHint = primary == .holdToStart ? FocusCopy.holdHint : nil
        showsDetails = stage != .running
        canTurn = stage == .choosing
    }
}

extension FocusStart {
    /// Home's Start, from the start screen's own model, so both say the same thing (F1-20). Build the model for the
    /// last-used preset at its own length, at `stage: .choosing`.
    public init(model: StartScreenModel) {
        self.init(presetID: model.preset.id, verb: model.preset.verb, minutes: model.minutes, strictness: model.strictness,
                  readiness: model.readiness)
    }
}
