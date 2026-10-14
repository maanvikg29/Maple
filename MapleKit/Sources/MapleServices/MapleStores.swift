import Foundation
import MapleCore

/// The app's stores, created once at launch and injected into the environment by `MapleApp`.
///
/// Release builds always use `live()`: the member's real files and the unconfigured rarity provider. DEBUG builds
/// launched with Core demo arguments (docs/debug-launch-arguments.md) get in-memory stores instead.
public struct MapleStores {
    public let collection: CollectionStore
    public let schedule: ScheduleStore
    public let shares: LeafShareStore
    /// Apple Health: the one permission this build can grant, and only once the member has been through Apple's
    /// prompt. DEBUG demos are granted what their launch arguments say.
    public let health: HealthPermission
    /// "Now" for every screen: live, or frozen inside a phase by `-MapleDemoPhase`.
    public let clock: MapleClock
    /// `-MapleDemoSeason`; nil uses the real season.
    public let seasonOverride: Season?
    /// The member's real files (false for DEBUG demos, which live in memory).
    public var isLive = false
    /// Reads Apple Health's nights into the collection: live stores only, so DEBUG demos are never fed nights.
    public var sleep: SleepImporter?

    public static let collectionFile = "collection.json"
    public static let scheduleFile = "schedule.json"
    public static let sharesFile = "leaf-shares.json"

    /// What this launch should use: the live stores, or in DEBUG the demo the launch arguments ask for.
    public static func launch() -> MapleStores {
        #if DEBUG
        let options = DemoLaunchOptions.current
        if options.isActive { return make(options) }
        #endif
        return live()
    }

    /// The member's own collection, schedule, rarity cache and Apple Health record, saved in `directory`, with the
    /// importer that reads their nights from Apple Health.
    ///
    /// Permissions are real: Apple Health is granted only once the member has been through Apple's prompt
    /// (`HealthPermission`), and nothing else can be granted in this build.
    ///
    /// The calendar is the autoupdating one, so a new time zone moves phases and days with the member; the app
    /// calls `collection.systemTimeChanged()` on a time-zone change to refresh what screens already drew.
    public static func live(
        directory: URL = MapleContainer.directory(), calendar: Calendar = .autoupdatingCurrent, now: Date = .now,
        healthAuthorizer: any HealthAuthorizing = HealthKitAuthorizer(),
        sleepReader: any SleepSampleReading = HealthKitSleepReader()
    ) -> MapleStores {
        let health = HealthPermission.live(directory: directory, authorizer: healthAuthorizer)
        let context = CollectionContext(permissions: health.permissions, calendar: calendar, hemisphere: .current)
        let collection = CollectionStore(
            storage: JSONStorage(.file(directory.appending(path: collectionFile))), context: context, now: now
        )
        collection.followsSystemCalendar = true
        let schedule = ScheduleStore(storage: JSONStorage(.file(directory.appending(path: scheduleFile))), collection: collection)
        let shares = LeafShareStore(
            provider: UnconfiguredLeafShareProvider(), storage: JSONStorage(.file(directory.appending(path: sharesFile))),
            features: context.features, clock: .live
        )
        var stores = MapleStores(collection: collection, schedule: schedule, shares: shares, health: health, clock: .live,
                                 seasonOverride: nil)
        stores.isLive = true
        stores.sleep = SleepImporter(collection: collection, health: health, reader: sleepReader)
        return stores
    }

    /// Whether the collection and schedule files could both be read (see `CollectionStore.isAvailable`).
    public var isAvailable: Bool { collection.isAvailable && schedule.isAvailable }

    /// Reads the collection, schedule and Apple Health record again if launch couldn't (before the first unlock
    /// after a restart).
    /// - Returns: Whether the collection or schedule changed from its placeholder, so the first-run step must be
    ///   decided again.
    @discardableResult
    public func reloadIfUnavailable() -> Bool {
        let collectionReloaded = collection.reloadIfUnavailable()
        let scheduleReloaded = schedule.reloadIfUnavailable()
        let healthReloaded = health.reloadIfUnavailable()
        if collectionReloaded, !scheduleReloaded {
            // The collection's placeholder had the standard schedule; give it the member's again.
            collection.schedule = schedule.schedule
        }
        if collectionReloaded || healthReloaded { health.apply(to: collection) }
        return collectionReloaded || scheduleReloaded
    }

