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
/// With a weekly schedule the times come from two nights: a day's morning and day follow **last night's** wake (the
/// night that woke into it), and its evening, wind-down and night follow **tonight's** schedule (the night named by
/// that day's evening, `WeeklySleepSchedule.schedule(forNight:calendar:)`). So on a Saturday–Sunday weekend, Friday's
/// evening already runs to the weekend bedtime, and Monday's morning starts from the weekday wake.
///
/// Windows wrap midnight and are worked out as dates (`NightTimes`), so they follow daylight-saving changes. When the
/// day would be negative it is empty and the morning ends at the evening's start; no window ever runs past the next
/// morning's start.
public struct PhaseWindows: Sendable, Equatable {
    public let weekly: WeeklySleepSchedule

    /// The same schedule every night.
    public init(schedule: SleepSchedule) {
        self.init(weekly: .everyNight(schedule))
    }

    public init(weekly: WeeklySleepSchedule) {
        self.weekly = weekly
    }

    /// One local day's phases, as dates: from its morning's start to the next morning's start.
    public struct Day: Sendable, Equatable {
        /// The day; it also names tonight's night.
        public let day: LocalDay
        public let morning: Date
        public let dayStart: Date
        public let evening: Date
        public let windDown: Date
        public let night: Date
        /// The next morning's start, where this day ends.
        public let end: Date

        /// The phase at `date`, which must fall inside the day.
        public func phase(at date: Date) -> NowPhase {
            if date >= night { return .night }
            if date >= windDown { return .windDown }
            if date >= evening { return .evening }
            if date >= dayStart { return .day }
            return .morning
        }

        public func contains(_ date: Date) -> Bool {
            morning <= date && date < end
        }

        public func start(of phase: NowPhase) -> Date {
            switch phase {
            case .morning: morning
            case .day: dayStart
            case .evening: evening
            case .windDown: windDown
            case .night: night
            }
        }

        public func end(of phase: NowPhase) -> Date {
            switch phase {
            case .morning: dayStart
            case .day: evening
            case .evening: windDown
            case .windDown: night
            case .night: end
            }
        }
    }

    /// The phases of `day`: its morning from last night's wake, the rest from tonight's schedule.
    public func day(_ day: LocalDay, calendar: Calendar) -> Day {
        let lastNight = weekly.times(forNight: day.adding(days: -1, calendar: calendar), calendar: calendar)
        let tonight = weekly.times(forNight: day, calendar: calendar)
        return Self.day(day, lastNight: lastNight, tonight: tonight)
    }

    private static func day(_ day: LocalDay, lastNight: NightTimes, tonight: NightTimes) -> Day {
        func clamp(_ date: Date, _ lower: Date, _ upper: Date) -> Date { min(max(date, lower), upper) }
        let morning = lastNight.morningStart
        let end = max(tonight.morningStart, morning)
        let night = clamp(tonight.bedtime, morning, end)
        let windDown = clamp(tonight.windDownStart, morning, night)
        let evening = clamp(windDown.addingTimeInterval(-2 * 3600), morning, windDown)
        let dayStart = min(lastNight.wake.addingTimeInterval(3 * 3600), evening)
        return Day(day: day, morning: morning, dayStart: max(morning, dayStart), evening: evening, windDown: windDown,
                   night: night, end: end)
    }

    /// The day whose phases hold `date`: usually its own calendar day, or yesterday in the hours before this morning's
    /// start.
    public func day(containing date: Date, calendar: Calendar) -> Day {
        let today = LocalDay(date, calendar: calendar)
        // Nights from three evenings ago to tomorrow's cover every day that can hold `date`.
        let nights = (-3...1).map { weekly.times(forNight: today.adding(days: $0, calendar: calendar), calendar: calendar) }
        // The latest day that holds it, so a schedule whose nights overlap still has one answer.
        for index in stride(from: nights.count - 1, through: 1, by: -1) {
            let candidate = Self.day(nights[index].night, lastNight: nights[index - 1], tonight: nights[index])
            if candidate.contains(date) { return candidate }
        }
        return Self.day(today, lastNight: nights[2], tonight: nights[3])
    }

