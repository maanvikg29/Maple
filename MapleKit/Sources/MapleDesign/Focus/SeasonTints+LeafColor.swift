import MapleCore

extension Theme.SeasonTints {
    /// The standard theme's season tints as plain 0xRRGGBB values, for a surface that can't read `Theme`: the Live
    /// Activity's Lock Screen leaf (F1 design §5.11), which is season tint and never gold. They must equal
    /// `Theme.maple`'s tints; `LiveActivitySketchTests` checks every season.
    nonisolated public static func leafColor(for season: Season) -> LeafColor {
        switch season {
        case .spring: LeafColor(0xBFD8A6)
        case .summer: LeafColor(0x9CC3A4)
        case .autumn: LeafColor(0xE3A49E)
        case .winter: LeafColor(0xC9DDEE)
        }
    }
}
