import SwiftUI
import MapleCore
import MapleDesign

struct TodayView: View {
    @Environment(\.theme) private var theme
    @State private var showingSettings = false

    private var season: Season {
        Season(for: .now, hemisphere: .current)
    }

    var body: some View {
        FeatureScreen(title: greeting) {
            GlowCard {
                HStack(alignment: .center, spacing: theme.spacing.lg) {
                    LeafGlyph(color: theme.colors.leaves.color(for: season), size: 56)
                    VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                        SectionLabel("Your maple")
                        Text("Waiting for its first leaf")
                            .font(MapleFont.headline)
                            .foregroundStyle(theme.colors.textPrimary)
                        Text("Keep tonight's bedtime and you'll find it here in the morning.")
                            .font(MapleFont.callout)
                            .foregroundStyle(theme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            PlaceholderCard(
                symbol: "moon.zzz",
                title: "Tonight",
                message: "A countdown to wind-down and bedtime, based on the schedule you set up in onboarding.",
                milestone: "M1"
            )

            PlaceholderCard(
                symbol: "sunrise",
                title: "Morning check-in",
                message: "See last night's leaf, how you slept, and tend your tree.",
                milestone: "M1"
            )
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Settings", systemImage: "gearshape") {
                    showingSettings = true
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }

    private var greeting: LocalizedStringKey {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<22: "Good evening"
        default: "Rest well"
        }
    }
}

#Preview {
    NavigationStack { TodayView() }
        .preferredColorScheme(.dark)
}
