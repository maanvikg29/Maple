import SwiftUI
import MapleDesign

enum AppTab: Hashable {
    case today, sleep, focus, grove, insights
}

struct RootView: View {
    @Environment(\.theme) private var theme
    @State private var selection: AppTab = .today

    var body: some View {
        TabView(selection: $selection) {
            // Each tab owns its navigation stack, so screens can add toolbars, sheets and pushes.
            Tab("Today", systemImage: "sun.horizon", value: AppTab.today) {
                NavigationStack { TodayView() }
            }
            Tab("Sleep", systemImage: "moon.stars", value: AppTab.sleep) {
                NavigationStack { SleepView() }
            }
            Tab("Focus", systemImage: "timer", value: AppTab.focus) {
                NavigationStack { FocusView() }
            }
            Tab("Grove", systemImage: "leaf", value: AppTab.grove) {
                NavigationStack { GroveView() }
            }
            Tab("Insights", systemImage: "chart.bar.xaxis", value: AppTab.insights) {
                NavigationStack { InsightsView() }
            }
        }
        .tint(theme.colors.textPrimary)
    }
}

#Preview {
    RootView()
        .preferredColorScheme(.dark)
}
