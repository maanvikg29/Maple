import Foundation
import Testing
@testable import MapleCore

@Suite("Pip at home: always a little alive, and the playful things he does")
struct PipAtHomeTests {
    private func frames(of act: PipAct, every step: Double = 1.0 / 60) -> [(time: Double, scene: PipScene)] {
        stride(from: 0, through: act.seconds, by: step).map { ($0, act.scene(at: $0)) }
    }

    private func shown(_ scene: PipScene, _ kind: PipProp.Kind) -> [PipProp] {
        scene.props.filter { $0.kind == kind && $0.opacity > 0.01 }
    }

    private func leaves(_ scene: PipScene) -> [PipProp] {
        scene.props.filter { prop in
            if case .leaf = prop.kind { return prop.opacity > 0.01 }
            return false
        }
    }

    // MARK: Standing

    @Test("Standing where the picture has him, nothing is moved: no props, the ladle on its knob, his eyes open")
    func rest() {
        let scene = PipScene.rest
        #expect(scene.pose.x == PipHome.standX && scene.pose.y == PipHome.standY)
        #expect(scene.pose.lift == 0 && scene.pose.turn == 0 && scene.pose.size == 1)
        #expect(scene.pose.stretchX == 1 && scene.pose.stretchY == 1)
        #expect(scene.pose.tail == 0 && scene.pose.ear == 0)
        #expect(!scene.pose.asleep && !scene.pose.facesLeft && scene.pose.shadow == 1)
        #expect(scene.props.isEmpty && scene.ladleTurn == nil && !scene.inBasket)
    }

    @Test("Always alive: he stays on his spot while his tail swishes, his ear flicks and he breathes, all slightly")
    func idle() {
        var tails: [Double] = []
        var ears: [Double] = []
        var breaths: [Double] = []
        for step in 0 ..< 1200 {
            let pose = PipIdle.pose(at: Double(step) / 60)
            #expect(pose.x == PipHome.standX && pose.y == PipHome.standY && pose.lift == 0 && pose.turn == 0)
            tails.append(pose.tail)
            ears.append(pose.ear)
            breaths.append(pose.stretchY)
        }
        // The tail goes both ways, never far: its hidden edge must stay behind him.
        #expect(tails.min()! < -0.02 && tails.max()! > 0.02)
        #expect(tails.allSatisfy { abs($0) <= 0.05 })
        // The ear is still most of the time, and flicks now and then.
        #expect(ears.filter { $0 == 0 }.count > ears.count / 2)
        #expect(ears.contains { abs($0) > 0.06 })
        #expect(ears.allSatisfy { abs($0) <= 0.13 })
        #expect(breaths.min()! < 0.997 && breaths.max()! > 1.003)
        #expect(breaths.allSatisfy { abs($0 - 1) <= 0.02 })
        // The same moment is always the same frame.
        #expect(PipIdle.pose(at: 3.21) == PipIdle.pose(at: 3.21))
        #expect(PipIdle.pose(at: .nan) == PipIdle.pose(at: 0))
    }

    @Test("A place in the picture is on him or not, wherever he has gone")
    func contains() {
        let rest = PipHomePose.rest
        #expect(rest.contains(x: 1180, y: 1500))
        #expect(rest.contains(x: 1110, y: 1640))
        #expect(!rest.contains(x: 1400, y: 1500))
        #expect(!rest.contains(x: 1180, y: 1300))
        var away = rest
        away.x = 1560
        away.y = 1800
        #expect(away.contains(x: 1560, y: 1700))
        #expect(!away.contains(x: 1180, y: 1500))
        var up = rest
        up.lift = 200
        #expect(up.contains(x: 1180, y: 1300))
        #expect(!up.contains(x: 1180, y: 1640))
        #expect(!rest.contains(x: .nan, y: 1500))
    }

    // MARK: Every act

    @Test("Every act begins and ends with him standing as the picture has him", arguments: PipAct.allCases)
    func beginsAndEndsAtRest(act: PipAct) {
        #expect(act.seconds > 0.5)
        #expect(act.scene(at: 0) == .rest)
        #expect(act.scene(at: act.seconds) == .rest)
        #expect(act.scene(at: -4) == .rest)
        #expect(act.scene(at: act.seconds + 60) == .rest)
        #expect(act.scene(at: .nan) == .rest)
        #expect(act.scene(at: .infinity) == .rest)
    }

