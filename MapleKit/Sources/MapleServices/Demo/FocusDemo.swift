#if DEBUG
import Foundation
import MapleCore

/// DEBUG only: the values of the Focus launch arguments (F1 design §8.2, docs/debug-launch-arguments.md). Each is read
/// by `DemoLaunchOptions`, in any letter case; Task 2's scenarios turn them into seeded stores.
///
/// The enums are `nonisolated` one by one: MapleServices is main-actor by default, and `DemoLaunchOptions` is read off
/// the main actor.
nonisolated public enum FocusDemo {
    /// `-MapleDemoFocus`: where the Focus tab is.
    nonisolated public enum State: String, Sendable, CaseIterable {
        /// The start screen, ready: Study on six apps.
        case idle
        /// No app set chosen: "Choose apps to block ›".
        case noSet
        /// A selection that doesn't qualify (R3): "Allowing 24 apps · 20 or fewer count ›".
        case smallSet
        /// "Some apps need choosing again ›".
        case expired
        case running
        /// Running, with the screen dimmed after 30 seconds.
        case dimmed
        case breakTime = "break"
        /// Running, with the start screen showing "Return to session".
        case minimised
        /// A session that ended on time just now: the receipt, with its finish.
        case ended
        /// A session that ended 2 hours before launch: the receipt, shown still.
        case endedAway
        /// Running, with the End early sheet over it.
        case endEarly
        /// Running Locked, with the emergency release.
        case emergency
        /// Nothing ever focused: Quick preselected, the definition, the first-session line.
        case first
    }

    /// `-MapleDemoScreenTime`: what blocking can do.
    nonisolated public enum ScreenTime: String, Sendable, CaseIterable {
        case approved, notDetermined, declined, restricted, noPasscode
        /// A free build: this version of Maple can't lock apps.
        case unavailable
        /// Screen Time turned off for Maple mid-session.
        case revoked
        /// A plain timer running.
        case plain
        /// Every apply fails: "Couldn't lock your apps · Start as a plain timer?".
        case failStart
    }

    /// `-MapleDemoReceipt`: how the session that just ended went (§5.8's endings and variants).
    nonisolated public enum Receipt: String, Sendable, CaseIterable {
        case clean, unlocked, early, plain, revoked, bedtime, capped, leaf, leafNight, notQualifying
        /// Locked, released by the emergency hold 18 minutes in: §5.7's breath (`-MapleDemoFinishAt` freezes it), then
        /// its ended state.
        case emergency
    }

    /// `-MapleDemoSaved`: today's earlier sessions.
    nonisolated public enum Saved: String, Sendable, CaseIterable {
        case typical, capped, empty
    }

    /// `-MapleDemoLiveActivity`.
    nonisolated public enum LiveActivity: String, Sendable, CaseIterable {
        case running
        case breakTime = "break"
        case plain, ended
    }

    /// `-MapleDemoPresent`, when it names a Focus sheet.
    nonisolated public enum Sheet: String, Sendable, CaseIterable {
        case blocking, preset, saved, streak, intention
    }
}

// MARK: - Scenarios

extension FocusDemo {
    /// The device every demo event carries.
    nonisolated public static let deviceID = UUID(uuidString: "6D61706C-6500-4445-5649-000000000001")!
    /// The session a scenario is about: running, just ended, or ended while away.
    nonisolated public static let subjectID = UUID(uuidString: "6D61706C-6500-5345-5353-000000000001")!

    /// Today's earlier sessions, numbered from the earliest: 1, 2, ….
    nonisolated public static func historyID(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "6D61706C-6500-5345-5353-1000000000%02d", index))!
    }
}

/// The demo's clocks: the shifted wall clock (the demo clock's offset), and the real continuous clock started a week
/// early, so a scenario can stamp events up to a week back inside this boot however recently the device started.
/// `nonisolated`: `LedgerWriter` holds it as a `Sendable` time source.
nonisolated struct FocusDemoTime: FocusTimeSource {
    static let headroom: UInt64 = 7 * 86_400 * 1_000_000_000

    let shifted: ShiftedFocusTime

    func stamp() -> EventStamp {
        var stamp = shifted.stamp()
        stamp.continuous += Self.headroom
        return stamp
    }
}

