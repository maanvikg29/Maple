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

    private func plan(at date: Date, settings: ReminderSettings = .allOn, waiting: [WaitingLeaf] = []) -> ReminderPlan {
        ReminderPlan(.init(
            nights: UpcomingNight.nights(for: .standard, around: date, calendar: utc), settings: settings,
            waiting: waiting, now: date, calendar: utc, locale: Locale(identifier: "en_GB")
        ))
    }

    private func heldLeaf() -> WaitingLeaf {
        WaitingLeaf(speciesID: "rubrum", opensAt: at(2026, 10, 13, 6))
    }

    @Test("Rescheduling leaves exactly the plan's requests pending, at their wall-clock times")
    func reschedule() async throws {
        let center = FakeNotificationCenter()
        let scheduler = NotificationScheduler(center: center, clock: .fixed(now))
        let plan = plan(at: now, waiting: [heldLeaf()])
        await scheduler.reschedule(plan: plan)
        #expect(center.mapleIdentifiers == Set(plan.requests.map(\.id)))
        #expect(center.mapleIdentifiers.count == 8)
        #expect(scheduler.scheduled == plan.requests)
        let morning = try #require(center.pending["maple.reminder.morningLeaf.2026-10-12"])
        #expect(morning.trigger == .date(DateComponents(year: 2026, month: 10, day: 13, hour: 6, minute: 0, second: 0)))
        #expect(morning.request.interruption == .passive)
    }

    @Test("Rescheduling again replaces rather than duplicates, and drops what the plan no longer has")
    func replaces() async {
        let center = FakeNotificationCenter()
        let scheduler = NotificationScheduler(center: center, clock: .fixed(now))
        await scheduler.reschedule(plan: plan(at: now, waiting: [heldLeaf()]))
        await scheduler.reschedule(plan: plan(at: now, waiting: [heldLeaf()]))
        #expect(center.mapleIdentifiers.count == 8)
        // The leaf was opened: the morning reminder goes.
        await scheduler.reschedule(plan: plan(at: now))
        #expect(center.mapleIdentifiers.count == 7)
        #expect(!center.mapleIdentifiers.contains("maple.reminder.morningLeaf.2026-10-12"))
        // Wind-down turned off: nothing is left.
        await scheduler.reschedule(plan: plan(at: now, settings: .allOff))
        #expect(center.mapleIdentifiers.isEmpty)
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
        let everything = plan(at: now, waiting: [heldLeaf()])
        let morningOnly = plan(at: now, settings: ReminderSettings(windDown: false, morningLeaf: true), waiting: [heldLeaf()])
        let first = Task { await scheduler.reschedule(plan: everything) }
        let second = Task { await scheduler.reschedule(plan: morningOnly) }
        await first.value
        await second.value
        #expect(center.mapleIdentifiers == ["maple.reminder.morningLeaf.2026-10-12"])
    }

    @Test("Delivered reminders that no longer hold leave Notification Center")
    func clearsDelivered() async {
        let center = FakeNotificationCenter()
        center.delivered = ["maple.reminder.morningLeaf.2026-10-11", "maple.reminder.windDown.2026-10-11", "com.example.other"]
        let scheduler = NotificationScheduler(center: center, clock: .fixed(at(2026, 10, 12, 12)))
        // Midday, nothing waiting: both Maple notifications are out of date; the other app's stays.
        await scheduler.reschedule(plan: plan(at: at(2026, 10, 12, 12)))
        #expect(Set(center.removedDelivered) == ["maple.reminder.morningLeaf.2026-10-11", "maple.reminder.windDown.2026-10-11"])
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

    @Test("A tap on the morning leaf routes to the reveal, once; wind-down routes nowhere")
    func route() {
        let scheduler = NotificationScheduler(center: FakeNotificationCenter(), clock: .fixed(now))
        scheduler.handleTap(identifier: "maple.reminder.windDown.2026-10-12")
        #expect(scheduler.pendingRoute == nil)
        scheduler.handleTap(identifier: "com.example.other")
        #expect(scheduler.pendingRoute == nil)
        scheduler.handleTap(identifier: "maple.reminder.morningLeaf.2026-10-12")
        #expect(scheduler.pendingRoute == .reveal)
        #expect(scheduler.takeRoute() == .reveal)
        #expect(scheduler.pendingRoute == nil)
        #expect(scheduler.takeRoute() == nil)
    }

    @Test("While Maple is open, only the morning leaf shows, as a banner")
    func foreground() {
        #expect(ReminderNotificationDelegate.foregroundOptions(for: "maple.reminder.windDown.2026-10-12").isEmpty)
        #expect(ReminderNotificationDelegate.foregroundOptions(for: "maple.reminder.morningLeaf.2026-10-12") == [.banner, .list])
        #expect(ReminderNotificationDelegate.foregroundOptions(for: "com.example.other").isEmpty)
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
    @Test("Both reminders are on by default, and each switch is saved")
    func persisted() throws {
        let url = try temporaryDirectory().appendingPathComponent(AppSettings.file)
        let settings = AppSettings(storage: JSONStorage(.file(url)), regionCode: "GB")
        #expect(settings.windDownReminder)
        #expect(settings.morningLeafReminder)
        #expect(settings.reminders == .allOn)
        settings.windDownReminder = false
        let reloaded = AppSettings(storage: JSONStorage(.file(url)), regionCode: "GB")
        #expect(!reloaded.windDownReminder)
        #expect(reloaded.morningLeafReminder)
        #expect(reloaded.reminders == ReminderSettings(windDown: false, morningLeaf: true))
    }

    @Test("A settings file from before the reminders existed turns them on")
    func olderFile() throws {
        let old = #"{"version":1,"hemisphere":"southern","sleepGoalMinutes":480,"revealSound":true}"#
        let snapshot = try JSONDecoder().decode(SettingsSnapshot.self, from: Data(old.utf8))
        #expect(snapshot.windDownReminder)
        #expect(snapshot.morningLeafReminder)
        #expect(snapshot.hemisphere == .southern)
        let roundTrip = try JSONDecoder().decode(SettingsSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(roundTrip == snapshot)
    }
}
