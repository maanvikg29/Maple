import MapleCore
import SwiftUI

/// The Focus streak's mark (F1 design §5.10, §5.15): a Field maple drawn in reward amber, never an SF Symbol. A run is
/// earned, so amber belongs here (spec §1.3). Blades and stalk only by default, so it reads at Home's 16pt; VoiceOver
/// hears the streak beside it, not the leaf.
///
/// ```swift
/// StreakLeaf().frame(width: 16, height: 16)                  // Home's header
/// StreakLeaf(detailed: true).frame(width: 36, height: 36)    // the streak sheet
/// ```
public struct StreakLeaf: View {
    /// The `reward` token's amber (`Theme.Colors.reward`, 0xE8A35C) as a leaf colour, so the stalk takes amber's own
    /// darker tone (`LeafColor.veinColor`).
    nonisolated public static let color = LeafColor(0xE8A35C)
    /// The Field maple, the leaf the Focus screens show.
    nonisolated public static let speciesID = "campestre"

    private let detail: LeafStyle.Detail

    /// - Parameter detailed: Outline and veins too, for a leaf of 36pt or more.
    public init(detailed: Bool = false) {
        detail = detailed ? .full : .fillOnly
    }

    public var body: some View {
        if let species = LeafCatalog.shared.species(id: Self.speciesID) ?? LeafCatalog.shared.species.first {
            LeafView(species, style: LeafStyle(fill: Self.color, detail: detail))
                .accessibilityHidden(true)
        }
    }
}
