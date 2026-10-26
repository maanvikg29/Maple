import Foundation
import MapleStorage
import Synchronization
import Testing
@testable import MapleCore
@testable import MapleServices

/// A session store on a manual clock, an in-memory ledger and the preview blocker, over a planted collection.
@MainActor
private final class Harness {
    let time = ManualFocusTime(wall: at(2026, 10, 23, 14))
    let ledger = MemoryLedgerStore()
    let device = UUID()
    let blocking: PreviewBlockingService
    let collection: CollectionStore
    let activity = RecordingLiveActivityController()
    let store: FocusSessionStore
    /// What the store reads and writes through: the in-memory ledger, or a wrapper around it.
    let events: any FocusLedgerStore

    let six = AppSet(id: AppSet.distractionsID, name: "Distractions", selection: Data("six".utf8),
                     summary: SelectionSummary(mode: .blockThese, apps: 6, sites: 0, categories: 0))

    /// - Parameters:
    ///   - failingAppend: The one append (counting from 1) the ledger refuses, if any.
    ///   - wrap: Wraps the in-memory ledger (to count or hide reads).
    init(authorization: BlockingProbe = .allowed, failingAppend: Int? = nil, wrap: ((MemoryLedgerStore) -> any FocusLedgerStore)? = nil) {
        blocking = PreviewBlockingService(authorization: authorization)
        collection = CollectionStore(storage: JSONStorage(.memory), context: testContext, now: at(2026, 10, 1, 9))
        collection.raise(.firstLeaf, to: 1, at: at(2026, 10, 1, 9))
        collection.openReveals(at: at(2026, 10, 1, 9, 5))
        let memory = ledger
        let events: any FocusLedgerStore
        if let wrap {
            events = wrap(memory)
        } else if let failingAppend {
            events = RefusingOneAppend(memory, refusing: failingAppend)
        } else {
            events = memory
        }
        self.events = events
        let writer = LedgerWriter(store: events, time: time, deviceID: device, writer: .app, source: blocking.source)
        store = FocusSessionStore(ledger: events, writer: writer, blocking: blocking, collection: collection,
                                  credited: [.live, .preview], liveActivity: activity, appBuild: "test")
    }

    func preset(_ index: Int = 0) -> FocusPreset {
        FocusPreset.defaults(appSetID: AppSet.distractionsID)[index]
    }

    func request(minutes: Int = 50, preset index: Int = 0, plain: Bool = false) -> FocusSessionStore.StartRequest {
        FocusSessionStore.StartRequest(preset: preset(index), minutes: minutes, appSet: six, plainTimer: plain, from: .focusTab)
    }

    func advance(minutes: Double) {
        time.advance(minutes * 60)
    }

    var kinds: [String] { ledger.events.map(\.kind.type) }

    /// A new store over `ledger` (this harness's in-memory ledger, or a wrapper around it), with the same clock, device,
    /// collection and, unless given another, blocker: the next process's store.
    func relaunch(over ledger: any FocusLedgerStore, blocking: (any BlockingService)? = nil) -> FocusSessionStore {
        let blocker = blocking ?? self.blocking
        let writer = LedgerWriter(store: ledger, time: time, deviceID: device, writer: .app, source: blocker.source)
        return FocusSessionStore(ledger: ledger, writer: writer, blocking: blocker, collection: collection, credited: [.live, .preview],
                                 liveActivity: RecordingLiveActivityController(), appBuild: "test")
    }
}

/// An in-memory ledger that refuses exactly one append (counting from 1) and accepts every other: a start written
/// only halfway.
private final class RefusingOneAppend: FocusLedgerStore {
    struct Refused: Error {}

    private let base: MemoryLedgerStore
    private let refusing: Int
    private let appends = Mutex(0)

    init(_ base: MemoryLedgerStore, refusing: Int) {
        self.base = base
        self.refusing = refusing
    }

    func append(_ event: FocusEvent) throws {
        let count = appends.withLock { count in
            count += 1
            return count
        }
        if count == refusing { throw Refused() }
        try base.append(event)
    }

