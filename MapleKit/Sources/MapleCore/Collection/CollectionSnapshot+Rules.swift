import Foundation

/// The member's circumstances that the collection rules depend on but that aren't part of the collection itself.
public struct CollectionContext: Sendable, Equatable {
    /// The member's weekday and weekend schedules (`ScheduleStore` keeps it in sync).
    public var schedule: WeeklySleepSchedule
    public var permissions: GrantedPermissions
    public var features: ShippedFeatures
    /// The member's calendar and time zone. The app passes `Calendar.autoupdatingCurrent`, so a new time zone (a
    /// flight, a trip) moves phases, days and held reveals with it; `CollectionStore.systemTimeChanged()` then
    /// refreshes every screen that read it.
    public var calendar: Calendar
    public var hemisphere: Hemisphere
    /// DEBUG `-MapleDemoSeason`: the tree shows this season instead of the real one.
    public var seasonOverride: Season?
    /// The member's sleep need (Settings › Sleep goal): a full night is at least this − 30 minutes asleep.
    public var sleepNeedMinutes: Int

    /// 7h 30m, until the member changes it (rewards.json `full_nights`, which supersedes spec §5.1's 7h;
    /// `AppSettings.defaultSleepGoalMinutes`).
    public static let defaultSleepNeedMinutes = 7 * 60 + 30

    /// - Parameter permissions: What the member has granted. Empty by default: nothing is granted until it really is.
    public init(
        schedule: WeeklySleepSchedule = .standard, permissions: GrantedPermissions = [], features: ShippedFeatures = .current,
        calendar: Calendar = .autoupdatingCurrent, hemisphere: Hemisphere = .current, seasonOverride: Season? = nil,
        sleepNeedMinutes: Int = CollectionContext.defaultSleepNeedMinutes
    ) {
        self.schedule = schedule
        self.permissions = permissions
        self.features = features
        self.calendar = calendar
        self.hemisphere = hemisphere
        self.seasonOverride = seasonOverride
        self.sleepNeedMinutes = sleepNeedMinutes
    }
}

// MARK: - Changes

extension CollectionSnapshot {
    /// Days of closing counters kept for the pace (plus one older baseline).
    static let historyDays = 30
    static let nightsKept = 14

    /// Adds `increases` to the counters. Non-positive amounts are ignored, so counters never fall. Any rise marks
    /// the local day as tended, except First steps and Community challenges (spec §4.1).
    /// - Returns: Whether any counter rose.
    @discardableResult
    public mutating func record(_ increases: [RewardCategoryID: Double], at date: Date, calendar: Calendar) -> Bool {
        var rose: [RewardCategoryID] = []
        for (category, amount) in increases where amount > 0 {
            counters[category, default: 0] += amount
            rose.append(category)
        }
        return didRaise(rose, at: date, calendar: calendar)
    }

    /// Raises a counter to `value` (a high-water mark); lower values are ignored.
    @discardableResult
    public mutating func raise(_ category: RewardCategoryID, to value: Double, at date: Date, calendar: Calendar) -> Bool {
        guard value > counters[category, default: 0] else { return false }
        counters[category] = value
        return didRaise([category], at: date, calendar: calendar)
    }

    private mutating func didRaise(_ categories: [RewardCategoryID], at date: Date, calendar: Calendar) -> Bool {
        guard !categories.isEmpty else { return false }
        let day = LocalDay(date, calendar: calendar)
        if categories.contains(where: { $0 != .firstLeaf }), !tendedDays.contains(day) {
            tendedDays.append(day)
            tendedDays.sort()
        }
        if let index = history.firstIndex(where: { $0.day == day }) {
            history[index].counters = counters
        } else {
            history.append(DailyCounters(day: day, counters: counters))
            history.sort { $0.day < $1.day }
        }
        // Keep about a month, plus the newest older entry as the pace's baseline.
        let cutoff = day.adding(days: -Self.historyDays, calendar: calendar)
        if let lastOld = history.lastIndex(where: { $0.day < cutoff }), lastOld > 0 {
            history.removeFirst(lastOld)
        }
        return true
    }

