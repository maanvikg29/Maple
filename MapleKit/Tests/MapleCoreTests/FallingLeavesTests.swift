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
        #expect((6 ... 13).contains(cycle))
        // Find a moment early in a fall, then look a second later.
        var start = 100.0
        while FallingLeaves.leaves(at: start, count: 1)[0].fall > 0.2 { start += 0.25 }
        let early = FallingLeaves.leaves(at: start, count: 1)[0]
        let later = FallingLeaves.leaves(at: start + 1, count: 1)[0]
        #expect(later.fall > early.fall)
        // One whole fall later it is a new leaf, starting from another place.
        let next = FallingLeaves.leaves(at: start + cycle, count: 1)[0]
        #expect(abs(next.fall - early.fall) < 0.001)
        #expect(next.x != early.x)
        #expect(first.x.isFinite)
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