    func readOpen(now: Date) -> [FocusEvent]? { base.readOpen(now: now) }
    func readAll() -> [FocusEvent]? { base.readAll() }
    func lastSeq(of writer: FocusWriter) -> Int? { base.lastSeq(of: writer) }
}

/// A session store over real ledger files in a temporary folder, so the open read's file window is the real one.
/// `relaunch()` builds a new store over the same folder, clock, blocker and collection, as the next process would.
@MainActor
private final class FileHarness {
    let folder: URL
    let time = ManualFocusTime(wall: at(2026, 10, 24, 14))
    let device = UUID()
    let blocking = PreviewBlockingService()
    let collection: CollectionStore
    private(set) var store: FocusSessionStore

    let six = AppSet(id: AppSet.distractionsID, name: "Distractions", selection: Data("six".utf8),
                     summary: SelectionSummary(mode: .blockThese, apps: 6, sites: 0, categories: 0))

    init() throws {
        folder = try temporaryDirectory()
        collection = CollectionStore(storage: JSONStorage(.memory), context: testContext, now: at(2026, 10, 1, 9))
        collection.raise(.firstLeaf, to: 1, at: at(2026, 10, 1, 9))
        collection.openReveals(at: at(2026, 10, 1, 9, 5))
        store = Self.makeStore(folder: folder, time: time, device: device, blocking: blocking, collection: collection)
    }

    private static func makeStore(
        folder: URL, time: ManualFocusTime, device: UUID, blocking: PreviewBlockingService, collection: CollectionStore
    ) -> FocusSessionStore {
        let ledger = FileLedgerStore(directory: folder)
        let writer = LedgerWriter(store: ledger, time: time, deviceID: device, writer: .app, source: blocking.source)
        return FocusSessionStore(ledger: ledger, writer: writer, blocking: blocking, collection: collection,
                                 credited: [.live, .preview], liveActivity: RecordingLiveActivityController(), appBuild: "test")
    }

    func relaunch() {
        store = Self.makeStore(folder: folder, time: time, device: device, blocking: blocking, collection: collection)
    }

    func request(_ strictness: Strictness = .steady, minutes: Int = 50) -> FocusSessionStore.StartRequest {
        var preset = FocusPreset.defaults(appSetID: AppSet.distractionsID)[0]
        preset.strictness = strictness
        return FocusSessionStore.StartRequest(preset: preset, minutes: minutes, appSet: six, from: .focusTab)
    }

    var files: [String] { MapleServicesTests.files(in: folder).sorted() }
    var events: [FocusEvent] { FileLedgerStore(directory: folder).readAll() ?? [] }

    func setModified(_ name: String, to date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: folder.appending(path: name).path)
    }
}

/// An in-memory ledger that counts its reads.
private final class CountingReads: FocusLedgerStore {
    let base: MemoryLedgerStore
    private let count = Mutex(0)

    init(_ base: MemoryLedgerStore) {
        self.base = base
    }

    /// Reads (open or full) since the last `reset()`.
    var reads: Int { count.withLock { $0 } }
    func reset() { count.withLock { $0 = 0 } }

    func append(_ event: FocusEvent) throws { try base.append(event) }
    func readOpen(now: Date) -> [FocusEvent]? {
        count.withLock { $0 += 1 }
        return base.readOpen(now: now)
    }
    func readAll() -> [FocusEvent]? {
        count.withLock { $0 += 1 }
        return base.readAll()
    }
    func lastSeq(of writer: FocusWriter) -> Int? { base.lastSeq(of: writer) }
}

/// An in-memory ledger whose open read leaves out some events, as when a session's earlier events are in a month file that
/// has left the open read. It counts full reads.
private final class PartialOpenRead: FocusLedgerStore {
    let base: MemoryLedgerStore
    let hidden: @Sendable (FocusEvent) -> Bool
    private let count = Mutex(0)

    init(_ base: MemoryLedgerStore, hiding hidden: @escaping @Sendable (FocusEvent) -> Bool = { _ in false }) {
        self.base = base
        self.hidden = hidden
    }

