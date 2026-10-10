// Rest › Sleep's presentational pieces (docs/design/spec.md §8.1): the sleep dial through the day, the schedule
// span, the editor's time fields and wind-down mode's bedside clock, on the real #05070D background.
//
//   SIMULATOR="Maple Sim 2" Scripts/snapshot-ios.sh Scripts/snapshot/RestScenes.swift [output-dir] [filter]
//   Scripts/snapshot.sh Scripts/snapshot/RestScenes.swift [output-dir]       (macOS: Mac type sizes)
//
// The screens themselves (header, primary, editor sheet, wind-down cover) live in the app; screenshot those in the
// simulator with the launch arguments in docs/debug-launch-arguments.md. Compiled together with MapleCore +
// MapleDesign; not part of the app.
import Foundation
import SwiftUI

@MainActor
func snapshotScenes() -> [SnapshotScene] {
    let standard = SleepSchedule.standard
    let late = SleepSchedule(bedtime: ClockTime(hour: 0, minute: 30), wake: ClockTime(hour: 8, minute: 30), windDownMinutes: 60)
    let early = SleepSchedule(bedtime: ClockTime(hour: 21, minute: 45), wake: ClockTime(hour: 5, minute: 45), windDownMinutes: 30)
    let h24 = Locale(identifier: "en_GB")
    let h12 = Locale(identifier: "en_US")

    var scenes: [SnapshotScene] = []
    // The moon walks the ring through the five phases of the standard schedule.
    let moments: [(String, ClockTime)] = [
        ("morning", ClockTime(hour: 7, minute: 30)),
        ("day", ClockTime(hour: 14, minute: 0)),
        ("evening", ClockTime(hour: 20, minute: 55)),
        ("winddown", ClockTime(hour: 22, minute: 22)),
        ("night", ClockTime(hour: 1, minute: 30)),
    ]
    for (name, now) in moments {
        scenes.append(SnapshotScene("rest-page-\(name)") {
            RestPagePreview(schedule: standard, now: now, showsPrimary: name == "evening" || name == "winddown")
                .environment(\.locale, h24)
        })
    }
    scenes += [
        SnapshotScene("rest-page-late-12h") {
            RestPagePreview(schedule: late, now: ClockTime(hour: 23, minute: 50), showsPrimary: true)
                .environment(\.locale, h12)
        },
        SnapshotScene("rest-page-early-summer") {
            RestPagePreview(schedule: early, now: ClockTime(hour: 4, minute: 10), showsPrimary: false)
                .environment(\.locale, h24).environment(\.season, .summer)
        },
        SnapshotScene("rest-page-ax3") {
            RestPagePreview(schedule: standard, now: ClockTime(hour: 20, minute: 55), showsPrimary: true)
                .environment(\.locale, h12).environment(\.dynamicTypeSize, .accessibility3)
        },
        SnapshotScene("rest-page-contrast") {
            RestPagePreview(schedule: standard, now: ClockTime(hour: 20, minute: 55), showsPrimary: true)
                .environment(\.locale, h24).environment(\.theme, .mapleIncreasedContrast)
        },
        SnapshotScene("rest-dial-seasons", size: CGSize(width: 640, height: 640)) {
            Grid(horizontalSpacing: 20, verticalSpacing: 20) {
                GridRow {
                    SleepDial(schedule: standard, now: ClockTime(hour: 22, minute: 30)).environment(\.season, .spring)
                    SleepDial(schedule: standard, now: ClockTime(hour: 22, minute: 30)).environment(\.season, .summer)
                }
                GridRow {
                    SleepDial(schedule: standard, now: ClockTime(hour: 22, minute: 30)).environment(\.season, .autumn)
                    SleepDial(schedule: standard, now: ClockTime(hour: 22, minute: 30)).environment(\.season, .winter)
                }
            }
            .environment(\.locale, h24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.maple.colors.background)
        },
        SnapshotScene("rest-editor-fields", size: CGSize(width: 402, height: 420)) {
            EditorPreview(schedule: late)
                .environment(\.locale, h12)
        },
        SnapshotScene("rest-editor-fields-ax3", size: CGSize(width: 402, height: 640)) {
            EditorPreview(schedule: late)
                .environment(\.locale, h12).environment(\.dynamicTypeSize, .accessibility3)
        },
        SnapshotScene("rest-bedside") {
            BedsidePreview(time: ClockTime(hour: 22, minute: 22), line: "38m until bed", goodnight: false)
                .environment(\.locale, h24)
        },
        SnapshotScene("rest-bedside-goodnight") {
            BedsidePreview(time: ClockTime(hour: 23, minute: 4), line: "Phone down at 11:04 PM", goodnight: true)
                .environment(\.locale, h12)
        },
    ]
    return scenes
}