    @Test("No act makes him jump from place to place between frames, sink into the ground, or lose his shape",
          arguments: PipAct.allCases)
    func movesSmoothly(act: PipAct) {
        let frames = frames(of: act, every: 1.0 / 120)
        for (before, after) in zip(frames, frames.dropFirst()) {
            let a = before.scene.pose
            let b = after.scene.pose
            let moved = hypot(b.x - a.x, (b.y - b.lift) - (a.y - a.lift))
            #expect(moved < 14, "\(act) at \(after.time): moved \(moved)")
            #expect(abs(b.turn - a.turn) < 0.2, "\(act) at \(after.time)")
            #expect(abs(b.size - a.size) < 0.03, "\(act) at \(after.time)")
            #expect(abs(b.stretchY - a.stretchY) < 0.04, "\(act) at \(after.time)")
        }
        for frame in frames {
            let pose = frame.scene.pose
            #expect(pose.lift >= 0)
            #expect(pose.stretchX > 0.8 && pose.stretchX < 1.2 && pose.stretchY > 0.8 && pose.stretchY < 1.2)
            #expect(pose.size >= 0.55 && pose.size <= 1)
            #expect(pose.shadow >= 0 && pose.shadow <= 1)
            #expect(pose.x > 150 && pose.x < 1750 && pose.y > 1500 && pose.y < 1950)
            for prop in frame.scene.props {
                #expect(prop.opacity >= 0 && prop.opacity <= 1 && prop.size >= 0 && prop.size <= 1.6)
                #expect(prop.x.isFinite && prop.y.isFinite && prop.turn.isFinite)
            }
        }
    }

    @Test("The acts he does unprompted are the six random ones: the hop and the dance wait for their cue")
    func unprompted() {
        #expect(Set(PipAct.unprompted) == [.juggle, .leafJump, .nap, .basket, .ladleTwirl, .rake])
    }

    // MARK: Each act

    @Test("Tapped, he hops on the spot and three hearts pop up and fade")
    func hop() {
        let frames = frames(of: .hop)
        #expect(frames.map(\.scene.pose.lift).max()! > 50)
        #expect(frames.allSatisfy { $0.scene.pose.x == PipHome.standX && $0.scene.pose.y == PipHome.standY })
        #expect(frames.map { shown($0.scene, .heart).count }.max() == 3)
        // He squashes as he lands.
        #expect(frames.map(\.scene.pose.stretchY).min()! < 0.95)
        // The hearts rise.
        let first = frames.first { !shown($0.scene, .heart).isEmpty }!.scene.props[0]
        let later = frames.last { !shown($0.scene, .heart).isEmpty }!.scene.props[0]
        #expect(later.y < first.y - 30)
    }

    @Test("The happy dance: he sways both ways on his spot with little bounces, and music notes drift up")
    func dance() {
        let frames = frames(of: .dance)
        #expect(frames.map(\.scene.pose.turn).min()! < -0.1 && frames.map(\.scene.pose.turn).max()! > 0.1)
        #expect(frames.allSatisfy { abs($0.scene.pose.x - PipHome.standX) < 40 && $0.scene.pose.y == PipHome.standY })
        #expect(frames.map(\.scene.pose.lift).max()! > 8)
        #expect(frames.map { shown($0.scene, .note).count }.max()! >= 2)
    }

    @Test("He takes the ladle off its knob, spins it twice round in his paw and hangs it back just as it was")
    func ladleTwirl() {
        let frames = frames(of: .ladleTwirl)
        let turns = frames.compactMap(\.scene.ladleTurn)
        #expect(turns.count > frames.count / 2)
        #expect(turns.first! < 0.05)
        #expect(abs(turns.max()! - 4 * .pi) < 0.05)
        // It only ever turns one way.
        #expect(zip(turns, turns.dropFirst()).allSatisfy { $1 >= $0 - 1e-9 })
        // In his paw it is where it hangs: he stays by the cabinet.
        #expect(frames.allSatisfy { abs($0.scene.pose.x - PipHome.standX) < 12 })
    }

    @Test("Juggling: three leaves, one of each colour, go round above his paws")
    func juggle() {
        let frames = frames(of: .juggle)
        let middle = PipAct.juggle.scene(at: PipAct.juggle.seconds / 2)
        let three = leaves(middle)
        #expect(three.count == 3)
        #expect(Set(three.map(\.kind)) == [.leaf(0), .leaf(1), .leaf(2)])
        // Never two in the same place.
        #expect(hypot(three[0].x - three[1].x, three[0].y - three[1].y) > 20)
        #expect(hypot(three[1].x - three[2].x, three[1].y - three[2].y) > 20)
        for frame in frames {
            for leaf in leaves(frame.scene) {
                #expect(leaf.y < PipHome.standY - 90 && leaf.y > PipHome.standY - 330)
                #expect(abs(leaf.x - PipHome.standX) < 100)
            }
        }
        // They go higher than his head.
        #expect(frames.flatMap { leaves($0.scene) }.map(\.y).min()! < PipHome.standY - 270)
    }

