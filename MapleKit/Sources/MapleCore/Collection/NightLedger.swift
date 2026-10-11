import Foundation

/// How a night's bedtime went: Apple Health's sleep onset against the member's bedtime (rewards.json
/// `on_time_bedtimes`).
public enum BedtimeOutcome: String, Codable, Sendable {
    /// Asleep from 2 hours before bedtime to 30 minutes after it.
    case onTime
    /// Asleep more than 30 minutes after bedtime.
    case late
    /// Asleep more than 2 hours before bedtime (for example when ill): neutral, never counted against the member.
    case early
    /// Tracked, but no schedule was in force yet: the install night, when the first schedule was saved less than
    /// 30 minutes before its bedtime. Neutral.
    case unscheduled
    /// Apple Health has no main sleep episode for the night (or none after setup): not a tracked night.
    case untracked

    /// Late and untracked nights are slips for a bedtime run (so taking the Watch off never helps); early and
    /// unscheduled ones aren't.
    public var isSlip: Bool { self == .late || self == .untracked }
    /// The night counts as tracked (Nights tracked).
    public var isTracked: Bool { self != .untracked }

    /// Late data only ever upgrades a night: untracked, then late, then early or unscheduled, then on time.
    var rank: Int {
        switch self {
        case .untracked: 0
        case .late: 1
        case .early, .unscheduled: 2
        case .onTime: 3
        }
    }
}

/// The nights behind the M1 sleep categories, from Apple Health (rewards.json, spec D9): Nights tracked, On-time
/// bedtimes, Bedtime runs, Steady weeks, Seasons in rhythm, Steady mornings and Full nights, plus the nights vitality
/// reads (spec §4.8). Source-agnostic and pure: it takes `SleepNightObservation`s, whatever read them, and
/// `CollectionSnapshot.recordSleep(_:at:context:engine:)` turns what it settles into counters. There is no manual
/// fallback: a Goodnight tap never reaches it.
///
/// - A night runs 18:00 to 18:00 local and belongs to the evening it starts on.
/// - Counting starts on the install night (the night the first schedule was saved in) when setup finished before
///   that night's sleep began. The schedule that judges a night is the weekly schedule in force at 18:00 that
///   evening, and within it the night's own variant: a night that wakes into a weekend day is judged by the weekend
///   schedule (`WeeklySleepSchedule.times(forNight:calendar:)`). The very first schedule applies to the install
///   night only if it was saved at least 30 minutes before its bedtime.
/// - A night is tracked when Apple Health has a main episode of 3 hours or more. It is on time when sleep onset
///   falls from bedtime − 2 h to bedtime + 30 min (earlier is early: neutral), and a steady morning when final wake
///   is within 30 minutes of the wake time. A full night has asleep time of at least the sleep need − 30 minutes,
///   and needs asleep time (a Watch, a tracker or another app; not iPhone's in-bed estimate).
/// - Bedtime and wake time are read in the time zone the night was spent in (the observation's, else the zone in
///   force when it was recorded), so a flight between a night and its settling never moves them.
/// - A night is settled once its next morning starts (wake − 60 min). Nights with no observation by then are
///   untracked. For 72 hours after that, late data (a Watch syncing) can upgrade it, never downgrade it; recording
///   the same night again changes nothing.
/// - A run continues while at least 5 of every 7 nights are on time: up to 2 slips (late or untracked) in any 7
///   nights of a run are forgiven, and a third ends it. Early and unscheduled nights are neutral.
/// - A week (the calendar's own, so the locale's first weekday) is steady when 5 or more of its nights are on time,
///   counted when its last night settles. A week belongs to the season (Mar–May, Jun–Aug, Sep–Nov, Dec–Feb) that
///   holds its Thursday, and a season counts once 8 of its weeks are steady.
public struct NightLedger: Sendable, Equatable {
    /// What judging a night depends on beyond the ledger itself.
    public struct Rules: Sendable {
        /// When the first schedule was saved (the Sugar maple's unlock): nights before it don't count.
        public var setup: Date
        /// The weekly schedule in force now. Nights that began before a change use the one recorded with
        /// `scheduleChanged(from:at:calendar:)`.
        public var schedule: WeeklySleepSchedule
        /// The member's sleep need in minutes; a full night is at least this − 30 minutes asleep.
        public var sleepNeedMinutes: Int
        public var calendar: Calendar

