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
    /// The page's measured parts, from which the dial's size is fitted (`HeroFit`).
    @State private var measured = RestMeasurements()

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.everyMinute) { context in
                screen(now: clock.date(forTimeline: context.date), visibleHeight: proxy.size.height)
            }
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

    /// The dial yields size at large text sizes so the times, "Edit schedule" and the capsule stay above the
    /// floating tab bar; when even the smallest dial leaves no room, the capsule is pinned above the tab bar.
    private func screen(now: Date, visibleHeight: CGFloat) -> some View {
        let action = windDownAction(at: now)
        let fit = HeroFit(
            preferred: SleepDial.diameter, minimum: Self.minimumDial, visible: visibleHeight,
            content: measured.content(gaps: theme.spacing.lg + theme.spacing.xl),
            // The slot is kept without an action, so the dial never changes size between phases.
            action: (measured.slot ?? HeroFit.estimatedActionHeight) + capsuleBottomGap - HeroFit.minimumBottomGap
        )
        return ScrollView {
            // Once the capsule is pinned, the page keeps its natural height from the top: filling the visible height
            // would hand the capsule's space to the gaps and push the times under the pinned bar.
            page(now: now, action: action, fit: fit)
                .frame(minHeight: fit.pageMinHeight(visible: visibleHeight))
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaBar(edge: .bottom) {
            if fit.pinsAction, let action {
                capsuleSlot(action)
                    .padding(.horizontal, theme.spacing.homeMargin)
                    .padding(.top, theme.spacing.sm)
                    .padding(.bottom, HeroFit.minimumBottomGap)
            }
        }
    }

    private func page(now: Date, action: NowState.Action?, fit: HeroFit) -> some View {
        let current = schedule.schedule
        let calendar = collection.context.calendar
        let dial = fit.heroHeight
        return VStack(spacing: 0) {
            header
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measured.header = $0 }
            Spacer(minLength: theme.spacing.lg)
            SleepDial(schedule: current, now: HomeFormat.clockTime(of: now, calendar: calendar))
                .scaleEffect(dial / SleepDial.diameter)
                .frame(width: dial, height: dial)
            details(current)
                // Always at its natural height, so squeezing the page can never feed back into the dial's size.
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measured.details = $0 }
            Spacer(minLength: theme.spacing.xl)
            if !fit.pinsAction {
                capsuleSlot(action)
                    .padding(.bottom, capsuleBottomGap)
            }
        }
        .padding(.horizontal, theme.spacing.homeMargin)
        .mapleAnimation(theme.motion.gentle, value: action)
        .mapleAnimation(theme.motion.gentle, value: current)
    }

    /// "23:00 → 07:00", "8h in bed" and "Edit schedule".
    private func details(_ current: SleepSchedule) -> some View {
        VStack(spacing: 0) {
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
        }
    }

    /// The capsule's slot is kept, at the capsule's own height for the text size, when there is no action, so the
    /// dial never shifts between phases.
    private func capsuleSlot(_ action: NowState.Action?) -> some View {
        ZStack {
            Button(NowState.Action.startWindDown.title) {}
                .buttonStyle(.moonlight(dimmed: true))
                .hidden()
                .accessibilityHidden(true)
            if let action {
                Button(action.title) { isWindingDown = true }
                    .buttonStyle(.moonlight(dimmed: true))
                    .transition(.opacity)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measured.slot = $0 }
    }

    /// Space under the primary capsule. The scroll content ends at the floating tab bar's top edge, and the capsule
    /// sits about where Home's does (30pt above the bar, §3.1), on the 4pt scale.
    private var capsuleBottomGap: CGFloat { theme.spacing.xl }

    /// The smallest the dial gets at the largest text sizes.
    private static let minimumDial: CGFloat = 180

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

/// Heights the Rest page measures; none depends on the dial's size, so fitting it settles in one pass.
private struct RestMeasurements: Equatable {
    var header: CGFloat?
    var details: CGFloat?
    /// The capsule's slot: the capsule's height at the current text size.
    var slot: CGFloat?

    /// Everything in the page besides the dial and the capsule: the header, the details and the spacers'
    /// minimums (`gaps`); nil until measured.
    func content(gaps: CGFloat) -> CGFloat? {
        guard let header, let details else { return nil }
        return header + details + gaps
    }
}

/// A leaf to reveal, as a full-screen cover item.
private struct RevealRequest: Identifiable {
    let id: String
}
