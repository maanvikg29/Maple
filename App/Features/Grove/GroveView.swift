import SwiftUI
import MapleDesign

struct GroveView: View {
    var body: some View {
        FeatureScreen(title: "Grove") {
            PlaceholderCard(
                symbol: "tree",
                title: "Your maple tree",
                message: "Grows with every leaf and changes with the real season. Bad nights never take leaves away.",
                milestone: "M1"
            )
            PlaceholderCard(
                symbol: "book.closed",
                title: "Herbarium",
                message: "Every leaf you've earned, with the date and what earned it.",
                milestone: "M2"
            )
        }
    }
}

#Preview {
    NavigationStack { GroveView() }
        .preferredColorScheme(.dark)
}
