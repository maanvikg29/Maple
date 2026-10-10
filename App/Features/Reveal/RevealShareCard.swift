import SwiftUI
import MapleCore
import MapleDesign

/// The image the reveal's share circle shares: the share card of spec §5.9, rendered at 1080 × 1350.
///
/// The Herbarium's `ShareCardView` draws the same card from leaf detail; once both are in one branch the reveal
/// can render that view here instead (one call site, `RevealShareCard.image(…)`).
enum RevealShareCard {
    /// Renders the card for an opened leaf. Text is drawn at the default size whatever the member's setting,
    /// so every shared card looks the same.
    @MainActor
    static func image(leaf: RevealLeaf, pressedOn date: Date, season: Season, theme: Theme) -> Image? {
        let card = Card(leaf: leaf, pressedOn: date)
            .environment(\.theme, theme)
            .environment(\.season, season)
            .environment(\.dynamicTypeSize, .large)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        guard let image = renderer.uiImage else { return nil }
        return Image(uiImage: image)
    }

    /// 360 × 450 pt: the specimen in its pressed colourway on a Level-2 frame, its names, when and why it was
    /// pressed, the approximate chip, the members line (fresh values only) and the wordmark.
    private struct Card: View {
        @Environment(\.theme) private var theme
        @Environment(\.season) private var season
        let leaf: RevealLeaf
        let pressedOn: Date

        var body: some View {
            let colors = theme.colors
            let species = leaf.species
            VStack(spacing: 0) {
                SpecimenView(species: species, colourway: leaf.colourway, size: 200)
                    .padding(.top, 10)
                Text(species.common.isEmpty ? species.name : species.common)
                    .font(species.common.isEmpty
                        ? .system(size: 26, weight: .semibold, design: .serif).italic()
                        : .system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 8)
                if !species.common.isEmpty {
                    Text(species.name)
                        .font(.system(size: 15, design: .serif).italic())
                        .foregroundStyle(colors.textSecondary)
                        .padding(.top, 2)
                }
                Text(pressedLine)
                    .font(.system(size: 13))
                    .foregroundStyle(colors.textSecondary)
                    .lineLimit(2)
                    .padding(.top, 8)
                if let chip = SmallChip(approximate: species.confidence) {
                    chip.padding(.top, 8)
                }
                if let members = MemberShareCopy.shareCard(leaf.share) {
                    Text(members)
                        .font(.system(size: 13))
                        .foregroundStyle(colors.seasonTint(season))
                        .padding(.top, 6)
                }
                Spacer(minLength: 8)
                Text("maple")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.bottom, 14)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .frame(width: 312, height: 402)
            .surface(.level2, radius: theme.radius.shareCard)
            .frame(width: 360, height: 450)
            .background(colors.background)
        }

        /// "Pressed 4 Oct 2026 · for 14 on-time bedtimes".
        private var pressedLine: String {
            let day = pressedOn.formatted(.dateTime.day().month(.abbreviated).year())
            let reason = leaf.earnedLine.prefix(1).lowercased() + leaf.earnedLine.dropFirst()
            return "Pressed \(day) · \(reason)"
        }
    }
}
