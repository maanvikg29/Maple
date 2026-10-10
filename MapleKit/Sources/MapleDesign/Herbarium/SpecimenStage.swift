import MapleCore
import SwiftUI

/// Leaf detail's hero (spec §5.6): a 300pt stage with the leaf at 200pt and its resting tilt, on a 22% bloom of its
/// own colour (r 180) above a 120 × 10 contact shadow. An earned leaf sways ±1.5° over 8s from its stalk; under
/// Reduce Motion it is still. A locked leaf is its skeleton, filling from the stalk when it is a next rung; a
/// waiting leaf is the amber bud, breathing.
public struct SpecimenStage: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let species: LeafSpecies
    private let colourway: LeafColourway
    private let state: SpecimenState

    public static let height: CGFloat = 300
    public static let leafSize: CGFloat = 200
    /// The sway's amplitude, in degrees either side of the resting tilt.
    static let swayDegrees = 1.5

    public init(species: LeafSpecies, colourway: LeafColourway, state: SpecimenState) {
        self.species = species
        self.colourway = colourway
        self.state = state
    }

    public var body: some View {
        Group {
            switch state {
            case .waiting:
                BudGlyph(waiting: true)
                    .frame(width: 128, height: 128)
            case .earned:
                if reduceMotion {
                    specimen
                } else {
                    specimen.phaseAnimator([-Self.swayDegrees, Self.swayDegrees]) { content, angle in
                        // Turning about the stalk, where the leaf would hang from its twig.
                        content.rotationEffect(.degrees(angle), anchor: UnitPoint(x: 0.5, y: 1 / 1.12))
                    } animation: { _ in
                        .easeInOut(duration: theme.motion.swayPeriod / 2)
                    }
                }
            case .next(let progress):
                nextRung(progress)
            case .locked, .needsPermission, .dormant:
                specimen
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
    }

    /// A next rung at 200pt: the detail skeleton with its progress rising from the stalk. A fill this large reads
    /// heavier than a tile's, so it is lighter here (30% against the tiles' 40%).
    private func nextRung(_ progress: Double) -> some View {
        let colors = theme.colors
        return LeafView(species, style: .skeleton(
            stroke: colors.textSecondary.opacity(0.55), vein: colors.textSecondary.opacity(0.35),
            outlineWidth: 1.25, veinWidth: 0.75
        ))
        .progressFill(fraction: ProgressHairline.clamped(progress), colour: Color(colourway.color(for: species)), opacity: 0.3)
        .frame(width: Self.leafSize, height: Self.leafSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(species.displayName), locked")
    }

    private var specimen: some View {
        SpecimenView(species: species, colourway: colourway, size: Self.leafSize, state: state)
            // The frame includes room for the shadow below the leaf's square; centre the square itself.
            .offset(y: Self.leafSize * 0.06)
    }
}

/// The specimen label (spec §5.6): native range, regions, leaf form, autumn colour, series, evergreen, the note
/// and, for approximate drawings, the accuracy line. Level 1, radius 28, 48pt rows with white 6% dividers.
public struct SpecimenLabel: View {
    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let species: LeafSpecies

    public init(species: LeafSpecies) {
        self.species = species
    }

    public var body: some View {
        VStack(spacing: 0) {
            row("Native range") { valueText(species.range) }
            divider
            row("Regions") {
                ChipFlow(spacing: 6, lineSpacing: 6, alignment: stacked ? .leading : .trailing) {
                    ForEach(species.regions, id: \.self) { region in
                        SmallChip(region.displayName)
                    }
                }
            }
            divider
            row("Leaf") { valueText(HerbariumCopy.leafDescription(species)) }
            divider
            row("Autumn colour") {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(species.autumn.color))
                        .frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                    valueText(species.autumn.displayName)
                }
            }
            divider
            row("Series") { valueText(species.series) }
            if species.evergreen {
                divider
                row("Evergreen") { valueText("Stays green all year") }
            }
            if !species.note.isEmpty {
                divider
                block("Note") {
                    Text(species.note)
                        .font(MapleFont.scientific(.subheadline))
                        .foregroundStyle(theme.colors.textSecondary)
                }
            }
            if let accuracy = species.confidence.accuracyNote {
                divider
                block("Accuracy") {
                    Text(accuracy)
                        .font(MapleFont.callout)
                        .foregroundStyle(theme.colors.textSecondary)
                }
            }
        }
        .surface(.level1, radius: theme.radius.largeTile)
    }

    private var stacked: Bool { dynamicTypeSize.isAccessibilitySize }

    /// Label left, value right; label above value at accessibility sizes.
    @ViewBuilder
    private func row<Value: View>(_ label: String, @ViewBuilder value: () -> Value) -> some View {
        Group {
            if stacked {
                VStack(alignment: .leading, spacing: 4) {
                    labelText(label)
                    value()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    labelText(label)
                    Spacer(minLength: 0)
                    value()
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
        .frame(minHeight: theme.spacing.labelRow)
        .accessibilityElement(children: .combine)
    }

    /// A label over a paragraph, for the note and the accuracy line.
    private func block<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            labelText(label)
            content()
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }

    private func labelText(_ text: String) -> some View {
        Text(text)
            .font(MapleFont.callout)
            .foregroundStyle(theme.colors.textSecondary)
            .layoutPriority(1)
    }

    private func valueText(_ text: String) -> some View {
        Text(text)
            .font(MapleFont.callout)
            .foregroundStyle(theme.colors.textPrimary)
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.colors.divider)
            .frame(height: 0.5)
            .padding(.leading, 20)
            .accessibilityHidden(true)
    }
}
