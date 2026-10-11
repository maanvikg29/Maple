import SwiftUI
import UIKit
import MapleCore
import MapleDesign
import MapleServices

/// Keeps Maple's two reminders in step with the member's day, and opens what a reminder tap asks for.
///
/// Reschedules (`NotificationScheduler.reschedule(plan:)`) on every foreground and whenever the plan's inputs
/// change: a schedule save, a leaf earned or opened (reveals opening and closing), a reminder switch, wind-down
/// mode opening, iOS's permission answer, and a time-zone or clock change. A tap on "A new leaf is waiting" opens
/// the reveal over whatever is showing, once the first leaf is on the maple and something can be opened now;
/// otherwise the tap just opens the app.
struct ReminderUpkeep: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.mapleClock) private var clock
    @Environment(\.locale) private var locale
    @Environment(NotificationScheduler.self) private var reminders
    @Environment(CollectionStore.self) private var collection
    @Environment(ScheduleStore.self) private var schedule
    @Environment(AppSettings.self) private var settings
    private let bedside = BedsideLog.shared

    @State private var showsReveal = false
    #if DEBUG
    @State private var showsDemoStep = ReminderDemo.showsPrimerStep
    #endif

    func body(content: Content) -> some View {
        content
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                await reminders.refreshAuthorization()
                await reschedule()
            }
            .onChange(of: inputs) {
                Task { await reschedule() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                Task { await reschedule() }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                Task { await reschedule() }
            }
            .onChange(of: reminders.pendingRoute, initial: true) {
                guard let route = reminders.takeRoute() else { return }
                open(route)
            }
            .fullScreenCover(isPresented: $showsReveal) { RevealFlow() }
            #if DEBUG
            .task { await ReminderDemo.postIfRequested(reminders: reminders, schedule: schedule, collection: collection, locale: locale) }
            .fullScreenCover(isPresented: $showsDemoStep) {
                NotificationsPrimerStep { showsDemoStep = false }
            }
            #endif
    }

    /// Everything the plan reads, so a change to any of it reschedules.
    private var inputs: ReminderInputsState {
        ReminderInputsState(
            schedule: schedule.weekly, savedAt: schedule.savedAt, nightSchedule: collection.schedule,
            waiting: collection.waiting.map(\.speciesID), settings: settings.reminders,
            windDownOpenedAt: bedside.session.startedAt, authorization: reminders.authorization
        )
    }

    private func reschedule() async {
        let plan = ReminderInputs.plan(
            collection: collection, schedule: schedule, settings: settings, bedside: bedside, now: clock.now(), locale: locale
        )
        await reminders.reschedule(plan: plan)
    }

    private func open(_ route: ReminderRoute) {
        switch route {
        case .reveal:
            // Never over the first run, and only when a leaf can be opened now (never in wind-down or at night).
            guard collection.hasPlacedFirstLeaf, !collection.revealable(at: clock.now()).isEmpty, !showsReveal else { return }
            presentingRevealWithoutSlide { showsReveal = true }
        }
    }
}

/// What `ReminderPlan` is built from, compared to decide when to reschedule.
private struct ReminderInputsState: Equatable {
    var schedule: WeeklySleepSchedule
    var savedAt: Date?
    var nightSchedule: WeeklySleepSchedule
    var waiting: [String]
    var settings: ReminderSettings
    var windDownOpenedAt: Date?
    var authorization: ReminderAuthorization
}

extension View {
    /// Keeps the reminders scheduled and routes reminder taps (`ReminderUpkeep`). Apply it once, at the root,
    /// inside the theme and season environment so the reveal it opens is styled like every other.
    func reminderUpkeep() -> some View {
        modifier(ReminderUpkeep())
    }
}
