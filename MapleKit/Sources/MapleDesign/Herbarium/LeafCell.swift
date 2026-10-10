import MapleCore
import SwiftUI

/// One Herbarium tile in any state (spec §5.5): earned, waiting, next, locked, needs permission and dormant.
///
/// The grid tile is about 116.7 × 156: a 116 × 100 leaf well with the specimen at 64pt, the name at y 104 and the
/// meta at y 124. Earned and waiting tiles sit on Level 1 (the earned bloom is clipped to the tile); locked tiles
/// have no container at all. At accessibility text sizes the Herbarium switches to `.row`: a 72pt row with a
/// 48pt leaf on the left.
///
/// ```swift
/// Button { open(entry) } label: { LeafCell(LeafCellModel(entry, season: season)) }
///     .buttonStyle(.leafCell)
/// ```
public struct LeafCell: View {
    nonisolated public enum Layout: Sendable, Hashable {
        /// The 3- (or 2-) column grid tile.
        case tile
        /// The 1-column list row used at accessibility text sizes.
        case row
    }

    @Environment(\.theme) private var theme
    private let model: LeafCellModel
    private let layout: Layout

    public init(_ model: LeafCellModel, layout: Layout = .tile) {
        self.model = model
        self.layout = layout
    }

    public var body: some View {
        Group {
            switch layout {
            case .tile: tile
            case .row: row
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel)
        .accessibilityHint(model.accessibilityHint.map { Text($0) } ?? Text(""))
    }

    // MARK: Tile

    private var tile: some View {
        let shape = RoundedRectangle(cornerRadius: theme.radius.tile, style: .continuous)
        return VStack(spacing: 0) {
            specimen(size: LeafCellMetrics.leafSize)
                .padding(.top, LeafCellMetrics.leafTop)
                .frame(maxWidth: .infinity, minHeight: LeafCellMetrics.wellHeight, maxHeight: LeafCellMetrics.wellHeight,
                       alignment: .top)
            name
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .padding(.top, 4)
            metaView(alignment: .center)
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .background {
            if model.variant.hasContainer {
                Color.clear.surface(.level1, radius: theme.radius.tile)
            }
        }
        // The earned bloom spills past the specimen; the tile keeps it inside its own corners.
        .clipShape(model.variant.hasContainer ? AnyShape(shape) : AnyShape(Rectangle()))
        .overlay(alignment: .topLeading) { approximateMark.padding(10) }
        .overlay(alignment: .topTrailing) { unseenDot.padding(10) }
        .contentShape(shape)
    }

    // MARK: Row

    private var row: some View {
        let shape = RoundedRectangle(cornerRadius: theme.radius.tile, style: .continuous)
        return HStack(spacing: 16) {
            specimen(size: 48)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if model.showsApproximateMark {
                        Text(verbatim: "≈")
                            .font(MapleFont.micro)
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                    name
                }
                metaView(alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            unseenDot
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 72)
        .background {
            if model.variant.hasContainer {
                Color.clear.surface(.level1, radius: theme.radius.tile)
            }
        }
        .clipShape(model.variant.hasContainer ? AnyShape(shape) : AnyShape(Rectangle()))
        .contentShape(shape)
    }

    // MARK: Parts

    @ViewBuilder
    private func specimen(size: CGFloat) -> some View {
        SpecimenView(species: model.species, colourway: model.variant.colourway, size: size,
                     state: model.variant.specimenState)
    }

    private var name: some View {
        Text(model.name)
            .font(model.nameIsScientific ? MapleFont.scientific(.footnote) : MapleFont.tileName)
            .foregroundStyle(model.nameIsSecondary ? theme.colors.textSecondary : theme.colors.textPrimary)
            .lineLimit(layout == .row ? 2 : 1)
            .minimumScaleFactor(0.85)
            // Only width may shrink a name; a row's height never squeezes it.
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func metaView(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 5) {
            Text(model.meta.text)
                .font(MapleFont.tileMeta)
                .foregroundStyle(theme.colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
            // The bar's slot is kept on every tile, so all tiles in a row share one height.
            Group {
                if case .amount(_, let fraction) = model.meta {
                    ProgressHairline(fraction: fraction, height: 2)
                } else {
                    Color.clear
                }
            }
            .frame(width: LeafCellMetrics.barWidth, height: 2)
        }
    }

    @ViewBuilder
    private var approximateMark: some View {
        if model.showsApproximateMark {
            Text(verbatim: "≈")
                .font(MapleFont.micro)
                .foregroundStyle(theme.colors.textSecondary)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var unseenDot: some View {
        if model.showsUnseenDot {
            Circle()
                .fill(theme.colors.reward)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
        }
    }
}

/// Tile geometry (spec §5.5).
nonisolated enum LeafCellMetrics {
    static let wellHeight: CGFloat = 100
    static let leafSize: CGFloat = 64
    /// The leaf's square sits 16pt down the well, so its shadow lands just above the name.
    static let leafTop: CGFloat = 16
    static let barWidth: CGFloat = 56
}

/// Press feedback for tiles and cards: 0.98 scale and 90% opacity over `press` (spec §5.5).
public struct LeafCellButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        LeafCellPress(configuration: configuration)
    }
}

private struct LeafCellPress: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let configuration: ButtonStyleConfiguration

    var body: some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .mapleAnimation(theme.motion.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == LeafCellButtonStyle {
    /// Tiles and Almost-there cards.
    public static var leafCell: LeafCellButtonStyle { LeafCellButtonStyle() }
}
