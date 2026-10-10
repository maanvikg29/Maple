import Foundation
import Testing
@testable import MapleCore

private let seeds: [UInt64] = [0x00C0_FFEE_0A1E_5EED, 1, 42, 7, 2026]
private let speciesIDs = LeafCatalog.shared.species.map(\.id)
private let growths = stride(from: 0.0, through: 1.0, by: 0.05).map { $0 }

private func ids(_ count: Int) -> [String] {
    Array(speciesIDs.prefix(count))
}

/// The committed, every-feature member from docs/design/rewards.md ("Pacing"): species by tended day.
private func pacedSpecies(day: Int, speedUp: Double = 1) -> Int {
    let points: [(Double, Double)] = [(0, 1), (1, 4), (7, 11), (30, 32), (180, 89), (365, 124), (639, 155), (10_000, 155)]
    let d = Double(day) * speedUp
    for k in 1..<points.count where d <= points[k].0 {
        let (d0, n0) = points[k - 1], (d1, n1) = points[k]
        return min(155, Int((n0 + (n1 - n0) * (d - d0) / (d1 - d0)).rounded()))
    }
    return 155
}

@Suite("Tree layout")
struct TreeLayoutTests {
    @Test("The same inputs always give the same tree; another seed gives another tree")
    func determinism() {
        for seed in seeds {
            let a = TreeLayout.generate(seed: seed, growth: 0.42, species: ids(37), buds: [TreeBudRequest(speciesID: "rubrum", progress: 0.5)], featured: ids(3)[2])
            let b = TreeLayout.generate(seed: seed, growth: 0.42, species: ids(37), buds: [TreeBudRequest(speciesID: "rubrum", progress: 0.5)], featured: ids(3)[2])
            #expect(a == b)
        }
        let first = TreeLayout.generate(seed: 1, growth: 0.6, species: ids(20))
        let second = TreeLayout.generate(seed: 2, growth: 0.6, species: ids(20))
        #expect(first.segments != second.segments)
    }

    @Test("SplitMix64 matches the reference sequence")
    func splitMix() {
        var rng = SplitMix64(seed: 1234567)
        #expect(rng.next() == 6_457_827_717_110_365_317)
        #expect(rng.next() == 3_203_168_211_198_807_973)
        var unit = SplitMix64(seed: 9)
        for _ in 0..<1000 {
            let x = unit.unit()
            #expect(x >= 0 && x < 1)
        }
    }

    @Test("As growth rises, segments only appear, lengthen and thicken; topology never changes", arguments: seeds)
    func monotonicGrowth(seed: UInt64) {
        var previous: [Int: TreeSkeleton.Segment] = [:]
        var previousTrunk = 0.0
        for g in growths {
            let skeleton = TreeLayout.generate(seed: seed, growth: g, species: ids(10))
            let current = Dictionary(uniqueKeysWithValues: skeleton.segments.map { ($0.node, $0) })
            for (node, before) in previous {
                guard let after = current[node] else {
                    Issue.record("segment \(node) disappeared at g \(g)")
                    continue
                }
                #expect(after.parentNode == before.parentNode)
                #expect(after.depth == before.depth)
                #expect(after.length >= before.length - 1e-9, "segment \(node) shortened at g \(g)")
                #expect(after.tipWidth >= before.tipWidth - 1e-9, "segment \(node) thinned at g \(g)")
                #expect(after.emergence >= before.emergence - 1e-12)
            }
            #expect(skeleton.trunkBaseWidth >= previousTrunk - 1e-9)
            previousTrunk = skeleton.trunkBaseWidth
            previous = current
        }
        let mature = TreeLayout.generate(seed: seed, growth: 1, species: ids(10))
        #expect(mature.segments.allSatisfy { $0.emergence == 1 })
    }

    @Test("The trunk forks low into two or three leaders, and depths run from 1 to at most 8", arguments: seeds)
    func construction(seed: UInt64) {
        let skeleton = TreeLayout.generate(seed: seed, growth: 1, species: ids(1))
        let leaders = skeleton.branches.filter { $0.depth == 2 }
        #expect((2...3).contains(leaders.count))
        let trunks = skeleton.branches.filter { $0.depth == 1 }
        #expect(trunks.count == 1)
        let trunkTop = trunks.first?.points.last?.y ?? 0
        #expect(trunkTop / skeleton.height > 0.22 && trunkTop / skeleton.height < 0.34, "fork at \(trunkTop / skeleton.height) of the height")
        #expect(skeleton.segments.allSatisfy { (1...8).contains($0.depth) })
        #expect(abs(skeleton.trunkBaseWidth - 22) < 0.01)
    }

