import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// "Allow reminders" from Settings: the calm primer (`NotificationsPrimerView`) as a `.medium` sheet on
/// `surface2`, whose "Allow reminders" shows iOS's prompt through `NotificationScheduler`. Once iOS answers, the
/// sheet goes and the reminders are scheduled (`ReminderUpkeep` sees the new answer); "Not now" changes nothing.
struct NotificationsPrimerSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.season) private var season
    @Environment(\.dismiss) private var dismiss
    @Environment(NotificationScheduler.self) private var reminders
    @Environment(CollectionStore.self) private var collection

    var body: some View {
        let leaf = PrimerLeaf(collection: collection, season: season)
        NotificationsPrimerView(
            species: leaf.species, colourway: leaf.colourway, isAsking: reminders.isRequesting, onAllow: allow,
            onNotNow: { dismiss() }
        )
        .presentationDetents([.medium])
        .presentationBackground(theme.colors.surface2)
    }

    private func allow() {
        guard !reminders.isRequesting else { return }
        Task {
            await reminders.requestAuthorization()
            dismiss()
        }
    }
}

/// The first run's reminders step, for onboarding to place where it fits (after the schedule is a good moment:
/// the wind-down time is then known). Full screen on `background`, with the same leaf, words and buttons as the
/// Settings primer. "Allow reminders" shows iOS's prompt and continues once it is answered; "Not now" continues
/// at once. Either way nothing else is asked, and Settings can turn reminders on later.
///
/// ```swift
/// if NotificationsPrimerStep.isNeeded(reminders) {
///     NotificationsPrimerStep { step = .next }
/// }
/// ```
///
/// It reads `NotificationScheduler` and `CollectionStore` from the environment (`MapleApp` injects both).
struct NotificationsPrimerStep: View {
    /// Called after iOS's prompt is answered, or on "Not now".
    var onContinue: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.season) private var season
    @Environment(NotificationScheduler.self) private var reminders
    @Environment(CollectionStore.self) private var collection

    /// Whether the step has anything to ask: iOS hasn't been asked yet. Skip it otherwise.
    static func isNeeded(_ reminders: NotificationScheduler) -> Bool {
        reminders.authorization == .notDetermined
    }

    var body: some View {
        let leaf = PrimerLeaf(collection: collection, season: season)
        NotificationsPrimerView(
            species: leaf.species, colourway: leaf.colourway, isAsking: reminders.isRequesting,
            page: theme.colors.background, onAllow: allow, onNotNow: onContinue
        )
        .background(theme.colors.background)
    }

    private func allow() {
        guard !reminders.isRequesting else { return }
        Task {
            await reminders.requestAuthorization()
            onContinue()
        }
    }
}

/// The leaf above the primer's words: the member's featured leaf in the colourway it was pressed in, else the
/// first leaf every member earns (the Sugar maple), pressed in this season.
private struct PrimerLeaf {
    let species: LeafSpecies?
    let colourway: LeafColourway

    @MainActor
    init(collection: CollectionStore, season: Season) {
        if let id = collection.featuredLeaf, let owned = LeafCatalog.shared.species(id: id),
           let unlock = collection.unlock(for: id) {
            species = owned
            colourway = unlock.colourway
            return
        }
        let first = RewardCatalog.shared.rungs(in: .firstSteps).first
            .flatMap { LeafCatalog.shared.species(id: $0.speciesID) }
        species = first
        colourway = LeafColourway.pressed(in: season, evergreen: first?.evergreen ?? false)
    }
}
