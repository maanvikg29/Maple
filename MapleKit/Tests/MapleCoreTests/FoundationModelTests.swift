import Foundation
import Testing
@testable import MapleCore

@Suite("Leaf colourways")
struct LeafColourwayTests {
    private let catalog = LeafCatalog.shared

    @Test("Pressed colourway follows the season earned; evergreens stay green")
    func pressed() {
        #expect(LeafColourway.pressed(in: .spring, evergreen: false) == .spring)
        #expect(LeafColourway.pressed(in: .summer, evergreen: false) == .summer)
        #expect(LeafColourway.pressed(in: .autumn, evergreen: false) == .autumn)
        #expect(LeafColourway.pressed(in: .winter, evergreen: false) == .frost)
        for season in Season.allCases {
            #expect(LeafColourway.pressed(in: season, evergreen: true) == .summer)
        }
    }

    @Test("Autumn uses the species' autumn code; spring and frost are blends")
    func colours() throws {
        let rubrum = try #require(catalog.species(id: "rubrum"))
        #expect(LeafColourway.autumn.color(for: rubrum) == rubrum.autumnColor)
        let spring = LeafColourway.spring.color(for: rubrum)
        #expect(spring == rubrum.summerColor.mixed(with: LeafColor(0xD8E8B0), amount: 0.25))
        #expect(LeafColourway.frost.hasFrostRim(for: rubrum))
        let firstEvergreen = catalog.species.first { $0.evergreen }
        let evergreen = try #require(firstEvergreen)
        #expect(!LeafColourway.frost.hasFrostRim(for: evergreen))
        #expect(LeafColourway.frost.color(for: evergreen) == evergreen.summerColor)
    }

    @Test("Colour maths round-trips and stays in range")
    func maths() {
        let colour = LeafColor(0x3A8F3E)
        let (h, s, l) = colour.hsl
        #expect(LeafColor(hue: h, saturation: s, lightness: l).isClose(to: colour, tolerance: 1))
        #expect(colour.lightened(by: 0.06).hsl.lightness > l)
        #expect(LeafColor(0xFFFFFF).lightened(by: 0.5) == LeafColor(0xFFFFFF))
        #expect(LeafColor(0x000000).mixed(with: LeafColor(0xFFFFFF), amount: 0.5).isClose(to: LeafColor(0x808080), tolerance: 1))
        #expect(colour.desaturated(by: 1).hsl.saturation < 0.01)
    }
}

@Suite("Tree growth")
struct TreeGrowthTests {
    @Test("Structure follows the spec's curve", arguments: [
        (1, 0.023), (30, 0.18), (90, 0.34), (180, 0.52), (365, 0.79), (540, 1.0),
    ])
    func curve(days: Int, expected: Double) {
        #expect(abs(TreeGrowth.structure(tendedDays: days) - expected) < 0.006)
    }

    @Test("Structure never decreases and is capped at 1")
    func monotonic() {
        var previous = TreeGrowth.structure(tendedDays: 0)
        #expect(previous == 0)
        for day in 1...800 {
            let g = TreeGrowth.structure(tendedDays: day)
            #expect(g >= previous)
            #expect(g <= 1)
            previous = g
        }
    }

    @Test("Leaf instances match the spec's examples")
    func examples() {
        #expect(TreeGrowth.leafInstances(species: 0, growth: 0) == 0)
        #expect(TreeGrowth.leafInstances(species: 1, growth: 0) == 24)
        #expect(TreeGrowth.leafInstances(species: 10, growth: 0.08) == 60)
        #expect(TreeGrowth.leafInstances(species: 155, growth: 1) == 465)
    }

    @Test("Leaf instances never decrease and always show 3 per species")
    func leafBudget() {
        for species in 1...155 {
            var previous = 0
            for step in 0...20 {
                let total = TreeGrowth.leafInstances(species: species, growth: Double(step) / 20)
                #expect(total >= previous)
                #expect(total >= 3 * species)
                #expect(total <= TreeGrowth.maxLeafInstances)
                previous = total
            }
            if species > 1 {
                #expect(TreeGrowth.leafInstances(species: species, growth: 0.5) >= TreeGrowth.leafInstances(species: species - 1, growth: 0.5))
            }
        }
    }

    @Test("Stage names follow species collected", arguments: [
        (0, TreeStage.seed), (1, .seedling), (4, .seedling), (5, .sapling), (19, .sapling), (20, .youngMaple),
        (49, .youngMaple), (50, .spreadingMaple), (99, .spreadingMaple), (100, .oldMaple), (154, .oldMaple), (155, .grandMaple),
    ])
    func stages(count: Int, stage: TreeStage) {
        #expect(TreeStage(speciesCount: count) == stage)
    }
}

@Suite("Sleep schedule")
struct SleepScheduleTests {
    @Test("Wind-down start wraps around midnight")
    func windDown() {
        #expect(SleepSchedule.standard.windDownStart == ClockTime(hour: 22, minute: 15))
        let early = SleepSchedule(bedtime: ClockTime(hour: 0, minute: 20), wake: ClockTime(hour: 8), windDownMinutes: 45)
        #expect(early.windDownStart == ClockTime(hour: 23, minute: 35))
    }

    @Test("Time in bed spans midnight")
    func inBed() {
        #expect(SleepSchedule.standard.minutesInBed == 8 * 60)
    }

    @Test("Progress clamps to its threshold")
    func progress() {
        let progress = LeafProgress(speciesID: "x", category: .restedNights, threshold: 3, tier: .common, current: 5,
                                    availability: .available, state: .locked, estimatedDays: nil)
        #expect(progress.fraction == 1)
        #expect(progress.remaining == 0)
    }
}
