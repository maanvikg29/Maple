import Foundation
import Testing
@testable import MapleCore
@testable import MapleServices

/// iOS's notification centre as the test says it is: what it allows, what the prompt answers, and what is pending.
@MainActor
final class FakeReminderCenter: ReminderCenter {
    struct Failed: Error {}

    var status: ReminderAuthorization = .notDetermined
    /// What the member answers when Apple's prompt is shown.
    var answer = true
    var promptFails = false
    private(set) var prompts = 0
    /// The pending reminders, as the last `schedule(_:)` left them.
    private(set) var pending: [Reminder] = []
    private(set) var scheduleCalls = 0

    func authorization() async -> ReminderAuthorization { status }

    func requestAuthorization() async throws -> Bool {
        prompts += 1
        if promptFails { throw Failed() }
        if status == .notDetermined { status = answer ? .allowed : .denied }
        return status == .allowed
    }

    func schedule(_ reminders: [Reminder]) async throws {
        scheduleCalls += 1
        pending = reminders
    }

    var pendingKinds: [ReminderKind] { pending.map(\.kind) }
}

@Suite("Reminders")
@MainActor
struct RemindersTests {
    private let now = at(2026, 10, 10, 15)
    private let gb = Locale(identifier: "en_GB")

    private func reminders(
        _ center: FakeReminderCenter, storage: JSONStorage<ReminderSettings> = JSONStorage(.memory),
        schedule: SleepSchedule = .standard
    ) -> Reminders {
        Reminders(storage: storage, center: center, schedule: schedule, locale: gb)
    }

    @Test("A first launch wants the wind-down reminder only, and writes nothing")
    func defaults() throws {
        let folder = try temporaryDirectory()
        let store = reminders(FakeReminderCenter(), storage: JSONStorage(.file(folder.appendingPathComponent(Reminders.file))))
        #expect(store.settings.windDown)
        #expect(!store.settings.morning)
        #expect(store.settings.primerOfferedAt == nil)
        #expect(store.authorization == nil)
        #expect(files(in: folder).isEmpty)
    }

    @Test("Nothing is scheduled, or touched, before iOS has been asked")
    func notDetermined() async {
        let center = FakeReminderCenter()
        let store = reminders(center)
        await store.update(schedule: SleepSchedule(bedtime: ClockTime(hour: 22), wake: ClockTime(hour: 6), windDownMinutes: 30))
        #expect(center.scheduleCalls == 0)

        await store.refresh()
        #expect(store.authorization == .notDetermined)
        #expect(center.pending.isEmpty)
        #expect(!store.isOn(.windDown))
        #expect(store.shouldOfferPrimer)
    }

    @Test("Allowing notifications schedules the wind-down reminder at the wind-down start")
    func allow() async {
        let center = FakeReminderCenter()
        let store = reminders(center)
        await store.refresh()
        #expect(await store.requestAuthorization())
        #expect(center.prompts == 1)
        #expect(store.authorization == .allowed)
        #expect(center.pendingKinds == [.windDown])
        #expect(center.pending.first?.time == ClockTime(hour: 22, minute: 15))
        #expect(center.pending.first?.body == "Bed at 23:00. Let the evening slow down.")
        #expect(store.isOn(.windDown))
        #expect(!store.isOn(.morning))
        #expect(!store.shouldOfferPrimer)
    }

    @Test("Allowing from the morning toggle turns the morning check-in on too")
    func allowEnabling() async {
        let center = FakeReminderCenter()
        let store = reminders(center)
        await store.refresh()
        await store.requestAuthorization(enabling: .morning)
        #expect(store.settings.morning)
        #expect(center.pendingKinds == [.windDown, .morning])
        #expect(center.pending.last?.time == ClockTime(hour: 7, minute: 30))
    }

    @Test("Refusing schedules nothing and changes no setting")
    func refuse() async {
        let center = FakeReminderCenter()
        center.answer = false
        let store = reminders(center)
        await store.refresh()
        #expect(!(await store.requestAuthorization(enabling: .morning)))
        #expect(store.isDenied)
        #expect(!store.settings.morning)
        #expect(center.pending.isEmpty)
        #expect(!store.shouldOfferPrimer)
    }

    @Test("A failing prompt reads iOS's answer anyway")
    func promptFails() async {
        let center = FakeReminderCenter()
        center.promptFails = true
        let store = reminders(center)
        await store.refresh()
        #expect(!(await store.requestAuthorization()))
        #expect(store.authorization == .notDetermined)
        #expect(!store.isRequesting)
    }

