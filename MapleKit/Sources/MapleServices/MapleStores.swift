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
    /// "Now" for every screen: live, or frozen inside a phase by `-MapleDemoPhase`.
    public let clock: MapleClock
    /// `-MapleDemoSeason`; nil uses the real season.
    public let seasonOverride: Season?
    /// The member's real files (false for DEBUG demos, which live in memory). Only these record nights.
    public var isLive = false

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

    /// The member's own collection, schedule and rarity cache, saved in `directory`.
    ///
    /// The calendar is the autoupdating one, so a new time zone moves phases and days with the member; the app
    /// calls `collection.systemTimeChanged()` on a time-zone change to refresh what screens already drew.
    public static func live(
        directory: URL = MapleContainer.directory(), calendar: Calendar = .autoupdatingCurrent, now: Date = .now
    ) -> MapleStores {
        let context = CollectionContext(calendar: calendar, hemisphere: .current)
        let collection = CollectionStore(
            storage: JSONStorage(.file(directory.appending(path: collectionFile))), context: context, now: now
        )
        collection.followsSystemCalendar = true
        let schedule = ScheduleStore(storage: JSONStorage(.file(directory.appending(path: scheduleFile))), collection: collection)
        let shares = LeafShareStore(
            provider: UnconfiguredLeafShareProvider(), storage: JSONStorage(.file(directory.appending(path: sharesFile))),
            features: context.features, clock: .live
        )
        var stores = MapleStores(collection: collection, schedule: schedule, shares: shares, clock: .live, seasonOverride: nil)
        stores.isLive = true
        return stores
    }

    /// Whether the collection and schedule files could both be read (see `CollectionStore.isAvailable`).
    public var isAvailable: Bool { collection.isAvailable && schedule.isAvailable }

    /// Reads the collection and schedule again if launch couldn't (before the first unlock after a restart).
    /// - Returns: Whether either one changed from its placeholder, so the first-run step must be decided again.
    @discardableResult
    public func reloadIfUnavailable() -> Bool {
        let collectionReloaded = collection.reloadIfUnavailable()
        let scheduleReloaded = schedule.reloadIfUnavailable()
        if collectionReloaded, !scheduleReloaded {
            // The collection's placeholder had the standard schedule; give it the member's again.
            collection.schedule = schedule.schedule
        }
        return collectionReloaded || scheduleReloaded
    }

    #if DEBUG
    /// DEBUG launches with demo arguments. Every store is in memory, so the real files are never written:
    /// a demo collection (`-MapleDemoSpecies`/`Days`/`Waiting`), an empty first run (`-MapleDemoFresh`), or an
    /// in-memory copy of the member's own collection when only the phase, season or rarity is overridden.
    public static func make(
        _ options: DemoLaunchOptions, directory: URL = MapleContainer.directory(), calendar: Calendar = .current,
        now: Date = .now
    ) -> MapleStores {
        let usesDemo = options.usesDemoCollection
        let permissions = options.permissions ?? (usesDemo ? DemoData.defaultPermissions : [])
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
        return MapleStores(collection: collection, schedule: schedule, shares: shares, clock: clock, seasonOverride: options.season)
    }
    #endif
}
