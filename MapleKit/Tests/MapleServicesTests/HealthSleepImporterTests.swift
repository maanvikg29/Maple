import Foundation
import HealthKit
import Testing
@testable import MapleCore
@testable import MapleServices

/// Apple Health's sleep store as the test says it is: samples come and go, and each read returns what changed since
/// the anchor it was given.
@MainActor
final class FakeSleepReader: SleepSampleReading {
    var isHealthDataAvailable = true
    var failure: SleepReadError?
    private(set) var reads: [(anchor: Data?, start: Date)] = []
    private(set) var backgroundDeliveryRequests = 0
    private(set) var onChange: (@MainActor @Sendable () async -> Void)?
    private var version = 0
    private var stored: [(sample: SleepSample, version: Int)] = []
    private var deletions: [(id: String, version: Int)] = []

    func add(_ samples: [SleepSample]) {
        version += 1
        stored += samples.map { ($0, version) }
    }

    func delete(_ ids: Set<String>) {
        version += 1
        stored.removeAll { ids.contains($0.sample.id) }
        deletions += ids.map { ($0, version) }
    }

    func changes(since anchor: Data?, from start: Date, zone: String) async throws(SleepReadError) -> SleepSampleChanges {
        reads.append((anchor, start))
        if let failure { throw failure }
        let since = anchor.flatMap { Int(String(decoding: $0, as: UTF8.self)) } ?? 0
        return SleepSampleChanges(
            added: stored.filter { $0.version > since && $0.sample.end > start }.map(\.sample),
            deletedIDs: since == 0 ? [] : deletions.filter { $0.version > since }.map(\.id),
            anchor: Data("\(version)".utf8)
        )
    }

    func startObserving(_ onChange: @escaping @MainActor @Sendable () async -> Void) {
        self.onChange = onChange
    }

    func stopObserving() {
        onChange = nil
    }

    func enableBackgroundDelivery() async throws(SleepReadError) {
        backgroundDeliveryRequests += 1
    }
}

private let watch = SleepSample.Origin(bundleIdentifier: "com.apple.health.watch", name: "Apple Watch", productType: "Watch7,1",
                                       deviceModel: "Watch")
private let iPhone = SleepSample.Origin(bundleIdentifier: "com.apple.health.phone", name: "iPhone", productType: "iPhone17,1")

/// A Watch night from `onset` to `wake`, with ids that say which night it is.
private func watchNight(_ onset: Date, _ wake: Date, tag: String) -> [SleepSample] {
    [SleepSample(id: "\(tag)-asleep", start: onset, end: wake, stage: .asleepCore, origin: watch)]
}

@Suite("Apple Health sleep import")
@MainActor
struct HealthSleepImporterTests {
    /// Planted at 21:00 on 1 October (install night 1 Oct), Apple Health connected, the standard schedule.
    private func member(
        connected: Bool = true, planted: Bool = true, reader: FakeSleepReader = FakeSleepReader()
    ) async throws -> (stores: MapleStores, importer: HealthSleepImporter, reader: FakeSleepReader, folder: URL) {
        let folder = try temporaryDirectory()
        let stores = MapleStores.live(directory: folder, calendar: utc, now: at(2026, 10, 1, 20),
                                      healthAuthorizer: FakeHealthAuthorizer())
        if planted {
            stores.schedule.save(.standard, at: at(2026, 10, 1, 21))
            stores.collection.openReveals(at: at(2026, 10, 1, 21, 5))
        }
        if connected {
            await stores.health.requestAccess(at: at(2026, 10, 1, 21, 10))
            stores.health.apply(to: stores.collection)
        }
        let importer = HealthSleepImporter.live(container: folder, health: stores.health, collection: stores.collection,
                                                reader: reader)
        return (stores, importer, reader, folder)
    }

