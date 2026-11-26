import Foundation

/// The drawn clock that sets a session's length (syrup van design §6.2). Pure.
///
/// The long hand is the minutes past the hour and the short hand follows it, as on any clock, so a length reads as a
/// time: 1 hour 30 has the long hand at 6 and the short hand half-way between 1 and 2. Lengths keep today's limits and
/// step (`DialLayout`).
public struct ClockSetting: Sendable, Equatable {
    public private(set) var minutes: Int

    public init(minutes: Int) {
        self.minutes = Self.allowed(minutes)
    }

    /// The long hand, in degrees clockwise from 12.
    public var minuteAngle: Double { Double(minutes % 60) * 6 }
    /// The short hand, in degrees clockwise from 12: 30 degrees an hour.
    public var hourAngle: Double { Double(minutes) * 0.5 }
    /// The digits in the hub: "0:50", "1:30".
    public var hubText: String {
        let part = minutes % 60
        return "\(minutes / 60):\(part < 10 ? "0" : "")\(part)"
    }

    public var wholeHours: Int { minutes / 60 }
    /// How much of the face the syrup colour fills: the part of the hour the long hand has swept.
    public var faceFill: Double { Double(minutes % 60) / 60 }

    /// Moves the long hand to `degrees` (clockwise from 12) by the shortest way round. Passing the top adds or takes
    /// away an hour. The hand stops at the limits.
    /// - Returns: Whether the length changed, for the tick.
    @discardableResult
    public mutating func turn(toAngle degrees: Double) -> Bool {
        guard degrees.isFinite else { return false }
        let wrapped = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let step = DialLayout.stepMinutes
        let target = (Int((wrapped / 6 / Double(step)).rounded()) * step) % 60
        var delta = (target - minutes % 60 + 60) % 60
        if delta >= 30 { delta -= 60 }
        return set(minutes + delta)
    }

    /// Moves by whole steps of 5 minutes: the minus and plus buttons, and VoiceOver's adjust.
    @discardableResult
    public mutating func nudge(_ steps: Int) -> Bool {
        let (moved, overflow) = steps.multipliedReportingOverflow(by: DialLayout.stepMinutes)
        return set(overflow ? (steps < 0 ? DialLayout.minimumMinutes : DialLayout.maximumMinutes) : minutes + moved)
    }

    /// The angle of a touch `dx` to the right of and `dy` below the clock's centre, clockwise from 12.
    public static func angle(dx: Double, dy: Double) -> Double {
        let degrees = atan2(dx, -dy) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }

    private mutating func set(_ value: Int) -> Bool {
        let next = min(max(value, DialLayout.minimumMinutes), DialLayout.maximumMinutes)
        guard next != minutes else { return false }
        minutes = next
        return true
    }

    private static func allowed(_ value: Int) -> Int {
        let step = DialLayout.stepMinutes
        let snapped = Int((Double(value) / Double(step)).rounded()) * step
        return min(max(snapped, DialLayout.minimumMinutes), DialLayout.maximumMinutes)
    }
}