// MARK: - Page compositions (review only; the app's RestView and WindDownView are the real screens)

/// The Rest tab's layout at 402 × 874: status bar 0–62, the 44pt "Rest" header, the dial and its numbers, the
/// primary above a stand-in for the floating tab bar.
private struct RestPagePreview: View {
    let schedule: SleepSchedule
    let now: ClockTime
    let showsPrimary: Bool

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 62)
            Text("Rest")
                .font(MapleFont.screenTitle)
                .foregroundStyle(theme.colors.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            Spacer(minLength: 24)
            SleepDial(schedule: schedule, now: now)
            SleepScheduleSpan(schedule)
                .padding(.top, 28)
            Text(RestCopy.inBed(schedule))
                .font(MapleFont.callout)
                .foregroundStyle(theme.colors.textSecondary)
                .padding(.top, 4)
            TextLink("Edit schedule") {}
                .padding(.top, 4)
            Spacer(minLength: 32)
            Group {
                if showsPrimary {
                    Button("Start wind-down") {}.buttonStyle(.moonlight(dimmed: true))
                } else {
                    Color.clear
                }
            }
            .frame(height: 52)
            // 32pt above the floating tab bar (y 791–853 on an iPhone 17), as in the app.
            Color.clear.frame(height: 32 + 62 + 21)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.background)
        .environment(\.drawsGlassAsSolid, true)
    }
}

private struct EditorPreview: View {
    let schedule: SleepSchedule
    @State private var minutes = 60
    @Environment(\.theme) private var theme
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Sleep schedule")
                .font(MapleFont.sectionTitle)
                .foregroundStyle(theme.colors.textPrimary)
                .frame(minHeight: 44)
            HStack(spacing: 12) {
                ScheduleTimeField("Bedtime", time: schedule.bedtime, isSelected: true) {}
                ScheduleTimeField("Wake-up", time: schedule.wake, isSelected: false) {}
            }
            .padding(.top, 16)
            HStack {
                Text("Wind-down")
                    .font(MapleFont.headline)
                    .foregroundStyle(theme.colors.textPrimary)
                Spacer()
                SegmentedCapsule(selection: $minutes, options: [30, 45, 60], size: .regular) {
                    RestCopy.windDownOption(minutes: $0)
                }
                // As in the app's editor: on a surface2 sheet the thumb lifts with white.
                .environment(\.theme, {
                    var sheet = theme
                    sheet.colors.surface2 = .white.opacity(0.12)
                    return sheet
                }())
            }
            .padding(.top, 24)
            Text(RestCopy.editorSummary(schedule, locale: locale))
                .font(MapleFont.footnote)
                .foregroundStyle(theme.colors.textSecondary)
                .padding(.top, 4)
            Spacer(minLength: 24)
            Button("Save") {}.buttonStyle(.moonlight)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.colors.surface2)
        .environment(\.drawsGlassAsSolid, true)
    }
}

private struct BedsidePreview: View {
    let time: ClockTime
    let line: String
    let goodnight: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Close", systemImage: "xmark") {}.buttonStyle(.iconCircle)
                Spacer()
            }
            .padding(.top, 62)
            Spacer()
            BedsideClock(time: time, line: line)
            Spacer()
            Spacer()
            Group {
                if goodnight { Color.clear } else { Button("Goodnight") {}.buttonStyle(.moonlight(dimmed: true)) }
            }
            .frame(height: 52)
            .padding(.bottom, 34 + 24)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.background)
        .environment(\.drawsGlassAsSolid, true)
    }
}
