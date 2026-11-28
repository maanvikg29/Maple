import Testing
@testable import MapleCore

@Suite("What moves in the session scene: everything, only Pip when calm, nothing when dimmed or with Reduce Motion")
struct VanSessionMotionTests {
    @Test("Ordinarily everything moves: the leaves fall, the clouds drift, the lights twinkle, Pip breathes and catches")
    func everything() {
        let motion = VanSessionMotion.of(calm: false, dimmed: false, reduceMotion: false)
        #expect(motion == VanSessionMotion(leaves: true, clouds: true, lights: true, pip: true))
        #expect(motion.anything)
    }

    @Test("Calm keeps only Pip moving: no leaves in the air at all, the clouds and lights hold still")
    func calm() {
        // The owner, 28 Nov 2026: "a button for making everything less distractive which disables the leafs falling and
        // ... just keeps pip moving".
        let motion = VanSessionMotion.of(calm: true, dimmed: false, reduceMotion: false)
        #expect(motion == VanSessionMotion(leaves: false, clouds: false, lights: false, pip: true))
        #expect(motion.anything)
    }

    @Test("Dimmed, or with Reduce Motion, nothing moves, calm or not")
    func still() {
        for calm in [false, true] {
            #expect(!VanSessionMotion.of(calm: calm, dimmed: true, reduceMotion: false).anything)
            #expect(!VanSessionMotion.of(calm: calm, dimmed: false, reduceMotion: true).anything)
            #expect(!VanSessionMotion.of(calm: calm, dimmed: true, reduceMotion: true).anything)
        }
    }

    @Test("Calm never brings back leaves frozen in the air: when the leaves don't fall, none are drawn")
    func noFrozenLeaves() {
        #expect(!VanSessionMotion.of(calm: true, dimmed: false, reduceMotion: false).showsFallingLeaves)
        #expect(VanSessionMotion.of(calm: false, dimmed: false, reduceMotion: false).showsFallingLeaves)
        // Dimmed without calm, the scene is only paused under the shade, as before.
        #expect(VanSessionMotion.of(calm: false, dimmed: true, reduceMotion: false).showsFallingLeaves)
        // Calm and dimmed, or calm with Reduce Motion: still no leaves.
        #expect(!VanSessionMotion.of(calm: true, dimmed: true, reduceMotion: false).showsFallingLeaves)
        #expect(!VanSessionMotion.of(calm: true, dimmed: false, reduceMotion: true).showsFallingLeaves)
    }
}
