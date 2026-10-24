import Foundation
import MapleCore
import MapleStorage
import Observation

/// Focus sessions (F1 design §7.4). Turns the member's commands into ledger events and verified shield operations,
/// replays the ledger, and hands each replay's credit to `CollectionStore.applyFocus`.
///
/// - Commands run one at a time, in order. Each reads the ledger once; what it writes is merged into the replay in
///   memory, and a later read that brings nothing new (only what the store wrote) keeps the replay as it is.
/// - The block is applied and read back before `sessionStarted` is written; a session that can't be written lifts its
///   block at once. Final clears (a session's end, "Release all apps") always run, written or not.
/// - While the ledger can't be read the store is in an unknown state: it neither writes nor clears.
/// - A running session whose shields go missing is marked `shieldLost` and carries on as a plain timer.
/// - Each command replays the open ledger. When the open read shows a sign of a missing start (an unended session's
///   events without its `sessionStarted`, or applied shields whose session it doesn't show running), it also reads the
///   whole ledger and adds the events of every session it holds unended, and nothing else of the history: a clock set
///   far forward can push a running session's start out of the open read's files.
@Observable
public final class FocusSessionStore {
    public struct StartRequest: Sendable {
        public var preset: FocusPreset
        /// This session's length (the dial can differ from the preset's); kept to 20 minutes–3 hours.
        public var minutes: Int
        /// The app set to block; nil starts a plain timer.
        public var appSet: AppSet?
        /// The member chose "Use a plain timer".
        public var plainTimer: Bool
        public var from: StartSource

        public init(preset: FocusPreset, minutes: Int, appSet: AppSet?, plainTimer: Bool = false, from: StartSource) {
            self.preset = preset
            self.minutes = minutes
            self.appSet = appSet
            self.plainTimer = plainTimer
            self.from = from
        }
    }

    public enum StartOutcome: Sendable, Equatable {
        case started(UUID)
        /// A session is starting or running: a second tap does nothing.
        case alreadyRunning
        case ledgerUnavailable
        /// "Couldn't lock your apps · Start as a plain timer?"
        case blockingFailed(ShieldFailure)
        /// The ledger couldn't be written; the block was lifted.
        case notRecorded
    }

    /// Seconds saved, counted plus the running session's provisional time: what the dial and Home show.
    public struct DisplayCredit: Sendable, Equatable {
        public var today: Int
        public var yesterday: Int
        public var total: Int
    }

    /// The shortest gap between two written checkpoints.
    public static let checkpointInterval: TimeInterval = 60

    public private(set) var isLedgerReadable = false
    public private(set) var isStarting = false
    public private(set) var sessions: [SessionRecord] = []
    public private(set) var running: SessionRecord?
    /// The session that ended last while this store watched: the receipt's.
    public private(set) var lastEnded: SessionRecord?
    public private(set) var probe: BlockingProbe = .notDetermined

    @ObservationIgnored public let blocking: any BlockingService
    @ObservationIgnored private let ledger: any FocusLedgerStore
    @ObservationIgnored private let writer: LedgerWriter
    @ObservationIgnored private let collection: CollectionStore
    @ObservationIgnored private let credited: Set<FocusSource>
    @ObservationIgnored private let liveActivity: any LiveActivityController
    @ObservationIgnored private let appBuild: String
    @ObservationIgnored private let plannedSecondsOverride: Int?
    @ObservationIgnored private var queue: Task<Void, Never>?
    /// This device's newest event in the boot that was current at the last replay: trusted time runs on from it.
    @ObservationIgnored private var anchor: PlacedEvent?
    /// The replay the commands read: the last read's events plus what the store has written since.
    @ObservationIgnored private var replayed = FocusLedger()
    /// The last open read, as the ledger handed it back (an unchanged read is the same array, quick to compare).
    @ObservationIgnored private var lastRead: [FocusEvent]?
    /// Every event id in `replayed`.
    @ObservationIgnored private var known: Set<String> = []
    /// Events the running command wrote that `replayed` doesn't hold yet.
    @ObservationIgnored private var written: [FocusEvent] = []
    /// Since `replayed` was last rebuilt, a full read added every session the ledger holds unended.
    @ObservationIgnored private var widened = false
    /// Sessions in `replayed` without their `sessionStarted` that may still be running: none of their events ends them
    /// or clears their shields as orphaned.
    @ObservationIgnored private var missingStarts: Set<UUID> = []
    /// Sessions a full read found with no `sessionStarted` anywhere (a damaged line): no sign of a missing start, so they
    /// don't widen later replays.
    @ObservationIgnored private var startless: Set<UUID> = []

