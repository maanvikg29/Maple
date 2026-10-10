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
        let rose = snapshot.record([.nightsTracked: 1, .onTimeBedtimes: 1], at: at(2026, 10, 2, 7), calendar: utc)
        #expect(rose)
        #expect(snapshot.counters == [.nightsTracked: 1, .onTimeBedtimes: 1])
        #expect(snapshot.tendedDays == [LocalDay(year: 2026, month: 10, day: 2)])
        snapshot.record([.nightsTracked: 1], at: at(2026, 10, 2, 22), calendar: utc)
        snapshot.record([.nightsTracked: 1], at: at(2026, 10, 4, 7), calendar: utc)
        #expect(snapshot.counters[.nightsTracked] == 3)
        #expect(snapshot.tendedDays == [LocalDay(year: 2026, month: 10, day: 2), LocalDay(year: 2026, month: 10, day: 4)])
        #expect(snapshot.tendedDayCount == 2)
    }

    @Test("First steps and community challenges never tend the tree")
    func notTended() {
        var snapshot = fresh()
        snapshot.raise(.firstSteps, to: 1, at: at(2026, 10, 1, 9), calendar: utc)
        snapshot.record([.communityChallenges: 1], at: at(2026, 10, 3, 9), calendar: utc)
        #expect(snapshot.counters == [.firstSteps: 1, .communityChallenges: 1])
        #expect(snapshot.tendedDays.isEmpty)
    }

    @Test("Counters never go down")
    func monotonic() {
        var snapshot = fresh()
        snapshot.raise(.bedtimeRun, to: 5, at: at(2026, 10, 2, 7), calendar: utc)
        let lowered = snapshot.raise(.bedtimeRun, to: 3, at: at(2026, 10, 3, 7), calendar: utc)
        let negative = snapshot.record([.nightsTracked: 0, .onTimeBedtimes: -2], at: at(2026, 10, 3, 7), calendar: utc)
        #expect(!lowered)
        #expect(!negative)
        #expect(snapshot.counters == [.bedtimeRun: 5])
        #expect(snapshot.tendedDays == [LocalDay(year: 2026, month: 10, day: 2)])
    }

    @Test("History keeps each day's closing counters, and a baseline older than the window")
    func history() {
        var snapshot = fresh()
        for day in 1...40 {
            snapshot.record([.nightsTracked: 1], at: at(2026, 9, 1, 7).addingTimeInterval(Double(day - 1) * 86_400), calendar: utc)
        }
        snapshot.record([.onTimeBedtimes: 1], at: at(2026, 10, 10, 21), calendar: utc)
        let last = snapshot.history.last
        #expect(last?.day == LocalDay(year: 2026, month: 10, day: 10))
        #expect(last?.counters == [.nightsTracked: 40, .onTimeBedtimes: 1])
        #expect(snapshot.history.count <= 32)
        let window = LeafPace.rate(for: .nightsTracked, current: 40, history: snapshot.history,
                                   today: LocalDay(year: 2026, month: 10, day: 10), calendar: utc)
        #expect(abs(window - 1) < 1e-9)
    }
}

@Suite("Collection: unlocks and reveals")
struct CollectionRevealTests {
    private let context = CollectionContext(schedule: .standard, calendar: utc, hemisphere: .northern)

    private func planted(at date: Date = at(2026, 10, 1, 21)) -> CollectionSnapshot {
        var snapshot = CollectionSnapshot.empty(profileID: UUID(), createdAt: date)
        snapshot.raise(.firstSteps, to: 1, at: date, calendar: utc)
        snapshot.runEngine(at: date, context: context)
        return snapshot
    }

    @Test("The engine adds new unlocks once, pressed in the season")
    func engine() throws {
        var snapshot = planted()
        #expect(snapshot.unlocks.map(\.speciesID) == ["saccharum"])
        #expect(snapshot.hasPlantedMaple)
        snapshot.record([.nightsTracked: 3], at: at(2026, 10, 3, 7), calendar: utc)
        let added = snapshot.runEngine(at: at(2026, 10, 3, 7), context: context)
        #expect(added.map(\.speciesID) == [species(.nightsTracked, rung: 0), species(.nightsTracked, rung: 1)])
        #expect(added.allSatisfy { $0.season == .autumn && $0.colourway == .autumn && !$0.revealed })
        #expect(snapshot.runEngine(at: at(2026, 10, 3, 8), context: context).isEmpty)
        #expect(snapshot.unlocks.count == 3)
    }

    @Test("First steps can be opened at any hour; others wait for morning, day or evening")
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
        snapshot.record([.nightsTracked: 1], at: at(2026, 10, 2, 14), calendar: utc)
        snapshot.runEngine(at: at(2026, 10, 2, 14), context: context)               // pending at once
        snapshot.record([.onTimeBedtimes: 1], at: at(2026, 10, 2, 21), calendar: utc)
        snapshot.runEngine(at: at(2026, 10, 2, 21), context: context)               // evening: held

