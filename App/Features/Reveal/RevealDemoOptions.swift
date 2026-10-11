#if DEBUG
import SwiftUI
import MapleServices

/// DEBUG only: the launch arguments the reveal and the onboarding end read, so every moment of the ritual can be
/// screenshotted in the simulator without tapping (docs/debug-launch-arguments.md). They act only on a demo launch
/// (at least one Core argument, so every store is in memory) and release builds never read them.
enum RevealDemoOptions {
    /// `-MapleDemoRevealAt <seconds>`: taps the first bud open on launch and freezes the ritual that many seconds
    /// after the tap (`0.3`, `0.9`, `1.6`, `3`).
    static var openAt: TimeInterval? { seconds("MapleDemoRevealAt") }
    /// `-MapleDemoRevealOpenAll <seconds>`: opens the first leaf, taps "Open all" and freezes that many seconds
    /// into it (`0.5` mid-row, `4` the list).
    static var openAllAt: TimeInterval? { seconds("MapleDemoRevealOpenAll") }
    /// `-MapleDemoRevealConsent YES`: opens the first leaf and shows the rarity consent sheet over it.
    static var showsConsent: Bool { isDemoLaunch && UserDefaults.standard.bool(forKey: "MapleDemoRevealConsent") }
    /// `-MapleDemoRevealLeaf <speciesID>`: the waiting leaf `-MapleDemoPresent reveal` opens first
    /// (`RevealFlow(startingWith:)`).
    static var leaf: String? { isDemoLaunch ? UserDefaults.standard.string(forKey: "MapleDemoRevealLeaf") : nil }
    /// `-MapleDemoReduceMotion YES`: the reveal and the onboarding end render as under Reduce Motion
    /// (`simctl` has no Reduce Motion switch).
    static var reduceMotion: Bool { isDemoLaunch && UserDefaults.standard.bool(forKey: "MapleDemoReduceMotion") }
    /// `-MapleDemoOnboardingStep <step>`: opens onboarding on one screen (docs/debug-launch-arguments.md). The
    /// setup screens: `wake`, `weekend`, `weekend:later`, `sleep`, `winddown`, `schedule`, `schedule:weekend`,
    /// `health`, `notifications`. The end, past the schedule step (the default schedule is saved through
    /// `ScheduleStore`, in memory): `seed` holds the neutral bud, `sprout` lets it turn amber, `reveal` opens the
    /// Sugar maple (freeze it with `-MapleDemoRevealAt`), `placed` shows the grafted seedling and stays there.
    static var onboardingStep: String? {
        isDemoLaunch ? UserDefaults.standard.string(forKey: "MapleDemoOnboardingStep") : nil
    }

    /// Every store is in memory, so a demo step that saves (the onboarding's schedule) never reaches the
    /// member's files.
    private static var isDemoLaunch: Bool { DemoLaunchOptions.current.isActive }

    private static func seconds(_ key: String) -> TimeInterval? {
        guard isDemoLaunch else { return nil }
        return UserDefaults.standard.string(forKey: key).flatMap(TimeInterval.init).map { max(0, $0) }
    }
}

extension View {
    /// Applies `-MapleDemoReduceMotion` to everything inside.
    func revealDemoMotion() -> some View {
        modifier(RevealDemoMotion())
    }
}

private struct RevealDemoMotion: ViewModifier {
    func body(content: Content) -> some View {
        if RevealDemoOptions.reduceMotion {
            content.environment(\._accessibilityReduceMotion, true)
        } else {
            content
        }
    }
}
#endif
