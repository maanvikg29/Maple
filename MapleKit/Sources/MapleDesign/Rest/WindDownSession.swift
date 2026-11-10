import Foundation
import MapleCore

/// The evening's wind-down facts and their rules (spec §8.1, §3.4): when wind-down mode was opened, and when the
/// member said Goodnight (their phone-down time). Pure and Codable; the app keeps one in a small JSON file.
///
/// - Wind-down is offered in the evening and wind-down phases only, so only a start then counts.
/// - It stays active, and Home and Rest say "Return to wind-down", from that start until Goodnight or the end of
///   the wind-down phase, whichever comes first.
/// - The morning reads last night's Goodnight as the "in bed" time when Apple Health has nothing.
nonisolated public struct WindDownSession: Codable, Sendable, Equatable {
    public var startedAt: Date?
    public var goodnightAt: Date?

    public init(startedAt: Date? = nil, goodnightAt: Date? = nil) {
        self.startedAt = startedAt
        self.goodnightAt = goodnightAt
    }

    /// Whether `phase` offers "Start wind-down".
    public static func offersWindDown(in phase: NowPhase) -> Bool {
        phase == .evening || phase == .windDown
    }

    /// Records a start at `date` when wind-down is offered then and isn't already on.
    /// - Returns: Whether the start was recorded.
    @discardableResult
    public mutating func start(at date: Date, schedule: WeeklySleepSchedule, calendar: Calendar) -> Bool {
        guard Self.offersWindDown(in: NowPhase.resolve(date: date, weekly: schedule, calendar: calendar)),
              !isActive(at: date, schedule: schedule, calendar: calendar) else { return false }
        startedAt = date
        return true
    }

    /// Goodnight: the phone goes down at `date`.
    public mutating func sayGoodnight(at date: Date) {
        goodnightAt = date
    }

    /// Wind-down was opened this evening and Goodnight hasn't been said since.
    public func isActive(at date: Date, schedule: WeeklySleepSchedule, calendar: Calendar) -> Bool {
        guard let startedAt, startedAt <= date else { return false }
        if let goodnightAt, goodnightAt >= startedAt { return false }
        let today = PhaseWindows(weekly: schedule).day(containing: date, calendar: calendar)
        guard Self.offersWindDown(in: today.phase(at: date)) else { return false }
        // This evening's start (tonight's schedule: a weekend night's later evening on Fridays).
        return startedAt >= today.evening
    }

    /// Last night's Goodnight, for the morning: the last one, if it was within the 20 hours before `date`.
    public func goodnight(forMorningOf date: Date) -> Date? {
        guard let goodnightAt, goodnightAt <= date, date.timeIntervalSince(goodnightAt) < 20 * 3600 else { return nil }
        return goodnightAt
    }
}