    @Test("Not connected, not planted, or no Apple Health: nothing is read or recorded")
    func doesNothing() async throws {
        let notConnected = try await member(connected: false)
        #expect(await notConnected.importer.importNow(at: at(2026, 10, 2, 8)).isEmpty)
        #expect(notConnected.reader.reads.isEmpty)

        let notPlanted = try await member(planted: false)
        #expect(await notPlanted.importer.importNow(at: at(2026, 10, 2, 8)).isEmpty)
        #expect(notPlanted.reader.reads.isEmpty)

        let reader = FakeSleepReader()
        reader.isHealthDataAvailable = false
        let unavailable = try await member(reader: reader)
        #expect(await unavailable.importer.importNow(at: at(2026, 10, 2, 8)).isEmpty)
        #expect(reader.reads.isEmpty)
        #expect(unavailable.importer.lastImportAt == nil)
    }

    @Test("A Watch night is read, built and recorded: leaves the next morning, Home's numeral, the local cache")
    func importsANight() async throws {
        let (stores, importer, reader, folder) = try await member()
        reader.add(watchNight(at(2026, 10, 1, 23, 5), at(2026, 10, 2, 6, 55), tag: "oct1"))

        let unlocked = await importer.importNow(at: at(2026, 10, 2, 7, 30))
        #expect(!unlocked.isEmpty)
        #expect(stores.collection.snapshot.counters[.nightsTracked] == 1)
        #expect(stores.collection.snapshot.counters[.onTimeBedtimes] == 1)
        // A night with asleep time unlocks Full nights.
        #expect(stores.collection.availability(of: .fullNights) == .available)

        // The first read has no anchor and starts the evening before the install night.
        let firstRead = try #require(reader.reads.first)
        #expect(firstRead.anchor == nil)
        #expect(firstRead.start == at(2026, 9, 30, 18))

        #expect(importer.hasReceivedSleep)
        #expect(importer.lastImportAt == at(2026, 10, 2, 7, 30))
        #expect(importer.lastNight?.night == LocalDay(year: 2026, month: 10, day: 1))
        let lastNight = try #require(importer.lastNightSleep(at: at(2026, 10, 2, 7, 30)))
        #expect(lastNight.asleep == at(2026, 10, 1, 23, 5))
        #expect(lastNight.duration == 470 * 60)
        // Home's morning numeral comes from it.
        let state = stores.collection.nowState(at: at(2026, 10, 2, 7, 30), locale: Locale(identifier: "en_GB"), lastNight: lastNight)
        #expect(state.content == .lastNightSleep)
        #expect(state.numeral.text == "7h 50m")
        #expect(state.caption == "asleep 23:05 · up 06:55")

        // The cache is local only: its own folder, excluded from backups, never in the synced stores.
        let cacheFolder = folder.appending(path: HealthSleepImporter.folder)
        #expect(files(in: cacheFolder) == [HealthSleepImporter.file])
        let values = try cacheFolder.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
        let saved = try #require(JSONStorage<SleepImportCache>(.file(cacheFolder.appending(path: HealthSleepImporter.file))).load())
        #expect(saved.samples.map(\.id) == ["oct1-asleep"])
        #expect(saved.anchor != nil)

        // A relaunch has last night at once, before reading Apple Health again.
        let relaunched = HealthSleepImporter.live(container: folder, health: stores.health, collection: stores.collection,
                                                  reader: FakeSleepReader())
        #expect(relaunched.lastNightSleep(at: at(2026, 10, 2, 9)) == lastNight)
        #expect(relaunched.hasReceivedSleep)
    }

    @Test("Each run reads on from the anchor and sends every night again, which records nothing twice")
    func incremental() async throws {
        let (stores, importer, reader, _) = try await member()
        reader.add(watchNight(at(2026, 10, 1, 23), at(2026, 10, 2, 7), tag: "oct1"))
        await importer.importNow(at: at(2026, 10, 2, 7, 30))
        reader.add(watchNight(at(2026, 10, 2, 23), at(2026, 10, 3, 7), tag: "oct2"))
        await importer.importNow(at: at(2026, 10, 3, 7, 30))
        await importer.importNow(at: at(2026, 10, 3, 9))

        #expect(reader.reads.count == 3)
        #expect(reader.reads[1].anchor.map { String(decoding: $0, as: UTF8.self) } == "1")
        #expect(stores.collection.snapshot.counters[.nightsTracked] == 2)
        #expect(stores.collection.snapshot.counters[.onTimeBedtimes] == 2)
        #expect(stores.collection.currentBedtimeRun == 2)
    }

