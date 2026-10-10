import Foundation
import Testing
@testable import MapleCore
@testable import MapleServices

@Suite("Collection store")
@MainActor
struct CollectionStoreTests {
    @Test("First launch creates and saves a collection with a stable tree seed")
    func firstLaunch() throws {
        let folder = try temporaryDirectory()
        let url = folder.appendingPathComponent("collection.json")
        let store = CollectionStore(storage: JSONStorage(.file(url)), context: testContext, now: at(2026, 10, 1, 9))
        #expect(store.snapshot.unlocks.isEmpty)
        #expect(!store.hasPlantedMaple)
        #expect(FileManager.default.fileExists(atPath: url.path))
        let again = CollectionStore(storage: JSONStorage(.file(url)), context: testContext, now: at(2026, 12, 1))
        #expect(again.snapshot.treeSeed == store.snapshot.treeSeed)
        #expect(again.snapshot.createdAt == at(2026, 10, 1, 9))
    }

    @Test("Recording runs the engine and persists every change")
    func recordAndPersist() throws {
        let url = try temporaryDirectory().appendingPathComponent("collection.json")
        let store = CollectionStore(storage: JSONStorage(.file(url)), context: testContext, now: at(2026, 10, 1, 9))
        store.raise(.firstSteps, to: 1, at: at(2026, 10, 1, 9))
        let unlocked = store.record([.nightsTracked: 1], at: at(2026, 10, 2, 7))
        #expect(unlocked.map(\.speciesID) == ["rubrum"])
        #expect(store.waiting.map(\.speciesID) == ["saccharum", "rubrum"])
        let opened = store.openReveals(at: at(2026, 10, 2, 8))
        #expect(opened.map(\.speciesID) == ["saccharum", "rubrum"])
        store.markSeen("rubrum")
        store.pin("palmatum")
        store.feature("saccharum")
        store.setRarityConsent(true)

        let reloaded = CollectionStore(storage: JSONStorage(.file(url)), context: testContext)
        #expect(reloaded.snapshot == store.snapshot)
        #expect(reloaded.earned.map(\.speciesID) == ["saccharum", "rubrum"])
        #expect(reloaded.snapshot.tendedDays == [LocalDay(year: 2026, month: 10, day: 2)])
        #expect(reloaded.pinnedSpeciesID == "palmatum")
        #expect(reloaded.featuredLeaf == "saccharum")
        #expect(reloaded.rarityConsent == .included)
        #expect(reloaded.revealsOpened == 2)
        #expect(!reloaded.isUnseen("rubrum"))
        #expect(reloaded.isUnseen("saccharum"))
    }

    @Test("In-memory collections never touch the disk")
    func memory() throws {
        let folder = try temporaryDirectory()
        let store = CollectionStore(storage: JSONStorage(.memory), context: testContext, now: at(2026, 10, 1, 9))
        store.raise(.firstSteps, to: 1, at: at(2026, 10, 1, 9))
        #expect(store.hasPlantedMaple)
        #expect(files(in: folder).isEmpty)
    }

    @Test("A damaged file is set aside, never overwritten")
    func damaged() throws {
        let folder = try temporaryDirectory()
        let url = folder.appendingPathComponent("collection.json")
        try Data("{ not json".utf8).write(to: url)
        let store = CollectionStore(storage: JSONStorage(.file(url)), context: testContext, now: at(2026, 10, 1, 9))
        #expect(store.snapshot.unlocks.isEmpty)
        #expect(files(in: folder).contains { $0.hasPrefix("collection.damaged-") })
    }