    /// Runs the engine over the counters and appends whatever it awards, pressed in the season at `date`.
    @discardableResult
    public mutating func runEngine(at date: Date, context: CollectionContext, engine: LeafEngine = LeafEngine()) -> [LeafUnlock] {
        let added = engine.newUnlocks(counters: counters, existing: unlocks, at: date, hemisphere: context.hemisphere, calendar: context.calendar)
        unlocks.append(contentsOf: added)
        return added
    }

    /// Opens leaves that may be opened now (`revealable`), in queue order: the given ids, or all of them.
    ///
    /// A reveal that began while leaves could be opened passes its start as `eligibleAt`: what was revealable then
    /// is still placed when "Place on your maple" comes after Evening has turned into Wind-down (the member has
    /// already watched those leaves open). Held leaves stay closed either way.
    /// - Returns: The opened leaves, now revealed, stamped with `date`.
    @discardableResult
    public mutating func openReveals(
        _ speciesIDs: [String]?, at date: Date, eligibleAt: Date? = nil, context: CollectionContext
    ) -> [LeafUnlock] {
        var allowed = revealable(at: date, context: context)
        if let eligibleAt, eligibleAt < date {
            let now = Set(allowed.map(\.speciesID))
            let earlier = revealable(at: eligibleAt, context: context).filter { !now.contains($0.speciesID) }
            if !earlier.isEmpty {
                // Back in unlock order, as `revealable` gives them.
                let order = Dictionary(uniqueKeysWithValues: unlocks.enumerated().map { ($0.element.speciesID, $0.offset) })
                allowed = (allowed + earlier).sorted { (order[$0.speciesID] ?? 0) < (order[$1.speciesID] ?? 0) }
            }
        }
        let chosen = speciesIDs.map { ids in allowed.filter { ids.contains($0.speciesID) } } ?? allowed
        var opened: [LeafUnlock] = []
        for leaf in chosen {
            guard let index = unlocks.firstIndex(where: { $0.speciesID == leaf.speciesID }) else { continue }
            unlocks[index].revealed = true
            revealedAt[leaf.speciesID] = date
            opened.append(unlocks[index])
        }
        revealsOpened += opened.count
        return opened
    }

    /// The member has looked at the leaf; its unseen dot goes.
    public mutating func markSeen(_ speciesID: String) {
        guard let index = unlocks.firstIndex(where: { $0.speciesID == speciesID }) else { return }
        unlocks[index].seen = true
    }

    /// Pins a leaf as the next leaf (nil unpins). Whether it is still locked and available is checked when picking.
    public mutating func pin(_ speciesID: String?) {
        pinnedSpeciesID = speciesID
    }

    /// Features an earned leaf on the crown and avatar (nil returns to the newest).
    /// - Returns: False when the leaf isn't earned and opened.
    @discardableResult
    public mutating func feature(_ speciesID: String?) -> Bool {
        guard let speciesID else {
            featuredSpeciesID = nil
            return true
        }
        guard earned.contains(where: { $0.speciesID == speciesID }) else { return false }
        featuredSpeciesID = speciesID
        return true
    }

    /// Adds or replaces one night's outcome, keeping the last 14.
    public mutating func recordNight(_ night: NightRecord) {
        recentNights.removeAll { $0.day == night.day }
        recentNights.append(night)
        recentNights.sort { $0.day < $1.day }
        if recentNights.count > Self.nightsKept {
            recentNights.removeFirst(recentNights.count - Self.nightsKept)
        }
    }

