import MapleCore
import SwiftUI

/// The dial's centre leaf (F1 design §4.3): the next hours leaf as a skeleton in season tint, its rung filling
/// from the stalk in two golds (softer for what was saved before this session, brighter for this session's counted
/// time) with a light edge at the fill line. When it opens it cross-fades over 0.6 s to a fully gold leaf with
/// dark veins and a soft glow.
public struct DialLeaf: View {
    @Environment(\.theme) private var theme
    @Environment(\.season) private var season

    private let species: LeafSpecies
    private let fill: DialFill
    /// The glow's size and strength, set by `DialCentre` (and by the finish's pulse).
    var glowScale: Double = 1
    var glowStrength: Double = 0.55

    public init(species: LeafSpecies, fill: DialFill) {
        self.species = species
        self.fill = fill
    }

    public var body: some View {
        let dial = theme.dial
        let opened = fill.opened
        ZStack {
            Circle()
                .fill(EllipticalGradient(
                    colors: [dial.gold.opacity(0.5), dial.gold.opacity(0)], center: .center,
                    startRadiusFraction: 0, endRadiusFraction: 0.5
                ))
                .scaleEffect(1.6 * glowScale)
                .opacity(glowStrength * opened)
            LeafView(
                species,
                style: .skeleton(stroke: theme.colors.seasonTint(season).opacity(0.6), vein: .white.opacity(0.15)),
                progress: fill.leafFill,
                palette: LeafFill.Palette(before: dial.goldSoft, session: dial.gold, edge: dial.goldEdge)
            )
            .opacity(1 - opened)
            LeafView(species, style: LeafStyle(fill: dial.gold, vein: dial.goldVein, detail: .full))
                .opacity(opened)
        }
        .mapleAnimation(theme.motion.gentle, value: opened)
        .accessibilityHidden(true)
    }

    func glowing(scale: Double, strength: Double) -> DialLeaf {
        var leaf = self
        leaf.glowScale = scale
        leaf.glowStrength = strength
        return leaf
    }
}

/// The dial's centre (F1 design §4.3): the leaf above the hero numeral (SF Rounded semibold, its unit smaller in
/// secondary) and a caption, laid out as the mockup lays them out and scaled with the dial. Type follows Dynamic
/// Type up to xxLarge and no further (§5.17); everything moves only by offset and scale, so the receipt's growing
/// leaf animates with transforms alone.
///
/// ```swift
/// DialCentre(leaf: DialLeaf(species: leaf, fill: frame.fill), numeral: DialCentre.numeralParts(FocusTimeText.remaining(left)),
///            caption: "left of 50m", diameter: diameter)
/// ```
public struct DialCentre: View {
    let leaf: DialLeaf?
    let numeral: [NumeralPart]
    let caption: String?
    let diameter: CGFloat
    /// 0…1: the receipt's leaf growing into the centre, the numeral shrinking to 72% beneath it.
    var grow: Double = 0
    /// The finish's glow pulse and fade-ins (Task 7's `finishing(_:)`).
    var glowScale: Double = 1
    var glowOpacity: Double = 1
    var numeralOpacity: Double = 1
    var numeralRise: Double = 0

    /// - Parameters:
    ///   - leaf: The next leaf, or nil for no leaf (a plain timer, the break, an emergency release): the numeral
    ///     then sits a little higher.
    ///   - numeral: "32m" as `[.value("32"), .unit("m")]` (`numeralParts(_:)`).
    ///   - diameter: The dial's diameter.
    public init(leaf: DialLeaf?, numeral: [NumeralPart], caption: String?, diameter: CGFloat) {
        self.leaf = leaf
        self.numeral = numeral
        self.caption = caption
        self.diameter = diameter
    }

    /// The receipt's centre (§4.3): `amount` 1 grows the leaf to fill the centre with the numeral at 72% beneath it.
    public func grown(_ amount: Double) -> DialCentre {
        var centre = self
        centre.grow = amount.isFinite ? min(1, max(0, amount)) : 0
        return centre
    }

    public var body: some View {
        DialCentreBody(centre: self)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .frame(width: diameter, height: diameter)
            .accessibilityElement(children: .combine)
    }

    /// Time text as numeral parts: runs of digits (with ":") are values, runs of letters are units, and spaces go
    /// (the numeral spaces its groups itself). Text with no digits stays one value ("Breathe in").
    nonisolated public static func numeralParts(_ text: String) -> [NumeralPart] {
        guard text.contains(where: \.isNumber) else { return [.value(text)] }
        var parts: [NumeralPart] = []
        var run = ""
        var runIsUnit = false
        for character in text {
            if character == " " {
                if !run.isEmpty { parts.append(NumeralPart(text: run, isUnit: runIsUnit)) }
                run = ""
                continue
            }
            let isUnit = character.isLetter
            if !run.isEmpty && isUnit != runIsUnit {
                parts.append(NumeralPart(text: run, isUnit: runIsUnit))
                run = ""
            }
            run.append(character)
            runIsUnit = isUnit
        }
        if !run.isEmpty { parts.append(NumeralPart(text: run, isUnit: runIsUnit)) }
        return parts
    }
}

