import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// The four onboarding questions (spec §8.8), one per screen, before "Your sleep schedule":
///
/// 1. "When do you need to be up on weekdays?": a time wheel.
/// 2. "And on weekends?": "Same time" or "Later", with a wheel for the later time.
/// 3. "How much sleep feels best?": 7h to 9h in half hours (default 7h 30m), which becomes Settings › Sleep goal.
/// 4. "How long do you like to wind down?": 30m, 45m or 1h.
///
/// Every change is saved at once (`OnboardingStore`), so a relaunch opens on the same question with the same
/// answers. Each answer shows its consequence in one quiet line (the bedtime it leads to), so the proposal on the
/// next screen is never a surprise.
struct OnboardingQuestionView: View {
    let step: OnboardingStep
    var onBack: (() -> Void)?
    var onContinue: () -> Void

    @Environment(OnboardingStore.self) private var onboarding
    @Environment(\.theme) private var theme

    var body: some View {
        OnboardingPage(step: step, onBack: onBack, primary: .init(title: "Continue", action: onContinue)) {
            Group {
                switch step {
                case .weekdayWake: WeekdayWakeQuestion()
                case .weekendWake: WeekendWakeQuestion()
                case .sleepNeed: SleepNeedQuestion()
                case .windDown: WindDownQuestion()
                case .schedule, .health, .notifications, .sprout: EmptyView()
                }
            }
            .padding(.top, theme.spacing.hero)
            .padding(.bottom, theme.spacing.xl)
        }
    }
}

/// The answers as a binding into the store, so every change is saved.
private struct AnswerBinding {
    let store: OnboardingStore

    func callAsFunction<Value>(_ keyPath: WritableKeyPath<OnboardingAnswers, Value>) -> Binding<Value> {
        Binding {
            store.answers[keyPath: keyPath]
        } set: { value in
            var answers = store.answers
            answers[keyPath: keyPath] = value
            store.answers = answers
        }
    }
}

/// The quiet consequence line under an answer: "Bed about 23:15".
private struct ConsequenceLine: View {
    let text: String
    @Environment(\.theme) private var theme