    @Test("No backfill: nights before the install night are read but never counted")
    func noBackfill() async throws {
        let (stores, importer, reader, _) = try await member()
        for day in 20...30 {
            let onset = at(2026, 9, day, 23)
            reader.add(watchNight(onset, onset.addingTimeInterval(8 * 3600), tag: "sep\(day)"))
        }
        await importer.importNow(at: at(2026, 10, 1, 21, 30))
        #expect(stores.collection.snapshot.counters[.nightsTracked] == nil)
        // Only the night before the install night is even read.
        let read = try #require(reader.reads.first)
        #expect(read.start == at(2026, 9, 30, 18))
    }

    @Test("A deleted sample: the night is rebuilt without it before it settles")
    func deletions() async throws {
        let (stores, importer, reader, _) = try await member()
        reader.add([
            SleepSample(id: "oct1-early", start: at(2026, 10, 1, 23), end: at(2026, 10, 1, 23, 40), stage: .asleepCore, origin: watch),
            SleepSample(id: "oct1-awake", start: at(2026, 10, 1, 23, 40), end: at(2026, 10, 2, 0, 20), stage: .awake, origin: watch),
            SleepSample(id: "oct1-main", start: at(2026, 10, 2, 0, 20), end: at(2026, 10, 2, 7), stage: .asleepCore, origin: watch),
        ])
        await importer.importNow(at: at(2026, 10, 2, 5))   // before the night settles
        #expect(importer.lastNight?.onset == at(2026, 10, 1, 23))

        reader.delete(["oct1-early", "oct1-awake"])
        await importer.importNow(at: at(2026, 10, 2, 5, 30))
        #expect(importer.lastNight?.onset == at(2026, 10, 2, 0, 20))

        // It settles as rebuilt: tracked, but asleep after 23:30, so not on time.
        await importer.importNow(at: at(2026, 10, 2, 7, 30))
        #expect(stores.collection.snapshot.counters[.nightsTracked] == 1)
        #expect(stores.collection.snapshot.counters[.onTimeBedtimes] == nil)
    }

    @Test("Late Watch data upgrades a night settled from iPhone's estimate")
    func lateWatchData() async throws {
        let (stores, importer, reader, _) = try await member()
        reader.add([SleepSample(id: "oct1-bed", start: at(2026, 10, 1, 23, 10), end: at(2026, 10, 2, 7, 5), stage: .inBed,
                                origin: iPhone)])
        await importer.importNow(at: at(2026, 10, 2, 7, 30))
        #expect(importer.lastNight?.source == .iPhoneInBed)
        #expect(stores.collection.snapshot.counters[.nightsTracked] == 1)
        #expect(stores.collection.snapshot.counters[.onTimeBedtimes] == 1)
        #expect(stores.collection.snapshot.counters[.fullNights] == nil)
        #expect(stores.collection.availability(of: .fullNights) == .needsSleepTracker)

        // The Watch syncs a day later: the same night becomes a full night, and nothing counts twice.
        reader.add(watchNight(at(2026, 10, 1, 23, 15), at(2026, 10, 2, 7), tag: "oct1"))
        await importer.importNow(at: at(2026, 10, 3, 8))
        #expect(stores.collection.snapshot.counters[.fullNights] == 1)
        #expect(stores.collection.snapshot.counters[.nightsTracked] == 1)
        #expect(stores.collection.snapshot.counters[.onTimeBedtimes] == 1)
        #expect(stores.collection.availability(of: .fullNights) == .available)
    }