        public init(setup: Date, schedule: WeeklySleepSchedule, sleepNeedMinutes: Int, calendar: Calendar) {
            self.setup = setup
            self.schedule = schedule
            self.sleepNeedMinutes = sleepNeedMinutes
            self.calendar = calendar
        }
    }

    /// One settled night.
    public struct Night: Codable, Sendable, Hashable {
        public var night: LocalDay
        public var outcome: BedtimeOutcome
        /// Final wake within 30 minutes of the wake time. False for an untracked night.
        public var steadyMorning: Bool
        /// Asleep for the sleep need (less 30 minutes); nil without asleep time (iPhone in-bed data, or untracked).
        public var fullNight: Bool?
        /// The best source the night was recorded from; nil when untracked.
        public var source: SleepSource?
        /// The live bedtime run after this night.
        public var run: Int
        /// The first on-time night of that run; nil when there is no run.
        public var runStart: LocalDay?

        public init(
            night: LocalDay, outcome: BedtimeOutcome, steadyMorning: Bool = false, fullNight: Bool? = nil,
            source: SleepSource? = nil, run: Int = 0, runStart: LocalDay? = nil
        ) {
            self.night = night
            self.outcome = outcome
            self.steadyMorning = steadyMorning
            self.fullNight = fullNight
            self.source = source
            self.run = run
            self.runStart = runStart
        }

        private enum CodingKeys: String, CodingKey {
            case night, outcome, steadyMorning, fullNight, source, run, runStart
        }

