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
        #expect(stores.collection.schedule == stores.schedule.schedule)
        #expect(NowPhase.resolve(date: stores.clock.now(), schedule: stores.schedule.schedule, calendar: utc) == .windDown)
        #expect(!files(in: folder).contains("schedule.json"))

        let fresh = MapleStores.make(DemoLaunchOptions(arguments: ["-MapleDemoFresh", "YES", "-MapleDemoSchedule", "00:30-08:30"]),
                                     directory: folder, calendar: utc, now: now)
        #expect(!fresh.schedule.hasSavedSchedule)
    }
}
#endif
