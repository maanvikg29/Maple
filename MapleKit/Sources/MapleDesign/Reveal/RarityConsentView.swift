import MapleCore
import SwiftUI

/// The rarity consent sheet (spec §5.7, D5): asked once, as a `.medium` sheet at the end of the first morning
/// reveal. Opt-in: nothing is counted before "Include my leaves". Present it on `surface2`:
///
/// ```swift
/// .sheet(isPresented: $asksConsent) {
///     RarityConsentView(species: rubrum, colourway: .autumn, onInclude: { … }, onNotNow: { … })
///         .presentationDetents([.medium])
///         .presentationBackground(theme.colors.surface2)
/// }
/// ```
public struct RarityConsentView: View {
    @Environment(\.theme) private var theme

    private let species: LeafSpecies?
    private let colourway: LeafColourway
    private let onInclude: () -> Void
    private let onNotNow: () -> Void

    /// - Parameters:
    ///   - species: The leaf just placed, shown small above the question; nil shows the words alone.
    public init(
        species: LeafSpecies?, colourway: LeafColourway, onInclude: @escaping () -> Void, onNotNow: @escaping () -> Void
    ) {
        self.species = species
        self.colourway = colourway
        self.onInclude = onInclude
        self.onNotNow = onNotNow
    }

    nonisolated public static let title = "Help show how rare each leaf is?"
    /// Spec §5.7's body, adapted to the CloudKit counters (overrides 1): Maple adds to shared counts rather than
    /// sending a scrambled weekly list.
    nonisolated public static let message = "Maple can add the leaves you hold to an anonymous count. No account, no device ID, no health data."

    public var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    if let species {
                        SpecimenView(species: species, colourway: colourway, size: 64)
                            .accessibilityHidden(true)
                            .padding(.bottom, theme.spacing.md)
                    }
                    Text(Self.title)
                        .font(MapleFont.screenTitle)
                        .foregroundStyle(theme.colors.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text(Self.message)
                        .font(MapleFont.callout)
                        .foregroundStyle(theme.colors.textSecondary)
                        .padding(.top, theme.spacing.sm)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, theme.spacing.homeMargin)
                .padding(.vertical, theme.spacing.lg)
                // Centred in the room above the buttons; scrolls when large text needs more.
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: theme.spacing.xxs) {
                Button("Include my leaves", action: onInclude)
                    .buttonStyle(.moonlight)
                TextLink("Not now", chevron: false, action: onNotNow)
            }
            .padding(.horizontal, theme.spacing.homeMargin)
            .padding(.top, theme.spacing.sm)
            // The sheet sits on surface2.
            .footerFade(theme.colors.surface2)
        }
    }
}
