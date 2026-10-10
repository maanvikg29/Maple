import MapleCore
import SwiftUI

/// The calm primer before Apple's Health sheet (spec D9): one leaf the member can earn from their sleep, two
/// sentences on what Maple reads and that it stays on the iPhone, "Continue" (which shows Apple's sheet) and
/// "Not now". Present it as a `.medium` sheet on `surface2`, like the rarity consent:
///
/// ```swift
/// .sheet(isPresented: $asksForHealth) {
///     HealthPrimerView(species: rubrum, colourway: .autumn, onContinue: { … }, onNotNow: { … })
///         .presentationDetents([.medium])
///         .presentationBackground(theme.colors.surface2)
/// }
/// ```
public struct HealthPrimerView: View {
    @Environment(\.theme) private var theme

    private let species: LeafSpecies?
    private let colourway: LeafColourway
    private let isAsking: Bool
    private let onContinue: () -> Void
    private let onNotNow: () -> Void

    /// - Parameters:
    ///   - species: A leaf Apple Health would let the member earn, drawn above the words; nil shows the words alone.
    ///   - isAsking: Apple's sheet is on its way; "Continue" waits.
    public init(
        species: LeafSpecies?, colourway: LeafColourway, isAsking: Bool = false, onContinue: @escaping () -> Void,
        onNotNow: @escaping () -> Void
    ) {
        self.species = species
        self.colourway = colourway
        self.isAsking = isAsking
        self.onContinue = onContinue
        self.onNotNow = onNotNow
    }

    nonisolated public static let title = "Grow leaves from your sleep"
    /// What Maple reads, and that it stays on the iPhone (rewards.md: raw health data never leaves the iPhone).
    nonisolated public static let message = "Maple reads your sleep from Apple Health: when you fell asleep, when you woke and how long you slept. It stays on your iPhone."
    nonisolated public static let continueTitle = "Continue"
    nonisolated public static let notNowTitle = "Not now"

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
                Button(Self.continueTitle, action: onContinue)
                    .buttonStyle(.moonlight)
                    .disabled(isAsking)
                    .accessibilityHint("Shows Apple Health's permission sheet.")
                TextLink(Self.notNowTitle, chevron: false, action: onNotNow)
            }
            .padding(.horizontal, theme.spacing.homeMargin)
            .padding(.top, theme.spacing.sm)
            // The sheet sits on surface2.
            .footerFade(theme.colors.surface2)
        }
    }
}
