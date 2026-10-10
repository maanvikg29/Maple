import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// "Members who have this leaf": what the percentage means, how it is counted and what is shared (spec §5.7).
/// A `.medium` sheet from leaf detail's info button, ending with "Privacy settings", and from Privacy's
/// "How rarity works" link (where that closing link would lead back to the same page, so it is left out).
struct RarityExplainerSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone
    @Environment(CollectionStore.self) private var collection
    @Environment(LeafShareStore.self) private var shares

    /// The leaf the sheet explains; nil from Privacy, which explains rarity in general.
    let speciesID: String?
    @State private var showsPrivacy = false

    init(speciesID: String?) {
        self.speciesID = speciesID
    }

    var body: some View {
        // Without a leaf, the member's featured leaf stands in: the member count and week are the same for all.
        let share = shares.share(for: speciesID ?? collection.featuredLeaf ?? "saccharum")
        let explainer = RarityExplainer(
            share: share, memberCount: shares.memberCount, weekStart: shares.weekStart,
            included: collection.rarityConsent == .included, locale: locale, timeZone: timeZone
        )
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                RarityExplainerView(explainer, title: speciesID == nil ? "How rarity works" : RarityExplainer.title)
                if speciesID != nil {
                    TextLink("Privacy settings") { showsPrivacy = true }
                        .padding(.top, theme.spacing.xs)
                }
            }
            .padding(.horizontal, theme.spacing.listMargin)
            .padding(.top, theme.spacing.xl)
            .padding(.bottom, theme.spacing.lg)
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.medium])
        .presentationBackground(theme.colors.surface2)
        .presentationDragIndicator(.visible)
        // Privacy lives in the Profile sheet (spec §8.3, §8.7); it opens straight on that page.
        .sheet(isPresented: $showsPrivacy) { ProfileView(path: [.privacy]) }
    }
}
