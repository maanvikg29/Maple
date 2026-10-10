import Foundation

/// The colour of a species' leaves *on the tree* for the current season (spec §4.7). The tree always follows the
/// real season; a leaf's pressed colourway (the season it was earned in) belongs to the herbarium.
public enum TreeFoliage {
    /// One species' tree colour today.
    public struct Tone: Sendable, Equatable {
        public var fill: LeafColor
        /// Opacity of the thin white frost rim (0 = none). Drawn only on leaves of 14 pt and larger.
        public var frostRim: Double
    }

    /// Days a deciduous species may take to turn in autumn: each turns on its own seeded day in this window.
    public static let autumnTurningDays = 21
    /// Days over which winter frost reaches each deciduous species.
    public static let winterFrostDays = 10
    /// Spring flower dots show on this many first days of spring.
    public static let springFlowerDays = 21

    /// The tone of `species` on a tree grown from `seed`, `seasonDay` days into `season`.
    /// Before the season's on-tree treatment: no desaturation, phase brightness or vitality yet.
    public static func tone(for species: LeafSpecies, season: Season, seasonDay: Int, seed: UInt64) -> Tone {
        let summer = LeafColourway.summer.color(for: species)
        switch season {
        case .spring:
            return Tone(fill: species.evergreen ? species.summerColor : LeafColourway.spring.color(for: species), frostRim: 0)
        case .summer:
            return Tone(fill: summer, frostRim: 0)
        case .autumn:
            if species.evergreen || species.autumn == .staysGreen {
                return Tone(fill: LeafColourway.autumn.color(for: species), frostRim: 0)
            }
            let turned = turning(day: seasonDay, at: turnDay(species, seed: seed), over: 4)
            return Tone(fill: summer.mixed(with: species.autumnColor, amount: turned), frostRim: 0)
        case .winter:
            if species.evergreen {
                // Deep own green, with a fainter rim so evergreens visibly stand out.
                let deep = species.summerColor.lightened(by: -0.04)
                return Tone(fill: deep, frostRim: 0.25)
            }
            let frosted = turning(day: seasonDay, at: frostDay(species, seed: seed), over: 2)
            let frost = LeafColourway.frost.color(for: species)
            return Tone(fill: species.autumnColor.mixed(with: frost, amount: frosted), frostRim: 0.4 * frosted)
        }
    }

    /// The seeded day (0..<21) a deciduous species turns its autumn colour.
    public static func turnDay(_ species: LeafSpecies, seed: UInt64) -> Int {
        var rng = SplitMix64(seed: SplitMix64.derive(seed, "autumn.\(species.id)"))
        return Int(rng.unit() * Double(autumnTurningDays))
    }

    /// The seeded day (0..<10) frost reaches a deciduous species.
    public static func frostDay(_ species: LeafSpecies, seed: UInt64) -> Int {
        var rng = SplitMix64(seed: SplitMix64.derive(seed, "winter.\(species.id)"))
        return Int(rng.unit() * Double(winterFrostDays))
    }

    /// Days since the start of the current (meteorological) season: 0 on the 1st of its first month.
    public static func seasonDay(for date: Date, hemisphere: Hemisphere, calendar: Calendar = .current) -> Int {
        let season = Season(for: date, hemisphere: hemisphere, calendar: calendar)
        let firstNorthernMonth = switch season {
        case .spring: 3
        case .summer: 6
        case .autumn: 9
        case .winter: 12
        }
        let firstMonth = hemisphere == .northern ? firstNorthernMonth : (firstNorthernMonth + 5) % 12 + 1
        let today = calendar.startOfDay(for: date)
        var components = calendar.dateComponents([.year], from: today)
        components.month = firstMonth
        components.day = 1
        guard var start = calendar.date(from: components) else { return 0 }
        if start > today, let previous = calendar.date(byAdding: .year, value: -1, to: start) {
            start = previous
        }
        return max(0, calendar.dateComponents([.day], from: start, to: today).day ?? 0)
    }

    /// 0 before `start`, rising smoothly to 1 over `days` days.
    private static func turning(day: Int, at start: Int, over days: Double) -> Double {
        TreeMath.smoothstep((Double(day - start) + 1) / days)
    }
}
