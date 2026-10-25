#if DEBUG
import Foundation
import MapleCore

/// DEBUG only: the values of the Focus launch arguments (F1 design §8.2, docs/debug-launch-arguments.md). Each is read
/// by `DemoLaunchOptions`, in any letter case; Task 2's scenarios turn them into seeded stores.
///
/// The enums are `nonisolated` one by one: MapleServices is main-actor by default, and `DemoLaunchOptions` is read off
/// the main actor.
nonisolated public enum FocusDemo {
    /// `-MapleDemoFocus`: where the Focus tab is.
    nonisolated public enum State: String, Sendable, CaseIterable {
        /// The start screen, ready: Study on six apps.
        case idle
        /// No app set chosen: "Choose apps to block ›".
        case noSet
        /// A selection that doesn't qualify (R3): "Allowing 24 apps · 20 or fewer count ›".
        case smallSet
        /// "Some apps need choosing again ›".
        case expired
        case running
        /// Running, with the screen dimmed after 30 seconds.
        case dimmed
        case breakTime = "break"
        /// Running, with the start screen showing "Return to session".
        case minimised
        /// A session that ended on time just now: the receipt, with its finish.
        case ended
        /// A session that ended 2 hours before launch: the receipt, shown still.
        case endedAway
        /// Running, with the End early sheet over it.
        case endEarly
        /// Running Locked, with the emergency release.
        case emergency
        /// Nothing ever focused: Quick preselected, the definition, the first-session line.
        case first
    }

    /// `-MapleDemoScreenTime`: what blocking can do.
    nonisolated public enum ScreenTime: String, Sendable, CaseIterable {
        case approved, notDetermined, declined, restricted, noPasscode
        /// A free build: this version of Maple can't lock apps.
        case unavailable
        /// Screen Time turned off for Maple mid-session.
        case revoked
        /// A plain timer running.
        case plain
        /// Every apply fails: "Couldn't lock your apps · Start as a plain timer?".
        case failStart
    }

    /// `-MapleDemoReceipt`: how the session that just ended went (§5.8's endings and variants).
    nonisolated public enum Receipt: String, Sendable, CaseIterable {
        case clean, unlocked, early, plain, revoked, bedtime, capped, leaf, leafNight, notQualifying
    }

    /// `-MapleDemoSaved`: today's earlier sessions.
    nonisolated public enum Saved: String, Sendable, CaseIterable {
        case typical, capped, empty
    }

    /// `-MapleDemoLiveActivity`.
    nonisolated public enum LiveActivity: String, Sendable, CaseIterable {
        case running
        case breakTime = "break"
        case plain, ended
    }

    /// `-MapleDemoPresent`, when it names a Focus sheet.
    nonisolated public enum Sheet: String, Sendable, CaseIterable {
        case blocking, preset, saved, streak, intention
    }
}
#endif