    @Test("A locked iPhone keeps everything and reads again on unlock; other errors change nothing")
    func lockedAndErrors() async throws {
        let (stores, importer, reader, folder) = try await member()
        reader.add(watchNight(at(2026, 10, 1, 23), at(2026, 10, 2, 7), tag: "oct1"))
        await importer.importNow(at: at(2026, 10, 2, 7, 30))
        let cacheURL = folder.appending(path: "\(HealthSleepImporter.folder)/\(HealthSleepImporter.file)")
        let before = try Data(contentsOf: cacheURL)

        reader.failure = .locked
        reader.add(watchNight(at(2026, 10, 2, 23), at(2026, 10, 3, 7), tag: "oct2"))
        #expect(await importer.importNow(at: at(2026, 10, 3, 7, 30)).isEmpty)
        #expect(importer.isWaitingForUnlock)
        #expect(try Data(contentsOf: cacheURL) == before)
        #expect(importer.lastNight?.night == LocalDay(year: 2026, month: 10, day: 1))
        // Nothing settled while Apple Health couldn't be read.
        #expect(stores.collection.snapshot.counters[.nightsTracked] == 1)

        reader.failure = nil
        await importer.retryIfWaiting(at: at(2026, 10, 3, 7, 40))
        #expect(!importer.isWaitingForUnlock)
        #expect(stores.collection.snapshot.counters[.nightsTracked] == 2)

        reader.failure = .failed("Something else")
        #expect(await importer.importNow(at: at(2026, 10, 3, 9)).isEmpty)
        #expect(!importer.isWaitingForUnlock)
        #expect(importer.lastNight?.night == LocalDay(year: 2026, month: 10, day: 2))
        // Retrying only follows a lock.
        let reads = reader.reads.count
        await importer.retryIfWaiting(at: at(2026, 10, 3, 9, 5))
        #expect(reader.reads.count == reads)
    }

    @Test("The window moves forward: old samples are dropped and reading starts 16 nights back")
    func boundedWindow() async throws {
        let (_, importer, reader, folder) = try await member()
        reader.add(watchNight(at(2026, 10, 1, 23), at(2026, 10, 2, 7), tag: "oct1"))
        await importer.importNow(at: at(2026, 10, 2, 7, 30))
        reader.add(watchNight(at(2026, 10, 30, 23), at(2026, 10, 31, 7), tag: "oct30"))
        await importer.importNow(at: at(2026, 10, 31, 7, 30))

        #expect(reader.reads.last?.start == at(2026, 10, 15, 18))
        let saved = try #require(JSONStorage<SleepImportCache>(
            .file(folder.appending(path: "\(HealthSleepImporter.folder)/\(HealthSleepImporter.file)"))
        ).load())
        #expect(saved.samples.map(\.id) == ["oct30-asleep"])
        #expect(saved.windowStart == at(2026, 10, 15, 18))
    }

    @Test("Connected two nights without sleep: the hint shows, until the first sample arrives")
    func noSleepHint() async throws {
        let (_, importer, reader, _) = try await member()
        await importer.importNow(at: at(2026, 10, 2, 13))
        #expect(!importer.showsNoSleepHint(at: at(2026, 10, 2, 13)))
        #expect(importer.showsNoSleepHint(at: at(2026, 10, 3, 13)))
        #expect(!importer.hasReceivedSleep)

        // A sample typed in by hand isn't sleep that counts.
        reader.add([SleepSample(id: "typed", start: at(2026, 10, 2, 23), end: at(2026, 10, 3, 7), stage: .asleepCore,
                                origin: iPhone, wasUserEntered: true)])
        await importer.importNow(at: at(2026, 10, 3, 13))
        #expect(importer.showsNoSleepHint(at: at(2026, 10, 3, 13)))

        reader.add(watchNight(at(2026, 10, 3, 23), at(2026, 10, 4, 7), tag: "oct3"))
        await importer.importNow(at: at(2026, 10, 4, 8))
        #expect(importer.hasReceivedSleep)
        #expect(!importer.showsNoSleepHint(at: at(2026, 10, 5, 13)))

        let disconnected = try await member(connected: false)
        #expect(!disconnected.importer.showsNoSleepHint(at: at(2026, 10, 9)))
    }

    @Test("The observer imports new sleep while the app runs; background delivery only when the build may")
    func observing() async throws {
        let (stores, importer, reader, _) = try await member()
        importer.startObserving(clock: .fixed(at(2026, 10, 2, 7, 30)))
        importer.startObserving(clock: .fixed(at(2026, 10, 2, 7, 30)))
        #expect(reader.backgroundDeliveryRequests == 0)
        reader.add(watchNight(at(2026, 10, 1, 23), at(2026, 10, 2, 7), tag: "oct1"))
        let onChange = try #require(reader.onChange)
        await onChange()
        #expect(stores.collection.snapshot.counters[.nightsTracked] == 1)
        importer.stopObserving()
        #expect(reader.onChange == nil)

        let paid = try await member()
        paid.importer.usesBackgroundDelivery = true
        paid.importer.startObserving(clock: .live)
        await Task.yield()
        for _ in 0..<10 where paid.reader.backgroundDeliveryRequests == 0 { await Task.yield() }
        #expect(paid.reader.backgroundDeliveryRequests == 1)

        let notConnected = try await member(connected: false)
        notConnected.importer.startObserving(clock: .live)
        #expect(notConnected.reader.onChange == nil)
    }

    @Test("A cache from another version starts afresh, keeping when sleep first arrived")
    func cacheVersions() throws {
        let decoded = try JSONDecoder().decode(
            SleepImportCache.self,
            from: Data(#"{"version": 99, "samples": [], "firstSleepAt": 800000000, "anchor": "AA=="}"#.utf8)
        )
        #expect(decoded.samples.isEmpty && decoded.anchor == nil)
        #expect(decoded.firstSleepAt == Date(timeIntervalSinceReferenceDate: 800_000_000))
        let cache = SleepImportCache(anchor: Data([1]), windowStart: at(2026, 10, 1), samples: watchNight(at(2026, 10, 1, 23), at(2026, 10, 2, 7), tag: "x"))
        #expect(try JSONDecoder().decode(SleepImportCache.self, from: JSONEncoder().encode(cache)) == cache)
    }
}

