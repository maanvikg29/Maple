import SwiftUI
import MapleCore
import MapleDesign

/// One onboarding screen (spec §8.8): a quiet top bar with the back circle and the progress hairline, the content,
/// and the one primary capsule pinned at the bottom.
///
/// - The hairline is the season tint on `track`, 2pt, centred between the back circle's slot and an equal slot on
///   the right, so it never moves when the back circle is absent (the first question, the primers).
/// - The content scrolls only when large text needs more room than the screen has.
struct OnboardingPage<Content: View>: View {
    let step: OnboardingStep
    var onBack: (() -> Void)?
    var primary: Primary?
    @ViewBuilder var content: Content

    /// The capsule at the bottom.
    struct Primary {
        var title: String
        var isEnabled = true
        var action: () -> Void
    }

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            OnboardingTopBar(progress: step.progress ?? 1, onBack: onBack)
            GeometryReader { proxy in
                ScrollView {
                    content
                        .padding(.horizontal, theme.spacing.homeMargin)
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .top)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let primary {
                Button(primary.title, action: primary.action)
                    .buttonStyle(.moonlight)
                    .disabled(!primary.isEnabled)
                    .padding(.horizontal, theme.spacing.homeMargin)
                    .padding(.top, theme.spacing.sm)
                    .padding(.bottom, theme.spacing.md)
                    .footerFade(theme.colors.background)
            }
        }
    }
}

/// The back circle (when there is a way back) and the progress hairline.
struct OnboardingTopBar: View {
    let progress: Double
    var onBack: (() -> Void)?

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: theme.spacing.sm) {
            ZStack {
                if let onBack {
                    Button("Back", systemImage: "chevron.left", action: onBack)
                        .buttonStyle(.iconCircle)
                        .transition(.opacity)
                }
            }
            .frame(width: theme.spacing.minimumHitTarget, height: theme.spacing.minimumHitTarget)
            ProgressHairline(fraction: progress)
                .accessibilityHidden(true)
            Color.clear
                .frame(width: theme.spacing.minimumHitTarget, height: theme.spacing.minimumHitTarget)
                .accessibilityHidden(true)
        }
        // The back circle's 44pt hit area overhangs the margin, so the glyph lines up with the content edge.
        .padding(.horizontal, theme.spacing.homeMargin - 4)
        .padding(.top, theme.spacing.xs)
        .accessibilityElement(children: .contain)
    }
}

/// A question's words: the question in `screenTitle` and one quiet line under it, centred.
struct OnboardingQuestionHeader: View {
    let title: String
    let subtitle: String?

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: theme.spacing.xs) {
            Text(title)
                .font(MapleFont.screenTitle)
                .tracking(-0.3)
                .foregroundStyle(theme.colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(MapleFont.callout)
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
    }
}

/// The hour-and-minute wheel used by the wake questions. Only the hour and minute matter; a fixed reference day
/// keeps daylight-saving changes out of it.
struct ClockWheel: View {
    let label: String
    @Binding var time: ClockTime

    @Environment(\.calendar) private var calendar

    var body: some View {
        DatePicker(label, selection: Binding(get: { date(for: time) }, set: { time = HomeFormat.clockTime(of: $0, calendar: calendar) }),
                   displayedComponents: .hourAndMinute)
            .datePickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: 320)
    }

    private func date(for time: ClockTime) -> Date {
        let reference = calendar.date(from: DateComponents(year: 2001, month: 1, day: 1)) ?? Date(timeIntervalSinceReferenceDate: 0)
        return calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: reference) ?? reference
    }
}
