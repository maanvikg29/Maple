#if DEBUG
import Foundation
import MapleCore

extension FocusDemo.LiveActivity {
    /// The session a `-MapleDemoLiveActivity` launch shows, on real dates (F1 design §5.11: "Demo Live Activities use
    /// real dates"), so the system's timer text and the Lock Screen clock agree whatever `-MapleDemoPhase` says. It
    /// never touches the demo store.
    ///
    /// - `running`, `break` and `plain` are `-MapleDemoFocusAt` minutes in (18 by default; 31 for `break`, as the Focus
    ///   tab's break demo) of `-MapleDemoPreset`
    ///   (Study by default). A break started a minute ago, so it ends in 4 minutes.
    /// - `ended` reaches its planned end `endsAfter` seconds after launch, so a later screenshot reads
    ///   "Session complete".
    /// - The intention is `-MapleDemoIntention` ("" for none), or "Chemistry ch. 4".
    /// - Each launch is a new session (`session`), so an activity an earlier launch left is ended, never reused with
    ///   its old leaf and tint.
    public func state(options: DemoLaunchOptions, now: Date, session: UUID = UUID()) -> FocusActivityState {
        let presets = FocusPreset.defaults(appSetID: nil)
        let preset = presets.first { $0.verb == (options.preset ?? .study) } ?? presets[0]
        let length = TimeInterval(preset.minutes * 60)
        let intention = options.intention ?? Self.intention
        switch self {
        case .running, .breakTime, .plain:
            let minutesIn = min(max(options.focusAt ?? (self == .breakTime ? 31 : 18), 0), preset.minutes - 1)
            let start = now.addingTimeInterval(-TimeInterval(minutesIn * 60))
            return FocusActivityState(
                sessionID: session, presetName: preset.name, start: start, plannedEnd: start.addingTimeInterval(length),
                isPlainTimer: self == .plain, breakEnd: self == .breakTime ? now.addingTimeInterval(4 * 60) : nil,
                intention: intention
            )
        case .ended:
            let end = now.addingTimeInterval(Self.endsAfter)
            return FocusActivityState(
                sessionID: session, presetName: preset.name, start: end.addingTimeInterval(-length), plannedEnd: end,
                isPlainTimer: false, intention: intention
            )
        }
    }

    /// How long after launch `ended`'s activity goes stale.
    public static let endsAfter: TimeInterval = 8
    static let intention = "Chemistry ch. 4"
}
#endif