    @Test("Height, crown width and trunk follow spec §4.3", arguments: seeds)
    func size(seed: UInt64) {
        for g in [0.0, 0.18, 0.46, 0.79, 1.0] {
            let skeleton = TreeLayout.generate(seed: seed, growth: g, species: ids(max(1, Int(155 * g))))
            let target = TreeLayout.targetSize(growth: g)
            #expect(abs(skeleton.height - target.height) / target.height < 0.1, "height \(skeleton.height) vs \(target.height) at g \(g)")
            // Width is looser: a seedling's crown is whatever its first twigs span (about 85–110 pt), and the
            // horizontal scale may only grow, so it is not stretched to fit.
            #expect(abs(skeleton.width - target.width) / target.width < 0.25, "width \(skeleton.width) vs \(target.width) at g \(g)")
            #expect(skeleton.crownCentroid.y > 0.35 * skeleton.height && skeleton.crownCentroid.y < 0.85 * skeleton.height)
        }
    }

    @Test("Primary slots never move when more species are added, at any growth", arguments: seeds)
    func slotStability(seed: UInt64) {
        for g in [0.0, 0.2, 0.5, 1.0] {
            let fewer = TreeLayout.generate(seed: seed, growth: g, species: ids(20))
            let more = TreeLayout.generate(seed: seed, growth: g, species: ids(60))
            for id in ids(20) {
                #expect(fewer.primaryTips[id] == more.primaryTips[id])
                let before = fewer.rosettes.first { $0.speciesID == id && $0.kind == .primary }
                let after = more.rosettes.first { $0.speciesID == id && $0.kind == .primary }
                #expect(before?.anchor == after?.anchor, "\(id) moved at g \(g)")
                #expect(before?.tipID == after?.tipID)
            }
        }
        // The permanent twig is the same at every growth.
        let early = TreeLayout.generate(seed: seed, growth: 0.1, species: ids(30))
        let late = TreeLayout.generate(seed: seed, growth: 0.9, species: ids(30))
        #expect(early.primaryTips == late.primaryTips)
    }

    @Test("Early species each get their own twig end; primary twigs are distinct while tips allow", arguments: seeds)
    func distinctPrimaries(seed: UInt64) {
        let skeleton = TreeLayout.generate(seed: seed, growth: 0.0, species: ids(8))
        let primaries = skeleton.rosettes.filter { $0.kind == .primary }
        #expect(Set(primaries.compactMap(\.tipID)).count == primaries.count)
        #expect(primaries.allSatisfy { $0.shareRank == 0 })
    }

    @Test("Capacity: tips × 3 ≥ species + 3 throughout the pacing simulation", arguments: seeds)
    func capacity(seed: UInt64) {
        for speedUp in [1.0, 1.5] {
            for day in stride(from: 0, through: 640, by: 5) {
                let g = TreeGrowth.structure(tendedDays: day)
                let n = pacedSpecies(day: day, speedUp: speedUp)
                let skeleton = TreeLayout.generate(seed: seed, growth: g, species: ids(n))
                #expect(skeleton.tips.count * 3 >= n + 3, "day \(day): \(skeleton.tips.count) tips for \(n) species")
            }
        }
        let grand = TreeLayout.generate(seed: seed, growth: 1, species: ids(155))
        #expect(grand.tips.count * 3 >= 158)
        #expect(grand.tips.count >= 120, "a grand maple has a twig end for nearly every species")
    }