    /// - Parameters:
    ///   - writer: The app's writer, whose time source is the store's clock (a shifted one in demos).
    ///   - credited: The sources whose events earn credit: `live`, plus `preview` in the sandbox (§7.6).
    ///   - plannedSecondsOverride: DEBUG sandbox only: every session lasts this long (`-MapleDemoSessionSeconds`).
    public init(
        ledger: any FocusLedgerStore, writer: LedgerWriter, blocking: any BlockingService, collection: CollectionStore,
        credited: Set<FocusSource>, liveActivity: any LiveActivityController, appBuild: String,
        plannedSecondsOverride: Int? = nil
    ) {
        self.ledger = ledger
        self.writer = writer
        self.blocking = blocking
        self.collection = collection
        self.credited = credited
        self.liveActivity = liveActivity
        self.appBuild = appBuild
        self.plannedSecondsOverride = plannedSecondsOverride
    }

    /// The store's "now", on trusted time (F1 design §3.2): the placed time of this device's newest event in the
    /// current boot plus the continuous time since it, so setting the clock never ends a session early. The wall
    /// clock only until this boot has an event.
    public var now: Date {
        let stamp = writer.time.stamp()
        guard let anchor, anchor.event.stamp.boot == stamp.boot else { return stamp.wall }
        return anchor.placed.addingTimeInterval(stamp.seconds(since: anchor.event.stamp))
    }

    /// Each session's reflection, for the intention chips.
    public var reflections: [UUID: Reflection] {
        Dictionary(sessions.compactMap { session in session.reflection.map { (session.id, $0) } }, uniquingKeysWith: { $1 })
    }

    /// The running session, for its end reminder.
    public var reminderSession: ReminderPlan.RunningSession? {
        running.map {
            ReminderPlan.RunningSession(id: $0.id, plannedEnd: $0.plannedEnd, presetName: $0.plan.presetName,
                                        plannedMinutes: $0.plan.plannedMinutes, isPlainTimer: $0.plan.kind == .plainTimer)
        }
    }

    /// When the latest session started, so the study reminder skips that day.
    public var lastSessionStart: Date? { sessions.last?.started.placed }

    // MARK: Commands

    /// Replays the ledger, ends a session whose planned end has passed, writes a checkpoint, matches the shields to the
    /// ledger, applies credit and updates the Live Activity. Call it on launch, on every return to the foreground and
    /// from a running session's timeline.
    public func refresh() async {
        await serially { [self] in
            guard await replay(shields: blocking.readStore()) else { return }
            let now = self.now
            probe = await blocking.probe()
            syncPermission()
            if let session = running {
                if now >= session.plannedEnd {
                    await finish(session, reason: .completed)
                } else if session.plan.kind == .blocking, session.lostAt == nil {
                    await checkpoint(session, now: now)
                }
            }
            await reconcileShields(now: now)
            await settle(now: now)
        }
    }

    public func start(_ request: StartRequest) async -> StartOutcome {
        // Checked before any await, so a second tap during the first start is refused.
        guard !isStarting, running == nil else { return .alreadyRunning }
        isStarting = true
        defer { isStarting = false }
        return await serially { [self] in await performStart(request) }
    }

    /// Ends the running session now: `.completed` at its end, `.endedEarly` or `.emergencyRelease` before it.
    public func end(_ reason: EndReason) async {
        await serially { [self] in
            guard await replay(shields: blocking.readStore()), let session = running else { return }
            await finish(session, reason: reason)
            await settle(now: now)
        }
    }

    /// Settings › Release all apps: clears every store, then ends a running session's credit (R4).
    public func releaseAll() async {
        await serially { [self] in
            let shields = await blocking.readStore()
            _ = await blocking.releaseAll()
            guard replay(shields: shields) else { return }
            if let session = running {
                _ = try? write(.sessionEnded(.releaseAll, verified: false), session: session.id)
                _ = try? write(.shieldCleared(.releaseAll), session: session.id)
                absorb()
                lastEnded = sessions.first { $0.id == session.id }
            }
            await settle(now: now)
        }
    }

