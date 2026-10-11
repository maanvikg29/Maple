import SwiftUI
import MapleCore
import MapleDesign

/// "Your sleep schedule", after the questions: one calm screen that opens on the schedule proposed from the answers
/// (bedtime = wake − sleep need − 15 minutes, per variant; "Proposed from your answers"), which the member can still
/// adjust. Saving it earns the First-steps leaf (the Sugar maple, "Set your sleep schedule"), which the end of
/// onboarding reveals (spec §8.8, D12).
///
/// The two times are the hero: tapping one selects it and the wheel below edits it. When the weekend wake differs,
/// a "Weekdays · Weekends" capsule above the times switches which nights they are for.
struct SleepScheduleStep: View {
    /// The schedule the answers propose.
    let proposal: WeeklySleepSchedule
    /// Called with every change, so a relaunch reopens the step as the member left it.
    var onChange: (WeeklySleepSchedule) -> Void
    var onBack: () -> Void
    /// Called with the schedule when the member taps "Save schedule".
    var onSave: (WeeklySleepSchedule) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    @State private var weekday: SleepSchedule
    /// Nil when every night is the same.
    @State private var weekend: SleepSchedule?
    @State private var nights: WeeklySleepSchedule.Variant = .weekday
    @State private var editing: Edge = .bedtime

    private enum Edge: Hashable {
        case bedtime, wake
    }

    static let windDownChoices = OnboardingAnswers.windDownChoices

    /// - Parameter start: The schedule the step opens on: the member's earlier draft, else the proposal.
    init(
        proposal: WeeklySleepSchedule, start: WeeklySleepSchedule, onChange: @escaping (WeeklySleepSchedule) -> Void,
        onBack: @escaping () -> Void, onSave: @escaping (WeeklySleepSchedule) -> Void
    ) {
        self.proposal = proposal
        self.onChange = onChange
        self.onBack = onBack
        self.onSave = onSave
        _weekday = State(initialValue: start.weekday)
        _weekend = State(initialValue: start.weekend)
    }

    /// What "Save schedule" stores.
    private var schedule: WeeklySleepSchedule {
        WeeklySleepSchedule(weekday: weekday, weekend: weekend)
    }

    /// The times on screen.
    private var shown: Binding<SleepSchedule> {
        Binding {
            nights == .weekend ? (weekend ?? weekday) : weekday
        } set: { value in
            if nights == .weekend, weekend != nil { weekend = value } else { weekday = value }
        }
    }

    var body: some View {
        OnboardingPage(
            step: .schedule, onBack: onBack,
            primary: .init(title: "Save schedule", isEnabled: canSave) { onSave(schedule) }
        ) {
            VStack(spacing: 0) {
                header
                if weekend != nil {
                    nightsChoice
                        .padding(.top, theme.spacing.lg)
                }
                times
                    .padding(.top, weekend == nil ? theme.spacing.xxl : theme.spacing.md)
                Text("\(HomeFormat.duration(minutes: shown.wrappedValue.minutesInBed)) in bed")
                    .font(MapleFont.callout)
                    .monospacedDigit()
                    .foregroundStyle(theme.colors.textSecondary)
                    .contentTransition(.numericText())
                    .padding(.top, theme.spacing.sm)
                    .accessibilityLabel("\(HomeFormat.spokenDuration(minutes: shown.wrappedValue.minutesInBed, locale: locale)) in bed")
                wheel
                    .padding(.top, theme.spacing.xs)
                windDownChoice
                    .padding(.top, theme.spacing.md)
            }
            .padding(.top, theme.spacing.xl)
            .padding(.bottom, theme.spacing.xl)
        }
        .sensoryFeedback(.selection, trigger: editing)
        .mapleAnimation(theme.motion.gentle, value: shown.wrappedValue)
        .mapleAnimation(theme.motion.gentle, value: nights)
        .onChange(of: schedule) { onChange(schedule) }
    }

    private var canSave: Bool {
        weekday.minutesInBed > 0 && (weekend?.minutesInBed ?? 1) > 0
    }

    // MARK: Parts

