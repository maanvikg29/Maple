import Foundation

/// Which half of the world the user lives in. Seasons, and so leaf colours and the tree, flip between them.
public enum Hemisphere: String, Codable, Sendable, CaseIterable {
    case northern
    case southern

    /// Regions that lie wholly or mostly south of the equator. Anything else is treated as northern;
    /// the user can always override this in Settings.
    private static let southernRegions: Set<String> = [
        "AO", "AR", "AU", "BO", "BR", "BW", "CL", "FJ", "ID", "LS", "MG", "MU", "MW", "MZ",
        "NA", "NC", "NZ", "PE", "PF", "PG", "PY", "SB", "SZ", "TO", "UY", "VU", "WS", "ZA", "ZM", "ZW",
    ]

    public init(regionCode: String?) {
        guard let code = regionCode?.uppercased() else {
            self = .northern
            return
        }
        self = Self.southernRegions.contains(code) ? .southern : .northern
    }

    /// Best guess from the device's region setting.
    public static var current: Hemisphere {
        Hemisphere(regionCode: Locale.current.region?.identifier)
    }
}

/// The real-world season, using meteorological boundaries (whole months).
public enum Season: String, Codable, Sendable, CaseIterable {
    case spring
    case summer
    case autumn
    case winter

    public init(for date: Date, hemisphere: Hemisphere, calendar: Calendar = .current) {
        let month = calendar.component(.month, from: date)
        // Shift southern dates by six months so one lookup table serves both hemispheres.
        let northernMonth = hemisphere == .northern ? month : (month + 5) % 12 + 1
        switch northernMonth {
        case 3...5: self = .spring
        case 6...8: self = .summer
        case 9...11: self = .autumn
        default: self = .winter
        }
    }
}