    @Test("Derived values follow the schedule and the clock")
    func derived() {
        let store = CollectionStore(storage: JSONStorage(.memory), context: testContext, now: at(2026, 10, 1, 9))
        store.raise(.firstSteps, to: 1, at: at(2026, 10, 1, 9))
        store.openReveals(at: at(2026, 10, 1, 9, 5))
        store.record([.nightsTracked: 1], at: at(2026, 10, 2, 21))      // evening: held until morning
        #expect(store.revealable(at: at(2026, 10, 2, 21, 30)).isEmpty)
        #expect(store.held(at: at(2026, 10, 2, 21, 30)).map(\.speciesID) == ["rubrum"])
        // Moving bedtime later makes 21:00 part of the day, so the leaf is pending at once.
        store.schedule = SleepSchedule(bedtime: ClockTime(hour: 1), wake: ClockTime(hour: 9), windDownMinutes: 60)
        #expect(store.revealable(at: at(2026, 10, 2, 21, 30)).map(\.speciesID) == ["rubrum"])

        let now = at(2026, 10, 2, 21, 30)
        #expect(store.progress(at: now).count == 155)
        #expect(store.progress(for: "palmatum", at: now)?.current == 0)
        #expect(store.nextLeaf(at: now) != nil)
        #expect(store.buds(at: now).count == 3)
        #expect(store.treeInputs(at: now).species.map(\.speciesID) == ["saccharum"])
        #expect(store.nowState(at: now, locale: Locale(identifier: "en_GB")).phase == .day)
        #expect(store.totals.leaves == 1)
        #expect(store.vitality(at: now).value == 1)
    }

    @Test("Mark all seen, the bedtime run and nights")
    func housekeeping() {
        let store = CollectionStore(storage: JSONStorage(.memory), context: testContext, now: at(2026, 10, 1, 9))
        store.raise(.firstSteps, to: 1, at: at(2026, 10, 1, 9))
        store.record([.nightsTracked: 1], at: at(2026, 10, 2, 7))
        store.openReveals(at: at(2026, 10, 2, 8))
        #expect(store.isUnseen("saccharum") && store.isUnseen("rubrum"))
        store.markAllSeen()
        #expect(!store.isUnseen("saccharum") && !store.isUnseen("rubrum"))

        let unlocked = store.setCurrentBedtimeRun(3, at: at(2026, 10, 3, 7))
        #expect(unlocked.map(\.speciesID) == ["maximowiczianum"])
        #expect(store.currentBedtimeRun == 3)
        store.setCurrentBedtimeRun(0, at: at(2026, 10, 4, 7))
        #expect(store.currentBedtimeRun == 0)
        #expect(store.snapshot.counters[.bedtimeRun] == 3)            // the best run is kept

        store.recordNight(NightRecord(day: LocalDay(year: 2026, month: 10, day: 3), onTime: false, fullNight: nil, scrollFree: nil))
        #expect(store.vitality(at: at(2026, 10, 4, 7)).value == 0.4)
        #expect(store.vitality(at: at(2026, 10, 4, 7)).isQuiet)
    }

    @Test("Progress is cached per change, and recomputed after one")
    func cache() {
        let store = CollectionStore(storage: JSONStorage(.memory), context: testContext, now: at(2026, 10, 1, 9))
        let now = at(2026, 10, 2, 12)
        #expect(store.progress(for: "rubrum", at: now)?.current == 0)
        store.record([.nightsTracked: 1], at: at(2026, 10, 2, 7))
        #expect(store.progress(for: "saccharinum", at: now)?.current == 1)
    }
}

