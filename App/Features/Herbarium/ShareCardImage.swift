import SwiftUI
import UIKit
import UniformTypeIdentifiers
import MapleCore
import MapleDesign

/// The share card as a PNG (spec §5.9): `ShareCardView` rendered at 360 × 450pt × 3 = 1080 × 1350, shared through
/// `ShareLink`.
nonisolated struct ShareCardImage: Transferable, Sendable {
    let png: Data
    let image: Image
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.png }
            .suggestedFileName { "\($0.name).png" }
    }
}

extension ShareCardImage {
    @MainActor
    static func render(
        species: LeafSpecies, colourway: LeafColourway, pressedLine: String, share: MemberShare, theme: Theme, season: Season
    ) -> ShareCardImage? {
        let card = ShareCardView(species: species, colourway: colourway, pressedLine: pressedLine, share: share)
            .environment(\.theme, theme)
            .environment(\.season, season)
        let renderer = ImageRenderer(content: card)
        renderer.scale = ShareCardView.renderScale
        renderer.proposedSize = ProposedViewSize(ShareCardView.size)
        renderer.isOpaque = true
        guard let image = renderer.uiImage, let png = image.pngData() else { return nil }
        return ShareCardImage(png: png, image: Image(uiImage: image), name: species.displayName)
    }
}

#if DEBUG
/// DEBUG only (`-MapleDemoPresent share:<id>`): the exact PNG the share button sends, shown at its point size so
/// it can be screenshotted and judged.
struct ShareCardInspector: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let image: ShareCardImage?

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()
            if let image {
                image.image
                    .resizable()
                    .interpolation(.high)
                    .frame(width: ShareCardView.size.width, height: ShareCardView.size.height)
            } else {
                ProgressView()
            }
        }
        .overlay(alignment: .topLeading) {
            Button("Close", systemImage: "xmark") { dismiss() }
                .buttonStyle(.iconCircle)
                .padding(.horizontal, 12)
        }
    }
}
#endif
