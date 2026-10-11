import Foundation
import Testing
import UserNotifications
@testable import MapleCore
@testable import MapleServices

/// A notification center that keeps its requests in memory and records what was asked of it.
@MainActor
final class FakeNotificationCenter: NotificationCentering {
    var status: ReminderAuthorization
    /// What the prompt answers.
    var grants = true
    private(set) var prompts = 0
    private(set) var pending: [String: (request: ReminderRequest, trigger: ReminderTrigger)] = [:]
    var delivered: [String] = []
    private(set) var removedDelivered: [String] = []
    private(set) var adds = 0

    init(status: ReminderAuthorization = .allowed, pending others: [String] = []) {
        self.status = status
        for identifier in others {
            let request = ReminderRequest(
                id: identifier, kind: .windDown, fireDate: .distantFuture, calendar: utc, title: "", body: "",
                threadID: "", interruption: .active, playsSound: false
            )
            pending[identifier] = (request, .after(60))
        }
    }

    func authorization() async -> ReminderAuthorization { status }

    func requestAuthorization() async throws -> Bool {
        prompts += 1
        status = grants ? .allowed : .denied
        return grants
    }

    func pendingIdentifiers() async -> [String] { Array(pending.keys) }
    func deliveredIdentifiers() async -> [String] { delivered }

    func removePending(_ identifiers: [String]) {
        for identifier in identifiers { pending[identifier] = nil }
    }

    func removeDelivered(_ identifiers: [String]) {
        removedDelivered += identifiers
        delivered.removeAll { identifiers.contains($0) }
    }

    func add(_ request: ReminderRequest, trigger: ReminderTrigger) async throws {
        // A real center answers later: let other work run in between, as it would.
        await Task.yield()
        adds += 1
        pending[request.id] = (request, trigger)
    }

    var mapleIdentifiers: Set<String> { Set(pending.keys.filter { $0.hasPrefix(ReminderKind.identifierPrefix) }) }
}

@Suite("Notification scheduler")
@MainActor
struct NotificationSchedulerTests {
    private let now = at(2026, 10, 12, 21)

    private func plan(at date: Date, settings: ReminderSettings = .allOn) -> ReminderPlan {
        ReminderPlan(.init(
            nights: UpcomingNight.nights(for: .standard, around: date, calendar: utc), settings: settings,
            now: date, calendar: utc, locale: Locale(identifier: "en_GB")
        ))
    }

    @Test("Rescheduling leaves exactly the plan's requests pending, at their wall-clock times")
    func reschedule() async throws {
        let center = FakeNotificationCenter()
        let scheduler = NotificationScheduler(center: center, clock: .fixed(now))
        let plan = plan(at: now)
        await scheduler.reschedule(plan: plan)
        #expect(center.mapleIdentifiers == Set(plan.requests.map(\.id)))
        #expect(center.mapleIdentifiers.count == 7)
        #expect(scheduler.scheduled == plan.requests)
        let tonight = try #require(center.pending["maple.reminder.windDown.2026-10-12"])
        #expect(tonight.trigger == .date(DateComponents(year: 2026, month: 10, day: 12, hour: 22, minute: 15, second: 0)))
        #expect(tonight.request.interruption == .active)
    }

    @Test("Rescheduling again replaces rather than duplicates, and drops what the plan no longer has")
    func replaces() async {
        let center = FakeNotificationCenter()
        let scheduler = NotificationScheduler(center: center, clock: .fixed(now))
        await scheduler.reschedule(plan: plan(at: now))
        await scheduler.reschedule(plan: plan(at: now))
        #expect(center.mapleIdentifiers.count == 7)
        // Wind-down turned off: nothing is left.
        await scheduler.reschedule(plan: plan(at: now, settings: .allOff))
        #expect(center.mapleIdentifiers.isEmpty)
    }

    @Test("A morning reminder left pending by an earlier build is removed")
    func leftoverMorningReminderRemoved() async {
        let center = FakeNotificationCenter(pending: ["maple.reminder.morningLeaf.2026-10-12"])
        let scheduler = NotificationScheduler(center: center, clock: .fixed(now))
        await scheduler.reschedule(plan: plan(at: now))
        #expect(center.pending["maple.reminder.morningLeaf.2026-10-12"] == nil)
        #expect(center.mapleIdentifiers.count == 7)
    }

    @Test("Other identifiers are never touched")
    func onlyMaple() async {
        let center = FakeNotificationCenter(pending: ["com.example.other", "focus.session"])
        let scheduler = NotificationScheduler(center: center, clock: .fixed(now))
        await scheduler.reschedule(plan: plan(at: now, settings: .allOff))
        #expect(Set(center.pending.keys) == ["com.example.other", "focus.session"])
    }

    @Test("Nothing is scheduled until iOS allows it, and anything left over is removed")
    func needsPermission() async {
        let center = FakeNotificationCenter(status: .allowed)
        let scheduler = NotificationScheduler(center: center, clock: .fixed(now))
        await scheduler.reschedule(plan: plan(at: now))
        #expect(center.mapleIdentifiers.count == 7)
        center.status = .denied
        await scheduler.reschedule(plan: plan(at: now))
        #expect(scheduler.authorization == .denied)
        #expect(center.mapleIdentifiers.isEmpty)
        #expect(scheduler.scheduled.isEmpty)

        let undecided = FakeNotificationCenter(status: .notDetermined)
        let fresh = NotificationScheduler(center: undecided, clock: .fixed(now))
        await fresh.reschedule(plan: plan(at: now))
        #expect(undecided.mapleIdentifiers.isEmpty)
        #expect(undecided.prompts == 0)
    }