@Suite("Schedule store")
@MainActor
struct ScheduleStoreTests {
    @Test("Saving the first schedule plants the maple with the sugar maple")
    func firstSave() throws {
        let folder = try temporaryDirectory()
        let collection = CollectionStore(storage: JSONStorage(.file(folder.appendingPathComponent("collection.json"))),
                                         context: testContext, now: at(2026, 10, 1, 21))
        let schedules = ScheduleStore(storage: JSONStorage(.file(folder.appendingPathComponent("schedule.json"))), collection: collection)
        #expect(!schedules.hasSavedSchedule)
        #expect(schedules.schedule == .standard)

        let mine = SleepSchedule(bedtime: ClockTime(hour: 22, minute: 30), wake: ClockTime(hour: 6, minute: 30), windDownMinutes: 30)
        let unlocked = schedules.save(mine, at: at(2026, 10, 1, 23, 40))
        #expect(unlocked.map(\.speciesID) == ["saccharum"])
        #expect(RewardCatalog.shared.reward(forSpecies: "saccharum")?.unlockText == "Set your sleep schedule")
        #expect(collection.hasPlantedMaple)
        #expect(collection.schedule == mine)
        #expect(collection.snapshot.counters[.firstSteps] == 1)
        #expect(collection.snapshot.tendedDays.isEmpty)
        // It is the one leaf that can be opened at night.
        #expect(collection.revealable(at: at(2026, 10, 1, 23, 45)).map(\.speciesID) == ["saccharum"])

        // The first schedule replaces nothing.
        #expect(collection.snapshot.nights.pastSchedules.isEmpty)

        // Later saves change the schedule only.
        let later = SleepSchedule(bedtime: ClockTime(hour: 23), wake: ClockTime(hour: 7), windDownMinutes: 60)
        #expect(schedules.save(later, at: at(2026, 10, 3, 12)).isEmpty)
        #expect(collection.snapshot.unlocks.count == 1)
        #expect(collection.schedule == later)

        // Nights already under way when it changed keep the schedule they began with.
        #expect(collection.snapshot.nights.pastSchedules
            == [NightLedger.PastSchedule(through: LocalDay(year: 2026, month: 10, day: 2), schedule: mine)])

        let reloadedCollection = CollectionStore(storage: JSONStorage(.file(folder.appendingPathComponent("collection.json"))), context: testContext)
        let reloaded = ScheduleStore(storage: JSONStorage(.file(folder.appendingPathComponent("schedule.json"))), collection: reloadedCollection)
        #expect(reloaded.hasSavedSchedule)
        #expect(reloaded.schedule == later)
        #expect(reloadedCollection.schedule == later)
    }

    /// The member's real stores in `folder`, as a launch builds them.
    private func launch(_ folder: URL) -> MapleStores {
        MapleStores.live(directory: folder, calendar: utc, now: at(2026, 10, 1, 21))
    }

    @Test("Killed after Save schedule: the relaunch resumes at the sprout, without asking again or a second leaf")
    func resumeAfterSave() throws {
        let folder = try temporaryDirectory()
        let first = launch(folder)
        #expect(first.schedule.firstRun == .schedule)
        #expect(first.schedule.resumeFirstRun(at: at(2026, 10, 1, 21)) == .schedule)
        first.schedule.save(.standard, at: at(2026, 10, 1, 22, 40))
        #expect(first.schedule.firstRun == .sprout)

        // The app is killed here, before "Place on your maple", and launched again (in wind-down, then at night).
        for relaunchAt in [at(2026, 10, 1, 22, 50), at(2026, 10, 2, 2)] {
            let again = launch(folder)
            #expect(again.schedule.hasSavedSchedule)
            #expect(again.schedule.resumeFirstRun(at: relaunchAt) == .sprout)
            #expect(again.collection.unlocks.map(\.speciesID) == ["saccharum"])
            #expect(!again.collection.hasPlacedFirstLeaf)
            // The Sugar maple can still be opened at any hour, so the sprout never dead-ends.
            #expect(again.collection.revealable(at: relaunchAt).map(\.speciesID) == ["saccharum"])
        }

        // Placed on the third launch: the next one opens on the tabs.
        let third = launch(folder)
        #expect(third.collection.openReveals(["saccharum"], at: at(2026, 10, 2, 2, 5)).map(\.speciesID) == ["saccharum"])
        let fourth = launch(folder)
        #expect(fourth.schedule.firstRun == .finished)
        #expect(!fourth.schedule.firstRun.needsOnboarding)
        #expect(fourth.collection.unlocks.count == 1)
        #expect(fourth.collection.revealsOpened == 1)
    }

    @Test("Killed between the schedule file and the collection file: the leaf is recorded once on relaunch")
    func repairInterruptedSave() throws {
        let folder = try temporaryDirectory()
        // Only the schedule file made it to disk.
        JSONStorage<SavedSchedule>(.file(folder.appendingPathComponent(MapleStores.scheduleFile)))
            .save(SavedSchedule(schedule: .standard, savedAt: at(2026, 10, 1, 22, 40)))
        let relaunch = launch(folder)
        #expect(relaunch.schedule.firstRun == .recordFirstLeaf)
        #expect(relaunch.schedule.resumeFirstRun(at: at(2026, 10, 1, 22, 45)) == .sprout)
        #expect(relaunch.collection.unlocks.map(\.speciesID) == ["saccharum"])
        // Resuming again, or saving the schedule again, never awards it twice.
        #expect(relaunch.schedule.resumeFirstRun(at: at(2026, 10, 1, 22, 46)) == .sprout)
        #expect(relaunch.schedule.save(.standard, at: at(2026, 10, 1, 22, 47)).isEmpty)
        #expect(launch(folder).collection.unlocks.map(\.speciesID) == ["saccharum"])
    }

    /// Review finding "schedule-edit-same-night": rewards.md, "Schedule edits apply from the next night (cut-off
    /// 18:00 local), so a target can't be moved after the fact".
    @Test("Moving bedtime later once the night has begun never rescues that night")
    func scheduleEditSameNight() {
        let collection = CollectionStore(storage: JSONStorage(.memory), context: testContext, now: at(2026, 10, 1, 12))
        let schedules = ScheduleStore(storage: JSONStorage(.memory), collection: collection)
        schedules.save(.standard, at: at(2026, 10, 1, 12))                                    // bedtime 23:00
        collection.openReveals(at: at(2026, 10, 1, 12, 5))
        collection.recordSleep([], at: at(2026, 10, 5, 12))                                    // settled through the 4th

        // 23:40 on the 5th, already late: bedtime moves to 00:00, and sleep comes at 23:45.
        let midnight = SleepSchedule(bedtime: ClockTime(hour: 0), wake: ClockTime(hour: 7), windDownMinutes: 45)
        schedules.save(midnight, at: at(2026, 10, 5, 23, 40))
        #expect(collection.schedule == midnight)
        let tonight = SleepNightObservation(onset: at(2026, 10, 5, 23, 45), finalWake: at(2026, 10, 6, 7), asleepMinutes: 440,
                                            source: .watchOrTracker, calendar: utc)
        collection.recordSleep([tonight], at: at(2026, 10, 6, 7, 30))
        #expect(collection.snapshot.nights.recent.last?.night == LocalDay(year: 2026, month: 10, day: 5))
        #expect(collection.snapshot.nights.recent.last?.outcome == .late)
        #expect(collection.snapshot.counters[.onTimeBedtimes, default: 0] == 0)

        // From the next night on, 00:00 is the bedtime.
        let next = SleepNightObservation(onset: at(2026, 10, 7, 0, 10), finalWake: at(2026, 10, 7, 7), asleepMinutes: 400,
                                         source: .watchOrTracker, calendar: utc)
        collection.recordSleep([next], at: at(2026, 10, 7, 7, 30))
        #expect(collection.snapshot.nights.recent.last?.outcome == .onTime)
        #expect(collection.snapshot.counters[.onTimeBedtimes] == 1)
    }
}