/// DEBUG only: what a launch's Focus arguments ask for, reached with no tap (F1 design §7.4, §8.2).
///
/// - **One device, this boot.** The ledger is stamped back from the demo time source's now, so trusted time, the dial
///   and every checkpoint run on from it, and credit never crosses a boot.
/// - **The subject** is the session the scenario is about: running; past its planned end with no end written, so the
///   launch's `refresh()` ends it as after a kill; or ended early. The preview blocker holds its block while the
///   refresh will still see it.
/// - **Today's earlier sessions** follow `-MapleDemoSaved`, laid back from the subject's start.
/// - **The collection's Focus history** (`DemoData.FocusHistory`) holds the streak and puts the next hours leaf, at 20
///   hours, where the scenario needs it.
struct FocusDemoScenario {
    /// One seeded session, counted back from now.
    struct Script {
        enum End {
            case running
            /// Past its planned end with no end written: the launch's refresh ends it as `.completed`.
            case atRefresh
            /// Ended this many seconds into the countdown, verified unless its block was lost.
            case ended(EndReason, at: TimeInterval)
        }

        var id: UUID
        var preset: FocusPreset
        var minutes: Int
        var kind: SessionKind = .blocking
        var selection: SelectionSummary? = FocusDemoScenario.six
        var strictness: Strictness = .steady
        var breakSeconds: Int
        /// Seconds before now the countdown started: the block's read-back, or a plain timer's tap.
        var startedAgo: TimeInterval
        /// Seconds into the countdown the break began; `breakRunning` while it hasn't ended.
        var breakAt: TimeInterval?
        var breakRunning = false
        /// Seconds into the countdown a 5-minute unlock began.
        var unlockAt: TimeInterval?
        /// Seconds into the countdown of the last read-back, after which the block went missing a second later.
        var lostAt: TimeInterval?
        /// A running session's last read-back, this many seconds before now.
        var checkpointAgo: TimeInterval?
        var end: End
        var reflection: Reflection?
        var intention: String?

        /// Seconds before now the session was started: `sessionStarted`, 2 seconds before a block's read-back.
        var startAgo: TimeInterval { startedAgo + (kind == .blocking ? 2 : 0) }

        /// The session's events, each with how many seconds before now it was written.
        func timeline(_ plan: FocusPlan) -> [(ago: TimeInterval, kind: FocusEventKind)] {
            let blocks = kind == .blocking
            func ago(_ elapsed: TimeInterval) -> TimeInterval { startedAgo - elapsed }
            var events: [(ago: TimeInterval, kind: FocusEventKind)] = [(startAgo, .sessionStarted(plan))]
            if blocks { events.append((startedAgo, .shieldApplied)) }
            if let breakAt {
                events.append((ago(breakAt), .breakStarted(seconds: FocusPreset.breakSeconds)))
                if !breakRunning { events.append((ago(breakAt + TimeInterval(FocusPreset.breakSeconds)), .breakEnded)) }
            }
            if let unlockAt {
                events.append((ago(unlockAt), .overrideStarted(seconds: FocusDemoScenario.unlockSeconds)))
                events.append((ago(unlockAt + TimeInterval(FocusDemoScenario.unlockSeconds)), .overrideEnded))
            }
            if blocks, let lostAt {
                events.append((ago(lostAt), .shieldVerified))
                events.append((ago(lostAt + 1), .shieldLost))
            }
            if blocks, lostAt == nil, let checkpointAgo { events.append((checkpointAgo, .shieldVerified)) }
            if case .ended(let reason, let elapsed) = end {
                events.append((ago(elapsed), .sessionEnded(reason, verified: blocks && lostAt == nil)))
                if blocks { events.append((ago(elapsed + 1), .shieldCleared(.sessionEnded))) }
                if let reflection { events.append((ago(elapsed + 60), .reflected(reflection))) }
            }
            return events
        }
    }

