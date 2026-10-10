#if DEBUG
import Foundation
import Testing
@testable import MapleCore
@testable import MapleServices

@Suite("Demo data")
struct DemoDataTests {
    private let now = at(2026, 10, 10, 15)

    private func demo(_ species: Int, days: Int = 41, waiting: Int = 0) -> CollectionSnapshot {
        DemoData.snapshot(species: species, tendedDays: days, waiting: waiting, now: now, calendar: utc, hemisphere: .northern)
    }

    @Test("Exactly N species, first steps always, cheapest rungs first", arguments: [1, 2, 5, 23, 40, 73, 90, 155])
    func ladders(count: Int) {
        let snapshot = demo(count)
        #expect(snapshot.unlocks.count == count)
        #expect(Set(snapshot.unlocks.map(\.speciesID)).count == count)
        #expect(snapshot.unlocks.contains { $0.speciesID == "saccharum" })
        // Each category's earned rungs are the bottom of its ladder, and its counter sits between them and the next.
        for category in RewardCatalog.shared.categories {
            let rungs = RewardCatalog.shared.rungs(in: category.id)
            let earned = rungs.filter { rung in snapshot.unlocks.contains { $0.speciesID == rung.speciesID } }
            #expect(Array(rungs.prefix(earned.count)) == earned, "\(category.id)")
            let counter = snapshot.counters[category.id] ?? 0
            if let top = earned.last { #expect(counter >= top.threshold, "\(category.id)") }
            if earned.count < rungs.count { #expect(counter < rungs[earned.count].threshold, "\(category.id)") }
        }
        // So the engine has nothing to add.
        let added = LeafEngine().newUnlocks(counters: snapshot.counters, existing: snapshot.unlocks, at: now, season: .autumn)
        #expect(added.isEmpty)
    }

    @Test("Shipped categories fill first, so a small collection has no dormant leaves")
    func shippedFirst() {
        let snapshot = demo(23)
        #expect(snapshot.unlocks.allSatisfy { unlock in
            let category = RewardCatalog.shared.reward(forSpecies: unlock.speciesID)?.categoryID
            return category.map { ShippedFeatures.current.isShipped($0) } ?? false
        })
    }

    @Test("Waiting leaves are the newest, and can be opened in morning, day and evening")
    func waiting() {
        let snapshot = demo(23, waiting: 3)
        #expect(snapshot.waiting.count == 3)
        #expect(snapshot.earned.count == 20)
        #expect(Set(snapshot.waiting.map(\.speciesID)).isDisjoint(with: ["saccharum"]))
        let newest = snapshot.unlocks.sorted { $0.date < $1.date }.suffix(3)
        #expect(Set(newest.map(\.speciesID)) == Set(snapshot.waiting.map(\.speciesID)))
        #expect(snapshot.revealsOpened == 20)
        let context = CollectionContext(schedule: .standard, calendar: utc, hemisphere: .northern)
        for phase in [NowPhase.morning, .day, .evening] {
            let date = PhaseWindows(schedule: .standard).sampleDate(in: phase, onDayOf: now, calendar: utc)
            #expect(snapshot.revealable(at: date, context: context).count == 3, "\(phase)")
        }
        // Never more waiting than there are leaves besides the sugar maple.
        #expect(demo(2, waiting: 5).waiting.count == 1)
    }

    @Test("Tended days, mixed pressed seasons and a plausible week")
    func plausible() {
        let snapshot = demo(23, days: 41)
        #expect(snapshot.tendedDayCount == 41)
        #expect(snapshot.tendedDays.last == LocalDay(now, calendar: utc))
        #expect(Set(snapshot.unlocks.map(\.season)).count >= 2)
        #expect(snapshot.unlocks.allSatisfy { $0.date < now })
        #expect(snapshot.unlocks.allSatisfy { $0.colourway == LeafColourway.pressed(in: $0.season, evergreen: LeafCatalog.shared.species(id: $0.speciesID)?.evergreen ?? false) })
        #expect(snapshot.vitality.value > 0.8)
        #expect(snapshot.currentBedtimeRun >= 2)
        #expect(snapshot.recentNights.count == 7)
        let big = demo(155, days: 600)
        #expect(Set(big.unlocks.map(\.season)) == Set(Season.allCases))
        #expect(TreeStage(speciesCount: big.earned.count) == .grandMaple)
    }

