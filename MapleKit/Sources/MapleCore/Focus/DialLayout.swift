import Foundation

/// The minute-marks dial's arithmetic (F1 design §4.1, §4.5). Angles are radians clockwise from 12 o'clock.
public struct DialLayout: Sendable, Equatable {
    public static let minimumMinutes = 20
    public static let maximumMinutes = 180
    public static let stepMinutes = 5
    /// 30° of turn is one 5-minute step, so a full turn is an hour.
    public static let degreesPerStep = 30.0

    /// Proportions on a 200-unit box.
    public static let box = 200.0
    public static let outerRadius = 92.0
    public static let longInnerRadius = 80.0
    public static let shortInnerRadius = 84.0
    public static let gapInnerRadius = 86.0
    public static let stroke = 1.6
    public static let currentStroke = 2.2
    public static let dotRadius = 99.0
    public static let dotSize = 2.6

    public let plannedMinutes: Int
    /// 1 up to an hour, 2 up to 2 hours, 3 beyond.
    public let minutesPerMark: Int
    public let markCount: Int

    public init(plannedMinutes: Int) {
        let minutes = max(1, plannedMinutes)
        self.plannedMinutes = minutes
        minutesPerMark = minutes <= 60 ? 1 : minutes <= 120 ? 2 : 3
        markCount = (minutes + minutesPerMark - 1) / minutesPerMark
    }

    /// Mark `index` of `markCount` sits at index / markCount of a full turn.
    public func angle(ofMark index: Int) -> Double {
        2 * .pi * Double(index) / Double(markCount)
    }

    public func isLong(_ index: Int) -> Bool { index % 5 == 0 }

    /// The mark the session is in after `seconds`, from 0 to the last mark.
    public func mark(atElapsed seconds: Double) -> Int {
        min(markCount - 1, max(0, Int(seconds / Double(60 * minutesPerMark))))
    }

    /// Where `minute` of the session falls (the leaf dot). It uses the marks' own scale, a full turn being
    /// `markCount × minutesPerMark` minutes, so the dot lands on a mark even when the length isn't a multiple of
    /// `minutesPerMark` (65 minutes has 33 marks of 2 minutes: minute 64 sits on mark 32). That product is
    /// `plannedMinutes` whenever the length is a multiple of `minutesPerMark`.
    public func angle(atMinute minute: Double) -> Double {
        2 * .pi * minute / Double(markCount * minutesPerMark)
    }

    /// The length after turning the dial by `degrees` from `minutes`: whole 5-minute steps, each taken at its halfway
    /// point so the dial settles on the nearer length, 20 minutes to 3 hours.
    public static func length(turning degrees: Double, from minutes: Int) -> Int {
        stepped(minutes, by: Int((degrees / degreesPerStep).rounded(.toNearestOrAwayFromZero)))
    }

    /// `minutes` moved by `steps` 5-minute steps (VoiceOver's adjustable action), within the range.
    public static func stepped(_ minutes: Int, by steps: Int) -> Int {
        min(maximumMinutes, max(minimumMinutes, minutes + steps * stepMinutes))
    }
}
