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

    @Test("Reading the open ledger takes this month and last, any file changed lately, and each writer's newest file")
    func openFiles() throws {
        let folder = try temporaryDirectory()
        let store = FileLedgerStore(directory: folder)
        let now = at(2026, 10, 23)
        func setModified(_ name: String, to date: Date) throws {
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: folder.appending(path: name).path)
        }
        try store.append(event(1, wall: at(2026, 6, 10)))                    // an old month, written long ago
        try store.append(event(2, wall: at(2026, 7, 14)))                    // an old month, but the file was changed lately
        try store.append(event(3, wall: at(2026, 9, 20)))                    // last month
        try store.append(event(4, wall: at(2026, 10, 22)))                   // this month
        // The clock was set back to August while only the monitor ran, so its newest file is old-named, and the same
        // set-back clock stamped the file's modification date. Restoring the clock must not hide it.
        try store.append(event(5, wall: at(2026, 8, 3), writer: .monitor))
        try setModified("ledger-app-2026-06.jsonl", to: now.addingTimeInterval(-100 * 86400))
        try setModified("ledger-app-2026-07.jsonl", to: now.addingTimeInterval(-3 * 86400))
        try setModified("ledger-monitor-2026-08.jsonl", to: at(2026, 8, 3))
        let open = try #require(store.readOpen(now: now))
        #expect(Set(open.map(\.seq)) == [2, 3, 4, 5])
    }

    @Test("A clock set back appends to the writer's newest file, so the open read still finds the event")
    func clockSetBack() throws {
        let folder = try temporaryDirectory()
        let store = FileLedgerStore(directory: folder)
        try store.append(event(1, wall: at(2026, 10, 20)))
        try store.append(event(2, wall: at(2026, 8, 3)))                     // the clock was set back to August
        #expect(files(in: folder) == ["ledger-app-2026-10.jsonl"])
        try store.append(event(3, wall: at(2026, 8, 3), writer: .monitor))   // another writer's own files are its own
        #expect(Set(files(in: folder)) == ["ledger-app-2026-10.jsonl", "ledger-monitor-2026-08.jsonl"])
        let open = try #require(store.readOpen(now: at(2026, 10, 23)))
        #expect(Set(open.map(\.seq)) == [1, 2, 3])
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

    @Test("A writer made while the ledger is unreadable records nothing, then carries on after the highest seq once it can read")
    func writerOverUnreadableStore() throws {
        let store = MemoryLedgerStore([event(9, wall: at(2026, 10, 23, 9))])
        store.unreadable = true
        let time = ManualFocusTime(wall: at(2026, 10, 23, 14))
        let writer = LedgerWriter(store: store, time: time, deviceID: device, writer: .app, source: .live)
        #expect(throws: LedgerWriter.SequenceUnknown.self) { try writer.write(.shieldVerified, session: device) }
        #expect(throws: LedgerWriter.SequenceUnknown.self) { try writer.write(.shieldVerified, session: device) }
        #expect(store.events.map(\.seq) == [9])
        store.unreadable = false
        #expect(try writer.write(.shieldVerified, session: device).seq == 10)
        #expect(try writer.write(.shieldVerified, session: device).seq == 11)
        #expect(store.events.map(\.seq) == [9, 10, 11])
    }

    @Test("The last sequence number is unknown, not zero, while the writer's newest file can't be read")
    func lastSeqUnreadable() throws {
        let folder = try temporaryDirectory()
        let store = FileLedgerStore(directory: folder)
        try store.append(event(41, wall: at(2026, 9, 2)))
        try store.append(event(42, wall: at(2026, 10, 2)))
        let locked = folder.appending(path: "ledger-app-2026-10.jsonl").path
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked) }
        #expect(store.lastSeq(of: .app) == nil)
        #expect(store.readAll() == nil)
        #expect(store.lastSeq(of: .monitor) == 0)
    }

    @Test("The last sequence number reads only the writer's newest file, or the one before when it has no readable line")
    func lastSeqNewestFile() throws {
        let folder = try temporaryDirectory()
        let store = FileLedgerStore(directory: folder)
        try store.append(event(41, wall: at(2026, 9, 2)))
        try store.append(event(42, wall: at(2026, 10, 2)))
        try store.append(event(7, wall: at(2026, 10, 2), writer: .monitor))
        // Appends never go to a file named before the writer's newest, so an older file can't hold a higher number and is
        // never opened.
        let september = folder.appending(path: "ledger-app-2026-09.jsonl").path
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: september)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: september) }
        #expect(store.lastSeq(of: .app) == 42)
        try Data("{\"id\":\"half\n".utf8).write(to: folder.appending(path: "ledger-monitor-2026-11.jsonl"))
        #expect(store.lastSeq(of: .monitor) == 7)
    }

    @Test("A store reads what was appended since its last read, a torn tail only once it is whole, and a changed file in full")
    func incrementalRead() throws {
        let folder = try temporaryDirectory()
        let store = FileLedgerStore(directory: folder)
        let url = folder.appending(path: "ledger-app-2026-10.jsonl")
        try store.append(event(1, wall: at(2026, 10, 20)))
        try store.append(event(2, wall: at(2026, 10, 21)))
        #expect(store.readAll()?.map(\.seq) == [1, 2])
        #expect(store.readOpen(now: at(2026, 10, 23))?.map(\.seq) == [1, 2])

        // Another process appends a line, then is killed halfway through the next.
        try FileLedgerStore(directory: folder).append(event(3, wall: at(2026, 10, 22)))
        let fourth = try line(event(4, wall: at(2026, 10, 22)))
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: fourth.prefix(30))
        #expect(store.readAll()?.map(\.seq) == [1, 2, 3])
        try handle.write(contentsOf: fourth.dropFirst(30))
        try handle.close()
        #expect(store.readAll()?.map(\.seq) == [1, 2, 3, 4])
        #expect(store.readOpen(now: at(2026, 10, 23))?.map(\.seq) == [1, 2, 3, 4])
        #expect(store.lastSeq(of: .app) == 4)

        // The file is cut short in place, then replaced by another (a restore): each is read again in full.
        let cut = try FileHandle(forWritingTo: url)
        try cut.truncate(atOffset: UInt64(try line(event(1, wall: at(2026, 10, 20))).count))
        try cut.close()
        #expect(store.readAll()?.map(\.seq) == [1])
        try (line(event(9, wall: at(2026, 10, 20))) + line(event(10, wall: at(2026, 10, 20))) + line(event(11, wall: at(2026, 10, 20))))
            .write(to: url, options: .atomic)
        #expect(store.readAll()?.map(\.seq) == [9, 10, 11])
        #expect(store.lastSeq(of: .app) == 11)
        try FileManager.default.removeItem(at: url)
        #expect(store.readAll()?.isEmpty == true)
    }

    /// One encoded ledger line, as `JSONLinesFile` writes it.
    private func line(_ event: FocusEvent) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(event) + Data([0x0A])
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
