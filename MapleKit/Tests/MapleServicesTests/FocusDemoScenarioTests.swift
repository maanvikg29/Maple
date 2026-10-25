#if DEBUG
import Foundation
import MapleStorage
import Testing
@testable import MapleCore
@testable import MapleServices

@Suite("Demo Focus history")
struct DemoFocusHistoryTests {
    private let today = LocalDay(year: 2026, month: 10, day: 23)
    private let shipped = ShippedFeatures(releases: [.m1, .f1])

    private var standard: DemoData.FocusHistory {
        DemoData.FocusHistory(today: today, secondsBeforeToday: 65_100, runThroughYesterday: 11, bestRun: 21)
    }

    @Test("The history's finished days make a run of 11 through yesterday, 12 with today, and a best of 21")
    func runs() {
        let days = DemoData.focusDays(standard, calendar: utc)
        #expect(days.count == 31)
        #expect(days.allSatisfy { $0.frozen && $0.finished == 1 && $0.seconds == DemoData.focusDaySeconds && $0.zone == utc.timeZone.identifier })
        #expect(days.allSatisfy { $0.day < today })
        #expect(days.map(\.day) == days.map(\.day).sorted())
        // A rest day inside the current run, so the streak sheet's week shows a neutral dot.
        #expect(!days.contains { $0.day == today.adding(days: -4, calendar: utc) })
        let focusDays = days.map { (day: $0.day, zone: $0.zone) }
        let throughYesterday = FocusRuns(focusDays: focusDays, today: today)
        #expect(throughYesterday.current == 11)
        #expect(throughYesterday.best == 21)
        let withToday = FocusRuns(focusDays: focusDays + [(day: today, zone: utc.timeZone.identifier)], today: today)
        #expect(withToday.current == 12)
        #expect(withToday.best == 21)
    }

    @Test("A demo collection with a Focus history: counters, leaves and book agree, so nothing new unlocks")
    func collection() {
        let now = at(2026, 10, 23, 9)
        let snapshot = DemoData.snapshot(species: 23, tendedDays: 41, waiting: 0, now: now, calendar: utc, hemisphere: .northern,
                                         features: shipped, focusHistory: standard)
        #expect(snapshot.unlocks.count == 23)
        #expect(snapshot.counters[.hoursSaved] == 65_100.0 / 3600)
        #expect(snapshot.counters[.sessionsFinished] == 31)
        #expect(snapshot.counters[.focusStreak] == 21)
        #expect(snapshot.focus.totalSeconds == 65_100)
        #expect(snapshot.focus.totalFinished == 31)
        #expect(snapshot.focus.bestRun == 21)
        #expect(snapshot.focus.days.count == 31)
        for category in [RewardCategoryID.hoursSaved, .sessionsFinished, .focusStreak] {
            let rungs = RewardCatalog.shared.rungs(in: category)
            let earned = rungs.filter { rung in snapshot.unlocks.contains { $0.speciesID == rung.speciesID } }
            #expect(Array(rungs.prefix(earned.count)) == earned, "\(category)")
            let counter = snapshot.counters[category] ?? 0
            #expect(earned.last.map { $0.threshold <= counter } ?? false, "\(category)")
            #expect(rungs[earned.count].threshold > counter, "\(category)")
        }
        #expect(LeafEngine().newUnlocks(counters: snapshot.counters, existing: snapshot.unlocks, at: now, season: .autumn).isEmpty)
        let context = CollectionContext(schedule: .standard, features: shipped, calendar: utc, hemisphere: .northern)
        #expect(snapshot.currentRun(at: at(2026, 10, 23, 15), context: context) == 11)
    }

    @Test("A history with nothing in it earns no focus leaf and keeps an empty book")
    func nothing() {
        let empty = DemoData.FocusHistory(today: today, secondsBeforeToday: 0, runThroughYesterday: 0, bestRun: 0)
        let snapshot = DemoData.snapshot(species: 23, tendedDays: 41, waiting: 0, now: at(2026, 10, 23, 9), calendar: utc,
                                         hemisphere: .northern, features: shipped, focusHistory: empty)
        let focus: Set<RewardCategoryID> = [.hoursSaved, .sessionsFinished, .focusStreak]
        #expect(!snapshot.unlocks.contains { unlock in
            RewardCatalog.shared.reward(forSpecies: unlock.speciesID).map { focus.contains($0.categoryID) } ?? false
        })
        #expect(focus.allSatisfy { snapshot.counters[$0] == nil })
        #expect(snapshot.focus.days.isEmpty)
        #expect(snapshot.focus.totalSeconds == 0)
        #expect(snapshot.focus.bestRun == 0)
        #expect(snapshot.hasPlantedMaple)
    }
}
#endif