    @Test("He runs out onto the grass, jumps for a falling leaf, catches it and brings it back")
    func leafJump() {
        let frames = frames(of: .leafJump)
        let out = frames.filter { $0.scene.pose.x > 1500 }
        #expect(!out.isEmpty)
        // The jump is out there, not on the way.
        #expect(out.map(\.scene.pose.lift).max()! > 120)
        #expect(frames.filter { $0.scene.pose.x < 1400 }.map(\.scene.pose.lift).max()! < 90)
        // One leaf: it falls first, then is in his paw.
        #expect(frames.allSatisfy { leaves($0.scene).count <= 1 })
        let falling = frames.filter { !leaves($0.scene).isEmpty }
        #expect(falling.first!.scene.props[0].y < 1300)
        // He faces the way he hops: left on the way home, right again at the end.
        let home = frames.filter { $0.time > PipAct.leafJump.seconds - 1.6 && $0.time < PipAct.leafJump.seconds - 0.6 }
        #expect(home.allSatisfy { $0.scene.pose.facesLeft })
        #expect(frames.filter { $0.time < 2 }.allSatisfy { !$0.scene.pose.facesLeft })
    }

    @Test("Raking: out on the grass he sweeps a rake back and forth, and the scattered leaves end up in one pile")
    func rake() {
        let frames = frames(of: .rake)
        let raking = frames.filter { !shown($0.scene, .rake).isEmpty }
        #expect(raking.count > frames.count / 2)
        #expect(raking.allSatisfy { $0.scene.pose.x > 1450 })
        // The rake is in his paw, and swings.
        let swing = raking.map { shown($0.scene, .rake)[0].turn }
        #expect(swing.max()! - swing.min()! > 0.25)
        for frame in raking {
            let rake = shown(frame.scene, .rake)[0]
            #expect(abs(rake.x - (frame.scene.pose.x + PipHome.pawX)) < 16)
        }
        func spread(_ scene: PipScene) -> Double {
            let all = leaves(scene)
            let cx = all.map(\.x).reduce(0, +) / Double(all.count)
            let cy = all.map(\.y).reduce(0, +) / Double(all.count)
            return all.map { hypot($0.x - cx, $0.y - cy) }.max()!
        }
        let before = raking.first!.scene
        let after = raking.last!.scene
        #expect(leaves(before).count >= 5 && leaves(after).count == leaves(before).count)
        #expect(spread(after) < spread(before) / 2)
        #expect(spread(after) < 45)
    }

    @Test("The nap: he closes his eyes, tips over onto his side, sleeps with z's drifting up, and gets up again")
    func nap() {
        let act = PipAct.nap
        let frames = frames(of: act)
        let asleep = frames.filter(\.scene.pose.asleep)
        #expect(Double(asleep.count) / Double(frames.count) > 0.7)
        // On his side for all the middle of it.
        let middle = frames.filter { $0.time > 2 && $0.time < act.wakesAt! }
        #expect(middle.allSatisfy { abs($0.scene.pose.turn) > 1.2 && $0.scene.pose.asleep })
        #expect(middle.contains { !shown($0.scene, .zed).isEmpty })
        // The z's are only while he sleeps.
        #expect(frames.filter { !$0.scene.pose.asleep }.allSatisfy { shown($0.scene, .zed).isEmpty })
        // It is the long one, and waking is the end of it.
        #expect(act.seconds >= 12)
        #expect(act.wakesAt! > act.seconds - 2 && act.wakesAt! < act.seconds)
        #expect(PipAct.allCases.filter { $0 != .nap }.allSatisfy { $0.wakesAt == nil && $0.seconds < 10 })
    }

