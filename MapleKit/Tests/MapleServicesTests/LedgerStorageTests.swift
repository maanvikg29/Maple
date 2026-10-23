import Foundation
import Testing
@testable import MapleCore
@testable import MapleStorage

@Suite("Ledger storage")
struct LedgerStorageTests {
    private let device = UUID(uuidString: "00000000-0000-4000-8000-0000000000D1")!

    private func event(_ seq: Int, wall: Date, writer: FocusWriter = .app, kind: FocusEventKind = .shieldVerified) -> FocusEvent {
        FocusEvent(id: "e\(seq)-\(writer.rawValue)", kind: kind, sessionID: device, deviceID: device, writer: writer, seq: seq,
                   source: .live, stamp: EventStamp(wall: wall, continuous: UInt64(seq) * 1_000_000_000, boot: "b1", zone: "UTC"))
    }

    @Test("Appended lines read back in order")
    func appendRead() throws {
        let file = JSONLinesFile(url: try temporaryDirectory().appending(path: "lines.jsonl"))
        try file.append(event(1, wall: at(2026, 10, 23, 9)))
        try file.append(event(2, wall: at(2026, 10, 23, 10)))
        guard case .lines(let values, let damaged) = file.read(FocusEvent.self) else { Issue.record("unreadable"); return }
        #expect(values.map(\.seq) == [1, 2])
        #expect(damaged == 0)
        #expect(file.last(FocusEvent.self)?.seq == 2)
    }

    @Test("A torn tail is skipped, and the next append still decodes")
    func tornTail() throws {
        let url = try temporaryDirectory().appending(path: "lines.jsonl")
        let file = JSONLinesFile(url: url)
        try file.append(event(1, wall: at(2026, 10, 23, 9)))
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"id\":\"half".utf8))
        try handle.close()
        try file.append(event(2, wall: at(2026, 10, 23, 10)))
        guard case .lines(let values, let damaged) = file.read(FocusEvent.self) else { Issue.record("unreadable"); return }
        #expect(values.map(\.seq) == [1, 2])
        #expect(damaged == 1)
    }

    @Test("A missing file reads as empty")
    func missing() throws {
        let file = JSONLinesFile(url: try temporaryDirectory().appending(path: "none.jsonl"))
        guard case .lines(let values, _) = file.read(FocusEvent.self) else { Issue.record("unreadable"); return }
        #expect(values.isEmpty)
    }

    @Test("One file per writer per month, by the event's wall time in UTC")
    func fileNames() throws {
        #expect(FileLedgerStore.fileName(writer: .app, wall: at(2026, 10, 23, 9)) == "ledger-app-2026-10.jsonl")
        #expect(FileLedgerStore.fileName(writer: .shieldAction, wall: at(2026, 2, 1)) == "ledger-shieldAction-2026-02.jsonl")
        let folder = try temporaryDirectory()
        let store = FileLedgerStore(directory: folder)
        try store.append(event(1, wall: at(2026, 9, 30, 23)))
        try store.append(event(2, wall: at(2026, 10, 1, 1)))
        try store.append(event(1, wall: at(2026, 10, 1, 2), writer: .monitor))
        #expect(Set(files(in: folder)) == ["ledger-app-2026-09.jsonl", "ledger-app-2026-10.jsonl", "ledger-monitor-2026-10.jsonl"])
        #expect(store.readAll()?.count == 3)
    }

    @Test("Reading the open ledger takes this month and last, skips old files, and finds a recent file under an old name")
    func openFiles() throws {
        let folder = try temporaryDirectory()
        let store = FileLedgerStore(directory: folder)
        try store.append(event(1, wall: at(2026, 6, 10)))       // an old month, written long ago
        try store.append(event(2, wall: at(2026, 9, 20)))       // last month
        try store.append(event(3, wall: at(2026, 10, 22)))      // this month
        // 100 days before the `now` read below (not before the real now, so the test doesn't change with the date it runs).
        try FileManager.default.setAttributes([.modificationDate: at(2026, 10, 23).addingTimeInterval(-100 * 86400)],
                                              ofItemAtPath: folder.appending(path: "ledger-app-2026-06.jsonl").path)
        // The clock was set back to August before this append: it lands in August's file.
        try store.append(event(4, wall: at(2026, 8, 3)))
        let open = try #require(store.readOpen(now: at(2026, 10, 23)))
        #expect(Set(open.map(\.seq)) == [2, 3, 4])
    }

    @Test("The next sequence number carries on after the highest across every month")
    func lastSeq() throws {
        let store = FileLedgerStore(directory: try temporaryDirectory())
        try store.append(event(41, wall: at(2026, 10, 2)))
        try store.append(event(42, wall: at(2026, 8, 2)))        // a clock set back
        try store.append(event(7, wall: at(2026, 10, 2), writer: .monitor))
        #expect(store.lastSeq(of: .app) == 42)
        #expect(store.lastSeq(of: .monitor) == 7)
        #expect(store.lastSeq(of: .shieldAction) == 0)
    }

    @Test("The writer stamps and numbers events, and records nothing when a write fails")
    func writer() throws {
        let store = MemoryLedgerStore([event(9, wall: at(2026, 10, 23, 9))])
        let time = ManualFocusTime(wall: at(2026, 10, 23, 14))
        let writer = LedgerWriter(store: store, time: time, deviceID: device, writer: .app, source: .preview)
        let first = try writer.write(.shieldVerified, session: device)
        #expect(first.seq == 10)
        #expect(first.source == .preview)
        #expect(first.stamp.wall == at(2026, 10, 23, 14))
        store.failsWrites = true
        #expect(throws: MemoryLedgerStore.WriteFailed.self) { try writer.write(.shieldVerified, session: device) }
        store.failsWrites = false
        #expect(try writer.write(.shieldVerified, session: device).seq == 11)
        #expect(store.events.map(\.seq) == [9, 10, 11])
    }

    @Test("An unreadable memory store reads as nil")
    func unreadable() {
        let store = MemoryLedgerStore()
        store.unreadable = true
        #expect(store.readOpen(now: .now) == nil)
        #expect(store.readAll() == nil)
    }

    @Test("The device id is made once and kept")
    func deviceIdentity() throws {
        let folder = try temporaryDirectory()
        let first = try #require(DeviceIdentity.load(in: folder))
        #expect(DeviceIdentity.load(in: folder) == first)
        #expect(files(in: folder).contains(DeviceIdentity.file))
    }
}
