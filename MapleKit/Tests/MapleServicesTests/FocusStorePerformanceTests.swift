import Foundation
import Testing
@testable import MapleCore
@testable import MapleServices

/// F1 design §8.1 on the real workload: a member who does four 50-minute sessions a day, with a checkpoint every minute,
/// for two months (about 13,400 events in the ledger's month files), read through `FileLedgerStore` by the session
/// store. In the Debug simulator, each figure is the fastest of 3 after an untimed warm-up, so a busy moment on the
/// machine doesn't fail a limit.
@Suite("Focus store performance", .serialized)
@MainActor
struct FocusStorePerformanceTests {
    private let device = UUID()

    /// Writes the two months to `folder` as the app writes them (one file per month, each last changed at its last event).
    /// - Returns: How many events were written.
    private func writeTwoMonths(to folder: URL) throws -> Int {
        let memory = MemoryLedgerStore()
        let time = ManualFocusTime(wall: at(2026, 9, 1, 8))
        let writer = LedgerWriter(store: memory, time: time, deviceID: device, writer: .app, source: .live)
        let first = LocalDay(year: 2026, month: 9, day: 1)
        for offset in 0..<62 {
            let day = first.adding(days: offset, calendar: utc)
            let midnight = day.startDate(in: utc)
            let window = AwakeWindow(start: midnight.addingTimeInterval(6 * 3600), end: midnight.addingTimeInterval(23 * 3600),
                                     windDown: midnight.addingTimeInterval(22.25 * 3600))
            let plan = FocusPlan(
                presetID: UUID(), presetName: "Study", verb: .study, plannedSeconds: 50 * 60, breakSeconds: 0, strictness: .steady,
                kind: .blocking, appSetID: nil, selection: SelectionSummary(mode: .blockThese, apps: 6, sites: 0, categories: 0),
                startedFrom: .focusTab, mapleDay: day.description, window: window, zone: "UTC", appBuild: "test",
                rulesVersion: FocusRules.version
            )
            for hour in [9.0, 11.0, 14.0, 16.0] {
                time.advance(midnight.addingTimeInterval(hour * 3600).timeIntervalSince(time.now))
                let session = UUID()
                try writer.write(.sessionStarted(plan), session: session)
                time.advance(5)
                try writer.write(.shieldApplied, session: session)
                for _ in 1...50 {
                    time.advance(60)
                    try writer.write(.shieldVerified, session: session)
                }
                try writer.write(.sessionEnded(.completed, verified: true), session: session)
                try writer.write(.shieldCleared(.sessionEnded), session: session)
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var files: [String: (data: Data, last: Date)] = [:]
        for event in memory.events {
            let name = FileLedgerStore.fileName(writer: .app, wall: event.stamp.wall)
            var file = files[name] ?? (Data(), event.stamp.wall)
            file.data.append(try encoder.encode(event))
            file.data.append(0x0A)
            file.last = event.stamp.wall
            files[name] = file
        }
        for (name, file) in files {
            let url = folder.appending(path: name)
            try file.data.write(to: url)
            try FileManager.default.setAttributes([.modificationDate: file.last], ofItemAtPath: url.path)
        }
        return memory.events.count
    }

    @Test("Over two months of real use, a launch's first replay takes under 500 ms and a refresh with nothing new under 50 ms")
    func twoMonths() async throws {
        let folder = try temporaryDirectory()
        let written = try writeTwoMonths(to: folder)
        #expect(written == 62 * 4 * 54)
        let collection = CollectionStore(storage: JSONStorage(.memory), context: testContext, now: at(2026, 8, 31, 9))
        collection.raise(.firstLeaf, to: 1, at: at(2026, 8, 31, 9))
        collection.openReveals(at: at(2026, 8, 31, 9, 5))
        // The morning after the last session, in a later boot: the open read takes every month file.
        let time = ManualFocusTime(wall: at(2026, 11, 2, 8), boot: "b2")

        /// What a launch builds: a new ledger store (nothing cached), the writer, which reads its last sequence number,
        /// and the session store.
        func launch() -> FocusSessionStore {
            let ledger = FileLedgerStore(directory: folder)
            let writer = LedgerWriter(store: ledger, time: time, deviceID: device, writer: .app, source: .live)
            return FocusSessionStore(ledger: ledger, writer: writer, blocking: PreviewBlockingService(), collection: collection,
                                     credited: [.live], liveActivity: NoLiveActivityController(), appBuild: "test")
        }

        // Warm-up: the first launch also brings the collection up to date, as the launches before it would have.
        var store = launch()
        await store.refresh()
        #expect(store.sessions.count == 62 * 4)
        #expect(collection.focus.totalSeconds == 62 * 4 * 3000)

        var firstReplay = Duration.seconds(3600)
        for _ in 0..<3 {
            let start = ContinuousClock.now
            store = launch()
            await store.refresh()
            firstReplay = min(firstReplay, ContinuousClock.now - start)
        }
        await store.refresh()
        var warmRefresh = Duration.seconds(3600)
        for _ in 0..<3 {
            let start = ContinuousClock.now
            await store.refresh()
            warmRefresh = min(warmRefresh, ContinuousClock.now - start)
        }
        #expect(store.sessions.count == 62 * 4)
        #expect(firstReplay < .milliseconds(500), "first replay of a launch, fastest of 3: \(firstReplay)")
        #expect(warmRefresh < .milliseconds(50), "refresh with nothing new, fastest of 3: \(warmRefresh)")
    }
}
