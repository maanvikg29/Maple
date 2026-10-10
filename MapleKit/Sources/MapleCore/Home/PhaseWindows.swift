import Foundation

/// Where each phase of the member's day starts (spec §3.3), from wake W, wind-down start D and bedtime B:
///
/// | Phase | Window |
/// |---|---|
/// | Morning | W − 60m → W + 3h |
/// | Day | W + 3h → D − 2h (empty if negative) |
/// | Evening | D − 2h → D |
/// | Wind-down | D → B |
/// | Night | B → W − 60m |
///
/// Windows wrap midnight. When the day would be negative it is empty and the morning ends at the evening's start.
public struct PhaseWindows: Sendable, Equatable {
    private static let minutesPerDay = 24 * 60

    public let schedule: SleepSchedule
    /// Minutes since midnight at which the morning starts.
    private let origin: Int
    /// Each later phase's start, in minutes after the morning's start (non-decreasing).
    private let dayOffset: Int, eveningOffset: Int, windDownOffset: Int, nightOffset: Int

    public init(schedule: SleepSchedule) {
        self.schedule = schedule
        let day = Self.minutesPerDay
        origin = Self.wrap(schedule.wake.minutesSinceMidnight - 60)
        windDownOffset = Self.wrap(schedule.windDownStart.minutesSinceMidnight - origin)
        nightOffset = min(day, windDownOffset + max(0, schedule.windDownMinutes))
        eveningOffset = max(0, windDownOffset - 120)
        dayOffset = min(4 * 60, eveningOffset)
    }

    /// The phase at `minuteOfDay` (0…1439).
    public func phase(minuteOfDay: Int) -> NowPhase {
        let t = Self.wrap(minuteOfDay - origin)
        if t >= nightOffset { return .night }
        if t >= windDownOffset { return .windDown }
        if t >= eveningOffset { return .evening }
        if t >= dayOffset { return .day }
        return .morning
    }

    /// Minutes since midnight at which `phase` starts.
    public func startMinute(of phase: NowPhase) -> Int {
        Self.wrap(origin + offset(of: phase))
    }

    /// The first start of `phase` strictly after `date`.
    public func nextStart(of phase: NowPhase, after date: Date, calendar: Calendar) -> Date {
        let minute = startMinute(of: phase)
        let parts = DateComponents(hour: minute / 60, minute: minute % 60, second: 0)
        return calendar.nextDate(after: date, matching: parts, matchingPolicy: .nextTime) ?? date
    }

    /// A representative moment inside `phase` on the local day of `date`: the wireframe's moments where they fit
    /// (evening 1h 20m before wind-down, wind-down 38m before bed), otherwise the middle of the window.
    /// DEBUG `-MapleDemoPhase` freezes the clock here.
    public func sampleDate(in phase: NowPhase, onDayOf date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        func at(_ offset: Int) -> Date {
            calendar.date(byAdding: .minute, value: Self.wrap(origin + offset), to: start) ?? start
        }
        let lower = offset(of: phase)
        let upper = end(of: phase)
        let preferred: Int = switch phase {
        case .morning: 90
        case .day: (lower + upper) / 2
        case .evening: windDownOffset - 80
        case .windDown: nightOffset - 38
        case .night: nightOffset + 90
        }
        let target = (lower..<upper).contains(preferred) ? preferred : (lower + upper) / 2
        let candidate = at(target)
        if NowPhase.resolve(date: candidate, schedule: schedule, calendar: calendar) == phase { return candidate }
        // Daylight-saving days: walk the day for the first minute in the phase.
        for minute in stride(from: 0, to: Self.minutesPerDay, by: 1) {
            guard let moment = calendar.date(byAdding: .minute, value: minute, to: start) else { continue }
            if NowPhase.resolve(date: moment, schedule: schedule, calendar: calendar) == phase { return moment }
        }
        return candidate
    }

    private func offset(of phase: NowPhase) -> Int {
        switch phase {
        case .morning: 0
        case .day: dayOffset
        case .evening: eveningOffset
        case .windDown: windDownOffset
        case .night: nightOffset
        }
    }

    private func end(of phase: NowPhase) -> Int {
        switch phase {
        case .morning: dayOffset
        case .day: eveningOffset
        case .evening: windDownOffset
        case .windDown: nightOffset
        case .night: Self.minutesPerDay
        }
    }

    private static func wrap(_ minutes: Int) -> Int {
        ((minutes % minutesPerDay) + minutesPerDay) % minutesPerDay
    }
}

extension NowPhase {
    /// The phase at `date` for the member's schedule, in `calendar`'s time zone (spec §3.3).
    public static func resolve(date: Date, schedule: SleepSchedule, calendar: Calendar = .current) -> NowPhase {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return PhaseWindows(schedule: schedule).phase(minuteOfDay: (parts.hour ?? 0) * 60 + (parts.minute ?? 0))
    }
}
