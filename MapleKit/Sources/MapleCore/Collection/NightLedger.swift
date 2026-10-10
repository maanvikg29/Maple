import Foundation

/// How a night's bedtime went, judged from the Goodnight tap in wind-down mode (spec §5.1, rewards.md).
public enum BedtimeOutcome: String, Codable, Sendable {
    /// Goodnight from 2 hours before bedtime to 30 minutes after it.
    case onTime
    /// Goodnight more than 30 minutes after bedtime.
    case late
    /// Goodnight more than 2 hours before bedtime (for example when ill): neutral, never counted against the member.
    case early
    /// No Goodnight that night: not a tracked night.
    case untracked

    /// Late and untracked nights are slips for a bedtime run (so skipping the tap never helps); early ones aren't.
    public var isSlip: Bool { self == .late || self == .untracked }
    /// The night counts as tracked (Nights tracked).
    public var isTracked: Bool { self != .untracked }
}

/// The Goodnight taps and settled nights behind the sleep categories: Nights tracked, On-time bedtimes, Bedtime runs,
/// Steady weeks and Seasons in rhythm, and the nights vitality reads (spec §4.8, §5.1; rewards.md). Pure and Codable;
/// `CollectionSnapshot` keeps one and turns what it settles into counters.
///
/// - A night runs 18:00 to 18:00 local and belongs to the evening it starts on.
/// - Goodnight is the phone-down time. The last tap of a night counts, judged against the bedtime in force when it
///   was tapped: on time from bedtime − 2 h to bedtime + 30 min, early before that, late after.
/// - A night is settled once, after the next morning starts (wake − 60 min). A night without a tap is untracked.
/// - The first night that counts is the one the schedule was first saved on, if that was at least 30 minutes before
///   its bedtime; otherwise the next one.
/// - A run continues while at least 5 of every 7 nights are on time: up to 2 slips in any 7 nights of a run are
///   forgiven, and a third ends it. Early nights are neutral.
/// - A week (the calendar's own, so the locale's first weekday) is steady when 5 or more of its nights are on time;
///   it counts when its last night is settled. A season counts once 8 of its weeks are steady.
public struct NightLedger: Codable, Sendable, Equatable {
    /// One Goodnight tap, waiting for its night to be settled.
    public struct Goodnight: Codable, Sendable, Hashable {
        public var night: LocalDay
        public var at: Date
        /// The bedtime in force when it was tapped.
        public var bedtime: ClockTime

        public init(night: LocalDay, at: Date, bedtime: ClockTime) {
            self.night = night
            self.at = at
            self.bedtime = bedtime
        }
    }

    /// One settled night.
    public struct Night: Codable, Sendable, Hashable {
        public var night: LocalDay
        public var outcome: BedtimeOutcome

        public init(night: LocalDay, outcome: BedtimeOutcome) {
            self.night = night
            self.outcome = outcome
        }
    }

    /// What settling one night changed.
    public struct Settled: Sendable, Equatable {
        public var night: LocalDay
        public var outcome: BedtimeOutcome
        /// The live bedtime run after this night.
        public var run: Int
        /// This night closed a week with 5 or more on-time nights.
        public var closedSteadyWeek: Bool
        /// That steady week was its season's eighth.
        public var completedSeason: Bool
    }

    static let nightsKept = 14
    static let steadyWeeksKept = 20
    /// After a longer absence only the last two weeks are settled one by one; every night before them was untracked.
    static let catchUpLimit = 14
    static let lateAfter: TimeInterval = 30 * 60
    static let earlyBefore: TimeInterval = 2 * 3600
    /// Steady weeks a season needs (of its 13).
    static let steadyWeeksPerSeason = 8

    /// Taps for nights not settled yet, oldest first.
    public var goodnights: [Goodnight]
    /// The last night settled; nil until the first.
    public var settledThrough: LocalDay?
    /// The last 14 settled nights, oldest first: the run's 7-night window and the week being closed.
    public var recent: [Night]
    /// The first on-time night of the live run.
    public var runStart: LocalDay?
    /// The last night of each recent steady week, oldest first.
    public var steadyWeeks: [LocalDay]

    public init(
        goodnights: [Goodnight] = [], settledThrough: LocalDay? = nil, recent: [Night] = [], runStart: LocalDay? = nil,
        steadyWeeks: [LocalDay] = []
    ) {
        self.goodnights = goodnights
        self.settledThrough = settledThrough
        self.recent = recent
        self.runStart = runStart
        self.steadyWeeks = steadyWeeks
    }

    // MARK: Rules

    /// The night `date` belongs to: the evening it began on (nights run 18:00 to 18:00).
    public static func night(containing date: Date, calendar: Calendar) -> LocalDay {
        LocalDay(calendar.date(byAdding: .hour, value: -18, to: date) ?? date, calendar: calendar)
    }

    /// `time` on `night`: that evening, or the next morning for a time before 18:00.
    public static func date(_ time: ClockTime, on night: LocalDay, calendar: Calendar) -> Date {
        let day = time.hour >= 18 ? night : night.adding(days: 1, calendar: calendar)
        let parts = DateComponents(year: day.year, month: day.month, day: day.day, hour: time.hour, minute: time.minute)
        return calendar.date(from: parts) ?? day.startDate(in: calendar)
    }

    /// When `night` can be settled: the next morning's start, an hour before wake time.
    public static func settleDate(of night: LocalDay, schedule: SleepSchedule, calendar: Calendar) -> Date {
        let morning = night.adding(days: 1, calendar: calendar)
        let parts = DateComponents(year: morning.year, month: morning.month, day: morning.day,
                                   hour: schedule.wake.hour, minute: schedule.wake.minute)
        return (calendar.date(from: parts) ?? morning.startDate(in: calendar)).addingTimeInterval(-3600)
    }

