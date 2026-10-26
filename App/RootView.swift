import SwiftUI
import UIKit
import MapleCore
import MapleDesign
import MapleServices

enum AppTab: String, Hashable {
    case home, focus, herbarium
}

/// The app's root: the end of onboarding until the first leaf is on the maple, then the three tabs (spec §2.1).
struct RootView: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(NotificationRouter.self) private var notifications
    @State private var router = AppRouter(selectedTab: .initial)
    /// Latched at launch and cleared only by onboarding's `onFinish`: the First-steps leaf is placed mid-flow, and
    /// the seedling it grows still has to be shown before Home takes over.
    @State private var isPlanting: Bool
    private let firstRun: FirstRunStep

    /// - Parameter firstRun: Where the first run starts or resumes; `.finished` opens on the tabs.
    init(firstRun: FirstRunStep) {
        self.firstRun = firstRun
        _isPlanting = State(initialValue: firstRun.needsOnboarding)
    }

    var body: some View {
        ZStack {
            if isPlanting {
                // Full screen and non-dismissable: there is no Home without a maple (D12).
                PlantYourMapleView(start: firstRun, onFinish: finishPlanting)
                    .transition(.opacity)
                    .zIndex(1)
            } else {
                tabs
                    .transition(.opacity)
            }
        }
        .environment(router)
    }

    private var tabs: some View {
        TabView(selection: $router.selectedTab) {
            // Each tab owns its navigation stack, so screens can push, present sheets and add toolbars.
            Tab("Home", image: "maple.tree", value: AppTab.home) {
                NavigationStack { HomeView() }
            }
            Tab(value: AppTab.focus) {
                NavigationStack { FocusView() }
            } label: {
                // SF `timer` (P10), selected or not. Given the symbol itself, the bar can draw another variant when
                // selected, so it gets the outline as a plain template image, as the Rest tab's moon did.
                Label { Text("Focus") } icon: { Self.timerIcon }
            }
            Tab("Herbarium", image: "maple.herbarium", value: AppTab.herbarium) {
                NavigationStack { HerbariumView() }
            }
        }
        .tint(theme.colors.textPrimary)
        .tabBarMinimizeBehavior(.onScrollDown)
        .modifier(TabBarSurface())
        // A tapped session-end notification opens its receipt once the tabs are up: on a cold launch from the tap
        // too, and after the first run if it was still on screen.
        .onChange(of: notifications.tappedReceipt, initial: true) { _, session in
            guard let session else { return }
            notifications.tappedReceipt = nil
            router.showFocus(.receipt(session))
        }
        #if DEBUG
        .demoPresenter()
        .revealDemoMotion()
        #endif
    }

    /// SF `timer` (regular) drawn once into a template bitmap, so no symbol variant can replace it.
    private static let timerIcon: Image = {
        let configuration = UIImage.SymbolConfiguration(pointSize: 21, weight: .regular)
        guard let symbol = UIImage(systemName: "timer", withConfiguration: configuration) else {
            return Image(systemName: "timer")
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let bitmap = UIGraphicsImageRenderer(size: symbol.size, format: format).image { _ in
            symbol.withTintColor(.white).draw(at: .zero)
        }
        return Image(uiImage: bitmap.withRenderingMode(.alwaysTemplate))
    }()

    /// "Place on your maple" has grafted the Sugar maple and the seedling has been seen: Home appears, holding
    /// the same seedling, with a crossfade.
    private func finishPlanting() {
        router.selectedTab = .home
        withAnimation(reduceMotion ? nil : theme.motion.calm) { isPlanting = false }
    }
}

/// The floating tab bar (spec §2.1): system Liquid Glass, which renders darker than the moonlight capsule over
/// the evening sky as it is; under Reduce Transparency it becomes solid `surface2`.
private struct TabBarSurface: ViewModifier {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .toolbarBackground(theme.colors.surface2, for: .tabBar)
            .toolbarBackgroundVisibility(reduceTransparency ? .visible : .automatic, for: .tabBar)
    }
}

private extension AppTab {
    /// Home, unless a DEBUG build was launched with `-MapleDemoTab focus|herbarium` (used for simulator screenshots).
    static var initial: AppTab {
        #if DEBUG
        if let name = UserDefaults.standard.string(forKey: "MapleDemoTab"), let tab = AppTab(rawValue: name) {
            return tab
        }
        #endif
        return .home
    }
}