    @Test("The same inputs make the same collection")
    func deterministic() {
        #expect(demo(23, waiting: 1) == demo(23, waiting: 1))
        #expect(demo(23).treeSeed == DemoData.snapshot(species: 90, tendedDays: 200, waiting: 2, now: now, calendar: utc, hemisphere: .northern).treeSeed)
    }

    @Test("Zero species is an empty collection")
    func empty() {
        let snapshot = demo(0)
        #expect(snapshot.unlocks.isEmpty)
        #expect(snapshot.tendedDays.isEmpty)
        #expect(!snapshot.hasPlantedMaple)
    }
}

@Suite("Demo launch arguments")
struct DemoLaunchOptionsTests {
    @Test("Reads the Core-owned arguments")
    func parse() {
        let options = DemoLaunchOptions(arguments: [
            "/path/Maple", "-MapleDemoSpecies", "23", "-MapleDemoDays", "41", "-MapleDemoWaiting", "1",
            "-MapleDemoPhase", "windDown", "-MapleDemoSeason", "winter", "-MapleDemoRarity", "YES", "-MapleDemoTab", "home",
        ])
        #expect(options.species == 23)
        #expect(options.days == 41)
        #expect(options.waiting == 1)
        #expect(options.phase == .windDown)
        #expect(options.season == .winter)
        #expect(options.rarity)
        #expect(!options.fresh)
        #expect(options.usesDemoCollection)
    }

    @Test("Absent, invalid and out-of-range values are ignored or clamped")
    func invalid() {
        let none = DemoLaunchOptions(arguments: ["/path/Maple"])
        #expect(none == DemoLaunchOptions())
        #expect(!none.usesDemoCollection)
        #expect(!none.isActive)
        let odd = DemoLaunchOptions(arguments: ["-MapleDemoSpecies", "900", "-MapleDemoPhase", "dusk", "-MapleDemoFresh", "YES",
                                                "-MapleDemoRarity", "NO", "-MapleDemoDays"])
        #expect(odd.species == 155)
        #expect(odd.phase == nil)
        #expect(odd.fresh)
        #expect(!odd.rarity)
        #expect(odd.days == nil)
        #expect(odd.isActive)
        #expect(DemoLaunchOptions(arguments: ["-MapleDemoPhase", "winddown"]).phase == .windDown)
        #expect(DemoLaunchOptions(arguments: ["-MapleDemoDays", "12"]).usesDemoCollection)
        #expect(DemoLaunchOptions(arguments: ["-MapleDemoPermissions", "none"]).permissions == [])
        #expect(DemoLaunchOptions(arguments: ["-MapleDemoPermissions", "health"]).permissions == [.appleHealth, .sleepTracker])
    }
}

@Suite("Store wiring")
@MainActor
struct MapleStoresTests {
    private let now = at(2026, 10, 10, 15)

    @Test("Release wiring: an empty real collection and the unconfigured rarity provider")
    func live() throws {
        let folder = try temporaryDirectory()
        let stores = MapleStores.live(directory: folder, calendar: utc, now: now)
        #expect(stores.collection.snapshot.unlocks.isEmpty)
        #expect(!stores.schedule.hasSavedSchedule)
        #expect(stores.shares.providerIdentifier == UnconfiguredLeafShareProvider().identifier)
        #expect(!stores.clock.isFixed)
        #expect(stores.seasonOverride == nil)
        #expect(files(in: folder).contains("collection.json"))
    }

