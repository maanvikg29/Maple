import Testing
@testable import MapleCore

@Suite("The leaves that fall while a session runs")
struct FallingLeavesTests {
    @Test("The same moment always draws the same leaves, so a redraw never makes them jump")
    func steady() {
        #expect(FallingLeaves.leaves(at: 12.5) == FallingLeaves.leaves(at: 12.5))
        #expect(FallingLeaves.leaves(at: 12.5) != FallingLeaves.leaves(at: 13.5))
        #expect(FallingLeaves.leaves(at: 3, count: 5).count == 5)
        #expect(FallingLeaves.leaves(at: 3, count: 0).isEmpty)
        #expect(FallingLeaves.leaves(at: 3, count: -4).isEmpty)
    }

    @Test("Every leaf stays on the picture: across it, down its fall, one of the three colours, never invisible for long")
    func inRange() {
        for step in 0 ..< 600 {
            for leaf in FallingLeaves.leaves(at: Double(step) * 0.37) {
                #expect((0 ... 1).contains(leaf.x))
                #expect((0 ... 1).contains(leaf.fall))
                #expect((0 ... 1).contains(leaf.opacity))
                #expect((0 ..< 3).contains(leaf.colour))
                #expect((0.6 ... 1.4).contains(leaf.size))
                #expect(leaf.turn.isFinite)
            }
        }
    }

    @Test("A leaf falls: a little later it is lower, until it lands and another starts from the top somewhere else")
    func falls() {
        let first = FallingLeaves.leaves(at: 100, count: 1)[0]
        let cycle = FallingLeaves.seconds(ofLeaf: 0)
        #expect((12 ... 18).contains(cycle))
        // Find a moment early in a fall, then look a second later.
        var start = 100.0
        while FallingLeaves.leaves(at: start, count: 1)[0].fall > 0.2 { start += 0.25 }
        let early = FallingLeaves.leaves(at: start, count: 1)[0]
        let later = FallingLeaves.leaves(at: start + 1, count: 1)[0]
        #expect(later.fall > early.fall)
        // One whole fall later it is a new leaf, as far down its own fall, starting from another place.
        let next = FallingLeaves.leaves(at: start + cycle, count: 1)[0]
        #expect(abs(next.fall - early.fall) < 0.06)
        #expect(next.x != early.x)
        #expect(first.x.isFinite)
    }

    /// One leaf's whole fall, sampled 60 times a second, starting from a moment it is new at the top.
    private func oneFall(_ index: Int, count: Int = FallingLeaves.defaultCount) -> [FallingLeaves.Leaf] {
        let duration = FallingLeaves.seconds(ofLeaf: index)
        var start = 50.0
        while FallingLeaves.leaves(at: start, count: count)[index].fall > 0.01 { start += 1.0 / 60 }
        // Calm air, so only the leaf's own swing moves it sideways.
        while FallingLeaves.gust(at: start) > 0 || FallingLeaves.gust(at: start + duration) > 0 || (0 ..< 20).contains(where: {
            FallingLeaves.gust(at: start + duration * Double($0) / 20) > 0
        }) {
            start += duration
        }
        return stride(from: start, to: start + duration * 0.97, by: 1.0 / 60).map { FallingLeaves.leaves(at: $0, count: count)[index] }
    }

    @Test("A leaf swings side to side as it falls, slowing at each end of its swing, as a real leaf does")
    func swings() {
        for index in 0 ..< FallingLeaves.defaultCount {
            let fall = oneFall(index)
            #expect(fall.map(\.x).max()! - fall.map(\.x).min()! > 0.07)
            // Its speed down the screen at the ends of its swing, where it hardly moves sideways, against its speed
            // through the middle of its swing.
            let steps = zip(fall, fall.dropFirst()).filter { $0.0.fall > 0.15 && $0.1.fall < 0.85 }
            let across = steps.map { abs($0.1.x - $0.0.x) }
            let fastest = across.max()!
            let atEnds = steps.filter { abs($0.1.x - $0.0.x) < fastest * 0.25 }.map { $0.1.fall - $0.0.fall }
            let inMiddle = steps.filter { abs($0.1.x - $0.0.x) > fastest * 0.75 }.map { $0.1.fall - $0.0.fall }
            let mean = { (values: [Double]) in values.reduce(0, +) / Double(max(1, values.count)) }
            #expect(mean(atEnds) < mean(inMiddle) * 0.8)
        }
    }

