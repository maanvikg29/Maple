import Foundation
import MapleStorage
import Testing
@testable import MapleCore
@testable import MapleServices

/// Focus stores on a manual clock at 14:00 (the Day phase), an in-memory ledger and the given blocker, over a planted
/// collection, with Distractions holding six apps.
@MainActor
private struct ComposerStores {
    let time = ManualFocusTime(wall: at(2026, 10, 23, 14))
    let collection: CollectionStore
    let stores: FocusStores
    let settings = AppSettings(storage: JSONStorage(.memory))

    /// - Parameter started: `AppSettings.hasStartedFocus`: false for the first session ever.
    init(blocking: any BlockingService = PreviewBlockingService(), started: Bool = true) {
        collection = CollectionStore(storage: JSONStorage(.memory), context: testContext, now: at(2026, 10, 1, 9))
        collection.raise(.firstLeaf, to: 1, at: at(2026, 10, 1, 9))
        collection.openReveals(at: at(2026, 10, 1, 9, 5))
        let ledger = MemoryLedgerStore()
        let writer = LedgerWriter(store: ledger, time: time, deviceID: UUID(), writer: .app, source: blocking.source)
        let appSets = AppSetStore(storage: JSONStorage(.memory))
        let six = SelectionSummary(mode: .blockThese, apps: 6, sites: 0, categories: 0)
        _ = appSets.save(selection: Data("six".utf8), summary: six, to: AppSet.distractionsID)
        stores = FocusStores(
            sessions: FocusSessionStore(ledger: ledger, writer: writer, blocking: blocking, collection: collection,
                                        credited: [.live, .preview], liveActivity: NoLiveActivityController(), appBuild: "test"),
            presets: PresetStore(storage: JSONStorage(.memory), defaultAppSetID: AppSet.distractionsID),
            appSets: appSets,
            notes: SessionNotesStore(storage: JSONStorage(.memory)),
            mode: .live
        )
        settings.hasStartedFocus = started
    }

    var now: Date { stores.sessions.now }

    func status() -> FocusStatus {
        stores.status(at: now, collection: collection, settings: settings)
    }
}

@Suite("Focus status composer")
@MainActor
struct FocusStatusComposerTests {
    @Test("Home's Start is the last-used preset at its own length, read from the start screen's own model")
    func homeStart() async throws {
        let fixture = ComposerStores()
        await fixture.stores.sessions.refresh()
        let study = try #require(fixture.stores.presets.lastUsed)
        let model = fixture.stores.startScreen(preset: study, minutes: study.minutes, at: fixture.now,
                                               collection: fixture.collection, settings: fixture.settings)
        let status = fixture.status()
        #expect(status.start == FocusStart(model: model))
        #expect(status.start?.readiness == .ready(needsHold: false))
        #expect(status.start?.title == "Start study · 50m")
        #expect(status.blocking == .ready)
        #expect(status.remaining == nil)
        #expect(status.savedTodaySeconds == 0)
        #expect(status.savedTotalSeconds == 0)
    }

    @Test("The first session ever opens the start screen, from Home too, and the counts line is the definition")
    func firstSession() async throws {
        let fixture = ComposerStores(started: false)
        await fixture.stores.sessions.refresh()
        #expect(fixture.status().start?.readiness == .needsStartScreen(.firstSession))
        // Home's Start offers what the start screen opens on: Quick for the first session (P4, F1-20).
        let quick = try #require(fixture.stores.presets.presets.first { $0.verb == .quick })
        #expect(fixture.status().start?.presetID == quick.id)
        #expect(fixture.status().start?.title == "Start a quick session · 25m")
        let study = try #require(fixture.stores.presets.lastUsed)
        let model = fixture.stores.startScreen(preset: study, minutes: 50, at: fixture.now, collection: fixture.collection,
                                               settings: fixture.settings, locale: Locale(identifier: "en_GB"))
        #expect(model.countsLine == "Time your chosen apps stayed locked while you were awake.")
    }

    @Test("Blocking reads the build and the last probe: needs permission, or not in this build")
    func blocking() async {
        let declined = ComposerStores(blocking: PreviewBlockingService(authorization: .declined))
        await declined.stores.sessions.refresh()
        #expect(declined.stores.blockingStatus == .needsPermission)
        #expect(declined.status().blocking == .needsPermission)
        #expect(declined.status().start?.readiness == .needsStartScreen(.blockingUnavailable))

        let free = ComposerStores(blocking: UnavailableBlockingService())
        await free.stores.sessions.refresh()
        #expect(free.stores.blockingStatus == .notInThisBuild)
        #expect(free.status().blocking == .notInThisBuild)
    }

    @Test("A running session's time left runs on the store's trusted time")
    func running() async throws {
        let fixture = ComposerStores()
        await fixture.stores.sessions.refresh()
        let study = try #require(fixture.stores.presets.lastUsed)
        let request = FocusSessionStore.StartRequest(preset: study, minutes: 50, appSet: fixture.stores.appSets.set(id: AppSet.distractionsID),
                                                     from: .focusTab)
        guard case .started = await fixture.stores.sessions.start(request) else {
            Issue.record("not started")
            return
        }
        fixture.time.advance(18 * 60)
        let remaining = try #require(fixture.status().remaining)
        #expect(abs(remaining - 32 * 60) < 0.001)
    }

    @Test("The start screen's model takes the dial's length, its stage and the turn")
    func startScreen() async throws {
        let fixture = ComposerStores()
        await fixture.stores.sessions.refresh()
        let study = try #require(fixture.stores.presets.lastUsed)
        let model = fixture.stores.startScreen(preset: study, minutes: 65, at: fixture.now, collection: fixture.collection,
                                               settings: fixture.settings, stage: .locking, hasTurned: true)
        #expect(model.minutes == 65)
        #expect(model.capsuleTitle == "Locking 6 apps…")
        #expect(model.hint == nil)
        #expect(model.blockingLine.printed == "Blocking 6 apps · Steady ›")
        #expect(model.strictness == .steady)
    }

    @Test("The next hours leaf is the lowest locked hours-saved rung")
    func nextHoursLeaf() throws {
        let fixture = ComposerStores()
        let leaf = try #require(fixture.stores.nextHoursLeaf(at: fixture.now, collection: fixture.collection))
        let rungs = fixture.collection.progress(at: fixture.now).filter { $0.category == .hoursSaved && $0.state == .locked }
        #expect(leaf.category == .hoursSaved)
        #expect(leaf.state == .locked)
        #expect(leaf.threshold == rungs.map(\.threshold).min())
    }
}
