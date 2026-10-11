import Foundation
import Testing
@testable import MapleCore

@Suite("Reward catalogue")
struct RewardCatalogTests {
    private let rewards = RewardCatalog.shared
    private let leaves = LeafCatalog.shared

    @Test("Every species is exactly one reward rung")
    func everySpeciesOnce() {
        let ids = rewards.assignments.map(\.speciesID)
        #expect(ids.count == leaves.species.count)
        #expect(Set(ids) == Set(leaves.species.map(\.id)))
        for species in leaves.species {
            #expect(rewards.reward(forSpecies: species.id) != nil, "\(species.id) has no reward")
        }
    }

    @Test("The table's 19 categories decode, in Herbarium order")
    func categories() {
        let old: [RewardCategoryID] = [
            .firstSteps, .nightsTracked, .onTimeBedtimes, .bedtimeRun, .steadyWeeks, .seasonsInRhythm, .steadyMornings,
            .fullNights, .focusHours, .focusDays, .focusWeeks, .soundWindDowns, .scrollFreeWindDowns, .bedtimeShieldKept,
            .reflectionWeeks, .caffeineCurfew, .windDownRituals, .communityChallenges,
        ]
        #expect(rewards.categories.map(\.id) == [.phoneFreeMornings] + old)
        #expect(rewards.categories.map(\.info.order) == [4] + (20...38).filter { $0 != 33 })
    }

    @Test("Thresholds strictly increase within a category and match its ladder", arguments: RewardCatalog.shared.categories.map(\.id))
    func ladders(category: RewardCategoryID) throws {
        let rungs = rewards.rungs(in: category).map(\.threshold)
        #expect(!rungs.isEmpty)
        #expect(zip(rungs, rungs.dropFirst()).allSatisfy { $0 < $1 }, "\(category): \(rungs)")
        let ladder = try #require(rewards.category(category)).ladder
        #expect(rungs == ladder, "\(category) rungs \(rungs) vs ladder \(ladder)")
    }

    @Test("No two leaves share a milestone")
    func distinctMilestones() {
        let keys = rewards.assignments.map { "\($0.categoryID.rawValue)@\($0.threshold)" }
        #expect(Set(keys).count == keys.count)
    }

    @Test("Sugar maple is the setup leaf")
    func firstSteps() throws {
        let setup = try #require(rewards.reward(forSpecies: "saccharum"))
        #expect(setup.categoryID == .firstSteps)
        #expect(setup.tier == .firstSteps)
        #expect(rewards.rungs(in: .firstSteps).map(\.speciesID) == ["saccharum"])
    }

    @Test("Category copy reads naturally")
    func copy() {
        let onTime = RewardCategoryInfo(.onTimeBedtimes)
        #expect(onTime.shortRule(14) == "14 on time")
        #expect(onTime.earnedLine(14) == "For 14 on-time bedtimes")
        #expect(onTime.earnedLine(1) == "For your first on-time bedtime")
        #expect(RewardCategoryInfo(.nightsTracked).shortRule(1) == "1 night")
        #expect(RewardCategoryInfo(.nightsTracked).shortRule(3) == "3 nights")
        #expect(RewardCategoryInfo(.bedtimeRun).earnedLine(7) == "For a 7-night run")
        #expect(RewardCategoryInfo(.focusHours).shortRule(18) == "18h focus")
    }

    @Test("Requirements and releases follow the reward table")
    func metadata() {
        #expect(RewardCategoryInfo(.scrollFreeWindDowns).requirement == .screenTime)
        #expect(RewardCategoryInfo(.scrollFreeWindDowns).release == .m3)
        #expect(RewardCategoryInfo(.fullNights).requirement == .sleepTracker)
        // Every other M1 sleep category comes from Apple Health only: no manual fallback (D9).
        for id in [RewardCategoryID.nightsTracked, .onTimeBedtimes, .bedtimeRun, .steadyWeeks, .seasonsInRhythm, .steadyMornings] {
            #expect(RewardCategoryInfo(id).requirement == .appleHealth, "\(id)")
        }
        #expect(RewardCategoryInfo(.firstSteps).requirement == RewardRequirement.none)
        #expect(RewardCategoryInfo(.nightsTracked).definition == "A night counts when Apple Health has your sleep.")
        #expect(RewardCategoryInfo(.onTimeBedtimes).definition == "Asleep no later than 30 minutes after your bedtime.")
        // No copy says a tap counts.
        for id in RewardCategoryID.allCases {
            #expect(!RewardCategoryInfo(id).definition.localizedCaseInsensitiveContains("goodnight"), "\(id)")
        }
        #expect(RewardCategoryInfo(.focusHours).timeOfDay == .day)
        #expect(RewardCategoryInfo(.communityChallenges).release == .m9)
        for id in RewardCategoryID.allCases {
            #expect(RewardCategoryInfo(id).designPace > 0)
            #expect(!RewardCategoryInfo(id).definition.isEmpty)
        }
    }
}

