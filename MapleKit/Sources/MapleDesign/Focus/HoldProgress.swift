import Foundation

/// A press-and-hold's progress as a pure value (F1 design §4.7, F1-22). It fills over the hold's length while
/// pressed and drains back at the same rate when let go early. It can instead be filled by a countdown, which is
/// what the hold's named accessibility action starts. `HoldButton` keeps one in its state and samples it on a
/// timer; tests drive it with plain dates.
nonisolated public struct HoldProgress: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        /// Empty and still.
        case idle
        /// Pressed, or counting down.
        case filling
        /// Let go or interrupted before it filled: draining at the rate it filled.
        case draining
        /// Full: the hold has done its job.
        case complete
    }

    private enum Motion: Sendable, Equatable { case still, filling, draining }

    /// Rounding slack, so a fill that reaches 1 through sums of fractions still counts as full.
    private static let slack = 1e-9

    /// The hold's length in seconds: 1.5 to start Locked, 3 to end Steady early, 10 for an emergency release.
    public let duration: TimeInterval
    /// The progress when the current fill or drain began.
    private var level: Double = 0
    private var since = Date(timeIntervalSinceReferenceDate: 0)
    private var motion = Motion.still
    /// The fill is a countdown started by the accessibility action, not a press.
    public private(set) var isCountdown = false
    /// The hold filled and `finish()` was called: it stays full until `reset()`.
    public private(set) var isComplete = false

    public init(duration: TimeInterval) {
        self.duration = duration.isFinite && duration > 0 ? duration : 1
    }

    /// The share of a `duration`-long hold that `seconds` of holding fills, 0…1.
    public static func progress(heldFor seconds: TimeInterval, duration: TimeInterval) -> Double {
        guard !seconds.isNaN else { return 0 }
        guard duration > 0 else { return seconds > 0 ? 1 : 0 }
        return min(1, max(0, seconds / duration))
    }

    /// What is left of `level` after `seconds` let go: it drains at the rate a hold fills.
    public static func drained(from level: Double, releasedFor seconds: TimeInterval, duration: TimeInterval) -> Double {
        max(0, min(1, level) - progress(heldFor: seconds, duration: duration))
    }

    /// The progress at `date`, 0…1.
    public func value(at date: Date) -> Double {
        if isComplete { return 1 }
        let elapsed = date.timeIntervalSince(since)
        switch motion {
        case .still: return level
        case .filling: return min(1, level + Self.progress(heldFor: elapsed, duration: duration))
        case .draining: return Self.drained(from: level, releasedFor: elapsed, duration: duration)
        }
    }

    /// Pressed or counting down, and not yet finished.
    public var isFilling: Bool { motion == .filling && !isComplete }

    /// Whether a fill has reached the end at `date` (the button then calls `finish()` and completes).
    public func isFilled(at date: Date) -> Bool {
        isFilling && value(at: date) >= 1 - Self.slack
    }

    public func phase(at date: Date) -> Phase {
        if isComplete { return .complete }
        switch motion {
        case .still: return .idle
        case .filling: return value(at: date) >= 1 - Self.slack ? .complete : .filling
        case .draining: return value(at: date) > 0 ? .draining : .idle
        }
    }

    /// Whole seconds until the fill completes, rounded up (the countdown's "8s"); the whole length when not filling.
    public func secondsLeft(at date: Date) -> Int {
        let remaining = isFilling ? (1 - value(at: date)) * duration : duration
        return max(0, Int((remaining - Self.slack).rounded(.up)))
    }

    /// A finger goes down: it fills from wherever it is, so a hold pressed again mid-drain carries on from there.
    public mutating func press(at date: Date) {
        fill(from: date, countdown: false)
    }

    /// The named accessibility action: a countdown fills it over the same length, as if held.
    public mutating func startCountdown(at date: Date) {
        fill(from: date, countdown: true)
    }

    /// Let go, interrupted or cancelled: it drains from wherever it is. Never completes.
    public mutating func release(at date: Date) {
        guard !isComplete, motion == .filling else { return }
        level = value(at: date)
        since = date
        motion = .draining
        isCountdown = false
    }

    /// The hold filled: it stays full and ignores everything until `reset()`.
    public mutating func finish() {
        level = 1
        motion = .still
        isCountdown = false
        isComplete = true
    }

    public mutating func reset() {
        self = HoldProgress(duration: duration)
    }

    private mutating func fill(from date: Date, countdown: Bool) {
        guard !isComplete else { return }
        level = value(at: date)
        since = date
        motion = .filling
        isCountdown = countdown
    }
}