    var fullReads: Int { count.withLock { $0 } }

    func append(_ event: FocusEvent) throws { try base.append(event) }
    func readOpen(now: Date) -> [FocusEvent]? {
        base.readOpen(now: now)?.filter { !hidden($0) }
    }
    func readAll() -> [FocusEvent]? {
        count.withLock { $0 += 1 }
        return base.readAll()
    }
    func lastSeq(of writer: FocusWriter) -> Int? { base.lastSeq(of: writer) }
}

/// The preview blocker, except that the first read-back of its store finds it empty: shields that appear between a
/// command's first read-back and its reconcile (another process applying them).
@MainActor
private final class LateShields: BlockingService {
    let base: PreviewBlockingService
    private var reads = 0

    init(_ base: PreviewBlockingService) {
        self.base = base
    }

    var capability: BlockingCapability { base.capability }
    var source: FocusSource { base.source }
    func probe() async -> BlockingProbe { await base.probe() }
    func requestAuthorization() async -> BlockingProbe { await base.requestAuthorization() }
    func readStore() async -> ShieldStoreState {
        reads += 1
        return reads == 1 ? .empty : await base.readStore()
    }
    func perform(_ op: ShieldOp, selection: Data?) async -> ShieldResult { await base.perform(op, selection: selection) }
    func releaseAll() async -> ShieldResult { await base.releaseAll() }
}

/// The preview blocker, noting `isLoaded` each time the store probes it or asks it for a shield operation.
@MainActor
private final class LoadedSpy: BlockingService {
    let base: PreviewBlockingService
    /// Reads the store's `isLoaded`; set once the store exists.
    var isLoaded: () -> Bool = { false }
    private(set) var seen: [Bool] = []

    init(_ base: PreviewBlockingService) {
        self.base = base
    }

    var capability: BlockingCapability { base.capability }
    var source: FocusSource { base.source }
    func probe() async -> BlockingProbe {
        seen.append(isLoaded())
        return await base.probe()
    }
    func requestAuthorization() async -> BlockingProbe { await base.requestAuthorization() }
    func readStore() async -> ShieldStoreState { await base.readStore() }
    func perform(_ op: ShieldOp, selection: Data?) async -> ShieldResult {
        seen.append(isLoaded())
        return await base.perform(op, selection: selection)
    }
    func releaseAll() async -> ShieldResult { await base.releaseAll() }
}

/// An in-memory ledger whose open read can be made to miss everything, as a clock set far forward can.
private final class BlindOpenRead: FocusLedgerStore {
    let base: MemoryLedgerStore
    private let blind = Mutex(false)

    init(_ base: MemoryLedgerStore) {
        self.base = base
    }

    var isBlind: Bool {
        get { blind.withLock { $0 } }
        set { blind.withLock { $0 = newValue } }
    }

    func append(_ event: FocusEvent) throws { try base.append(event) }
    func readOpen(now: Date) -> [FocusEvent]? { isBlind ? [] : base.readOpen(now: now) }
    func readAll() -> [FocusEvent]? { base.readAll() }
    func lastSeq(of writer: FocusWriter) -> Int? { base.lastSeq(of: writer) }
}

@Suite("Focus session store")
@MainActor
struct FocusSessionStoreTests {
    @Test("A Locked session survives a clock set 45 days forward and a relaunch")
    func lockedSurvivesClockForwardRelaunch() async throws {
        let h = try FileHarness()
        guard case .started(let id) = await h.store.start(h.request(.locked)) else { Issue.record("not started"); return }
        #expect(h.store.running?.plan.strictness == .locked)
        // Five minutes on, the member sets the date 45 days forward and opens Maple: a checkpoint goes to December's file,
        // now the writer's newest. October's file was last changed on the real October 24.
        h.time.advance(5 * 60)
        h.time.setWall(at(2026, 12, 8, 14, 5))
        await h.store.refresh()
        #expect(h.files == ["ledger-app-2026-10.jsonl", "ledger-app-2026-12.jsonl"])
        try h.setModified("ledger-app-2026-10.jsonl", to: at(2026, 10, 24, 14, 1))

        // Maple is killed and opened again: the first replay reads on the wall clock, December 8.
        h.relaunch()
        await h.store.refresh()
        #expect(h.blocking.store == .applied(session: id))
        #expect(h.store.running?.id == id)
        #expect(!h.events.contains { $0.kind == .shieldCleared(.orphaned) })

        // Continuous time runs past the planned end.
        h.time.advance(46 * 60)
        await h.store.refresh()
        #expect(h.store.running == nil)
        #expect(h.store.lastEnded?.id == id)
        #expect(h.store.lastEnded?.endReason == .completed)
        #expect(h.blocking.store == .empty)
        #expect(h.events.contains { $0.sessionID == id && $0.kind == .shieldCleared(.sessionEnded) })
        #expect(!h.events.contains { $0.kind == .shieldCleared(.orphaned) })
    }

