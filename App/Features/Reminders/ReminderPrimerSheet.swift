import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// The reminder primer (`ReminderPrimerView`), whose "Continue" shows Apple's notification prompt through
/// `Reminders`. Offered once on its own when the tabs first appear outside wind-down and night (`RootView`), and
/// from a Settings toggle while iOS hasn't asked yet. "Not now" leaves everything as it was. Present it with
/// `.sheet(item:)`; it brings its own detent and background.
struct ReminderPrimerSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @Environment(Reminders.self) private var reminders
    @Environment(ScheduleStore.self) private var schedule

    /// The reminder to turn on once allowed: the toggle the member came from, or nil for the wanted defaults.
    let enabling: ReminderKind?

    var body: some View {
        ReminderPrimerView(
            windDownStart: HomeFormat.clock(schedule.schedule.windDownStart, locale: locale),
            isAsking: reminders.isRequesting, onContinue: allow, onNotNow: { dismiss() }
        )
        .presentationDetents([.medium])
        .presentationBackground(theme.colors.surface2)
    }

    /// Apple's prompt over the primer; once the member answers it, the reminders are scheduled and the primer goes.
    private func allow() {
        guard !reminders.isRequesting else { return }
        Task {
            await reminders.requestAuthorization(enabling: enabling)
            dismiss()
        }
    }
}

/// A request to show the reminder primer.
struct ReminderPrimerRequest: Identifiable, Hashable {
    var enabling: ReminderKind?

    var id: String { "reminders.\(enabling?.rawValue ?? "")" }
}
