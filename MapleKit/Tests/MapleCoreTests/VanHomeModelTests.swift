import Foundation
import Testing
@testable import MapleCore

@Suite("The van's home view: its words")
struct VanHomeModelTests {
    private func model(
        _ phase: NowPhase = .day, hour: Int = 15, leaves: Int = 0, syrup: Int = 0, available: Bool = true, left: Int? = nil,
        saved: Int = 0
    ) -> VanHomeModel {
        VanHomeModel(
            phase: phase, hour: hour, leaves: leaves, syrupTenths: syrup, isAvailable: available, minutesLeft: left,
            savedTodaySeconds: saved
        )
    }

    @Test("Today's saved time is a line of its own, in hours and minutes, once there is a minute of it")
    func savedToday() {
        #expect(model(saved: 80 * 60).savedToday == "1h 20m saved today")
        #expect(model(saved: 45 * 60 + 59).savedToday == "45m saved today")
        #expect(model(saved: 2 * 3600).savedToday == "2h saved today")
        #expect(model(saved: 45 * 60).savedTodayMinutes == 45)
        // Under a minute, or none, says nothing rather than "0m".
        #expect(model(saved: 59).savedToday == nil)
        #expect(model(saved: 0).savedTodayMinutes == nil)
        #expect(model(saved: -300).savedToday == nil)
    }

    @Test("While a session runs, the line about it stands alone: today's saved time waits until it ends")
    func savedTodayWhileRunning() {
        #expect(model(left: 20, saved: 3600).savedToday == nil)
        // It doesn't depend on the van's own file.
        #expect(model(available: false, saved: 3600).savedToday == "1h saved today")
    }

    @Test("The end of the day follows the member's own schedule: evening, winding down, night", arguments: [
        (NowPhase.evening, "Good evening"), (.windDown, "Winding down"), (.night, "Good night"),
    ])
    func greeting(phase: NowPhase, words: String) {
        #expect(model(phase, hour: 22).greeting == words)
    }

    @Test("Before the evening the greeting follows the clock, so 10 in the morning never reads afternoon")
    func greetingByTheClock() {
        // Up at 7: the schedule's day starts at 10, and it is still the morning.
        #expect(model(.day, hour: 10).greeting == "Good morning")
        #expect(model(.morning, hour: 7).greeting == "Good morning")
        // Up at noon: the schedule's morning runs to 3 in the afternoon.
        #expect(model(.morning, hour: 13).greeting == "Good afternoon")
        #expect(model(.day, hour: 12).greeting == "Good afternoon")
        #expect(model(.day, hour: 17).greeting == "Good afternoon")
        #expect(model(.day, hour: 18).greeting == "Good evening")
        #expect(model(.day, hour: 99).greeting == "Good evening")
        #expect(model(.day, hour: -3).greeting == "Good morning")
    }

    @Test("With leaves to cook and no session running, home says the pot cooks one; otherwise it says nothing about it")
    func pot() {
        #expect(model(leaves: 3).potHint == "Tap the pot to cook a leaf")
        #expect(model(leaves: 0).potHint == nil)
        #expect(model(leaves: 3, left: 32).potHint == nil)
        #expect(model(leaves: 3, available: false).potHint == nil)
        #expect(model().enterHint == "Opens the clock")
        #expect(model(left: 32).enterHint == "Returns to your session")
    }

    @Test("Home still offers the reveal and wind-down, which the tree home's one button did; the van's own button is the timer's")
    func prompts() {
        #expect(NowState.Action.openReveals(count: 2).showsOnVan)
        #expect(NowState.Action.startWindDown.showsOnVan)
        #expect(NowState.Action.returnToWindDown.showsOnVan)
        #expect(!NowState.Action.returnToSession.showsOnVan)
        #expect(!NowState.Action.turnOnBlocking.showsOnVan)
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

    @Test("The one button sets the timer, or goes back to the session while one runs")
    func enter() {
        #expect(model().enterTitle == "Set the timer")
        #expect(model(left: 32).enterTitle == "Return to session")
        #expect(model(available: false).enterTitle == "Set the timer")
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
}
