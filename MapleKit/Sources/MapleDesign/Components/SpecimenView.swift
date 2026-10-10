import MapleCore
import SwiftUI

/// Where a leaf stands, as the specimen grammar draws it (spec §5.2, §5.5).
nonisolated public enum SpecimenState: Sendable, Hashable {
    /// Earned and revealed: the leaf in its pressed colourway, on its own bloom, above a contact shadow.
    case earned
    /// One of the next locked rungs: a skeleton with the colourway rising from the stalk to `progress` (0...1).
    case next(progress: Double)
    /// A further locked rung: the neutral skeleton.
    case locked
    /// Earned but not opened: the bud with its amber glow. The species stays hidden.
    case waiting
    /// The category needs Apple Health or Screen Time: the locked skeleton at 50%.
    case needsPermission
    /// The category has not shipped: the locked skeleton at 35%.
    case dormant
}

/// One leaf, presented as a specimen: the only way a leaf larger than 40pt is shown (spec §1.10, §7.3).
///
/// An earned leaf sits on a radial bloom of its own colour (18% in tiles, 22% from 120pt up, the §6.5 caps),
/// at its resting tilt, above a contact-shadow ellipse. Locked leaves are vein-only skeletons of their real shape,
/// never padlocks or grey copies. The bloom spills past the frame; a tile clips it to its own corners.
///
/// ```swift
/// SpecimenView(species: rubrum, colourway: unlock.colourway, size: 64)                      // earned tile
/// SpecimenView(species: rubrum, colourway: .autumn, size: 72, state: .next(progress: 0.6))  // Almost there
/// SpecimenView(species: rubrum, colourway: .autumn, size: 200, state: .locked)              // detail
/// ```
///
/// The view is `size` wide and `size × 1.12` tall: the leaf's square plus room for its shadow.
public struct SpecimenView: View {
    @Environment(\.theme) private var theme
    @Environment(\.season) private var season

    private let species: LeafSpecies
    private let colourway: LeafColourway
    private let size: CGFloat
    private let state: SpecimenState

    /// - Parameters:
    ///   - colourway: The pressed colourway for an earned leaf; for a locked one, the colourway its progress
    ///     fills with (the one it would be pressed in now).
    ///   - size: The leaf's square, in points. Detail and reveal use 200, Almost there 72, tiles 64.
    public init(species: LeafSpecies, colourway: LeafColourway, size: CGFloat, state: SpecimenState = .earned) {
        self.species = species
        self.colourway = colourway
        self.size = size
        self.state = state
    }