    @Test("Never more than the next 7 days, whatever the plan holds")
    func horizon() async {
        let center = FakeNotificationCenter()
        let scheduler = NotificationScheduler(center: center, clock: .fixed(now))
        let far = ReminderRequest(
            id: "maple.reminder.windDown.2026-10-30", kind: .windDown, fireDate: at(2026, 10, 30, 22), calendar: utc,
            title: "Time to wind down", body: "Bed at 23:00.", threadID: "maple.windDown", interruption: .active, playsSound: true
        )
        let past = ReminderRequest(
            id: "maple.reminder.windDown.2026-10-01", kind: .windDown, fireDate: at(2026, 10, 1, 22), calendar: utc,
            title: "Time to wind down", body: "Bed at 23:00.", threadID: "maple.windDown", interruption: .active, playsSound: true
        )
        await scheduler.reschedule(plan: ReminderPlan(requests: [far, past]))
        #expect(center.mapleIdentifiers.isEmpty)
    }

    @Test("Two reschedules at once never interleave: the later plan wins")
    func serialised() async {
        let center = FakeNotificationCenter()
        let scheduler = NotificationScheduler(center: center, clock: .fixed(now))
        let first = Task { await scheduler.reschedule(plan: plan(at: now)) }
        let second = Task { await scheduler.reschedule(plan: plan(at: now, settings: .allOff)) }
        await first.value
        await second.value
        #expect(center.mapleIdentifiers.isEmpty)
    }

    @Test("A delivered wind-down reminder that no longer holds leaves Notification Center")
    func clearsDelivered() async {
        let center = FakeNotificationCenter()
        center.delivered = ["maple.reminder.windDown.2026-10-11", "com.example.other"]
        let scheduler = NotificationScheduler(center: center, clock: .fixed(at(2026, 10, 12, 12)))
        // Midday: last night's wind-down reminder is out of date; the other app's stays.
        await scheduler.reschedule(plan: plan(at: at(2026, 10, 12, 12)))
        #expect(center.removedDelivered == ["maple.reminder.windDown.2026-10-11"])
        #expect(center.delivered == ["com.example.other"])
    }

    @Test("The prompt asks once at a time and reports the answer")
    func prompt() async {
        let center = FakeNotificationCenter(status: .notDetermined)
        let scheduler = NotificationScheduler(center: center, clock: .fixed(now))
        #expect(await scheduler.requestAuthorization())
        #expect(scheduler.authorization == .allowed)
        #expect(center.prompts == 1)

        let declining = FakeNotificationCenter(status: .notDetermined)
        declining.grants = false
        let other = NotificationScheduler(center: declining, clock: .fixed(now))
        #expect(await other.requestAuthorization() == false)
        #expect(other.authorization == .denied)
    }

    @Test("DEBUG demo launches never touch the member's reminders")
    func demoLaunchesDontSchedule() async {
        let center = FakeNotificationCenter()
        let scheduler = NotificationScheduler(center: center, clock: .fixed(now))
        scheduler.schedulesReminders = false
        await scheduler.reschedule(plan: plan(at: now))
        #expect(center.adds == 0)
        #expect(center.mapleIdentifiers.isEmpty)
    }

    @Test("iOS's authorization states map onto Maple's three")
    func authorizationMapping() {
        #expect(ReminderAuthorization(.notDetermined) == .notDetermined)
        #expect(ReminderAuthorization(.denied) == .denied)
        #expect(ReminderAuthorization(.authorized) == .allowed)
        #expect(ReminderAuthorization(.provisional) == .allowed)
        #expect(ReminderAuthorization(.ephemeral) == .allowed)
    }
}

@Suite("Reminder settings")
@MainActor
struct ReminderSettingsTests {
    @Test("The wind-down reminder is on by default, and its switch is saved")
    func persisted() throws {
        let url = try temporaryDirectory().appendingPathComponent(AppSettings.file)
        let settings = AppSettings(storage: JSONStorage(.file(url)), regionCode: "GB")
        #expect(settings.windDownReminder)
        #expect(settings.reminders == .allOn)
        settings.windDownReminder = false
        let reloaded = AppSettings(storage: JSONStorage(.file(url)), regionCode: "GB")
        #expect(!reloaded.windDownReminder)
        #expect(reloaded.reminders == .allOff)
    }

    @Test("A settings file from before the reminders existed turns wind-down on")
    func olderFile() throws {
        let old = #"{"version":1,"hemisphere":"southern","sleepGoalMinutes":480,"revealSound":true}"#
        let snapshot = try JSONDecoder().decode(SettingsSnapshot.self, from: Data(old.utf8))
        #expect(snapshot.windDownReminder)
        #expect(snapshot.hemisphere == .southern)
        let roundTrip = try JSONDecoder().decode(SettingsSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(roundTrip == snapshot)
    }

    @Test("A settings file with the old morning-leaf switch still loads, and the switch is dropped on save")
    func olderFileWithMorningSwitch() throws {
        let old = #"{"version":1,"hemisphere":"northern","sleepGoalMinutes":450,"revealSound":false,"windDownReminder":false,"morningLeafReminder":true}"#
        let snapshot = try JSONDecoder().decode(SettingsSnapshot.self, from: Data(old.utf8))
        #expect(!snapshot.windDownReminder)
        #expect(snapshot.sleepGoalMinutes == 450)
        let saved = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        #expect(!saved.contains("morningLeaf"))
    }
}
