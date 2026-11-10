import Foundation
import Testing
@testable import MapleCore

@Suite("Reward catalogue")
struct RewardCatalogTests {
    private let rewards = RewardCatalog.shared

    private let hours: [Double] = [1, 2, 3, 5, 7, 10, 13, 16, 20, 24, 28, 32, 36, 40, 45, 50, 55, 60, 65, 70, 75, 80, 85, 90, 95, 100,
        110, 120, 130, 140, 150, 160, 168, 180, 190, 200, 210, 220, 230, 240, 250, 265, 280, 295, 310, 325, 340, 355, 370, 385,
        400, 420, 440, 460, 480, 500, 520, 540, 560, 580, 600, 620, 640, 660, 680, 700, 720, 740, 760, 780, 800, 825, 850, 875,
        900, 925, 950, 975, 1000, 1025, 1050, 1075, 1100, 1125, 1150, 1175, 1200, 1225, 1250, 1275, 1300, 1325, 1350, 1375,
        1400, 1425, 1450, 1475, 1500, 1530, 1560, 1590, 1620, 1650, 1680, 1710, 1740, 1770, 1800, 1840, 1880, 1920, 1960, 2000]

    @Test("Seven ladders, exactly as the focus spec sets them")
    func ladders() {
        let catalog = RewardCatalog.shared
        #expect(catalog.categories.map(\.id) == [.firstLeaf, .hoursSaved, .sessionsFinished, .focusStreak, .phoneFreeMornings, .bedtimeKept, .restedNights])
        #expect(catalog.category(.hoursSaved)?.ladder == hours)
        #expect(hours.count == 114)
        #expect(catalog.category(.sessionsFinished)?.ladder == [1, 10, 25, 50, 100, 250, 500, 1000])
        #expect(catalog.category(.focusStreak)?.ladder == [3, 7, 14, 30, 50, 75, 100, 150, 250, 365])
        #expect(catalog.category(.phoneFreeMornings)?.ladder == [1, 7, 25, 50, 100, 200, 365])
        #expect(catalog.category(.bedtimeKept)?.ladder == [1, 7, 25, 50, 100, 200, 365])
        #expect(catalog.category(.restedNights)?.ladder == [3, 14, 30, 60, 100, 175, 250, 365])
        for category in catalog.categories {
            #expect(catalog.rungs(in: category.id).map(\.threshold) == category.ladder, "\(category.id)")
        }
    }

    @Test("Every species is exactly one rung")
    func everySpeciesOnce() {
        let catalog = RewardCatalog.shared
        #expect(catalog.assignments.count == 155)
        #expect(Set(catalog.assignments.map(\.speciesID)) == Set(LeafCatalog.shared.species.map(\.id)))
        #expect(Set(catalog.assignments.map { "\($0.categoryID.rawValue)/\($0.threshold)" }).count == 155)
    }

    @Test("Famous maples on early and landmark rungs; the Sugar maple is the first leaf")
    func pins() {
        func at(_ category: RewardCategoryID, _ threshold: Double) -> String? {
            RewardCatalog.shared.rungs(in: category).first { $0.threshold == threshold }?.speciesID
        }
        #expect(at(.firstLeaf, 1) == "saccharum")
        #expect(at(.hoursSaved, 1) == "rubrum")
        #expect(at(.hoursSaved, 24) == "palmatum")
        #expect(at(.hoursSaved, 168) == "griseum")
        #expect(at(.hoursSaved, 720) == "japonicum")
        #expect(at(.sessionsFinished, 1) == "buergerianum")
        #expect(at(.restedNights, 3) == "saccharinum")
        #expect(RewardCatalog.shared.rungs(in: .hoursSaved).first { $0.threshold == 24 }?.unlockText == "Save 24 hours · A day back")
        #expect(RewardCatalog.shared.rungs(in: .hoursSaved).last?.unlockText == "Save 2,000 hours · A working year back")
    }

