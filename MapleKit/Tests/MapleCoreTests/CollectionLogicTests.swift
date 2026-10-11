import Foundation
import Testing
@testable import MapleCore

@Suite("Collection: counters and tended days")
struct CollectionCounterTests {
    private func fresh() -> CollectionSnapshot {
        CollectionSnapshot.empty(profileID: UUID(), createdAt: at(2026, 10, 1, 9))
    }

    @Test("Increases raise counters and mark the local day tended")
    func increases() {
        var snapshot = fresh()
        let rose = snapshot.record([.restedNights: 1, .hoursSaved: 1], at: at(2026, 10, 2, 7), calendar: utc)
        #expect(rose)
        #expect(snapshot.counters == [.restedNights: 1, .hoursSaved: 1])
        #expect(snapshot.tendedDays == [LocalDay(year: 2026, month: 10, day: 2)])
        snapshot.record([.restedNights: 1], at: at(2026, 10, 2, 22), calendar: utc)
        snapshot.record([.restedNights: 1], at: at(2026, 10, 4, 7), calendar: utc)
        #expect(snapshot.counters[.restedNights] == 3)
        #expect(snapshot.tendedDays == [LocalDay(year: 2026, month: 10, day: 2), LocalDay(year: 2026, month: 10, day: 4)])
        #expect(snapshot.tendedDayCount == 2)
    }

    @Test("The first leaf never tends the tree")
    func notTended() {
        var snapshot = fresh()
        snapshot.raise(.firstLeaf, to: 1, at: at(2026, 10, 1, 9), calendar: utc)
        #expect(snapshot.counters == [.firstLeaf: 1])
        #expect(snapshot.tendedDays.isEmpty)
    }

    @Test("Counters never go down")
    func monotonic() {
        var snapshot = fresh()
        snapshot.raise(.focusStreak, to: 5, at: at(2026, 10, 2, 7), calendar: utc)
        let lowered = snapshot.raise(.focusStreak, to: 3, at: at(2026, 10, 3, 7), calendar: utc)
        let negative = snapshot.record([.restedNights: 0, .hoursSaved: -2], at: at(2026, 10, 3, 7), calendar: utc)
        #expect(!lowered)
        #expect(!negative)
        #expect(snapshot.counters == [.focusStreak: 5])
        #expect(snapshot.tendedDays == [LocalDay(year: 2026, month: 10, day: 2)])
    }

    @Test("History keeps each day's closing counters, and a baseline older than the window")
    func history() {
        var snapshot = fresh()
        for day in 1...40 {
            snapshot.record([.restedNights: 1], at: at(2026, 9, 1, 7).addingTimeInterval(Double(day - 1) * 86_400), calendar: utc)
        }
        snapshot.record([.hoursSaved: 1], at: at(2026, 10, 10, 21), calendar: utc)
        let last = snapshot.history.last
        #expect(last?.day == LocalDay(year: 2026, month: 10, day: 10))
        #expect(last?.counters == [.restedNights: 40, .hoursSaved: 1])
        #expect(snapshot.history.count <= 32)
        let window = LeafPace.rate(for: .restedNights, current: 40, history: snapshot.history,
                                   today: LocalDay(year: 2026, month: 10, day: 10), calendar: utc)
        #expect(abs(window - 1) < 1e-9)
    }

    @Test("Apple Health's on-time nights earn Rested nights")
    func restedNights() throws {
        let calendar = utc
        var snapshot = CollectionSnapshot.empty(profileID: UUID(), createdAt: at(2026, 10, 1, 12))
        let context = CollectionContext(schedule: .standard, permissions: [.appleHealth], calendar: calendar, hemisphere: .northern)
        snapshot.raise(.firstLeaf, to: 1, at: at(2026, 10, 1, 20), calendar: calendar)
        _ = snapshot.runEngine(at: at(2026, 10, 1, 20), context: context, engine: LeafEngine())
        // Three on-time nights (onset 23:10 against bed 23:00), each settled at the next morning.
        let observations = (1...3).map { day in
            SleepNightObservation(onset: at(2026, 10, day, 23, 10), finalWake: at(2026, 10, day + 1, 7), asleepMinutes: 450,
                                  source: .watchOrTracker, calendar: calendar)
        }
        let unlocks = snapshot.recordSleep(observations, at: at(2026, 10, 4, 9), context: context)
        #expect(snapshot.counters[.restedNights] == 3)
        #expect(unlocks.map(\.speciesID) == [try #require(RewardCatalog.shared.rungs(in: .restedNights).first).speciesID])
        #expect(snapshot.counters.keys.allSatisfy { [.firstLeaf, .restedNights].contains($0) })
    }

