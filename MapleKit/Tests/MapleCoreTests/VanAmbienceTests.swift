import Foundation
import Testing
@testable import MapleCore

@Suite("Home's picture is alive: leaves fall, smoke drifts, the fire flickers, the lights twinkle")
struct VanAmbienceTests {
    private let times = stride(from: 0.0, through: 60, by: 1.0 / 30).map { $0 }

    @Test("Leaves leave the maple's canopy and come down onto the grass, a few at a time")
    func homeLeaves() {
        var seen = 0
        for time in times {
            let leaves = VanAmbience.leaves(at: time)
            #expect(leaves.count == VanAmbience.leafCount)
            for leaf in leaves where leaf.opacity > 0.05 {
                seen += 1
                #expect(leaf.x > -80 && leaf.x < 1500)
                #expect(leaf.y > VanAmbience.canopyTop - 1 && leaf.y < VanAmbience.groundBottom + 1)
                #expect(leaf.colour >= 0 && leaf.colour <= 2)
            }
        }
        #expect(seen > 0)
        // Over a minute, every leaf has fallen from the canopy to the grass at least once.
        for index in 0 ..< VanAmbience.leafCount {
            let path = times.map { VanAmbience.leaves(at: $0)[index] }
            #expect(path.map(\.y).min()! < VanAmbience.canopyBottom)
            #expect(path.map(\.y).max()! > VanAmbience.groundTop)
        }
        #expect(VanAmbience.leaves(at: 12.5) == VanAmbience.leaves(at: 12.5))
        #expect(VanAmbience.leaves(at: .nan) == VanAmbience.leaves(at: 0))
    }

    @Test("A falling leaf moves a little each frame, never jumping, except when it starts again at the top")
    func leavesAreSmooth() {
        for (before, after) in zip(times, times.dropFirst()) {
            for (a, b) in zip(VanAmbience.leaves(at: before), VanAmbience.leaves(at: after)) {
                let jump = hypot(b.x - a.x, b.y - a.y)
                // A restart is unseen: the leaf has faded out at the bottom and is still faded in at the top.
                #expect(jump < 30 || (a.opacity < 0.05 && b.opacity < 0.05))
            }
        }
    }

    @Test("The leaves the picture paints in mid-air never hang still: each swings where it is drawn, lets go and falls, and comes back")
    func paintedLeaves() {
        // The owner, 28 Nov 2026: "there are still frozen leaves in the air".
        let long = stride(from: 0.0, through: 120, by: 1.0 / 20).map { $0 }
        for index in 0 ..< VanAmbience.paintedLeafCount {
            let path = long.map { VanAmbience.paintedLeaf(index, at: $0) }
            #expect(path.allSatisfy { $0.opacity >= 0 && $0.opacity <= 1 })
            // At the start, the picture is as drawn.
            let first = VanAmbience.paintedLeaf(index, at: 0)
            #expect(first.opacity == 1 && abs(first.dx) < 16 && abs(first.dy) < 16)
            // It swings where it hangs.
            let hanging = path.filter { $0.opacity > 0.99 && $0.dy < 16 }
            #expect(hanging.map(\.turn).max()! - hanging.map(\.turn).min()! > 0.3)
            // Within two minutes it has fallen well down, and been back at its place.
            #expect(path.map(\.dy).max()! > 300)
            #expect(path.last(where: { $0.dy > 300 }) != nil && path.contains { $0.opacity > 0.99 && abs($0.dy) < 16 })
            // While it is far from its place it is falling, and it is gone before it could show back there.
            for (a, b) in zip(path, path.dropFirst()) where a.dy > 200 && b.dy < 16 {
                #expect(a.opacity < 0.05)
            }
        }
        // They don't all go at once: at any moment most are hanging.
        for time in long {
            let falling = (0 ..< VanAmbience.paintedLeafCount).filter { VanAmbience.paintedLeaf($0, at: time).dy > 40 }
            #expect(falling.count <= 3)
        }
        #expect(VanAmbience.paintedLeaf(0, at: .nan) == VanAmbience.paintedLeaf(0, at: 0))
    }

