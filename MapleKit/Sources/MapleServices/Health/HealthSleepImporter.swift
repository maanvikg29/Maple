import Foundation
import MapleCore
import Observation
import os

/// What the importer keeps between runs: Apple Health's sleep samples for the window it reads, and the anchor to
/// read on from. Health data, so it is **local only**: a file in `LocalHealth/` next to the other stores, protected
/// until first unlock, excluded from backups and never synced (App Store guideline 5.1.3(ii)).
nonisolated public struct SleepImportCache: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    /// The `HKQueryAnchor` of the last read, archived.
    public var anchor: Data?
    /// The start of the window the samples were read for.
    public var windowStart: Date?
    /// Every sample in the window, oldest first.
    public var samples: [SleepSample]
    /// When a sleep sample that can count first arrived; nil until then (Privacy's and Home's no-sleep hint).
    public var firstSleepAt: Date?
    public var lastImportAt: Date?

    public init(
        anchor: Data? = nil, windowStart: Date? = nil, samples: [SleepSample] = [], firstSleepAt: Date? = nil,
        lastImportAt: Date? = nil
    ) {
        version = Self.currentVersion
        self.anchor = anchor
        self.windowStart = windowStart
        self.samples = samples
        self.firstSleepAt = firstSleepAt
        self.lastImportAt = lastImportAt
    }

    private enum CodingKeys: String, CodingKey {
        case version, anchor, windowStart, samples, firstSleepAt, lastImportAt
    }

    /// Tolerant: a cache from another version starts the window afresh (HealthKit still has every sample), keeping
    /// only when sleep first arrived.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = (try? c.decodeIfPresent(Int.self, forKey: .version)) ?? 0
        let firstSleepAt = (try? c.decodeIfPresent(Date.self, forKey: .firstSleepAt)) ?? nil
        let lastImportAt = (try? c.decodeIfPresent(Date.self, forKey: .lastImportAt)) ?? nil
        guard version == Self.currentVersion,
              let samples = try? c.decodeIfPresent([SleepSample].self, forKey: .samples) else {
            self.init(firstSleepAt: firstSleepAt, lastImportAt: lastImportAt)
            return
        }
        self.init(
            anchor: (try? c.decodeIfPresent(Data.self, forKey: .anchor)) ?? nil,
            windowStart: (try? c.decodeIfPresent(Date.self, forKey: .windowStart)) ?? nil,
            samples: samples, firstSleepAt: firstSleepAt, lastImportAt: lastImportAt
        )
    }
}

/// M1's Apple Health importer: reads sleep analysis, rebuilds the nights with `SleepNightBuilder` and hands them to
/// `CollectionStore.recordSleep(_:at:)`, the sleep leaves' only source (spec D9).
///
/// ```swift
/// @Environment(HealthSleepImporter.self) private var sleep
///
/// await sleep.importNow(at: clock.now())                   // MapleApp: every foreground, and after Apple's prompt
/// collection.nowState(at: now, lastNight: sleep.lastNightSleep(at: now))   // Home's morning numeral
/// sleep.showsNoSleepHint(at: now)                          // connected, but nothing from Apple Health in 2 nights
/// ```
///
/// - Only while Apple Health is connected and the maple is planted; otherwise it does nothing.
/// - Reads a bounded window (`SleepImportWindow`): never before the night before the install night (no backfill),
///   at most the last 16 nights. Each run reads only what changed since the last (an anchored query), drops deleted
///   samples, rebuilds every night in the window and sends them all; the ledger takes repeats idempotently, settles
///   nights and upgrades late Watch data for 72 hours.
/// - The samples and the anchor are cached locally (`SleepImportCache`). A locked iPhone (protected health data)
///   keeps everything and waits for the next foreground or unlock; no error ever clears the cache.
/// - While the app runs an `HKObserverQuery` imports new sleep as it arrives; background delivery is turned on only
///   in builds that carry its entitlement (the paid tier: docs/entitlements.md).
@Observable
public final class HealthSleepImporter {
    nonisolated public static let folder = "LocalHealth"
    nonisolated public static let file = "sleep-import.json"

    /// The end of the last import that read Apple Health.
    public private(set) var lastImportAt: Date?
    /// The most recent night Apple Health has sleep for (settled or still provisional), as the importer built it.
    public private(set) var lastNight: SleepNightObservation?
    /// A sleep sample that can count has arrived since Apple Health was connected.
    public private(set) var hasReceivedSleep: Bool
    public private(set) var isImporting = false
    /// The last read was refused because the iPhone was locked; the next foreground or unlock reads again.
    public private(set) var isWaitingForUnlock = false

    /// False for DEBUG demo collections, which are never fed nights.
    @ObservationIgnored public var isEnabled = true
    /// Ask HealthKit to wake the app for new sleep. Only builds with the background-delivery entitlement set it.
    @ObservationIgnored public var usesBackgroundDelivery = false

