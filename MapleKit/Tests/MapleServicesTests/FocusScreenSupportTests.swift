#if DEBUG
import Foundation
import MapleStorage
import Testing
@testable import MapleCore
@testable import MapleServices

/// F1 shipped, Apple Health on: Focus leaves can open, and the hours leaves need Screen Time.
private let f1Context = CollectionContext(
    schedule: .standard, permissions: [.appleHealth], features: ShippedFeatures(releases: [.m1, .f1]), calendar: utc,
    hemisphere: .northern
)

private struct NotStarted: Error {}

/// A session store on a manual clock, over an in-memory ledger, the preview blocker and a planted collection with F1
/// shipped. `relaunch()` builds the next process's store over the same ledger, clock, blocker and collection.
@MainActor
private final class ScreenRig {
    let time: ManualFocusTime
    let ledger = MemoryLedgerStore()
    let device = UUID()
    let blocking = PreviewBlockingService()
    let collection: CollectionStore
    private(set) var store: FocusSessionStore
    let six = AppSet(id: AppSet.distractionsID, name: "Distractions", selection: Data("six".utf8),
                     summary: SelectionSummary(mode: .blockThese, apps: 6, sites: 0, categories: 0))

    init(at start: Date) {
        time = ManualFocusTime(wall: start)
        collection = CollectionStore(storage: JSONStorage(.memory), context: f1Context, now: at(2026, 10, 1, 9))
        collection.raise(.firstLeaf, to: 1, at: at(2026, 10, 1, 9))
        collection.openReveals(at: at(2026, 10, 1, 9, 5))
        store = Self.makeStore(ledger: ledger, time: time, device: device, blocking: blocking, collection: collection)
    }

    private static func makeStore(
        ledger: MemoryLedgerStore, time: ManualFocusTime, device: UUID, blocking: PreviewBlockingService,
        collection: CollectionStore
    ) -> FocusSessionStore {
        let writer = LedgerWriter(store: ledger, time: time, deviceID: device, writer: .app, source: blocking.source)
        return FocusSessionStore(ledger: ledger, writer: writer, blocking: blocking, collection: collection,
                                 credited: [.live, .preview], liveActivity: NoLiveActivityController(), appBuild: "test")
    }

    func relaunch() {
        store = Self.makeStore(ledger: ledger, time: time, device: device, blocking: blocking, collection: collection)
    }

    func advance(minutes: Double) {
        time.advance(minutes * 60)
    }

    /// Starts `minutes` of the starter preset at `index` (Study, Quick, Deep, Read), blocking Distractions.
    @discardableResult
    func start(minutes: Int = 50, preset index: Int = 0) async throws -> UUID {
        let preset = FocusPreset.defaults(appSetID: AppSet.distractionsID)[index]
        let request = FocusSessionStore.StartRequest(preset: preset, minutes: minutes, appSet: six, from: .focusTab)
        guard case .started(let id) = await store.start(request) else { throw NotStarted() }
        return id
    }
}

private func firstLeaf(of category: RewardCategoryID) throws -> String {
    try #require(RewardCatalog.shared.rungs(in: category).first).speciesID
}

@Suite("Session unlocks")
@MainActor
struct SessionUnlocksTests {
    /// 30 minutes saved before today, so the 1-hour leaf opens 30 minutes into today's first session.
    private func rig() -> ScreenRig {
        let rig = ScreenRig(at: at(2026, 10, 23, 14))
        rig.collection.raise(.hoursSaved, to: 0.5, at: at(2026, 10, 22, 12))
        return rig
    }

    @Test("A leaf that opens mid-session is the session's, through its end, until the next start")
    func midSession() async throws {
        let rig = rig()
        let hoursLeaf = try firstLeaf(of: .hoursSaved)
        let finishedLeaf = try firstLeaf(of: .sessionsFinished)
        await rig.store.refresh()
        let first = try await rig.start()
        #expect(rig.store.sessionUnlocks.isEmpty)
        rig.advance(minutes: 35)
        await rig.store.refresh()                                           // 14:35: proven past minute 30
        #expect(rig.store.sessionUnlocks.map(\.speciesID) == [hoursLeaf])
        #expect(rig.store.sessionUnlocks.first?.date == at(2026, 10, 23, 14, 35))

        rig.advance(minutes: 15)
        await rig.store.refresh()                                           // 14:50: ends on time, the first finished
        #expect(rig.store.lastEnded?.id == first)
        #expect(rig.store.sessionUnlocks.map(\.speciesID) == [hoursLeaf, finishedLeaf])
        await rig.store.refresh()
        #expect(rig.store.sessionUnlocks.map(\.speciesID) == [hoursLeaf, finishedLeaf], "a later refresh keeps them")

        try await rig.start(minutes: 20, preset: 1)
        #expect(rig.store.sessionUnlocks.isEmpty)
        rig.advance(minutes: 20)
        await rig.store.refresh()                                           // 1h 40m saved: no new leaf
        #expect(rig.store.sessionUnlocks.isEmpty, "the earlier session's leaves are not this one's")
    }

