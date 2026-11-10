import Foundation

/// Awards leaves (spec §5.1, §7.4). Pure: given the member's counters and the leaves they already hold, it returns
/// a `LeafUnlock` for every rung whose threshold is met and isn't held yet. Unlocks are keyed by species id, so
/// running it again, or on merged data, never awards a leaf twice.
public struct LeafEngine: Sendable {
    public var rewards: RewardCatalog
    public var species: LeafCatalog

    public init(rewards: RewardCatalog = .shared, species: LeafCatalog = .shared) {
        self.rewards = rewards
        self.species = species
    }

    /// New unlocks in canonical order (category order, then threshold), dated `date` and pressed in `season`.
    /// They start unrevealed and unseen.
    public func newUnlocks(counters: [RewardCategoryID: Double], existing: [LeafUnlock], at date: Date, season: Season) -> [LeafUnlock] {
        let held = Set(existing.map(\.speciesID))
        var unlocks: [LeafUnlock] = []
        for category in rewards.categories {
            let counter = counters[category.id] ?? 0
            for rung in rewards.rungs(in: category.id) where counter >= rung.threshold && !held.contains(rung.speciesID) {
                let evergreen = species.species(id: rung.speciesID)?.evergreen ?? false
                unlocks.append(LeafUnlock(
                    speciesID: rung.speciesID, date: date, season: season,
                    colourway: LeafColourway.pressed(in: season, evergreen: evergreen)
                ))
            }
        }
        return unlocks
    }

    /// As above, with the season taken from the date and the member's hemisphere.
    public func newUnlocks(
        counters: [RewardCategoryID: Double], existing: [LeafUnlock], at date: Date, hemisphere: Hemisphere, calendar: Calendar = .current
    ) -> [LeafUnlock] {
        newUnlocks(counters: counters, existing: existing, at: date, season: Season(for: date, hemisphere: hemisphere, calendar: calendar))
    }
}

/// When an earned leaf may be opened (spec §3.3, §5.8, D8, D12).
///
/// Leaves unlocked from the start of Evening until the next Morning start are *held* and become *pending* at Morning
/// start; all others are pending at once. Pending leaves open only in Morning, Day and Evening, never in Wind-down
/// or Night. The first leaf is the exception: it opens at the end of onboarding, at any hour.
public enum RevealSchedule {
    /// The moment `unlock` stops being held.
    public static func releaseDate(for unlock: LeafUnlock, schedule: WeeklySleepSchedule, calendar: Calendar) -> Date {
        if isFirstLeaf(unlock.speciesID) { return unlock.date }
        switch NowPhase.resolve(date: unlock.date, weekly: schedule, calendar: calendar) {
        case .morning, .day:
            return unlock.date
        case .evening, .windDown, .night:
            return PhaseWindows(weekly: schedule).nextStart(of: .morning, after: unlock.date, calendar: calendar)
        }
    }

    public static func isHeld(_ unlock: LeafUnlock, at date: Date, schedule: WeeklySleepSchedule, calendar: Calendar) -> Bool {
        !unlock.revealed && releaseDate(for: unlock, schedule: schedule, calendar: calendar) > date
    }

    /// Unopened leaves that are no longer held, oldest first.
    public static func pending(_ unlocks: [LeafUnlock], at date: Date, schedule: WeeklySleepSchedule, calendar: Calendar) -> [LeafUnlock] {
        ordered(unlocks.filter { !$0.revealed && !isHeld($0, at: date, schedule: schedule, calendar: calendar) })
    }

    /// Unopened leaves still held until the morning, oldest first.
    public static func held(_ unlocks: [LeafUnlock], at date: Date, schedule: WeeklySleepSchedule, calendar: Calendar) -> [LeafUnlock] {
        ordered(unlocks.filter { isHeld($0, at: date, schedule: schedule, calendar: calendar) })
    }

    /// Whether pending reveals may surface and open in `phase`.
    public static func opensIn(_ phase: NowPhase) -> Bool {
        phase == .morning || phase == .day || phase == .evening
    }

    /// What a reveal can open right now: pending leaves in Morning, Day and Evening, and the first leaf at any hour.
    public static func revealable(_ unlocks: [LeafUnlock], at date: Date, schedule: WeeklySleepSchedule, calendar: Calendar) -> [LeafUnlock] {
        let phaseAllows = opensIn(NowPhase.resolve(date: date, weekly: schedule, calendar: calendar))
        return pending(unlocks, at: date, schedule: schedule, calendar: calendar).filter { phaseAllows || isFirstLeaf($0.speciesID) }
    }

    static func isFirstLeaf(_ speciesID: String) -> Bool {
        RewardCatalog.shared.reward(forSpecies: speciesID)?.categoryID == .firstLeaf
    }

    private static func ordered(_ unlocks: [LeafUnlock]) -> [LeafUnlock] {
        // Stable: same-instant unlocks keep the engine's canonical order.
        unlocks.enumerated().sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }.map(\.element)
    }
}