    @Test("Demo collections live in memory and never touch the real file")
    func demo() throws {
        let folder = try temporaryDirectory()
        let real = MapleStores.live(directory: folder, calendar: utc, now: now)
        real.schedule.save(.standard, at: now)
        let before = try Data(contentsOf: folder.appendingPathComponent("collection.json"))

        let options = DemoLaunchOptions(arguments: ["-MapleDemoSpecies", "23", "-MapleDemoWaiting", "2", "-MapleDemoPhase", "evening",
                                                    "-MapleDemoSeason", "winter", "-MapleDemoRarity", "YES"])
        let stores = MapleStores.make(options, directory: folder, calendar: utc, now: now)
        #expect(stores.collection.snapshot.unlocks.count == 23)
        #expect(stores.collection.waiting.count == 2)
        #expect(stores.schedule.hasSavedSchedule)
        #expect(stores.clock.isFixed)
        #expect(NowPhase.resolve(date: stores.clock.now(), schedule: stores.schedule.schedule, calendar: utc) == .evening)
        #expect(LocalDay(stores.clock.now(), calendar: utc) == LocalDay(now, calendar: utc))
        #expect(stores.seasonOverride == .winter)
        #expect(stores.collection.context.seasonOverride == .winter)
        #expect(stores.collection.rarityConsent == .included)
        #expect(stores.shares.providerIdentifier == "preview")

        stores.collection.record([.nightsTracked: 50], at: now)
        stores.collection.openReveals(at: stores.clock.now())
        #expect(try Data(contentsOf: folder.appendingPathComponent("collection.json")) == before)
    }

    @Test("Fresh: an empty collection with no saved schedule, in memory")
    func fresh() throws {
        let folder = try temporaryDirectory()
        let real = MapleStores.live(directory: folder, calendar: utc, now: now)
        real.schedule.save(.standard, at: now)
        let stores = MapleStores.make(DemoLaunchOptions(arguments: ["-MapleDemoFresh", "YES"]), directory: folder, calendar: utc, now: now)
        #expect(stores.collection.snapshot.unlocks.isEmpty)
        #expect(!stores.schedule.hasSavedSchedule)
        stores.schedule.save(.standard, at: now)
        #expect(stores.collection.hasPlantedMaple)
        let reread = MapleStores.live(directory: folder, calendar: utc, now: now)
        #expect(reread.collection.snapshot.unlocks.count == 1)
    }

    @Test("Rarity alone keeps the real collection but writes nothing")
    func rarityOnly() throws {
        let folder = try temporaryDirectory()
        let real = MapleStores.live(directory: folder, calendar: utc, now: now)
        real.schedule.save(.standard, at: now)
        let before = try Data(contentsOf: folder.appendingPathComponent("collection.json"))
        let stores = MapleStores.make(DemoLaunchOptions(arguments: ["-MapleDemoRarity", "YES"]), directory: folder, calendar: utc, now: now)
        #expect(stores.collection.snapshot.unlocks.map(\.speciesID) == ["saccharum"])
        #expect(stores.collection.rarityConsent == .included)
        #expect(try Data(contentsOf: folder.appendingPathComponent("collection.json")) == before)
    }
}

@Suite("Preview rarity")
struct PreviewShareProviderTests {
    @Test("Plausible, tier-correlated shares over more than 1,000 members")
    func plausible() async throws {
        let counts = try await PreviewLeafShareProvider().fetchCounts()
        let members = try #require(counts.members)
        #expect(members > 1_000)
        #expect(counts.counts.count == 155)
        func share(_ id: String) -> Double { Double(counts.counts[id] ?? 0) / Double(members) * 100 }
        #expect(share("saccharum") > 80 && share("saccharum") < 97)
        let byTier = Dictionary(grouping: RewardCatalog.shared.assignments, by: \.tier).mapValues { rungs in
            rungs.map { share($0.speciesID) }.reduce(0, +) / Double(rungs.count)
        }
        let tiers = RewardTier.allCases.compactMap { byTier[$0] }
        #expect(tiers == tiers.sorted(by: >))
        for rung in RewardCatalog.shared.assignments where rung.tier == .legendary {
            #expect(share(rung.speciesID) < 1, "\(rung.speciesID)")
        }
        let again = try await PreviewLeafShareProvider().fetchCounts()
        #expect(again == counts)
    }
}
#endif