    public var body: some View {
        let metrics = SpecimenMetrics(size: size)
        ZStack(alignment: .top) {
            switch state {
            case .earned:
                contactShadow(metrics)
                leaf
            case .next(let progress):
                skeleton(next: true)
                    .progressFill(
                        fraction: ProgressHairline.clamped(progress),
                        colour: Color(colourway.color(for: species)),
                        opacity: 0.4
                    )
                    .frame(width: size, height: size)
            case .locked:
                skeleton(next: false).frame(width: size, height: size)
            case .needsPermission:
                skeleton(next: false).frame(width: size, height: size).opacity(0.5)
            case .dormant:
                skeleton(next: false).frame(width: size, height: size).opacity(0.35)
            case .waiting:
                BudGlyph(waiting: true, glow: .still)
                    .frame(width: size * 0.75, height: size * 0.75)
                    .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: metrics.height, alignment: .top)
        .background(alignment: .top) {
            if state == .earned {
                bloom(metrics)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isImage)
    }

    // MARK: Parts

    private var leaf: some View {
        LeafView(species, fill: .colourway(colourway))
            .frame(width: size, height: size)
            .overlay {
                // Frost leaves carry a thin white rim from 14pt up (spec §6.1).
                if colourway.hasFrostRim(for: species) && size >= 14 {
                    LeafView(species, style: .skeleton(stroke: .white.opacity(0.4), vein: .clear, outlineWidth: 0.75))
                        .frame(width: size, height: size)
                }
            }
    }

    private func skeleton(next: Bool) -> LeafView {
        let colors = theme.colors
        let style: LeafStyle
        if size >= SpecimenMetrics.detailSize {
            // Detail and reveal: a finer neutral skeleton, whether or not it is a next rung (spec §5.6).
            style = .skeleton(
                stroke: colors.textSecondary.opacity(0.55), vein: colors.textSecondary.opacity(0.35),
                outlineWidth: 1.25, veinWidth: 0.75
            )
        } else if next {
            style = .skeleton(stroke: colors.seasonTint(season).opacity(0.6), vein: .white.opacity(0.15))
        } else {
            style = .skeleton(stroke: colors.skeletonStroke, vein: colors.skeletonVein)
        }
        return LeafView(species, style: style)
    }

    private func bloom(_ metrics: SpecimenMetrics) -> some View {
        let cap = size >= SpecimenMetrics.detailSize
            ? theme.elevation.detailLeafBloomCap : theme.elevation.tileLeafBloomCap
        let colour = Color(colourway.color(for: species))
        let radius = metrics.bloomRadius
        return Circle()
            .fill(RadialGradient(
                stops: [
                    .init(color: colour.opacity(cap), location: 0),
                    .init(color: colour.opacity(cap * 0.62), location: 0.3),
                    .init(color: colour.opacity(cap * 0.22), location: 0.65),
                    .init(color: colour.opacity(0), location: 1),
                ],
                center: .center, startRadius: 0, endRadius: radius
            ))
            .frame(width: radius * 2, height: radius * 2)
            // Centred on the leaf's square, not on the frame, which includes the shadow.
            .offset(y: size / 2 - radius)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func contactShadow(_ metrics: SpecimenMetrics) -> some View {
        Ellipse()
            .fill(theme.colors.scene.contactShadow.opacity(metrics.shadowOpacity / 0.55))
            .frame(width: metrics.shadowSize.width, height: metrics.shadowSize.height)
            .blur(radius: metrics.shadowBlur)
            .offset(y: metrics.shadowCentreY - metrics.shadowSize.height / 2)
            .accessibilityHidden(true)
    }

    private var accessibilityLabel: String {
        if state == .waiting { return "A new leaf is waiting" }
        var parts = [species.displayName]
        switch state {
        case .earned, .waiting: break
        case .next, .locked, .needsPermission, .dormant: parts.append("locked")
        }
        var label = parts.joined(separator: ", ")
        if let approximate = species.confidence.approximateSpokenLabel {
            label += ". " + approximate
        }
        return label
    }
}

/// Bloom and contact-shadow geometry for a specimen of `size` points, scaled between the spec's tile (64pt:
/// bloom r 70, shadow 40 × 5) and detail (200pt: bloom r 180, shadow 120 × 10, blur 10) values.
nonisolated struct SpecimenMetrics {
    /// From here up the specimen is shown at detail scale: the 22% bloom cap and the detail skeleton.
    static let detailSize: CGFloat = 120

    let size: CGFloat

    /// The frame: the leaf's square plus room below for its shadow.
    var height: CGFloat { size * 1.12 }

    var bloomRadius: CGFloat { 0.809 * size + 18.2 }

    /// 40 × 5 at 64pt, 120 × 10 at 200pt.
    var shadowSize: CGSize {
        CGSize(width: max(8, 0.588 * size + 2.35), height: max(3, 0.0368 * size + 2.65))
    }

    /// Black 50% in tiles, 45% in detail (spec §5.5, §5.6).
    var shadowOpacity: Double { size >= Self.detailSize ? 0.45 : 0.5 }

    /// The contact-shadow blur range, 6 to 10 (spec §6.5).
    var shadowBlur: CGFloat { min(10, max(6, 0.0294 * size + 4.12)) }

    /// Just below the leaf's square, where the stalk ends.
    var shadowCentreY: CGFloat { size * 1.02 }
}
