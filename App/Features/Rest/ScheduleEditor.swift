import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// The schedule editor sheet (spec §8.1), opened by "Edit schedule" on Rest › Sleep.
///
/// - At the top, a 36pt `SegmentedCapsule` chooses which nights the times below are for: "Every day" (one
///   schedule, every night), "Weekdays" or "Weekends". A quiet line under it names those nights from the member's
///   calendar ("Friday and Saturday nights"), so a Friday–Saturday weekend reads right too. One control with three
///   plain words keeps the sheet to a single decision: it is both the switch (Every day, or a separate weekend) and
///   the tab for the weekend times, with no extra toggle row.
/// - At `.medium` it shows the two times side by side, the wind-down length (30m, 45m or 1h) and Save.
/// - Tapping a time opens its wheel underneath and lifts the sheet to `.large`; tapping it again closes it.
/// - Weekend times start as a copy of the weekday ones the first time Weekends is chosen. Saving on Every day saves
///   one schedule for every night (the weekend draft is kept until the sheet closes, so switching back restores it).
/// - Save goes through `ScheduleStore.save(_:at:)`, which applies the schedule everywhere at once and from the next
///   night for the ledger. The first save ever also plants the maple: it unlocks the First-steps leaf, which `onSave`
///   hands back for the reveal.
struct ScheduleEditor: View {
    enum Field: Hashable {
        case bedtime, wake
    }

    /// Which nights the times are for.
    enum Nights: Hashable, CaseIterable {
        case everyNight, weekdays, weekends

        var title: String {
            switch self {
            case .everyNight: "Every day"
            case .weekdays: "Weekdays"
            case .weekends: "Weekends"
            }
        }

        /// The segment the editor opens on: Every day for one schedule, otherwise tonight's nights.
        static func opening(_ schedule: WeeklySleepSchedule, tonight: WeeklySleepSchedule.Variant) -> Nights {
            guard schedule.differsOnWeekends else { return .everyNight }
            return tonight == .weekend ? .weekends : .weekdays
        }
    }

    /// Wind-down lengths on offer, in minutes.
    static let windDownChoices = [30, 45, 60]