    /// What the stores start from.
    struct Seed {
        var presets: PresetsFile
        var appSets: AppSetsFile
        var notes: SessionNotesFile
        var events: [FocusEvent]
        var blocking: any BlockingService
    }

    /// Distractions: "Blocking 6 apps", "6 apps resting".
    static let six = SelectionSummary(mode: .blockThese, apps: 6, sites: 0, categories: 0)
    /// "Allowing 24 apps": an allow list over 20, which doesn't qualify (R3).
    static let notQualifying = SelectionSummary(mode: .onlyThese, apps: 24, sites: 0, categories: 0)
    /// The header's "Study · Chemistry ch. 4" (§5.4).
    static let intention = "Chemistry ch. 4"
    static let unlockSeconds = 5 * 60
    /// Today's typical sessions count 50 and 30 minutes.
    static let typicalSeconds = 80 * 60
    /// The hours leaf the scenarios place: the 20-hour rung.
    static let nextLeafSeconds = 20 * 3600
    /// The bedtime receipt's session starts this long after tonight's bedtime.
    static let afterBedtime: TimeInterval = 5 * 60

    let state: FocusDemo.State
    /// The ending, when `state` is `ended` or `endedAway`.
    let receipt: FocusDemo.Receipt
    let saved: FocusDemo.Saved
    let screenTime: FocusDemo.ScreenTime
    let verb: FocusVerb
    let strictness: Strictness
    let focusAt: Int?
    let intention: String?

    init(_ options: DemoLaunchOptions) {
        var asked = options.focus
        if asked == nil, let live = options.liveActivity {
            asked = switch live {
            case .running, .plain: .running
            case .breakTime: .breakTime
            case .ended: .ended
            }
        }
        if asked == nil, options.receipt != nil || options.finishAt != nil { asked = .ended }
        if asked == nil, options.endCountdown != nil { asked = .endEarly }
        if asked == nil, options.screenTime == .revoked || options.screenTime == .plain { asked = .running }
        let state = asked ?? .idle
        let screenTime = options.screenTime ?? (options.liveActivity == .plain ? .plain : .approved)
        let ends = state == .ended || state == .endedAway
        self.state = state
        self.screenTime = screenTime
        receipt = options.receipt ?? .clean
        saved = if state == .first || screenTime == .unavailable {
            .empty
        } else if ends, options.receipt == .capped {
            .capped
        } else {
            options.saved ?? .typical
        }
        verb = options.preset ?? .study
        strictness = switch state {
        case .emergency: .locked
        case .endEarly: options.strictness == .gentle ? .gentle : .steady
        // Only Locked has the emergency release.
        case .ended, .endedAway: options.receipt == .emergency ? .locked : options.strictness ?? .steady
        default: options.strictness ?? .steady
        }
        focusAt = options.focusAt
        intention = options.intention ?? Self.intention
    }

    var isRunning: Bool { [.running, .dimmed, .breakTime, .minimised, .endEarly, .emergency].contains(state) }
    var isEnded: Bool { state == .ended || state == .endedAway }
    /// The receipt the launch opens on; nil while nothing has just ended.
    var endedOn: FocusDemo.Receipt? { isEnded ? receipt : nil }
    /// Without blocking allowed, a session can only be a plain timer.
    var subjectIsPlain: Bool {
        endedOn == .plain || [.plain, .unavailable, .notDetermined, .declined, .restricted, .noPasscode].contains(screenTime)
    }
    var subjectLosesBlock: Bool { !subjectIsPlain && (screenTime == .revoked || endedOn == .revoked) }
    /// How long before now the subject ended.
    var endedFor: TimeInterval { state == .endedAway ? 2 * 3600 : 5 }
    var subjectMinutes: Int { FocusPreset.defaults(appSetID: nil).first { $0.verb == verb }?.minutes ?? 50 }

    // MARK: The collection and the clock

