import Foundation
import Observation
import Synchronization
import Testing
@testable import MapleCore
@testable import MapleServices

/// Review findings "storage-io-error-wipes-collection", "stale-calendar-timezone" and "no-behaviour-data-source"
/// at the store level.
@Suite("Store safety")
@MainActor
struct StoreSafetyTests {
    /// Makes a file unreadable, as it is before the first unlock after a restart.
    private func lock(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
    }

    private func unlock(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
    }

    /// A planted collection saved in `folder`.
    private func savedCollection(in folder: URL) -> CollectionSnapshot {
        let store = CollectionStore(storage: JSONStorage(.file(folder.appendingPathComponent(MapleStores.collectionFile))),
                                    context: testContext, now: at(2026, 10, 1, 21))
        store.raise(.firstSteps, to: 1, at: at(2026, 10, 1, 21))
        store.openReveals(at: at(2026, 10, 1, 21, 5))
        return store.snapshot
    }

    @Test("A collection that can't be read yet is kept, never replaced, and read once it can be")
    func unreadableCollection() throws {
        let folder = try temporaryDirectory()
        let url = folder.appendingPathComponent(MapleStores.collectionFile)
        let real = savedCollection(in: folder)
        let before = try Data(contentsOf: url)
        try lock(url)
        defer { try? unlock(url) }

        let store = CollectionStore(storage: JSONStorage(.file(url)), context: testContext, now: at(2026, 10, 9, 4))
        #expect(!store.isAvailable)
        #expect(store.snapshot.profileID != real.profileID)
        #expect(files(in: folder) == [MapleStores.collectionFile])          // nothing set aside
        // A change while it is still unreadable never reaches the disk.
        store.record([.nightsTracked: 1], at: at(2026, 10, 9, 4))
        #expect(!store.reloadIfUnavailable())

        try unlock(url)
        #expect(try Data(contentsOf: url) == before)
        #expect(store.reloadIfUnavailable())
        #expect(store.isAvailable)
        #expect(store.snapshot == real)
        #expect(store.hasPlacedFirstLeaf)
        #expect(files(in: folder) == [MapleStores.collectionFile])
    }

    @Test("A launch before the first unlock opens on the member's own collection once the files can be read")
    func liveRelaunch() throws {
        let folder = try temporaryDirectory()
        let first = MapleStores.live(directory: folder, calendar: utc, now: at(2026, 10, 1, 21))
        first.schedule.save(.standard, at: at(2026, 10, 1, 21))
        first.collection.openReveals(at: at(2026, 10, 1, 21, 5))
        let profile = first.collection.snapshot.profileID
        let collectionURL = folder.appendingPathComponent(MapleStores.collectionFile)
        let scheduleURL = folder.appendingPathComponent(MapleStores.scheduleFile)
        try lock(collectionURL)
        try lock(scheduleURL)
        defer { try? unlock(collectionURL); try? unlock(scheduleURL) }

        let prewarmed = MapleStores.live(directory: folder, calendar: utc, now: at(2026, 10, 9, 4))
        #expect(!prewarmed.isAvailable)
        #expect(!prewarmed.reloadIfUnavailable())
        try unlock(collectionURL)
        try unlock(scheduleURL)
        #expect(prewarmed.reloadIfUnavailable())
        #expect(prewarmed.isAvailable)
        #expect(prewarmed.collection.snapshot.profileID == profile)
        #expect(prewarmed.schedule.hasSavedSchedule)
        #expect(prewarmed.schedule.firstRun == .finished)
        #expect(Set(files(in: folder)) == [MapleStores.collectionFile, MapleStores.scheduleFile])
    }

