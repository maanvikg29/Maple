import Foundation
import MapleCore

/// The running session's Live Activity, behind a protocol so the store never imports ActivityKit. F1b adds the
/// ActivityKit controller.
public protocol LiveActivityController: AnyObject {
    /// Shows `state`, or ends every Maple activity when it is nil, reconnecting to one already running. Called
    /// after every change; calling it again with the same state changes nothing.
    func reconcile(running state: FocusActivityState?) async
}

/// No Live Activity: tests, and builds before F1b.
public final class NoLiveActivityController: LiveActivityController {
    public init() {}
    public func reconcile(running state: FocusActivityState?) async {}
}

#if DEBUG
/// DEBUG only: remembers what it was asked to show.
public final class RecordingLiveActivityController: LiveActivityController {
    public private(set) var current: FocusActivityState?
    /// Each session it began showing, in order.
    public private(set) var shownSessions: [UUID] = []

    public init() {}

    public func reconcile(running state: FocusActivityState?) async {
        if let state, state.sessionID != current?.sessionID { shownSessions.append(state.sessionID) }
        current = state
    }
}
#endif