    @Test("Killed and reopened: the next process finds the session's leaves, still running or ended while away")
    func relaunched() async throws {
        let rig = rig()
        let hoursLeaf = try firstLeaf(of: .hoursSaved)
        let finishedLeaf = try firstLeaf(of: .sessionsFinished)
        await rig.store.refresh()
        try await rig.start()
        rig.advance(minutes: 35)
        await rig.store.refresh()

        rig.relaunch()
        rig.advance(minutes: 1)
        await rig.store.refresh()
        #expect(rig.store.running != nil)
        #expect(rig.store.sessionUnlocks.map(\.speciesID) == [hoursLeaf])

        rig.relaunch()
        rig.advance(minutes: 30)                                            // past its planned end while closed
        await rig.store.refresh()
        #expect(rig.store.lastEnded != nil)
        #expect(rig.store.sessionUnlocks.map(\.speciesID) == [hoursLeaf, finishedLeaf])
    }

    @Test("A store that didn't see the session run or end credits it nothing")
    func unattributed() async throws {
        let rig = rig()
        await rig.store.refresh()
        try await rig.start()
        rig.advance(minutes: 50)
        await rig.store.refresh()                                           // ended in the old process
        #expect(!rig.store.sessionUnlocks.isEmpty)
        rig.relaunch()
        await rig.store.refresh()
        #expect(rig.store.lastEnded == nil)
        #expect(rig.store.sessionUnlocks.isEmpty)
    }

    @Test("The leaf demos credit their leaf to the session: ended by the launch's refresh, or running past minute 35")
    func demos() async throws {
        let leaf = try #require(RewardCatalog.shared.rungs(in: .hoursSaved).first { $0.threshold == 20 }).speciesID
        func launch(_ arguments: String...) async throws -> FocusSessionStore {
            let stores = MapleStores.make(DemoLaunchOptions(arguments: ["-MapleDemoShip", "f1"] + arguments),
                                          directory: try temporaryDirectory(), calendar: utc, now: at(2026, 10, 23, 9))
            await stores.focus.sessions.refresh()
            return stores.focus.sessions
        }
        let ended = try await launch("-MapleDemoReceipt", "leaf")
        #expect(ended.sessionUnlocks.map(\.speciesID) == [leaf])
        let running = try await launch("-MapleDemoFocus", "running", "-MapleDemoFocusAt", "40")
        #expect(running.sessionUnlocks.map(\.speciesID) == [leaf])
        let clean = try await launch("-MapleDemoReceipt", "clean")
        #expect(clean.sessionUnlocks.isEmpty)
        let early = try await launch("-MapleDemoFocus", "running")
        #expect(early.sessionUnlocks.isEmpty)
    }
}

