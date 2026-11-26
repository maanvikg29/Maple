import Foundation

/// How the camera goes into the van (syrup van design §5.3). Pure.
public enum VanEntrance: Sendable, Equatable {
    /// The whole entrance: once a day.
    case full
    /// Every other time that day.
    case short
    /// With Reduce Motion on.
    case crossFade

    public var seconds: Double {
        switch self {
        case .full: 1.2
        case .short: 0.45
        case .crossFade: 0.3
        }
    }

    public static func style(lastFull: Date?, now: Date, calendar: Calendar, reduceMotion: Bool) -> VanEntrance {
        if reduceMotion { return .crossFade }
        guard let lastFull, calendar.isDate(lastFull, inSameDayAs: now) else { return .full }
        return .short
    }
}
