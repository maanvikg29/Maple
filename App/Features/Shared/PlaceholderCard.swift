import SwiftUI
import MapleDesign

/// Stands in for a feature that hasn't been built yet, and says which milestone delivers it.
struct PlaceholderCard: View {
    @Environment(\.theme) private var theme
    let symbol: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let milestone: String

    var body: some View {
        GlowCard {
            VStack(alignment: .leading, spacing: theme.spacing.sm) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(theme.colors.textSecondary)
                    .accessibilityHidden(true)
                Text(title)
                    .font(MapleFont.headline)
                    .foregroundStyle(theme.colors.textPrimary)
                Text(message)
                    .font(MapleFont.callout)
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Arrives in \(milestone)")
                    .font(MapleFont.overline)
                    .foregroundStyle(theme.colors.textSecondary)
                    .padding(.horizontal, theme.spacing.xs)
                    .padding(.vertical, theme.spacing.xxs)
                    .overlay(Capsule().strokeBorder(theme.colors.borderSoft))
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// A scrolling screen with Maple's background and standard margins.
/// Expects to sit inside a `NavigationStack` (each tab provides one).
struct FeatureScreen<Content: View>: View {
    @Environment(\.theme) private var theme
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.lg) {
                content
            }
            .padding(.horizontal, theme.spacing.screen)
            .padding(.vertical, theme.spacing.md)
        }
        .mapleBackground()
        .navigationTitle(title)
    }
}