    @Test("Leaf instances follow TreeGrowth.leafInstances, split floor(T / n) with the remainder to the earliest")
    func instanceBudget() {
        for seed in seeds.prefix(3) {
            for (n, g) in [(1, 0.0), (5, 0.05), (10, 0.08), (15, 0.14), (40, 0.34), (50, 0.46), (90, 0.7), (155, 1.0), (155, 0.6), (3, 0.9)] {
                let skeleton = TreeLayout.generate(seed: seed, growth: g, species: ids(n), featured: ids(1)[0])
                let total = TreeGrowth.leafInstances(species: n, growth: g)
                let regular = skeleton.rosettes.filter { $0.kind != .featured }
                let counted = regular.reduce(0) { $0 + $1.leaves.count }
                #expect(counted == total, "n \(n) g \(g): \(counted) leaves, expected \(total)")
                for (index, id) in ids(n).enumerated() {
                    let own = regular.filter { $0.speciesID == id }.reduce(0) { $0 + $1.leaves.count }
                    #expect(own == total / n + (index < total % n ? 1 : 0))
                    #expect(own >= 3)
                }
                #expect(regular.allSatisfy { (3...6).contains($0.leaves.count) || $0.leaves.count == total / n })
                let featured = skeleton.rosettes.filter { $0.kind == .featured }
                #expect(featured.count == 1 && featured.first?.leaves.count == 3)
                #expect(skeleton.leaves.count == counted + 3)
            }
        }
    }

    @Test("The seedling: one species dressed in five rosettes of about 18 pt leaves, with three buds")
    func seedling() {
        let skeleton = TreeLayout.generate(
            seed: seeds[0], growth: 0, species: ids(1),
            buds: [TreeBudRequest(speciesID: "a", progress: 0.6), TreeBudRequest(speciesID: "b", progress: 0.2), TreeBudRequest(speciesID: "c", progress: 0)]
        )
        #expect(skeleton.rosettes.count == 5)
        #expect(skeleton.leaves.count == 24)
        #expect(abs(skeleton.leafSize - 18) < 0.01)
        #expect(skeleton.buds.count == 3)
        #expect(skeleton.buds.filter(\.isNext).count == 1)
        #expect(skeleton.buds.first?.isNext == true)
        // Rosettes spread over the sapling instead of clumping on one twig.
        let anchors = skeleton.rosettes.map(\.anchor)
        for (i, a) in anchors.enumerated() {
            for b in anchors.dropFirst(i + 1) {
                #expect(a.distance(to: b) > 8)
            }
        }
    }

    @Test("A waiting bud hangs at the twig its species will own once opened", arguments: seeds)
    func waitingBud(seed: UInt64) {
        for g in [0.0, 0.3, 0.8] {
            let waitingID = ids(13)[12]
            let before = TreeLayout.generate(seed: seed, growth: g, species: ids(12), waiting: [waitingID])
            let after = TreeLayout.generate(seed: seed, growth: g, species: ids(13))
            let bud = before.buds.first { $0.isWaiting }
            let placed = after.rosettes.first { $0.speciesID == waitingID && $0.kind == .primary }
            #expect(bud?.speciesID == waitingID)
            #expect(bud?.tipID == placed?.tipID)
            #expect(before.leaves.allSatisfy { $0.speciesID != waitingID })
        }
    }

    @Test("Leaves fan up and out, never hanging down, and shrink from 18 to 11 pt with growth")
    func leafPose() {
        for g in [0.0, 0.5, 1.0] {
            let skeleton = TreeLayout.generate(seed: seeds[1], growth: g, species: ids(60))
            #expect(skeleton.leaves.allSatisfy { abs($0.rotation) <= 2.0 + 1e-9 })
            let expected = 18 + (11 - 18) * g
            #expect(skeleton.leaves.allSatisfy { $0.size >= expected * 0.85 - 1e-9 && $0.size <= expected * 1.15 + 1e-9 })
        }
    }

    @Test("Most rosettes sit on the crown's outer shell", arguments: seeds)
    func shell(seed: UInt64) {
        let skeleton = TreeLayout.generate(seed: seed, growth: 1, species: ids(155))
        let inner = Double(skeleton.rosettes.filter(\.isInner).count) / Double(skeleton.rosettes.count)
        #expect(inner > 0.05 && inner < 0.45, "inner share \(inner)")
    }

    @Test("Before the first leaf there are no leaves, but buds still hang")
    func empty() {
        let skeleton = TreeLayout.generate(seed: 5, growth: 0, species: [], buds: [TreeBudRequest(speciesID: "rubrum", progress: 0.3)], waiting: ["saccharum"])
        #expect(skeleton.leaves.isEmpty && skeleton.rosettes.isEmpty)
        #expect(skeleton.buds.count == 2)
        #expect(!skeleton.tips.isEmpty)
    }

