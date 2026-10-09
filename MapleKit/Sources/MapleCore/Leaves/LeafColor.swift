import Foundation

/// A colour stored as 0xRRGGBB, so MapleCore stays free of UI frameworks.
public struct LeafColor: Codable, Sendable, Hashable {
    public var rgb: UInt32

    public init(_ rgb: UInt32) {
        self.rgb = rgb & 0xFF_FFFF
    }

    public init(red: Int, green: Int, blue: Int) {
        self.init(UInt32(Self.clamp(red)) << 16 | UInt32(Self.clamp(green)) << 8 | UInt32(Self.clamp(blue)))
    }

    /// CSS-style HSL. `hue` in degrees, `saturation` and `lightness` in 0...1.
    public init(hue: Double, saturation: Double, lightness: Double) {
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let sector = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let second = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let (r, g, b): (Double, Double, Double) = switch Int(sector) {
        case 0: (chroma, second, 0)
        case 1: (second, chroma, 0)
        case 2: (0, chroma, second)
        case 3: (0, second, chroma)
        case 4: (second, 0, chroma)
        default: (chroma, 0, second)
        }
        let match = lightness - chroma / 2
        self.init(
            red: Int(((r + match) * 255).rounded()),
            green: Int(((g + match) * 255).rounded()),
            blue: Int(((b + match) * 255).rounded())
        )
    }

    public var red: Int { Int(rgb >> 16 & 0xFF) }
    public var green: Int { Int(rgb >> 8 & 0xFF) }
    public var blue: Int { Int(rgb & 0xFF) }

    /// The darker tone used for veins, stalk and outline: the fill at 55% brightness, as in the original drawings.
    public var veinColor: LeafColor {
        func dim(_ channel: Int) -> Int { Int((Double(channel) * 0.55).rounded(.down)) }
        return LeafColor(red: dim(red), green: dim(green), blue: dim(blue))
    }

    /// Whether each channel is within `tolerance` of another colour.
    public func isClose(to other: LeafColor, tolerance: Int) -> Bool {
        abs(red - other.red) <= tolerance && abs(green - other.green) <= tolerance && abs(blue - other.blue) <= tolerance
    }

    private static func clamp(_ value: Int) -> Int {
        min(max(value, 0), 255)
    }
}