    @Test("The basket: he leaps into the leaf basket, pops up smaller with a leaf on his head, and leaps home")
    func basket() {
        let frames = frames(of: .basket)
        let inside = frames.filter(\.scene.inBasket)
        #expect(Double(inside.count) / Double(frames.count) > 0.4)
        for frame in inside {
            #expect(abs(frame.scene.pose.x - PipHome.basketX) < 60)
            #expect(frame.scene.pose.size < 0.75)
        }
        // Standing at home he is never behind the basket's front, and he is his own size.
        #expect(frames.filter { $0.scene.pose.x > 900 }.allSatisfy { !$0.scene.inBasket })
        // The leap is high and he turns right over in it.
        #expect(frames.map(\.scene.pose.lift).max()! > 250)
        #expect(frames.map { abs($0.scene.pose.turn) }.max()! > 3)
        // Popped up, a leaf sits on his head.
        let up = inside.filter { $0.scene.pose.y < PipHome.basketY + 5 && $0.scene.pose.lift == 0 }
        #expect(!up.isEmpty)
        #expect(up.contains { frame in
            leaves(frame.scene).contains { $0.inFront && abs($0.x - frame.scene.pose.x) < 30 && $0.y < frame.scene.pose.y - 130 }
        })
    }

    // MARK: When

    @Test("He does something of his own soon after home opens, then every 10 to 20 seconds, never the same twice")
    func director() {
        for roll in 0 ..< 200 {
            let first = PipDirector.next(after: nil, roll: UInt64(roll) &* 0x9E37_79B9_7F4A_7C15)
            #expect(first.wait >= 3 && first.wait <= 7)
        }
        var seen: Set<PipAct> = []
        var last: PipAct? = .juggle
        for roll in 0 ..< 600 {
            let next = PipDirector.next(after: last, roll: UInt64(roll) &* 0x9E37_79B9_7F4A_7C15)
            #expect(next.wait >= 10 && next.wait <= 20)
            #expect(next.act != last)
            #expect(PipAct.unprompted.contains(next.act))
            seen.insert(next.act)
            last = next.act
        }
        #expect(seen == Set(PipAct.unprompted))
        #expect(PipDirector.next(after: .nap, roll: 7) == PipDirector.next(after: .nap, roll: 7))
    }

    @Test("On stage he idles until an act is played, does it once, and idles again")
    func stage() {
        var stage = PipStage()
        #expect(!stage.isBusy(at: 100))
        #expect(stage.scene(at: 100).pose == PipIdle.pose(at: 100))
        stage.play(.dance, at: 100)
        #expect(stage.isBusy(at: 100.5))
        #expect(stage.act(at: 100.5) == .dance)
        // The act's own frame, with his tail and ear still alive on top.
        let playing = stage.scene(at: 101)
        #expect(playing.pose.turn == PipAct.dance.scene(at: 1).pose.turn)
        #expect(playing.props == PipAct.dance.scene(at: 1).props)
        #expect(!stage.isBusy(at: 100 + PipAct.dance.seconds))
        #expect(stage.act(at: 100 + PipAct.dance.seconds) == nil)
        #expect(stage.scene(at: 200).pose == PipIdle.pose(at: 200))
        // A second act does not cut in on the first.
        stage.play(.rake, at: 300)
        stage.play(.juggle, at: 301)
        #expect(stage.act(at: 302) == .rake)
        // Unless it is asked to.
        stage.play(.dance, at: 302, cuttingIn: true)
        #expect(stage.act(at: 302.5) == .dance)
    }

    @Test("A tap makes him hop when he is idle, wakes him from a nap, and is left alone in the middle of anything else")
    func taps() {
        var stage = PipStage()
        stage.tapped(at: 10)
        #expect(stage.act(at: 10.1) == .hop)
        // A tap mid-hop does not start the hop again.
        stage.tapped(at: 10.3)
        #expect(stage.scene(at: 10.4) != stage.scene(at: 10.1))
        #expect(!stage.isBusy(at: 10 + PipAct.hop.seconds))

        stage.play(.nap, at: 50)
        stage.tapped(at: 55)
        // He is waking: what is left is the getting up.
        #expect(stage.act(at: 55) == .nap)
        let left = PipAct.nap.seconds - PipAct.nap.wakesAt!
        #expect(stage.isBusy(at: 55 + left - 0.05))
        #expect(!stage.isBusy(at: 55 + left + 0.05))
        // Tapped again while getting up, he just gets up.
        stage.tapped(at: 55.2)
        #expect(!stage.isBusy(at: 55 + left + 0.05))

        stage.play(.rake, at: 100)
        stage.tapped(at: 102)
        #expect(stage.act(at: 102.5) == .rake)
        #expect(stage.isBusy(at: 100 + PipAct.rake.seconds - 0.1))
    }

    @Test("Standing about, he blinks every few seconds, quickly, and is otherwise wide awake")
    func blinks() {
        let frames = stride(from: 0.0, through: 30, by: 1.0 / 60).map { PipIdle.pose(at: $0) }
        let shut = frames.filter(\.asleep).count
        #expect(shut > 0)
        #expect(Double(shut) / Double(frames.count) < 0.08)
        // Every closing is short.
        var run = 0
        var longest = 0
        for frame in frames {
            run = frame.asleep ? run + 1 : 0
            longest = max(longest, run)
        }
        #expect(longest <= 12)
        // At least four blinks in half a minute.
        let openings = zip(frames, frames.dropFirst()).filter { $0.asleep && !$1.asleep }.count
        #expect(openings >= 4)
        // He blinks in the middle of an act too, but never wakes from a nap by blinking.
        var stage = PipStage()
        stage.play(.nap, at: 0)
        #expect(stride(from: 3.0, through: 10, by: 0.05).allSatisfy { stage.scene(at: $0).pose.asleep })
    }

    @Test("Stilled, he stands exactly as the picture has him whatever is asked of him")
    func still() {
        var stage = PipStage()
        stage.play(.dance, at: 5)
        #expect(stage.scene(at: 6, still: true) == .rest)
        #expect(PipStage().scene(at: 6, still: true) == .rest)
    }
}
