import Foundation
import Testing
@testable import MapleCore
@testable import MapleFocusCore

@Suite("Ending a van session early: the words say the leaves are lost")
struct VanSessionEndTests {
    @Test("The sheet says ending now loses this session's leaves, and without the van it says what it always did")
    func sheet() {
        let van = EndEarlyModel(path: .gentle, countedSeconds: 600, breakAvailable: false, losesLeaves: true)
        #expect(van.body == "Ending now loses this session's leaves.")
        #expect(!van.body.lowercased().contains("fail") && !van.body.lowercased().contains("quit"))
        let before = EndEarlyModel(path: .gentle, countedSeconds: 600, breakAvailable: false)
        #expect(before.body == FocusCopy.EndEarly.savedLine(countedSeconds: 600))
    }

    @Test("After the breath the second question says it again, plainly")
    func secondQuestion() {
        let asked = EndBreathModel(
            path: .gentle, countedSeconds: 600, focusedSeconds: 700, canCount: true, seconds: 100, reduceMotion: false,
            losesLeaves: true
        )
        #expect(asked.isAsking)
        #expect(asked.body == "Ending now loses this session's leaves.")
        let before = EndBreathModel(
            path: .gentle, countedSeconds: 600, focusedSeconds: 700, canCount: true, seconds: 100, reduceMotion: false
        )
        #expect(before.body == FocusCopy.EndEarly.savedLine(countedSeconds: 600))
        let breathing = EndBreathModel(
            path: .gentle, countedSeconds: 600, focusedSeconds: 700, canCount: true, seconds: 1, reduceMotion: false,
            losesLeaves: true
        )
        #expect(breathing.body == nil)
    }

    @Test("Once a session has ended, Pip walks back if it finished and tumbles if it was ended early or released")
    func momentAfterTheEnd() {
        #expect(PipMoment(after: .completed) == .walkBack)
        #expect(PipMoment(after: .endedEarly) == .tumble)
        #expect(PipMoment(after: .releaseAll) == .tumble)
        // Locked's 10-second hold isn't a van way out: straight to the receipt.
        #expect(PipMoment(after: .emergencyRelease) == nil)
    }
}