@Suite("Session credit for screens")
@MainActor
struct SessionCreditTests {
    @Test("credit(for:) applies the daily cap across the day; countedSoFar adds only the room left under it")
    func cap() async throws {
        let rig = ScreenRig(at: at(2026, 10, 23, 8))
        let first = try await rig.start(minutes: 180, preset: 2)
        rig.advance(minutes: 180)
        await rig.store.refresh()                                           // 11:00
        let second = try await rig.start(minutes: 150, preset: 2)
        rig.advance(minutes: 150)
        await rig.store.refresh()                                           // 13:30: 5h 30m counted
        let third = try await rig.start(minutes: 50)
        rig.advance(minutes: 20)
        await rig.store.refresh()                                           // 13:50: a checkpoint
        rig.advance(minutes: 20)                                            // 14:10: 20 minutes past it

        #expect(rig.store.credit(for: first)?.seconds == 3 * 3600)
        #expect(rig.store.credit(for: second)?.seconds == 150 * 60)
        let running = try #require(rig.store.credit(for: third))
        #expect(running.seconds == 20 * 60)
        #expect(running.stretches.last?.rule == .unconfirmed)
        // 5h 50m counted today, so 10 of the 20 provisional minutes fit under 6 hours.
        #expect(rig.store.countedSoFar(third) == 30 * 60)
        #expect(rig.store.displayCredit(at: rig.store.now).today == HoursCredit.dailyCap)

        rig.advance(minutes: 10)
        await rig.store.refresh()                                           // 14:20: ends at its planned end
        let ended = try #require(rig.store.credit(for: third))
        #expect(ended.seconds == 30 * 60)
        #expect(ended.stretches.contains { $0.rule == .dailyCap && $0.interval.duration == 20 * 60 })
        #expect(rig.store.countedSoFar(third) == 30 * 60)
        #expect(rig.store.countedSoFar(UUID()) == 0)
        #expect(rig.store.credit(for: UUID()) == nil)
    }

    @Test("credit(for:) counts a session against every other in the replay: time another already counted overlaps")
    func overlap() async throws {
        let rig = ScreenRig(at: at(2026, 10, 23, 12))
        let mine = try await rig.start()
        rig.advance(minutes: 50)
        await rig.store.refresh()                                           // 12:50: completed and verified
        rig.advance(minutes: 20)                                            // 13:10
        // Another process's session on this device, 12:20 to 13:10, its block read back to the end.
        let plan = try #require(rig.store.sessions.first?.plan)
        let other = UUID()
        let now = rig.time.stamp()
        func event(_ kind: FocusEventKind, minutesAgo: Double, seq: Int) -> FocusEvent {
            let ago = minutesAgo * 60
            return FocusEvent(
                id: "other-\(seq)", kind: kind, sessionID: other, deviceID: rig.device, writer: .monitor, seq: seq,
                source: .preview,
                stamp: EventStamp(wall: now.wall.addingTimeInterval(-ago), continuous: now.continuous - UInt64(ago * 1e9),
                                  boot: now.boot, zone: now.zone)
            )
        }
        try rig.ledger.append(event(.sessionStarted(plan), minutesAgo: 50, seq: 1))
        try rig.ledger.append(event(.shieldApplied, minutesAgo: 50, seq: 2))
        try rig.ledger.append(event(.sessionEnded(.completed, verified: true), minutesAgo: 0, seq: 3))
        await rig.store.refresh()

        #expect(rig.store.credit(for: mine)?.seconds == 50 * 60)
        let theirs = try #require(rig.store.credit(for: other))
        #expect(theirs.seconds == 20 * 60)
        #expect(theirs.stretches.contains { $0.rule == .overlap && $0.interval.duration == 30 * 60 })
        #expect(rig.store.countedSoFar(other) == 20 * 60)
    }
}

@Suite("Focus store construction")
@MainActor
struct FocusStoresConstructionTests {
    private func collection() -> CollectionStore {
        CollectionStore(storage: JSONStorage(.memory), context: f1Context, now: at(2026, 10, 23, 9))
    }

    /// Starts a 25-minute plain timer from the last-used preset.
    private func plainStart(_ stores: FocusStores) async throws -> UUID {
        let preset = try #require(stores.presets.lastUsed)
        let request = FocusSessionStore.StartRequest(preset: preset, minutes: 25, appSet: nil, from: .focusTab)
        guard case .started(let id) = await stores.sessions.start(request) else { throw NotStarted() }
        return id
    }

    @Test("Every factory tells the collection what this build can do about blocking before the first refresh")
    func capability() async throws {
        let live = collection()
        #expect(live.context.blocking == .screenTime)
        _ = FocusStores.live(directory: try temporaryDirectory(), collection: live)
        #expect(live.context.blocking == .unavailableInBuild)
        #expect(live.availability(of: .hoursSaved) == .notInThisBuild)

        let sandbox = collection()
        _ = FocusStores.sandbox(directory: try temporaryDirectory(), collection: sandbox, sessionSeconds: nil)
        #expect(sandbox.context.blocking == .preview)
        #expect(sandbox.availability(of: .hoursSaved) == .needsScreenTime)

        let free = collection()
        _ = FocusStores.demo(collection: free, clock: .live,
                             options: DemoLaunchOptions(arguments: ["-MapleDemoScreenTime", "unavailable"]))
        #expect(free.context.blocking == .unavailableInBuild)

        // The session store still keeps it in sync, with the permission, from its first refresh.
        let demo = collection()
        let stores = FocusStores.demo(collection: demo, clock: .live, options: DemoLaunchOptions(arguments: []))
        #expect(demo.context.blocking == .preview)
        #expect(!demo.context.permissions.contains(.screenTime))
        await stores.sessions.refresh()
        #expect(demo.context.blocking == .preview)
        #expect(demo.context.permissions.contains(.screenTime))
        #expect(demo.availability(of: .hoursSaved) == .available)
    }

