#if DEBUG
import Foundation
import MapleFocusCore

/// DEBUG only: what Settings › Ledger inspector lists (F1 design §7.7). Every event, newest first, by its kind, its
/// session (the id's first 8 characters), its writer and sequence number, its source and its wall time. Nothing
/// else: no preset name, intention, length or reason, so the inspector shows the ledger's shape, never its content.
public enum LedgerInspection {
    public struct Row: Sendable, Hashable, Identifiable {
        /// The event's id.
        public var id: String
        /// The kind's name in the ledger file: "sessionStarted", "shieldApplied", …
        public var kind: String
        /// "session 00000000 · app #3 · live".
        public var detail: String
        /// The wall time in the calendar's time zone: "2026-10-23 14:03:05".
        public var time: String
    }

    public struct Page: Sendable, Hashable {
        /// "3 events · 1 session"; past `rowLimit`, "Showing the newest 500 of 812 events · 9 sessions".
        public var summary: String
        public var rows: [Row]
    }

    /// The most rows the inspector lists.
    public static let rowLimit = 500

    public static func page(_ events: [FocusEvent], calendar: Calendar) -> Page {
        let newestFirst = events.sorted { a, b in
            if a.stamp.wall != b.stamp.wall { return a.stamp.wall > b.stamp.wall }
            if a.seq != b.seq { return a.seq > b.seq }
            return a.id > b.id
        }
        let rows = newestFirst.prefix(rowLimit).map { event in
            Row(
                id: event.id, kind: event.kind.type,
                detail: "session \(event.sessionID.uuidString.prefix(8)) · \(event.writer.rawValue) #\(event.seq) · \(event.source.rawValue)",
                time: wallTime(event.stamp.wall, calendar: calendar)
            )
        }
        let sessions = Set(events.map(\.sessionID)).count
        let counted = "\(count(events.count, "event")) · \(count(sessions, "session"))"
        let summary = events.count > rowLimit ? "Showing the newest \(rowLimit) of \(counted)" : counted
        return Page(summary: summary, rows: Array(rows))
    }

    private static func count(_ n: Int, _ noun: String) -> String {
        n == 1 ? "1 \(noun)" : "\(n) \(noun)s"
    }

    private static func wallTime(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func two(_ value: Int?) -> String {
            let value = value ?? 0
            return value < 10 ? "0\(value)" : "\(value)"
        }
        return "\(parts.year ?? 0)-\(two(parts.month))-\(two(parts.day)) \(two(parts.hour)):\(two(parts.minute)):\(two(parts.second))"
    }
}
#endif
