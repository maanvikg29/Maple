import Foundation
import Testing
@testable import MapleCore

@Suite("The van's home view: its words")
struct VanHomeModelTests {
    private func model(_ phase: NowPhase = .day, leaves: Int = 0, syrup: Int = 0, available: Bool = true, left: Int? = nil) -> VanHomeModel {
        VanHomeModel(phase: phase, leaves: leaves, syrupTenths: syrup, isAvailable: available, minutesLeft: left)
    }

    @Test("The greeting follows the member's own day", arguments: [
        (NowPhase.morning, "Good morning"), (.day, "Good afternoon"), (.evening, "Good evening"), (.windDown, "Winding down"),
        (.night, "Good night"),
    ])
    func greeting(phase: NowPhase, words: String) {
        #expect(model(phase).greeting == words)
    }

    @Test("One line says what is waiting: no leaves, one leaf, several")
    func waiting() {
        #expect(model(leaves: 0).status == "Pip is out of leaves")
        #expect(model(leaves: 1).status == "1 leaf waiting to cook")
        #expect(model(leaves: 45).status == "45 leaves waiting to cook")
    }

    @Test("While a session runs the line says so, with the time left and no leaf count")
    func running() {
        let line = model(leaves: 12, left: 32).status
        #expect(line == "Session running · \(FocusTimeText.length(minutes: 32)) left")
        #expect(!line.contains("leaf") && !line.contains("leaves"))
    }

    @Test("The one button opens the van, or goes back to the session while one runs")
    func enter() {
        #expect(model().enterTitle == "Open the van")
        #expect(model(left: 32).enterTitle == "Return to session")
        #expect(model(available: false).enterTitle == "Open the van")
    }

    @Test("The counters read whole leaves and syrup to one decimal")
    func counters() {
        let shown = model(leaves: 45, syrup: 127)
        #expect(shown.leavesText == "45")
        #expect(shown.syrupText == "12.7")
        #expect(model(syrup: 30).syrupText == "3.0")
        #expect(model(syrup: 5).syrupText == "0.5")
    }

    @Test("Before the van's file can be read, the counters are absent rather than zero, and the line is empty")
    func unavailable() {
        let shown = model(leaves: 0, syrup: 0, available: false)
        #expect(shown.leavesText == nil)
        #expect(shown.syrupText == nil)
        #expect(shown.status.isEmpty)
    }

    @Test("The gauge's face reads the length that would start now")
    func gauge() {
        #expect(VanHomeModel.gaugeText(minutes: 50) == FocusTimeText.length(minutes: 50))
    }
}
