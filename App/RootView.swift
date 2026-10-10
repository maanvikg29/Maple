import SwiftUI
import MapleDesign

enum AppTab: String, Hashable {
    case home, rest, herbarium
}

struct RootView: View {
    @Environment(\.theme) private var theme
    @State private var router = AppRouter(selectedTab: .initial)

    var body: some View {
        TabView(selection: $router.selectedTab) {
            // Each tab owns its navigation stack, so screens can push, present sheets and add toolbars.
            Tab("Home", image: "maple.tree", value: AppTab.home) {
                NavigationStack { HomeView() }
            }
            Tab("Rest", systemImage: "moon", value: AppTab.rest) {
                NavigationStack { RestView() }
            }
            Tab("Herbarium", image: "maple.herbarium", value: AppTab.herbarium) {
                NavigationStack { HerbariumView() }
            }
        }
        .tint(theme.colors.textPrimary)
        .tabBarMinimizeBehavior(.onScrollDown)
        .environment(router)
        #if DEBUG
        .demoPresenter()
        #endif
    }
}

private extension AppTab {
    /// Home, unless a DEBUG build was launched with `-MapleDemoTab rest|herbarium` (used for simulator screenshots).
    static var initial: AppTab {
        #if DEBUG
        if let name = UserDefaults.standard.string(forKey: "MapleDemoTab"), let tab = AppTab(rawValue: name) {
            return tab
        }
        #endif
        return .home
    }
}
