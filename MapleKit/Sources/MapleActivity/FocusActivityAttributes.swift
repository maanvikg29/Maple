import ActivityKit
import Foundation

/// The running session's Live Activity, shared by the app and the MapleWidgets extension (F1 design §5.11, §7.7).
/// This first version only carries the times, so the target wiring can be built and checked on its own; the next
/// commits give it the lines, the leaf and the tint.
public struct FocusActivityAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public var start: Date
        public var end: Date

        public init(start: Date, end: Date) {
            self.start = start
            self.end = max(start, end)
        }
    }

    public var sessionID: UUID

    public init(sessionID: UUID) {
        self.sessionID = sessionID
    }
}
