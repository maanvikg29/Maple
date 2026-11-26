import Foundation
import Testing
@testable import MapleCore
@testable import MapleServices

/// Evaporator: level 1 for 5 leaves (+0.2 bottles a leaf). Filter press: level 1 for 3 (+0.1).
private let small = WorkshopTuning(
    secondsPerLeaf: 300, baseTenthsPerLeaf: 10,
    ladders: [
        .evaporator: WorkshopTuning.Ladder(prices: [5], bonusTenths: [2]),
        .filterPress: WorkshopTuning.Ladder(prices: [3], bonusTenths: [1]),
    ]
)

/// A demo launch with seventeen days of sessions (`-MapleDemoHistory`) on Friday 23 October 2026, refreshed once as the
/// app does at launch.
@MainActor
private func launchWithHistory(_ arguments: [String] = []) async throws -> MapleStores {
    let all = ["-MapleDemoShip", "f1", "-MapleDemoFocus", "idle", "-MapleDemoHistory", "YES"] + arguments
    let stores = MapleStores.make(DemoLaunchOptions(arguments: all), directory: try temporaryDirectory(), calendar: utc,
                                  now: at(2026, 10, 23, 9))
    await stores.focus.sessions.refresh()
    return stores
}

@Suite("The syrup van's store")
@MainActor
struct WorkshopStoreTests {
    private func url() throws -> URL {
        try temporaryDirectory().appendingPathComponent(WorkshopStore.file)
    }

    private func open(_ file: URL) -> WorkshopStore {
        WorkshopStore(storage: JSONStorage(.file(file)), tuning: small)
    }

    private func lock(_ file: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
    }

    private func unlock(_ file: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
    }

    @Test("A first launch has an empty van and writes nothing until something changes")
    func firstLaunch() throws {
        let file = try url()
        let store = open(file)
        #expect(store.isAvailable)
        #expect(store.leaves == 0 && store.syrupTenths == 0 && store.tenthsPerLeaf == 10)
        #expect(store.noteEarned(0) == 0)
        #expect(store.cook() == 0)
        #expect(files(in: file.deletingLastPathComponent()).isEmpty)
    }

    @Test("Leaves, syrup and upgrades are saved as they change")
    func saved() throws {
        let file = try url()
        let store = open(file)
        #expect(store.noteEarned(20) == 20)
        #expect(store.cook(3) == 3)
        #expect(store.upgrade(.evaporator) == .upgraded(level: 1))
        #expect(store.cook() == 1)

        let reopened = open(file)
        #expect(reopened.bank == store.bank)
        #expect(reopened.leaves == 11)
        #expect(reopened.syrupTenths == 42)
        #expect(reopened.level(of: .evaporator) == 1)
        #expect(reopened.price(of: .evaporator) == nil)
        #expect(reopened.price(of: .filterPress) == 3)
        #expect(reopened.tenthsPerLeaf == 12)
    }

    @Test("An upgrade the van can't afford is reported and nothing is saved")
    func cannotAfford() throws {
        let file = try url()
        let store = open(file)
        store.noteEarned(2)
        let before = try Data(contentsOf: file)
        #expect(store.upgrade(.evaporator) == .short(by: 3))
        #expect(try Data(contentsOf: file) == before)
    }

    @Test("A van that can't be read yet is never overwritten: nothing changes until it can")
    func unavailable() throws {
        let file = try url()
        let saved = open(file)
        saved.noteEarned(20)
        saved.cook(4)
        let before = try Data(contentsOf: file)

        try lock(file)
        defer { try? unlock(file) }
        let store = open(file)
        #expect(!store.isAvailable)
        #expect(store.leaves == 0)
        #expect(store.noteEarned(30) == 0)
        #expect(store.cook() == 0)
        #expect(store.upgrade(.evaporator) == nil)

        try unlock(file)
        #expect(try Data(contentsOf: file) == before)
        #expect(store.noteEarned(30) == 10)
        #expect(store.isAvailable)
        #expect(store.leaves == 26)
        #expect(open(file).leaves == 26)
    }

    @Test("The van counts the ledger at its own pace: after a retune, earned leaves stay and the next session still earns")
    func retunedPace() throws {
        let file = try url()
        open(file).noteEarned(600)
        var slower = small
        slower.secondsPerLeaf = 360
        let store = WorkshopStore(storage: JSONStorage(.file(file)), tuning: slower)
        #expect(store.noteEarned(500) == 0)
        #expect(store.leaves == 600)
        #expect(store.noteEarned(510) == 10)
        #expect(WorkshopStore(storage: JSONStorage(.file(file)), tuning: slower).leaves == 610)
    }

    @Test("A file read with losses is copied aside before the van saves over it")
    func copiedAside() throws {
        let file = try url()
        try Data(#"{"earned":12,"cooked":-5,"levels":{"evaporator":1}}"#.utf8).write(to: file)
        let store = open(file)
        #expect(store.isAvailable)
        #expect(store.leaves == 12)
        #expect(store.level(of: .evaporator) == 1)
        let folder = files(in: file.deletingLastPathComponent())
        #expect(folder.contains { $0.hasPrefix("workshop.damaged-") })
        store.cook(2)
        #expect(open(file).leaves == 10)
    }

    @Test("History fills the van once: a second read of the same ledger brings nothing new")
    func collects() async throws {
        let stores = try await launchWithHistory()
        let workshop = stores.focus.workshop
        #expect(workshop.leaves == 0)
        await stores.focus.sessions.loadHistory()
        let history = try #require(stores.focus.sessions.history)
        let running = stores.focus.sessions.running?.id

        let gained = workshop.collect(from: history, running: running)
        #expect(gained > 0)
        #expect(gained == LeafEarnings.total(history.records, running: running))
        let pace = workshop.tuning.secondsPerLeaf
        #expect(gained == history.sessions.reduce(0) { $0 + ($1.focusedSeconds + pace - 1) / pace },
                "every listed session earns for its time focused, rounded up, whether or not it blocked apps")
        #expect(workshop.leaves == gained)
        #expect(workshop.collect(from: history, running: running) == 0)
        #expect(workshop.leaves == gained)
    }

    @Test("In a free-tier build every session is a plain timer, and each earns for its time focused, rounded up")
    func freeTier() async throws {
        let stores = try await launchWithHistory(["-MapleDemoScreenTime", "unavailable"])
        await stores.focus.sessions.loadHistory()
        let history = try #require(stores.focus.sessions.history)
        #expect(history.sessions.allSatisfy { $0.savedSeconds == 0 })
        let pace = stores.focus.workshop.tuning.secondsPerLeaf
        let expected = history.sessions.reduce(0) { $0 + ($1.focusedSeconds + pace - 1) / pace }
        #expect(expected > 0)
        #expect(stores.focus.workshop.collect(from: history, running: nil) == expected)
    }

    @Test("Before History has been read, the van is left as it is")
    func notLoaded() throws {
        let store = open(try url())
        store.noteEarned(12)
        #expect(store.collect(from: nil, running: nil) == 0)
        #expect(store.collect(from: FocusSessionStore.History(records: [], credits: [], sessions: []), running: nil) == 0)
        #expect(store.leaves == 12)
    }
}
