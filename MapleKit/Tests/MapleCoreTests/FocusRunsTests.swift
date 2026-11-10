import Foundation
import Testing
@testable import MapleCore

@Suite("Focus streak")
struct FocusRunsTests {
    /// Day `n` of a run of days starting on Monday 5 October 2026.
    private func day(_ n: Int) -> LocalDay {
        LocalDay(year: 2026, month: 10, day: 5).adding(days: n, calendar: utc)
    }

    private func runs(_ days: [Int], today: Int, zones: [Int: String] = [:]) -> FocusRuns {
        FocusRuns(focusDays: days.map { (day($0), zones[$0] ?? "UTC") }, today: day(today))
    }

    @Test("Monday to Friday keeps the run going, weekends bridged as rest days")
    func weekdays() {
        let weeks = [0, 1, 2, 3, 4, 7, 8, 9, 10, 11, 14, 15, 16, 17, 18]
        let result = runs(weeks, today: 18)
        #expect(result.current == 19)
        #expect(result.best == 19)
    }

    @Test("A third miss in 7 days breaks the run")
    func thirdMiss() {
        let result = runs([0, 2, 4, 6], today: 6)
        #expect(result.best == 5)
        #expect(result.current == 1)
    }

    @Test("One session then misses never makes a run longer than 1")
    func trailing() {
        #expect(runs([0], today: 2).current == 1)
        #expect(runs([0], today: 3).current == 1)
        #expect(runs([0], today: 4).current == 0)
        #expect(runs([0], today: 4).best == 1)
    }

    @Test("Misses are bridged once a finished day follows")
    func bridged() {
        #expect(runs([0, 3], today: 3).current == 4)
    }

    @Test("Today stays pending")
    func pending() {
        #expect(runs([0, 1, 2], today: 3).current == 3)
        #expect(runs([0, 1, 2, 3], today: 3).current == 4)
    }

    @Test("A one-day gap across a time-zone change is neutral")
    func travel() {
        let result = runs([0, 2], today: 2, zones: [0: "Europe/London", 2: "America/Los_Angeles"])
        #expect(result.current == 2)
        // In one zone the same gap is a rest day and counts toward the length.
        #expect(runs([0, 2], today: 2).current == 3)
    }

    @Test("A day spent in two zones counts once")
    func twoZones() {
        // Day 2 is spent in UTC and Tokyo. It shares Tokyo with day 4, so the gap on day 3 is a rest day: one run of 5 days.
        let forward: [(day: LocalDay, zone: String)] = [(day(0), "UTC"), (day(2), "UTC"), (day(2), "Asia/Tokyo"), (day(4), "Asia/Tokyo")]
        let reversed: [(day: LocalDay, zone: String)] = [(day(0), "UTC"), (day(2), "Asia/Tokyo"), (day(2), "UTC"), (day(4), "Asia/Tokyo")]
        for days in [forward, reversed] {
            let result = FocusRuns(focusDays: days, today: day(4))
            #expect(result.current == 5)
            #expect(result.best == 5)
        }
    }

    @Test("A gap between days that share a zone is a rest day, whichever order the zones come in")
    func sharedZone() {
        let forward = FocusRuns(focusDays: [(day(0), "Europe/London"), (day(0), "America/Los_Angeles"), (day(2), "America/Los_Angeles")], today: day(2))
        let reversed = FocusRuns(focusDays: [(day(0), "America/Los_Angeles"), (day(0), "Europe/London"), (day(2), "America/Los_Angeles")], today: day(2))
        #expect(forward.current == 3)
        #expect(forward == reversed)
    }

    @Test("A gap into a day that adds a zone is a rest day, whichever order the zones come in")
    func addedZone() {
        let forward = FocusRuns(focusDays: [(day(0), "UTC"), (day(2), "UTC"), (day(2), "Asia/Tokyo")], today: day(2))
        let reversed = FocusRuns(focusDays: [(day(0), "UTC"), (day(2), "Asia/Tokyo"), (day(2), "UTC")], today: day(2))
        #expect(forward.current == 3)
        #expect(forward == reversed)
    }

    @Test("A one-day gap from Los Angeles to London is neutral")
    func reverseTravel() {
        #expect(runs([0, 2], today: 2, zones: [0: "America/Los_Angeles", 2: "Europe/London"]).current == 2)
    }

    @Test("At most 2 rest days in any 7 days in a row")
    func fits() {
        #expect(FocusRuns.fits([1, 2]))
        #expect(!FocusRuns.fits([1, 2, 7]))
        #expect(FocusRuns.fits([1, 2, 8]))
    }

    @Test("Nothing yet")
    func empty() {
        let result = runs([], today: 3)
        #expect(result.current == 0)
        #expect(result.best == 0)
    }
}
