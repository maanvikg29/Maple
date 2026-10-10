import SwiftUI
import MapleCore
import MapleDesign

/// The image the reveal's share circle shares: the share card of spec §5.9, rendered at 1080 × 1350.
///
/// It is the Herbarium's `ShareCardView`, rendered through `ShareCardImage`, so a leaf shared from the reveal and
/// from leaf detail is the same picture.
enum RevealShareCard {
    /// Renders the card for an opened leaf. Text is drawn at the default size whatever the member's setting,
    /// so every shared card looks the same.
    @MainActor
    static func image(leaf: RevealLeaf, pressedOn date: Date, season: Season, theme: Theme) -> Image? {
        ShareCardImage.render(
            species: leaf.species, colourway: leaf.colourway, pressedLine: pressedLine(leaf, pressedOn: date),
            share: leaf.share, theme: theme, season: season
        )?.image
    }

    /// "Pressed 4 Oct 2026 · for 14 on-time bedtimes".
    private static func pressedLine(_ leaf: RevealLeaf, pressedOn date: Date) -> String {
        let day = date.formatted(.dateTime.day().month(.abbreviated).year())
        let reason = leaf.earnedLine.prefix(1).lowercased() + leaf.earnedLine.dropFirst()
        return "Pressed \(day) · \(reason)"
    }
}