    /// Where the demo clock starts: the asked-for phase, or the moment the scenario needs: the Day, where a session
    /// counts; after tonight's bedtime for the bedtime receipt; wind-down for a leaf held until morning.
    func start(phase: NowPhase?, day: Date, windows: PhaseWindows, calendar: Calendar) -> Date {
        if let phase { return windows.sampleDate(in: phase, onDayOf: day, calendar: calendar) }
        switch endedOn {
        case .bedtime?:
            let bedtime = windows.day(LocalDay(day, calendar: calendar), calendar: calendar).night
            return bedtime.addingTimeInterval(Self.afterBedtime + TimeInterval(subjectMinutes * 60) + endedFor)
        case .leafNight?:
            return windows.sampleDate(in: .windDown, onDayOf: day, calendar: calendar)
        default:
            return windows.sampleDate(in: .day, onDayOf: day, calendar: calendar)
        }
    }

    /// The collection's Focus history: the streak unless `-MapleDemoSaved empty`, and the hours before today that put
    /// the next leaf where the scenario needs it. A first session and a free build have none.
    func history(today: LocalDay) -> DemoData.FocusHistory {
        guard state != .first, screenTime != .unavailable else {
            return DemoData.FocusHistory(today: today, secondsBeforeToday: 0, runThroughYesterday: 0, bestRun: 0)
        }
        let streak = saved != .empty
        return DemoData.FocusHistory(today: today, secondsBeforeToday: secondsBeforeToday,
                                     runThroughYesterday: streak ? 11 : 0, bestRun: streak ? 21 : 0)
    }

    /// The next hours leaf (20h, Korean maple) sits 35 minutes into a session started now ("You'll reach Korean maple at
    /// minute 35", the running "17m to go", the leaf receipts); for an ending that opens none, 1h 10m off once it ends.
    var secondsBeforeToday: Int {
        let today = switch saved {
        case .empty: 0
        case .typical: Self.typicalSeconds
        case .capped: HoursCredit.dailyCap
        }
        let opensNone = endedOn.map { ![.leaf, .leafNight, .capped].contains($0) } ?? false
        let ahead = opensNone ? 70 * 60 + subjectMinutes * 60 : 35 * 60
        return Self.nextLeafSeconds - ahead - today
    }

    // MARK: The stores

    /// The four starters on Distractions, with `-MapleDemoStrictness` on the selected one, which is the last used
    /// (none yet for a first session).
    func presetsFile() -> PresetsFile {
        var presets = FocusPreset.defaults(appSetID: AppSet.distractionsID)
        let index = presets.firstIndex { $0.verb == verb } ?? 0
        presets[index].strictness = strictness
        return PresetsFile(presets: presets, lastUsedID: state == .first ? nil : presets[index].id)
    }

    /// Distractions holds six apps unless the state says otherwise; Study apps allows four apps and a site.
    func appSetsFile() -> AppSetsFile {
        var sets = AppSet.starters()
        var distractions = AppSet(id: AppSet.distractionsID, name: "Distractions", selection: Data("distractions".utf8),
                                  summary: Self.six)
        switch state {
        case .noSet:
            distractions = sets[0]
        case .smallSet:
            distractions.summary = Self.notQualifying
        case .expired:
            distractions.tokensExpired = true
        default:
            if endedOn == .notQualifying { distractions.summary = Self.notQualifying }
        }
        sets[0] = distractions
        sets[1] = AppSet(id: AppSet.studyAppsID, name: "Study apps", selection: Data("study-apps".utf8),
                         summary: SelectionSummary(mode: .onlyThese, apps: 4, sites: 1, categories: 0))
        return AppSetsFile(sets: sets)
    }