        /// Tolerant: missing or unknown values take their defaults, so an older file never fails the collection.
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            night = try c.decode(LocalDay.self, forKey: .night)
            outcome = (try? c.decodeIfPresent(BedtimeOutcome.self, forKey: .outcome)) ?? .untracked
            steadyMorning = (try? c.decodeIfPresent(Bool.self, forKey: .steadyMorning)) ?? false
            fullNight = (try? c.decodeIfPresent(Bool.self, forKey: .fullNight)) ?? nil
            source = (try? c.decodeIfPresent(SleepSource.self, forKey: .source)) ?? nil
            run = (try? c.decodeIfPresent(Int.self, forKey: .run)) ?? 0
            runStart = (try? c.decodeIfPresent(LocalDay.self, forKey: .runStart)) ?? nil
        }
    }

    /// A schedule that was replaced, and the last night it judged. One saved before weekend schedules existed
    /// decodes as the same schedule every night (`WeeklySleepSchedule`'s coding).
    public struct PastSchedule: Codable, Sendable, Hashable {
        public var through: LocalDay
        public var schedule: WeeklySleepSchedule

        public init(through: LocalDay, schedule: WeeklySleepSchedule) {
            self.through = through
            self.schedule = schedule
        }
    }

    /// What recording and settling changed, for the collection to apply.
    public struct Changes: Sendable, Equatable {
        /// Counter increases, by category.
        public var increases: [RewardCategoryID: Double] = [:]
        /// The live bedtime run afterwards; nil when no night touched it.
        public var run: Int?
        /// The longest run reached on the way, for the Bedtime-runs high-water mark.
        public var bestRun = 0
        /// Each tracked night's outcome for vitality (replacing that day's earlier record).
        public var vitality: [NightRecord] = []
        /// Nights settled now, oldest first.
        public var settled: [LocalDay] = []
        /// Settled nights that late data upgraded.
        public var upgraded: [LocalDay] = []

        public init() {}

        public var isEmpty: Bool { settled.isEmpty && upgraded.isEmpty }
    }

    static let nightsKept = 14
    static let steadyWeeksKept = 20
    static let pendingKept = 14
    static let pastSchedulesKept = 64
    /// After a very long absence the nights before the last two years settle as untracked in one step.
    static let longestSettle = 730
    static let lateAfter: TimeInterval = 30 * 60
    static let earlyBefore: TimeInterval = 2 * 3600
    /// The first schedule judges the install night only when it was saved this long before its bedtime.
    static let firstScheduleLead: TimeInterval = 30 * 60
    static let steadyMorningWindow: TimeInterval = 30 * 60
    static let fullNightAllowanceMinutes = 30
    /// A tracked night needs a main sleep episode at least this long.
    public static let minimumEpisode: TimeInterval = 3 * 3600
    /// How long after its morning a settled night still takes late data.
    public static let upgradeWindow: TimeInterval = 72 * 3600
    static let steadyWeekNights = 5
    /// Steady weeks a season needs (of its 13).
    static let steadyWeeksPerSeason = 8

    /// Observations for nights not settled yet, the best per night, oldest first.
    public var pending: [SleepNightObservation]
    /// The last night settled; nil until the first.
    public var settledThrough: LocalDay?
    /// The last 14 settled nights, oldest first: the run's 7-night window, the week being closed, and late upgrades.
    public var recent: [Night]
    /// The Thursday of each recent steady week (it names the week's season), oldest first.
    public var steadyWeeks: [LocalDay]
    /// Replaced schedules still needed to judge nights that aren't settled (or may still be upgraded).
    public var pastSchedules: [PastSchedule]
    /// Apple Health has delivered a night with asleep time (a Watch, a tracker or another app), so Full nights can be
    /// earned (`CollectionSnapshot.permissions(in:)`).
    public var sawAsleepTime: Bool

    public init(
        pending: [SleepNightObservation] = [], settledThrough: LocalDay? = nil, recent: [Night] = [],
        steadyWeeks: [LocalDay] = [], pastSchedules: [PastSchedule] = [], sawAsleepTime: Bool = false
    ) {
        self.pending = pending
        self.settledThrough = settledThrough
        self.recent = recent
        self.steadyWeeks = steadyWeeks
        self.pastSchedules = pastSchedules
        self.sawAsleepTime = sawAsleepTime
    }

    /// The live bedtime run after the last settled night.
    public var run: Int { recent.last?.run ?? 0 }

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

    /// When `night` can be settled under `schedule`: the next morning's start, an hour before that night's wake time
    /// (the weekend wake for a weekend night).
    public static func settleDate(of night: LocalDay, schedule: WeeklySleepSchedule, calendar: Calendar) -> Date {
        schedule.times(forNight: night, calendar: calendar).morningStart
    }

    /// On time, late or early: sleep onset against that night's bedtime.
    public static func outcome(onset: Date, bedtime: Date) -> BedtimeOutcome {
        let offset = onset.timeIntervalSince(bedtime)
        if offset > lateAfter { return .late }
        if offset < -earlyBefore { return .early }
        return .onTime
    }

    /// The install night: the night the first schedule was saved in. It counts when setup finished before that
    /// night's sleep began (rewards.json `nights_tracked`).
    public static func firstNight(setUpAt setup: Date, calendar: Calendar) -> LocalDay {
        night(containing: setup, calendar: calendar)
    }

    /// The weekly schedule that judges `night`: the one in force at 18:00 that evening.
    public func schedule(for night: LocalDay, current: WeeklySleepSchedule) -> WeeklySleepSchedule {
        pastSchedules.first { $0.through >= night }?.schedule ?? current
    }

    /// `night`'s bedtime and wake as it is judged: the weekly schedule in force at 18:00 that evening, and within it
    /// the night's own variant (a night waking into a weekend day uses the weekend schedule), in `calendar`.
    public func times(for night: LocalDay, current: WeeklySleepSchedule, calendar: Calendar) -> NightTimes {
        schedule(for: night, current: current).times(forNight: night, calendar: calendar)
    }

    /// Judges one night from its observation (nil: untracked). Run fields are left at zero. Bedtime and wake time are
    /// read in the zone the night was spent in (`SleepNightObservation.timeZoneIdentifier`), never the one in force
    /// when it settles.
    public func evaluate(_ night: LocalDay, observation: SleepNightObservation?, rules: Rules) -> Night {
        guard let observation, observation.isMainEpisode else { return Night(night: night, outcome: .untracked) }
        let first = Self.firstNight(setUpAt: rules.setup, calendar: rules.calendar)
        // The install night counts only when setup finished before sleep began.
        if night == first, observation.onset <= rules.setup { return Night(night: night, outcome: .untracked) }

        let calendar = observation.calendar(from: rules.calendar)
        let times = times(for: night, current: rules.schedule, calendar: calendar)
        let bedtime = times.bedtime
        let judged = night != first || rules.setup <= bedtime.addingTimeInterval(-Self.firstScheduleLead)
        let outcome = judged ? Self.outcome(onset: observation.onset, bedtime: bedtime) : .unscheduled
        // That day's target wake time (rewards.json `steady_mornings`): the weekend wake after a weekend night.
        let steadyMorning = abs(observation.finalWake.timeIntervalSince(times.wake)) <= Self.steadyMorningWindow
        let fullNight: Bool? = observation.source.hasAsleepTime
            ? (observation.asleepMinutes ?? 0) >= Double(rules.sleepNeedMinutes - Self.fullNightAllowanceMinutes)
            : nil
        return Night(night: night, outcome: outcome, steadyMorning: steadyMorning, fullNight: fullNight,
                     source: observation.source)
    }

    /// The calendar week holding `night`: its first and last days.
    static func week(of night: LocalDay, calendar: Calendar) -> (start: LocalDay, end: LocalDay)? {
        let noon = night.startDate(in: calendar).addingTimeInterval(12 * 3600)
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: noon) else { return nil }
        return (LocalDay(interval.start, calendar: calendar), LocalDay(interval.end.addingTimeInterval(-1), calendar: calendar))
    }

    /// The Thursday of the week `start…end`, which names the week's season (rewards.json `seasons_in_rhythm`).
    static func thursday(start: LocalDay, end: LocalDay, calendar: Calendar) -> LocalDay {
        var day = start
        while day <= end {
            let noon = day.startDate(in: calendar).addingTimeInterval(12 * 3600)
            if calendar.component(.weekday, from: noon) == 5 { return day }
            day = day.adding(days: 1, calendar: calendar)
        }
        return end
    }

    /// The three-month block a day falls in (Mar–May, Jun–Aug, Sep–Nov, Dec–Feb): the meteorological seasons, the
    /// same months in both hemispheres.
    static func seasonBlock(of day: LocalDay) -> Int {
        let shifted = (day.month + 9) % 12            // March 0 … February 11
        let year = day.month < 3 ? day.year - 1 : day.year
        return year * 4 + shifted / 3
    }

    /// One night applied to the run. `history` holds the settled nights up to and including this one.
    static func advance(
        run: Int, runStart: LocalDay?, with night: Night, history: [Night], calendar: Calendar
    ) -> (run: Int, runStart: LocalDay?) {
        switch night.outcome {
        case .onTime:
            return (run + 1, run == 0 ? night.night : runStart)
        case .early, .unscheduled:
            return (run, runStart)
        case .late, .untracked:
            guard run > 0 else { return (0, nil) }
            let lastWeek = night.night.adding(days: -6, calendar: calendar)
            let window = runStart.map { max($0, lastWeek) } ?? lastWeek
            let slips = history.filter { $0.night >= window && $0.night <= night.night && $0.outcome.isSlip }.count
            return slips >= 3 ? (0, nil) : (run, runStart)
        }
    }

    // MARK: Changes

    /// A schedule was replaced at `date`. Nights that had begun by then (18:00 cut-off) keep being judged by `old`
    /// (rewards.md: "Schedule edits apply from the next night").
    public mutating func scheduleChanged(from old: WeeklySleepSchedule, at date: Date, calendar: Calendar) {
        let through = Self.night(containing: date, calendar: calendar)
        pastSchedules.append(PastSchedule(through: through, schedule: old))
        if pastSchedules.count > Self.pastSchedulesKept {
            pastSchedules.removeFirst(pastSchedules.count - Self.pastSchedulesKept)
        }
    }

    /// Records Apple Health's nights, then settles every night whose next morning has started by `date`.
    ///
    /// Nights not settled yet keep their best observation. A settled night still inside its 72-hour window takes an
    /// upgrade (a better outcome, a steady morning or a full night it lacked); anything else about it is ignored.
    /// Nights before the install night never count. Idempotent: recording the same nights again changes nothing.
    /// A night without a time zone is stamped with the one in force now, so it is judged in that zone even if it
    /// settles after a flight.
    public mutating func record(_ observations: [SleepNightObservation], at date: Date, rules: Rules) -> Changes {
        var changes = Changes()
        let first = Self.firstNight(setUpAt: rules.setup, calendar: rules.calendar)
        let zone = rules.calendar.timeZone.identifier
        let stamped = observations.map { observation in
            var observation = observation
            if observation.timeZoneIdentifier == nil { observation.timeZoneIdentifier = zone }
            return observation
        }
        for observation in stamped.sorted(by: { $0.night < $1.night }) where observation.night >= first {
            if observation.isMainEpisode, observation.source.hasAsleepTime { sawAsleepTime = true }
            if let settledThrough, observation.night <= settledThrough {
                upgrade(with: observation, at: date, rules: rules, changes: &changes)
            } else {
                remember(observation)
            }
        }
        settle(at: date, rules: rules, changes: &changes)
        return changes
    }

    /// Settles, oldest first, every night from the install night whose next morning has started by `date`. Nights
    /// with no observation settle as untracked (so a run sees its slips).
    public mutating func settle(at date: Date, rules: Rules) -> Changes {
        var changes = Changes()
        settle(at: date, rules: rules, changes: &changes)
        return changes
    }

    private mutating func settle(at date: Date, rules: Rules, changes: inout Changes) {
        let calendar = rules.calendar
        var last = Self.night(containing: date, calendar: calendar)
        for _ in 0..<3 where settleDate(of: last, rules: rules) > date {
            last = last.adding(days: -1, calendar: calendar)
        }
        guard settleDate(of: last, rules: rules) <= date else { return }
        let first = Self.firstNight(setUpAt: rules.setup, calendar: calendar)
        var next = settledThrough.map { max(first, $0.adding(days: 1, calendar: calendar)) } ?? first
        guard next <= last else { return }
        if next.days(until: last, calendar: calendar) >= Self.longestSettle {
            // Away for years: everything before the last two was untracked, which ended any run long ago. The jump
            // never passes a night Apple Health still has data for: that night (and everything after it) settles.
            let jump = last.adding(days: -(Self.longestSettle - 1), calendar: calendar)
            let target = min(jump, pending.first { $0.night >= next }?.night ?? jump)
            // Only a skip of a week or more: its untracked nights have ended any run and any steady week.
            if next.days(until: target, calendar: calendar) >= 7 {
                next = target
                recent.removeAll()
            }
        }

        var night = next
        while night <= last {
            settleOne(night, rules: rules, changes: &changes)
            night = night.adding(days: 1, calendar: calendar)
        }
        pending.removeAll { $0.night <= last }
        settledThrough = last
        // Schedules older than the nights that can still be upgraded are done with.
        let oldestOpen = last.adding(days: -4, calendar: calendar)
        pastSchedules.removeAll { $0.through < oldestOpen }
    }

    private func settleDate(of night: LocalDay, rules: Rules) -> Date {
        Self.settleDate(of: night, schedule: schedule(for: night, current: rules.schedule), calendar: rules.calendar)
    }

    /// Keeps the best observation for a night not settled yet (a newer one from as good a source replaces it).
    private mutating func remember(_ observation: SleepNightObservation) {
        if let index = pending.firstIndex(where: { $0.night == observation.night }) {
            if observation.source.rank >= pending[index].source.rank { pending[index] = observation }
            return
        }
        pending.append(observation)
        pending.sort { $0.night < $1.night }
        if pending.count > Self.pendingKept { pending.removeFirst(pending.count - Self.pendingKept) }
    }

    private mutating func settleOne(_ night: LocalDay, rules: Rules, changes: inout Changes) {
        let calendar = rules.calendar
        var judged = evaluate(night, observation: pending.first { $0.night == night }, rules: rules)
        let before = recent.last
        recent.append(judged)
        let step = Self.advance(run: before?.run ?? 0, runStart: before?.runStart, with: judged, history: recent, calendar: calendar)
        judged.run = step.run
        judged.runStart = step.runStart
        recent[recent.count - 1] = judged

        changes.add(newly: judged, over: Night(night: night, outcome: .untracked))
        changes.run = step.run
        changes.bestRun = max(changes.bestRun, step.run)
        closeWeekIfDue(endingWith: night, calendar: calendar, changes: &changes)
        if recent.count > Self.nightsKept { recent.removeFirst(recent.count - Self.nightsKept) }
        changes.settled.append(night)
    }

    /// Late data for a settled night: keeps the better of each result, adds what it newly earned, and replays the run
    /// (and the week, if it has closed) from that night.
    private mutating func upgrade(with observation: SleepNightObservation, at date: Date, rules: Rules, changes: inout Changes) {
        let calendar = rules.calendar
        guard let index = recent.firstIndex(where: { $0.night == observation.night }),
              date <= settleDate(of: observation.night, rules: rules).addingTimeInterval(Self.upgradeWindow) else { return }
        let old = recent[index]
        let fresh = evaluate(observation.night, observation: observation, rules: rules)
        var merged = old
        if fresh.outcome.rank > old.outcome.rank { merged.outcome = fresh.outcome }
        merged.steadyMorning = old.steadyMorning || fresh.steadyMorning
        if fresh.fullNight == true || (old.fullNight == nil && fresh.fullNight != nil) { merged.fullNight = fresh.fullNight }
        if let source = fresh.source, (old.source?.rank ?? -1) < source.rank { merged.source = source }
        guard merged != old else { return }
        recent[index] = merged
        changes.add(newly: merged, over: old)

        if merged.outcome != old.outcome {
            // The run from this night on, with the better outcome.
            if index > 0 {
                var run = recent[index - 1].run
                var start = recent[index - 1].runStart
                for position in index..<recent.count {
                    (run, start) = Self.advance(run: run, runStart: start, with: recent[position], history: recent, calendar: calendar)
                    recent[position].run = run
                    recent[position].runStart = start
                    changes.bestRun = max(changes.bestRun, run)
                }
                changes.run = run
            }
            // A week that has closed may now be steady.
            if let week = Self.week(of: merged.night, calendar: calendar), let settledThrough, week.end <= settledThrough {
                closeWeekIfDue(endingWith: week.end, calendar: calendar, changes: &changes)
            }
        }
        changes.upgraded.append(merged.night)
    }

    /// When `night` is its week's last, counts the week if 5 or more of its nights were on time (once), and the
    /// season when that was its eighth steady week.
    private mutating func closeWeekIfDue(endingWith night: LocalDay, calendar: Calendar, changes: inout Changes) {
        guard let week = Self.week(of: night, calendar: calendar), week.end == night else { return }
        let thursday = Self.thursday(start: week.start, end: week.end, calendar: calendar)
        guard !steadyWeeks.contains(thursday) else { return }
        let onTime = recent.filter { $0.night >= week.start && $0.night <= week.end && $0.outcome == .onTime }.count
        guard onTime >= Self.steadyWeekNights else { return }
        steadyWeeks.append(thursday)
        steadyWeeks.sort()
        if steadyWeeks.count > Self.steadyWeeksKept { steadyWeeks.removeFirst(steadyWeeks.count - Self.steadyWeeksKept) }
        changes.increases[.steadyWeeks, default: 0] += 1
        let season = Self.seasonBlock(of: thursday)
        if steadyWeeks.filter({ Self.seasonBlock(of: $0) == season }).count == Self.steadyWeeksPerSeason {
            changes.increases[.seasonsInRhythm, default: 0] += 1
        }
    }
}