/// The centre's sizes and offsets from the dial's centre (y down), scaled from the mockup's 236pt dial:
/// at rest the leaf at −44 (41% of its grown size), the numeral at +4 and the caption at +40; grown, the leaf at −34
/// with the numeral at 72% beneath it; with no leaf, the numeral at −8 and the caption at +28. Larger type pushes
/// the leaf up and the caption down, so nothing overlaps.
nonisolated struct DialCentreLayout: Equatable {
    static let reference: CGFloat = 236
    static let restingLeafScale: CGFloat = 0.41

    let diameter: CGFloat
    let numeralSize: CGFloat
    let captionSize: CGFloat
    let hasLeaf: Bool
    let grow: CGFloat

    init(diameter: CGFloat, numeralBase: CGFloat, captionBase: CGFloat, hasLeaf: Bool, grow: Double) {
        self.diameter = diameter
        let k = diameter / Self.reference
        numeralSize = numeralBase * k
        captionSize = captionBase * k
        self.hasLeaf = hasLeaf
        self.grow = hasLeaf && grow.isFinite ? CGFloat(min(1, max(0, grow))) : 0
    }

    private var k: CGFloat { diameter / Self.reference }
    /// The grown leaf's side; at rest it is scaled to 41% of it.
    var leafSide: CGFloat { 98 * k }
    var leafScale: CGFloat { mix(Self.restingLeafScale, 1) }
    var numeralScale: CGFloat { mix(1, 0.72) }
    var leafY: CGFloat {
        mix(restingNumeralY - numeralSize / 2 - leafSide * Self.restingLeafScale / 2 - 4 * k, grownLeafY)
    }
    var numeralY: CGFloat { mix(restingNumeralY, grownNumeralY) }
    var captionY: CGFloat {
        let resting = restingNumeralY + numeralSize / 2 + captionSize * 0.6 + (hasLeaf ? 6 : 5) * k
        let grown = grownNumeralY + numeralSize * 0.36 + captionSize * 0.6 + 2 * k
        return mix(resting, grown)
    }
    /// The opened leaf's glow: 55% while running, full on the receipt.
    var glowStrength: Double { 0.55 + 0.45 * Double(grow) }

    private var restingNumeralY: CGFloat { (hasLeaf ? 4 : -8) * k }
    private var grownLeafY: CGFloat { -34 * k }
    private var grownNumeralY: CGFloat { grownLeafY + leafSide / 2 + numeralSize * 0.36 }

    private func mix(_ start: CGFloat, _ end: CGFloat) -> CGFloat {
        start + (end - start) * grow
    }
}

private struct DialCentreBody: View {
    @Environment(\.theme) private var theme
    @ScaledMetric(relativeTo: .largeTitle) private var numeralBase: CGFloat = 48
    @ScaledMetric(relativeTo: .subheadline) private var captionBase: CGFloat = 12

    let centre: DialCentre

    var body: some View {
        let layout = DialCentreLayout(
            diameter: centre.diameter, numeralBase: numeralBase, captionBase: captionBase,
            hasLeaf: centre.leaf != nil, grow: centre.grow
        )
        ZStack {
            if let leaf = centre.leaf {
                leaf.glowing(scale: centre.glowScale, strength: layout.glowStrength * centre.glowOpacity)
                    .frame(width: layout.leafSide, height: layout.leafSide)
                    .scaleEffect(layout.leafScale)
                    .offset(y: layout.leafY)
            }
            numeral(size: layout.numeralSize)
                .frame(maxWidth: centre.diameter * 0.74)
                .scaleEffect(layout.numeralScale)
                .offset(y: layout.numeralY + centre.numeralRise)
                .opacity(centre.numeralOpacity)
            if let caption = centre.caption {
                Text(caption)
                    .font(.system(size: layout.captionSize, design: .rounded))
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: centre.diameter * 0.7)
                    .offset(y: layout.captionY)
            }
        }
        .frame(width: centre.diameter, height: centre.diameter)
    }

    /// The numeral: digits in `textPrimary` with the hero's tracking, units at 27/48 of the size in `textSecondary`,
    /// and a word space before a value that follows a unit ("1h 30m").
    private func numeral(size: CGFloat) -> some View {
        let parts = centre.numeral
        return HStack(alignment: .firstTextBaseline, spacing: 1) {
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                Text(part.text)
                    .font(part.isUnit ? MapleFont.numeralUnit(size: size * 27 / 48) : MapleFont.numeral(size: size))
                    .tracking(part.isUnit ? 0 : -1.5 * size / 48)
                    .foregroundStyle(part.isUnit ? theme.colors.textSecondary : theme.colors.textPrimary)
                    .padding(.leading, index > 0 && !part.isUnit && parts[index - 1].isUnit ? size * 0.14 : 0)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }
}
