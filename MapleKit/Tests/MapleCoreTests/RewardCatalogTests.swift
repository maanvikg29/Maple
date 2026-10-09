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

    @Test("All 19 categories decode, in canonical order")
    func categories() {
        #expect(rewards.categories.map(\.id) == RewardCategoryID.allCases)
        #expect(rewards.categories.map(\.info.order) == Array(0..<RewardCategoryID.allCases.count))
    }

    @Test("Thresholds strictly increase within a category and match its ladder", arguments: RewardCategoryID.allCases)
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
        #expect(RewardCategoryInfo(.focusHours).timeOfDay == .day)
        #expect(RewardCategoryInfo(.communityChallenges).release == .m9)
        for id in RewardCategoryID.allCases {
            #expect(RewardCategoryInfo(id).designPace > 0)
            #expect(!RewardCategoryInfo(id).definition.isEmpty)
        }
    }
}
