import SwiftUI
import MapleDesign

enum AppTab: Hashable {
    case home, rest, herbarium
}

struct RootView: View {
    @Environment(\.theme) private var theme
    @State private var selection: AppTab = .home

    var body: some View {
        TabView(selection: $selection) {
            // Each tab owns its navigation stack, so screens can push, present sheets and add toolbars.
            Tab("Home", systemImage: "tree", value: AppTab.home) {
                NavigationStack { HomeView() }
            }
            Tab("Rest", systemImage: "moon", value: AppTab.rest) {
                NavigationStack { RestView() }
            }
            Tab("Herbarium", systemImage: "book.closed", value: AppTab.herbarium) {
                NavigationStack { HerbariumView() }
            }
        }
        .tint(theme.colors.textPrimary)
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}