    @Environment(\.theme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.mapleClock) private var clock
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ScheduleStore.self) private var store
    @Environment(CollectionStore.self) private var collection

    @State private var weekday: SleepSchedule
    @State private var weekend: SleepSchedule
    @State private var nights: Nights
    /// The weekend times are the member's own (saved before, or edited here), not a copy of the weekday ones.
    @State private var weekendIsOwn: Bool
    @State private var editing: Field?
    @Binding private var detent: PresentationDetent
    private let onSave: ([LeafUnlock]) -> Void

    /// - Parameters:
    ///   - schedule: The weekly schedule to start from.
    ///   - nights: The segment to open on (`Nights.opening(_:tonight:)`).
    ///   - editing: A time whose picker starts open.
    ///   - detent: The sheet's detent; the editor lifts it to `.large` while a picker is open.
    ///   - onSave: Called with the leaves the save unlocked (the First-steps leaf on the very first save).
    init(
        schedule: WeeklySleepSchedule, nights: Nights, editing: Field? = nil, detent: Binding<PresentationDetent>,
        onSave: @escaping ([LeafUnlock]) -> Void
    ) {
        var weekday = schedule.weekday
        weekday.windDownMinutes = Self.nearestChoice(to: weekday.windDownMinutes)
        var weekend = schedule.weekend ?? weekday
        weekend.windDownMinutes = Self.nearestChoice(to: weekend.windDownMinutes)
        _weekday = State(initialValue: weekday)
        _weekend = State(initialValue: weekend)
        _weekendIsOwn = State(initialValue: schedule.differsOnWeekends)
        _nights = State(initialValue: nights)
        _editing = State(initialValue: editing)
        _detent = detent
        self.onSave = onSave
    }

    /// The schedule Save would store.
    private var result: WeeklySleepSchedule {
        nights == .everyNight ? .everyNight(weekday) : WeeklySleepSchedule(weekday: weekday, weekend: weekend)
    }

    /// The times on screen: the weekend's on Weekends, otherwise the weekday (every-night) ones.
    private var draft: Binding<SleepSchedule> {
        Binding {
            nights == .weekends ? weekend : weekday
        } set: { value in
            if nights == .weekends {
                weekend = value
                weekendIsOwn = true
            } else {
                weekday = value
            }
        }
    }

    private var canSave: Bool {
        result.weekday.minutesInBed > 0 && result.schedule(for: .weekend).minutesInBed > 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                nightsChoice
                    .padding(.top, theme.spacing.md)
                fields
                    .padding(.top, theme.spacing.md)
                if let editing {
                    picker(for: editing)
                        .padding(.top, theme.spacing.xs)
                        .transition(.opacity)
                }
                windDown
                    .padding(.top, theme.spacing.lg)
                Text(summary)
                    .font(MapleFont.footnote)
                    .foregroundStyle(theme.colors.textSecondary)
                    .padding(.top, theme.spacing.xs)
                    .contentTransition(.opacity)
            }
            .padding(.horizontal, theme.spacing.listMargin)
            .padding(.top, theme.spacing.lg)
            .padding(.bottom, theme.spacing.lg)
            .mapleAnimation(theme.motion.gentle, value: editing)
            .mapleAnimation(theme.motion.gentle, value: draft.wrappedValue)
            .mapleAnimation(theme.motion.gentle, value: nights)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaBar(edge: .bottom) {
            Button("Save", action: save)
                .buttonStyle(.moonlight(dimmed: isQuietHours))
                .disabled(!canSave)
                .padding(.horizontal, theme.spacing.listMargin)
                .padding(.top, theme.spacing.xs)
                .padding(.bottom, theme.spacing.xs)
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationBackground(theme.colors.surface2)
        .onAppear {
            // At accessibility sizes the two times alone fill a medium sheet, so it opens tall.
            if dynamicTypeSize.isAccessibilitySize { detent = .large }
        }
        .onChange(of: nights) {
            // The first visit to Weekends starts from the weekday times.
            if nights == .weekends, !weekendIsOwn { weekend = weekday }
        }
    }

    // MARK: Parts

    private var header: some View {
        HStack(alignment: .center, spacing: theme.spacing.sm) {
            Text("Sleep schedule")
                .font(MapleFont.sectionTitle)
                .foregroundStyle(theme.colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button("Close", systemImage: "xmark") { dismiss() }
                .buttonStyle(.iconCircle)
        }
        // The close circle's 44pt hit area overhangs the margin, so the glyph lines up with the content edge.
        .padding(.trailing, -4)
    }

    /// "Every day · Weekdays · Weekends", and which nights that is.
    private var nightsChoice: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xxs) {
            SegmentedCapsule(selection: $nights, options: Nights.allCases, size: .regular, fillsWidth: true) { $0.title }
                .accessibilityLabel(Text("Nights"))
                .environment(\.theme, sheetTheme)
            Text(nightsLine)
                .font(MapleFont.footnote)
                .foregroundStyle(theme.colors.textSecondary)
                .contentTransition(.opacity)
        }
    }

    private var nightsLine: String {
        let calendar = collection.context.calendar
        switch nights {
        case .everyNight: return store.weekly.differsOnWeekends ? "Weekends will use these times too" : "The same every night"
        case .weekdays: return RestCopy.nights(.weekday, calendar: calendar)
        case .weekends: return RestCopy.nights(.weekend, calendar: calendar)
        }
    }

    private var fields: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: theme.spacing.sm))
            : AnyLayout(HStackLayout(spacing: theme.spacing.sm))
        let shown = draft.wrappedValue
        return layout {
            ScheduleTimeField("Bedtime", time: shown.bedtime, isSelected: editing == .bedtime) { toggle(.bedtime) }
            ScheduleTimeField("Wake-up", time: shown.wake, isSelected: editing == .wake) { toggle(.wake) }
        }
    }

    private func picker(for field: Field) -> some View {
        DatePicker(
            field == .bedtime ? "Bedtime" : "Wake-up",
            selection: binding(for: field),
            displayedComponents: .hourAndMinute
        )
        .datePickerStyle(.wheel)
        .labelsHidden()
        .frame(maxWidth: .infinity)
        // One wheel at a time: switching fields swaps the wheel instead of scrolling it.
        .id(field)
    }

    private var windDown: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: theme.spacing.sm) {
                windDownTitle
                Spacer(minLength: 0)
                windDownChoices
            }
            VStack(alignment: .leading, spacing: theme.spacing.xs) {
                windDownTitle
                windDownChoices
            }
        }
    }

    private var windDownTitle: some View {
        Text("Wind-down")
            .font(MapleFont.headline)
            .foregroundStyle(theme.colors.textPrimary)
    }

    private var windDownChoices: some View {
        SegmentedCapsule(selection: draft.windDownMinutes, options: Self.windDownChoices, size: .regular) { minutes in
            RestCopy.windDownOption(minutes: minutes)
        }
        .accessibilityLabel(Text("Wind-down length"))
        .environment(\.theme, sheetTheme)
    }

    /// The segment thumb is `surface2`, which is also the sheet's own fill, so on the sheet it would vanish. Here
    /// it lifts with white instead, the same way the time tiles do.
    private var sheetTheme: Theme {
        var sheet = theme
        sheet.colors.surface2 = .white.opacity(0.12)
        return sheet
    }

    private var summary: String {
        let shown = draft.wrappedValue
        return shown.minutesInBed == 0 ? "Bedtime and wake-up need to differ" : RestCopy.editorSummary(shown, locale: locale)
    }

    /// The primary capsule's dimmed variant from the evening on (D11).
    private var isQuietHours: Bool {
        switch collection.phase(at: clock.now()) {
        case .evening, .windDown, .night: true
        case .morning, .day: false
        }
    }

    // MARK: Actions

    private func toggle(_ field: Field) {
        let opening = editing != field
        editing = opening ? field : nil
        detent = opening || dynamicTypeSize.isAccessibilitySize ? .large : .medium
    }

    private func save() {
        let schedule = result
        let unchanged = store.hasSavedSchedule && schedule == store.weekly
        let unlocked = unchanged ? [] : store.save(schedule, at: clock.now())
        onSave(unlocked)
        dismiss()
    }

    // MARK: Times ↔ dates

    /// The wheel edits a date; only its hour and minute matter. A fixed reference day keeps daylight-saving
    /// changes out of it.
    private func binding(for field: Field) -> Binding<Date> {
        let calendar = collection.context.calendar
        return Binding {
            Self.date(for: field == .bedtime ? draft.wrappedValue.bedtime : draft.wrappedValue.wake, calendar: calendar)
        } set: { date in
            let time = HomeFormat.clockTime(of: date, calendar: calendar)
            switch field {
            case .bedtime: draft.wrappedValue.bedtime = time
            case .wake: draft.wrappedValue.wake = time
            }
        }
    }

    private static func date(for time: ClockTime, calendar: Calendar) -> Date {
        let reference = calendar.date(from: DateComponents(year: 2001, month: 1, day: 1)) ?? Date(timeIntervalSinceReferenceDate: 0)
        return calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: reference) ?? reference
    }

    static func nearestChoice(to minutes: Int) -> Int {
        windDownChoices.min { abs($0 - minutes) < abs($1 - minutes) } ?? 45
    }
}