@Suite("Conservation data")
struct ConservationTests {
    @Test("Assessed species carry their IUCN category, year and source; the rest have none")
    func decoded() throws {
        let assessed = LeafCatalog.shared.species.filter { $0.conservation != nil }
        #expect(!assessed.isEmpty)
        for species in assessed {
            let status = try #require(species.conservation)
            #expect(status.year >= 1990 && status.year <= 2026, "\(species.id)")
            #expect(status.source.hasPrefix("https://"), "\(species.id)")
        }
        #expect(LeafCatalog.shared.species.contains { $0.conservation?.category.isThreatened == true })
    }

    @Test("Threatened means Critically endangered, Endangered or Vulnerable")
    func threatened() {
        #expect(RedListCategory.allCases.filter(\.isThreatened) == [.cr, .en, .vu])
        #expect(RedListCategory.cr.displayName == "Critically endangered")
        #expect(RedListCategory.en.displayName == "Endangered")
        #expect(RedListCategory.vu.displayName == "Vulnerable")
    }
}

@Suite("Focus categories")
struct FocusCategoryTests {
    private let focus: [RewardCategoryID] = [.firstLeaf, .hoursSaved, .sessionsFinished, .focusStreak, .phoneFreeMornings, .bedtimeKept, .restedNights]

    @Test("The seven focus categories, in Herbarium order, with their needs and releases")
    func info() {
        #expect(focus.map { RewardCategoryInfo($0).order } == [0, 1, 2, 3, 4, 5, 6])
        #expect(focus.map { RewardCategoryInfo($0).requirement } == [.none, .screenTime, .screenTime, .screenTime, .screenTime, .screenTime, .appleHealth])
        #expect(focus.map { RewardCategoryInfo($0).release } == [.m1, .f1, .f1, .f1, .f2, .f2, .m1])
        #expect(focus.map { RewardCategoryInfo($0).designPace } == [1, 1.9, 1, 0.8, 0.5, 0.5, 0.6])
        #expect(RewardCategoryInfo(.hoursSaved).definition == "Time your chosen apps stayed locked while you were awake.")
        #expect(RewardCategoryInfo(.hoursSaved).shortRule(24) == "24h saved")
        #expect(RewardCategoryInfo(.hoursSaved).earnedLine(1) == "For your first hour saved")
        #expect(RewardCategoryInfo(.sessionsFinished).earnedLine(10) == "For 10 finished sessions")
        #expect(RewardCategoryInfo(.focusStreak).shortRule(7) == "7-day streak")
        #expect(RewardCategoryInfo(.restedNights).earnedLine(3) == "For 3 rested nights")
        #expect(RewardCategoryInfo(.firstLeaf).earnedLine(1) == "For planting your maple")
    }

    @Test("Focus and Screen Time ship with F1, sounds with F2; this build ships neither")
    func releases() {
        #expect(!ShippedFeatures.current.focus && !ShippedFeatures.current.screenTime && !ShippedFeatures.current.sleepSounds)
        let f1 = ShippedFeatures(releases: [.m1, .f1])
        #expect(f1.focus && f1.screenTime && !f1.sleepSounds)
        #expect(ShippedFeatures(releases: [.m1, .f1, .f2]).sleepSounds)
        #expect(f1.isShipped(.hoursSaved) && !f1.isShipped(.bedtimeKept))
        #expect(ShippedFeatures.current.isShipped(.restedNights) && ShippedFeatures.current.isShipped(.firstLeaf))
    }

    @Test("Remainders in each category's own words")
    func remainders() {
        func row(_ category: RewardCategoryID, _ current: Double, _ threshold: Double) -> LeafProgress {
            LeafProgress(speciesID: "x", category: category, threshold: threshold, tier: .common, current: current,
                         availability: .available, state: .locked, estimatedDays: 1)
        }
        #expect(LeafRemainder(row(.hoursSaved, 4.5, 8), phase: .day).text == "3h 30m")
        #expect(LeafRemainder(row(.hoursSaved, 6, 8), phase: .day).amount == "6h of 8h")
        #expect(LeafRemainder(row(.sessionsFinished, 7, 10), phase: .day).text == "3 sessions")
        #expect(LeafRemainder(row(.focusStreak, 6, 7), phase: .day).text == "Today")
        #expect(LeafRemainder(row(.restedNights, 2, 3), phase: .evening).text == "Tonight")
        #expect(LeafRemainder(row(.phoneFreeMornings, 3, 7), phase: .day).text == "4 mornings")
        #expect(LeafRemainder(row(.bedtimeKept, 5, 7), phase: .day).text == "2 nights")
    }
}