@Suite("HealthKit samples to plain values")
struct HealthKitMappingTests {
    @Test("Stages, origin, typed-in flag and time zone come across; unknown values are dropped")
    func mapping() throws {
        let type = HKCategoryType(.sleepAnalysis)
        let device = HKDevice(name: "Apple Watch", manufacturer: "Apple Inc.", model: "Watch", hardwareVersion: "Watch7,1",
                              firmwareVersion: nil, softwareVersion: nil, localIdentifier: nil, udiDeviceIdentifier: nil)
        let sample = HKCategorySample(
            type: type, value: HKCategoryValueSleepAnalysis.asleepDeep.rawValue, start: at(2026, 10, 1, 23), end: at(2026, 10, 2, 1),
            device: device, metadata: [HKMetadataKeyTimeZone: "Europe/Paris", HKMetadataKeyWasUserEntered: true]
        )
        let mapped = try #require(HealthKitSleepReader.sample(from: sample, zone: "UTC"))
        #expect(mapped.stage == .asleepDeep)
        #expect(mapped.id == sample.uuid.uuidString)
        #expect(mapped.start == at(2026, 10, 1, 23) && mapped.end == at(2026, 10, 2, 1))
        #expect(mapped.origin.deviceModel == "Watch")
        #expect(mapped.origin.deviceManufacturer == "Apple Inc.")
        #expect(mapped.wasUserEntered)
        #expect(mapped.timeZoneIdentifier == "Europe/Paris")

        // Without a zone of its own, the sample takes the one in force when it was read.
        let plain = HKCategorySample(type: type, value: HKCategoryValueSleepAnalysis.inBed.rawValue,
                                     start: at(2026, 10, 1, 23), end: at(2026, 10, 2, 7))
        let mappedPlain = try #require(HealthKitSleepReader.sample(from: plain, zone: "Asia/Kolkata"))
        #expect(mappedPlain.timeZoneIdentifier == "Asia/Kolkata")
        #expect(!mappedPlain.wasUserEntered)
        #expect(mappedPlain.stage == .inBed)

        let stages = (0...5).compactMap(HealthKitSleepReader.stage)
        #expect(stages == [.inBed, .asleepUnspecified, .awake, .asleepCore, .asleepDeep, .asleepREM])
        #expect(HealthKitSleepReader.stage(42) == nil)
    }

    @Test("A locked iPhone's error is told apart from the rest")
    func errors() {
        #expect(HealthKitSleepReader.readError(HKError(.errorDatabaseInaccessible)) == .locked)
        #expect(HealthKitSleepReader.readError(HKError(.errorAuthorizationNotDetermined)) == .notAuthorized)
        #expect(HealthKitSleepReader.readError(HKError(.errorHealthDataUnavailable)) == .healthDataUnavailable)
        if case .failed = HealthKitSleepReader.readError(CocoaError(.fileReadUnknown)) {} else {
            Issue.record("Any other error is a plain failure")
        }
    }
}

