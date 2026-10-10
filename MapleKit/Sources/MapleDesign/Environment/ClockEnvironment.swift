import MapleCore
import SwiftUI

extension EnvironmentValues {
    /// Where "now" comes from. Screens use it instead of `Date()`, so DEBUG `-MapleDemoPhase` launches and previews
    /// can freeze time inside a phase:
    ///
    /// ```swift
    /// @Environment(\.mapleClock) private var clock
    ///
    /// TimelineView(.everyMinute) { context in
    ///     let now = clock.date(forTimeline: context.date)
    ///     NowBlock(state: collection.nowState(at: now))
    /// }
    /// ```
    ///
    /// For a one-off action, use `clock.now()`: `collection.openReveals(at: clock.now())`.
    @Entry public var mapleClock: MapleClock = .live
}
