import Foundation
import MapleFocusCore

/// How often the session store refreshes while a session runs (ruling P6; the F1 design's timing rule): every 15
/// seconds, and also at the break's end and the planned end, so a lost shield is noticed within 15 seconds and the
/// session ends on time. The dial itself ticks once a second from `FocusSessionStore.now`.
public enum FocusRefresh {
    public static let interval: TimeInterval = 15

    /// The next refresh after `now`: 15 seconds on, or sooner at the running break's end or the planned end; `now`
    /// once the planned end has passed; nil when nothing runs.
    public static func next(after now: Date, running: SessionRecord?) -> Date? {
        guard let running, !running.isEnded else { return nil }
        var next = min(now.addingTimeInterval(interval), running.plannedEnd)
        if let breakEnd = running.breakEnd(at: now) { next = min(next, breakEnd) }
        return max(next, now)
    }
}
