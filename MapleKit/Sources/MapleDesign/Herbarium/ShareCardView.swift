import MapleCore
import SwiftUI

/// The share card (spec §5.9): a 360 × 450pt picture of one earned leaf, rendered with `ImageRenderer` at scale 3
/// (1080 × 1350) and shared as a PNG.
///
/// On `#05070D`, a Level-2 frame inset 24 (radius 40, the one bordered-and-glowing element) holds the specimen at
/// 200pt in its pressed colourway, the name, the scientific name, "Pressed 4 Oct 2026 · for 14 on-time bedtimes",
/// the approximate or Uncharted chip, the member share (only while it is a fresh value) in the season tint, and
/// a quiet "maple" wordmark. `ImageRenderer` doesn't inherit the environment, so pass the theme and season in.
///
/// ```swift
/// let renderer = ImageRenderer(content: ShareCardView(species: rubrum, colourway: .autumn, pressedLine: line, share: share)
///     .environment(\.theme, theme).environment(\.season, season))
/// renderer.scale = ShareCardView.renderScale
/// ```
public struct ShareCardView: View {
    @Environment(\.theme) private var theme
    @Environment(\.season) private var season

    private let species: LeafSpecies
    private let colourway: LeafColourway
    private let pressedLine: String
    private let share: MemberShare

    public static let size = CGSize(width: 360, height: 450)
    public static let renderScale: CGFloat = 3
    static let inset: CGFloat = 24

    /// - Parameter pressedLine: "Pressed 4 Oct 2026 · for 14 on-time bedtimes" (`HerbariumCopy.shareCardLine`).
    public init(species: LeafSpecies, colourway: LeafColourway, pressedLine: String, share: MemberShare) {
        self.species = species
        self.colourway = colourway
        self.pressedLine = pressedLine
        self.share = share
    }

    public var body: some View {
        let colors = theme.colors
        ZStack {
            colors.background
            VStack(spacing: 0) {
                SpecimenView(species: species, colourway: colourway, size: 200)
                    .frame(height: 212, alignment: .top)
                    .padding(.top, 14)
                names
                    .padding(.top, 6)
                PressedLine(text: pressedLine)
                    .padding(.top, 10)
                if let chip = SmallChip(approximate: species.confidence) {
                    chip.padding(.top, 10)
                }
                if let line = MemberShareCopy.shareCard(share) {
                    Text(line)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(colors.seasonTint(season))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.top, 8)
                }
                Spacer(minLength: 8)
                Text(verbatim: "maple")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.bottom, 18)
            }
            .padding(.horizontal, 20)
            .frame(width: Self.size.width - 2 * Self.inset, height: Self.size.height - 2 * Self.inset)
            // The leaf's bloom stays inside the frame's corners.
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.shareCard, style: .continuous))
            .surface(.level2, radius: theme.radius.shareCard)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        // A share card is a fixed picture: text stays at its designed size whatever the reader's setting.
        .dynamicTypeSize(.large)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var names: some View {
        let colors = theme.colors
        VStack(spacing: 3) {
            if species.common.isEmpty {
                Text(species.name)
                    .font(.system(size: 26, weight: .semibold, design: .serif).italic())
                    .foregroundStyle(colors.textPrimary)
                Text("Series \(species.series)")
                    .font(.system(size: 15))
                    .foregroundStyle(colors.textSecondary)
            } else {
                Text(species.common)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                Text(species.name)
                    .font(.system(size: 15, design: .serif).italic())
                    .foregroundStyle(colors.textSecondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private var accessibilityLabel: String {
        var parts = [species.displayName, pressedLine]
        if let approximate = species.confidence.approximateSpokenLabel { parts.append(approximate) }
        if let line = MemberShareCopy.shareCard(share) { parts.append(line) }
        return parts.map { $0.hasSuffix(".") ? $0 : $0 + "." }.joined(separator: " ")
    }
}

/// "Pressed 4 Oct 2026 · for 14 on-time bedtimes": one line when it fits, otherwise broken at the " · ".
private struct PressedLine: View {
    @Environment(\.theme) private var theme
    let text: String

    var body: some View {
        let parts = text.components(separatedBy: " · ")
        ViewThatFits(in: .horizontal) {
            Text(text).lineLimit(1)
            VStack(spacing: 2) {
                Text(parts.first ?? text)
                if parts.count > 1 {
                    Text(HerbariumCopy.capitalisingFirst(parts.dropFirst().joined(separator: " · ")))
                }
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(theme.colors.textSecondary)
        .multilineTextAlignment(.center)
    }
}
