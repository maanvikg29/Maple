import Foundation
import MapleFocusCore

extension CollectionSnapshot {
    /// The Maple day and frozen awake window for a session starting at `start` (F1 design §3.3 step 6). Each night is
    /// judged by the schedule in force at 18:00 that evening, so a bedtime edit after 18:00 applies from the next night.
    public func focusWindow(at start: Date, context: CollectionContext) -> (day: LocalDay, window: AwakeWindow) {
        AwakeWindow.frozen(at: start, schedule: { nights.schedule(for: $0, current: context.schedule) }, calendar: context.calendar)
    }
}