    @Test("Smoke sways about the chimney's top, and new puffs rise from it, grow and fade")
    func smoke() {
        let sways = times.map { VanAmbience.smoke(at: $0) }
        #expect(sways.map(\.turn).min()! < -0.02 && sways.map(\.turn).max()! > 0.02)
        #expect(sways.allSatisfy { abs($0.turn) <= 0.08 && $0.scale >= 1 && $0.scale <= 1.08 })
        for time in times {
            for puff in VanAmbience.chimneyPuffs(at: time) {
                #expect(puff.opacity >= 0 && puff.opacity <= 1)
                // Up from the chimney, never down.
                #expect(puff.rise >= 0 && puff.rise <= 1)
                #expect(puff.scale > 0 && puff.scale <= 1.2)
            }
        }
        // A puff grows as it rises.
        let early = VanAmbience.puff(rise: 0.1)
        let late = VanAmbience.puff(rise: 0.8)
        #expect(late.scale > early.scale)
        #expect(VanAmbience.puff(rise: 0).opacity < 0.05 && VanAmbience.puff(rise: 1).opacity < 0.05)
    }

    @Test("Steam comes off the pot in soft puffs that rise and fade")
    func steam() {
        for time in times {
            let puffs = VanAmbience.steam(at: time)
            #expect(puffs.count == VanAmbience.steamCount)
            for puff in puffs {
                #expect(puff.rise >= 0 && puff.rise <= 1 && puff.opacity >= 0 && puff.opacity <= 1)
            }
        }
    }

    @Test("The picture's own steam billows: each puff swells and settles, never smaller than drawn, each on its own beat")
    func steamBillows() {
        // The owner, 28 Nov 2026: "the smoke isnt moving in the cooking pot".
        for index in 0 ..< VanAmbience.paintedSteamCount {
            let swells = times.map { VanAmbience.steamSwell(index, at: $0) }
            // It only ever grows from how it is drawn, so the picture's still puff never shows from behind.
            #expect(swells.allSatisfy { $0 >= 1.03 && $0 <= 1.25 })
            #expect(swells.max()! - swells.min()! > 0.06)
        }
        #expect(VanAmbience.steamSwell(0, at: 1) != VanAmbience.steamSwell(1, at: 1))
    }

    @Test("The flag flaps and the bunting sways, each flag on its own beat, a few degrees at most")
    func flags() {
        let flag = times.map { VanAmbience.flag(at: $0) }
        #expect(flag.map(\.turn).max()! - flag.map(\.turn).min()! > 0.06)
        #expect(flag.allSatisfy { abs($0.turn) <= 0.12 && $0.stretch <= 1 && $0.stretch >= 0.9 })
        for index in 0 ..< VanAmbience.buntingCount {
            let turns = times.map { VanAmbience.bunting(index, at: $0) }
            #expect(turns.allSatisfy { abs($0) <= 0.09 })
            #expect(turns.max()! - turns.min()! > 0.04)
        }
        #expect(VanAmbience.bunting(0, at: 2) != VanAmbience.bunting(1, at: 2))
    }

    @Test("Fire and lantern flicker, the string lights twinkle, all between dim and bright, never off")
    func lights() {
        for time in times {
            for seed in 0 ..< 3 {
                let value = VanAmbience.flicker(at: time, seed: seed)
                #expect(value >= 0 && value <= 1)
            }
            for bulb in 0 ..< VanAmbience.bulbCount {
                let value = VanAmbience.bulb(bulb, at: time)
                #expect(value >= 0.25 && value <= 1)
            }
        }
        let fire = times.map { VanAmbience.flicker(at: $0, seed: 0) }
        #expect(fire.max()! - fire.min()! > 0.4)
        // Smooth enough to read as a flame, not a strobe.
        #expect(zip(fire, fire.dropFirst()).allSatisfy { abs($1 - $0) < 0.25 })
        let bulb = times.map { VanAmbience.bulb(2, at: $0) }
        #expect(bulb.max()! - bulb.min()! > 0.3)
    }

    @Test("The cat breathes slowly, only ever growing a little from how the picture has it")
    func cat() {
        let breaths = times.map { VanAmbience.catBreath(at: $0) }
        #expect(breaths.allSatisfy { $0 >= 1 && $0 <= 1.03 })
        #expect(breaths.max()! - breaths.min()! > 0.015)
    }
}