    @Test("Applied shields the open read can't explain send a relaunched store to the full read: it finds the session running and keeps none of the ended history")
    func orphanNeedsFullRead() async throws {
        let h = Harness()
        // An earlier session that ended, then the running one.
        guard case .started(let ended) = await h.store.start(h.request()) else { Issue.record("not started"); return }
        h.advance(minutes: 50)
        await h.store.refresh()
        #expect(h.store.lastEnded?.id == ended)
        h.advance(minutes: 10)
        guard case .started(let id) = await h.store.start(h.request()) else { Issue.record("not started"); return }
        h.advance(minutes: 5)
        let blind = BlindOpenRead(h.ledger)
        blind.isBlind = true
        func verified() -> Int { h.ledger.events.filter { $0.sessionID == id && $0.kind == .shieldVerified }.count }

        // A relaunch whose open read misses everything; its first command is a Start.
        let first = h.relaunch(over: blind)
        #expect(await first.start(h.request()) == .alreadyRunning)
        #expect(first.running?.id == id)
        #expect(first.sessions.map(\.id) == [id], "the full read keeps only the unended session, not the history")
        #expect(h.blocking.store == .applied(session: id))

        // A relaunch whose first command is a refresh: the session is found before the checkpoint, which proves it.
        let second = h.relaunch(over: blind)
        await second.refresh()
        #expect(second.running?.id == id)
        #expect(verified() == 1)
        #expect(second.sessions.map(\.id) == [id])
        #expect(h.blocking.store == .applied(session: id))

        // Shields that read back only by the time the shields are matched: the reconcile reads the whole ledger itself.
        let third = h.relaunch(over: blind, blocking: LateShields(h.blocking))
        await third.refresh()
        #expect(third.running?.id == id)
        #expect(h.blocking.store == .applied(session: id))
        #expect(!h.ledger.events.contains { $0.kind == .shieldCleared(.orphaned) })

        // A real orphan (applied, nothing written) is still cleared once the full read confirms it.
        await second.end(.endedEarly)
        #expect(second.lastEnded?.id == id)
        let orphan = UUID()
        _ = await h.blocking.perform(.apply(session: orphan), selection: Data("six".utf8))
        await second.refresh()
        #expect(h.blocking.store == .empty)
        #expect(h.ledger.events.contains { $0.sessionID == orphan && $0.kind == .shieldCleared(.orphaned) })
    }

