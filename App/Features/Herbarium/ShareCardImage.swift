import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import MapleCore
import MapleDesign

/// The share card as a PNG (spec §5.9): `ShareCardView` rendered at 360 × 450pt × 3 = 1080 × 1350, shared through
/// `ShareLink`.
///
/// Rendering keeps the bitmap only. The PNG (around 100 ms of ImageIO work for a card this size) is encoded when
/// the member actually shares, inside the transfer representation's exporter, which the share sheet runs off the
/// main actor, so no screen stalls on it.
nonisolated struct ShareCardImage: Transferable, Sendable {
    let bitmap: CGImage
    let image: Image
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { try $0.pngData() }
            .suggestedFileName { "\($0.name).png" }
    }

    private struct EncodingFailed: Error {}

    /// The card as PNG data.
    func pngData() throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw EncodingFailed()
        }
        CGImageDestinationAddImage(destination, bitmap, nil)
        guard CGImageDestinationFinalize(destination) else { throw EncodingFailed() }
        return data as Data
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
        guard let bitmap = renderer.cgImage else { return nil }
        return ShareCardImage(
            bitmap: bitmap, image: Image(decorative: bitmap, scale: ShareCardView.renderScale), name: species.displayName
        )
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