    @Test("Schedule and settings files that can't be read are never overwritten with defaults")
    func unreadableScheduleAndSettings() throws {
        let folder = try temporaryDirectory()
        let collection = CollectionStore(storage: JSONStorage(.memory), context: testContext, now: at(2026, 10, 1, 21))
        let scheduleURL = folder.appendingPathComponent(MapleStores.scheduleFile)
        let mine = SleepSchedule(bedtime: ClockTime(hour: 22, minute: 30), wake: ClockTime(hour: 6, minute: 30), windDownMinutes: 30)
        JSONStorage<SavedSchedule>(.file(scheduleURL)).save(SavedSchedule(schedule: mine, savedAt: at(2026, 10, 1, 21)))
        let settingsURL = folder.appendingPathComponent(AppSettings.file)
        let settings = AppSettings(storage: JSONStorage(.file(settingsURL)), regionCode: "GB")
        settings.sleepGoalMinutes = 8 * 60
        try lock(scheduleURL)
        try lock(settingsURL)
        defer { try? unlock(scheduleURL); try? unlock(settingsURL) }

        let schedules = ScheduleStore(storage: JSONStorage(.file(scheduleURL)), collection: collection)
        #expect(!schedules.isAvailable && !schedules.hasSavedSchedule)
        let lockedSettings = AppSettings(storage: JSONStorage(.file(settingsURL)), regionCode: "GB")
        #expect(!lockedSettings.isAvailable)
        lockedSettings.revealSound = true                                  // refused on disk while unreadable

        try unlock(scheduleURL)
        try unlock(settingsURL)
        #expect(schedules.reloadIfUnavailable())
        #expect(schedules.schedule == mine && collection.schedule == mine)
        #expect(lockedSettings.reloadIfUnavailable())
        #expect(lockedSettings.sleepGoalMinutes == 8 * 60)
        #expect(AppSettings(storage: JSONStorage(.file(settingsURL)), regionCode: "GB").sleepGoalMinutes == 8 * 60)
        #expect(!files(in: folder).contains { $0.contains("damaged") })
    }

    @Test("A collection an older build set aside is restored when the file is missing")
    func restoresSetAside() throws {
        let folder = try temporaryDirectory()
        let real = savedCollection(in: folder)
        let url = folder.appendingPathComponent(MapleStores.collectionFile)
        try FileManager.default.moveItem(at: url, to: folder.appendingPathComponent("collection.damaged-1790000000.json"))
        try Data("{ not json".utf8).write(to: folder.appendingPathComponent("collection.damaged-1790000500.json"))

        let store = CollectionStore(storage: JSONStorage(.file(url)), context: testContext, now: at(2026, 10, 9, 8))
        #expect(store.isAvailable)
        #expect(store.snapshot == real)
        #expect(Set(files(in: folder)) == [MapleStores.collectionFile, "collection.damaged-1790000500.json"])
    }

    /// Review finding "restore-unreadable-setaside": the copy an older build set aside can't be read before the first
    /// unlock, and must not be taken for a first run.
    @Test("A set-aside collection that can't be read yet is waited for, never replaced by an empty one")
    func unreadableSetAside() throws {
        let folder = try temporaryDirectory()
        let real = savedCollection(in: folder)
        let url = folder.appendingPathComponent(MapleStores.collectionFile)
        let copy = folder.appendingPathComponent("collection.damaged-1790000000.json")
        try FileManager.default.moveItem(at: url, to: copy)
        try lock(copy)
        defer { try? unlock(copy) }

        let store = CollectionStore(storage: JSONStorage(.file(url)), context: testContext, now: at(2026, 10, 9, 4))
        #expect(!store.isAvailable)
        #expect(!store.hasPlantedMaple)
        // The first run resuming before the first unlock never creates the missing file.
        store.raise(.firstSteps, to: 1, at: at(2026, 10, 9, 4))
        #expect(!store.reloadIfUnavailable())
        #expect(files(in: folder) == ["collection.damaged-1790000000.json"])

        try unlock(copy)
        #expect(store.reloadIfUnavailable())
        #expect(store.isAvailable)
        #expect(store.snapshot == real)
        #expect(store.hasPlacedFirstLeaf)
        #expect(files(in: folder) == [MapleStores.collectionFile])
        #expect(CollectionStore(storage: JSONStorage(.file(url)), context: testContext).snapshot == real)
    }

