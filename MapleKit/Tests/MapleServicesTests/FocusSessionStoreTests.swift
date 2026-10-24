import Foundation
import MapleStorage
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

    let six = AppSet(id: AppSet.distractionsID, name: "Distractions", selection: Data("six".utf8),
                     summary: SelectionSummary(mode: .blockThese, apps: 6, sites: 0, categories: 0))

    init(authorization: BlockingProbe = .allowed) {
        blocking = PreviewBlockingService(authorization: authorization)
        collection = CollectionStore(storage: JSONStorage(.memory), context: testContext, now: at(2026, 10, 1, 9))
        collection.raise(.firstLeaf, to: 1, at: at(2026, 10, 1, 9))
        collection.openReveals(at: at(2026, 10, 1, 9, 5))
        let writer = LedgerWriter(store: ledger, time: time, deviceID: device, writer: .app, source: blocking.source)
        store = FocusSessionStore(ledger: ledger, writer: writer, blocking: blocking, collection: collection,
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
}

@Suite("Focus session store")
@MainActor
struct FocusSessionStoreTests {
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
}