@Suite("Collection count")
@MainActor
struct CollectionCountTests {
    @Test("N counts opened leaves; waiting ones are told apart, and the stage follows N")
    func openedOnly() {
        let store = CollectionStore(storage: JSONStorage(.memory), context: testContext, now: at(2026, 10, 1, 9))
        store.raise(.firstSteps, to: 1, at: at(2026, 10, 1, 9))
        #expect(store.leafCount == LeafCount(opened: 0, waiting: 1, total: 155))
        #expect(store.openedCount == 0)
        #expect(store.stage == .seed)
        store.openReveals(at: at(2026, 10, 1, 9, 5))
        store.record([.nightsTracked: 3], at: at(2026, 10, 2, 9))
        #expect(store.waiting.count == 2)
        #expect(store.openedCount == 1)
        #expect(store.leafCount.text == "1 of 155")
        #expect(store.leafCount.waitingText == "2 waiting")
        #expect(store.stage == .seedling)
        #expect(store.totals.leaves == 1)
        #expect(store.treeInputs(at: at(2026, 10, 2, 10)).species.count == store.openedCount)
        store.openReveals(at: at(2026, 10, 2, 10))
        #expect(store.openedCount == 3)
        #expect(store.leafCount.waitingText == nil)
    }
}

@Suite("Leaf share store")
@MainActor
struct LeafShareStoreTests {
    private let now = at(2026, 10, 10, 9)

