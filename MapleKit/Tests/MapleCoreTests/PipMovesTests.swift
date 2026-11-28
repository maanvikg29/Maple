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
        for step in 0 ... Int(PipFall.seconds * 100) {
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

    @Test("Up again, he sways a little, dazed, and then sits still")
    func dazed() {
        let sway = stride(from: 1.4, through: 2.2, by: 0.01).map { abs(PipFall.pose(at: $0).turn) }
        #expect(sway.max()! > 0.05 && sway.max()! < 0.25)
        #expect(PipFall.pose(at: 2.6).turn == 0)
        #expect(PipFall.pose(at: 2.6).x == PipFall.landingX && PipFall.pose(at: 2.6).y == PipFall.landingY)
    }

    /// Where the pail's middle is, from Pip's seat.
    private func pailMiddle(_ time: Double) -> (x: Double, y: Double) {
        let pail = PipFall.pail(at: time)
        return (PipFall.pailX + pail.x, PipFall.pailY + pail.y)
    }

    @Test("The pail stays in his paw until he slips, then flies off on its own, turns over and lands on its side")
    func pail() {
        #expect(PipFall.pail(at: 0) == .hanging)
        #expect(PipFall.pail(at: .nan) == .hanging)
        // In his paw it keeps its place beside him, whichever way he turns.
        for step in 0 ..< 30 {
            let time = Double(step) / 100
            let pip = PipFall.pose(at: time)
            let middle = pailMiddle(time)
            #expect(abs(hypot(middle.x - pip.x, middle.y - pip.y) - hypot(PipFall.pailX, PipFall.pailY)) < 0.5)
            #expect(abs(PipFall.pail(at: time).turn - pip.turn) < 0.0001)
        }
        // On its way down it is upside down for a moment, so the leaves pour out.
        let turns = stride(from: 0.3, through: 1.3, by: 0.01).map { PipFall.pail(at: $0).turn }
        #expect(turns.contains { cos($0) < -0.95 })
        // It ends on the grass to Pip's right, lying on its side with its mouth toward him, and stays there.
        let end = PipFall.pail(at: PipFall.seconds)
        let middle = pailMiddle(PipFall.seconds)
        #expect(middle.x > PipFall.landingX + 150)
        #expect(middle.y > PipFall.landingY && middle.y < PipFall.groundTop + 120)
        #expect(sin(end.turn) < -0.95)
        #expect(PipFall.pail(at: PipFall.seconds + 4) == end)
        // It is never below the grass.
        for step in 0 ... Int(PipFall.seconds * 100) {
            #expect(pailMiddle(Double(step) / 100).y < PipFall.groundTop + 120)
        }
    }

    @Test("The leaves come out of the pail's mouth as it tips, never before")
    func spillStart() {
        let count = PipFall.spillCount
        #expect(count >= 16)
        #expect(PipFall.spill(at: 0).count == count)
        #expect(PipFall.spill(at: 0.4).allSatisfy { $0.opacity == 0 })
        for index in 0 ..< count {
            // The first moment each one shows, it is at the pail's mouth.
            guard let first = stride(from: 0.0, through: PipFall.seconds, by: 1.0 / 240)
                .first(where: { PipFall.spill(at: $0)[index].opacity > 0 }) else {
                Issue.record("Leaf \(index) never comes out")
                continue
            }
            let leaf = PipFall.spill(at: first)[index]
            let mouth = PipFall.mouth(at: first)
            #expect(hypot(leaf.x - mouth.x, leaf.y - mouth.y) < 45)
        }
    }

    @Test("They flutter down, side to side and tilting, and land scattered over the grass, where they stay")
    func spillFall() {
        let count = PipFall.spillCount
        let times = stride(from: 0.0, through: PipFall.seconds, by: 1.0 / 60).map { $0 }
        var swaying = 0
        for index in 0 ..< count {
            let path = times.map { PipFall.spill(at: $0)[index] }.filter { $0.opacity > 0 }
            // Side to side: its sideways movement changes direction on the way down.
            let steps = zip(path, path.dropFirst()).map { $1.x - $0.x }.filter { abs($0) > 0.01 }
            if zip(steps, steps.dropFirst()).contains(where: { $0 * $1 < 0 }) { swaying += 1 }
            // Never through the grass.
            #expect(path.allSatisfy { $0.y <= PipFall.groundBottom + 0.001 })
        }
        #expect(swaying >= count - 2)
        // Down by the end, on the grass, and still.
        let end = PipFall.spill(at: PipFall.seconds)
        #expect(end == PipFall.spill(at: PipFall.seconds + 5))
        for leaf in end {
            #expect(leaf.opacity == 1)
            #expect(leaf.y >= PipFall.groundTop - 0.001 && leaf.y <= PipFall.groundBottom + 0.001)
            #expect(leaf.x > PipFall.grassLeft && leaf.x < PipFall.grassRight)
            #expect((0 ..< 3).contains(leaf.colour))
            #expect(leaf.size > 0.5 && leaf.size < 1.3)
        }
        // Scattered, not in a heap.
        #expect(end.map(\.x).max()! - end.map(\.x).min()! > 350)
        #expect(PipFall.spill(at: 0.9) == PipFall.spill(at: 0.9))
        #expect(PipFall.spill(at: .nan) == PipFall.spill(at: 0))
    }

    @Test("A puff of dust where he lands, and a smaller one where the pail lands, gone soon after")
    func dust() {
        #expect(PipFall.dust(at: 0.9).allSatisfy { $0.opacity == 0 })
        let after = PipFall.dust(at: 1.2).filter { $0.opacity > 0.05 }
        #expect(after.count >= 4)
        // At his feet.
        #expect(after.allSatisfy { abs($0.y - (PipFall.landingY + 150)) < 120 })
        #expect(PipFall.dust(at: 2.4).allSatisfy { $0.opacity == 0 })
        #expect(PipFall.dust(at: 1.35).allSatisfy { $0.radius > 0 && $0.opacity <= 1 })
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
