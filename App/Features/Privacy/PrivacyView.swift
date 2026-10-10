import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// Privacy (spec §8.7, §5.7): the rarity-stats consent toggle, the same answer the consent sheet after the first
/// morning reveal records (`CollectionStore.rarityConsent`), with the explainer link; Apple Health's status, with
/// "Turn on" (the primer) while it is off; and the promise that sleep, focus and screen data stay on the iPhone. A
/// Screen Time row joins once Screen Time ships. Works in any navigation stack, so the rarity explainer's "Privacy
/// settings" link can push it too.
struct PrivacyView: View {
    @Environment(\.theme) private var theme
    @Environment(CollectionStore.self) private var collection
    @Environment(HealthPermission.self) private var health
    @State private var showsExplainer = false
    @State private var healthPrimer: HealthPrimerRequest?

    var body: some View {
        let included = Binding(
            get: { collection.rarityConsent == .included },
            set: { collection.setRarityConsent($0) }
        )
        ProfilePage("Privacy") {
            VStack(alignment: .leading, spacing: theme.spacing.sm) {
                ProfileListGroup {
                    ProfileSettingRow(
                        "Include my leaves in rarity stats",
                        detail: Text("Maple adds the leaves you hold to anonymous counts, so each leaf can show how many members have it. No account, no device ID, no health data."),
                        link: TextLink("How rarity works") { showsExplainer = true }
                    ) {
                        ProfileToggle("Include my leaves in rarity stats", isOn: included)
                    }
                    appleHealthRow
                }
                Text("Your sleep, focus and screen data never leave your iPhone.")
                    .font(MapleFont.footnote)
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, theme.spacing.listMargin)
            }
        }
        .sheet(isPresented: $showsExplainer) {
            // The Herbarium's explainer, in its general form (no leaf, no "Privacy settings" link).
            RarityExplainerSheet(speciesID: nil)
        }
        .sheet(item: $healthPrimer) { HealthPrimerSheet(speciesID: $0.speciesID) }
        #if DEBUG
        .task {
            // `-MapleDemoProfile rarity` opens the explainer once the sheet has settled.
            guard UserDefaults.standard.string(forKey: "MapleDemoProfile") == "rarity" else { return }
            try? await Task.sleep(for: .seconds(1))
            showsExplainer = true
        }
        #endif
    }

    /// Apple Health: "Connected" once the member has been through Apple's prompt (HealthKit never says what they
    /// allowed, so the line points to the Health app), else a "Turn on" capsule that opens the primer.
    private var appleHealthRow: some View {
        ProfileSettingRow(
            "Apple Health",
            detail: Text(health.isConnected
                ? "Maple reads only your sleep, on this iPhone. Change what it can read in the Health app."
                : "Your sleep leaves grow from the sleep Apple Health records."),
            controlIsLabelled: false
        ) {
            if health.isConnected {
                Text("Connected")
                    .font(MapleFont.callout)
                    .foregroundStyle(theme.colors.textSecondary)
            } else {
                Button("Turn on") { healthPrimer = HealthPrimerRequest() }
                    .buttonStyle(.glassCapsule(.compact))
                    .accessibilityLabel("Turn on Apple Health")
            }
        }
    }
}
