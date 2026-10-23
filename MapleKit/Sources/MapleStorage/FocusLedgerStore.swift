import Foundation
import MapleFocusCore
import Synchronization

/// Where focus events live (F1 design §7.3).
public protocol FocusLedgerStore: Sendable {
    /// Appends one event to its writer's file. Throws when it can't be written; the caller then acts on nothing.
    func append(_ event: FocusEvent) throws
    /// The events that can still change an open day: this month's and last month's files, each writer's newest
    /// file whatever its name (a clock set back can leave a writer's newest file under an older month's name, and
    /// the file's modification date comes from that same clock), plus any file changed in the last 40 days.
    /// Nil when a file can't be read now.
    func readOpen(now: Date) -> [FocusEvent]?
    /// Every event, for a full rebuild. Nil when a file can't be read now.
    func readAll() -> [FocusEvent]?
    /// The highest sequence number `writer` has written (0 when it has written nothing), so a new writer carries on
    /// after it. Nil when one of its files can't be read now: the number is unknown, and a caller must not guess.
    func lastSeq(of writer: FocusWriter) -> Int?
}

/// The ledger as files in the container: one per writer per month ("ledger-app-2026-10.jsonl"), so each process
/// appends only to its own files and a replay of the open days reads only the last two months.
public struct FileLedgerStore: FocusLedgerStore {
    public let directory: URL

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
        return read(open)
    }

    public func readAll() -> [FocusEvent]? {
        read(files())
    }

    public func lastSeq(of writer: FocusWriter) -> Int? {
        var highest = 0
        for url in files() where url.lastPathComponent.hasPrefix(Self.prefix(of: writer)) {
            switch JSONLinesFile(url: url).read(FocusEvent.self) {
            case .lines(let values, _): highest = max(highest, values.map(\.seq).max() ?? 0)
            case .unavailable: return nil
            }
        }
        return highest
    }

    // MARK: Private

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

    private func read(_ urls: [URL]) -> [FocusEvent]? {
        var events: [FocusEvent] = []
        for url in urls {
            switch JSONLinesFile(url: url).read(FocusEvent.self) {
            case .lines(let values, _): events += values
            case .unavailable: return nil
            }
        }
        return events
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
