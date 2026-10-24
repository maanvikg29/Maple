import Foundation
import MapleFocusCore
import Synchronization

/// Where focus events live (F1 design §7.3).
public protocol FocusLedgerStore: Sendable {
    /// Appends one event to its writer's file. Throws when it can't be written; the caller then acts on nothing.
    func append(_ event: FocusEvent) throws
    /// The events that can still change an open day: this month's and last month's files, each writer's newest
    /// file whatever its name (a clock set back can leave a writer's newest file under an older month's name, and
    /// the file's modification date comes from that same clock), plus any file changed in the last 40 days. A clock
    /// set far forward can still leave a running session's start outside it; `FocusSessionStore` reads everything
    /// then. Nil when a file can't be read now.
    func readOpen(now: Date) -> [FocusEvent]?
    /// Every event, for a full rebuild. Nil when a file can't be read now.
    func readAll() -> [FocusEvent]?
    /// The highest sequence number `writer` has written (0 when it has written nothing), so a new writer carries on
    /// after it. Nil when it can't be read now: the number is unknown, and a caller must not guess.
    func lastSeq(of writer: FocusWriter) -> Int?
}

/// The ledger as files in the container: one per writer per month ("ledger-app-2026-10.jsonl"), so each process
/// appends only to its own files and files stay small.
///
/// Reads are incremental: for each file the open read takes, the store keeps the events it decoded and how many bytes
/// that took, and the next read decodes only what was appended since. A torn tail (no final newline yet) is left until
/// it is whole. A file that shrank or was replaced (another inode or creation date) is read again in full. An open read
/// that finds nothing changed hands back the very same array, so a caller can tell cheaply. A full read (rare) decodes
/// the older files without keeping them.
public final class FileLedgerStore: FocusLedgerStore {
    public let directory: URL
    private let cache = Mutex(Cache())

    public init(directory: URL) {
        self.directory = directory
    }

    /// The file that holds `writer`'s events for the month `wall` falls in.
    public static func fileName(writer: FocusWriter, wall: Date) -> String {
        fileName(writer: writer, month: month(of: wall))
    }

    /// Appends to the month of the event's wall time, but never to a file named for an older month than the
    /// writer's newest: a clock set back would otherwise scatter new events into old files, which an open replay
    /// could miss. Such an event keeps its own stamp and goes into the newest file.
    public func append(_ event: FocusEvent) throws {
        let month = max(Self.month(of: event.stamp.wall), newestMonth(of: event.writer) ?? "")
        try JSONLinesFile(url: directory.appending(path: Self.fileName(writer: event.writer, month: month))).append(event)
    }

    public func readOpen(now: Date) -> [FocusEvent]? {
        let previous = Self.utc.date(byAdding: .month, value: -1, to: now) ?? now
        let months = [Self.month(of: now), Self.month(of: previous)]
        let recent = now.addingTimeInterval(-40 * 86400)
        let all = files()
        let newest = Set(FocusWriter.allCases.compactMap { newestFile(of: $0, in: all) })
        let open = all.filter { url in
            if newest.contains(url) { return true }
            if months.contains(where: { url.lastPathComponent.hasSuffix("-\($0).jsonl") }) { return true }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return (modified ?? .distantPast) >= recent
        }
        return read(open, as: .open)
    }

    public func readAll() -> [FocusEvent]? {
        read(files(), as: .all)
    }

    /// From the writer's newest file alone: appends never go to a file named before it, so no older file can hold a
    /// higher number. A newest file with no readable number falls back to the one before, and so on.
    public func lastSeq(of writer: FocusWriter) -> Int? {
        let urls = files().filter { $0.lastPathComponent.hasPrefix(Self.prefix(of: writer)) }
        return cache.withLock { cache in
            for url in urls.reversed() {
                guard let file = Self.read(url, cache: &cache.files) else { return nil }
                // A seq of 0 is one that didn't read; a whole last line without its newline still counts.
                if let highest = (file.events.map(\.seq) + [file.tail?.seq ?? 0]).filter({ $0 > 0 }).max() { return highest }
            }
            return 0
        }
    }

    // MARK: Private

    /// Where a file stands: which file it is, and how far it has been decoded.
    private struct FileState: Hashable {
        let device: Int64
        let inode: UInt64
        let created: Int64
        let createdNanoseconds: Int64
        /// Bytes decoded so far, always just after a newline.
        var length: UInt64
    }

    private struct CachedFile {
        var state: FileState
        var events: [FocusEvent]
    }

    private enum ReadKind {
        case open, all
    }

    private struct Cache {
        var files: [String: CachedFile] = [:]
        /// The last open read's file names.
        var open: Set<String> = []
        /// The last open read and the file states it came from, so an unchanged read is the same array.
        var lastOpen: (states: [FileState], events: [FocusEvent])?
    }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    static func month(of date: Date) -> String {
        let parts = utc.dateComponents([.year, .month], from: date)
        let month = parts.month ?? 1
        return "\(parts.year ?? 1970)-" + (month < 10 ? "0" : "") + "\(month)"
    }

    private static func fileName(writer: FocusWriter, month: String) -> String {
        prefix(of: writer) + month + suffix
    }

    private static let suffix = ".jsonl"

    private static func prefix(of writer: FocusWriter) -> String {
        "ledger-\(writer.rawValue)-"
    }

