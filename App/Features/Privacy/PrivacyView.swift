import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// Privacy (spec §8.7, §5.7): the rarity-stats consent toggle, the same answer the consent sheet after the first
/// morning reveal records (`CollectionStore.rarityConsent`), with the explainer link; and the promise that sleep,
/// focus and screen data stay on the iPhone. Apple Health and Screen Time status rows join once those integrations
/// ship. Works in any navigation stack, so the rarity explainer's "Privacy settings" link can push it too.
struct PrivacyView: View {
    @Environment(\.theme) private var theme
    @Environment(CollectionStore.self) private var collection
    @State private var showsExplainer = false

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
        #if DEBUG
        .task {
            // `-MapleDemoProfile rarity` opens the explainer once the sheet has settled.
            guard UserDefaults.standard.string(forKey: "MapleDemoProfile") == "rarity" else { return }
            try? await Task.sleep(for: .seconds(1))
            showsExplainer = true
        }
        #endif
    }
}
