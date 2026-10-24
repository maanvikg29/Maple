import Foundation
import MapleFocusCore

/// What a session can still count: the minute the next hours leaf would open (the dial's leaf dot), and the start
/// screen's counts line (F1 design §4.1, §5.1, §5.4, §5.8).
public struct SessionForecast: Sendable, Equatable {
    /// The start screen's counts line.
    public enum CountsLine: Sendable, Equatable {
        /// A plain timer, a selection that doesn't qualify, or nothing to say.
        case hidden
        /// The first session ever: the definition (focus spec §3.3).
        case definition
        case afterBedtime
        case capReached
        /// The session runs past bedtime, so it counts until then.
        case untilBed(Date)
        case reaches(leaf: String, minute: Int)
        case toward(leaf: String, minutesToGo: Int)

        public func text(locale: Locale, calendar: Calendar) -> String? {
            switch self {
            case .hidden: nil
            case .definition: "Time your chosen apps stayed locked while you were awake."
            case .afterBedtime: "After bedtime · this won't count"
            case .capReached: "6h counted today · more won't add"
            case .untilBed(let bedtime):
                "Counts until bed at \(HomeFormat.clock(HomeFormat.clockTime(of: bedtime, calendar: calendar), locale: locale))"
            case .reaches(let leaf, let minute): "You'll reach \(leaf) at minute \(minute)"
            case .toward(let leaf, let minutes): "Counts toward \(leaf) · \(HomeFormat.duration(minutes: minutes)) to go"
            }
        }
    }

    /// The minute from the countdown's start at which the next hours leaf would open; nil when it is out of this
    /// session's reach (the dot is hidden).
    public let leafMinute: Int?
    public let countsLine: CountsLine

    /// - Parameters:
    ///   - start: The countdown's start (now, on the start screen).
    ///   - now: The present; time before it has already been counted.
    ///   - secondsToLeaf: Counted seconds still needed for the next hours leaf (display credit included), or nil
    ///     when there is none.
    ///   - roomLeftToday: Seconds of today's 6 hours still free.
    public init(
        start: Date, plannedSeconds: Int, window: AwakeWindow, now: Date, canCount: Bool, secondsToLeaf: Int?,
        leafName: String?, roomLeftToday: Int, firstEver: Bool
    ) {
        let plannedEnd = start.addingTimeInterval(TimeInterval(plannedSeconds))
        let from = max(now, window.start)
        let countable = max(0, min(plannedEnd, window.end).timeIntervalSince(from))
        let reach = min(Double(max(0, roomLeftToday)), countable)
        if canCount, let needed = secondsToLeaf, needed > 0, Double(needed) <= reach {
            leafMinute = Int(((from.timeIntervalSince(start) + Double(needed)) / 60 - 1e-9).rounded(.up))
        } else {
            leafMinute = nil
        }

        if !canCount {
            countsLine = .hidden
        } else if now >= window.end || (!window.contains(now) && plannedEnd <= window.start) {
            // A start in the sleep window freezes the next day's window (`AwakeWindow.frozen(at:)`): when the session
            // ends before that window opens, nothing of it can count.
            countsLine = .afterBedtime
        } else if roomLeftToday <= 0 {
            countsLine = .capReached
        } else if firstEver {
            countsLine = .definition
        } else if plannedEnd > window.end {
            countsLine = .untilBed(window.end)
        } else if let leafName, let minute = leafMinute {
            countsLine = .reaches(leaf: leafName, minute: minute)
        } else if let leafName, let needed = secondsToLeaf, needed > 0 {
            countsLine = .toward(leaf: leafName, minutesToGo: Int((Double(needed) / 60 - 1e-9).rounded(.up)))
        } else {
            countsLine = .hidden
        }
    }

    /// "Field maple · 17m to go".
    public static func leafLine(leaf: String, secondsToGo: Int) -> String {
        "\(leaf) · \(HomeFormat.duration(minutes: Int((Double(max(0, secondsToGo)) / 60 - 1e-9).rounded(.up)))) to go"
    }

    /// "Field maple is yours · it opens after this session", or "… opens in the morning" when it is held.
    public static func openedLine(leaf: String, heldUntilMorning: Bool) -> String {
        "\(leaf) is yours · it opens \(heldUntilMorning ? "in the morning" : "after this session")"
    }

    /// "2 new leaves are yours".
    public static func openedLine(count: Int) -> String {
        "\(count) new leaves are yours"
    }
}
