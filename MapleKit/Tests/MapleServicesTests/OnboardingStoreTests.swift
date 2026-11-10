import Foundation
import Testing
@testable import MapleCore
@testable import MapleServices

/// The weekly schedule on disk, and the first run's progress across relaunches.
@Suite("Weekly schedule store and onboarding progress")
@MainActor
struct OnboardingStoreTests {
    private let weekend = SleepSchedule(bedtime: ClockTime(hour: 0, minute: 30), wake: ClockTime(hour: 9), windDownMinutes: 60)

    @Test("A schedule file from before weekend schedules loads as the same schedule every night, losslessly")
    func migration() throws {
        let folder = try temporaryDirectory()
        let url = folder.appendingPathComponent(MapleStores.scheduleFile)
        // The single-schedule file an earlier build wrote.
        let saved = Date(timeIntervalSinceReferenceDate: 813_000_000)
        let old = #"{"schedule":{"bedtime":{"hour":22,"minute":30},"wake":{"hour":6,"minute":30},"windDownMinutes":30},"savedAt":813000000}"#
        try Data(old.utf8).write(to: url)

        let collection = CollectionStore(storage: JSONStorage(.memory), context: testContext, now: at(2026, 10, 1, 9))
        let schedules = ScheduleStore(storage: JSONStorage(.file(url)), collection: collection)
        let mine = SleepSchedule(bedtime: ClockTime(hour: 22, minute: 30), wake: ClockTime(hour: 6, minute: 30), windDownMinutes: 30)
        #expect(schedules.hasSavedSchedule)
        #expect(schedules.savedAt == saved)
        #expect(schedules.weekly == .everyNight(mine))
        #expect(schedules.weekly.weekend == nil)
        #expect(schedules.schedule == mine)
        #expect(collection.schedule == .everyNight(mine))
        // Nothing was rewritten just by reading it.
        #expect(try String(contentsOf: url, encoding: .utf8) == old)

        // A weekend schedule is saved beside the weekday one, and an older build still reads the weekday one.
        schedules.save(WeeklySleepSchedule(weekday: mine, weekend: weekend), at: at(2026, 10, 3, 12))
        let reloaded = ScheduleStore(storage: JSONStorage(.file(url)), collection: collection)
        #expect(reloaded.weekly == WeeklySleepSchedule(weekday: mine, weekend: weekend))
        let object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let schedule = try #require(object["schedule"] as? [String: Any])
        #expect(schedule["weekend"] != nil)
        struct OlderBuild: Decodable { var schedule: SleepSchedule; var savedAt: Date }
        #expect(try JSONDecoder().decode(OlderBuild.self, from: Data(contentsOf: url)).schedule == mine)
    }