    @Test("A missing start widens the read only while its session may be running: an ended session, an orphan clear or a lone reflection never does")
    func endedAndOrphanDontWiden() async throws {
        // A session that ran across the 1st: the next launch's open read holds its end but not its start.
        let crossed = Harness()
        guard case .started(let ended) = await crossed.store.start(crossed.request()) else { Issue.record("not started"); return }
        crossed.advance(minutes: 50)
        await crossed.store.refresh()
        #expect(crossed.store.lastEnded?.id == ended)
        let withoutStart = PartialOpenRead(crossed.ledger, hiding: { $0.sessionID == ended && $0.kind.type == "sessionStarted" })
        let relaunched = crossed.relaunch(over: withoutStart)
        await relaunched.refresh()
        #expect(withoutStart.fullReads == 0)
        #expect(relaunched.running == nil)

        // Shields cleared as orphaned: their session never had a start.
        let orphaned = Harness()
        _ = await orphaned.blocking.perform(.apply(session: UUID()), selection: Data("six".utf8))
        await orphaned.store.refresh()
        #expect(orphaned.ledger.events.contains { $0.kind == .shieldCleared(.orphaned) })
        let counting = PartialOpenRead(orphaned.ledger)
        let next = orphaned.relaunch(over: counting)
        await next.refresh()
        #expect(counting.fullReads == 0)
        #expect(next.running == nil)

        // A session that ended before the 1st, reflected on after it: the open read holds only the reflection, which can't
        // change credit (a running session out of sight still shows itself through its checkpoints).
        let reflected = Harness()
        guard case .started(let done) = await reflected.store.start(reflected.request()) else { Issue.record("not started"); return }
        reflected.advance(minutes: 50)
        await reflected.store.refresh()
        #expect(reflected.store.lastEnded?.id == done)
        reflected.advance(minutes: 10)
        await reflected.store.reflect(.allDone, on: done)
        let onlyReflection = PartialOpenRead(reflected.ledger, hiding: { $0.sessionID == done && $0.kind.type != "reflected" })
        let afterReflection = reflected.relaunch(over: onlyReflection)
        await afterReflection.refresh()
        #expect(onlyReflection.fullReads == 0)
        #expect(afterReflection.running == nil)
    }

    @Test("Each command reads the ledger once: what it writes is merged in memory, not read back")
    func oneReadPerCommand() async throws {
        let h = Harness(wrap: { CountingReads($0) })
        let reads = try #require(h.events as? CountingReads)
        guard case .started(let id) = await h.store.start(h.request()) else { Issue.record("not started"); return }
        #expect(reads.reads == 1)

        reads.reset()
        h.advance(minutes: 5)
        await h.store.refresh()
        #expect(h.kinds.last == "shieldVerified")
        #expect(h.store.running?.lastCheckpoint == at(2026, 10, 23, 14, 5))
        #expect(reads.reads == 1)

        reads.reset()
        await h.store.refresh()
        #expect(reads.reads == 1)

        reads.reset()
        h.advance(minutes: 45)
        await h.store.refresh()
        #expect(h.store.lastEnded?.id == id)
        #expect(h.store.lastEnded?.endReason == .completed)
        #expect(h.collection.focus.totalSeconds == 3000)
        #expect(reads.reads == 1)
    }

    @Test("A session starts with the block confirmed, completes at its planned end, and its credit reaches the collection")
    func wholeSession() async throws {
        let h = Harness()
        await h.store.refresh()
        let outcome = await h.store.start(h.request())
        guard case .started(let id) = outcome else { Issue.record("\(outcome)"); return }
        #expect(h.kinds == ["sessionStarted", "shieldApplied"])
        #expect(h.blocking.store == .applied(session: id))
        #expect(h.store.running?.id == id)
        #expect(h.activity.current?.sessionID == id)
        #expect(h.store.reminderSession?.plannedEnd == at(2026, 10, 23, 14, 50))

        h.advance(minutes: 50)
        await h.store.refresh()
        #expect(h.store.running == nil)
        #expect(h.store.lastEnded?.id == id)
        #expect(h.store.lastEnded?.endReason == .completed)
        #expect(h.store.lastEnded?.endVerified == true)
        #expect(h.blocking.store == .empty)
        #expect(h.kinds.suffix(2) == ["sessionEnded", "shieldCleared"])
        #expect(h.collection.focus.totalSeconds == 3000)
        #expect(h.collection.snapshot.counters[.sessionsFinished] == 1)
        #expect(h.activity.current == nil)
    }

    @Test("Review Focus 5: a second Start while one is starting or running is refused")
    func doubleStart() async {
        let h = Harness()
        let request = h.request()
        async let first = h.store.start(request)
        async let second = h.store.start(request)
        let outcomes = await [first, second]
        #expect(outcomes.filter { if case .started = $0 { true } else { false } }.count == 1)
        #expect(outcomes.contains(.alreadyRunning))
        #expect(h.kinds.filter { $0 == "sessionStarted" }.count == 1)
        #expect(await h.store.start(h.request()) == .alreadyRunning)
    }

