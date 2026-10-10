#if DEBUG
import SwiftUI

/// DEBUG only: opens the app-level screens named by `-MapleDemoPresent` on launch, so each can be screenshotted
/// in the simulator without tapping (docs/debug-launch-arguments.md). Feature-level routes are handled by the
/// features themselves.
private enum DemoPresentation: String, Identifiable {
    case reveal, onboarding, profile, winddown

    var id: String { rawValue }

    static var requested: DemoPresentation? {
        UserDefaults.standard.string(forKey: "MapleDemoPresent").flatMap(DemoPresentation.init(rawValue:))
    }
}

private struct DemoPresenter: ViewModifier {
    @State private var cover: DemoPresentation? = DemoPresentation.requested.flatMap { $0 == .profile ? nil : $0 }
    @State private var sheet: DemoPresentation? = DemoPresentation.requested.flatMap { $0 == .profile ? $0 : nil }

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $cover) { presentation in
                switch presentation {
                case .reveal: RevealFlow()
                case .onboarding: PlantYourMapleView { cover = nil }
                case .winddown: WindDownView()
                case .profile: EmptyView()
                }
            }
            .sheet(item: $sheet) { _ in ProfileView() }
    }
}

extension View {
    func demoPresenter() -> some View {
        modifier(DemoPresenter())
    }
}
#endif
