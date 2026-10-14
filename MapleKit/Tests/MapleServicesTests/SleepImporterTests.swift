import Foundation
import Testing
@testable import MapleCore
@testable import MapleServices

/// Apple Health's sleep as the test says it is, remembering what was asked for.
@MainActor
final class FakeSleepReader: SleepSampleReading {
    struct Locked: Error {}

    var samples: [SleepSample] = []
    var fails = false
    private(set) var reads: [(start: Date, end: Date)] = []

    func sleepSamples(from start: Date, to end: Date) async throws -> [SleepSample] {
        reads.append((start, end))
        if fails { throw Locked() }
        return samples.filter { $0.end > start && $0.start < end }
    }
}

@Suite("Apple Health sleep import")
@MainActor
struct SleepImporterTests {
    private let morning = at(2026, 10, 2, 7, 10)
    /// Last night from an Apple Watch: asleep at 22:55, up at 7:00.
    private let lastNight = SleepSample(start: at(2026, 10, 1, 22, 55), end: at(2026, 10, 2, 7), source: .watchOrTracker)

    /// A member who planted their maple on the evening of 1 October, with Apple Health connected unless asked not to.
    private func member(connected: Bool = true, planted: Bool = true) async throws -> (MapleStores, FakeSleepReader) {
        let reader = FakeSleepReader()
        let stores = MapleStores.live(directory: try temporaryDirectory(), calendar: utc, now: at(2026, 10, 1, 20),
                                      healthAuthorizer: FakeHealthAuthorizer(), sleepReader: reader)
        if planted {
            stores.schedule.save(.standard, at: at(2026, 10, 1, 21))
            stores.collection.openReveals(at: at(2026, 10, 1, 21, 5))
        }
        if connected {
            await stores.health.requestAccess(at: at(2026, 10, 1, 21, 10))
            stores.health.apply(to: stores.collection)
        }
        return (stores, reader)
    }

    @Test("The live stores have an importer")
    func live() async throws {
        let (stores, _) = try await member()
        #expect(stores.sleep != nil)
    }

    @Test("Last night's Watch sleep is read, settled and earns its leaves")
    func importsLastNight() async throws {
        let (stores, reader) = try await member()
        reader.samples = [lastNight]
        let sleep = try #require(stores.sleep)

        let unlocked = await sleep.importRecentNights(at: morning)
        #expect(!unlocked.isEmpty)
        #expect(stores.collection.snapshot.counters[.nightsTracked] == 1)
        #expect(stores.collection.snapshot.counters[.onTimeBedtimes] == 1)
        #expect(stores.collection.currentBedtimeRun == 1)
        // A night with asleep time makes Full nights earnable.
        #expect(stores.collection.availability(of: .fullNights) == .available)
    }

    @Test("It reads every night still inside the 72-hour upgrade window, up to now")
    func window() async throws {
        let (stores, reader) = try await member()
        await stores.sleep?.importRecentNights(at: morning)
        let read = try #require(reader.reads.only)
        // Last night is 1 October; four earlier nights, plus the evening before them that is read and left out.
        #expect(read.start == at(2026, 9, 26, 18))
        #expect(read.end == morning)
    }

    @Test("Importing again changes nothing")
    func idempotent() async throws {
        let (stores, reader) = try await member()
        reader.samples = [lastNight]
        await stores.sleep?.importRecentNights(at: morning)
        let snapshot = stores.collection.snapshot
        #expect(await stores.sleep?.importRecentNights(at: at(2026, 10, 2, 9)) == [])
        #expect(stores.collection.snapshot == snapshot)
    }

    @Test("Late Watch data upgrades the night iPhone estimated")
    func lateWatchData() async throws {
        let (stores, reader) = try await member()
        reader.samples = [SleepSample(start: at(2026, 10, 1, 22, 50), end: at(2026, 10, 2, 7), source: .iPhoneInBed)]
        await stores.sleep?.importRecentNights(at: morning)
        #expect(stores.collection.availability(of: .fullNights) == .needsSleepTracker)

        reader.samples.append(lastNight)
        await stores.sleep?.importRecentNights(at: at(2026, 10, 2, 12))
        #expect(stores.collection.availability(of: .fullNights) == .available)
        #expect(stores.collection.snapshot.counters[.nightsTracked] == 1)
    }

    @Test("Without Apple Health, or before the maple is planted, Apple Health isn't read")
    func notReady() async throws {
        let (unconnected, unconnectedReader) = try await member(connected: false)
        unconnectedReader.samples = [lastNight]
        #expect(await unconnected.sleep?.importRecentNights(at: morning) == [])
        #expect(unconnectedReader.reads.isEmpty)
        #expect(unconnected.collection.snapshot.counters[.nightsTracked] == nil)

        let (unplanted, unplantedReader) = try await member(planted: false)
        #expect(await unplanted.sleep?.importRecentNights(at: morning) == [])
        #expect(unplantedReader.reads.isEmpty)
    }

    @Test("When Apple Health can't be read (a locked device), no night is settled")
    func readFails() async throws {
        let (stores, reader) = try await member()
        reader.fails = true
        let before = stores.collection.snapshot
        #expect(await stores.sleep?.importRecentNights(at: morning) == [])
        #expect(stores.collection.snapshot == before)

        // The next read that works settles the night as usual.
        reader.fails = false
        reader.samples = [lastNight]
        await stores.sleep?.importRecentNights(at: at(2026, 10, 2, 8))
        #expect(stores.collection.snapshot.counters[.nightsTracked] == 1)
    }

    @Test("A night Apple Health has nothing for settles untracked")
    func emptyNight() async throws {
        let (stores, _) = try await member()
        #expect(await stores.sleep?.importRecentNights(at: morning) == [])
        #expect(stores.collection.snapshot.counters[.nightsTracked] == nil)
        #expect(stores.collection.currentBedtimeRun == 0)
        #expect(stores.collection.snapshot.nights.settledThrough == LocalDay(year: 2026, month: 10, day: 1))
    }

    #if DEBUG
    @Test("DEBUG demo stores are never fed nights")
    func demos() throws {
        #expect(MapleStores.make(DemoLaunchOptions(), directory: try temporaryDirectory()).sleep == nil)
    }
    #endif
}

private extension Array {
    /// The one element, or nil when there are none or several.
    var only: Element? { count == 1 ? first : nil }
}