    @Test("The Live Activity controller is the one the launch passes in; a demo launch's store keeps none")
    func liveActivity() async throws {
        let live = RecordingLiveActivityController()
        let liveStores = FocusStores.live(directory: try temporaryDirectory(), collection: collection(), liveActivity: live)
        let liveID = try await plainStart(liveStores)
        #expect(live.shownSessions == [liveID])

        let sandbox = RecordingLiveActivityController()
        let sandboxStores = FocusStores.sandbox(directory: try temporaryDirectory(), collection: collection(), sessionSeconds: nil,
                                                liveActivity: sandbox)
        let sandboxID = try await plainStart(sandboxStores)
        #expect(sandbox.shownSessions == [sandboxID])

        let demo = RecordingLiveActivityController()
        let demoStores = FocusStores.demo(collection: collection(), clock: .live, options: DemoLaunchOptions(arguments: []),
                                          liveActivity: demo)
        let demoID = try await plainStart(demoStores)
        #expect(demo.shownSessions == [demoID])

        // A demo launch's store never shows one: Task 18's -MapleDemoLiveActivity runner drives the controller.
        let made = RecordingLiveActivityController()
        let madeStores = MapleStores.make(DemoLaunchOptions(arguments: ["-MapleDemoSpecies", "10"]), directory: try temporaryDirectory(),
                                          calendar: utc, now: at(2026, 10, 23, 9), liveActivity: made)
        _ = try await plainStart(madeStores.focus)
        #expect(made.shownSessions.isEmpty)

        let launched = RecordingLiveActivityController()
        let liveMade = MapleStores.live(directory: try temporaryDirectory(), calendar: utc, now: at(2026, 10, 23, 9),
                                        healthAuthorizer: FakeHealthAuthorizer(), liveActivity: launched)
        let launchedID = try await plainStart(liveMade.focus)
        #expect(launched.shownSessions == [launchedID])
    }
}

@Suite("Starting from a screen")
@MainActor
struct FocusStartTests {
    private func stores() -> FocusStores {
        let collection = CollectionStore(storage: JSONStorage(.memory), context: f1Context, now: at(2026, 10, 23, 9))
        return FocusStores.demo(collection: collection, clock: .live, options: DemoLaunchOptions(arguments: []))
    }

    private let six = AppSet(id: AppSet.distractionsID, name: "Distractions", selection: Data("six".utf8),
                             summary: SelectionSummary(mode: .blockThese, apps: 6, sites: 0, categories: 0))

    @Test("A start marks its preset used, keeps its intention at the start and records the first start")
    func started() async throws {
        let stores = stores()
        let settings = AppSettings(storage: JSONStorage(.memory))
        let quick = stores.presets.presets[1]
        #expect(stores.presets.lastUsed?.id != quick.id)
        let request = FocusSessionStore.StartRequest(preset: quick, minutes: 25, appSet: six, from: .focusTab)
        let outcome = await stores.start(request, intention: "  Chemistry ch. 4 ", settings: settings)
        guard case .started(let id) = outcome else { Issue.record("not started: \(outcome)"); return }
        #expect(stores.presets.lastUsedID == quick.id)
        #expect(stores.notes.intention(for: id) == "Chemistry ch. 4")
        let started = try #require(stores.sessions.running?.started.placed)
        #expect(stores.notes.notes[id.uuidString.lowercased()]?.at == started)
        #expect(settings.hasStartedFocus)
    }

