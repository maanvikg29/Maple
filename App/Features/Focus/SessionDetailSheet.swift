import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// One session, opened from History (F2 Study record).
///
/// - When it ran, and its timeline: locked time solid, time with apps not locked faint, a break as an outline, an
///   unlock as a gap.
/// - "Focused 48m · Saved 45m", then why time didn't count, in the receipt's words.
/// - "How did it go?", the subject and what it was for, all changeable afterwards.
/// - "Remove from History", which asks once in place. Leaves the session earned stay.
///
/// The session comes from the store's history, so a change shows as soon as the store has read the ledger again; a
/// session that is no longer there (removed) closes the sheet.
struct SessionDetailSheet: View {
    let sessionID: UUID

    @Environment(\.theme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(CollectionStore.self) private var collection
    @Environment(FocusSessionStore.self) private var sessions
    @Environment(SessionNotesStore.self) private var notes
    @Environment(SubjectStore.self) private var subjects

    @State private var isConfirmingRemoval = false
    @State private var picksSubject = false
    @State private var editsIntention = false

    var body: some View {
        Group {
            if let record = sessions.history?.record(sessionID), !record.isHidden {
                page(record)
            } else {
                Color.clear.onAppear { dismiss() }
            }
        }
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                theme.colors.background.opacity(0.78)
            }
        }
        .sheet(isPresented: $picksSubject) {
            SubjectSheet(selected: sessions.history?.record(sessionID)?.subjectID) { subject in
                Task { await sessions.setSubject(subject, for: sessionID) }
            }
        }
        .sheet(isPresented: $editsIntention) {
            IntentionEntry(intention: intention)
        }
    }

    private func page(_ record: SessionRecord) -> some View {
        let context = collection.context
        let model = SessionDetailModel(
            session: record, credit: sessions.history?.credit(sessionID), subject: subjects.name(for: record.subjectID),
            today: collection.snapshot.focusWindow(at: sessions.now, context: context).day, calendar: context.calendar, locale: locale
        )
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(model.title)
                    .font(MapleFont.sectionTitle)
                    .foregroundStyle(theme.colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(model.whenLine)
                    .font(MapleFont.footnote)
                    .foregroundStyle(theme.colors.textSecondary)
                    .padding(.top, theme.spacing.xxs)
                SessionTimeline(segments: model.segments)
                    .frame(height: 14)
                    .padding(.top, theme.spacing.md)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(model.timelineSpoken)
                legend(model.legend)
                    .padding(.top, theme.spacing.xs)
                Text(model.totalsLine)
                    .font(MapleFont.callout)
                    .foregroundStyle(theme.colors.textPrimary)
                    .padding(.top, theme.spacing.md)
                ForEach(model.reasons, id: \.self) { reason in
                    Text(reason)
                        .font(MapleFont.footnote)
                        .foregroundStyle(theme.colors.textSecondary)
                        .padding(.top, theme.spacing.xxs)
                }
                divider.padding(.top, theme.spacing.md)
                reflection(record.reflection)
                divider
                linkRow(SessionDetailModel.subjectTitle,
                        value: SubjectCopy.line(name: subjects.name(for: record.subjectID), hasSubjects: !subjects.active.isEmpty)) {
                    picksSubject = true
                }
                divider
                linkRow(SessionDetailModel.intentionTitle,
                        value: notes.intention(for: sessionID) ?? SessionDetailModel.addIntention) {
                    editsIntention = true
                }
                divider
                removal
                    .padding(.top, theme.spacing.sm)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, theme.spacing.homeMargin)
            .padding(.top, theme.spacing.xl)
            .padding(.bottom, theme.spacing.xl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .environment(\.theme, theme.onSheet)
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.colors.divider)
            .frame(height: theme.elevation.hairlineWidth)
    }

    /// The timeline's key: only the kinds this session has.
    private func legend(_ kinds: [SessionDetailModel.Segment.Kind]) -> some View {
        ChipFlow(spacing: theme.spacing.sm, lineSpacing: theme.spacing.xxs) {
            ForEach(kinds, id: \.self) { kind in
                HStack(spacing: 6) {
                    SessionTimeline(segments: [.init(from: 0, to: 1, kind: kind)])
                        .frame(width: 14, height: 8)
                    Text(kind.label)
                        .font(MapleFont.micro)
                        .foregroundStyle(theme.colors.textSecondary)
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// "How did it go?", changeable afterwards: the newest answer is the one kept.
    private func reflection(_ current: Reflection?) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            Text(SessionDetailModel.reflectionTitle)
                .font(MapleFont.footnote)
                .foregroundStyle(theme.colors.textSecondary)
            ChipFlow(spacing: theme.spacing.xs, lineSpacing: theme.spacing.xs) {
                ForEach(SessionDetailModel.reflections, id: \.reflection) { choice in
                    Chip(choice.title, isSelected: current == choice.reflection) {
                        Task { await sessions.reflect(choice.reflection, on: sessionID) }
                    }
                }
            }
        }
        .padding(.vertical, theme.spacing.sm)
        .accessibilityElement(children: .contain)
    }

    private func linkRow(_ title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: theme.spacing.sm) {
                Text(title)
                    .font(MapleFont.callout)
                    .foregroundStyle(theme.colors.textSecondary)
                Spacer(minLength: theme.spacing.sm)
                Text("\(value) ›")
                    .font(MapleFont.callout)
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
            .frame(minHeight: theme.spacing.minimumHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(value)")
    }

    /// "Remove from History", then the one question in its place.
    @ViewBuilder
    private var removal: some View {
        if isConfirmingRemoval {
            VStack(alignment: .leading, spacing: theme.spacing.xs) {
                Text(SessionDetailModel.removeQuestion)
                    .font(MapleFont.callout)
                    .foregroundStyle(theme.colors.textPrimary)
                Text(SessionDetailModel.removeBody)
                    .font(MapleFont.footnote)
                    .foregroundStyle(theme.colors.textSecondary)
                HStack(spacing: theme.spacing.sm) {
                    Button(SessionDetailModel.keep) { isConfirmingRemoval = false }
                        .buttonStyle(.glassCapsule(.compact))
                    Button(SessionDetailModel.removeConfirm) { remove() }
                        .buttonStyle(.glassCapsule(.compact))
                }
                .padding(.top, theme.spacing.xxs)
            }
        } else {
            TextLink(SessionDetailModel.removeTitle, chevron: false) { isConfirmingRemoval = true }
        }
    }

    private func remove() {
        Task {
            if await sessions.removeFromHistory(sessionID) { dismiss() }
        }
    }

    /// What the session was for, saved to `session-notes.json` as the entry sheet closes.
    private var intention: Binding<String?> {
        Binding(
            get: { notes.intention(for: sessionID) },
            set: { text in
                let at = sessions.history?.record(sessionID)?.started.placed ?? sessions.now
                notes.setIntention(text, for: sessionID, at: at)
            }
        )
    }
}

/// A session's timeline as one bar: locked time solid, time with apps not locked faint, a break as an outline, and an
/// unlock left empty.
struct SessionTimeline: View {
    @Environment(\.theme) private var theme
    let segments: [SessionDetailModel.Segment]

    var body: some View {
        let solid = theme.colors.textPrimary.opacity(0.7)
        let faint = theme.colors.textPrimary.opacity(0.22)
        Canvas { context, size in
            let gap: CGFloat = segments.count > 1 ? 2 : 0
            for segment in segments {
                let from = size.width * segment.from, to = size.width * segment.to
                let rect = CGRect(x: from + gap / 2, y: 0, width: max(1, to - from - gap), height: size.height)
                let shape = Path(roundedRect: rect, cornerRadius: min(4, rect.width / 2), style: .continuous)
                switch segment.kind {
                case .locked: context.fill(shape, with: .color(solid))
                case .open: context.fill(shape, with: .color(faint))
                case .breakTime:
                    let inner = Path(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), cornerRadius: min(4, rect.width / 2), style: .continuous)
                    context.stroke(inner, with: .color(solid), lineWidth: 1.5)
                case .unlocked:
                    let dash = Path { path in
                        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
                        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
                    }
                    context.stroke(dash, with: .color(faint), style: StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
                }
            }
        }
    }
}
