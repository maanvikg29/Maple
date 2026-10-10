import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// "Members who have this leaf": what the percentage means, how it is counted and what is shared (spec §5.7).
/// A `.medium` sheet from leaf detail's info button, ending with "Privacy settings".
struct RarityExplainerSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone
    @Environment(CollectionStore.self) private var collection
    @Environment(LeafShareStore.self) private var shares

    let speciesID: String
    @State private var showsPrivacy = false

    var body: some View {
        let explainer = RarityExplainer(
            share: shares.share(for: speciesID), memberCount: shares.memberCount, weekStart: shares.weekStart,
            included: collection.rarityConsent == .included, locale: locale, timeZone: timeZone
        )
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                RarityExplainerView(explainer)
                TextLink("Privacy settings") { showsPrivacy = true }
                    .padding(.top, theme.spacing.xs)
            }
            .padding(.horizontal, theme.spacing.listMargin)
            .padding(.top, theme.spacing.xl)
            .padding(.bottom, theme.spacing.lg)
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.medium])
        .presentationBackground(theme.colors.surface2)
        .presentationDragIndicator(.visible)
        // Privacy lives in the Profile sheet (spec §8.3, §8.7).
        .sheet(isPresented: $showsPrivacy) { ProfileView() }
    }
}