    @Test("Review Focus 3: shields applied before the app was killed, with no session written, are cleared")
    func orphanShields() async {
        let h = Harness()
        let orphan = UUID()
        _ = await h.blocking.perform(.apply(session: orphan), selection: Data("six".utf8))
        await h.store.refresh()
        #expect(h.blocking.store == .empty)
        #expect(h.ledger.events.contains { $0.sessionID == orphan && $0.kind == .shieldCleared(.orphaned) })
        #expect(h.store.running == nil)
    }

    @Test("Review Focus 4: editing the schedule mid-session keeps the session's frozen window")
    func scheduleEdit() async {
        let h = Harness()
        _ = await h.store.start(h.request())
        h.collection.schedule = .everyNight(SleepSchedule(bedtime: ClockTime(hour: 14, minute: 30), wake: ClockTime(hour: 6), windDownMinutes: 30))
        h.advance(minutes: 50)
        await h.store.refresh()
        #expect(h.collection.focus.totalSeconds == 3000)
    }

    @Test("A ledger that can't be read leaves everything alone: no writes, no clears, no start")
    func unreadable() async {
        let h = Harness()
        let orphan = UUID()
        _ = await h.blocking.perform(.apply(session: orphan), selection: Data())
        h.ledger.unreadable = true
        await h.store.refresh()
        #expect(!h.store.isLedgerReadable)
        #expect(h.blocking.store == .applied(session: orphan))
        #expect(await h.store.start(h.request()) == .ledgerUnavailable)
        #expect(h.ledger.events.isEmpty)
    }

    @Test("Loaded only once the first refresh has replayed the ledger, probed blocking and ended a session that ended while away")
    func loaded() async throws {
        let h = Harness()
        await h.store.refresh()
        guard case .started(let id) = await h.store.start(h.request()) else { Issue.record("not started"); return }
        // Maple is killed mid-session and opened again after the planned end.
        h.advance(minutes: 60)
        let spy = LoadedSpy(h.blocking)
        let store = h.relaunch(over: h.ledger, blocking: spy)
        spy.isLoaded = { [unowned store] in store.isLoaded }
        #expect(!store.isLoaded)
        // A ledger that can't be read loads nothing.
        h.ledger.unreadable = true
        await store.refresh()
        #expect(!store.isLoaded)
        h.ledger.unreadable = false
        await store.refresh()
        // Not while it probed, read the block back or cleared it: only once the session it found had ended.
        #expect(!spy.seen.isEmpty)
        #expect(spy.seen.allSatisfy { !$0 })
        #expect(store.isLoaded)
        #expect(store.running == nil)
        #expect(store.lastEnded?.id == id)
        // It stays loaded.
        await store.refresh()
        #expect(store.isLoaded)
    }

    @Test("A block that doesn't verify starts nothing; a session that can't be written lifts its block at once")
    func startFailures() async {
        let failing = Harness()
        failing.blocking.failures = [.applyFails]
        #expect(await failing.store.start(failing.request()) == .blockingFailed(.applyFailed))
        #expect(failing.ledger.events.isEmpty)

        let overflow = Harness()
        overflow.blocking.failures = [.tokenOverflow]
        #expect(await overflow.store.start(overflow.request()) == .blockingFailed(.readBack))

        let unwritable = Harness()
        unwritable.ledger.failsWrites = true
        #expect(await unwritable.store.start(unwritable.request()) == .notRecorded)
        #expect(unwritable.blocking.store == .empty)
        #expect(unwritable.store.running == nil)
    }

    @Test("A plain timer touches no shields and counts nothing")
    func plainTimer() async throws {
        let h = Harness()
        _ = await h.store.start(h.request(plain: true))
        #expect(h.kinds == ["sessionStarted"])
        #expect(h.store.running?.plan.kind == .plainTimer)
        h.advance(minutes: 50)
        await h.store.refresh()
        #expect(h.blocking.operations.isEmpty)
        #expect(h.store.lastEnded?.endReason == .completed)
        #expect(h.collection.focus.totalSeconds == 0)
    }