    /// The phase at `date` in `calendar`'s time zone.
    public func phase(at date: Date, calendar: Calendar) -> NowPhase {
        day(containing: date, calendar: calendar).phase(at: date)
    }

    /// The first start of `phase` strictly after `date`.
    public func nextStart(of phase: NowPhase, after date: Date, calendar: Calendar) -> Date {
        let current = day(containing: date, calendar: calendar).day
        for offset in 0...8 {
            let start = day(current.adding(days: offset, calendar: calendar), calendar: calendar).start(of: phase)
            if start > date { return start }
        }
        return date
    }

    /// A representative moment inside `phase` on the calendar day of `date`: the wireframe's moments where they fit
    /// (evening 1h 20m before wind-down, wind-down 38m before bed), otherwise the middle of the window. A window that
    /// starts after midnight (a late wind-down or the night) is taken from the night that began the evening before,
    /// so the moment stays on that calendar day. DEBUG `-MapleDemoPhase` freezes the clock here.
    public func sampleDate(in phase: NowPhase, onDayOf date: Date, calendar: Calendar) -> Date {
        let today = LocalDay(date, calendar: calendar)
        let dayStart = today.startDate(in: calendar)
        let dayEnd = today.adding(days: 1, calendar: calendar).startDate(in: calendar)
        // The phase's window on this calendar day, from today's phases and from yesterday's (whose wind-down and
        // night can run past midnight), with the moment the wireframe prefers in it.
        let windows: [(lower: Date, upper: Date, preferred: Date)] = [today, today.adding(days: -1, calendar: calendar)].compactMap { candidate in
            let phases = day(candidate, calendar: calendar)
            let lower = max(phases.start(of: phase), dayStart)
            let upper = min(phases.end(of: phase), dayEnd)
            guard lower < upper else { return nil }
            let middle = lower.addingTimeInterval((upper.timeIntervalSince(lower) / 120).rounded(.down) * 60)
            let preferred: Date = switch phase {
            case .morning: phases.morning.addingTimeInterval(90 * 60)
            case .day: middle
            case .evening: phases.windDown.addingTimeInterval(-80 * 60)
            case .windDown: phases.night.addingTimeInterval(-38 * 60)
            case .night: phases.night.addingTimeInterval(90 * 60)
            }
            return (lower, upper, preferred)
        }
        let preferred = windows.first { $0.preferred >= $0.lower && $0.preferred < $0.upper }.map(\.preferred)
        let middles = windows.map { $0.lower.addingTimeInterval(($0.upper.timeIntervalSince($0.lower) / 120).rounded(.down) * 60) }
        for moment in [preferred].compactMap({ $0 }) + middles where self.phase(at: moment, calendar: calendar) == phase {
            return moment
        }
        // Daylight-saving days and squeezed windows: walk the day for the first minute in the phase.
        for minute in stride(from: 0, to: 24 * 60, by: 1) {
            guard let moment = calendar.date(byAdding: .minute, value: minute, to: dayStart) else { continue }
            if self.phase(at: moment, calendar: calendar) == phase { return moment }
        }
        return dayStart
    }
}

extension NowPhase {
    /// The phase at `date` for a schedule that is the same every night, in `calendar`'s time zone (spec §3.3).
    public static func resolve(date: Date, schedule: SleepSchedule, calendar: Calendar = .current) -> NowPhase {
        resolve(date: date, weekly: .everyNight(schedule), calendar: calendar)
    }

    /// The phase at `date` for the member's weekly schedule, in `calendar`'s time zone (spec §3.3).
    public static func resolve(date: Date, weekly: WeeklySleepSchedule, calendar: Calendar = .current) -> NowPhase {
        PhaseWindows(weekly: weekly).phase(at: date, calendar: calendar)
    }
}
