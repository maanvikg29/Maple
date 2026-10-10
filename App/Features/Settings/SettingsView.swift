import SwiftUI
import UIKit
import MapleCore
import MapleDesign
import MapleServices

/// Settings (spec §8.7): hemisphere, sleep goal and the reveal sound, as one Level-1 group, then the reminders.
/// Every change saves at once through `AppSettings`; the hemisphere moves the seasons (and the tree) straight away.
///
/// Reminders: the wind-down nudge and the quiet morning check-in, each a toggle through `Reminders`. Turning one on
/// before iOS has asked shows the reminder primer first; once iOS has said no, it opens Maple's page in the Settings
/// app instead, and a row says why the toggles are off.
///
/// The sleep goal only decides Full nights, which need sleep-stage data from Apple Health; until those leaves can
/// be earned on this iPhone the row is absent (spec §1.5: a feature appears only when it has real state).
struct SettingsView: View {
    @Environment(\.theme) private var theme
    @Environment(\.mapleClock) private var clock
    @Environment(AppSettings.self) private var settings
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL
    @Environment(CollectionStore.self) private var collection
    @Environment(ScheduleStore.self) private var schedule
    @Environment(Reminders.self) private var reminders
    @State private var reminderPrimer: ReminderPrimerRequest?

    var body: some View {
        @Bindable var settings = settings
        ProfilePage("Settings") {
            ProfileListGroup {
                ProfileSettingRow("Hemisphere", detail: Text(hemisphereDetail), stacked: true, controlIsLabelled: false) {
                    HemispherePicker(selection: $settings.hemisphere)
                }
                if collection.availability(of: .fullNights) == .available {
                    ProfileSettingRow("Sleep goal", detail: Text("A full night is this much sleep, or within 30 minutes of it.")) {
                        SleepGoalStepper()
                    }
                }
                ProfileSettingRow("Reveal sound", detail: Text("A soft chime as a new leaf opens.")) {
                    ProfileToggle("Reveal sound", isOn: $settings.revealSound)
                }
            }
            ProfileListGroup {
                ProfileSettingRow("Wind-down reminder", detail: Text(windDownDetail)) {
                    ProfileToggle("Wind-down reminder", isOn: reminderToggle(.windDown))
                }
                ProfileSettingRow("Morning check-in", detail: Text(morningDetail)) {
                    ProfileToggle("Morning check-in", isOn: reminderToggle(.morning))
                }
                if reminders.isDenied {
                    ProfileSettingRow(
                        "Notifications are off",
                        detail: Text("Maple can send reminders once notifications are allowed in the Settings app."),
                        link: TextLink("Open Settings", action: openSystemSettings), controlIsLabelled: false
                    ) {
                        EmptyView()
                    }
                }
            }
        }
        .sheet(item: $reminderPrimer) { request in
            ReminderPrimerSheet(enabling: request.enabling)
        }
    }

    /// "At 22:15, when your wind-down starts."
    private var windDownDetail: String {
        "At \(HomeFormat.clock(schedule.schedule.windDownStart, locale: locale)), when your wind-down starts."
    }

    /// "A quiet note at 07:30, half an hour after you wake."
    private var morningDetail: String {
        "A quiet note at \(HomeFormat.clock(ReminderPlan.morningTime(for: schedule.schedule), locale: locale)), half an hour after you wake."
    }

    /// On only while wanted and allowed. Turning one on that iOS hasn't been asked about shows the primer; one iOS
    /// has refused opens the Settings app.
    private func reminderToggle(_ kind: ReminderKind) -> Binding<Bool> {
        Binding {
            reminders.isOn(kind)
        } set: { isOn in
            Task {
                guard await !reminders.set(kind, on: isOn) else { return }
                if reminders.isDenied {
                    openSystemSettings()
                } else {
                    reminderPrimer = ReminderPrimerRequest(enabling: kind)
                }
            }
        }
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }

    /// "Northern, from your region. It's autumn now." / "It's spring now in the southern hemisphere."
    private var hemisphereDetail: String {
        let hemisphere = settings.resolvedHemisphere
        let season = Season(for: clock.now(), hemisphere: hemisphere).rawValue
        if settings.hemisphere == .automatic {
            return "\(hemisphere.rawValue.capitalized), from your region. It's \(season) now."
        }
        return "It's \(season) now in the \(hemisphere.rawValue) hemisphere."
    }
}

/// Automatic, Northern, Southern as a segmented capsule; at accessibility text sizes, where three segments can't
/// hold their words, as chips that wrap.
private struct HemispherePicker: View {
    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var selection: HemisphereChoice

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            ChipFlow(spacing: theme.spacing.xs, lineSpacing: 0) {
                ForEach(HemisphereChoice.allCases, id: \.self) { choice in
                    Chip(choice.displayName, isSelected: selection == choice) { selection = choice }
                }
            }
        } else {
            SegmentedCapsule(selection: $selection, options: HemisphereChoice.allCases, fillsWidth: true) {
                $0.displayName
            }
        }
    }
}

/// Minus and plus icon circles around the goal ("7h 30m"), in 30-minute steps from 5 to 10 hours. VoiceOver
/// treats it as one adjustable element.
private struct SleepGoalStepper: View {
    @Environment(\.theme) private var theme
    @Environment(\.locale) private var locale
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let minutes = settings.sleepGoalMinutes
        HStack(spacing: 0) {
            Button("Shorter", systemImage: "minus") { settings.decreaseSleepGoal() }
                .buttonStyle(.iconCircle)
                .disabled(!settings.canDecreaseSleepGoal)
            Text(HomeFormat.duration(minutes: minutes))
                .font(MapleFont.headline.monospacedDigit())
                .foregroundStyle(theme.colors.textPrimary)
                .contentTransition(.numericText())
                .mapleAnimation(theme.motion.gentle, value: minutes)
                .frame(minWidth: 72)
                .lineLimit(1)
            Button("Longer", systemImage: "plus") { settings.increaseSleepGoal() }
                .buttonStyle(.iconCircle)
                .disabled(!settings.canIncreaseSleepGoal)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleep goal")
        .accessibilityValue(HomeFormat.spokenDuration(minutes: minutes, locale: locale))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: settings.increaseSleepGoal()
            case .decrement: settings.decreaseSleepGoal()
            @unknown default: break
            }
        }
    }
}
