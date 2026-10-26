import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// The daily study reminder's time (F1 design §5.12, §6). A wheel kept to the times in the Day phase on every day of
/// the member's week (`StudyReminderWindow`), opening on the saved time or 16:00. "Save" turns the reminder on at that
/// time; closing the sheet changes nothing. It is a sheet over the Profile sheet, as the schedule editor is.
struct StudyReminderSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.mapleClock) private var clock
    @Environment(CollectionStore.self) private var collection
    @State private var time: ClockTime
    @State private var detent: PresentationDetent = .medium
    private let window: StudyReminderWindow
    private let onSave: (ClockTime) -> Void

    /// - Parameters:
    ///   - initial: The saved time, or `StudyReminderWindow.suggested`. A time outside the window moves to its nearest
    ///     edge.
    ///   - onSave: Called with the chosen time, just before the sheet closes.
    init(window: StudyReminderWindow, initial: ClockTime, onSave: @escaping (ClockTime) -> Void) {
        self.window = window
        self.onSave = onSave
        _time = State(initialValue: window.nearest(to: initial))
    }

    var body: some View {
        let calendar = collection.context.calendar
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                Text(FocusSettingsCopy.studyRange(window, locale: locale))
                    .font(MapleFont.footnote)
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, theme.spacing.xs)
                DatePicker(
                    FocusSettingsCopy.studyTitle, selection: selection(calendar),
                    in: Self.date(for: window.earliest, calendar: calendar)...Self.date(for: window.latest, calendar: calendar),
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                // The wheel reads the member's calendar, as the time it saves does.
                .environment(\.calendar, calendar)
                .environment(\.timeZone, calendar.timeZone)
                .frame(maxWidth: .infinity)
                .padding(.top, theme.spacing.sm)
            }
            .padding(.horizontal, theme.spacing.listMargin)
            .padding(.top, theme.spacing.lg)
            .padding(.bottom, theme.spacing.lg)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaBar(edge: .bottom) {
            Button(FocusSettingsCopy.save) {
                onSave(time)
                dismiss()
            }
            .buttonStyle(.moonlight(dimmed: isQuietHours))
            .disabled(!window.contains(time))
            .padding(.horizontal, theme.spacing.listMargin)
            .padding(.top, theme.spacing.xs)
            .padding(.bottom, theme.spacing.xs)
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationBackground(theme.colors.surface2)
        .onAppear {
            // At accessibility sizes the wheel alone fills a medium sheet, so it opens tall.
            if dynamicTypeSize.isAccessibilitySize { detent = .large }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: theme.spacing.sm) {
            Text(FocusSettingsCopy.studyTitle)
                .font(MapleFont.sectionTitle)
                .foregroundStyle(theme.colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button(FocusSettingsCopy.close, systemImage: "xmark") { dismiss() }
                .buttonStyle(.iconCircle)
        }
        // The close circle's 44pt hit area overhangs the margin, so the glyph lines up with the content edge.
        .padding(.trailing, -4)
    }

    /// Evening, wind-down and night dim the primary, as they do everywhere (spec §7.3).
    private var isQuietHours: Bool {
        switch collection.phase(at: clock.now()) {
        case .evening, .windDown, .night: true
        case .morning, .day: false
        }
    }

    private func selection(_ calendar: Calendar) -> Binding<Date> {
        Binding {
            Self.date(for: time, calendar: calendar)
        } set: { date in
            time = window.nearest(to: HomeFormat.clockTime(of: date, calendar: calendar))
        }
    }

    /// `time` on a fixed reference day, for the wheel.
    private static func date(for time: ClockTime, calendar: Calendar) -> Date {
        let reference = calendar.date(from: DateComponents(year: 2001, month: 1, day: 1)) ?? Date(timeIntervalSinceReferenceDate: 0)
        return calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: reference) ?? reference
    }
}