    @Test("Now and then a gust: it builds, blows for a few seconds and dies away, and the air is calm in between")
    func gusts() {
        let times = stride(from: 0.0, through: 120, by: 1.0 / 30).map { $0 }
        let wind = times.map { FallingLeaves.gust(at: $0) }
        #expect(wind.allSatisfy { $0 >= 0 && $0 <= 1 })
        #expect(wind.max()! > 0.9)
        #expect(Double(wind.filter { $0 == 0 }.count) / Double(wind.count) > 0.5)
        // Several gusts in two minutes, each smooth.
        let starts = zip(wind, wind.dropFirst()).filter { $0.0 == 0 && $0.1 > 0 }.count
        #expect(starts >= 5)
        #expect(zip(wind, wind.dropFirst()).allSatisfy { abs($1 - $0) < 0.05 })
        #expect(FallingLeaves.gust(at: .nan) == 0)
    }

    @Test("A gust carries the falling leaves along with it, and they don't blow back when it dies")
    func carried() throws {
        // The first gust: the wind's push only ever grows while a leaf falls through it.
        let start = try #require(stride(from: 0.0, through: 30, by: 1.0 / 60).first { FallingLeaves.gust(at: $0) > 0 })
        let before = FallingLeaves.drift(at: start - 0.5)
        let during = FallingLeaves.drift(at: start + 1.5)
        let after = FallingLeaves.drift(at: start + 6)
        #expect(during > before)
        #expect(after > during)
        #expect(FallingLeaves.drift(at: start + 8) == after)
    }

    @Test("They fall slowly: every leaf takes 12 to 18 seconds to come down, never quicker")
    func slow() {
        // The owner, 28 Nov 2026: "even generally just slow down the leafs falling too".
        for index in 0 ..< 40 {
            #expect((12 ... 18).contains(FallingLeaves.seconds(ofLeaf: index)))
        }
        // Down the whole picture, a second moves a leaf less than a tenth of the way.
        let fall = (0 ..< 600).map { FallingLeaves.leaves(at: 200 + Double($0) / 60, count: 1)[0].fall }
        let steps = zip(fall, fall.dropFirst()).map { $1 - $0 }.filter { $0 > 0 }
        #expect(steps.allSatisfy { $0 * 60 < 0.16 })
    }

    @Test("They don't all fall together")
    func scattered() {
        let falls = FallingLeaves.leaves(at: 40).map(\.fall)
        #expect((falls.max() ?? 0) - (falls.min() ?? 0) > 0.4)
    }

    @Test("A time that isn't a number, or before the start, still draws")
    func oddTimes() {
        #expect(FallingLeaves.leaves(at: .nan) == FallingLeaves.leaves(at: 0))
        #expect(FallingLeaves.leaves(at: .infinity) == FallingLeaves.leaves(at: 0))
        #expect(FallingLeaves.leaves(at: -50).count == FallingLeaves.defaultCount)
        #expect(FallingLeaves.leaves(at: -50).allSatisfy { (0 ... 1).contains($0.fall) && (0 ... 1).contains($0.x) })
    }

    @Test("Pip's feet land in the fork of the maple, where the picture has it")
    func fork() {
        let feet = VanCanvas.tree.point(x: 440, y: 668, width: 600, height: 1300)
        #expect(feet.x == 220 && feet.y == 334)
    }
}
