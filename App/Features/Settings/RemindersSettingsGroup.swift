import SwiftUI
import UIKit
import MapleCore
import MapleDesign
import MapleServices

/// Settings › reminders (spec §8.7, F1 design §5.12 and §6) as one Level-1 group, saved at once through `AppSettings`
/// and rescheduled by `ReminderUpkeep`: wind-down and, once Focus ships, a session's end and the daily study reminder.
///
/// A switch shows on only when its reminder will really come: iOS must allow Maple's notifications. Until iOS has
/// been asked, a status line says nothing is sent, and "Allow reminders" (or turning a switch on) opens the
/// primer. Once the member has said no, the switches rest off and "Turn on in Settings" opens Maple's notification
/// settings in the Settings app.
///
/// Turning the study reminder on opens its time first (16:00 suggested), kept to the Day phase on every day of the
/// member's week (`StudyReminderWindow`); closing that sheet leaves it off. Before iOS has been asked, the primer
/// follows a saved time.
struct RemindersSettingsGroup: View {
    @Environment(\.theme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.mapleClock) private var clock
    @Environment(AppSettings.self) private var settings
    @Environment(NotificationScheduler.self) private var reminders
    @Environment(CollectionStore.self) private var collection
    @Environment(ScheduleStore.self) private var schedule
    @State private var sheet: RemindersSheet?
    /// A study time saved before iOS was asked: the primer opens once the time sheet has gone.
    @State private var primerFollows = false

    var body: some View {
        let window = studyWindow
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            ProfileListGroup {
                ProfileSettingRow("Wind-down reminder", detail: Text("As wind-down begins, with your bedtime.")) {
                    ProfileToggle("Wind-down reminder", isOn: binding(\.windDownReminder))
                }
                if collection.context.features.focus {
                    ProfileSettingRow(FocusSettingsCopy.sessionEndTitle, detail: Text(FocusSettingsCopy.sessionEndDetail)) {
                        ProfileToggle(FocusSettingsCopy.sessionEndTitle, isOn: binding(\.sessionEndReminder))
                    }
                    ProfileSettingRow(FocusSettingsCopy.studyTitle, detail: Text(studyDetail(window)), link: studyLink(window)) {
                        ProfileToggle(FocusSettingsCopy.studyTitle, isOn: studyBinding(window))
                            // Nothing to turn on while the schedule leaves no daytime; a saved time can still go.
                            .disabled(window == nil && settings.studyReminderTime == nil)
                    }
                }
            }
            .disabled(reminders.authorization == .denied)
            status
        }
        // The page puts 24pt above each group; groups sit 32pt apart (spec §1 rule 10).
        .padding(.top, theme.spacing.xs)
        .sheet(item: $sheet, onDismiss: sheetDismissed) { sheet in
            switch sheet {
            case .primer:
                NotificationsPrimerSheet()
            case .studyTime(let window):
                StudyReminderSheet(window: window, initial: settings.studyReminderTime ?? StudyReminderWindow.suggested) { time in
                    settings.studyReminderTime = time
                }
            }
        }
        #if DEBUG
        .task { await openForDemo() }
        #endif
    }

    /// The line under the group, and its action, while reminders can't be sent.
    @ViewBuilder private var status: some View {
        switch reminders.authorization {
        case .allowed:
            EmptyView()
        case .notDetermined:
            statusLine("Maple sends nothing until you allow it.", link: TextLink("Allow reminders") { sheet = .primer })
        case .denied:
            statusLine("Maple's notifications are off in the Settings app.", link: TextLink("Turn on in Settings") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
            })
        }
    }

    private func statusLine(_ text: String, link: TextLink) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(text)
                .font(MapleFont.footnote)
                .foregroundStyle(theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            // The link's 44pt hit area overlaps the line's spacing rather than adding to it, as in a setting row.
            link
                .padding(.top, dynamicTypeSize.isAccessibilitySize ? 0 : -theme.spacing.xs)
        }
        .padding(.horizontal, theme.spacing.listMargin)
    }

    /// On when the member wants it and iOS allows it. Turning one on before iOS has been asked opens the primer.
    private func binding(_ key: ReferenceWritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { reminders.isAllowed && settings[keyPath: key] },
            set: { isOn in
                switch reminders.authorization {
                case .allowed:
                    settings[keyPath: key] = isOn
                case .notDetermined:
                    guard isOn else { return }
                    settings[keyPath: key] = true
                    sheet = .primer
                case .denied:
                    break
                }
            }
        )
    }

    // MARK: The daily study reminder

    /// The times the study reminder can be set to this week; nil when the schedule leaves no daytime.
    private var studyWindow: StudyReminderWindow? {
        StudyReminderWindow(weekly: schedule.weekly, around: clock.now(), calendar: collection.context.calendar)
    }

    private func studyDetail(_ window: StudyReminderWindow?) -> String {
        guard let window else { return FocusSettingsCopy.studyNoDaytime }
        guard let time = settings.studyReminderTime else { return FocusSettingsCopy.studyOff }
        return window.contains(time)
            ? FocusSettingsCopy.studyOn(time, locale: locale)
            : FocusSettingsCopy.studyOutsideDay(time, window: window, locale: locale)
    }

    /// "Change time", once a time is saved.
    private func studyLink(_ window: StudyReminderWindow?) -> TextLink? {
        guard let window, settings.studyReminderTime != nil, reminders.authorization != .denied else { return nil }
        return TextLink(FocusSettingsCopy.studyChangeTime) { sheet = .studyTime(window) }
    }

    /// On when a time is saved and iOS allows it. Turning it on opens the time sheet, whose "Save" turns it on; turning
    /// it off forgets the time.
    private func studyBinding(_ window: StudyReminderWindow?) -> Binding<Bool> {
        Binding(
            get: { reminders.isAllowed && settings.studyReminderTime != nil },
            set: { isOn in
                guard isOn else {
                    settings.studyReminderTime = nil
                    return
                }
                guard let window else { return }
                switch reminders.authorization {
                case .allowed:
                    sheet = .studyTime(window)
                case .notDetermined:
                    primerFollows = true
                    sheet = .studyTime(window)
                case .denied:
                    break
                }
            }
        )
    }

    /// After the time sheet: the primer, when a time was saved before iOS was asked.
    private func sheetDismissed() {
        guard primerFollows else { return }
        primerFollows = false
        if settings.studyReminderTime != nil, reminders.authorization == .notDetermined { sheet = .primer }
    }

    #if DEBUG
    /// `-MapleDemoStudyReminder`, then `-MapleDemoNotifyPrimer sheet` or `-MapleDemoSettingsOpen studyTime` once the
    /// page has settled.
    private func openForDemo() async {
        if let time = SettingsDemo.studyReminder { settings.studyReminderTime = time }
        let opensTime = SettingsDemo.opening == .studyTime && collection.context.features.focus
        guard ReminderDemo.showsPrimerSheet || opensTime else { return }
        try? await Task.sleep(for: .seconds(1))
        if ReminderDemo.showsPrimerSheet {
            sheet = .primer
        } else if let window = studyWindow {
            sheet = .studyTime(window)
        }
    }
    #endif
}

/// What opens over Settings' reminders.
private enum RemindersSheet: Identifiable, Hashable {
    /// "A gentle reminder", with iOS's prompt behind it.
    case primer
    /// The daily study reminder's time.
    case studyTime(StudyReminderWindow)

    var id: String {
        switch self {
        case .primer: "primer"
        case .studyTime: "studyTime"
        }
    }
}