    var body: some View {
        Text(text)
            .font(MapleFont.callout)
            .monospacedDigit()
            .foregroundStyle(theme.colors.textSecondary)
            .multilineTextAlignment(.center)
            .contentTransition(.numericText())
            .mapleAnimation(theme.motion.gentle, value: text)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - 1. Weekday wake

private struct WeekdayWakeQuestion: View {
    @Environment(OnboardingStore.self) private var onboarding
    @Environment(\.theme) private var theme

    var body: some View {
        let answer = AnswerBinding(store: onboarding)
        VStack(spacing: 0) {
            OnboardingQuestionHeader(
                title: "When do you need to be up on weekdays?",
                subtitle: "Your bedtime is worked back from it."
            )
            ClockWheel(label: "Weekday wake-up time", time: answer(\.weekdayWake))
                .padding(.top, theme.spacing.xxl)
        }
    }
}

// MARK: - 2. Weekend wake

private struct WeekendWakeQuestion: View {
    @Environment(OnboardingStore.self) private var onboarding
    @Environment(\.theme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar

    private enum Choice: Hashable {
        case same, later

        var title: String { self == .same ? "Same time" : "Later" }
    }

    var body: some View {
        let answers = onboarding.answers
        let choice: Binding<Choice> = Binding {
            answers.weekendWake == nil ? .same : .later
        } set: { choice in
            var updated = onboarding.answers
            updated.weekendWake = choice == .same ? nil : (updated.weekendWake ?? updated.suggestedWeekendWake)
            onboarding.answers = updated
        }
        let later = Binding<ClockTime> {
            onboarding.answers.weekendWake ?? onboarding.answers.suggestedWeekendWake
        } set: { time in
            var updated = onboarding.answers
            updated.weekendWake = time
            onboarding.answers = updated
        }

        VStack(spacing: 0) {
            OnboardingQuestionHeader(title: "And on weekends?", subtitle: RestCopy.weekendMornings(calendar: calendar))
            SegmentedCapsule(selection: choice, options: [Choice.same, .later], size: .regular) { $0.title }
                .accessibilityLabel(Text("Weekend wake-up"))
                .padding(.top, theme.spacing.xxl)
            // The wheel's room is kept for "Same time" too, so nothing moves under the finger.
            ZStack {
                if answers.weekendWake != nil {
                    ClockWheel(label: "Weekend wake-up time", time: later)
                        .transition(.opacity)
                } else {
                    ConsequenceLine(text: "Up at \(HomeFormat.clock(answers.weekdayWake, locale: locale)), as on weekdays")
                        .transition(.opacity)
                }
            }
            .frame(minHeight: Self.wheelHeight)
            .padding(.top, theme.spacing.md)
            .mapleAnimation(theme.motion.gentle, value: answers.weekendWake == nil)
        }
    }

    /// The system wheel's height, kept for the "Same time" line.
    private static let wheelHeight: CGFloat = 216
}

// MARK: - 3. Sleep need

private struct SleepNeedQuestion: View {
    @Environment(OnboardingStore.self) private var onboarding
    @Environment(\.theme) private var theme
    @Environment(\.locale) private var locale

    private let choices = OnboardingAnswers.sleepNeedChoices

    var body: some View {
        let answers = onboarding.answers
        let need = answers.sleepNeedMinutes
        let index = choices.firstIndex(of: need) ?? 1
        let bedtime = answers.proposal(waking: answers.weekdayWake).bedtime
        let bedLine = "Bed about \(HomeFormat.clock(bedtime, locale: locale))"
            + (answers.weekendWake == nil ? "" : " on weekdays")

        VStack(spacing: 0) {
            OnboardingQuestionHeader(title: "How much sleep feels best?", subtitle: "Most people feel best with 7 to 9 hours.")
            HStack(spacing: theme.spacing.lg) {
                Button("Less sleep", systemImage: "minus") { select(index - 1) }
                    .buttonStyle(.iconCircle)
                    .disabled(index == 0)
                StatNumber(HomeFormat.durationParts(minutes: need).map { $0.isUnit ? .unit($0.text) : .value($0.text) }, size: .hero)
                    .frame(minWidth: 168)
                Button("More sleep", systemImage: "plus") { select(index + 1) }
                    .buttonStyle(.iconCircle)
                    .disabled(index == choices.count - 1)
            }
            .padding(.top, theme.spacing.xxl)
            // One adjustable element for VoiceOver: swipe up or down to change it.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Sleep need"))
            .accessibilityValue(Text(HomeFormat.spokenDuration(minutes: need, locale: locale)))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: select(index + 1)
                case .decrement: select(index - 1)
                @unknown default: break
                }
            }
            ChoiceDots(count: choices.count, selected: index)
                .padding(.top, theme.spacing.md)
            ConsequenceLine(text: bedLine)
                .padding(.top, theme.spacing.lg)
        }
        .sensoryFeedback(.selection, trigger: need)
    }

    private func select(_ index: Int) {
        guard choices.indices.contains(index) else { return }
        var updated = onboarding.answers
        updated.sleepNeedMinutes = choices[index]
        onboarding.answers = updated
    }
}

/// Where the sleep need sits among its five choices: 6pt dots, the chosen one in the season tint.
private struct ChoiceDots: View {
    let count: Int
    let selected: Int

    @Environment(\.theme) private var theme
    @Environment(\.season) private var season

    var body: some View {
        HStack(spacing: theme.spacing.xs) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == selected ? theme.colors.seasonTint(season) : theme.colors.track)
                    .frame(width: 6, height: 6)
            }
        }
        .mapleAnimation(theme.motion.gentle, value: selected)
        .accessibilityHidden(true)
    }
}

// MARK: - 4. Wind-down

private struct WindDownQuestion: View {
    @Environment(OnboardingStore.self) private var onboarding
    @Environment(\.theme) private var theme
    @Environment(\.locale) private var locale

    var body: some View {
        let answer = AnswerBinding(store: onboarding)
        let answers = onboarding.answers
        let start = answers.proposal(waking: answers.weekdayWake).windDownStart
        let line = "Wind-down from \(HomeFormat.clock(start, locale: locale))" + (answers.weekendWake == nil ? "" : " on weekdays")

        VStack(spacing: 0) {
            OnboardingQuestionHeader(
                title: "How long do you like to wind down?",
                subtitle: "A quiet stretch before bed, with the phone put away."
            )
            SegmentedCapsule(selection: answer(\.windDownMinutes), options: OnboardingAnswers.windDownChoices, size: .regular) {
                RestCopy.windDownOption(minutes: $0)
            }
            .accessibilityLabel(Text("Wind-down length"))
            .padding(.top, theme.spacing.xxl)
            ConsequenceLine(text: line)
                .padding(.top, theme.spacing.lg)
        }
    }
}