    @Test("Saving a weekly schedule earns the Sugar maple once; later saves apply from the next night")
    func weeklySave() {
        let collection = CollectionStore(storage: JSONStorage(.memory), context: testContext, now: at(2026, 10, 8, 12))
        let schedules = ScheduleStore(storage: JSONStorage(.memory), collection: collection)
        let week = WeeklySleepSchedule(weekday: .standard, weekend: weekend)
        #expect(schedules.save(week, at: at(2026, 10, 8, 20)).map(\.speciesID) == ["saccharum"])
        #expect(collection.schedule == week)
        #expect(schedules.save(.standard, at: at(2026, 10, 9, 20)).isEmpty)
        #expect(schedules.save(week, at: at(2026, 10, 9, 21)).isEmpty)
        #expect(collection.snapshot.unlocks.map(\.speciesID) == ["saccharum"])
        // Friday night began under the weekly schedule; the two edits at 20:00 and 21:00 that evening are kept.
        #expect(collection.snapshot.nights.pastSchedules.map(\.through) == [LocalDay(year: 2026, month: 10, day: 9), LocalDay(year: 2026, month: 10, day: 9)])
        #expect(collection.snapshot.nights.times(for: LocalDay(year: 2026, month: 10, day: 9), current: collection.schedule, calendar: utc).bedtime
            == at(2026, 10, 10, 0, 30))
        // Tonight's schedule follows the store's clock.
        schedules.clock = .fixed(at(2026, 10, 9, 22))
        #expect(schedules.schedule == weekend)
        schedules.clock = .fixed(at(2026, 10, 11, 22))
        #expect(schedules.schedule == .standard)
        #expect(schedules.tonight(at: at(2026, 10, 10, 2)) == weekend)
    }

    /// The member's real stores and onboarding file in `folder`, as a launch builds them.
    private func launch(_ folder: URL) -> (stores: MapleStores, onboarding: OnboardingStore) {
        (MapleStores.live(directory: folder, calendar: utc, now: at(2026, 10, 1, 21)), OnboardingStore.live(directory: folder))
    }

    @Test("Killed mid-flow, the relaunch opens on the same question with the same answers")
    func resumeQuestions() throws {
        let folder = try temporaryDirectory()
        var run = launch(folder)
        #expect(run.onboarding.step(schedule: run.stores.schedule, collection: run.stores.collection) == .weekdayWake)
        var answers = run.onboarding.answers
        answers.weekdayWake = ClockTime(hour: 6, minute: 30)
        run.onboarding.answers = answers
        run.onboarding.go(to: .weekendWake)
        answers.weekendWake = ClockTime(hour: 8)
        run.onboarding.answers = answers
        run.onboarding.go(to: .sleepNeed)

        run = launch(folder)
        #expect(run.onboarding.step(schedule: run.stores.schedule, collection: run.stores.collection) == .sleepNeed)
        #expect(run.onboarding.answers.weekdayWake == ClockTime(hour: 6, minute: 30))
        #expect(run.onboarding.answers.weekendWake == ClockTime(hour: 8))

        // The schedule step's draft survives too, and a changed answer proposes again.
        run.onboarding.go(to: .schedule)
        let draft = WeeklySleepSchedule.everyNight(SleepSchedule(bedtime: ClockTime(hour: 22), wake: ClockTime(hour: 6, minute: 30), windDownMinutes: 45))
        run.onboarding.setScheduleDraft(draft)
        run = launch(folder)
        #expect(run.onboarding.step(schedule: run.stores.schedule, collection: run.stores.collection) == .schedule)
        #expect(run.onboarding.scheduleShown == draft)
        run.onboarding.setScheduleDraft(run.onboarding.progress.answers.proposedSchedule)
        #expect(run.onboarding.progress.scheduleDraft == nil)
        run.onboarding.setScheduleDraft(draft)
        answers = run.onboarding.answers
        answers.sleepNeedMinutes = 480
        run.onboarding.answers = answers
        #expect(run.onboarding.scheduleShown == answers.proposedSchedule)
        #expect(Set(files(in: folder)).isSuperset(of: [OnboardingStore.file]))
    }

    @Test("After Save schedule the relaunch goes to the primers, never back to the schedule, and the Sugar maple stays one")
    func resumeAfterSave() throws {
        let folder = try temporaryDirectory()
        var run = launch(folder)
        run.onboarding.go(to: .schedule)
        run.stores.schedule.save(run.onboarding.scheduleShown, at: at(2026, 10, 1, 21, 30))
        run.onboarding.go(to: .health)

        // Killed on the Apple Health primer.
        run = launch(folder)
        #expect(run.stores.schedule.resumeFirstRun(at: at(2026, 10, 1, 21, 40)) == .sprout)
        #expect(run.onboarding.step(schedule: run.stores.schedule, collection: run.stores.collection) == .health)
        run.onboarding.answered(.health)
        #expect(run.onboarding.progress.step == .notifications)

        // Killed on the notifications primer; even a file that still says "schedule" can't bring the schedule back.
        run = launch(folder)
        #expect(run.onboarding.step(schedule: run.stores.schedule, collection: run.stores.collection) == .notifications)
        run.onboarding.answered(.notifications)
        run.onboarding.go(to: .schedule)
        run = launch(folder)
        #expect(run.onboarding.step(schedule: run.stores.schedule, collection: run.stores.collection) == .sprout)
        #expect(run.stores.collection.unlocks.map(\.speciesID) == ["saccharum"])

        // Placed: the first run is over.
        run.stores.collection.openReveals(["saccharum"], at: at(2026, 10, 1, 22))
        run = launch(folder)
        #expect(run.onboarding.step(schedule: run.stores.schedule, collection: run.stores.collection) == nil)
        #expect(run.stores.schedule.firstRun == .finished)
        #expect(run.stores.collection.unlocks.count == 1)
    }

    @Test("An onboarding file that can't be read is never overwritten")
    func unreadable() throws {
        let folder = try temporaryDirectory()
        let url = folder.appendingPathComponent(OnboardingStore.file)
        let first = OnboardingStore(storage: JSONStorage(.file(url)))
        first.go(to: .windDown)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path) }

        let locked = OnboardingStore(storage: JSONStorage(.file(url)))
        #expect(!locked.isAvailable)
        #expect(locked.progress == OnboardingProgress())
        locked.go(to: .sleepNeed)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        #expect(locked.reloadIfUnavailable())
        #expect(locked.progress.step == .windDown)
    }
}