    @Test("A collection saved by the old table loads, keeps its leaves and carries on-time nights over")
    func oldCollectionLoads() throws {
        let json = #"""
        {"profileID":"5D2A2C0E-6B7E-4F3B-9C55-1A2B3C4D5E6F","createdAt":0,"unlocks":[{"speciesID":"saccharum","date":0,"season":"autumn","colourway":"autumn","revealed":true,"seen":true}],
         "counters":{"first_steps":1,"on_time_bedtimes":11,"bedtime_run":6,"steady_weeks":1},"currentBedtimeRun":4}
        """#
        let snapshot = try JSONDecoder().decode(CollectionSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.unlocks.map(\.speciesID) == ["saccharum"])
        #expect(snapshot.counters[.restedNights] == 11)
        #expect(snapshot.counters[.firstLeaf] == 1)
        #expect(snapshot.hasPlantedMaple)
    }

    @Test("Recording sleep keeps no bedtime run and raises nothing but Rested nights")
    func noBedtimeRun() throws {
        let calendar = utc
        var snapshot = CollectionSnapshot.empty(profileID: UUID(), createdAt: at(2026, 10, 1, 12))
        let context = CollectionContext(schedule: .standard, permissions: [.appleHealth], calendar: calendar, hemisphere: .northern)
        snapshot.raise(.firstLeaf, to: 1, at: at(2026, 10, 1, 20), calendar: calendar)
        _ = snapshot.runEngine(at: at(2026, 10, 1, 20), context: context)
        let observations = (1...6).map { day in
            SleepNightObservation(onset: at(2026, 10, day, 23, 5), finalWake: at(2026, 10, day + 1, 7), asleepMinutes: 450,
                                  source: .watchOrTracker, calendar: calendar)
        }
        snapshot.recordSleep(observations, at: at(2026, 10, 7, 9), context: context)
        #expect(Set(snapshot.counters.keys) == [.firstLeaf, .restedNights])
        let encoded = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        #expect(!encoded.contains("currentBedtimeRun"))
    }
}

@Suite("Collection: unlocks and reveals")
struct CollectionRevealTests {
    private let context = CollectionContext(schedule: .standard, calendar: utc, hemisphere: .northern)

    private func planted(at date: Date = at(2026, 10, 1, 21)) -> CollectionSnapshot {
        var snapshot = CollectionSnapshot.empty(profileID: UUID(), createdAt: date)
        snapshot.raise(.firstLeaf, to: 1, at: date, calendar: utc)
        snapshot.runEngine(at: date, context: context)
        return snapshot
    }

    @Test("The engine adds new unlocks once, pressed in the season")
    func engine() throws {
        var snapshot = planted()
        #expect(snapshot.unlocks.map(\.speciesID) == ["saccharum"])
        #expect(snapshot.hasPlantedMaple)
        snapshot.record([.restedNights: 14], at: at(2026, 10, 3, 7), calendar: utc)
        let added = snapshot.runEngine(at: at(2026, 10, 3, 7), context: context)
        #expect(added.map(\.speciesID) == [species(.restedNights, rung: 0), species(.restedNights, rung: 1)])
        #expect(added.allSatisfy { $0.season == .autumn && $0.colourway == .autumn && !$0.revealed })
        #expect(snapshot.runEngine(at: at(2026, 10, 3, 8), context: context).isEmpty)
        #expect(snapshot.unlocks.count == 3)
    }

    @Test("The first leaf can be opened at any hour; others wait for morning, day or evening")
    func firstStepsAtNight() {
        var snapshot = planted(at: at(2026, 10, 1, 23, 30))
        #expect(snapshot.revealable(at: at(2026, 10, 1, 23, 31), context: context).map(\.speciesID) == ["saccharum"])
        let opened = snapshot.openReveals(nil, at: at(2026, 10, 1, 23, 32), context: context)
        #expect(opened.map(\.speciesID) == ["saccharum"])
        #expect(snapshot.unlocks.first?.revealed == true)
        #expect(snapshot.revealsOpened == 1)
        #expect(snapshot.revealedAt["saccharum"] == at(2026, 10, 1, 23, 32))
    }

    @Test("Held leaves wait for morning; pending leaves never open in wind-down or night")
    func heldAndPending() {
        var snapshot = planted()
        snapshot.openReveals(nil, at: at(2026, 10, 1, 21, 5), context: context)
        snapshot.record([.hoursSaved: 1], at: at(2026, 10, 2, 14), calendar: utc)
        snapshot.runEngine(at: at(2026, 10, 2, 14), context: context)               // pending at once
        snapshot.record([.sessionsFinished: 1], at: at(2026, 10, 2, 21), calendar: utc)
        snapshot.runEngine(at: at(2026, 10, 2, 21), context: context)               // evening: held

        let evening = at(2026, 10, 2, 21, 30)
        #expect(snapshot.waiting.map(\.speciesID) == ["rubrum", "buergerianum"])
        #expect(snapshot.pending(at: evening, context: context).map(\.speciesID) == ["rubrum"])
        #expect(snapshot.held(at: evening, context: context).map(\.speciesID) == ["buergerianum"])
        #expect(snapshot.revealable(at: evening, context: context).map(\.speciesID) == ["rubrum"])
        #expect(snapshot.revealable(at: at(2026, 10, 2, 22, 30), context: context).isEmpty)  // wind-down
        #expect(snapshot.revealable(at: at(2026, 10, 3, 2), context: context).isEmpty)       // night
        #expect(snapshot.openReveals(nil, at: at(2026, 10, 3, 2), context: context).isEmpty)

        let morning = at(2026, 10, 3, 6, 30)
        #expect(snapshot.revealable(at: morning, context: context).map(\.speciesID) == ["rubrum", "buergerianum"])
        let one = snapshot.openReveals(["buergerianum"], at: morning, context: context)
        #expect(one.map(\.speciesID) == ["buergerianum"])
        #expect(snapshot.waiting.map(\.speciesID) == ["rubrum"])
        let rest = snapshot.openReveals(nil, at: morning, context: context)
        #expect(rest.map(\.speciesID) == ["rubrum"])
        #expect(snapshot.revealsOpened == 3)
        #expect(snapshot.earned.map(\.speciesID) == ["saccharum", "rubrum", "buergerianum"])
    }

    @Test("Seen, pinned and featured leaves")
    func flags() {
        var snapshot = planted(at: at(2026, 10, 1, 9))
        snapshot.openReveals(nil, at: at(2026, 10, 1, 9, 5), context: context)
        #expect(snapshot.isUnseen("saccharum"))
        snapshot.markSeen("saccharum")
        #expect(!snapshot.isUnseen("saccharum"))
        #expect(snapshot.featuredLeaf == "saccharum")

        snapshot.record([.hoursSaved: 1], at: at(2026, 10, 2, 9), calendar: utc)
        snapshot.runEngine(at: at(2026, 10, 2, 9), context: context)
        #expect(snapshot.featuredLeaf == "saccharum")                 // waiting leaves can't be featured
        snapshot.openReveals(nil, at: at(2026, 10, 2, 9, 5), context: context)
        #expect(snapshot.featuredLeaf == "rubrum")                    // defaults to the newest
        let featured = snapshot.feature("saccharum")
        #expect(featured)
        #expect(snapshot.featuredLeaf == "saccharum")
        let notEarned = snapshot.feature("griseum")
        #expect(!notEarned)                                           // not earned
        #expect(snapshot.featuredLeaf == "saccharum")
        snapshot.feature(nil)
        #expect(snapshot.featuredLeaf == "rubrum")

        snapshot.pin("japonicum")
        #expect(snapshot.pinnedSpeciesID == "japonicum")
        snapshot.pin(nil)
        #expect(snapshot.pinnedSpeciesID == nil)
    }

    @Test("Nights keep the last 14, one per day")
    func nights() {
        var snapshot = planted()
        for day in 1...20 {
            snapshot.recordNight(NightRecord(day: LocalDay(year: 2026, month: 9, day: day), onTime: day % 2 == 0, fullNight: nil, scrollFree: nil))
        }
        snapshot.recordNight(NightRecord(day: LocalDay(year: 2026, month: 9, day: 20), onTime: false, fullNight: nil, scrollFree: nil))
        #expect(snapshot.recentNights.count == 14)
        #expect(snapshot.recentNights.last == NightRecord(day: LocalDay(year: 2026, month: 9, day: 20), onTime: false, fullNight: nil, scrollFree: nil))
        #expect(snapshot.vitality(at: at(2026, 9, 21, 7), calendar: utc).value < 1)
        // Six weeks later those nights are long gone: full vitality again (spec §4.8).
        #expect(snapshot.vitality(at: at(2026, 11, 1, 7), calendar: utc).value == 1)
    }
}

@Suite("Collection: tree and totals")
struct CollectionTreeTests {
    /// Apple Health connected, so the sleep categories can be earned.
    private let context = CollectionContext(schedule: .standard, permissions: [.appleHealth], calendar: utc, hemisphere: .northern)

    /// Planted on 1 Oct, three on-time nights and an hour saved on each of the next three days, everything opened by
    /// the 4th.
    private func grown() -> CollectionSnapshot {
        var snapshot = CollectionSnapshot.empty(profileID: UUID(uuidString: "7F3C1C9E-1C3B-4E5E-8E0B-2B0F6C2D4A11")!, createdAt: at(2026, 10, 1, 9))
        snapshot.raise(.firstLeaf, to: 1, at: at(2026, 10, 1, 9), calendar: utc)
        snapshot.runEngine(at: at(2026, 10, 1, 9), context: context)
        snapshot.openReveals(nil, at: at(2026, 10, 1, 9, 5), context: context)
        for day in 2...4 {
            snapshot.record([.restedNights: 1, .hoursSaved: 1], at: at(2026, 10, day, 7), calendar: utc)
            snapshot.runEngine(at: at(2026, 10, day, 7), context: context)
        }
        snapshot.openReveals(nil, at: at(2026, 10, 4, 12), context: context)
        return snapshot
    }

    @Test("Tree inputs carry the placed species, growth, stage and seed")
    func inputs() {
        let snapshot = grown()
        let tree = snapshot.treeInputs(at: at(2026, 10, 4, 13), context: context)
        #expect(tree.species.map(\.speciesID) == snapshot.earned.map(\.speciesID))
        #expect(tree.species.first == TreeInputs.Leaf(speciesID: "saccharum", pressed: .autumn))
        #expect(tree.tendedDays == 3)
        #expect(tree.growth == TreeGrowth.structure(tendedDays: 3))
        #expect(tree.stage == TreeStage(speciesCount: snapshot.earned.count))
        #expect(tree.seed == snapshot.treeSeed)
        #expect(tree.season == .autumn)
        #expect(tree.seasonDay == TreeFoliage.seasonDay(for: at(2026, 10, 4, 13), hemisphere: .northern, calendar: utc))
        #expect(tree.vitality == 1)
        #expect(tree.featured == snapshot.featuredLeaf)
        #expect(tree.waiting.isEmpty)
        #expect(tree.unlockOrder == snapshot.unlocks.map(\.speciesID))
    }

    @Test("Tree inputs list every earned leaf in unlock order, held ones too, so no place on the crown shifts")
    func unlockOrder() {
        var snapshot = grown()
        let evening = at(2026, 10, 4, 21)
        snapshot.record([.restedNights: 100], at: evening, calendar: utc)
        let held = snapshot.runEngine(at: evening, context: context)
        #expect(!held.isEmpty)
        let tree = snapshot.treeInputs(at: evening, context: context)
        #expect(tree.unlockOrder == snapshot.unlocks.map(\.speciesID))
        #expect(Array(tree.unlockOrder.suffix(held.count)) == held.map(\.speciesID))
        #expect(tree.waiting.isEmpty)
        #expect(tree.species.map(\.speciesID) == Array(tree.unlockOrder.prefix(tree.species.count)))
    }

    @Test("Buds are the next three leaves with their progress, Home's pick first")
    func buds() {
        let snapshot = grown()
        let now = at(2026, 10, 4, 21)
        // Every category earnable, so there are more than three candidates.
        var all = context
        all.features = .all
        all.permissions = [.appleHealth, .screenTime]
        let tree = snapshot.treeInputs(at: now, context: all)
        let next = snapshot.nextLeaf(at: now, context: all)
        #expect(tree.buds.count == 3)
        #expect(tree.buds.first?.speciesID == next?.speciesID)
        #expect(tree.buds.allSatisfy { $0.progress >= 0 && $0.progress <= 1 })
        #expect(snapshot.buds(at: now, context: all).map(\.speciesID) == tree.buds.map(\.speciesID))
    }

    @Test("Halos mark leaves opened in the last 24 hours")
    func halos() {
        let snapshot = grown()
        let soon = snapshot.treeInputs(at: at(2026, 10, 4, 13), context: context)
        #expect(Set(soon.newLeafHalos.map(\.speciesID)) == Set(snapshot.earned.dropFirst().map(\.speciesID)))
        #expect(soon.newLeafHalos.allSatisfy { $0.placedAt == at(2026, 10, 4, 12) })
        #expect(snapshot.treeInputs(at: at(2026, 10, 5, 12, 1), context: context).newLeafHalos.isEmpty)
    }

    @Test("The waiting bud shows only when the leaf can be opened now")
    func waiting() {
        var snapshot = grown()
        snapshot.record([.restedNights: 14], at: at(2026, 10, 5, 12), calendar: utc)
        snapshot.runEngine(at: at(2026, 10, 5, 12), context: context)
        #expect(snapshot.treeInputs(at: at(2026, 10, 5, 13), context: context).waiting == [species(.restedNights, rung: 1)])
        #expect(snapshot.treeInputs(at: at(2026, 10, 5, 23, 30), context: context).waiting.isEmpty)
    }

    @Test("A season override wins over the date")
    func seasonOverride() {
        var overridden = context
        overridden.seasonOverride = .winter
        #expect(grown().treeInputs(at: at(2026, 10, 4, 13), context: overridden).season == .winter)
        #expect(grown().season(at: at(2026, 10, 4, 13), context: overridden) == .winter)
    }

    @Test("Profile totals show only categories that exist")
    func totals() {
        let snapshot = grown()
        let totals = snapshot.totals(context: context)
        #expect(totals.leaves == snapshot.earned.count)
        #expect(totals.tendedDays == 3)
        #expect(totals.stage == .sapling)
        #expect(totals.restedNights == 3)
        // The focus categories ship with F1 and F2.
        #expect(totals.hoursSaved == nil && totals.sessionsFinished == nil && totals.phoneFreeMornings == nil)
        // Without Apple Health no sleep category can count, so it has no total.
        var withoutHealth = context
        withoutHealth.permissions = []
        #expect(snapshot.totals(context: withoutHealth).restedNights == nil)
        var everything = context
        everything.features = .all
        everything.permissions = [.appleHealth, .screenTime]
        #expect(snapshot.totals(context: everything).hoursSaved == 3)
    }

    @Test("Profile totals: hours saved, sessions, rested nights and mornings, each only once it can be earned")
    func focusTotals() {
        var snapshot = CollectionSnapshot.empty(profileID: UUID(), createdAt: at(2026, 10, 1, 12))
        snapshot.counters = [.hoursSaved: 12.5, .sessionsFinished: 9, .restedNights: 4, .phoneFreeMornings: 2]
        let now = CollectionContext(schedule: .standard, permissions: [.appleHealth], calendar: utc, hemisphere: .northern)
        let today = snapshot.totals(context: now)
        #expect(today.hoursSaved == nil && today.sessionsFinished == nil && today.phoneFreeMornings == nil)
        #expect(today.restedNights == 4)
        let f2 = CollectionContext(schedule: .standard, permissions: [.appleHealth, .screenTime],
                                   features: ShippedFeatures(releases: [.m1, .f1, .f2]), calendar: utc, hemisphere: .northern)
        let later = snapshot.totals(context: f2)
        #expect(later.hoursSaved == 12.5 && later.sessionsFinished == 9 && later.phoneFreeMornings == 2)
    }

    @Test("Progress and the picker read the snapshot")
    func progress() throws {
        let snapshot = grown()
        let now = at(2026, 10, 4, 21)
        let rows = snapshot.progress(at: now, context: context)
        #expect(rows.count == 155)
        let nights = try #require(rows.first { $0.speciesID == species(.restedNights, rung: 1) })
        #expect(nights.current == 3)
        #expect(nights.estimatedDays != nil)
        #expect(snapshot.almostThere(at: now, context: context).count <= 6)
        #expect(!snapshot.nextRungIDs(at: now, context: context).isEmpty)
    }
}
