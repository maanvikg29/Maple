import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// The Rest tab (spec §8.1). Until Focus ships it is Sleep only, so there is no Sleep / Focus switch, and no
/// Level-1 rows: each row (sounds, wind-down apps, caffeine, alarm) appears only once its feature ships.
///
/// - A 44pt "Rest" header.
/// - The hero: `SleepDial`, with the moon at the current time.
/// - "23:00 → 07:00", "8h in bed" and "Edit schedule", which opens the schedule editor sheet.
/// - In the evening and wind-down only, the dimmed primary "Start wind-down" (or "Return to wind-down" while the
///   mode is on), which opens wind-down mode full screen.
struct RestView: View {
    @Environment(\.theme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.mapleClock) private var clock
    @Environment(ScheduleStore.self) private var schedule
    @Environment(CollectionStore.self) private var collection

    @State private var isEditing = Self.opensEditorOnLaunch
    @State private var editorDetent: PresentationDetent = Self.editorFieldOnLaunch == nil ? .medium : .large
    /// A time whose picker the editor opens with (DEBUG launches only).
    @State private var editorField = Self.editorFieldOnLaunch
    @State private var isWindingDown = false
    /// A leaf unlocked by the first schedule save, revealed once the editor has gone.
    @State private var unlockedBySave: String?
    @State private var reveal: RevealRequest?

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                TimelineView(.everyMinute) { context in
                    page(now: clock.date(forTimeline: context.date))
                }
                .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(theme.colors.background)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .sheet(isPresented: $isEditing, onDismiss: editorDismissed) {
            ScheduleEditor(schedule: schedule.schedule, editing: editorField, detent: $editorDetent) { unlocked in
                unlockedBySave = unlocked.first?.speciesID
            }
        }
        .fullScreenCover(isPresented: $isWindingDown) {
            WindDownView()
        }
        .fullScreenCover(item: $reveal) { request in
            RevealFlow(startingWith: request.id)
        }
    }

    // MARK: Page

    private func page(now: Date) -> some View {
        let current = schedule.schedule
        let calendar = collection.context.calendar
        let action = windDownAction(at: now)
        return VStack(spacing: 0) {
            header
            Spacer(minLength: theme.spacing.lg)
            SleepDial(schedule: current, now: HomeFormat.clockTime(of: now, calendar: calendar))
            SleepScheduleSpan(current)
                .padding(.top, 28)
            Text(RestCopy.inBed(current))
                .font(MapleFont.callout)
                .foregroundStyle(theme.colors.textSecondary)
                .padding(.top, theme.spacing.xxs)
                .accessibilityLabel(Text(RestCopy.spokenInBed(current, locale: locale)))
            TextLink(schedule.hasSavedSchedule ? "Edit schedule" : "Set your schedule") {
                editorDetent = .medium
                isEditing = true
            }
            .padding(.top, theme.spacing.xxs)
            Spacer(minLength: theme.spacing.xl)
            // The capsule's slot is kept when there is no action, so the dial never shifts between phases.
            ZStack {
                Color.clear.frame(height: 52)
                if let action {
                    Button(action.title) { isWindingDown = true }
                        .buttonStyle(.moonlight(dimmed: true))
                        .transition(.opacity)
                }
            }
            .padding(.bottom, capsuleBottomGap)
        }
        .padding(.horizontal, theme.spacing.homeMargin)
        .mapleAnimation(theme.motion.gentle, value: action)
        .mapleAnimation(theme.motion.gentle, value: current)
    }

    /// Space under the primary capsule. The scroll content ends at the floating tab bar's top edge, and the capsule
    /// sits about where Home's does (30pt above the bar, §3.1), on the 4pt scale.
    private var capsuleBottomGap: CGFloat { theme.spacing.xl }

    private var header: some View {
        Text("Rest")
            .font(MapleFont.screenTitle)
            .tracking(-0.3)
            .foregroundStyle(theme.colors.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    /// The primary, in the evening and wind-down only (§8.1).
    private func windDownAction(at now: Date) -> NowState.Action? {
        guard WindDownSession.offersWindDown(in: collection.phase(at: now)) else { return nil }
        let active = BedsideLog.shared.isWindDownActive(at: now, schedule: schedule.schedule, calendar: collection.context.calendar)
        return active ? .returnToWindDown : .startWindDown
    }

    private func editorDismissed() {
        editorField = nil
        guard let speciesID = unlockedBySave else { return }
        unlockedBySave = nil
        presentingRevealWithoutSlide { reveal = RevealRequest(id: speciesID) }
    }

    // MARK: DEBUG launch

    private static var opensEditorOnLaunch: Bool {
        #if DEBUG
        RestDemo.opensScheduleEditor
        #else
        false
        #endif
    }

    private static var editorFieldOnLaunch: ScheduleEditor.Field? {
        #if DEBUG
        RestDemo.openField
        #else
        nil
        #endif
    }
}

/// A leaf to reveal, as a full-screen cover item.
private struct RevealRequest: Identifiable {
    let id: String
}
