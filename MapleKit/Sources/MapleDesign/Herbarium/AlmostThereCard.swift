import MapleCore
import SwiftUI

/// A leaf that is close (spec §5.3): a 136 × 170 Level-1 card with a season-tint spotlight, the skeleton filling
/// from its stalk, the name, a 2pt tint bar and what is left ("3 nights to go"). At accessibility text sizes the
/// rail becomes a vertical stack of `.row` cards.
///
/// ```swift
/// AlmostThereCard(species: rubrum, fraction: 0.6, colourway: .autumn, remainder: "3 nights to go")
/// ```
public struct AlmostThereCard: View {
    nonisolated public enum Layout: Sendable, Hashable {
        case card
        case row
    }

    @Environment(\.theme) private var theme
    @Environment(\.season) private var season

    private let species: LeafSpecies
    private let fraction: Double
    private let colourway: LeafColourway
    private let remainder: String
    private let layout: Layout

    public static let size = CGSize(width: 136, height: 170)

    /// - Parameters:
    ///   - colourway: The colourway the leaf would be pressed in now; its progress fills in it at 40%.
    ///   - remainder: "3 nights to go", "Tonight".
    public init(species: LeafSpecies, fraction: Double, colourway: LeafColourway, remainder: String, layout: Layout = .card) {
        self.species = species
        self.fraction = fraction
        self.colourway = colourway
        self.remainder = remainder
        self.layout = layout
    }

    public var body: some View {
        Group {
            switch layout {
            case .card: card
            case .row: row
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: theme.radius.tile, style: .continuous)
        return VStack(spacing: 0) {
            SpecimenView(species: species, colourway: colourway, size: 72, state: .next(progress: fraction))
                .padding(.top, 14)
            Spacer(minLength: 4)
            name
                .padding(.horizontal, 14)
            ProgressHairline(fraction: fraction, height: 2)
                .padding(.horizontal, 14)
                .padding(.top, 10)
            Text(remainder)
                .font(MapleFont.tileMeta)
                .foregroundStyle(theme.colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.top, 8)
        }
        .padding(.bottom, 16)
        // 170pt tall at the default size; larger text grows the card rather than squeezing it.
        .frame(width: Self.size.width)
        .frame(minHeight: Self.size.height)
        .fixedSize(horizontal: false, vertical: true)
        .background { spotlight }
        .surface(.level1, radius: theme.radius.tile)
        .clipShape(shape)
        .overlay(alignment: .topLeading) { approximateMark.padding(10) }
        .contentShape(shape)
    }

    private var row: some View {
        HStack(spacing: 16) {
            SpecimenView(species: species, colourway: colourway, size: 48, state: .next(progress: fraction))
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    approximateMark
                    name
                }
                ProgressHairline(fraction: fraction, height: 2)
                Text(remainder)
                    .font(MapleFont.tileMeta)
                    .foregroundStyle(theme.colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background { spotlight }
        .surface(.level1, radius: theme.radius.tile)
        .clipShape(RoundedRectangle(cornerRadius: theme.radius.tile, style: .continuous))
    }

    private var name: some View {
        Text(species.displayName)
            .font(species.common.isEmpty ? MapleFont.scientific(.footnote) : MapleFont.tileName)
            .foregroundStyle(theme.colors.textPrimary)
            .lineLimit(layout == .row ? 2 : 1)
            .minimumScaleFactor(0.85)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The season tint lighting the card from above: radial, 8%, radius 120.
    private var spotlight: some View {
        RadialGradient(
            colors: [theme.colors.seasonTint(season).opacity(0.08), theme.colors.seasonTint(season).opacity(0)],
            center: UnitPoint(x: 0.5, y: 0), startRadius: 0, endRadius: 120
        )
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var approximateMark: some View {
        if species.confidence.isApproximate {
            Text(verbatim: "≈")
                .font(MapleFont.micro)
                .foregroundStyle(theme.colors.textSecondary)
                .accessibilityHidden(true)
        }
    }

    private var accessibilityLabel: String {
        var parts = [species.common.isEmpty ? species.name : "\(species.common), \(species.name)", remainder]
        if let approximate = species.confidence.approximateSpokenLabel { parts.append(approximate) }
        return parts.map { $0.hasSuffix(".") ? $0 : $0 + "." }.joined(separator: " ")
    }
}
