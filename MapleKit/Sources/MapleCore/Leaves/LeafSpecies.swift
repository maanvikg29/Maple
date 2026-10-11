import Foundation

/// One collectible maple species, decoded from `Resources/species.json` (the source of truth).
/// Field names follow the supplied catalogue; see `Catalog/HANDOFF.md`.
public struct LeafSpecies: Codable, Sendable, Hashable, Identifiable {
    public enum Form: String, Codable, Sendable, CaseIterable {
        case palmate, unlobed, trifoliate, pinnate, palmcompound
    }

    public enum Margin: Int, Codable, Sendable, CaseIterable {
        case smooth = 0, toothed = 1, doubleToothed = 2
    }

    public enum AutumnColor: String, Codable, Sendable, CaseIterable {
        case crimson = "R", scarlet = "S", orange = "O", gold = "Y", staysGreen = "G"

        public var color: LeafColor {
            switch self {
            case .crimson: LeafColor(0xB3312B)
            case .scarlet: LeafColor(0xD2462A)
            case .orange: LeafColor(0xD9782B)
            case .gold: LeafColor(0xD1A020)
            case .staysGreen: LeafColor(0x3F6D3B)
            }
        }
    }

    /// How well documented the leaf is. Inferred and placeholder leaves must be presented as approximate.
    public enum Confidence: String, Codable, Sendable, CaseIterable {
        case documented = "k", inferred = "i", placeholder = "u"

        public var isApproximate: Bool { self != .documented }
    }

    public enum Region: String, Codable, Sendable, CaseIterable {
        case eastAsia = "EA"
        case himalaya = "HM"
        case southeastAsia = "SEA"
        case westCentralAsia = "WA"
        case europe = "EU"
        case northAfrica = "AF"
        case northAmerica = "NA"
        case centralAmerica = "CA"

        public var displayName: String {
            switch self {
            case .eastAsia: "East Asia"
            case .himalaya: "Himalaya"
            case .southeastAsia: "Southeast Asia"
            case .westCentralAsia: "West & Central Asia"
            case .europe: "Europe"
            case .northAfrica: "North Africa"
            case .northAmerica: "North America"
            case .centralAmerica: "Mexico & Central America"
            }
        }
    }

    public let id: String
    /// Scientific name, shown in italics.
    public let name: String
    /// English name, or "" when the species has none.
    public let common: String
    public let series: String
    public let range: String
    public let regions: [Region]
    public let form: Form
    /// Lobe count (palmate) or leaflet count (compound forms).
    public let lobes: Int
    /// 0...1, how deep the lobes cut (palmate only).
    public let depth: Double
    public let margin: Margin
    public let evergreen: Bool
    public let autumn: AutumnColor
    public let confidence: Confidence
    public let note: String
    /// The species' IUCN Red List assessment, when the Red List of Maples (or the IUCN) has one Maple could check;
    /// nil otherwise. Data: docs/design/iucn-maples.json.
    public let conservation: Conservation?

    public struct Conservation: Codable, Sendable, Hashable {
        public let category: RedListCategory
        /// The year of the assessment.
        public let year: Int
        /// The page that states it.
        public let source: String
        /// One short sourced fact, e.g. "Fewer than 500 wild trees".
        public let note: String?

        public init(category: RedListCategory, year: Int, source: String, note: String?) {
            self.category = category
            self.year = year
            self.source = source
            self.note = note
        }
    }

    /// The English name when there is one, otherwise the scientific name.
    public var displayName: String {
        common.isEmpty ? name : common
    }

    /// The species' summer green, identical to the original generator's `summerGreen(id)`.
    public var summerColor: LeafColor {
        let hue = 95 + StableHash.unitInterval(id) * 30
        let lightness = 30 + StableHash.unitInterval(id + "l") * 10
        return LeafColor(hue: hue, saturation: 0.42, lightness: lightness / 100)
    }

    /// Autumn colour, as in the original drawings (evergreens use the "stays green" tone).
    public var autumnColor: LeafColor {
        autumn.color
    }

    /// The small fixed tilt each leaf is drawn with, identical to the original generator.
    public var restingTiltDegrees: Double {
        (StableHash.unitInterval(id + "r") - 0.5) * 16
    }
}

/// IUCN Red List categories Maple shows.
public enum RedListCategory: String, Codable, Sendable, CaseIterable {
    case cr = "CR", en = "EN", vu = "VU", nt = "NT", lc = "LC", dd = "DD"

    public var displayName: String {
        switch self {
        case .cr: "Critically endangered"
        case .en: "Endangered"
        case .vu: "Vulnerable"
        case .nt: "Near threatened"
        case .lc: "Least concern"
        case .dd: "Data deficient"
        }
    }

    /// Critically endangered, Endangered or Vulnerable.
    public var isThreatened: Bool { self == .cr || self == .en || self == .vu }
}

/// The FNV-1a hash the original JavaScript generator used, so per-species variation matches exactly.
enum StableHash {
    static func unitInterval(_ string: String) -> Double {
        var hash: UInt32 = 2_166_136_261
        for unit in string.utf16 {
            hash ^= UInt32(unit)
            hash = hash &* 16_777_619
        }
        return Double(hash) / 4_294_967_295
    }
}