    @Test("Turning a reminder on needs iOS's permission first")
    func setNeedsPermission() async {
        let center = FakeReminderCenter()
        let store = reminders(center)
        await store.refresh()
        #expect(!(await store.set(.morning, on: true)))
        #expect(!store.settings.morning)

        center.status = .denied
        await store.refresh()
        #expect(!(await store.set(.morning, on: true)))
        #expect(!store.settings.morning)
        // Turning off never needs asking.
        #expect(await store.set(.windDown, on: false))
        #expect(!store.settings.windDown)
    }

    @Test("Toggles schedule and unschedule at once, and are saved")
    func toggles() async throws {
        let url = try temporaryDirectory().appendingPathComponent(Reminders.file)
        let center = FakeReminderCenter()
        center.status = .allowed
        let store = reminders(center, storage: JSONStorage(.file(url)))
        await store.refresh()
        #expect(center.pendingKinds == [.windDown])

        #expect(await store.set(.morning, on: true))
        #expect(center.pendingKinds == [.windDown, .morning])
        #expect(await store.set(.windDown, on: false))
        #expect(center.pendingKinds == [.morning])
        #expect(await store.set(.morning, on: false))
        #expect(center.pending.isEmpty)

        let reloaded = reminders(center, storage: JSONStorage(.file(url)))
        #expect(reloaded.settings == store.settings)
        #expect(!reloaded.settings.windDown)
    }

    @Test("A new schedule moves the reminders")
    func scheduleChange() async {
        let center = FakeReminderCenter()
        center.status = .allowed
        let store = reminders(center)
        await store.refresh()
        await store.set(.morning, on: true)
        let early = SleepSchedule(bedtime: ClockTime(hour: 22), wake: ClockTime(hour: 6), windDownMinutes: 60)
        await store.update(schedule: early)
        #expect(center.pending.map(\.time) == [ClockTime(hour: 21), ClockTime(hour: 6, minute: 30)])
        #expect(center.pending.first?.body == "Bed at 22:00. Let the evening slow down.")

        // The same schedule again schedules nothing new.
        let calls = center.scheduleCalls
        await store.update(schedule: early)
        #expect(center.scheduleCalls == calls)
    }

    @Test("Notifications turned off in Settings remove the pending reminders on the next foreground")
    func revokedInSettings() async {
        let center = FakeReminderCenter()
        center.status = .allowed
        let store = reminders(center)
        await store.refresh()
        #expect(!center.pending.isEmpty)

        center.status = .denied
        await store.refresh()
        #expect(center.pending.isEmpty)
        #expect(!store.isOn(.windDown))
        // The member's wish is kept for when they allow notifications again.
        #expect(store.settings.windDown)

        center.status = .allowed
        await store.refresh()
        #expect(center.pendingKinds == [.windDown])
    }

    @Test("The primer is offered on its own once")
    func primerOnce() async throws {
        let url = try temporaryDirectory().appendingPathComponent(Reminders.file)
        let center = FakeReminderCenter()
        let store = reminders(center, storage: JSONStorage(.file(url)))
        #expect(!store.shouldOfferPrimer) // iOS not read yet
        await store.refresh()
        #expect(store.shouldOfferPrimer)
        store.markPrimerOffered(at: now)
        #expect(!store.shouldOfferPrimer)
        store.markPrimerOffered(at: now.addingTimeInterval(60))
        #expect(store.settings.primerOfferedAt == now)

        let reloaded = reminders(center, storage: JSONStorage(.file(url)))
        await reloaded.refresh()
        #expect(!reloaded.shouldOfferPrimer)
    }

    @Test("Settings decode tolerantly: missing values take their defaults")
    func tolerantDecoding() throws {
        let empty = try JSONDecoder().decode(ReminderSettings.self, from: Data("{}".utf8))
        #expect(empty == ReminderSettings())
        let partial = try JSONDecoder().decode(ReminderSettings.self, from: Data(#"{"morning":true}"#.utf8))
        #expect(partial.windDown)
        #expect(partial.morning)
    }

    @Test("DEBUG demos never offer the primer")
    func demos() throws {
        let stores = MapleStores.make(DemoLaunchOptions(), directory: try temporaryDirectory(), calendar: utc, now: now)
        #expect(stores.reminders.settings.primerOfferedAt != nil)
        #expect(!stores.reminders.shouldOfferPrimer)
    }

    @Test("The live stores read and save reminders.json beside the collection")
    func live() async throws {
        let folder = try temporaryDirectory()
        let center = FakeReminderCenter()
        center.status = .allowed
        let stores = MapleStores.live(
            directory: folder, calendar: utc, now: now, healthAuthorizer: FakeHealthAuthorizer(), reminderCenter: center
        )
        await stores.reminders.refresh()
        #expect(center.pendingKinds == [.windDown])
        await stores.reminders.set(.morning, on: true)
        #expect(files(in: folder).contains(Reminders.file))
    }
}
