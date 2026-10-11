import SwiftUI
import UIKit
import MapleCore
import MapleDesign
import MapleServices

/// Keeps Maple's wind-down reminder in step with the member's day: reschedules
/// (`NotificationScheduler.reschedule(plan:)`) on every foreground and whenever the plan's inputs change (a schedule
/// save, the reminder switch, wind-down mode opening, iOS's permission answer, and a time-zone or clock change).
struct ReminderUpkeep: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.mapleClock) private var clock
    @Environment(\.locale) private var locale
    @Environment(NotificationScheduler.self) private var reminders
    @Environment(CollectionStore.self) private var collection
    @Environment(ScheduleStore.self) private var schedule
    @Environment(AppSettings.self) private var settings
    private let bedside = BedsideLog.shared

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
            settings: settings.reminders,
            windDownOpenedAt: bedside.session.startedAt, authorization: reminders.authorization
        )
    }

    private func reschedule() async {
        let plan = ReminderInputs.plan(
            collection: collection, schedule: schedule, settings: settings, bedside: bedside, now: clock.now(), locale: locale
        )
        await reminders.reschedule(plan: plan)
    }
}

/// What `ReminderPlan` is built from, compared to decide when to reschedule.
private struct ReminderInputsState: Equatable {
    var schedule: WeeklySleepSchedule
    var savedAt: Date?
    var nightSchedule: WeeklySleepSchedule
    var settings: ReminderSettings
    var windDownOpenedAt: Date?
    var authorization: ReminderAuthorization
}

extension View {
    /// Keeps the reminder scheduled (`ReminderUpkeep`). Apply it once, at the root.
    func reminderUpkeep() -> some View {
        modifier(ReminderUpkeep())
    }
}