    @Test("Nothing is kept when the session doesn't start, and a blank intention keeps no note")
    func notStarted() async throws {
        let stores = stores()
        let settings = AppSettings(storage: JSONStorage(.memory))
        let preview = try #require(stores.sessions.blocking as? PreviewBlockingService)
        preview.failures = [.applyFails]
        let quick = stores.presets.presets[1]
        let request = FocusSessionStore.StartRequest(preset: quick, minutes: 25, appSet: six, from: .focusTab)
        #expect(await stores.start(request, intention: "Essay", settings: settings) == .blockingFailed(.applyFailed))
        #expect(stores.presets.lastUsedID != quick.id)
        #expect(stores.notes.notes.isEmpty)
        #expect(!settings.hasStartedFocus)

        preview.failures = []
        let outcome = await stores.start(request, intention: "   ", settings: settings)
        guard case .started(let id) = outcome else { Issue.record("not started: \(outcome)"); return }
        #expect(stores.notes.intention(for: id) == nil)
        #expect(stores.notes.notes.isEmpty)
        #expect(settings.hasStartedFocus)
        #expect(await stores.start(request, intention: "Again", settings: settings) == .alreadyRunning)
        #expect(stores.notes.notes.isEmpty)
    }
}

@Suite("Focus settings")
@MainActor
struct FocusSettingsTests {
    @Test("No session has started and no receipt has been seen until they are; both are saved")
    func persisted() throws {
        let url = try temporaryDirectory().appendingPathComponent(AppSettings.file)
        let settings = AppSettings(storage: JSONStorage(.file(url)), regionCode: "GB")
        #expect(!settings.hasStartedFocus)
        #expect(settings.lastReceiptSeen == nil)
        let seen = UUID()
        settings.hasStartedFocus = true
        settings.lastReceiptSeen = seen
        let reloaded = AppSettings(storage: JSONStorage(.file(url)), regionCode: "GB")
        #expect(reloaded.hasStartedFocus)
        #expect(reloaded.lastReceiptSeen == seen)
        #expect(reloaded.snapshot == settings.snapshot)
    }

    @Test("Older or hand-edited files read as no start and no receipt seen")
    func tolerant() throws {
        let decoder = JSONDecoder()
        let older = try decoder.decode(SettingsSnapshot.self, from: Data(#"{"version":1,"revealSound":true}"#.utf8))
        #expect(!older.hasStartedFocus)
        #expect(older.lastReceiptSeen == nil)
        #expect(older.revealSound)
        let odd = try decoder.decode(SettingsSnapshot.self,
                                     from: Data(#"{"hasStartedFocus":"yes","lastReceiptSeen":"not an id"}"#.utf8))
        #expect(!odd.hasStartedFocus)
        #expect(odd.lastReceiptSeen == nil)
        let full = SettingsSnapshot(hasStartedFocus: true, lastReceiptSeen: UUID())
        #expect(try decoder.decode(SettingsSnapshot.self, from: JSONEncoder().encode(full)) == full)
    }

    @Test("A Focus demo's settings follow its scenario; other demos copy the member's; none writes the member's file")
    func demo() throws {
        let folder = try temporaryDirectory()
        let file = folder.appending(path: AppSettings.file)
        let member = SettingsSnapshot(revealSound: true, hasStartedFocus: true, lastReceiptSeen: FocusDemo.subjectID)
        JSONStorage<SettingsSnapshot>(.file(file)).save(member)
        func settings(_ arguments: String...) -> AppSettings {
            AppSettings.demo(DemoLaunchOptions(arguments: arguments), directory: folder)
        }

        let idle = settings("-MapleDemoFocus", "idle")
        #expect(idle.hasStartedFocus)
        #expect(idle.lastReceiptSeen == nil)
        #expect(idle.revealSound)
        #expect(!settings("-MapleDemoFocus", "first").hasStartedFocus)
        #expect(settings("-MapleDemoScreenTime", "unavailable").hasStartedFocus)
        #expect(settings("-MapleDemoScreenTime", "unavailable", "-MapleDemoFocus", "running").hasStartedFocus)
        #expect(settings("-MapleDemoSaved", "empty").hasStartedFocus)
        #expect(settings("-MapleDemoReceipt", "leaf").hasStartedFocus)
        #expect(!settings("-MapleDemoFresh", "YES", "-MapleDemoFocus", "idle").hasStartedFocus)
        #expect(!settings("-MapleDemoFresh", "YES").hasStartedFocus)

        let other = settings("-MapleDemoSpecies", "10")
        #expect(other.snapshot == member)

        idle.hasStartedFocus = false
        #expect(JSONStorage<SettingsSnapshot>(.file(file)).load() == member)
    }
}
#endif