    private var header: some View {
        VStack(spacing: theme.spacing.xs) {
            Text("Your sleep schedule")
                .font(MapleFont.screenTitle)
                .tracking(-0.3)
                .foregroundStyle(theme.colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                Text(schedule == proposal ? "Proposed from your answers." : "Adjusted from your answers.")
                    .contentTransition(.opacity)
                Text("Saving it plants your maple.")
            }
            .font(MapleFont.callout)
            .foregroundStyle(theme.colors.textSecondary)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// "Weekdays · Weekends", and which nights that is.
    private var nightsChoice: some View {
        VStack(spacing: theme.spacing.xxs) {
            SegmentedCapsule(selection: $nights, options: [.weekday, .weekend], size: .regular) {
                $0 == .weekday ? "Weekdays" : "Weekends"
            }
            .accessibilityLabel(Text("Nights"))
            Text(RestCopy.nights(nights, calendar: calendar))
                .font(MapleFont.footnote)
                .foregroundStyle(theme.colors.textSecondary)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
        }
    }

    /// Bedtime → wake-up, side by side, or stacked when large text needs the room.
    private var times: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: theme.spacing.xs) {
                choice(.bedtime)
                arrow
                choice(.wake)
            }
            VStack(spacing: theme.spacing.xs) {
                choice(.bedtime)
                choice(.wake)
            }
        }
    }

    private var arrow: some View {
        Text(verbatim: "→")
            .font(MapleFont.sectionTitle)
            .foregroundStyle(theme.colors.textSecondary)
            .accessibilityHidden(true)
    }

    private func choice(_ edge: Edge) -> some View {
        let selected = editing == edge
        let time = edge == .bedtime ? shown.wrappedValue.bedtime : shown.wrappedValue.wake
        let label = edge == .bedtime ? "Bedtime" : "Wake-up"
        return Button {
            editing = edge
        } label: {
            VStack(spacing: theme.spacing.xxs) {
                Text(label)
                    .font(MapleFont.footnote)
                    .foregroundStyle(theme.colors.textSecondary)
                ScheduleClock(time: time, emphasised: selected)
            }
            .padding(.vertical, theme.spacing.sm)
            .padding(.horizontal, theme.spacing.md)
            .frame(minWidth: 144)
            .background {
                let shape = RoundedRectangle(cornerRadius: theme.radius.tile, style: .continuous)
                if selected {
                    shape.fill(theme.colors.surface2)
                        .overlay { shape.strokeBorder(selectedHairline, lineWidth: 1) }
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: theme.radius.tile, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(HomeFormat.clock(time, locale: locale))")
        .accessibilityHint("Shows it on the wheel")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .mapleAnimation(theme.motion.gentle, value: selected)
    }

    /// The selected chip's top-lit white 14% hairline, as on segment thumbs.
    private var selectedHairline: LinearGradient {
        LinearGradient(
            stops: [.init(color: .white.opacity(0.14), location: 0), .init(color: .white.opacity(0), location: 0.4)],
            startPoint: .top, endPoint: .bottom
        )
    }

    private var wheel: some View {
        ClockWheel(
            label: editing == .bedtime ? "Bedtime" : "Wake-up time",
            time: Binding(
                get: { editing == .bedtime ? shown.wrappedValue.bedtime : shown.wrappedValue.wake },
                set: { time in
                    if editing == .bedtime { shown.wrappedValue.bedtime = time } else { shown.wrappedValue.wake = time }
                }
            )
        )
    }

    private var windDownChoice: some View {
        VStack(spacing: theme.spacing.xs) {
            Text("Wind-down")
                .font(MapleFont.footnote)
                .foregroundStyle(theme.colors.textSecondary)
            SegmentedCapsule(selection: shown.windDownMinutes, options: Self.windDownChoices, size: .regular) {
                HomeFormat.duration(minutes: $0)
            }
            .accessibilityLabel("Wind-down length")
            Text("From \(HomeFormat.clock(shown.wrappedValue.windDownStart, locale: locale))")
                .font(MapleFont.footnote)
                .monospacedDigit()
                .foregroundStyle(theme.colors.textSecondary)
                .contentTransition(.numericText())
        }
    }
}

/// A clock time at the statistic size: "23:00", or "11:00" with a smaller " PM".
private struct ScheduleClock: View {
    @Environment(\.theme) private var theme
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .title) private var size: CGFloat = 34
    let time: ClockTime
    let emphasised: Bool

    var body: some View {
        let colour = emphasised ? theme.colors.textPrimary : theme.colors.textSecondary
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            ForEach(Array(HomeFormat.clockParts(time, locale: locale).enumerated()), id: \.offset) { _, part in
                Text(part.text)
                    .font(part.isUnit ? MapleFont.numeralUnit(size: size / 2) : MapleFont.numeral(size: size))
                    .foregroundStyle(colour)
                    .contentTransition(.numericText())
            }
        }
        // Never shrinks: when the pair is too wide for the screen, `times` stacks it instead, so both times
        // always share one size.
        .lineLimit(1)
        .fixedSize()
    }
}
