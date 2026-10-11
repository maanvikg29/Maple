import MapleCore
import SwiftUI

/// The calm primer before iOS's notification prompt, in `HealthPrimerView`'s pattern: one leaf, a title and one
/// sentence on the only two reminders Maple sends, "Allow reminders" (which shows iOS's prompt) and "Not now".
///
/// Present it as a `.medium` sheet on `surface2` (Settings), or full screen on `background` (the first run):
///
/// ```swift
/// .sheet(isPresented: $asksForReminders) {
///     NotificationsPrimerView(species: saccharum, colourway: .autumn, onAllow: { … }, onNotNow: { … })
///         .presentationDetents([.medium])
///         .presentationBackground(theme.colors.surface2)
/// }
/// ```
public struct NotificationsPrimerView: View {
    @Environment(\.theme) private var theme

    private let species: LeafSpecies?
    private let colourway: LeafColourway
    private let isAsking: Bool
    private let page: Color?
    private let onAllow: () -> Void
    private let onNotNow: () -> Void

    /// - Parameters:
    ///   - species: A leaf drawn above the words (the member's first leaf reads well); nil shows the words alone.
    ///   - isAsking: iOS's prompt is on its way; "Allow reminders" waits.
    ///   - page: The colour behind the buttons, which the content fades into: `surface2` (the default) in a
    ///     sheet, `background` on a full screen.
    public init(
        species: LeafSpecies? = nil, colourway: LeafColourway = .summer, isAsking: Bool = false, page: Color? = nil,
        onAllow: @escaping () -> Void, onNotNow: @escaping () -> Void
    ) {
        self.species = species
        self.colourway = colourway
        self.isAsking = isAsking
        self.page = page
        self.onAllow = onAllow
        self.onNotNow = onNotNow
    }

    nonisolated public static let title = "Two gentle reminders"
    /// What Maple sends, and that it sends nothing more.
    nonisolated public static let message = "One when it's time to wind down, and one in the morning when a leaf is waiting. Nothing else."
    nonisolated public static let allowTitle = "Allow reminders"
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
                Button(Self.allowTitle, action: onAllow)
                    .buttonStyle(.moonlight)
                    .disabled(isAsking)
                    .accessibilityHint("Shows the iPhone's notification permission prompt.")
                TextLink(Self.notNowTitle, chevron: false, action: onNotNow)
            }
            .padding(.horizontal, theme.spacing.homeMargin)
            .padding(.top, theme.spacing.sm)
            .footerFade(page ?? theme.colors.surface2)
        }
    }
}
