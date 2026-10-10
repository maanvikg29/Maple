import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// Settings (spec §8.7): hemisphere, sleep goal and the reveal sound, as one Level-1 group. Every change saves at
/// once through `AppSettings`; the hemisphere moves the seasons (and the tree) straight away.
///
/// The sleep goal only decides Full nights, which need sleep-stage data from Apple Health; until those leaves can
/// be earned on this iPhone the row is absent (spec §1.5: a feature appears only when it has real state).
struct SettingsView: View {
    @Environment(\.theme) private var theme
    @Environment(\.mapleClock) private var clock
    @Environment(AppSettings.self) private var settings
    @Environment(CollectionStore.self) private var collection

    var body: some View {
        @Bindable var settings = settings
        ProfilePage("Settings") {
            ProfileListGroup {
                ProfileSettingRow("Hemisphere", detail: Text(hemisphereDetail), stacked: true, controlIsLabelled: false) {
                    HemispherePicker(selection: $settings.hemisphere)
                }
                if collection.availability(of: .fullNights) == .available {
                    ProfileSettingRow("Sleep goal", detail: Text("A full night is at least this much sleep.")) {
                        SleepGoalStepper()
                    }
                }
                ProfileSettingRow("Reveal sound", detail: Text("A soft chime as a new leaf opens.")) {
                    ProfileToggle("Reveal sound", isOn: $settings.revealSound)
                }
            }
        }
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