    private func store(_ provider: any LeafShareProvider, folder: URL? = nil, clock: MapleClock? = nil) -> LeafShareStore {
        let storage: JSONStorage<LeafShareCache> = folder.map { JSONStorage(.file($0.appendingPathComponent("leaf-shares.json"))) } ?? JSONStorage(.memory)
        return LeafShareStore(provider: provider, storage: storage, clock: clock ?? .fixed(now), locale: Locale(identifier: "en_US"))
    }

    @Test("Unconfigured: not enough members, and dormant leaves are not earnable")
    func unconfigured() async {
        let shares = store(UnconfiguredLeafShareProvider())
        #expect(shares.share(for: "rubrum") == .loading)
        await shares.refreshIfNeeded()
        #expect(shares.share(for: "rubrum") == .notEnoughMembers(soFar: nil))
        #expect(shares.share(for: "buergerianum") == .notEarnableYet)
        #expect(shares.estimate(for: "rubrum") == nil)
        #expect(shares.memberCount == nil)
    }

    @Test("Fetches at most once a day and caches the result on disk")
    func caching() async throws {
        let folder = try temporaryDirectory()
        let provider = StubShareProvider(.success(counts(members: 12_480, ["rubrum": 2_746])))
        let shares = store(provider, folder: folder)
        await shares.refreshIfNeeded()
        await shares.refreshIfNeeded()
        #expect(await provider.calls == 1)
        #expect(shares.share(for: "rubrum") == .value(display: "22%", asOf: now))
        #expect(shares.memberCount == 12_400)
        #expect(shares.weekStart == at(2026, 9, 28))
        #expect(shares.estimate(for: "rubrum") != nil)

        // A new launch reads the cache without asking again.
        let relaunched = store(provider, folder: folder, clock: .fixed(now.addingTimeInterval(23 * 3600)))
        #expect(relaunched.share(for: "rubrum") == .value(display: "22%", asOf: now))
        await relaunched.refreshIfNeeded()
        #expect(await provider.calls == 1)

        // After 24 hours it asks again; force always asks.
        let tomorrow = store(provider, folder: folder, clock: .fixed(now.addingTimeInterval(25 * 3600)))
        await tomorrow.refreshIfNeeded()
        #expect(await provider.calls == 2)
        await tomorrow.refreshIfNeeded(force: true)
        #expect(await provider.calls == 3)
    }

    @Test("Offline: never fetched without a cache, stale after 48 hours with one")
    func offline() async throws {
        let folder = try temporaryDirectory()
        let provider = StubShareProvider(.failure(Offline()))
        let fresh = store(provider, folder: folder)
        await fresh.refreshIfNeeded()
        #expect(fresh.share(for: "rubrum") == .neverFetched)

        await provider.set(.success(counts(members: 12_400, ["rubrum": 2_728])))
        await fresh.refreshIfNeeded()
        #expect(fresh.share(for: "rubrum") == .value(display: "22%", asOf: now))

        await provider.set(.failure(Offline()))
        let later = store(provider, folder: folder, clock: .fixed(now.addingTimeInterval(49 * 3600)))
        await later.refreshIfNeeded()
        #expect(later.share(for: "rubrum") == .stale(display: "22%", asOf: now))
        #expect(later.estimate(for: "rubrum") == nil)
    }

    @Test("A cache from another provider is ignored")
    func providerChange() async throws {
        let folder = try temporaryDirectory()
        await store(UnconfiguredLeafShareProvider(), folder: folder).refreshIfNeeded()
        let provider = StubShareProvider(identifier: "cloudkit", .success(counts(members: 5_000, ["rubrum": 900])))
        let upgraded = store(provider, folder: folder)
        #expect(upgraded.share(for: "rubrum") == .loading)
        await upgraded.refreshIfNeeded()
        #expect(await provider.calls == 1)
        #expect(upgraded.share(for: "rubrum") == .value(display: "18%", asOf: now))
    }
}