@Suite("DEBUG Apple Health seeder")
struct HealthSleepSeederTests {
    private let schedule = SleepSchedule.standard

    @Test("Launch arguments: nights, source and store")
    func options() {
        #expect(HealthSleepSeeder.Options(arguments: []) == nil)
        #expect(HealthSleepSeeder.Options(arguments: ["-MapleDemoSeedHealth", "0"]) == nil)
        #expect(HealthSleepSeeder.Options(arguments: ["-MapleDemoSeedHealth", "10"])
            == HealthSleepSeeder.Options(nights: 10, source: .watch, store: .health))
        #expect(HealthSleepSeeder.Options(arguments: ["-MapleDemoSeedHealth", "5", "-MapleDemoSeedSource", "iphone",
                                                      "-MapleDemoSeedStore", "memory"])
            == HealthSleepSeeder.Options(nights: 5, source: .iphone, store: .memory))
        #expect(HealthSleepSeeder.Options(arguments: ["-MapleDemoSeedHealth", "500"])?.nights == 60)
        // Seed arguments never make a launch a Core demo.
        #expect(!DemoLaunchOptions(arguments: ["-MapleDemoSeedHealth", "10", "-MapleDemoSeedStore", "memory"]).isActive)
    }

    @Test("Seeded Watch nights read as a Watch, vary around the schedule, and end before now")
    func watchNights() {
        let now = at(2026, 10, 11, 8)
        let samples = HealthSleepSeeder.samples(nights: 10, source: .watch, schedule: schedule, now: now, calendar: utc)
        let nights = SleepNightBuilder(calendar: utc).nights(from: samples)
        #expect(nights.count == 10)
        #expect(nights.last?.night == LocalDay(year: 2026, month: 10, day: 10))
        #expect(nights.allSatisfy { $0.source == .watchOrTracker && $0.isMainEpisode })
        #expect(samples.allSatisfy { $0.end <= now })
        // Realistic: some late, some short, and most on time.
        let bedtimeOffsets = nights.map { $0.onset.timeIntervalSince(NightLedger.date(schedule.bedtime, on: $0.night, calendar: utc)) }
        #expect(bedtimeOffsets.contains { $0 > 30 * 60 })
        #expect(bedtimeOffsets.filter { abs($0) <= 30 * 60 }.count >= 5)
        #expect(nights.contains { ($0.asleepMinutes ?? 0) < 6.5 * 60 })
        #expect(nights.allSatisfy { ($0.asleepMinutes ?? 0) <= $0.span / 60 })
        // The same nights every time.
        #expect(HealthSleepSeeder.samples(nights: 10, source: .watch, schedule: schedule, now: now, calendar: utc) == samples)
    }

    @Test("Seeded iPhone and other-app nights take their own rungs; nothing starts before the maple was planted")
    func otherSources() throws {
        let now = at(2026, 10, 11, 8)
        let iPhoneNights = SleepNightBuilder(calendar: utc).nights(
            from: HealthSleepSeeder.samples(nights: 3, source: .iphone, schedule: schedule, now: now, calendar: utc)
        )
        #expect(iPhoneNights.count == 3 && iPhoneNights.allSatisfy { $0.source == .iPhoneInBed })
        let appNights = SleepNightBuilder(calendar: utc).nights(
            from: HealthSleepSeeder.samples(nights: 3, source: .otherApp, schedule: schedule, now: now, calendar: utc)
        )
        #expect(appNights.count == 3 && appNights.allSatisfy { $0.source == .otherApp })

        let planted = at(2026, 10, 10, 23, 43)
        let samples = HealthSleepSeeder.samples(nights: 3, source: .watch, schedule: schedule, now: now, calendar: utc,
                                                notBefore: planted)
        let lastNight = try #require(SleepNightBuilder(calendar: utc).nights(from: samples).last)
        #expect(lastNight.onset > planted)
        #expect(lastNight.isMainEpisode)
    }
}