    /// The session the scenario is about, or nil when nothing runs or has just ended.
    func subjectScript(presets: [FocusPreset]) -> Script? {
        guard isRunning || isEnded else { return nil }
        let preset = presets.first { $0.verb == verb } ?? presets[0]
        let minutes = preset.minutes
        var script = Script(id: FocusDemo.subjectID, preset: preset, minutes: minutes, kind: subjectIsPlain ? .plainTimer : .blocking,
                            strictness: strictness, breakSeconds: preset.hasBreak ? FocusPreset.breakSeconds : 0,
                            startedAgo: 0, end: .running, intention: intention)
        if isRunning {
            let inBreak = state == .breakTime
            let at = min(max(focusAt ?? (inBreak ? 31 : 18), inBreak ? 2 : 1), minutes - 1)
            script.startedAgo = TimeInterval(at * 60)
            if inBreak {
                script.breakSeconds = FocusPreset.breakSeconds
                script.breakAt = TimeInterval((at - 1) * 60)
                script.breakRunning = true
            }
            if subjectLosesBlock {
                script.lostAt = min(600, TimeInterval((at - 1) * 60))
            } else {
                script.checkpointAgo = min(20, TimeInterval(at * 60) / 2)
            }
            return script
        }
        if receipt == .early || receipt == .emergency {
            let at = TimeInterval(min(max(focusAt ?? 18, 1), minutes - 1) * 60)
            script.startedAgo = at + endedFor
            script.end = .ended(receipt == .early ? .endedEarly : .emergencyRelease, at: at)
        } else {
            script.startedAgo = TimeInterval(minutes * 60) + endedFor
            script.end = .atRefresh
        }
        switch receipt {
        case .clean where preset.hasBreak && minutes >= 40: script.breakAt = 30 * 60
        case .unlocked: script.unlockAt = 20 * 60
        case .revoked: script.lostAt = 10 * 60
        case .notQualifying: script.selection = Self.notQualifying
        default: break
        }
        return script
    }

    /// Today's earlier sessions (`-MapleDemoSaved`), earliest first, each ending a little before the next began; the
    /// last ends before `reference` (seconds before now the subject started, or now).
    func earlierScripts(presets: [FocusPreset], before reference: TimeInterval) -> [Script] {
        func preset(_ verb: FocusVerb) -> FocusPreset { presets.first { $0.verb == verb } ?? presets[0] }
        var next = reference
        func lay(_ preset: FocusPreset, minutes: Int, gap: TimeInterval) -> Script {
            let script = Script(id: UUID(), preset: preset, minutes: minutes,
                                breakSeconds: preset.hasBreak ? FocusPreset.breakSeconds : 0,
                                startedAgo: next + gap + TimeInterval(minutes * 60),
                                end: .ended(.completed, at: TimeInterval(minutes * 60)))
            next = script.startAgo
            return script
        }
        var latestFirst: [Script] = []
        switch saved {
        case .empty:
            break
        case .typical:
            var read = lay(preset(.reading), minutes: 35, gap: 30 * 60)
            read.unlockAt = 15 * 60
            read.reflection = .partly
            read.intention = "Essay"
            var study = lay(preset(.study), minutes: 50, gap: 60 * 60)
            study.breakAt = 25 * 60
            study.reflection = .allDone
            study.intention = "Maths sheet"
            latestFirst = [read, study]
        case .capped:
            // The capped receipt is the session over the cap; otherwise a Study 50m plays it.
            if endedOn != .capped { latestFirst.append(lay(preset(.study), minutes: 50, gap: 10 * 60)) }
            for _ in 0..<3 { latestFirst.append(lay(preset(.deep), minutes: 120, gap: 10 * 60)) }
        }
        return latestFirst.reversed().enumerated().map { index, script in
            var script = script
            script.id = FocusDemo.historyID(index + 1)
            return script
        }
    }

    /// The blocker: the free build's, or the preview one with the scenario's authorization and failures, holding the
    /// block of a subject the launch's refresh will still see running or end.
    func blocker(for subject: Script?) -> any BlockingService {
        if screenTime == .unavailable { return UnavailableBlockingService() }
        let authorization: BlockingProbe = switch screenTime {
        case .notDetermined: .notDetermined
        case .declined, .plain: .declined
        case .restricted: .restricted
        case .noPasscode: .noPasscode
        case .approved, .unavailable, .revoked, .failStart: .allowed
        }
        var failures: Set<PreviewBlockingService.Failure> = []
        if subjectLosesBlock { failures.insert(.revoked) }
        if screenTime == .failStart { failures.insert(.applyFails) }
        var store = ShieldStoreState.empty
        if let subject, subject.kind == .blocking, subject.lostAt == nil {
            switch subject.end {
            case .running, .atRefresh: store = .applied(session: subject.id)
            case .ended: break
            }
        }
        return PreviewBlockingService(authorization: authorization, failures: failures, store: store)
    }

