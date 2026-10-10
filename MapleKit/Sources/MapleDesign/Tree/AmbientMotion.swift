import Combine
import MapleCore
import SwiftUI

/// When the ambient scenes (the maple and Home's sky) hold still (spec §4.9): they pause off screen, while the app is
/// inactive, in Low Power Mode, under a full-screen cover (`\.treeScenesPaused`) and after a minute at Night without
/// interaction. A paused scene keeps its last frame (a paused `TimelineView`), so pausing never repaints or snaps.

extension EnvironmentValues {
    /// Set by `nightIdleFreeze(phase:)`: whether the night's idle minute has run out for everything under it, so Home's
    /// sky and tree stop and wake together. Nil without that modifier: a `MapleTreeScene` then keeps its own countdown.
    @Entry public var nightIdleFrozen: Bool? = nil
}

extension View {
    /// Shares one night-idle freeze between everything under this view: at Night, after 60 seconds without a tap, the
    /// maple and the sky hold their frame; any tap wakes them and starts the minute again (spec §4.9).
    ///
    /// ```swift
    /// ScrollView { … }                      // Home: the stage and its SkyBackdrop
    ///     .nightIdleFreeze(phase: state.phase)
    /// ```
    public func nightIdleFreeze(phase: NowPhase) -> some View {
        modifier(NightIdleFreeze(phase: phase))
    }

    /// Calls `action` on the main actor with the new state whenever Low Power Mode turns on or off. The system posts
    /// the change on a background queue, so it is moved to the main queue first.
    func onLowPowerModeChange(_ action: @escaping (Bool) -> Void) -> some View {
        onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange).receive(on: DispatchQueue.main)) { _ in
            action(ProcessInfo.processInfo.isLowPowerModeEnabled)
        }
    }
}

/// The shared night-idle countdown behind `nightIdleFreeze(phase:)`.
struct NightIdleFreeze: ViewModifier {
    /// How long the scene keeps moving at Night without interaction.
    static let delay: Duration = .seconds(60)

    let phase: NowPhase

    @Environment(\.scenePhase) private var scenePhase
    @State private var frozen = false
    /// Bumped by every tap, so each interaction restarts the countdown.
    @State private var wakes = 0

    func body(content: Content) -> some View {
        content
            .environment(\.nightIdleFrozen, frozen)
            .task(id: Key(phase: phase, active: scenePhase == .active, wakes: wakes)) {
                frozen = false
                guard phase == .night else { return }
                try? await Task.sleep(for: Self.delay)
                if !Task.isCancelled { frozen = true }
            }
            .simultaneousGesture(TapGesture().onEnded {
                frozen = false
                wakes += 1
            })
    }

    private struct Key: Hashable {
        var phase: NowPhase
        var active: Bool
        var wakes: Int
    }
}
