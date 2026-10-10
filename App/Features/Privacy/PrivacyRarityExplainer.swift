import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// What "% of members have this leaf" means (spec §5.7), as a `.medium` sheet: who is counted, how uncertain
/// values are shown, and what is shared. The CloudKit counters behind it store only which leaves members hold
/// (spec override 1), so there is no "flips some of its answers" sentence.
///
/// The Herbarium's explainer may replace this one when the branches merge; until then Privacy presents it.
struct PrivacyRarityExplainer: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(LeafShareStore.self) private var shares
    /// Shows the closing "Privacy settings" link when the explainer is opened from outside Privacy.
    var privacySettings: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: theme.spacing.sm) {
                    Text("How rarity works")
                        .font(MapleFont.sectionTitle)
                        .foregroundStyle(theme.colors.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .buttonStyle(.iconCircle)
                        .padding(.trailing, -theme.spacing.xxs)
                }

                VStack(alignment: .leading, spacing: theme.spacing.sm) {
                    Text(countParagraph)
                    Text("When the numbers are too small to be sure, Maple shows a bound like “Under 1%” instead of a guess.")
                    Text("Only which leaves you hold is ever shared, never sleep, health or screen data.")
                }
                .font(MapleFont.callout)
                .foregroundStyle(theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, theme.spacing.md)

                if let privacySettings {
                    TextLink("Privacy settings") {
                        dismiss()
                        privacySettings()
                    }
                    .padding(.top, theme.spacing.xs)
                }
            }
            .padding(.horizontal, theme.spacing.listMargin)
            .padding(.top, theme.spacing.lg)
            .padding(.bottom, theme.spacing.xl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.medium, .large])
        .presentationBackground(theme.colors.surface2)
    }

    /// "Each leaf shows the share of members who hold it, out of 12,400 members who shared their leaves in the week
    /// of 29 Sep." Before 1,000 members take part there is no count to quote.
    private var countParagraph: String {
        let lead = "Each leaf shows the share of Maple members who hold it"
        guard let members = shares.memberCount else {
            let threshold = MemberShareCopy.memberThreshold.formatted(.number.locale(locale))
            return "\(lead). Percentages appear once \(threshold) members take part."
        }
        let count = members.formatted(.number.locale(locale))
        guard let week = shares.weekStart else {
            return "\(lead), out of \(count) members who shared their leaves."
        }
        let day = week.formatted(Date.FormatStyle(locale: locale).day().month(.abbreviated))
        return "\(lead), out of \(count) members who shared their leaves in the week of \(day)."
    }
}
