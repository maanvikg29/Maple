import SwiftUI
import UIKit
import MapleCore
import MapleDesign
import MapleServices

/// Settings › the wind-down reminder (spec §8.7) as a Level-1 group, saved at once through `AppSettings` and
/// rescheduled by `ReminderUpkeep`.
///
/// A switch shows on only when its reminder will really come: iOS must allow Maple's notifications. Until iOS has
/// been asked, a status line says nothing is sent, and "Allow reminders" (or turning a switch on) opens the
/// primer. Once the member has said no, the switches rest off and "Turn on in Settings" opens Maple's notification
/// settings in the Settings app.
struct RemindersSettingsGroup: View {
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(AppSettings.self) private var settings
    @Environment(NotificationScheduler.self) private var reminders
    @State private var showsPrimer = false

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            ProfileListGroup {
                ProfileSettingRow("Wind-down reminder", detail: Text("As wind-down begins, with your bedtime.")) {
                    ProfileToggle("Wind-down reminder", isOn: binding(\.windDownReminder))
                }
            }
            .disabled(reminders.authorization == .denied)
            status
        }
        // The page puts 24pt above each group; groups sit 32pt apart (spec §1 rule 10).
        .padding(.top, theme.spacing.xs)
        .sheet(isPresented: $showsPrimer) { NotificationsPrimerSheet() }
        #if DEBUG
        .task {
            // `-MapleDemoNotifyPrimer sheet` opens the primer once the page has settled.
            guard ReminderDemo.showsPrimerSheet else { return }
            try? await Task.sleep(for: .seconds(1))
            showsPrimer = true
        }
        #endif
    }

    /// The line under the group, and its action, while reminders can't be sent.
    @ViewBuilder private var status: some View {
        switch reminders.authorization {
        case .allowed:
            EmptyView()
        case .notDetermined:
            statusLine("Maple sends nothing until you allow it.", link: TextLink("Allow reminders") { showsPrimer = true })
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
                    showsPrimer = true
                case .denied:
                    break
                }
            }
        )
    }
}