    /// A session's plan, frozen at its start as `FocusSessionStore.start` freezes it.
    func frozenPlan(for script: Script, startedAt date: Date, snapshot: CollectionSnapshot, context: CollectionContext,
                    appBuild: String) -> FocusPlan {
        let frozen = snapshot.focusWindow(at: date, context: context)
        let blocks = script.kind == .blocking
        return FocusPlan(
            presetID: script.preset.id, presetName: script.preset.name, verb: script.preset.verb,
            plannedSeconds: script.minutes * 60, breakSeconds: script.breakSeconds, strictness: script.strictness,
            kind: script.kind, appSetID: blocks ? AppSet.distractionsID : nil, selection: blocks ? script.selection : nil,
            startedFrom: .focusTab, mapleDay: frozen.day.description, window: frozen.window,
            zone: context.calendar.timeZone.identifier, appBuild: appBuild, rulesVersion: FocusRules.version
        )
    }

    /// Everything the stores start from, stamped back from `now`: the demo time source's stamp (this boot, the shifted
    /// wall clock).
    func seed(now: EventStamp, snapshot: CollectionSnapshot, context: CollectionContext, appBuild: String) -> Seed {
        let presets = presetsFile()
        let subject = subjectScript(presets: presets.presets)
        let scripts = earlierScripts(presets: presets.presets, before: subject?.startAgo ?? 0) + [subject].compactMap { $0 }
        let blocking = blocker(for: subject)
        var timed: [(ago: TimeInterval, session: UUID, kind: FocusEventKind)] = []
        var notes: [String: SessionNote] = [:]
        for script in scripts {
            let started = now.wall.addingTimeInterval(-script.startAgo)
            let plan = frozenPlan(for: script, startedAt: started, snapshot: snapshot, context: context, appBuild: appBuild)
            timed += script.timeline(plan).map { (ago: $0.ago, session: script.id, kind: $0.kind) }
            if let text = script.intention.flatMap(RecentIntentions.normalized) {
                notes[script.id.uuidString.lowercased()] = SessionNote(text: text, at: started)
            }
        }
        // Oldest first; events written at the same moment keep the order they were listed in.
        let ordered = timed.enumerated().sorted { a, b in
            a.element.ago != b.element.ago ? a.element.ago > b.element.ago : a.offset < b.offset
        }
        let events = ordered.enumerated().map { index, item in
            let ago = item.element.ago
            return FocusEvent(
                id: "\(item.element.session.uuidString.lowercased()).\(index + 1)", kind: item.element.kind,
                sessionID: item.element.session, deviceID: FocusDemo.deviceID, writer: .app, seq: index + 1,
                source: blocking.source,
                stamp: EventStamp(wall: now.wall.addingTimeInterval(-ago), continuous: now.continuous - UInt64((ago * 1e9).rounded()),
                                  boot: now.boot, zone: now.zone)
            )
        }
        return Seed(presets: presets, appSets: appSetsFile(), notes: SessionNotesFile(notes: notes), events: events,
                    blocking: blocking)
    }
}

extension FocusDemoScenario {
    /// Whether this scenario's member has started a session before (P4, `AppSettings.hasStartedFocus`): everyone
    /// but a first session.
    var hasStartedFocus: Bool { state != .first }

    /// The last receipt this scenario's member has seen (P5, `AppSettings.lastReceiptSeen`): the newest of today's
    /// earlier sessions, whose receipt showed as it ended. So only the scenario's own session opens on a receipt; nil
    /// without earlier sessions.
    var seenReceipt: UUID? {
        earlierScripts(presets: presetsFile().presets, before: 0).last?.id
    }
}
#endif
