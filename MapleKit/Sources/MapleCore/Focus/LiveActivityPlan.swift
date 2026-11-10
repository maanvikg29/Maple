import Foundation

/// What to do with the Live Activities ActivityKit lists, so that exactly the running session's one shows (F1 design
/// §5.11, upkeep). Pure, so the rules are tested here; `ActivityKitController` applies the plan.
///
/// - Nothing running: every activity still showing ends.
/// - The running session's activity is found again (after a relaunch, or a kill): it is kept, and sent the new
///   content only when that content changed. Any other activity, and any second copy of it, ends.
/// - Its activity was dismissed (by the member, or ended by the system): it isn't asked for again.
/// - None yet: it is asked for, once per launch.
public struct LiveActivityPlan: Sendable, Equatable {
    /// One activity ActivityKit lists.
    public struct Listed: Sendable, Equatable {
        public var session: UUID
        /// Not ended and not dismissed.
        public var isShown: Bool

        public init(session: UUID, isShown: Bool) {
            self.session = session
            self.isShown = isShown
        }
    }

    public enum Next: Sendable, Equatable {
        /// Nothing is wanted.
        case clear
        /// The wanted activity already shows this content.
        case unchanged
        /// Send the new content to the activity at this index.
        case update(Int)
        /// The wanted session's activity was dismissed: leave it.
        case dismissed
        /// Ask ActivityKit for the wanted session's activity.
        case request
        /// This launch already asked for it, and it isn't showing.
        case notAsked
    }

    /// Indices of the listed activities to end.
    public var end: [Int]
    public var next: Next

    public init(end: [Int], next: Next) {
        self.end = end
        self.next = next
    }

    /// - Parameters:
    ///   - activities: Every Maple activity ActivityKit lists, in its order.
    ///   - wanted: The running session, or nil when nothing runs.
    ///   - contentChanged: Whether the content to show differs from what this launch last sent (always true after a
    ///     relaunch, so a reconnected activity gets fresh content).
    ///   - mayRequest: Whether this launch may still ask for the wanted session's activity.
    public static func make(activities: [Listed], wanted: UUID?, contentChanged: Bool, mayRequest: Bool) -> LiveActivityPlan {
        var end: [Int] = []
        var kept: Int?
        var wasDismissed = false
        for (index, listed) in activities.enumerated() {
            if let wanted, listed.session == wanted {
                if !listed.isShown {
                    wasDismissed = true
                    continue
                }
                if kept == nil {
                    kept = index
                    continue
                }
            }
            if listed.isShown { end.append(index) }
        }
        guard wanted != nil else { return LiveActivityPlan(end: end, next: .clear) }
        if let kept { return LiveActivityPlan(end: end, next: contentChanged ? .update(kept) : .unchanged) }
        if wasDismissed { return LiveActivityPlan(end: end, next: .dismissed) }
        return LiveActivityPlan(end: end, next: mayRequest ? .request : .notAsked)
    }
}
