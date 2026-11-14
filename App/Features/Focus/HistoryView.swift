import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// History (F2 Study record), pushed from the Focus tab's "History ›" and from "focused this week ›".
///
/// - A Week / Month switch, with arrows to step back and forward. The week starts on the calendar's first weekday, as
///   the streak's does.
/// - One numeral: time focused. Under it, time saved and sessions finished, when there are any.
/// - One bar a day, white at 70%, with a season-tint dot over a day a session finished in. Tapping a bar scrolls to
///   that day's sessions.
/// - "By subject": tapping a row filters the sessions to it; tapping it again clears the filter.
/// - Sessions by day, newest first. A row opens the session's detail (`SessionDetailSheet`).
///
/// Every word is `HistoryPage`'s. The whole ledger is read as the page opens, and again when a session ends
/// (`FocusSessionStore.loadHistory()`); nothing is drawn under the header until it has been read.
struct HistoryView: View {
    @Environment(\.theme) private var theme
    @Environment(\.season) private var season
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(CollectionStore.self) private var collection
    @Environment(FocusSessionStore.self) private var sessions
    @Environment(SessionNotesStore.self) private var notes
    @Environment(SubjectStore.self) private var subjects

    @State private var span: HistoryPeriod.Span = .week
    /// Periods back from the one being lived in: 0, -1, -2…
    @State private var shift = 0
    @State private var filter: HistoryPage.SubjectKey?
    @State private var detail: SessionID?
    @ScaledMetric(relativeTo: .body) private var ringSize: CGFloat = 18

    private struct SessionID: Identifiable, Hashable {
        let id: UUID
    }