    #if DEBUG
    /// DEBUG launches with demo arguments. Every store is in memory, so the real files are never written:
    /// a demo collection (`-MapleDemoSpecies`/`Days`/`Waiting`), an empty first run (`-MapleDemoFresh`), or an
    /// in-memory copy of the member's own collection when only the phase, season or rarity is overridden.
    ///
    /// Permissions: `-MapleDemoPermissions` when given; otherwise demo collections are granted Apple Health and a
    /// sleep tracker (`DemoData.defaultPermissions`), so their leaves show earned progress; a fresh first run gets
    /// nothing; and a copy of the member's own collection gets their own Apple Health record.
    public static func make(
        _ options: DemoLaunchOptions, directory: URL = MapleContainer.directory(), calendar: Calendar = .current,
        now: Date = .now
    ) -> MapleStores {
        let usesDemo = options.usesDemoCollection
        let savedHealth = JSONStorage<HealthConnection>(.file(directory.appending(path: HealthPermission.file))).load()
        let permissions = options.permissions
            ?? (options.fresh ? [] : usesDemo ? DemoData.defaultPermissions : (savedHealth ?? HealthConnection()).permissions)
        let connection = permissions.contains(.appleHealth)
            ? HealthConnection(promptCompletedAt: savedHealth?.promptCompletedAt ?? now) : HealthConnection()
        let health = HealthPermission(storage: JSONStorage(.memory, initial: connection))
        let context = CollectionContext(
            permissions: permissions, calendar: calendar, hemisphere: .current, seasonOverride: options.season
        )
        let realCollection = JSONStorage<CollectionSnapshot>(.file(directory.appending(path: collectionFile)))
        let realSchedule = JSONStorage<SavedSchedule>(.file(directory.appending(path: scheduleFile)))

        let snapshot: CollectionSnapshot?
        var saved: SavedSchedule?
        if options.fresh {
            snapshot = .empty(profileID: DemoData.profileID, createdAt: now)
            saved = nil
        } else if usesDemo {
            let demo = DemoData.snapshot(
                species: options.species ?? DemoData.defaultSpecies, tendedDays: options.days ?? DemoData.defaultDays,
                waiting: options.waiting ?? 0, now: now, calendar: calendar, hemisphere: context.hemisphere,
                permissions: permissions, features: context.features
            )
            snapshot = demo
            saved = demo.hasPlantedMaple ? SavedSchedule(schedule: .standard, savedAt: demo.createdAt) : nil
        } else {
            snapshot = realCollection.load()
            saved = realSchedule.load()
        }
        if let custom = options.schedule, !options.fresh {
            saved = SavedSchedule(schedule: custom, savedAt: saved?.savedAt ?? now)
        }

        let collection = CollectionStore(storage: JSONStorage(.memory, initial: snapshot), context: context, now: now)
        let schedule = ScheduleStore(storage: JSONStorage(.memory, initial: saved), collection: collection)
        if options.rarity { collection.setRarityConsent(true) }

        let clock: MapleClock = options.phase.map { phase in
            .fixed(PhaseWindows(schedule: schedule.schedule).sampleDate(in: phase, onDayOf: now, calendar: calendar))
        } ?? .live
        let provider: any LeafShareProvider = options.rarity ? PreviewLeafShareProvider() : UnconfiguredLeafShareProvider()
        let shares = LeafShareStore(provider: provider, storage: JSONStorage(.memory), features: context.features, clock: clock)
        return MapleStores(collection: collection, schedule: schedule, shares: shares, health: health, clock: clock,
                           seasonOverride: options.season)
    }
    #endif
}
