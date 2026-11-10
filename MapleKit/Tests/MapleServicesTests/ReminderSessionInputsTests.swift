import Foundation
import MapleStorage
import Testing
@testable import MapleCore
@testable import MapleServices

/// A session store on a manual clock over a planted collection, with the schedule and settings the plan reads.
@MainActor
private final class InputsHarness {
    let time = ManualFocusTime(wall: at(2026, 10, 12, 14))
    let collection: CollectionStore
    let schedule: ScheduleStore
    let settings: AppSettings
    let sessions: FocusSessionStore

    let six = AppSet(id: AppSet.distractionsID, name: "Distractions", selection: Data("six".utf8),
                     summary: SelectionSummary(mode: .blockThese, apps: 6, sites: 0, categories: 0))

    init() {
        collection = CollectionStore(storage: JSONStorage(.memory), context: testContext, now: at(2026, 10, 1, 9))
        collection.raise(.firstLeaf, to: 1, at: at(2026, 10, 1, 9))
        collection.openReveals(at: at(2026, 10, 1, 9, 5))
        schedule = ScheduleStore(storage: JSONStorage(.memory), collection: collection)
        settings = AppSettings(storage: JSONStorage(.memory), regionCode: "GB")
        let ledger = MemoryLedgerStore()
        let blocking = PreviewBlockingService(authorization: .allowed)
        let writer = LedgerWriter(store: ledger, time: time, deviceID: UUID(), writer: .app, source: blocking.source)
        sessions = FocusSessionStore(ledger: ledger, writer: writer, blocking: blocking, collection: collection,
                                     credited: [.live, .preview], liveActivity: NoLiveActivityController(), appBuild: "test")
    }

    func plan() -> ReminderPlan? {
        ReminderInputs.plan(collection: collection, schedule: schedule, settings: settings, windDownOpenedAt: nil,
                            sessions: sessions, locale: Locale(identifier: "en_GB"))
    }

    /// Starts Study for `minutes`; nil if the store refused.
    func start(minutes: Int = 50) async -> UUID? {
        let preset = FocusPreset.defaults(appSetID: AppSet.distractionsID)[0]
        let request = FocusSessionStore.StartRequest(preset: preset, minutes: minutes, appSet: six, from: .focusTab)
        guard case .started(let id) = await sessions.start(request) else { return nil }
        return id
    }
}

@Suite("Reminder inputs from the session store")
@MainActor
struct ReminderSessionInputsTests {
    @Test("Nothing is planned before the store's first replay, so a pending end is never removed")
    func waitsForReplay() async throws {
        let h = InputsHarness()
        #expect(!h.sessions.isLedgerReadable)
        #expect(h.plan() == nil)
        await h.sessions.refresh()
        let plan = try #require(h.plan())
        #expect(plan.requests.contains { $0.kind == .windDown })
        #expect(!plan.requests.contains { $0.kind == .sessionEnd })
    }

    @Test("A running session's end is planned at its planned end, named by its id")
    func sessionEnd() async throws {
        let h = InputsHarness()
        await h.sessions.refresh()
        let id = try #require(await h.start())
        let end = try #require(h.plan()?.requests.first { $0.kind == .sessionEnd })
        #expect(end.id == ReminderKind.sessionEndIdentifier(for: id))
        #expect(end.fireDate == at(2026, 10, 12, 14, 50))
        #expect(end.isAbsolute)
        #expect(end.title == "Session done")
        #expect(end.body == "Study, 50 minutes")
    }

    @Test("The plan runs on trusted time: a clock set forward keeps the end planned, after its real time left")
    func trustedTime() async throws {
        let h = InputsHarness()
        await h.sessions.refresh()
        let id = try #require(await h.start())
        // Ten minutes on, the member sets the clock to 16:00.
        h.time.advance(10 * 60)
        h.time.setWall(at(2026, 10, 12, 16))
        await h.sessions.refresh()
        #expect(h.sessions.now == at(2026, 10, 12, 14, 10))
        let plan = try #require(h.plan())
        let end = try #require(plan.requests.first { $0.kind == .sessionEnd })
        #expect(end.id == ReminderKind.sessionEndIdentifier(for: id))
        #expect(end.fireDate == at(2026, 10, 12, 14, 50))

        // The scheduler's own clock says 16:00; at the store's time the end is 40 minutes away.
        let center = FakeNotificationCenter()
        let scheduler = NotificationScheduler(center: center, clock: .fixed(at(2026, 10, 12, 16)))
        await scheduler.reschedule(plan: plan, now: h.sessions.now)
        let pending = try #require(center.pending[ReminderKind.sessionEndIdentifier(for: id)])
        #expect(pending.trigger == .after(40 * 60))
    }

    @Test("Ending the session, or releasing every app, takes its end out of the plan")
    func endedSession() async throws {
        let h = InputsHarness()
        await h.sessions.refresh()
        _ = try #require(await h.start())
        await h.sessions.end(.endedEarly)
        let afterEnd = try #require(h.plan())
        #expect(!afterEnd.requests.contains { $0.kind == .sessionEnd })

        let released = InputsHarness()
        await released.sessions.refresh()
        _ = try #require(await released.start())
        await released.sessions.releaseAll()
        let afterRelease = try #require(released.plan())
        #expect(!afterRelease.requests.contains { $0.kind == .sessionEnd })
    }

    @Test("The study reminder skips the day a session started")
    func studySkipsStartedDay() async throws {
        let h = InputsHarness()
        h.settings.studyReminderTime = ClockTime(hour: 16)
        await h.sessions.refresh()
        let before = try #require(h.plan()).requests.filter { $0.kind == .studyReminder }
        #expect(before.first?.fireDate == at(2026, 10, 12, 16))
        _ = try #require(await h.start())
        #expect(h.sessions.lastSessionStart == at(2026, 10, 12, 14))
        let after = try #require(h.plan()).requests.filter { $0.kind == .studyReminder }
        #expect(after.first?.fireDate == at(2026, 10, 13, 16))
    }
}
