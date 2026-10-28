import SwiftUI
import UIKit
import MapleCore
import MapleDesign
import MapleServices

/// "Turn on Apple Health", from Home's needs-permission row, a Herbarium section header, leaf detail or Privacy:
/// the calm primer (`HealthPrimerView`), whose "Continue" shows Apple's Health sheet through `HealthPermission`.
/// Once the member closes Apple's sheet, Apple Health counts as connected, the sleep leaves become available
/// everywhere and the importer reads Apple Health's sleep at once; "Not now" leaves everything as it was. Present it
/// with `.sheet(item:)`; it brings its own detent and background.
struct HealthPrimerSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.season) private var season
    @Environment(\.mapleClock) private var clock
    @Environment(\.dismiss) private var dismiss
    @Environment(HealthPermission.self) private var health
    @Environment(CollectionStore.self) private var collection
    @Environment(HealthSleepImporter.self) private var sleep

    /// The leaf drawn above the words: the one the member came from, else the cheapest sleep leaf.
    let speciesID: String?

    var body: some View {
        let species = leaf
        HealthPrimerView(
            species: species, colourway: LeafColourway.pressed(in: season, evergreen: species?.evergreen ?? false),
            isAsking: health.isRequesting, onContinue: connect, onNotNow: { dismiss() }
        )
        .presentationDetents([.medium])
        .presentationBackground(theme.colors.surface2)
        #if DEBUG
        .task {
            // `-MapleDemoHealthContinue YES`: taps Continue once the sheet has settled, so Apple's Health sheet can
            // be screenshotted (docs/debug-launch-arguments.md).
            guard UserDefaults.standard.bool(forKey: "MapleDemoHealthContinue") else { return }
            try? await Task.sleep(for: .seconds(1))
            connect()
        }
        #endif
    }

    private var leaf: LeafSpecies? {
        let fallback = collection.permissionPrompt(at: clock.now())?.speciesID
            ?? RewardCatalog.shared.rungs(in: .restedNights).first?.speciesID
        return (speciesID ?? fallback).flatMap { LeafCatalog.shared.species(id: $0) }
    }

    /// Apple's sheet over the primer; once the member closes it, the sleep leaves follow, the importer reads
    /// whatever sleep Apple Health already has (from the night before the install night on), and the primer goes.
    private func connect() {
        guard !health.isRequesting else { return }
        Task {
            let connected = await health.requestAccess(at: clock.now())
            health.apply(to: collection)
            dismiss()
            guard connected else { return }
            sleep.startObserving(clock: clock)
            await sleep.importNow(at: clock.now())
        }
    }
}

/// A request to show the Apple Health primer, drawing the given leaf.
struct HealthPrimerRequest: Identifiable, Hashable {
    var speciesID: String?

    var id: String { "health.\(speciesID ?? "")" }
}

/// What "Turn on" does for a missing permission: Apple Health shows the primer (`HealthPrimerSheet`); Screen Time,
/// once it ships, opens Maple's page in Settings.
@MainActor
func turnOnPermission(
    _ availability: LeafAvailability, speciesID: String?, showHealthPrimer: (HealthPrimerRequest) -> Void,
    openURL: OpenURLAction
) {
    switch availability {
    case .needsAppleHealth:
        showHealthPrimer(HealthPrimerRequest(speciesID: speciesID))
    case .needsScreenTime:
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    case .available, .dormant:
        break
    }
}
