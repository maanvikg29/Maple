import SwiftUI
import MapleCore
import MapleDesign

/// A living reference of Maple's tokens and components, for reviewing the look on a real screen.
struct DesignSystemView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.xl) {
                colors
                leaves
                typography
                components
            }
            .padding(.horizontal, theme.spacing.screen)
            .padding(.vertical, theme.spacing.md)
        }
        .mapleBackground()
        .navigationTitle("Design system")
    }

    private var colors: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            SectionLabel("Colour")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: theme.spacing.sm)], spacing: theme.spacing.sm) {
                Swatch(name: "Background", color: theme.colors.background)
                Swatch(name: "Raised", color: theme.colors.backgroundRaised)
                Swatch(name: "Surface", color: theme.colors.surface)
                Swatch(name: "Text", color: theme.colors.textPrimary)
                Swatch(name: "Secondary", color: theme.colors.textSecondary)
                Swatch(name: "Reward", color: theme.colors.reward)
            }
        }
    }

    private var leaves: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            SectionLabel("Leaves")
            GlowCard {
                HStack(spacing: theme.spacing.md) {
                    ForEach(Season.allCases, id: \.self) { season in
                        VStack(spacing: theme.spacing.xs) {
                            LeafGlyph(color: theme.colors.leaves.color(for: season), size: 44)
                            Text(season.rawValue.capitalized)
                                .font(MapleFont.caption)
                                .foregroundStyle(theme.colors.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private var typography: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            SectionLabel("Type")
            GlowCard {
                VStack(alignment: .leading, spacing: theme.spacing.sm) {
                    Text("Display").font(MapleFont.display)
                    Text("Title").font(MapleFont.title)
                    Text("Headline").font(MapleFont.headline)
                    Text("Body text reads in SF Pro at the user's chosen size.").font(MapleFont.body)
                    Text("Caption").font(MapleFont.caption).foregroundStyle(theme.colors.textSecondary)
                }
                .foregroundStyle(theme.colors.textPrimary)
            }
        }
    }

    private var components: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            SectionLabel("Components")
            GlowCard {
                StatNumber("7h 42m", label: "Last night")
            }
            GlowCard {
                HStack(alignment: .top) {
                    StatNumber("12", unit: "leaves", label: "This week", size: .compact)
                    Spacer()
                    StatNumber("86", label: "Consistency", size: .compact)
                }
            }
            Button("Start wind-down") {}
                .buttonStyle(.maple)
            Button("Not now") {}
                .buttonStyle(.mapleSecondary)
        }
    }
}

private struct Swatch: View {
    @Environment(\.theme) private var theme
    let name: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xxs) {
            RoundedRectangle(cornerRadius: theme.radius.chip, style: .continuous)
                .fill(color)
                .frame(height: 56)
                .overlay {
                    RoundedRectangle(cornerRadius: theme.radius.chip, style: .continuous)
                        .strokeBorder(theme.colors.borderSoft)
                }
            Text(name)
                .font(MapleFont.caption)
                .foregroundStyle(theme.colors.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
    }
}

#Preview {
    NavigationStack {
        DesignSystemView()
    }
    .preferredColorScheme(.dark)
}
