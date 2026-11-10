import Foundation

/// The Focus tab's time words (F1 design §4.4, F1-5): calm minutes, with seconds only in the last minute.
public enum FocusTimeText {
    /// "32m" (whole minutes, rounded up) from 60 seconds left; "0:SS" (seconds rounded up) below. 60 seconds reads
    /// "1m", never "0:60".
    public static func remaining(_ seconds: Double) -> String {
        let left = max(0, seconds)
        let wholeSeconds = Int((left - 1e-9).rounded(.up))
        if wholeSeconds >= 60 {
            return HomeFormat.duration(minutes: Int((left / 60 - 1e-9).rounded(.up)))
        }
        return wholeSeconds < 10 ? "0:0\(max(0, wholeSeconds))" : "0:\(wholeSeconds)"
    }

    /// "32 minutes left", "45 seconds left".
    public static func spokenRemaining(_ seconds: Double, locale: Locale) -> String {
        let left = max(0, seconds)
        let wholeSeconds = Int((left - 1e-9).rounded(.up))
        if wholeSeconds >= 60 {
            return HomeFormat.spokenDuration(minutes: Int((left / 60 - 1e-9).rounded(.up)), locale: locale) + " left"
        }
        return "\(max(0, wholeSeconds)) \(wholeSeconds == 1 ? "second" : "seconds") left"
    }

    /// "50m", "1h", "1h 30m".
    public static func length(minutes: Int) -> String {
        HomeFormat.duration(minutes: minutes)
    }

    /// "1 hour, 30 minutes".
    public static func spokenLength(minutes: Int, locale: Locale) -> String {
        HomeFormat.spokenDuration(minutes: minutes, locale: locale)
    }
}
