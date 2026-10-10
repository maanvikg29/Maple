import SwiftUI
import MapleCore
import MapleDesign

/// The onboarding end's first step: one calm screen to set bedtime, wake-up and wind-down. Saving it earns the
/// First-steps leaf (the Sugar maple, "Set your sleep schedule"), which the next steps reveal (spec §8.8, D12).
///
/// The two times are the hero: tapping one selects it and the wheel below edits it.
struct SleepScheduleStep: View {
    /// Called with the schedule when the member taps "Save schedule".
    var onSave: (SleepSchedule) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    @State private var bedtime = SleepSchedule.standard.bedtime
    @State private var wake = SleepSchedule.standard.wake
    @State private var windDown = SleepSchedule.standard.windDownMinutes
    @State private var editing: Edge = .bedtime

    private enum Edge: Hashable {
        case bedtime, wake
    }

    static let windDownChoices = [30, 45, 60]

    private var schedule: SleepSchedule {
        SleepSchedule(bedtime: bedtime, wake: wake, windDownMinutes: windDown)
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: theme.spacing.xl)
                    header
                    times
                        .padding(.top, theme.spacing.xxl)
                    Text("\(HomeFormat.duration(minutes: schedule.minutesInBed)) in bed")
                        .font(MapleFont.callout)
                        .monospacedDigit()
                        .foregroundStyle(theme.colors.textSecondary)
                        .contentTransition(.numericText())
                        .padding(.top, theme.spacing.sm)
                        .accessibilityLabel("\(HomeFormat.spokenDuration(minutes: schedule.minutesInBed, locale: locale)) in bed")
                    wheel
                        .padding(.top, theme.spacing.xs)
                    windDownChoice
                        .padding(.top, theme.spacing.md)
                    Spacer(minLength: theme.spacing.xl)
                }
                .padding(.horizontal, theme.spacing.homeMargin)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button("Save schedule") { onSave(schedule) }
                .buttonStyle(.moonlight)
                .padding(.horizontal, theme.spacing.homeMargin)
                .padding(.top, theme.spacing.sm)
                .padding(.bottom, theme.spacing.md)
                .footerFade(theme.colors.background)
        }
        .sensoryFeedback(.selection, trigger: editing)
        .mapleAnimation(theme.motion.gentle, value: schedule)
    }

    // MARK: Parts

    private var header: some View {
        VStack(spacing: theme.spacing.xs) {
            Text("Your sleep schedule")
                .font(MapleFont.screenTitle)
                .foregroundStyle(theme.colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Saving it plants your maple.")
                .font(MapleFont.callout)
                .foregroundStyle(theme.colors.textSecondary)
        }
        .multilineTextAlignment(.center)
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
        let time = edge == .bedtime ? bedtime : wake
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
        DatePicker(
            editing == .bedtime ? "Bedtime" : "Wake-up time",
            selection: Binding(
                get: { date(for: editing == .bedtime ? bedtime : wake) },
                set: { newValue in
                    let time = HomeFormat.clockTime(of: newValue, calendar: calendar)
                    if editing == .bedtime { bedtime = time } else { wake = time }
                }
            ),
            displayedComponents: .hourAndMinute
        )
        .datePickerStyle(.wheel)
        .labelsHidden()
        .frame(maxWidth: 320)
    }

    private var windDownChoice: some View {
        VStack(spacing: theme.spacing.xs) {
            Text("Wind-down")
                .font(MapleFont.footnote)
                .foregroundStyle(theme.colors.textSecondary)
            SegmentedCapsule(selection: $windDown, options: Self.windDownChoices, size: .regular) {
                HomeFormat.duration(minutes: $0)
            }
            .accessibilityLabel("Wind-down length")
            Text("From \(HomeFormat.clock(schedule.windDownStart, locale: locale))")
                .font(MapleFont.footnote)
                .monospacedDigit()
                .foregroundStyle(theme.colors.textSecondary)
                .contentTransition(.numericText())
        }
    }

    private func date(for time: ClockTime) -> Date {
        let day = calendar.startOfDay(for: .now)
        return calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day) ?? day
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
