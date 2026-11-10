import Foundation

/// Which sessions this launch may still ask ActivityKit for, so the refresh every 15 seconds never asks again for an
/// activity the member dismissed (F1 design §5.11, upkeep). Pure, so the rules are tested here; `ActivityKitController`
/// keeps one for the launch.
///
/// - A session whose activity showed (requested, or found again and kept) or was dismissed isn't asked for again in
///   this launch.
/// - One ActivityKit refused (for one, because Maple wasn't in front) is asked for once more after Maple next becomes
///   active.
/// - Live Activities turned off for Maple never stop a later ask, and are reported once per launch.
public struct LiveActivityAsks: Sendable, Equatable {
    /// What happened to a session's activity.
    public enum Outcome: Sendable, Equatable {
        /// Requested now, or found showing and kept (sent new content, or already showing it).
        case shown
        /// Dismissed by the member, or ended by the system.
        case dismissed
        /// ActivityKit refused the request.
        case refused
        /// Live Activities are off for Maple.
        case disabled
    }

    /// Shown or dismissed: not asked for again in this launch.
    private var settled: Set<UUID> = []
    /// Refused: asked for once more after Maple next becomes active.
    private var refused: Set<UUID> = []
    private var reportedDisabled = false

    public init() {}

    /// Whether this launch may ask ActivityKit for `session`'s activity.
    public func mayRequest(_ session: UUID) -> Bool {
        !settled.contains(session) && !refused.contains(session)
    }

    /// Notes what happened to `session`'s activity.
    /// - Returns: Whether to log it: always, except `.disabled` after its first time in this launch.
    @discardableResult
    public mutating func record(_ outcome: Outcome, for session: UUID) -> Bool {
        switch outcome {
        case .shown, .dismissed:
            refused.remove(session)
            settled.insert(session)
            return true
        case .refused:
            refused.insert(session)
            return true
        case .disabled:
            defer { reportedDisabled = true }
            return !reportedDisabled
        }
    }

    /// Maple is in front again: each refused session may be asked for once more.
    public mutating func mapleBecameActive() {
        refused.removeAll()
    }
}
