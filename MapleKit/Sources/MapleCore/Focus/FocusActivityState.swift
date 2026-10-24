import Foundation
import MapleFocusCore

/// What the Live Activity shows for a running session (F1 design §5.11): display only, no buttons. The preset name,
/// never the intention, appears on the Lock Screen.
public struct FocusActivityState: Sendable, Hashable {
    public var sessionID: UUID
    public var presetName: String
    public var start: Date
    public var plannedEnd: Date
    public var isPlainTimer: Bool
    /// When a running break ends ("Break · back at 14:28"); nil outside a break.
    public var breakEnd: Date?

    public init(session: SessionRecord, now: Date) {
        sessionID = session.id
        presetName = session.plan.presetName
        start = session.countdownStart
        plannedEnd = session.plannedEnd
        isPlainTimer = session.plan.kind == .plainTimer
        breakEnd = session.breakEnd(at: now)
    }
}
