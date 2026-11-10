#if DEBUG
import Foundation
import Testing
@testable import MapleCore
@testable import MapleServices

/// `-MapleDemoSchedule` (docs/debug-launch-arguments.md): a demo launch with the member's schedule replaced, so
/// Rest and Home can be screenshotted on a non-default schedule with the phase clock still inside the right phase.
@Suite("Demo schedule")
@MainActor
struct RestDemoScheduleTests {
    private let now = at(2026, 10, 10, 15)

    @Test("Parses bedtime-wake with an optional wind-down length, and ignores anything malformed")
    func parsing() {
        let late = DemoLaunchOptions(arguments: ["-MapleDemoSchedule", "00:30-08:30/60"]).schedule
        #expect(late == SleepSchedule(bedtime: ClockTime(hour: 0, minute: 30), wake: ClockTime(hour: 8, minute: 30), windDownMinutes: 60))
        let standardWindDown = DemoLaunchOptions(arguments: ["-MapleDemoSchedule", "22:45-06:15"]).schedule
        #expect(standardWindDown?.windDownMinutes == SleepSchedule.standard.windDownMinutes)
        for bad in ["23:00", "25:00-07:00", "23:00-07:60", "23-07", "23:00-07:00/x", "23:00-07:00/30/5"] {
            #expect(DemoLaunchOptions(arguments: ["-MapleDemoSchedule", bad]).schedule == nil, "\(bad)")
        }
        #expect(DemoLaunchOptions(arguments: ["-MapleDemoSchedule", "00:30-08:30"]).isActive)
    }

    @Test("The schedule is saved in memory and the phase clock follows it")
    func wiring() throws {
        let folder = try temporaryDirectory()
        let options = DemoLaunchOptions(arguments: ["-MapleDemoSpecies", "23", "-MapleDemoPhase", "windDown",
                                                    "-MapleDemoSchedule", "00:30-08:30/60"])
        let stores = MapleStores.make(options, directory: folder, calendar: utc, now: now)
        #expect(stores.schedule.schedule.bedtime == ClockTime(hour: 0, minute: 30))
        #expect(stores.schedule.hasSavedSchedule)
        #expect(stores.collection.schedule == stores.schedule.weekly)
        #expect(NowPhase.resolve(date: stores.clock.now(), schedule: stores.schedule.schedule, calendar: utc) == .windDown)
        #expect(!files(in: folder).contains("schedule.json"))

        let fresh = MapleStores.make(DemoLaunchOptions(arguments: ["-MapleDemoFresh", "YES", "-MapleDemoSchedule", "00:30-08:30"]),
                                     directory: folder, calendar: utc, now: now)
        #expect(!fresh.schedule.hasSavedSchedule)
    }

    @Test("A weekend schedule and a demo day freeze the clock on that day's evening")
    func weekendDemo() throws {
        let folder = try temporaryDirectory()
        // `now` is Saturday 10 October 2026; the next Friday is the 16th, the next Wednesday the 14th.
        let friday = MapleStores.make(DemoLaunchOptions(arguments: [
            "-MapleDemoSpecies", "23", "-MapleDemoPhase", "evening", "-MapleDemoWeekendSchedule", "00:30-09:00/60",
            "-MapleDemoDay", "friday",
        ]), directory: folder, calendar: utc, now: now)
        let weekend = SleepSchedule(bedtime: ClockTime(hour: 0, minute: 30), wake: ClockTime(hour: 9), windDownMinutes: 60)
        #expect(friday.schedule.weekly == WeeklySleepSchedule(weekday: .standard, weekend: weekend))
        #expect(friday.collection.schedule == friday.schedule.weekly)
        // Friday evening runs to the weekend wind-down: 23:30 − 1h 20m.
        #expect(friday.clock.now() == at(2026, 10, 16, 22, 10))
        #expect(friday.schedule.schedule == weekend)
        #expect(friday.collection.nowState(at: friday.clock.now(), locale: Locale(identifier: "en_GB")).caption == "until wind-down · bed 00:30")

        let wednesday = MapleStores.make(DemoLaunchOptions(arguments: [
            "-MapleDemoSpecies", "23", "-MapleDemoPhase", "evening", "-MapleDemoWeekendSchedule", "00:30-09:00/60",
            "-MapleDemoDay", "Wednesday",
        ]), directory: folder, calendar: utc, now: now)
        #expect(wednesday.clock.now() == at(2026, 10, 14, 20, 55))
        #expect(wednesday.schedule.schedule == .standard)

        // Today's own weekday, a date, and something unreadable.
        let options = DemoLaunchOptions(arguments: ["-MapleDemoDay", "saturday"])
        #expect(options.demoDay(from: now, calendar: utc) == at(2026, 10, 10, 12))
        #expect(DemoLaunchOptions(arguments: ["-MapleDemoDay", "2026-10-09"]).demoDay(from: now, calendar: utc) == at(2026, 10, 9, 12))
        #expect(DemoLaunchOptions(arguments: ["-MapleDemoDay", "someday"]).demoDay(from: now, calendar: utc) == nil)
        // Both schedules together.
        let both = DemoLaunchOptions(arguments: ["-MapleDemoSchedule", "22:30-06:30/30", "-MapleDemoWeekendSchedule", "00:00-08:00"])
        #expect(both.weekly(replacing: .standard) == WeeklySleepSchedule(
            weekday: SleepSchedule(bedtime: ClockTime(hour: 22, minute: 30), wake: ClockTime(hour: 6, minute: 30), windDownMinutes: 30),
            weekend: SleepSchedule(bedtime: ClockTime(hour: 0), wake: ClockTime(hour: 8), windDownMinutes: 45)
        ))
        #expect(DemoLaunchOptions(arguments: []).weekly(replacing: .standard) == nil)
    }
}
#endif