    /// Apple Health's nights (M1's importer; spec D9: there is no manual fallback, so no tap ever counts). Records
    /// them in the ledger, settles every night whose next morning has started by `date` (from the install night),
    /// and records what they earned: Rested nights per on-time night, plus each tracked night's outcome for vitality. Late data upgrades a settled night for 72 hours; recording the same
    /// nights again changes nothing. Ignored before the maple is planted.
    /// - Returns: Leaves the nights unlocked, stamped `date` (held or pending like any unlock).
    @discardableResult
    public mutating func recordSleep(
        _ observations: [SleepNightObservation], at date: Date, context: CollectionContext, engine: LeafEngine = LeafEngine()
    ) -> [LeafUnlock] {
        guard let setup = firstLeaf?.date else { return [] }
        let calendar = context.calendar
        let rules = NightLedger.Rules(setup: setup, schedule: context.schedule, sleepNeedMinutes: context.sleepNeedMinutes,
                                      calendar: calendar)
        let changes = nights.record(observations, at: date, rules: rules)
        guard !changes.isEmpty else { return [] }
        record(changes.increases, at: date, calendar: calendar)
        if let run = changes.run {
            currentBedtimeRun = run
        }
        for night in changes.vitality { recordNight(night) }
        return runEngine(at: date, context: context, engine: engine)
    }

    /// The member replaced their schedule at `date`. Nights that had begun by then are still judged by `old`
    /// (rewards.md: edits apply from the next night, cut-off 18:00). The first schedule ever saved replaces nothing.
    public mutating func scheduleChanged(from old: WeeklySleepSchedule, to new: WeeklySleepSchedule, at date: Date, calendar: Calendar) {
        guard old != new, hasPlantedMaple else { return }
        nights.scheduleChanged(from: old, at: date, calendar: calendar)
    }
}

// MARK: - Reading

extension CollectionSnapshot {
    /// Opened leaves, in unlock order.
    public var earned: [LeafUnlock] { unlocks.filter(\.revealed) }
    /// Leaves earned but not opened yet (held or pending), in unlock order.
    public var waiting: [LeafUnlock] { unlocks.filter { !$0.revealed } }
    /// "N of 155": opened leaves only (spec §5.2, `LeafCount`).
    public var leafCount: LeafCount { LeafCount(unlocks: unlocks) }
    /// The First-steps leaf has been earned: onboarding is done and Home can show (D12).
    public var hasPlantedMaple: Bool { unlocks.contains { RevealSchedule.isFirstLeaf($0.speciesID) } }
    public var tendedDayCount: Int { tendedDays.count }

    public func unlock(for speciesID: String) -> LeafUnlock? {
        unlocks.first { $0.speciesID == speciesID }
    }

    /// An opened leaf the member hasn't looked at yet (the amber unseen dot).
    public func isUnseen(_ speciesID: String) -> Bool {
        unlock(for: speciesID).map { $0.revealed && !$0.seen } ?? false
    }

    /// The leaf on the avatar and the crown's top: the member's choice, else the newest opened leaf.
    public var featuredLeaf: String? {
        if let featuredSpeciesID, earned.contains(where: { $0.speciesID == featuredSpeciesID }) { return featuredSpeciesID }
        return earned.last?.speciesID
    }

    /// The tree's vitality on the day of `date`, from the nights of the week before it (spec §4.8).
    public func vitality(at date: Date, calendar: Calendar) -> Vitality {
        Vitality(nights: recentNights, today: LocalDay(date, calendar: calendar), calendar: calendar)
    }

    public func pending(at date: Date, context: CollectionContext) -> [LeafUnlock] {
        RevealSchedule.pending(unlocks, at: date, schedule: context.schedule, calendar: context.calendar)
    }

    public func held(at date: Date, context: CollectionContext) -> [LeafUnlock] {
        RevealSchedule.held(unlocks, at: date, schedule: context.schedule, calendar: context.calendar)
    }

    /// What can be opened now; Home's waiting bud, row and CTA show exactly these.
    public func revealable(at date: Date, context: CollectionContext) -> [LeafUnlock] {
        RevealSchedule.revealable(unlocks, at: date, schedule: context.schedule, calendar: context.calendar)
    }

    /// What the member has granted, plus a sleep tracker once Apple Health has delivered a night with asleep time
    /// (rewards.json `full_nights`: with iPhone in-bed data only, Full nights need "Apple Watch or a sleep tracker").
    public func permissions(in context: CollectionContext) -> GrantedPermissions {
        var granted = context.permissions
        if granted.contains(.appleHealth), nights.sawAsleepTime { granted.insert(.sleepTracker) }
        return granted
    }

    public func availability(of category: RewardCategoryID, context: CollectionContext) -> LeafAvailability {
        LeafAvailability(category: category, permissions: permissions(in: context), features: context.features)
    }