    /// Starts the preset's one locked break, cut short at the planned end (F1-11). The block is read back first.
    /// - Returns: False when there is no break to take, or it couldn't be recorded.
    public func startBreak() async -> Bool {
        await serially { [self] in
            guard await replay(shields: blocking.readStore()), let session = running, session.plan.breakSeconds > 0,
                  !session.breakUsed
            else { return false }
            let seconds = min(session.plan.breakSeconds, Int(session.plannedEnd.timeIntervalSince(now)))
            guard seconds > 0, await readBackBeforeBreak(session) else { return false }
            let recorded = (try? write(.breakStarted(seconds: seconds), session: session.id)) != nil
            await settle(now: now)
            return recorded
        }
    }

    /// "Back to studying" before the break runs out. The block is read back first.
    public func endBreak() async {
        await serially { [self] in
            guard await replay(shields: blocking.readStore()), let session = running, session.breakEnd(at: now) != nil,
                  await readBackBeforeBreak(session)
            else { return }
            _ = try? write(.breakEnded, session: session.id)
            await settle(now: now)
        }
    }

    /// The receipt's "How did it go?".
    public func reflect(_ reflection: Reflection, on session: UUID) async {
        await serially { [self] in
            guard replay() else { return }
            _ = try? write(.reflected(reflection), session: session)
            absorb()
        }
    }

    /// Asks for Screen Time once (Needs Screen Time's "Turn on Screen Time").
    public func requestAuthorization() async -> BlockingProbe {
        await serially { [self] in
            probe = await blocking.requestAuthorization()
            syncPermission()
            return probe
        }
    }

    // MARK: Reading

    public func displayCredit(at date: Date) -> DisplayCredit {
        let today = collection.snapshot.focusWindow(at: date, context: collection.context).day
        let yesterday = today.adding(days: -1, calendar: collection.context.calendar)
        let book = collection.focus
        var provisional = 0
        if let running, running.plan.day == today {
            provisional = HoursCredit.provisionalSeconds(for: running, now: date, roomLeftToday: HoursCredit.dailyCap - book.seconds(on: today))
        }
        return DisplayCredit(today: book.seconds(on: today) + provisional, yesterday: book.seconds(on: yesterday),
                             total: book.totalSeconds + provisional)
    }

    // MARK: Private

    private func serially<Result: Sendable>(_ body: @escaping @MainActor @Sendable () async -> Result) async -> Result {
        let previous = queue
        let task = Task { @MainActor in
            await previous?.value
            return await body()
        }
        queue = Task { _ = await task.value }
        return await task.value
    }

    /// Reads the open ledger, the command's one read. A read that holds only what the replay already has (what this store
    /// wrote) keeps it; anything else rebuilds it from the read. The replay is widened (`widen()`) when it shows a sign
    /// of a missing start: an unended session's events without its `sessionStarted`, or `shields` (a read-back) applied
    /// for a session it doesn't show running. An ended session's missing start doesn't matter: it can't be running.
    /// False when what it must read can't be read: the command then does nothing (the unknown state).
    @discardableResult
    private func replay(shields: ShieldStoreState? = nil) -> Bool {
        guard let events = ledger.readOpen(now: now) else {
            isLedgerReadable = false
            return false
        }
        isLedgerReadable = true
        absorb()
        if events != lastRead {
            lastRead = events
            if !events.allSatisfy({ known.contains($0.id) }) {
                rebuild(events)
                widened = false
            }
        }
        guard !widened else { return true }
        var orphaned = false
        if case .applied(let id) = shields { orphaned = running?.id != id }
        guard orphaned || !missingStarts.isSubset(of: startless) else { return true }
        return widen()
    }

    /// Reads the whole ledger and adds to the replay the events of every session it holds unended (started, with no
    /// `sessionEnded`), so a running session's start is found wherever it is. Nothing else of the history is kept, so
    /// later commands cost what the open read costs. False when the ledger can't be read.
    private func widen() -> Bool {
        guard let all = ledger.readAll() else {
            isLedgerReadable = false
            return false
        }
        var started = Set<UUID>()
        var ended = Set<UUID>()
        for event in all {
            if case .sessionStarted = event.kind { started.insert(event.sessionID) }
            if Self.ends(event) { ended.insert(event.sessionID) }
        }
        let unended = started.subtracting(ended)
        let found = all.filter { unended.contains($0.sessionID) && !known.contains($0.id) }
        if !found.isEmpty {
            replayed.merge(found)
            for event in found { known.insert(event.id) }
            derive()
        }
        widened = true
        startless = missingStarts
        return true
    }