    @Test("Checkpoints prove time once a minute; revoked access stops credit at the last one")
    func revoked() async {
        let h = Harness()
        _ = await h.store.start(h.request())
        h.advance(minutes: 5)
        await h.store.refresh()
        #expect(h.kinds.last == "shieldVerified")
        await h.store.refresh()
        #expect(h.kinds.filter { $0 == "shieldVerified" }.count == 1)
        h.advance(minutes: 5)
        h.blocking.revoke()
        await h.store.refresh()
        #expect(h.kinds.last == "shieldLost")
        #expect(h.store.running?.lostAt != nil)
        h.advance(minutes: 40)
        await h.store.refresh()
        #expect(h.store.lastEnded?.endVerified == false)
        #expect(h.collection.focus.totalSeconds == 300)
    }

    @Test("Ending early keeps the counted minutes but never finishes")
    func endEarly() async {
        let h = Harness()
        _ = await h.store.start(h.request())
        h.advance(minutes: 20)
        await h.store.end(.endedEarly)
        #expect(h.store.lastEnded?.endReason == .endedEarly)
        #expect(h.blocking.store == .empty)
        #expect(h.collection.focus.totalSeconds == 1200)
        #expect((h.collection.snapshot.counters[.sessionsFinished] ?? 0) == 0)
        #expect(h.activity.current == nil)
    }

    @Test("Release all apps clears every store and ends the session's credit")
    func releaseAll() async {
        let h = Harness()
        _ = await h.store.start(h.request())
        h.advance(minutes: 10)
        await h.store.releaseAll()
        #expect(h.blocking.store == .empty)
        #expect(h.store.lastEnded?.endReason == .releaseAll)
        #expect(h.store.lastEnded?.endVerified == false)
        #expect(h.ledger.events.contains { $0.kind == .shieldCleared(.releaseAll) })
    }

    @Test("One locked break, inside the planned length")
    func breaks() async {
        let h = Harness()
        _ = await h.store.start(h.request())
        h.advance(minutes: 10)
        #expect(await h.store.startBreak())
        #expect(h.ledger.events.last?.kind == .breakStarted(seconds: 300))
        #expect(!(await h.store.startBreak()))
        h.advance(minutes: 2)
        await h.store.endBreak()
        #expect(h.ledger.events.last?.kind == .breakEnded)

        let quick = Harness()
        _ = await quick.store.start(quick.request(minutes: 25, preset: 1))
        #expect(!(await quick.store.startBreak()))
    }

    @Test("Display credit adds the running session's provisional time to what the book has counted")
    func displayCredit() async {
        let h = Harness()
        _ = await h.store.start(h.request())
        h.advance(minutes: 20)
        await h.store.refresh()
        h.advance(minutes: 5)
        let display = h.store.displayCredit(at: h.store.now)
        #expect(display.today == 1500)
        #expect(display.total == 1500)
        #expect(display.yesterday == 0)
        #expect(h.collection.focus.totalSeconds == 1200)
    }

    @Test("Screen Time shows as granted in the collection only while blocking is available and allowed")
    func permissionBridge() async {
        let allowed = Harness()
        await allowed.store.refresh()
        #expect(allowed.collection.context.permissions.contains(.screenTime))
        #expect(allowed.collection.context.blocking == .preview)

        let asking = Harness(authorization: .notDetermined)
        await asking.store.refresh()
        #expect(!asking.collection.context.permissions.contains(.screenTime))
        #expect(await asking.store.requestAuthorization() == .allowed)
        #expect(asking.collection.context.permissions.contains(.screenTime))
    }

    @Test("Reflections are written to the ledger and read back by session")
    func reflections() async throws {
        let h = Harness()
        guard case .started(let id) = await h.store.start(h.request()) else { Issue.record("not started"); return }
        h.advance(minutes: 50)
        await h.store.refresh()
        await h.store.reflect(.partly, on: id)
        #expect(h.store.reflections[id] == .partly)
        #expect(h.store.lastSessionStart == at(2026, 10, 23, 14))
    }