    /// On time, late or early, against the bedtime on that night; untracked without a tap.
    public static func outcome(goodnight: Date?, bedtime: Date) -> BedtimeOutcome {
        guard let goodnight else { return .untracked }
        let offset = goodnight.timeIntervalSince(bedtime)
        if offset > lateAfter { return .late }
        if offset < -earlyBefore { return .early }
        return .onTime
    }

    /// The first night that counts: the night the schedule was first saved on, when that was at least 30 minutes
    /// before its bedtime (rewards.md), otherwise the next.
    public static func firstNight(setUpAt setup: Date, schedule: SleepSchedule, calendar: Calendar) -> LocalDay {
        let night = night(containing: setup, calendar: calendar)
        let bedtime = date(schedule.bedtime, on: night, calendar: calendar)
        return setup <= bedtime.addingTimeInterval(-30 * 60) ? night : night.adding(days: 1, calendar: calendar)
    }

    /// The three-month block a day falls in (Mar–May, Jun–Aug, Sep–Nov, Dec–Feb), the same in both hemispheres.
    static func seasonBlock(of day: LocalDay) -> Int {
        let shifted = (day.month + 9) % 12            // March 0 … February 11
        let year = day.month < 3 ? day.year - 1 : day.year
        return year * 4 + shifted / 3
    }

    // MARK: Changes

    /// Records a Goodnight tap. A later tap the same night replaces it; a tap for a settled night is ignored.
    /// - Returns: Whether it was recorded.
    @discardableResult
    public mutating func recordGoodnight(at date: Date, bedtime: ClockTime, calendar: Calendar) -> Bool {
        let night = Self.night(containing: date, calendar: calendar)
        if let settledThrough, night <= settledThrough { return false }
        goodnights.removeAll { $0.night == night }
        goodnights.append(Goodnight(night: night, at: date, bedtime: bedtime))
        goodnights.sort { $0.night < $1.night }
        if goodnights.count > Self.nightsKept { goodnights.removeFirst(goodnights.count - Self.nightsKept) }
        return true
    }

    /// Settles, oldest first, every night from `first` whose next morning has started by `date`.
    /// - Parameters:
    ///   - first: The first night that counts (`firstNight(setUpAt:schedule:calendar:)`).
    ///   - run: The live bedtime run before these nights.
    /// - Returns: One entry per night settled; empty when nothing was due.
    public mutating func settle(
        at date: Date, from first: LocalDay, run: Int, schedule: SleepSchedule, calendar: Calendar
    ) -> [Settled] {
        var last = Self.night(containing: date, calendar: calendar)
        for _ in 0..<3 where Self.settleDate(of: last, schedule: schedule, calendar: calendar) > date {
            last = last.adding(days: -1, calendar: calendar)
        }
        guard Self.settleDate(of: last, schedule: schedule, calendar: calendar) <= date else { return [] }
        var next = settledThrough.map { max(first, $0.adding(days: 1, calendar: calendar)) } ?? first
        guard next <= last else { return [] }

        var run = max(0, run)
        let catchUp = last.adding(days: -(Self.catchUpLimit - 1), calendar: calendar)
        if next < catchUp {
            // Away for weeks: the nights before the last two were untracked, which ended any run long ago.
            next = catchUp
            run = 0
            runStart = nil
            recent.removeAll()
        }

        var settled: [Settled] = []
        var night = next
        while night <= last {
            settled.append(settleOne(night, run: &run, calendar: calendar))
            night = night.adding(days: 1, calendar: calendar)
        }
        goodnights.removeAll { $0.night <= last }
        settledThrough = last
        return settled
    }

    private mutating func settleOne(_ night: LocalDay, run: inout Int, calendar: Calendar) -> Settled {
        let tap = goodnights.last { $0.night == night }
        let outcome = tap.map {
            Self.outcome(goodnight: $0.at, bedtime: Self.date($0.bedtime, on: night, calendar: calendar))
        } ?? .untracked
        recent.append(Night(night: night, outcome: outcome))
        if recent.count > Self.nightsKept { recent.removeFirst(recent.count - Self.nightsKept) }

        switch outcome {
        case .onTime:
            if run == 0 { runStart = night }
            run += 1
        case .early:
            break
        case .late, .untracked:
            if run > 0, let start = runStart {
                let window = max(start, night.adding(days: -6, calendar: calendar))
                let slips = recent.filter { $0.night >= window && $0.outcome.isSlip }.count
                if slips >= 3 {
                    run = 0
                    runStart = nil
                }
            }
        }

        var closedSteadyWeek = false
        var completedSeason = false
        if let week = calendar.dateInterval(of: .weekOfYear, for: night.startDate(in: calendar).addingTimeInterval(12 * 3600)) {
            let weekStart = LocalDay(week.start, calendar: calendar)
            let weekEnd = LocalDay(week.end.addingTimeInterval(-1), calendar: calendar)
            if night == weekEnd {
                let onTime = recent.filter { $0.night >= weekStart && $0.night <= weekEnd && $0.outcome == .onTime }.count
                if onTime >= 5 {
                    closedSteadyWeek = true
                    steadyWeeks.append(weekEnd)
                    if steadyWeeks.count > Self.steadyWeeksKept {
                        steadyWeeks.removeFirst(steadyWeeks.count - Self.steadyWeeksKept)
                    }
                    let season = Self.seasonBlock(of: weekEnd)
                    completedSeason = steadyWeeks.filter { Self.seasonBlock(of: $0) == season }.count == Self.steadyWeeksPerSeason
                }
            }
        }
        return Settled(night: night, outcome: outcome, run: run, closedSteadyWeek: closedSteadyWeek, completedSeason: completedSeason)
    }
}
