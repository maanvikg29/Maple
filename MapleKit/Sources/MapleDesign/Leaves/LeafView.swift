import MapleCore
import SwiftUI

/// One species' leaf, drawn natively from the catalogue generator's geometry at any size and in any colour.
///
/// ```swift
/// LeafView(species)                         // autumn colour, as in the catalogue
/// LeafView(species, fill: .summer)
/// LeafView(species, fill: .color(LeafColor(0xE8A35C)), detail: .fillOnly)
///     .frame(width: 24, height: 24)
/// ```
///
/// The leaf keeps its resting tilt and is fitted to its own drawing (the square the catalogue exports used),
/// so every species fills the frame nicely. VoiceOver reads the species' display name.
///
/// A leaf that is not earned yet is drawn as a skeleton, optionally with its progress rising from the stalk:
///
/// ```swift
/// LeafView(species, style: .skeleton(stroke: tint.opacity(0.6), vein: tint.opacity(0.35)))
///     .progressFill(fraction: 0.4, colour: Color(hex: pressed.rgb), opacity: 0.4)
///     .frame(width: 32, height: 32)
/// ```
public struct LeafView: View {
    /// The blade colour. Outline, veins and stalk always use its `LeafColor.veinColor`.
    public enum Fill: Sendable, Hashable {
        /// The species' own summer green.
        case summer
        /// The species' autumn colour (evergreens stay green).
        case autumn
        case color(LeafColor)
        /// A colourway (spring, summer, autumn, frost) computed from the species, as in spec §6.1.
        case colourway(LeafColourway)

        public func color(for species: LeafSpecies) -> LeafColor {
            switch self {
            case .summer: species.summerColor
            case .autumn: species.autumnColor
            case .color(let color): color
            case .colourway(let colourway): colourway.color(for: species)
            }
        }
    }

    nonisolated public enum Detail: Sendable, Hashable {
        /// Full drawing once a leaf unit is at least `Detail.minimumFullScale` points (a leaf of roughly
        /// 40 points or more), fill and stalk only below that.
        case automatic
        case full
        /// Blades and stalk only, for tiny leaves where outline and veins would be sub-pixel.
        case fillOnly

        /// Points per leaf-space unit at which `automatic` switches to the full drawing
        /// (the 0.8-unit outline is then about a quarter of a point wide).
        public static let minimumFullScale: CGFloat = 0.3

        /// The drawing detail for a leaf shown at `scale` points per leaf-space unit.
        public func resolved(atScale scale: CGFloat) -> LeafStyle.Detail {
            switch self {
            case .full: .full
            case .fillOnly: .fillOnly
            case .automatic: scale >= Self.minimumFullScale ? .full : .fillOnly
            }
        }
    }

    /// Which part of leaf space the view shows.
    nonisolated public enum Framing: Sendable, Equatable {
        /// The leaf's own fitted square (`LeafGeometry.frame`), like the catalogue exports.
        case fitted
        /// A fixed leaf-space rectangle, e.g. the generator's whole -100...100 box so leaves keep their
        /// relative sizes. Coordinates are placed leaf space (after offset and tilt).
        case leafSpace(CGRect)
    }

    /// What the leaf is drawn with: a species colour, or a caller's style (skeletons, theme colours).
    private enum Appearance {
        case fill(Fill, Detail)
        case style(LeafStyle)
    }

    /// Progress towards a locked leaf, filled up from the stalk under the leaf's lines.
    nonisolated private struct Progress {
        var fraction: Double
        var color: Color
    }

    private let species: LeafSpecies
    private let appearance: Appearance
    private let framing: Framing
    private var progress: Progress?

    public init(_ species: LeafSpecies, fill: Fill = .autumn, detail: Detail = .automatic, framing: Framing = .fitted) {
        self.species = species
        self.appearance = .fill(fill, detail)
        self.framing = framing
    }

    /// Draws the leaf in `style` exactly as given, e.g. `.skeleton(stroke:vein:)` for a leaf not earned yet.
    public init(_ species: LeafSpecies, style: LeafStyle, framing: Framing = .fitted) {
        self.species = species
        self.appearance = .style(style)
        self.framing = framing
    }

    /// Fills the blades from where the stalk joins up to `fraction` (0...1) of the leaf's length, along its
    /// own axis, in `colour` at `opacity`, under the leaf's lines: progress towards a locked leaf. Meant for
    /// skeletons (a filled leaf covers it).
    public func progressFill(fraction: Double, colour: Color, opacity: Double = 0.4) -> LeafView {
        var view = self
        view.progress = Progress(fraction: fraction, color: colour.opacity(opacity))
        return view
    }

    public var body: some View {
        let geometry = LeafGeometry.of(species)
        let region = switch framing {
        case .fitted: geometry.frame
        case .leafSpace(let rect): rect
        }
        // A species fill resolves its detail from the drawn size; a given style is drawn exactly as given.
        let (style, detail): (LeafStyle, Detail?) = switch appearance {
        case .fill(let fill, let detail): (LeafStyle(fill: fill.color(for: species), detail: .full), detail)
        case .style(let style): (style, nil)
        }
        let progress = progress
        Canvas { context, size in
            let transform = LeafRenderer.transform(fitting: region, into: CGRect(origin: .zero, size: size))
            if let progress {
                LeafRenderer.drawProgressFill(
                    geometry, in: context, transform: transform, fraction: progress.fraction, color: progress.color
                )
            }
            var resolved = style
            if let detail {
                resolved.detail = detail.resolved(atScale: hypot(transform.a, transform.b))
            }
            LeafRenderer.draw(geometry, in: context, transform: transform, style: resolved)
        }
        .aspectRatio(region.width / max(region.height, 1), contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(Text(species.displayName))
        .accessibilityAddTraits(.isImage)
    }
}

#Preview("Leaves") {
    let catalog = LeafCatalog.shared
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88))]) {
            ForEach(catalog.species) { species in
                LeafView(species, fill: .autumn)
                    .frame(width: 88, height: 88)
            }
        }
        .padding()
    }
}
