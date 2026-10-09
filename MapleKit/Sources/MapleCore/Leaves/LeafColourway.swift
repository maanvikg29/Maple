import Foundation

/// The colour a leaf is drawn in. A leaf's *pressed* colourway is the season it was earned in, and never changes;
/// leaves on the tree follow the current season instead.
public enum LeafColourway: String, Codable, Sendable, CaseIterable {
    case spring, summer, autumn, frost

    /// The permanent colourway for a leaf earned in `season`. Evergreens are always pressed green.
    public static func pressed(in season: Season, evergreen: Bool) -> LeafColourway {
        if evergreen { return .summer }
        switch season {
        case .spring: return .spring
        case .summer: return .summer
        case .autumn: return .autumn
        case .winter: return .frost
        }
    }

    public var displayName: String {
        switch self {
        case .spring: "Spring"
        case .summer: "Summer"
        case .autumn: "Autumn"
        case .frost: "Frost"
        }
    }

    /// The fill colour of `species` in this colourway (design spec §6.1).
    public func color(for species: LeafSpecies) -> LeafColor {
        switch self {
        case .summer:
            return species.summerColor.lightened(by: 0.06)
        case .spring:
            return species.summerColor.mixed(with: LeafColor(0xD8E8B0), amount: 0.25)
        case .autumn:
            return species.autumn == .staysGreen ? species.autumnColor.lightened(by: 0.06) : species.autumnColor
        case .frost:
            // Evergreens never frost; they keep their deep green.
            return species.evergreen
                ? species.summerColor
                : species.autumnColor.mixed(with: LeafColor(0xC9DCE8), amount: 0.6)
        }
    }

    /// Whether leaves in this colourway get a thin white rim when drawn at 14pt or larger.
    public func hasFrostRim(for species: LeafSpecies) -> Bool {
        self == .frost && !species.evergreen
    }
}

extension LeafColor {
    /// Linear blend toward `other` by `amount` (0 = self, 1 = other).
    public func mixed(with other: LeafColor, amount: Double) -> LeafColor {
        func blend(_ a: Int, _ b: Int) -> Int { Int((Double(a) + (Double(b) - Double(a)) * amount).rounded()) }
        return LeafColor(red: blend(red, other.red), green: blend(green, other.green), blue: blend(blue, other.blue))
    }

    /// The colour with its HSL lightness raised by `amount` (0...1), clamped.
    public func lightened(by amount: Double) -> LeafColor {
        let (h, s, l) = hsl
        return LeafColor(hue: h, saturation: s, lightness: min(1, max(0, l + amount)))
    }

    /// The colour with its HSL saturation scaled by `factor`.
    public func desaturated(by fraction: Double) -> LeafColor {
        let (h, s, l) = hsl
        return LeafColor(hue: h, saturation: min(1, max(0, s * (1 - fraction))), lightness: l)
    }

    /// Hue in degrees, saturation and lightness in 0...1.
    public var hsl: (hue: Double, saturation: Double, lightness: Double) {
        let r = Double(red) / 255, g = Double(green) / 255, b = Double(blue) / 255
        let maxC = max(r, g, b), minC = min(r, g, b)
        let lightness = (maxC + minC) / 2
        let delta = maxC - minC
        guard delta > 0 else { return (0, 0, lightness) }
        let saturation = delta / (1 - abs(2 * lightness - 1))
        let hue: Double
        switch maxC {
        case r: hue = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6)
        case g: hue = 60 * ((b - r) / delta + 2)
        default: hue = 60 * ((r - g) / delta + 4)
        }
        return ((hue + 360).truncatingRemainder(dividingBy: 360), saturation, lightness)
    }
}
