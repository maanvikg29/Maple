#if DEBUG
import SwiftUI

/// DEBUG only: opens the app-level screens named by `-MapleDemoPresent` on launch, so each can be screenshotted
/// in the simulator without tapping (docs/debug-launch-arguments.md). `schedule` and its `schedule:…` forms open
/// Settings in the Profile sheet, which then opens the schedule editor (`SleepDemo`). Feature-level routes are
/// handled by the features themselves, and `onboarding` by `RootView`'s first-run gate (`MapleApp.needsOnboarding`).
private enum DemoPresentation: String, Identifiable {
    case reveal, profile, winddown, schedule

    var id: String { rawValue }

    /// The Profile sheet (on Settings, for the schedule editor); the others are full-screen covers.
    var isSheet: Bool { self == .profile || self == .schedule }

    static var requested: DemoPresentation? {
        guard let value = UserDefaults.standard.string(forKey: "MapleDemoPresent") else { return nil }
        if value.hasPrefix("schedule:") { return .schedule }
        return DemoPresentation(rawValue: value)
    }
}

private struct DemoPresenter: ViewModifier {
    @State private var cover: DemoPresentation? = DemoPresentation.requested.flatMap { $0.isSheet ? nil : $0 }
    @State private var sheet: DemoPresentation? = DemoPresentation.requested.flatMap { $0.isSheet ? $0 : nil }

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $cover) { presentation in
                switch presentation {
                case .reveal: RevealFlow()
                case .winddown: WindDownView()
                case .profile, .schedule: EmptyView()
                }
            }
            .sheet(item: $sheet) { presentation in
                ProfileView(path: presentation == .schedule ? [.settings] : nil)
            }
    }
}

extension View {
    func demoPresenter() -> some View {
        modifier(DemoPresenter())
    }
}
#endif
