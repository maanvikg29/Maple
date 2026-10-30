import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// Saved today (F1 design §5.9, focus spec §3.3): today's counted time, then each session's counted stretch with the
/// time beside it that didn't count, greyed, and why ("Unlocked 5 min", "After bedtime", "Over today's 6h",
/// "Couldn't confirm the block"), then how counting works. Opened from Home's numeral and the receipt's.
///
/// Today is the Maple day the member is still living in at the session store's trusted now (`livingDay`), so a receipt
/// finishing past bedtime opens the total it just showed, and each session's credit is the store's own
/// (`credit(for:)`), so caps and overlaps count as they do everywhere else. `.medium`, lifting to `.large`; `.large` at
/// accessibility sizes.
struct SavedTodaySheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(CollectionStore.self) private var collection
    @Environment(FocusSessionStore.self) private var sessions

    var body: some View {
        // Once a minute, so a running session's row keeps up between the store's 15-second refreshes.
        TimelineView(.everyMinute) { _ in
            page(model())
        }
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationBackground(theme.colors.surface2)
        .presentationDragIndicator(.visible)
    }

    private func model() -> SavedTodayModel {
        let now = sessions.now
        let today = collection.snapshot.livingDay(at: now, context: collection.context)
        let todays = sessions.sessions.filter { $0.plan.day == today }
        return SavedTodayModel(
            credits: todays.compactMap { sessions.credit(for: $0.id) }, sessions: todays, day: today, now: now,
            calendar: collection.context.calendar, locale: locale
        )
    }

    private func page(_ model: SavedTodayModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(SavedTodayModel.title)
                    .font(MapleFont.sectionTitle)
                    .foregroundStyle(theme.colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let empty = model.emptyLine {
                    Text(empty)
                        .font(MapleFont.body)
                        .foregroundStyle(theme.colors.textSecondary)
                        .padding(.top, theme.spacing.xs)
                } else {
                    // Crisp, never rolled: the roll animates a blur, and Focus motion is transform and opacity only (§4.6).
                    // A running session moves the total once a minute while the sheet is open.
                    StatNumber(model.total, size: .stat, accessibilityText: model.totalSpoken, rolls: false)
                        .padding(.top, theme.spacing.xs)
                    ProfileListGroup {
                        ForEach(model.rows) { row in
                            SavedTodayRow(title: row.title, reasons: row.reasons, spoken: row.spoken)
                        }
                    }
                    .padding(.top, theme.spacing.md)
                }
                Text(FocusSheetCopy.howWeCountTitle)
                    .font(MapleFont.headline)
                    .foregroundStyle(theme.colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, theme.spacing.lg)
                VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                    ForEach(SavedTodayModel.howWeCount, id: \.self) { line in
                        Text(line)
                            .font(MapleFont.footnote)
                            .foregroundStyle(theme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, theme.spacing.xxs)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, theme.spacing.listMargin)
            .padding(.top, theme.spacing.xl)
            .padding(.bottom, theme.spacing.lg)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// One session's counted stretch, with the time that didn't count under it in secondary, and why. One VoiceOver
/// element per session, read with its lengths in words (`SavedTodayModel.Row.spoken`).
private struct SavedTodayRow: View {
    @Environment(\.theme) private var theme
    let title: String
    let reasons: [String]
    let spoken: String

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xxs) {
            Text(title)
                .font(MapleFont.body)
                .foregroundStyle(theme.colors.textPrimary)
            ForEach(Array(reasons.enumerated()), id: \.offset) { _, reason in
                Text(reason)
                    .font(MapleFont.footnote)
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, theme.spacing.listMargin)
        .padding(.vertical, theme.spacing.sm)
        .frame(minHeight: theme.spacing.row)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}