    public func progress(at date: Date, context: CollectionContext) -> [LeafProgress] {
        LeafProgressBuilder(permissions: permissions(in: context), features: context.features)
            .progress(counters: counters, unlocks: unlocks, history: history, today: LocalDay(date, calendar: context.calendar),
                      calendar: context.calendar, currentBedtimeRun: currentBedtimeRun)
    }

    public func picker(at date: Date, context: CollectionContext) -> NextLeafPicker {
        NextLeafPicker(progress: progress(at: date, context: context))
    }

    public func nextLeaf(at date: Date, context: CollectionContext) -> LeafProgress? {
        picker(at: date, context: context).next(pinned: pinnedSpeciesID)
    }

    public func buds(at date: Date, context: CollectionContext) -> [LeafProgress] {
        picker(at: date, context: context).buds(pinned: pinnedSpeciesID)
    }

    public func almostThere(at date: Date, context: CollectionContext) -> [LeafProgress] {
        picker(at: date, context: context).almostThere()
    }

    public func nextRungIDs(at date: Date, context: CollectionContext) -> Set<String> {
        picker(at: date, context: context).nextRungIDs
    }

    /// With nothing earnable for want of a permission, the leaf Home offers to turn it on for (D9).
    public func permissionPrompt(at date: Date, context: CollectionContext) -> LeafProgress? {
        picker(at: date, context: context).permissionPrompt()
    }

    public func phase(at date: Date, context: CollectionContext) -> NowPhase {
        NowPhase.resolve(date: date, weekly: context.schedule, calendar: context.calendar)
    }

    /// The season the tree shows: the real one for the member's hemisphere, unless overridden.
    public func season(at date: Date, context: CollectionContext) -> Season {
        context.seasonOverride ?? Season(for: date, hemisphere: context.hemisphere, calendar: context.calendar)
    }

    /// Everything the maple scene needs, except the phase (which the screen takes from `NowState`).
    public func treeInputs(at date: Date, context: CollectionContext) -> TreeInputs {
        let placed = earned
        let picker = picker(at: date, context: context)
        let halos = placed.compactMap { leaf -> TreeInputs.Halo? in
            guard let opened = revealedAt[leaf.speciesID], date.timeIntervalSince(opened) < TreeInputs.haloLifetime,
                  opened <= date else { return nil }
            return TreeInputs.Halo(speciesID: leaf.speciesID, placedAt: opened)
        }
        return TreeInputs(
            seed: treeSeed,
            tendedDays: tendedDayCount,
            growth: TreeGrowth.structure(tendedDays: tendedDayCount),
            stage: TreeStage(speciesCount: leafCount.opened),
            species: placed.map { TreeInputs.Leaf(speciesID: $0.speciesID, pressed: $0.colourway) },
            buds: picker.buds(pinned: pinnedSpeciesID).map { TreeInputs.Bud(speciesID: $0.speciesID, progress: $0.fraction) },
            waiting: revealable(at: date, context: context).map(\.speciesID),
            featured: featuredLeaf,
            season: season(at: date, context: context),
            seasonDay: TreeFoliage.seasonDay(for: date, hemisphere: context.hemisphere, calendar: context.calendar),
            vitality: vitality(at: date, calendar: context.calendar).value,
            newLeafHalos: halos,
            unlockOrder: unlocks.map(\.speciesID)
        )
    }

    /// The Profile sheet's totals; a total is nil until its category exists for this member.
    public func totals(context: CollectionContext) -> ProfileTotals {
        func total(_ category: RewardCategoryID) -> Double? {
            availability(of: category, context: context) == .available ? counters[category, default: 0] : nil
        }
        let opened = leafCount.opened
        return ProfileTotals(
            leaves: opened, tendedDays: tendedDayCount, stage: TreeStage(speciesCount: opened),
            nightsOnTime: total(.restedNights).map { Int($0) }, focusHours: total(.focusHours),
            windDowns: total(.windDownRituals).map { Int($0) }, mornings: total(.steadyMornings).map { Int($0) }
        )
    }
}