    var body: some View {
        // Once a minute, so "Today" and the week turn over while the page is open.
        TimelineView(.everyMinute) { _ in
            let now = sessions.now
            let context = collection.context
            let today = collection.snapshot.focusWindow(at: now, context: context).day
            VStack(spacing: 0) {
                topBar
                if let history = sessions.history {
                    let period = HistoryPeriod(span, containing: today, calendar: context.calendar)
                        .shifted(by: shift, calendar: context.calendar)
                    content(HistoryPage(
                        sessions: history.sessions, period: period, today: today, subjects: subjects.list, intentions: intentions,
                        filter: filter, calendar: context.calendar, locale: locale
                    ), isFirstRun: history.sessions.isEmpty)
                } else {
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { FocusSky().ignoresSafeArea() }
        .background(theme.colors.background)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .sheet(item: $detail) { SessionDetailSheet(sessionID: $0.id) }
        // The whole ledger: as the page opens, and again once a session ends or starts.
        .task(id: reloadKey) { await sessions.loadHistory() }
        .onChange(of: span) {
            shift = 0
        }
        #if DEBUG
        .task { await openDemoDetail() }
        #endif
    }

    private var reloadKey: String {
        "\(sessions.lastEnded?.id.uuidString ?? "")|\(sessions.running?.id.uuidString ?? "")"
    }

    /// Each session's intention, from `session-notes.json`.
    private var intentions: [UUID: String] {
        notes.notes.reduce(into: [:]) { result, entry in
            if let id = UUID(uuidString: entry.key) { result[id] = entry.value.text }
        }
    }

    // MARK: Header

    private var topBar: some View {
        HStack(spacing: theme.spacing.sm) {
            Button("Back", systemImage: "chevron.left") { dismiss() }
                .buttonStyle(.iconCircle)
            Text(HistoryPage.screenTitle)
                .font(MapleFont.screenTitle)
                .tracking(-0.3)
                .foregroundStyle(theme.colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, theme.spacing.homeMargin - 4)
        .frame(minHeight: 44)
    }

    // MARK: Page

    private func content(_ page: HistoryPage, isFirstRun: Bool) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    SegmentedCapsule(selection: $span, options: HistoryPeriod.Span.allCases, size: .regular, fillsWidth: true) {
                        $0 == .week ? "Week" : "Month"
                    }
                    stepper(page)
                        .padding(.top, theme.spacing.md)
                    totals(page)
                        .padding(.top, theme.spacing.sm)
                    bars(page) { day in
                        withAnimation(theme.motion.press) { proxy.scrollTo(day, anchor: .top) }
                    }
                    .padding(.top, theme.spacing.lg)
                    if !page.subjects.isEmpty {
                        bySubject(page)
                            .padding(.top, theme.spacing.sectionGap)
                    }
                    if let empty = page.emptyLine {
                        emptyState(empty, isFirstRun: isFirstRun)
                            .padding(.top, theme.spacing.groupGap)
                    }
                    ForEach(page.groups) { group in
                        dayGroup(group)
                            .padding(.top, theme.spacing.sectionGap)
                            .id(group.day)
                    }
                }
                .padding(.horizontal, theme.spacing.homeMargin)
                .padding(.top, theme.spacing.sm)
                // Clear of the floating tab bar.
                .padding(.bottom, theme.spacing.hero + theme.spacing.xl)
            }
            .scrollIndicators(.hidden)
            // Rows fade out under the header instead of being cut by it.
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: theme.spacing.md)
                    Color.black
                }
                .ignoresSafeArea(edges: .bottom)
            }
        }
    }

    /// ‹ This week ›: one period at a time, never past the first session or the present.
    private func stepper(_ page: HistoryPage) -> some View {
        HStack(spacing: theme.spacing.xs) {
            stepButton("Earlier", systemImage: "chevron.left", enabled: page.canGoBack) { shift -= 1 }
            Text(page.title)
                .font(MapleFont.headline)
                .foregroundStyle(theme.colors.textPrimary)
                .frame(maxWidth: .infinity)
                .contentTransition(.opacity)
            stepButton("Later", systemImage: "chevron.right", enabled: page.canGoForward) { shift = min(0, shift + 1) }
        }
    }

    private func stepButton(_ title: String, systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(enabled ? theme.colors.textPrimary : theme.colors.textTertiary)
            .frame(width: theme.spacing.minimumHitTarget, height: theme.spacing.minimumHitTarget)
            .contentShape(Rectangle())
            .disabled(!enabled)
    }

    private func totals(_ page: HistoryPage) -> some View {
        VStack(spacing: theme.spacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: theme.spacing.xs) {
                StatNumber(page.numeral, size: .score, accessibilityText: page.numeralSpoken, rolls: false)
                Text(page.caption)
                    .font(MapleFont.callout)
                    .foregroundStyle(theme.colors.textSecondary)
                    .accessibilityHidden(true)
            }
            if let saved = page.savedLine {
                Text(saved)
                    .font(MapleFont.footnote)
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    // MARK: Bars

    private func bars(_ page: HistoryPage, onTap: @escaping (LocalDay) -> Void) -> some View {
        let isWeek = page.bars.count <= 7
        let height: CGFloat = 96
        return HStack(alignment: .bottom, spacing: isWeek ? theme.spacing.sm : 3) {
            ForEach(page.bars) { bar in
                let share = page.peakSeconds > 0 ? CGFloat(bar.seconds) / CGFloat(page.peakSeconds) : 0
                VStack(spacing: theme.spacing.xxs) {
                    Circle()
                        .fill(bar.hasFinished ? theme.colors.seasonTint(season) : .clear)
                        .frame(width: isWeek ? 5 : 3, height: isWeek ? 5 : 3)
                    RoundedRectangle(cornerRadius: isWeek ? 5 : 2, style: .continuous)
                        .fill(bar.seconds > 0 ? theme.colors.textPrimary.opacity(0.7) : theme.colors.track)
                        .frame(maxWidth: isWeek ? 24 : .infinity)
                        .frame(height: bar.seconds > 0 ? max(4, share * height) : 2)
                    Text(barLabel(bar, isWeek: isWeek))
                        .font(MapleFont.micro)
                        .foregroundStyle(theme.colors.textSecondary)
                        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(height: 14)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .contentShape(Rectangle())
                .onTapGesture { if bar.seconds > 0 { onTap(bar.day) } }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(bar.spoken)
            }
        }
        .frame(height: height + 14 + 5 + theme.spacing.xxs * 2)
        .accessibilityElement(children: .contain)
    }

    /// Every weekday's initial in a week; in a month, the 1st and every 7th date after it.
    private func barLabel(_ bar: HistoryPage.Bar, isWeek: Bool) -> String {
        isWeek || (bar.day.day - 1) % 7 == 0 ? bar.label : ""
    }

    // MARK: By subject

    private func bySubject(_ page: HistoryPage) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            sectionTitle(HistoryPage.bySubjectTitle)
            ForEach(page.subjects) { row in
                Button { filter = row.isSelected ? nil : row.key } label: {
                    VStack(spacing: 6) {
                        HStack(spacing: theme.spacing.sm) {
                            Text(row.name)
                                .font(MapleFont.callout)
                                .foregroundStyle(row.isPast ? theme.colors.textSecondary : theme.colors.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: theme.spacing.sm)
                            if row.isSelected {
                                Image(systemName: "line.3.horizontal.decrease")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(theme.colors.textSecondary)
                                    .accessibilityHidden(true)
                            }
                            Text(row.time)
                                .font(MapleFont.callout.monospacedDigit())
                                .foregroundStyle(theme.colors.textSecondary)
                        }
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(theme.colors.track)
                                Capsule()
                                    .fill(theme.colors.textPrimary.opacity(row.isPast ? 0.35 : 0.7))
                                    .frame(width: max(3, proxy.size.width * row.share))
                            }
                        }
                        .frame(height: 3)
                    }
                    .frame(minHeight: theme.spacing.minimumHitTarget)
                    .contentShape(Rectangle())
                    // With a filter on, the other rows step back.
                    .opacity(filter == nil || row.isSelected ? 1 : 0.5)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(row.name), \(row.time)")
                .accessibilityAddTraits(row.isSelected ? .isSelected : [])
                .accessibilityHint(row.isSelected ? "Shows every session again" : "Shows only these sessions")
            }
        }
    }

    // MARK: Sessions

    private func dayGroup(_ group: HistoryPage.DayGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle(group.title)
                .padding(.bottom, theme.spacing.xxs)
            ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Rectangle()
                        .fill(theme.colors.divider)
                        .frame(height: theme.elevation.hairlineWidth)
                }
                Button { detail = SessionID(id: row.id) } label: { sessionRow(row) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(row.spoken)
            }
        }
    }

    private func sessionRow(_ row: HistoryPage.SessionRow) -> some View {
        HStack(alignment: .top, spacing: theme.spacing.sm) {
            SessionRing(isFull: row.ranToEnd)
                .frame(width: min(ringSize, 28), height: min(ringSize, 28))
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(MapleFont.callout)
                    .foregroundStyle(theme.colors.textPrimary)
                Text([row.time, row.note].compactMap { $0 }.joined(separator: " · "))
                    .font(MapleFont.footnote)
                    .foregroundStyle(theme.colors.textSecondary)
                if let intention = row.intention {
                    Text(intention)
                        .font(MapleFont.footnote)
                        .foregroundStyle(theme.colors.textSecondary)
                        .lineLimit(2)
                }
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: theme.spacing.sm)
            Text(row.focused)
                .font(MapleFont.callout.monospacedDigit())
                .foregroundStyle(theme.colors.textPrimary)
        }
        .padding(.vertical, theme.spacing.sm)
        .frame(maxWidth: .infinity, minHeight: theme.spacing.minimumHitTarget, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(MapleFont.tileName)
            .foregroundStyle(theme.colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    private func emptyState(_ line: String, isFirstRun: Bool) -> some View {
        VStack(spacing: theme.spacing.sm) {
            Text(line)
                .font(MapleFont.callout)
                .foregroundStyle(theme.colors.textSecondary)
                .multilineTextAlignment(.center)
            if isFirstRun {
                TextLink("Start a session") { dismiss() }
            }
        }
        .frame(maxWidth: .infinity)
    }

    #if DEBUG
    /// `-MapleDemoPresent session`: the newest session's detail, once History has loaded.
    private func openDemoDetail() async {
        guard DemoLaunchOptions.current.focusSheet == .session else { return }
        await sessions.loadHistory()
        if let newest = sessions.history?.sessions.last { detail = SessionID(id: newest.id) }
    }
    #endif
}

/// A session's ring in History: whole for one that ran to its end, half for one ended early. Neutral: no colour says
/// good or bad.
struct SessionRing: View {
    @Environment(\.theme) private var theme
    let isFull: Bool

    var body: some View {
        ZStack {
            Circle().stroke(theme.colors.track, lineWidth: 2)
            Circle()
                .trim(from: 0, to: isFull ? 1 : 0.5)
                .stroke(theme.colors.textPrimary.opacity(0.7), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(1)
        .accessibilityHidden(true)
    }
}
