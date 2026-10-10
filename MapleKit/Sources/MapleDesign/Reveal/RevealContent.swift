import MapleCore
import SwiftUI

/// One waiting leaf, with everything the reveal says about it (spec §5.8).
nonisolated public struct RevealLeaf: Sendable, Equatable, Identifiable {
    public var id: String { species.id }
    public let species: LeafSpecies
    /// The colourway it was pressed in (the season it was earned).
    public let colourway: LeafColourway
    public let tier: RewardTier
    /// The header's second line, e.g. "On-time bedtimes".
    public let categoryName: String
    /// "For 14 on-time bedtimes".
    public let earnedLine: String
    /// How many members hold it, in any `MemberShare` state.
    public var share: MemberShare

    public init(
        species: LeafSpecies, colourway: LeafColourway, tier: RewardTier, categoryName: String, earnedLine: String,
        share: MemberShare
    ) {
        self.species = species
        self.colourway = colourway
        self.tier = tier
        self.categoryName = categoryName
        self.earnedLine = earnedLine
        self.share = share
    }

    /// The reveal's words for an earned leaf, from the catalogue and the reward table; nil for an unknown species.
    public init?(
        unlock: LeafUnlock, share: MemberShare, catalog: LeafCatalog = .shared, rewards: RewardCatalog = .shared
    ) {
        guard let species = catalog.species(id: unlock.speciesID),
              let reward = rewards.reward(forSpecies: unlock.speciesID) else { return nil }
        self.init(
            species: species,
            colourway: unlock.colourway,
            tier: reward.tier,
            categoryName: rewards.category(reward.categoryID)?.name ?? "",
            earnedLine: RewardCategoryInfo(reward.categoryID).earnedLine(reward.threshold),
            share: share
        )
    }
}

/// The cover's header: "A new leaf", with " · 1 of 3" while more wait, and the category under it. The species
/// itself stays hidden until it opens (spec §5.8).
public struct RevealHeader: View {
    @Environment(\.theme) private var theme
    private let title: String
    private let position: (index: Int, count: Int)?
    private let detail: String?

    /// - Parameters:
    ///   - title: "A new leaf", or "3 new leaves" while "Open all" runs.
    ///   - position: "1 of 3" when queued.
    ///   - detail: The category name, e.g. "On-time bedtimes".
    public init(_ title: String = "A new leaf", position: (index: Int, count: Int)? = nil, detail: String? = nil) {
        self.title = title
        self.position = position
        self.detail = detail
    }

    public var body: some View {
        VStack(spacing: 2) {
            Text(headline)
                .font(MapleFont.contextEmphasis)
                .monospacedDigit()
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(MapleFont.footnote)
            }
        }
        .foregroundStyle(theme.colors.textSecondary)
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var headline: String {
        guard let position else { return title }
        return "\(title) · \(position.index) of \(position.count)"
    }
}

/// The words under an opened leaf (spec §5.8): its name, scientific name, tier and approximate chips, what it
/// was earned for, and how many members hold it.
public struct RevealCaption: View {
    @Environment(\.theme) private var theme
    private let leaf: RevealLeaf

    public init(_ leaf: RevealLeaf) {
        self.leaf = leaf
    }

    public var body: some View {
        let species = leaf.species
        let colors = theme.colors
        VStack(spacing: 0) {
            Group {
                if species.common.isEmpty {
                    // Unnamed: the scientific name is the title, and the series goes under it.
                    Text(RevealText.latin(species.name))
                        .font(MapleFont.scientific(.title, weight: .semibold))
                } else {
                    Text(species.common)
                        .font(MapleFont.leafTitle)
                }
            }
            .foregroundStyle(colors.textPrimary)
            .accessibilityAddTraits(.isHeader)

            Group {
                if species.common.isEmpty {
                    Text(RevealText.series(species.series))
                        .font(MapleFont.callout)
                } else {
                    Text(RevealText.latin(species.name))
                        .font(MapleFont.scientific(.body))
                }
            }
            .foregroundStyle(colors.textSecondary)
            .padding(.top, 4)

            ChipFlow(alignment: .center) {
                SmallChip(tier: leaf.tier)
                if let chip = SmallChip(approximate: species.confidence) { chip }
            }
            .padding(.top, 12)

            Text(leaf.earnedLine)
                .font(MapleFont.callout)
                .foregroundStyle(colors.textSecondary)
                .padding(.top, 16)

            MemberShareLabel(share: leaf.share, layout: .inline)
                .padding(.top, 4)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        // One element, read in order: name, scientific name, tier, approximate drawing, earned line, rarity.
        .accessibilityElement(children: .combine)
    }
}

nonisolated enum RevealText {
    /// A scientific name that VoiceOver reads as Latin (spec §9).
    static func latin(_ name: String) -> AttributedString {
        var text = AttributedString(name)
        text.languageIdentifier = "la"
        return text
    }

    /// The line under an unnamed species' title: "Series Macrantha", or "Not placed in a series" for the
    /// catalogue's "Unplaced" species.
    static func series(_ series: String) -> String {
        series.isEmpty || series.caseInsensitiveCompare("Unplaced") == .orderedSame ? "Not placed in a series" : "Series \(series)"
    }
}