    /// Whether `event` ends its session, as `SessionRecord` reads a terminal event.
    private static func ends(_ event: FocusEvent) -> Bool {
        event.kind.isTerminal && event.affectsCredit
    }

    private func rebuild(_ events: [FocusEvent]) {
        replayed = FocusLedger(events)
        known = Set(replayed.events.map(\.id))
        derive()
    }

    /// Merges what the running command wrote into the replay, so nothing it wrote is read back from the files.
    private func absorb() {
        guard !written.isEmpty else { return }
        replayed.merge(written)
        for event in written { known.insert(event.id) }
        written.removeAll()
        derive()
    }

    /// The sessions, the running session, the anchor and the missing starts, from `replayed`.
    private func derive() {
        let placed = replayed.placed()
        // Within one boot of one device the ledger runs in continuous-time order, so the last is the newest.
        let boot = writer.time.stamp().boot
        let device = writer.deviceID
        anchor = placed.last { $0.event.deviceID == device && $0.event.stamp.boot == boot }
        sessions = FocusLedger.sessions(placed: placed)
        running = sessions.last { !$0.isEnded && !$0.isHidden }
        // A session ended, or whose shields were cleared as orphaned (only ever after a full read found nothing to run), is
        // no sign of a missing start.
        var ids = Set<UUID>()
        var closed = Set<UUID>()
        for event in replayed.events {
            ids.insert(event.sessionID)
            if Self.ends(event) || event.kind == .shieldCleared(.orphaned) { closed.insert(event.sessionID) }
        }
        missingStarts = ids.subtracting(sessions.map(\.id)).subtracting(closed)
    }

    /// Writes an event for `absorb()` to merge.
    @discardableResult
    private func write(_ kind: FocusEventKind, session: UUID) throws -> FocusEvent {
        let event = try writer.write(kind, session: session)
        written.append(event)
        return event
    }

    private func performStart(_ request: StartRequest) async -> StartOutcome {
        guard await replay(shields: blocking.readStore()) else { return .ledgerUnavailable }
        guard running == nil else { return .alreadyRunning }
        let now = self.now
        let context = collection.context
        let frozen = collection.snapshot.focusWindow(at: now, context: context)
        let blocks = !request.plainTimer && blocking.capability.canBlock && request.appSet != nil
        let minutes = DialLayout.stepped(request.minutes, by: 0)
        let plan = FocusPlan(
            presetID: request.preset.id, presetName: request.preset.name, verb: request.preset.verb, plannedSeconds: plannedSecondsOverride ?? minutes * 60,
            breakSeconds: request.preset.hasBreak ? FocusPreset.breakSeconds : 0, strictness: request.preset.strictness(on: frozen.day),
            kind: blocks ? .blocking : .plainTimer, appSetID: blocks ? request.appSet?.id : nil,
            selection: blocks ? request.appSet?.summary : nil, startedFrom: request.from, mapleDay: frozen.day.description,
            window: frozen.window, zone: context.calendar.timeZone.identifier, appBuild: appBuild, rulesVersion: FocusRules.version
        )
        let id = UUID()
        if blocks, let appSet = request.appSet {
            let result = await blocking.perform(.apply(session: id), selection: appSet.selection)
            guard result.isVerified else {
                if result.store == .applied(session: id) { _ = await blocking.perform(.clear(session: id), selection: nil) }
                return .blockingFailed(result.failure ?? .applyFailed)
            }
        }
        var startWritten = false
        do {
            try write(.sessionStarted(plan), session: id)
            startWritten = true
            if blocks { try write(.shieldApplied, session: id) }
        } catch {
            if blocks { _ = await blocking.perform(.clear(session: id), selection: nil) }
            // A start written only halfway is ended at once, so nothing runs from a start reported as not recorded.
            if startWritten { _ = try? write(.sessionEnded(.endedEarly, verified: false), session: id) }
            absorb()
            return .notRecorded
        }
        await settle(now: now)
        return .started(id)
    }