extension NightLedger.Changes {
    /// Adds what `night` earns that `previous` (the same night before, or untracked) hadn't, and its vitality.
    mutating func add(newly night: NightLedger.Night, over previous: NightLedger.Night) {
        if night.outcome.isTracked, !previous.outcome.isTracked { increases[.nightsTracked, default: 0] += 1 }
        if night.outcome == .onTime, previous.outcome != .onTime { increases[.onTimeBedtimes, default: 0] += 1 }
        if night.steadyMorning, !previous.steadyMorning { increases[.steadyMornings, default: 0] += 1 }
        if night.fullNight == true, previous.fullNight != true { increases[.fullNights, default: 0] += 1 }
        // Vitality hears on-time and late nights and full nights; early, unscheduled and untracked ones are neutral.
        let onTime: Bool? = switch night.outcome {
        case .onTime: true
        case .late: false
        case .early, .unscheduled, .untracked: nil
        }
        if night.outcome.isTracked, onTime != nil || night.fullNight != nil {
            vitality.removeAll { $0.day == night.night }
            vitality.append(NightRecord(day: night.night, onTime: onTime, fullNight: night.fullNight, scrollFree: nil))
        }
    }
}

// MARK: - Codable (tolerant: missing fields take their defaults, so an older file never fails the collection)

extension NightLedger: Codable {
    private enum CodingKeys: String, CodingKey {
        case pending, settledThrough, recent, steadyWeeks, pastSchedules, sawAsleepTime
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            pending: (try? c.decodeIfPresent([SleepNightObservation].self, forKey: .pending)) ?? [],
            settledThrough: (try? c.decodeIfPresent(LocalDay.self, forKey: .settledThrough)) ?? nil,
            recent: (try? c.decodeIfPresent([Night].self, forKey: .recent)) ?? [],
            steadyWeeks: (try? c.decodeIfPresent([LocalDay].self, forKey: .steadyWeeks)) ?? [],
            pastSchedules: (try? c.decodeIfPresent([PastSchedule].self, forKey: .pastSchedules)) ?? [],
            sawAsleepTime: (try? c.decodeIfPresent(Bool.self, forKey: .sawAsleepTime)) ?? false
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(pending, forKey: .pending)
        try c.encodeIfPresent(settledThrough, forKey: .settledThrough)
        try c.encode(recent, forKey: .recent)
        try c.encode(steadyWeeks, forKey: .steadyWeeks)
        try c.encode(pastSchedules, forKey: .pastSchedules)
        try c.encode(sawAsleepTime, forKey: .sawAsleepTime)
    }
}