    @Test("Only a protection or permission error makes a set-aside copy worth waiting for")
    func lockedOutErrors() throws {
        let noPermission = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError,
                                   userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))])
        #expect(JSONStorage<Int>.isLockedOut(noPermission))
        #expect(JSONStorage<Int>.isLockedOut(NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))))
        #expect(!JSONStorage<Int>.isLockedOut(NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError)))
        #expect(!JSONStorage<Int>.isLockedOut(NSError(domain: NSPOSIXErrorDomain, code: Int(EISDIR))))

        // A newer leftover that fails to read for another reason (here a folder) is skipped, as a damaged one is.
        let folder = try temporaryDirectory()
        let real = savedCollection(in: folder)
        let url = folder.appendingPathComponent(MapleStores.collectionFile)
        try FileManager.default.moveItem(at: url, to: folder.appendingPathComponent("collection.damaged-1790000000.json"))
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("collection.damaged-1790000900.json"),
                                                withIntermediateDirectories: false)
        let store = CollectionStore(storage: JSONStorage(.file(url)), context: testContext, now: at(2026, 10, 9, 8))
        #expect(store.isAvailable)
        #expect(store.snapshot == real)
    }

    @Test("A time-zone change refreshes everything that read the collection")
    func timeZoneChange() {
        let store = CollectionStore(storage: JSONStorage(.memory), context: CollectionContext(calendar: .autoupdatingCurrent), now: .now)
        store.followsSystemCalendar = true
        let refreshed = Mutex(false)
        withObservationTracking {
            _ = store.context.calendar
        } onChange: {
            refreshed.withLock { $0 = true }
        }
        store.systemTimeChanged()
        #expect(refreshed.withLock { $0 })
        #expect(store.context.calendar == .autoupdatingCurrent)

        // A store that doesn't follow the system (a DEBUG demo, a test) keeps its calendar.
        let fixed = CollectionStore(storage: JSONStorage(.memory), context: testContext, now: .now)
        fixed.systemTimeChanged()
        #expect(fixed.context.calendar == utc)
        #expect(MapleStores.live(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
            .collection.followsSystemCalendar)
    }

    @Test("Apple Health's nights are recorded, settled the next morning and saved")
    func appleHealthNights() throws {
        let folder = try temporaryDirectory()
        let url = folder.appendingPathComponent(MapleStores.collectionFile)
        var context = testContext
        context.permissions = [.appleHealth]
        let store = CollectionStore(storage: JSONStorage(.file(url)), context: context, now: at(2026, 10, 1, 21))
        let night = SleepNightObservation(onset: at(2026, 10, 1, 22, 55), finalWake: at(2026, 10, 2, 7), asleepMinutes: 460,
                                          source: .watchOrTracker, calendar: utc)
        #expect(store.recordSleep([night], at: at(2026, 10, 2, 7, 10)).isEmpty)       // not planted yet
        #expect(store.snapshot.counters.isEmpty)
        store.raise(.firstSteps, to: 1, at: at(2026, 10, 1, 21))
        store.openReveals(at: at(2026, 10, 1, 21, 5))
        #expect(store.recordSleep([night], at: at(2026, 10, 2, 3)).isEmpty)            // the morning hasn't started
        let unlocked = store.recordSleep([night], at: at(2026, 10, 2, 7, 10))
        #expect(unlocked.count == 2)
        #expect(store.revealable(at: at(2026, 10, 2, 7, 10)).count == 2)
        #expect(store.currentBedtimeRun == 1)

        let reloaded = CollectionStore(storage: JSONStorage(.file(url)), context: context)
        #expect(reloaded.snapshot == store.snapshot)
        #expect(reloaded.recordSleep([night], at: at(2026, 10, 2, 9)).isEmpty)
    }
}