    /// Ends `session`: a last read-back, the end event, then the final clear, which always runs.
    private func finish(_ session: SessionRecord, reason: EndReason) async {
        let blocks = session.plan.kind == .blocking
        var verified = false
        if blocks, session.lostAt == nil {
            verified = await blocking.perform(.verify(session: session.id), selection: nil).isVerified
        }
        _ = try? write(.sessionEnded(reason, verified: verified), session: session.id)
        if blocks {
            _ = await blocking.perform(.clear(session: session.id), selection: nil)
            _ = try? write(.shieldCleared(.sessionEnded), session: session.id)
        }
        absorb()
        lastEnded = sessions.first { $0.id == session.id }
    }

    /// Proves the block is still there (at most once a minute, and at once in a boot with no event yet), or marks it
    /// lost.
    private func checkpoint(_ session: SessionRecord, now: Date) async {
        let result = await blocking.perform(.verify(session: session.id), selection: nil)
        if result.isVerified {
            let last = session.lastCheckpoint ?? session.countdownStart
            // After a restart proof starts again at the first read-back (§3.3 step 3), which also anchors trusted
            // time: `now` is still the wall clock, which a clock set back puts before `last`.
            let firstInBoot = anchor?.event.stamp.boot != writer.time.stamp().boot
            if firstInBoot || now.timeIntervalSince(last) >= Self.checkpointInterval {
                _ = try? write(.shieldVerified, session: session.id)
            }
        } else {
            _ = try? write(.shieldLost, session: session.id)
        }
        absorb()
    }

    /// A break event is a checkpoint, trusted only right after a read-back (§3.3 step 2): a blocking session's block
    /// is verified first, and a block found missing is marked lost before the break is written (breaks are still
    /// recorded after a loss; they never count).
    /// - Returns: False when the block was missing and the loss couldn't be recorded: the break event, which would
    ///   then read as proof, mustn't be written.
    private func readBackBeforeBreak(_ session: SessionRecord) async -> Bool {
        guard session.plan.kind == .blocking, session.lostAt == nil else { return true }
        if await blocking.perform(.verify(session: session.id), selection: nil).isVerified { return true }
        return (try? write(.shieldLost, session: session.id)) != nil
    }

    /// Clears shields the ledger doesn't explain (orphans) or that outlived their session's planned end; marks a
    /// running session's missing shields as lost. The running session goes to the reconciler as it is: a lost one
    /// keeps its shields until its planned end.
    private func reconcileShields(now: Date) async {
        let store = await blocking.readStore()
        var now = now
        if case .applied(let id) = store, id != running?.id, !widened {
            // Shields the replay doesn't explain: read the whole ledger before calling them orphaned.
            guard widen() else { return }
            now = self.now
        }
        for op in ShieldReconciler.ops(running: running, store: store, now: now) {
            switch op {
            case .clear(let session):
                let orphaned = session != running?.id
                // A session the whole ledger still holds unended keeps its shields, even when another is running.
                if orphaned, sessions.contains(where: { $0.id == session && !$0.isEnded }) { continue }
                _ = await blocking.perform(op, selection: nil)
                _ = try? write(.shieldCleared(orphaned ? .orphaned : .expired), session: session)
            case .apply(let session):
                // Never re-applied silently: proof stops at the last checkpoint (§3.3).
                _ = try? write(.shieldLost, session: session)
            case .verify, .clearAll:
                break
            }
        }
        absorb()
    }

    /// Credit to the collection, then the Live Activity.
    private func settle(now: Date) async {
        absorb()
        collection.applyFocus(HoursCredit.credit(sessions, crediting: credited, now: now), at: now)
        await liveActivity.reconcile(running: running.map { FocusActivityState(session: $0, now: now) })
    }

    /// Grants `.screenTime` in the collection while blocking is available and allowed, as `HealthPermission` does
    /// for Apple Health, and tells it what this build can do.
    private func syncPermission() {
        var context = collection.context
        context.blocking = blocking.capability
        if blocking.capability.canBlock, probe.isAllowed {
            context.permissions.insert(.screenTime)
        } else {
            context.permissions.remove(.screenTime)
        }
        if context != collection.context { collection.context = context }
    }
}
