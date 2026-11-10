import SwiftUI
import UIKit
import MapleCore
import MapleDesign
import MapleServices

/// Keeps Maple's reminders in step with the member's day and their sessions (F1 design §6). It reschedules
/// (`NotificationScheduler.reschedule(plan:now:)`) on every foreground, and whenever the plan's inputs change:
/// - a schedule save, a reminder switch or the study time;
/// - wind-down mode opening, and iOS's permission answer;
/// - a session starting or ending, and the session store's first replay;
/// - a time-zone or clock change.
///
/// The plan runs on the session store's trusted time (`FocusSessionStore.now`), so a clock moved forward never drops a
/// session's end. Nothing is rescheduled until the store's first replay: before it, the store doesn't know whether a
/// session runs, and a plan without one would remove a pending end notification.
struct ReminderUpkeep: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    @Environment(NotificationScheduler.self) private var reminders
    @Environment(CollectionStore.self) private var collection
    @Environment(ScheduleStore.self) private var schedule
    @Environment(AppSettings.self) private var settings
    @Environment(FocusSessionStore.self) private var sessions
    private let bedside = BedsideLog.shared

    #if DEBUG
    @Environment(NotificationRouter.self) private var notifications
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
            .task {
                await ReminderDemo.postIfRequested(
                    reminders: reminders, schedule: schedule, collection: collection, sessions: sessions, locale: locale
                )
            }
            .task { await ReminderDemo.tapIfRequested(notifications: notifications, sessions: sessions) }
            .fullScreenCover(isPresented: $showsDemoStep) {
                NotificationsPrimerStep { showsDemoStep = false }
            }
            #endif
    }

    /// Everything the plan reads, so a change to any of it reschedules.
    private var inputs: ReminderInputsState {
        ReminderInputsState(
            schedule: schedule.weekly, savedAt: schedule.savedAt, nightSchedule: collection.schedule,
            settings: settings.reminders, windDownOpenedAt: bedside.session.startedAt, authorization: reminders.authorization,
            ledgerReadable: sessions.isLedgerReadable, runningSession: sessions.reminderSession,
            lastSessionStart: sessions.lastSessionStart
        )
    }

    private func reschedule() async {
        // Nil until the session store's first replay (`ReminderInputs.plan(…sessions:…)`).
        guard let plan = ReminderInputs.plan(
            collection: collection, schedule: schedule, settings: settings, windDownOpenedAt: bedside.session.startedAt,
            sessions: sessions, locale: locale
        ) else { return }
        await reminders.reschedule(plan: plan, now: sessions.now)
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
    /// The session store has replayed its ledger: the first replay schedules the first plan.
    var ledgerReadable: Bool
    var runningSession: ReminderPlan.RunningSession?
    var lastSessionStart: Date?
}

extension View {
    /// Keeps the reminders scheduled (`ReminderUpkeep`). Apply it once, at the root.
    func reminderUpkeep() -> some View {
        modifier(ReminderUpkeep())
    }
}