    /// `writer`'s newest file in `urls` (which `files()` sorts by name, and "yyyy-MM" sorts by date).
    private func newestFile(of writer: FocusWriter, in urls: [URL]) -> URL? {
        urls.last { $0.lastPathComponent.hasPrefix(Self.prefix(of: writer)) }
    }

    /// The month in the name of `writer`'s newest file, if it has one.
    private func newestMonth(of writer: FocusWriter) -> String? {
        newestFile(of: writer, in: files()).map { url in
            String(url.lastPathComponent.dropFirst(Self.prefix(of: writer).count).dropLast(Self.suffix.count))
        }
    }

    private func files() -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasPrefix("ledger-") && $0.hasSuffix(Self.suffix) }.sorted().map { directory.appending(path: $0) }
    }

    private func read(_ urls: [URL], as kind: ReadKind) -> [FocusEvent]? {
        cache.withLock { cache in
            if kind == .open { cache.open = Set(urls.map(\.lastPathComponent)) }
            var states: [FileState] = []
            var parts: [[FocusEvent]] = []
            for url in urls {
                // Only the open read's files are kept; a full read's older files are decoded and let go.
                var scratch: [String: CachedFile] = [:]
                let kept = cache.open.contains(url.lastPathComponent)
                guard let file = kept ? Self.read(url, cache: &cache.files) : Self.read(url, cache: &scratch) else { return nil }
                if let state = file.state {
                    states.append(state)
                    parts.append(file.events)
                }
            }
            guard kind == .open else { return Array(parts.joined()) }
            if let last = cache.lastOpen, last.states == states { return last.events }
            let events = Array(parts.joined())
            cache.lastOpen = (states, events)
            return events
        }
    }

    /// One file's whole lines, decoding only the bytes appended since it was last read, plus its unfinished last line
    /// if that decodes (never kept: it is read again until its newline arrives). A missing file is empty, with no
    /// state. Nil when the file is there but can't be read now (before the first unlock after a restart).
    private static func read(_ url: URL, cache: inout [String: CachedFile])
        -> (state: FileState?, events: [FocusEvent], tail: FocusEvent?)?
    {
        let name = url.lastPathComponent
        var info = stat()
        guard stat(url.path, &info) == 0 else {
            cache[name] = nil
            return errno == ENOENT ? (nil, [], nil) : nil
        }
        let size = UInt64(info.st_size)
        let state = FileState(device: Int64(info.st_dev), inode: UInt64(info.st_ino), created: Int64(info.st_birthtimespec.tv_sec),
                              createdNanoseconds: Int64(info.st_birthtimespec.tv_nsec), length: 0)
        var file = cache[name] ?? CachedFile(state: state, events: [])
        var known = file.state
        known.length = 0
        if known != state || size < file.state.length {
            // Another file, or this one cut short: read it again from the start.
            file = CachedFile(state: state, events: [])
        }
        var tail: FocusEvent?
        if size > file.state.length {
            let data: Data
            do {
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                try handle.seek(toOffset: file.state.length)
                data = try handle.readToEnd() ?? Data()
            } catch {
                return nil
            }
            let decoder = JSONDecoder()
            let whole = data.lastIndex(of: 0x0A).map { data.index(after: $0) } ?? data.startIndex
            for line in data[data.startIndex..<whole].split(separator: 0x0A, omittingEmptySubsequences: true) {
                if let event = try? decoder.decode(FocusEvent.self, from: Data(line)) { file.events.append(event) }
            }
            file.state.length += UInt64(whole - data.startIndex)
            if whole < data.endIndex { tail = try? decoder.decode(FocusEvent.self, from: Data(data[whole...])) }
        }
        cache[name] = file
        return (file.state, file.events, tail)
    }
}

/// The ledger in memory: demo launches and tests. Writes can be made to fail, and reads to find the ledger
/// unreadable, to test the store's unknown state.
public final class MemoryLedgerStore: FocusLedgerStore {
    public struct WriteFailed: Error {}

    private struct State {
        var events: [FocusEvent]
        var failsWrites = false
        var unreadable = false
    }

    private let state: Mutex<State>

    public init(_ events: [FocusEvent] = []) {
        state = Mutex(State(events: events))
    }

    public func append(_ event: FocusEvent) throws {
        try state.withLock { state in
            if state.failsWrites { throw WriteFailed() }
            state.events.append(event)
        }
    }

    public func readOpen(now: Date) -> [FocusEvent]? {
        state.withLock { $0.unreadable ? nil : $0.events }
    }

    public func readAll() -> [FocusEvent]? {
        state.withLock { $0.unreadable ? nil : $0.events }
    }

    public func lastSeq(of writer: FocusWriter) -> Int? {
        state.withLock { $0.unreadable ? nil : $0.events.filter { $0.writer == writer }.map(\.seq).max() ?? 0 }
    }

    public var events: [FocusEvent] {
        state.withLock { $0.events }
    }

    public var failsWrites: Bool {
        get { state.withLock { $0.failsWrites } }
        set { state.withLock { $0.failsWrites = newValue } }
    }

    public var unreadable: Bool {
        get { state.withLock { $0.unreadable } }
        set { state.withLock { $0.unreadable = newValue } }
    }
}