    @ObservationIgnored private var cache: SleepImportCache
    @ObservationIgnored private var cacheIsAvailable: Bool
    /// Every night in the window as built, oldest first. Observed, so Home redraws its numeral when it changes.
    private var nights: [SleepNightObservation] = []
    @ObservationIgnored private var rerunRequested = false
    @ObservationIgnored private var isObserving = false
    @ObservationIgnored private let storage: JSONStorage<SleepImportCache>
    @ObservationIgnored private let reader: any SleepSampleReading
    @ObservationIgnored private let health: HealthPermission
    @ObservationIgnored private let collection: CollectionStore
    @ObservationIgnored private let resolver = SleepSourceResolver()
    private static var logger: Logger { Logger(subsystem: "com.maanvikgupta.maple", category: "health") }

    public init(
        reader: any SleepSampleReading, storage: JSONStorage<SleepImportCache>, health: HealthPermission,
        collection: CollectionStore
    ) {
        self.reader = reader
        self.storage = storage
        self.health = health
        self.collection = collection
        switch storage.read() {
        case .value(let saved):
            cache = saved
            cacheIsAvailable = true
        case .absent:
            cache = SleepImportCache()
            cacheIsAvailable = true
        case .unavailable:
            cache = SleepImportCache()
            cacheIsAvailable = false
        }
        hasReceivedSleep = cache.firstSleepAt != nil
        lastImportAt = cache.lastImportAt
        rebuildNights()
    }

    // MARK: Reading

    /// Home's last night (spec §3.4): the night `date` falls in, when Apple Health has sleep for it.
    public func lastNightSleep(at date: Date) -> LastNightSleep? {
        SleepImportWindow.lastNight(in: nights, at: date, calendar: collection.context.calendar)
    }

    /// Connected for 2 nights or more without a single sleep sample: Privacy and Home say how to get some.
    public func showsNoSleepHint(at date: Date) -> Bool {
        guard isEnabled, health.isConnected else { return false }
        return SleepDataHint.isDue(connectedAt: health.connection.promptCompletedAt, hasReceivedSleep: hasReceivedSleep,
                                   now: date, calendar: collection.context.calendar)
    }

    // MARK: Importing

    /// Reads what changed in Apple Health's sleep, rebuilds the window's nights and records them. Does nothing while
    /// Apple Health isn't connected, the maple isn't planted, or the device has no Apple Health. A call while one is
    /// running makes that one read again when it finishes.
    /// - Returns: The leaves the nights unlocked.
    @discardableResult
    public func importNow(at date: Date) async -> [LeafUnlock] {
        guard isEnabled, health.isConnected, reader.isHealthDataAvailable, collection.firstLeaf != nil else { return [] }
        guard !isImporting else {
            rerunRequested = true
            return []
        }
        isImporting = true
        defer { isImporting = false }
        var unlocked: [LeafUnlock] = []
        repeat {
            rerunRequested = false
            unlocked += await importOnce(at: date)
        } while rerunRequested
        return unlocked
    }

    /// Reads again if the last read waited for the iPhone to unlock (call it when protected data becomes available).
    public func retryIfWaiting(at date: Date) async {
        guard isWaitingForUnlock || !cacheIsAvailable else { return }
        await importNow(at: date)
    }

    /// Imports new sleep as Apple Health records it while the app runs, and (when this build may) asks HealthKit to
    /// wake the app for it in the background. Safe to call on every foreground.
    public func startObserving(clock: MapleClock) {
        guard isEnabled, !isObserving, health.isConnected, reader.isHealthDataAvailable else { return }
        isObserving = true
        reader.startObserving { [weak self] in
            await self?.importNow(at: clock.now())
        }
        guard usesBackgroundDelivery else { return }
        Task {
            do {
                try await reader.enableBackgroundDelivery()
            } catch {
                Self.logger.error("Couldn't turn on background delivery: \(String(describing: error), privacy: .public)")
            }
        }
    }

    public func stopObserving() {
        guard isObserving else { return }
        reader.stopObserving()
        isObserving = false
    }

    // MARK: Private

