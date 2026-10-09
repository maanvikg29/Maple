import SwiftUI
import MapleDesign

struct InsightsView: View {
    var body: some View {
        FeatureScreen(title: "Insights") {
            PlaceholderCard(
                symbol: "chart.bar",
                title: "Sleep trends",
                message: "Duration and bedtime consistency over the last week and month.",
                milestone: "M2"
            )
            PlaceholderCard(
                symbol: "moon.haze",
                title: "Last scroll",
                message: "When you stop scrolling at night, and which apps keep you up. Never leaves your iPhone.",
                milestone: "M3"
            )
        }
    }
}

#Preview {
    NavigationStack { InsightsView() }
        .preferredColorScheme(.dark)
}