    @Test("The hardest rungs hold the most threatened maples")
    func threatenedOnTop() {
        let catalog = RewardCatalog.shared, species = LeafCatalog.shared
        func severity(_ id: String) -> Int {
            switch species.species(id: id)?.conservation?.category {
            case .cr: 0
            case .en: 1
            case .vu: 2
            default: 3
            }
        }
        let secondary: [RewardCategoryID] = [.sessionsFinished, .focusStreak, .phoneFreeMornings, .bedtimeKept, .restedNights]
        let top = Array(catalog.rungs(in: .hoursSaved).suffix(10)) + secondary.compactMap { catalog.rungs(in: $0).last }
        let threatenedCount = species.species.filter { $0.conservation?.category.isThreatened == true }.count
        let onTop = top.filter { severity($0.speciesID) < 3 }.count
        // Every top rung is threatened while there are enough; otherwise every threatened maple is on a top rung.
        #expect(onTop == min(top.count, threatenedCount))
        // Harder rung, never a less threatened leaf than an easier top rung.
        func days(_ rung: RewardAssignment) -> Double { rung.threshold / RewardCategoryInfo(rung.categoryID).designPace }
        // Hardest first; equal days go by category order, as the generator breaks ties.
        let ordered = top.sorted { a, b in
            days(a) != days(b) ? days(a) > days(b) : RewardCategoryInfo(a.categoryID).order < RewardCategoryInfo(b.categoryID).order
        }
        let severities = ordered.map { severity($0.speciesID) }
        #expect(severities == severities.sorted())
    }

    @Test("Evergreens on the consistency ladders; u-confidence maples never early")
    func placementRules() {
        let catalog = RewardCatalog.shared, species = LeafCatalog.shared
        // The hardest rungs go to the most threatened maples first; every other documented or inferred evergreen
        // sits on a consistency ladder. There are fewer free evergreens than consistency rungs, so the rest of those
        // rungs take the general order.
        let consistency: [RewardCategoryID] = [.focusStreak, .phoneFreeMornings, .bedtimeKept]
        let secondary: [RewardCategoryID] = [.sessionsFinished, .focusStreak, .phoneFreeMornings, .bedtimeKept, .restedNights]
        let top = Set(catalog.rungs(in: .hoursSaved).suffix(10).map(\.speciesID) + secondary.compactMap { catalog.rungs(in: $0).last?.speciesID })
        for leaf in species.species where leaf.evergreen && leaf.confidence != .placeholder && !top.contains(leaf.id) {
            let category = catalog.reward(forSpecies: leaf.id)?.categoryID
            #expect(category.map(consistency.contains) == true, "\(leaf.id)")
        }
        for rung in catalog.assignments where species.species(id: rung.speciesID)?.confidence == .placeholder {
            #expect(rung.tier != .firstSteps && rung.tier != .common, "\(rung.speciesID)")
        }
    }

    @Test("Tiers follow the design pace: 8, 45 and 180 days, and a year for a ladder's top")
    func tiers() {
        for rung in RewardCatalog.shared.assignments {
            let info = RewardCategoryInfo(rung.categoryID)
            let days = rung.categoryID == .firstLeaf ? 0 : rung.threshold / info.designPace
            let top = RewardCatalog.shared.category(rung.categoryID)?.ladder.last == rung.threshold
            let expected: RewardTier = rung.categoryID == .firstLeaf ? .firstSteps
                : top && days > 365 ? .legendary
                : days <= 8 ? .firstSteps : days <= 45 ? .common : days <= 180 ? .uncommon : .rare
            #expect(rung.tier == expected, "\(rung.speciesID)")
        }
    }

    @Test("No two leaves share a milestone")
    func distinctMilestones() {
        let keys = rewards.assignments.map { "\($0.categoryID.rawValue)@\($0.threshold)" }
        #expect(Set(keys).count == keys.count)
    }

    @Test("Sugar maple is the first leaf")
    func firstLeaf() throws {
        let first = try #require(rewards.reward(forSpecies: "saccharum"))
        #expect(first.categoryID == .firstLeaf)
        #expect(first.tier == .firstSteps)
        #expect(rewards.rungs(in: .firstLeaf).map(\.speciesID) == ["saccharum"])
    }

    @Test("Requirements follow the reward table, and no copy says a tap counts")
    func metadata() {
        // Rested nights come from Apple Health only: no manual fallback (D9).
        #expect(RewardCategoryInfo(.restedNights).requirement == .appleHealth)
        #expect(RewardCategoryInfo(.firstLeaf).requirement == RewardRequirement.none)
        for id in rewards.categories.map(\.id) where id != .firstLeaf && id != .restedNights {
            #expect(RewardCategoryInfo(id).requirement == .screenTime, "\(id)")
        }
        for id in RewardCategoryID.allCases {
            #expect(!RewardCategoryInfo(id).definition.localizedCaseInsensitiveContains("goodnight"), "\(id)")
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
