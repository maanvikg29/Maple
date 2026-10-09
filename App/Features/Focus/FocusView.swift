import SwiftUI
import MapleDesign

struct FocusView: View {
    var body: some View {
        FeatureScreen(title: "Focus") {
            PlaceholderCard(
                symbol: "timer",
                title: "Focus sessions",
                message: "A calm timer for study and deep work. Each finished session earns a leaf.",
                milestone: "M2"
            )
            PlaceholderCard(
                symbol: "app.badge.checkmark",
                title: "Distraction blocking",
                message: "Blocks the apps you choose while a session runs.",
                milestone: "M3"
            )
        }
    }
}

#Preview {
    NavigationStack { FocusView() }
        .preferredColorScheme(.dark)
}
