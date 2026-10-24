import Foundation
import MapleCore
import MapleStorage
import Observation

/// Focus sessions (F1 design §7.4). Turns the member's commands into ledger events and verified shield operations,
/// replays the ledger after every change, and hands each replay's credit to `CollectionStore.applyFocus`.
///
/// - Commands run one at a time, in order.
/// - The block is applied and read back before `sessionStarted` is written; a session that can't be written lifts its
///   block at once. Final clears (a session's end, "Release all apps") always run, written or not.
/// - While the ledger can't be read the store is in an unknown state: it neither writes nor clears.
/// - A running session whose shields go missing is marked `shieldLost` and carries on as a plain timer.
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
    @ObservationIgnored private var queue: Task<Void, Never>?
    /// This device's newest event in the boot that was current at the last replay: trusted time runs on from it.
    @ObservationIgnored private var anchor: PlacedEvent?

    /// - Parameters:
    ///   - writer: The app's writer, whose time source is the store's clock (a shifted one in demos).
    ///   - credited: The sources whose events earn credit: `live`, plus `preview` in the sandbox (§7.6).
    public init(
        ledger: any FocusLedgerStore, writer: LedgerWriter, blocking: any BlockingService, collection: CollectionStore,
        credited: Set<FocusSource>, liveActivity: any LiveActivityController, appBuild: String
    ) {
        self.ledger = ledger
        self.writer = writer
        self.blocking = blocking
        self.collection = collection
        self.credited = credited
        self.liveActivity = liveActivity
        self.appBuild = appBuild
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
            guard replay() else { return }
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
            guard replay(), let session = running else { return }
            await finish(session, reason: reason)
            await settle(now: now)
        }
    }

    /// Settings › Release all apps: clears every store, then ends a running session's credit (R4).
    public func releaseAll() async {
        await serially { [self] in
            _ = await blocking.releaseAll()
            guard replay() else { return }
            if let session = running {
                _ = try? writer.write(.sessionEnded(.releaseAll, verified: false), session: session.id)
                _ = try? writer.write(.shieldCleared(.releaseAll), session: session.id)
                replay()
                lastEnded = sessions.first { $0.id == session.id }
            }
            await settle(now: now)
        }
    }

    /// Starts the preset's one locked break, cut short at the planned end (F1-11). The block is read back first.
    /// - Returns: False when there is no break to take, or it couldn't be recorded.
    public func startBreak() async -> Bool {
        await serially { [self] in
            guard replay(), let session = running, session.plan.breakSeconds > 0, !session.breakUsed else { return false }
            let seconds = min(session.plan.breakSeconds, Int(session.plannedEnd.timeIntervalSince(now)))
            guard seconds > 0, await readBackBeforeBreak(session) else { return false }
            let written = (try? writer.write(.breakStarted(seconds: seconds), session: session.id)) != nil
            await settle(now: now)
            return written
        }
    }

    /// "Back to studying" before the break runs out. The block is read back first.
    public func endBreak() async {
        await serially { [self] in
            guard replay(), let session = running, session.breakEnd(at: now) != nil, await readBackBeforeBreak(session) else { return }
            _ = try? writer.write(.breakEnded, session: session.id)
            await settle(now: now)
        }
    }

    /// The receipt's "How did it go?".
    public func reflect(_ reflection: Reflection, on session: UUID) async {
        await serially { [self] in
            guard replay() else { return }
            _ = try? writer.write(.reflected(reflection), session: session)
            replay()
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

    /// Reads the open ledger and rebuilds the sessions. False, with nothing changed, when it can't be read.
    @discardableResult
    private func replay() -> Bool {
        guard let events = ledger.readOpen(now: now) else {
            isLedgerReadable = false
            return false
        }
        isLedgerReadable = true
        let replayed = FocusLedger(events)
        // Within one boot of one device the ledger runs in continuous-time order, so the last is the newest.
        let boot = writer.time.stamp().boot
        anchor = replayed.placed().last { $0.event.deviceID == writer.deviceID && $0.event.stamp.boot == boot }
        sessions = replayed.sessions()
        running = sessions.last { !$0.isEnded && !$0.isHidden }
        return true
    }

    private func performStart(_ request: StartRequest) async -> StartOutcome {
        guard replay() else { return .ledgerUnavailable }
        guard running == nil else { return .alreadyRunning }
        let now = self.now
        let context = collection.context
        let frozen = collection.snapshot.focusWindow(at: now, context: context)
        let blocks = !request.plainTimer && blocking.capability.canBlock && request.appSet != nil
        let minutes = DialLayout.stepped(request.minutes, by: 0)
        let plan = FocusPlan(
            presetID: request.preset.id, presetName: request.preset.name, verb: request.preset.verb, plannedSeconds: minutes * 60,
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
        do {
            try writer.write(.sessionStarted(plan), session: id)
            if blocks { try writer.write(.shieldApplied, session: id) }
        } catch {
            if blocks { _ = await blocking.perform(.clear(session: id), selection: nil) }
            replay()
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
        _ = try? writer.write(.sessionEnded(reason, verified: verified), session: session.id)
        if blocks {
            _ = await blocking.perform(.clear(session: session.id), selection: nil)
            _ = try? writer.write(.shieldCleared(.sessionEnded), session: session.id)
        }
        replay()
        lastEnded = sessions.first { $0.id == session.id }
    }

    /// Proves the block is still there (at most once a minute), or marks it lost.
    private func checkpoint(_ session: SessionRecord, now: Date) async {
        let result = await blocking.perform(.verify(session: session.id), selection: nil)
        if result.isVerified {
            let last = session.lastCheckpoint ?? session.countdownStart
            if now.timeIntervalSince(last) >= Self.checkpointInterval {
                _ = try? writer.write(.shieldVerified, session: session.id)
            }
        } else {
            _ = try? writer.write(.shieldLost, session: session.id)
        }
        replay()
    }

    /// A break event is a checkpoint, trusted only right after a read-back (§3.3 step 2): a blocking session's block
    /// is verified first, and a block found missing is marked lost before the break is written (breaks are still
    /// recorded after a loss; they never count).
    /// - Returns: False when the block was missing and the loss couldn't be recorded: the break event, which would
    ///   then read as proof, mustn't be written.
    private func readBackBeforeBreak(_ session: SessionRecord) async -> Bool {
        guard session.plan.kind == .blocking, session.lostAt == nil else { return true }
        if await blocking.perform(.verify(session: session.id), selection: nil).isVerified { return true }
        return (try? writer.write(.shieldLost, session: session.id)) != nil
    }

    /// Clears shields the ledger doesn't explain (orphans) or that outlived their session's planned end; marks a
    /// running session's missing shields as lost. The running session goes to the reconciler as it is: a lost one
    /// keeps its shields until its planned end.
    private func reconcileShields(now: Date) async {
        let store = await blocking.readStore()
        for op in ShieldReconciler.ops(running: running, store: store, now: now) {
            switch op {
            case .clear(let session):
                _ = await blocking.perform(op, selection: nil)
                _ = try? writer.write(.shieldCleared(session == running?.id ? .expired : .orphaned), session: session)
            case .apply(let session):
                // Never re-applied silently: proof stops at the last checkpoint (§3.3).
                _ = try? writer.write(.shieldLost, session: session)
            case .verify, .clearAll:
                break
            }
        }
        replay()
    }

    /// Credit to the collection, then the Live Activity.
    private func settle(now: Date) async {
        replay()
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
