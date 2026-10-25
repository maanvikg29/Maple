import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// Settings (spec §8.7, F1 design §5.12): hemisphere, the sleep schedule, sleep goal and the reveal sound, as one
/// Level-1 group, then the reminders. Every change saves at once through `AppSettings`; the hemisphere moves the
/// seasons (and the tree) straight away.
///
/// "Sleep schedule" opens the schedule editor as a sheet over the Profile sheet. The schedule feeds the awake window
/// (R6), so it stays editable now that the Rest tab is retired (F1-3).
///
/// The sleep goal is the sleep need behind Full nights (7 to 9 hours, 7h 30m unless changed; rewards.json
/// `full_nights`), which Apple Health's importer judges every night (`CollectionContext.sleepNeedMinutes`).
struct SettingsView: View {
    @Environment(\.theme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.mapleClock) private var clock
    @Environment(AppSettings.self) private var settings
    @Environment(ScheduleStore.self) private var schedule
    @Environment(CollectionStore.self) private var collection
    @State private var editsSchedule = false
    @State private var editorDetent: PresentationDetent = .medium
    /// A time whose wheel the editor opens with (DEBUG launches only).
    @State private var editorField: ScheduleEditor.Field?
    /// The nights the editor opens on (DEBUG launches only; otherwise tonight's).
    @State private var editorNights: ScheduleEditor.Nights?

    var body: some View {
        @Bindable var settings = settings
        let tonight = schedule.tonight(at: clock.now())
        // Built here, so the editor opens with the time and nights set just before it: a sheet's content closure alone
        // can hold an older copy of them.
        let editor = scheduleEditor
        ProfilePage("Settings") {
            ProfileListGroup {
                ProfileSettingRow("Hemisphere", detail: Text(hemisphereDetail), stacked: true, controlIsLabelled: false) {
                    HemispherePicker(selection: $settings.hemisphere)
                }
                // "Sleep schedule · 23:00 → 07:00 ›"; the value hides at accessibility sizes (ProfileNavigationRow).
                Button {
                    editorDetent = .medium
                    editsSchedule = true
                } label: {
                    ProfileNavigationRow("Sleep schedule", value: RestCopy.span(tonight, locale: locale))
                }
                .buttonStyle(.profileRow)
                .accessibilityValue(Text(RestCopy.spokenSchedule(tonight, locale: locale)))
                ProfileSettingRow("Sleep goal", detail: Text("A full night is this much sleep, or within 30 minutes of it.")) {
                    SleepGoalStepper()
                }
                ProfileSettingRow("Reveal sound", detail: Text("A soft chime as a new leaf opens.")) {
                    ProfileToggle("Reveal sound", isOn: $settings.revealSound)
                }
            }
            // The wind-down and morning-leaf reminders, with iOS's permission (RemindersSettingsGroup).
            RemindersSettingsGroup()
        }
        // A sheet over the Profile sheet, as the reminders primer is (RemindersSettingsGroup).
        .sheet(isPresented: $editsSchedule, onDismiss: editorDismissed) {
            editor
        }
        #if DEBUG
        .task {
            // `-MapleDemoPresent schedule[:…]` (App/DemoPresenter.swift opens this page): the editor, once the page
            // has settled.
            guard let request = SleepDemo.takeScheduleEditor() else { return }
            try? await Task.sleep(for: .seconds(1))
            editorField = request.field
            editorNights = request.nights
            editorDetent = request.field == nil ? .medium : .large
            editsSchedule = true
        }
        #endif
    }

    /// The editor, opening on tonight's nights. Its `onSave` hands back the First-steps leaf only on the first schedule
    /// save ever, which onboarding makes. A first save made here (only a DEBUG demo of an unplanted collection) leaves
    /// that leaf waiting on Home, as "Open your new leaf".
    private var scheduleEditor: some View {
        let calendar = collection.context.calendar
        let tonight = WeeklySleepSchedule.variant(
            forNight: schedule.weekly.currentNight(at: clock.now(), calendar: calendar), calendar: calendar
        )
        return ScheduleEditor(
            schedule: schedule.weekly, nights: editorNights ?? .opening(schedule.weekly, tonight: tonight),
            editing: editorField, detent: $editorDetent
        ) { _ in }
    }

    private func editorDismissed() {
        editorField = nil
        editorNights = nil
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

/// Minus and plus icon circles around the goal ("7h 30m"), in 30-minute steps from 7 to 9 hours. VoiceOver
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