    @Test("Duplicate and out-of-range inputs are handled")
    func robustness() {
        let skeleton = TreeLayout.generate(seed: 3, growth: 7, species: ["rubrum", "rubrum", "saccharum"], buds: [TreeBudRequest(speciesID: "rubrum", progress: 4)], featured: "unknown")
        #expect(skeleton.growth == 1)
        #expect(Set(skeleton.rosettes.map(\.speciesID)) == ["rubrum", "saccharum"])
        #expect(skeleton.buds.isEmpty, "a placed species is never also a bud")
        let negative = TreeLayout.generate(seed: 3, growth: -.infinity, species: ["rubrum"])
        #expect(negative.growth == 0)
    }
}

@Suite("Tree foliage")
struct TreeFoliageTests {
    private let catalog = LeafCatalog.shared

    @Test("Autumn: each deciduous species turns on its own seeded day within the first 21 days")
    func autumnTurning() throws {
        let deciduous = catalog.species.filter { !$0.evergreen && $0.autumn != .staysGreen }
        var days = Set<Int>()
        for species in deciduous {
            let day = TreeFoliage.turnDay(species, seed: 9)
            #expect((0..<21).contains(day))
            days.insert(day)
            let early = TreeFoliage.tone(for: species, season: .autumn, seasonDay: 0, seed: 9).fill
            let late = TreeFoliage.tone(for: species, season: .autumn, seasonDay: 30, seed: 9).fill
            #expect(late == species.autumnColor)
            if day >= 2 {
                #expect(early == LeafColourway.summer.color(for: species))
            }
        }
        #expect(days.count > 10, "turning days are spread out")
        let evergreen = try #require(catalog.species.first { $0.evergreen })
        #expect(TreeFoliage.tone(for: evergreen, season: .autumn, seasonDay: 30, seed: 9).fill == LeafColourway.autumn.color(for: evergreen))
    }

    @Test("Winter: deciduous leaves frost (with a rim) over the first 10 days; evergreens stay deep green")
    func winter() throws {
        let rubrum = try #require(catalog.species(id: "rubrum"))
        let frosted = TreeFoliage.tone(for: rubrum, season: .winter, seasonDay: 20, seed: 4)
        #expect(frosted.fill == rubrum.autumnColor.mixed(with: LeafColor(0xC9DCE8), amount: 0.6))
        #expect(abs(frosted.frostRim - 0.4) < 1e-9)
        #expect((0..<10).contains(TreeFoliage.frostDay(rubrum, seed: 4)))
        let evergreen = try #require(catalog.species.first { $0.evergreen })
        let deep = TreeFoliage.tone(for: evergreen, season: .winter, seasonDay: 20, seed: 4)
        #expect(deep.frostRim == 0.25)
        #expect(deep.fill.hsl.lightness < evergreen.summerColor.hsl.lightness)
    }

    @Test("Spring and summer use the spring and summer colourways")
    func springSummer() throws {
        let rubrum = try #require(catalog.species(id: "rubrum"))
        #expect(TreeFoliage.tone(for: rubrum, season: .spring, seasonDay: 3, seed: 1).fill == LeafColourway.spring.color(for: rubrum))
        #expect(TreeFoliage.tone(for: rubrum, season: .summer, seasonDay: 3, seed: 1).fill == LeafColourway.summer.color(for: rubrum))
    }

    @Test("Season day counts from the first of the season's first month, in both hemispheres")
    func seasonDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        func date(_ y: Int, _ m: Int, _ d: Int) throws -> Date {
            try #require(calendar.date(from: DateComponents(year: y, month: m, day: d)))
        }
        #expect(TreeFoliage.seasonDay(for: try date(2026, 10, 10), hemisphere: .northern, calendar: calendar) == 39)
        #expect(TreeFoliage.seasonDay(for: try date(2026, 9, 1), hemisphere: .northern, calendar: calendar) == 0)
        #expect(TreeFoliage.seasonDay(for: try date(2027, 1, 5), hemisphere: .northern, calendar: calendar) == 35)
        #expect(TreeFoliage.seasonDay(for: try date(2026, 10, 10), hemisphere: .southern, calendar: calendar) == 39)
        #expect(TreeFoliage.seasonDay(for: try date(2026, 7, 2), hemisphere: .southern, calendar: calendar) == 31)
    }
}