    private func importOnce(at date: Date) async -> [LeafUnlock] {
        guard let setup = collection.firstLeaf?.date else { return [] }
        if !cacheIsAvailable, !reloadCache() {
            // The cache can't be read yet (before the first unlock): nothing is read or written until it can.
            isWaitingForUnlock = true
            return []
        }
        let calendar = collection.context.calendar
        let installNight = NightLedger.firstNight(setUpAt: setup, calendar: calendar)
        let start = SleepImportWindow.start(installNight: installNight, now: date, calendar: calendar)

        var working = cache
        if (working.windowStart ?? .distantFuture) > start {
            // The window reaches further back than what was read: read it whole.
            working.anchor = nil
            working.samples = []
        }
        let changes: SleepSampleChanges
        do {
            changes = try await reader.changes(since: working.anchor, from: start, zone: calendar.timeZone.identifier)
        } catch .locked {
            isWaitingForUnlock = true
            return []
        } catch {
            Self.logger.error("Couldn't read sleep from Apple Health: \(String(describing: error), privacy: .public)")
            return []
        }
        isWaitingForUnlock = false

        var byID = Dictionary(working.samples.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for id in changes.deletedIDs { byID[id] = nil }
        // A sample already held keeps the zone it was first read in.
        for sample in changes.added where byID[sample.id] == nil { byID[sample.id] = sample }
        working.samples = byID.values.filter { $0.end > start }.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
        working.anchor = changes.anchor ?? working.anchor
        working.windowStart = start
        working.lastImportAt = date
        if working.firstSleepAt == nil, working.samples.contains(where: { resolver.source(of: $0) != nil }) {
            working.firstSleepAt = date
        }
        cache = working
        storage.save(working)

        rebuildNights()
        lastImportAt = date
        hasReceivedSleep = working.firstSleepAt != nil
        return collection.recordSleep(nights, at: date)
    }

    private func rebuildNights() {
        nights = SleepNightBuilder(calendar: collection.context.calendar).nights(from: cache.samples)
        lastNight = nights.last
    }

    @discardableResult
    private func reloadCache() -> Bool {
        switch storage.read() {
        case .value(let saved): cache = saved
        case .absent: cache = SleepImportCache()
        case .unavailable: return false
        }
        cacheIsAvailable = true
        hasReceivedSleep = cache.firstSleepAt != nil
        rebuildNights()
        return true
    }

    #if DEBUG
    /// DEBUG `-MapleDemoSeedStore memory`: `samples` as if just read from Apple Health (an in-memory cache only),
    /// recorded at once, so a demo launch shows them from its first frame without Apple's sheet. Later imports read
    /// HealthKit on top of them and keep them.
    @discardableResult
    public func seedInMemory(_ samples: [SleepSample], at date: Date) -> [LeafUnlock] {
        guard isEnabled, health.isConnected, let setup = collection.firstLeaf?.date, !samples.isEmpty else { return [] }
        let calendar = collection.context.calendar
        let start = SleepImportWindow.start(
            installNight: NightLedger.firstNight(setUpAt: setup, calendar: calendar), now: date, calendar: calendar
        )
        var seeded = cache
        seeded.samples = samples.filter { $0.end > start }.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
        seeded.windowStart = start
        seeded.lastImportAt = date
        seeded.firstSleepAt = seeded.firstSleepAt ?? date
        cache = seeded
        storage.save(seeded)
        rebuildNights()
        lastImportAt = date
        hasReceivedSleep = true
        return collection.recordSleep(nights, at: date)
    }
    #endif

    // MARK: Launch

    /// The local-only folder for health data: next to the other stores, excluded from backups.
    nonisolated public static func directory(in container: URL = MapleContainer.directory()) -> URL {
        let folder = container.appending(path: Self.folder, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = folder
        try? url.setResourceValues(values)
        return folder
    }

    /// The member's importer: Apple Health through HealthKit, the cache in `LocalHealth/` beside their stores.
    public static func live(
        container: URL = MapleContainer.directory(), health: HealthPermission, collection: CollectionStore,
        reader: any SleepSampleReading = HealthKitSleepReader()
    ) -> HealthSleepImporter {
        let file = directory(in: container).appending(path: Self.file)
        return HealthSleepImporter(reader: reader, storage: JSONStorage(.file(file)), health: health, collection: collection)
    }

    /// What this launch should use. Release builds always read Apple Health into the member's collection. DEBUG demo
    /// launches keep the cache in memory (an in-memory copy of the member's own); a demo collection
    /// (`-MapleDemoSpecies`/`Days`/`Waiting`, `-MapleDemoFresh`) is never fed nights.
    public static func launch(
        stores: MapleStores, container: URL = MapleContainer.directory(), backgroundDelivery: Bool = false
    ) -> HealthSleepImporter {
        #if DEBUG
        let options = DemoLaunchOptions.current
        if options.isActive {
            let saved = JSONStorage<SleepImportCache>(.file(container.appending(path: "\(folder)/\(file)"))).load()
            let importer = HealthSleepImporter(
                reader: HealthKitSleepReader(), storage: JSONStorage(.memory, initial: saved), health: stores.health,
                collection: stores.collection
            )
            importer.isEnabled = !options.usesDemoCollection && !options.fresh
            if importer.isEnabled, let seed = HealthSleepSeeder.Options.current, seed.store == .memory,
               let planted = stores.collection.firstLeaf?.date {
                // -MapleDemoSeedStore memory: synthetic nights, recorded before the first frame.
                let now = stores.clock.now()
                let samples = HealthSleepSeeder.samples(
                    nights: seed.nights, source: seed.source, schedule: stores.collection.schedule, now: now,
                    calendar: stores.collection.context.calendar, notBefore: planted
                )
                importer.seedInMemory(samples, at: now)
            }
            return importer
        }
        #endif
        let importer = live(container: container, health: stores.health, collection: stores.collection)
        importer.usesBackgroundDelivery = backgroundDelivery
        return importer
    }
}