    @Test("Setting the clock forward ends nothing early: the store's time is the ledger's plus the continuous clock")
    func clockSetForward() async {
        let h = Harness()
        guard case .started(let id) = await h.store.start(h.request()) else { Issue.record("not started"); return }
        #expect(h.store.running?.plan.strictness == .steady)
        h.advance(minutes: 10)
        h.time.setWall(at(2026, 10, 23, 14, 50))
        await h.store.refresh()
        #expect(h.store.now == at(2026, 10, 23, 14, 10))
        #expect(h.store.running?.id == id)
        #expect(h.store.lastEnded == nil)
        #expect(h.blocking.store == .applied(session: id))
    }

    @Test("A break reads the block back first: a block found missing is marked lost before the break is written")
    func breakReadsBack() async {
        let h = Harness()
        _ = await h.store.start(h.request())
        h.advance(minutes: 10)
        h.blocking.revoke()
        #expect(await h.store.startBreak())
        #expect(Array(h.kinds.suffix(2)) == ["shieldLost", "breakStarted"])
        #expect(h.store.running?.lostAt != nil)

        let ending = Harness()
        _ = await ending.store.start(ending.request())
        ending.advance(minutes: 10)
        #expect(await ending.store.startBreak())
        ending.advance(minutes: 2)
        ending.blocking.revoke()
        await ending.store.endBreak()
        #expect(Array(ending.kinds.suffix(2)) == ["shieldLost", "breakEnded"])
        #expect(ending.store.running?.lostAt != nil)
    }

    @Test("A lost session keeps its shields until its planned end: a refresh neither clears nor logs them")
    func lostKeepsShields() async throws {
        let h = Harness()
        guard case .started(let id) = await h.store.start(h.request()) else { Issue.record("not started"); return }
        h.advance(minutes: 5)
        // An event this build doesn't know, from another of the device's processes: proof stops there (§3.3).
        let monitor = LedgerWriter(store: h.ledger, time: h.time, deviceID: h.device, writer: .monitor, source: .preview)
        try monitor.write(.unknown("laterKind"), session: id)
        await h.store.refresh()
        #expect(h.store.running?.id == id)
        #expect(h.store.running?.lostAt != nil)
        #expect(h.blocking.store == .applied(session: id))
        #expect(!h.blocking.operations.contains(.clear(session: id)))
        #expect(!h.kinds.contains("shieldCleared"))
    }

    @Test("After a restart with the clock set back, the first read-back is a checkpoint and the session ends on time")
    func restartWithClockSetBack() async {
        let h = Harness()
        guard case .started(let id) = await h.store.start(h.request()) else { Issue.record("not started"); return }
        h.advance(minutes: 20)
        await h.store.refresh()
        h.time.reboot("b2", wall: at(2026, 10, 23, 13))
        await h.store.refresh()
        let restarted = h.ledger.events.last { $0.stamp.boot == "b2" }
        #expect(restarted?.kind == .shieldVerified)
        #expect(h.store.now == at(2026, 10, 23, 14, 20))

        h.advance(minutes: 30)
        await h.store.refresh()
        #expect(h.store.running == nil)
        #expect(h.store.lastEnded?.id == id)
        #expect(h.store.lastEnded?.endReason == .completed)
        #expect(h.store.lastEnded?.end?.placed == at(2026, 10, 23, 14, 50))
        #expect(h.blocking.store == .empty)
    }

    @Test("A start written only halfway is ended at once: nothing runs from a start reported as not recorded")
    func halfWrittenStart() async {
        let h = Harness(failingAppend: 2)
        #expect(await h.store.start(h.request()) == .notRecorded)
        #expect(h.blocking.store == .empty)
        #expect(h.store.running == nil)
        #expect(h.kinds == ["sessionStarted", "sessionEnded"])
        guard case .started = await h.store.start(h.request()) else { Issue.record("the next start was refused"); return }
    }
}
