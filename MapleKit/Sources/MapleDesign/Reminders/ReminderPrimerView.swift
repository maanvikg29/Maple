import MapleCore
import SwiftUI

/// The calm primer before Apple's notification prompt (architecture: a primer before every system prompt): the
/// moon, two sentences on what Maple sends and when, "Continue" (which shows Apple's prompt) and "Not now". Like the
/// Apple Health primer, present it as a `.medium` sheet on `surface2`:
///
/// ```swift
/// .sheet(isPresented: $offersReminders) {
///     ReminderPrimerView(windDownStart: "22:15", onContinue: { … }, onNotNow: { … })
///         .presentationDetents([.medium])
///         .presentationBackground(theme.colors.surface2)
/// }
/// ```
///
/// It never mentions leaves: reminders are about the evening, not progress (rewards.md).
public struct ReminderPrimerView: View {
    @Environment(\.theme) private var theme
    @Environment(\.season) private var season

    private let windDownStart: String
    private let isAsking: Bool
    private let onContinue: () -> Void
    private let onNotNow: () -> Void

    /// - Parameters:
    ///   - windDownStart: Tonight's wind-down start as a clock time in the member's locale ("22:15", "10:15 PM").
    ///   - isAsking: Apple's prompt is on its way; "Continue" waits.
    public init(
        windDownStart: String, isAsking: Bool = false, onContinue: @escaping () -> Void,
        onNotNow: @escaping () -> Void
    ) {
        self.windDownStart = windDownStart
        self.isAsking = isAsking
        self.onContinue = onContinue
        self.onNotNow = onNotNow
    }

    nonisolated public static let title = "A nudge at wind-down"
    nonisolated public static func message(windDownStart: String) -> String {
        "Maple can remind you at \(windDownStart), when your wind-down starts. You can change this any time in Settings."
    }
    nonisolated public static let continueTitle = "Continue"
    nonisolated public static let notNowTitle = "Not now"

    public var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Image(systemName: "moon")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(theme.colors.seasonTint(season))
                        .accessibilityHidden(true)
                        .padding(.bottom, theme.spacing.md)
                    Text(Self.title)
                        .font(MapleFont.screenTitle)
                        .foregroundStyle(theme.colors.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text(Self.message(windDownStart: windDownStart))
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
                    .accessibilityHint("Shows the notification permission prompt.")
                TextLink(Self.notNowTitle, chevron: false, action: onNotNow)
            }
            .padding(.horizontal, theme.spacing.homeMargin)
            .padding(.top, theme.spacing.sm)
            // The sheet sits on surface2.
            .footerFade(theme.colors.surface2)
        }
    }
}
