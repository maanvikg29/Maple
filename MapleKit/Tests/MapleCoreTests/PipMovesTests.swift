import Foundation
import Testing
@testable import MapleCore

@Suite("Pip's two moments at the tree: the tumble when a session ends early, and the walk back when it finishes")
struct PipMovesTests {
    @Test("The tumble starts where Pip sits and ends on the grass, upright again")
    func fallEnds() {
        let start = PipFall.pose(at: 0)
        #expect(start.x == 0 && start.y == 0 && start.turn == 0 && start.squash == 1)
        let end = PipFall.pose(at: PipFall.seconds)
        #expect(end.x == PipFall.landingX && end.y == PipFall.landingY)
        #expect(end.turn == 0 && end.squash == 1)
        // Before and after its time, and with a time that isn't one, it holds its first or last frame.
        #expect(PipFall.pose(at: -3) == start)
        #expect(PipFall.pose(at: 99) == end)
        #expect(PipFall.pose(at: .nan) == start)
    }

    @Test("He only goes down while he falls, turns over once on the way, and squashes a little as he lands")
    func fallShape() {
        var last = -1.0
        var turned = 0.0
        var squashed = 1.0
        for step in 0 ... 180 {
            let pose = PipFall.pose(at: Double(step) / 100)
            #expect(pose.y >= last - 0.001)
            last = pose.y
            turned = max(turned, abs(pose.turn))
            squashed = min(squashed, pose.squash)
            #expect(pose.y <= PipFall.landingY + 0.001)
        }
        #expect(turned > 3)
        #expect(squashed < 0.95 && squashed > 0.6)
    }

    @Test("The pail's leaves scatter: none before he slips, then all of them out and down onto the grass")
    func scatter() {
        #expect(PipFall.scatter(at: 0).allSatisfy { $0.opacity == 0 })
        let end = PipFall.scatter(at: PipFall.seconds)
        #expect(end.count == PipFall.scatterCount)
        #expect(end.allSatisfy { $0.opacity == 1 && $0.y > PipFall.landingY - 140 && $0.y < PipFall.landingY + 140 })
        #expect(Set(end.map { Int($0.x) }).count == PipFall.scatterCount)
        #expect(PipFall.scatter(at: 0.9) == PipFall.scatter(at: 0.9))
        #expect(end.allSatisfy { (0 ..< 3).contains($0.colour) })
    }

    @Test("The walk starts in the fork, comes down to the grass and goes off to the right, toward the van")
    func walk() {
        let start = PipWalk.pose(at: 0)
        #expect(start.x == 0 && start.y == 0)
        let end = PipWalk.pose(at: PipWalk.seconds)
        // Past the picture's right edge: his middle is 437 across a picture 1200 wide, and he is 372 wide.
        #expect(437 + end.x > 1200 + 186)
        #expect(PipWalk.seconds == 3)
        var last = -1.0
        for step in 0 ... 300 {
            let pose = PipWalk.pose(at: Double(step) / 100)
            #expect(pose.x >= last - 0.001)
            last = pose.x
            // Never under the grass, and upright but for a waddle.
            #expect(pose.y <= PipWalk.groundY + 0.001)
            #expect(abs(pose.turn) < 0.2)
        }
        #expect(abs(PipWalk.pose(at: 2).y - PipWalk.groundY) < 30)
        #expect(PipWalk.pose(at: -1) == start)
        #expect(PipWalk.pose(at: .infinity) == start)
    }
}
