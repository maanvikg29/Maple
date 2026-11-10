import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// The Focus streak (F1 design §5.15), from Home's header: the current run in amber beside its leaf, the best run and
/// the rest-day rule, then this week as 7 dots from the calendar's first weekday (ruling P8). Finished days are season
/// tint; rest days and misses look alike, in a neutral fill; today is an open ring until it ends. It never counts the
/// rest days left. `.medium`; `.large` at accessibility sizes.
struct StreakSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.mapleClock) private var clock
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(CollectionStore.self) private var collection
    @ScaledMetric(relativeTo: .title) private var numeralSize: CGFloat = 34
    @ScaledMetric(relativeTo: .title) private var leafSize: CGFloat = 36
    @ScaledMetric(relativeTo: .body) private var dotSize: CGFloat = 20

    var body: some View {
        // Home's own clock, so the sheet and the header agree; once a minute, so today turns over while it is open.
        TimelineView(.everyMinute) { timeline in
            let now = clock.date(forTimeline: timeline.date)
            page(week(at: now), current: collection.currentRun(at: now))
        }
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium])
        .presentationBackground(theme.colors.surface2)
        .presentationDragIndicator(.visible)
    }

    private func week(at now: Date) -> StreakWeek {
        let context = collection.context
        return StreakWeek(
            focusDays: collection.focus.focusDays, today: collection.snapshot.focusWindow(at: now, context: context).day,
            calendar: context.calendar, current: collection.currentRun(at: now), best: collection.focus.bestRun
        )
    }

    private func page(_ week: StreakWeek, current: Int) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: theme.spacing.sm) {
                    StreakLeaf(detailed: true)
                        .frame(width: min(leafSize, 56), height: min(leafSize, 56))
                    Text(week.title)
                        .font(MapleFont.numeral(size: min(numeralSize, 56)))
                        .foregroundStyle(theme.colors.reward)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(HomeSpeech.streak(days: current))
                .accessibilityAddTraits(.isHeader)
                VStack(spacing: theme.spacing.xxs) {
                    ForEach(Array(week.lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(MapleFont.callout)
                            .foregroundStyle(theme.colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, theme.spacing.sm)
                dots(week)
                    .padding(.top, theme.spacing.lg)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, theme.spacing.listMargin)
            .padding(.top, theme.spacing.xl)
            .padding(.bottom, theme.spacing.lg)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    /// The week: one dot per day with its weekday initial, and one sentence for VoiceOver.
    private func dots(_ week: StreakWeek) -> some View {
        let initials = FocusSheetCopy.weekdayInitials(calendar: collection.context.calendar)
        // Seven dots and their gaps fit a phone's width at every text size.
        let size = min(dotSize, 32)
        return HStack(spacing: 0) {
            ForEach(Array(week.dots.enumerated()), id: \.offset) { index, dot in
                VStack(spacing: theme.spacing.xxs) {
                    StreakDot(dot: dot)
                        .frame(width: size, height: size)
                    Text(initials.indices.contains(index) ? initials[index] : "")
                        .font(MapleFont.micro)
                        .foregroundStyle(dot == .pending ? theme.colors.textPrimary : theme.colors.textSecondary)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(week.weekLabel)
    }
}

/// One day of the week: finished in season tint, rest days and misses alike in a neutral fill, today an open ring.
private struct StreakDot: View {
    @Environment(\.theme) private var theme
    @Environment(\.season) private var season
    let dot: StreakWeek.Dot

    var body: some View {
        switch dot {
        case .finished: Circle().fill(theme.colors.seasonTint(season))
        case .neutral: Circle().fill(theme.colors.track)
        case .pending: Circle().strokeBorder(theme.colors.textSecondary, lineWidth: 1.5)
        }
    }
}