        let evening = at(2026, 10, 2, 21, 30)
        #expect(snapshot.waiting.map(\.speciesID) == ["rubrum", "palmatum"])
        #expect(snapshot.pending(at: evening, context: context).map(\.speciesID) == ["rubrum"])
        #expect(snapshot.held(at: evening, context: context).map(\.speciesID) == ["palmatum"])
        #expect(snapshot.revealable(at: evening, context: context).map(\.speciesID) == ["rubrum"])
        #expect(snapshot.revealable(at: at(2026, 10, 2, 22, 30), context: context).isEmpty)  // wind-down
        #expect(snapshot.revealable(at: at(2026, 10, 3, 2), context: context).isEmpty)       // night
        #expect(snapshot.openReveals(nil, at: at(2026, 10, 3, 2), context: context).isEmpty)

        let morning = at(2026, 10, 3, 6, 30)
        #expect(snapshot.revealable(at: morning, context: context).map(\.speciesID) == ["rubrum", "palmatum"])
        let one = snapshot.openReveals(["palmatum"], at: morning, context: context)
        #expect(one.map(\.speciesID) == ["palmatum"])
        #expect(snapshot.waiting.map(\.speciesID) == ["rubrum"])
        let rest = snapshot.openReveals(nil, at: morning, context: context)
        #expect(rest.map(\.speciesID) == ["rubrum"])
        #expect(snapshot.revealsOpened == 3)
        #expect(snapshot.earned.map(\.speciesID) == ["saccharum", "rubrum", "palmatum"])
    }

    @Test("Seen, pinned and featured leaves")
    func flags() {
        var snapshot = planted(at: at(2026, 10, 1, 9))
        snapshot.openReveals(nil, at: at(2026, 10, 1, 9, 5), context: context)
        #expect(snapshot.isUnseen("saccharum"))
        snapshot.markSeen("saccharum")
        #expect(!snapshot.isUnseen("saccharum"))
        #expect(snapshot.featuredLeaf == "saccharum")

        snapshot.record([.nightsTracked: 1], at: at(2026, 10, 2, 9), calendar: utc)
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

    /// Planted on 1 Oct, three tracked nights, everything opened by the 4th.
    private func grown() -> CollectionSnapshot {
        var snapshot = CollectionSnapshot.empty(profileID: UUID(uuidString: "7F3C1C9E-1C3B-4E5E-8E0B-2B0F6C2D4A11")!, createdAt: at(2026, 10, 1, 9))
        snapshot.raise(.firstSteps, to: 1, at: at(2026, 10, 1, 9), calendar: utc)
        snapshot.runEngine(at: at(2026, 10, 1, 9), context: context)
        snapshot.openReveals(nil, at: at(2026, 10, 1, 9, 5), context: context)
        for day in 2...4 {
            snapshot.record([.nightsTracked: 1, .onTimeBedtimes: 1], at: at(2026, 10, day, 7), calendar: utc)
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
    }

    @Test("Buds are the next three leaves with their progress, Home's pick first")
    func buds() {
        let snapshot = grown()
        let now = at(2026, 10, 4, 21)
        let tree = snapshot.treeInputs(at: now, context: context)
        let next = snapshot.nextLeaf(at: now, context: context)
        #expect(tree.buds.count == 3)
        #expect(tree.buds.first?.speciesID == next?.speciesID)
        #expect(tree.buds.allSatisfy { $0.progress >= 0 && $0.progress <= 1 })
        #expect(snapshot.buds(at: now, context: context).map(\.speciesID) == tree.buds.map(\.speciesID))
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
        snapshot.record([.nightsTracked: 4], at: at(2026, 10, 5, 12), calendar: utc)
        snapshot.runEngine(at: at(2026, 10, 5, 12), context: context)
        #expect(snapshot.treeInputs(at: at(2026, 10, 5, 13), context: context).waiting == [species(.nightsTracked, rung: 2)])
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
        #expect(totals.nightsOnTime == 3)
        #expect(totals.focusHours == nil)
        #expect(totals.windDowns == nil)
        #expect(totals.mornings == 0)
        // Without Apple Health no sleep category can count, so none has a total.
        var withoutHealth = context
        withoutHealth.permissions = []
        #expect(snapshot.totals(context: withoutHealth).nightsOnTime == nil)
        #expect(snapshot.totals(context: withoutHealth).mornings == nil)
        var everything = context
        everything.features = .all
        #expect(snapshot.totals(context: everything).focusHours == 0)
    }

    @Test("Progress and the picker read the snapshot")
    func progress() throws {
        let snapshot = grown()
        let now = at(2026, 10, 4, 21)
        let rows = snapshot.progress(at: now, context: context)
        #expect(rows.count == 155)
        let nights = try #require(rows.first { $0.speciesID == species(.nightsTracked, rung: 2) })
        #expect(nights.current == 3)
        #expect(nights.estimatedDays != nil)
        #expect(snapshot.almostThere(at: now, context: context).count <= 6)
        #expect(!snapshot.nextRungIDs(at: now, context: context).isEmpty)
    }
}
