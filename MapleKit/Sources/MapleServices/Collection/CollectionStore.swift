import Foundation
import MapleCore
import Observation

/// The member's leaf collection: counters, unlocks, reveals, the tree's inputs and everything derived from them.
/// One instance for the app, injected with `.environment(_:)`; screens read it with
/// `@Environment(CollectionStore.self)`.
///
/// Every change runs the leaf engine where it matters and saves the snapshot as JSON at once. Readers take the
/// moment explicitly (`at:`), so screens pass `clock.now()` (or the `TimelineView` date) and stay in step with the
/// DEBUG demo clock.
@Observable
public final class CollectionStore {
    public private(set) var snapshot: CollectionSnapshot
    private var contextStorage: CollectionContext
    /// Bumped when the system clock or time zone changes, so every view that read the context refreshes even though
    /// the autoupdating calendar compares equal to itself.
    private var timeEpoch = 0
    /// False while the collection file exists but can't be read yet (before the first unlock after a restart): the
    /// store then holds an empty placeholder that is never saved, and `reloadIfUnavailable()` reads the real one.
    public private(set) var isAvailable: Bool
    /// Follows the system calendar's time zone (`systemTimeChanged()`). True for the member's live store.
    @ObservationIgnored public var followsSystemCalendar = false

    @ObservationIgnored private let storage: JSONStorage<CollectionSnapshot>
    @ObservationIgnored private let engine = LeafEngine()
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var cache: (revision: Int, day: LocalDay, rows: [LeafProgress], byID: [String: LeafProgress], picker: NextLeafPicker)?

    /// Loads the saved collection, or on a first run creates (and saves) an empty one with a new profile id and tree
    /// seed. A file that is there but unreadable is never replaced: see `isAvailable`.
    /// - Parameter now: The first-launch time, kept as `createdAt`.
    public init(storage: JSONStorage<CollectionSnapshot>, context: CollectionContext = CollectionContext(), now: Date = .now) {
        self.storage = storage
        contextStorage = context
        switch storage.read() {
        case .value(let saved):
            snapshot = saved
            isAvailable = true
        case .absent:
            snapshot = .empty(profileID: UUID(), createdAt: now)
            isAvailable = true
            storage.save(snapshot)
        case .unavailable:
            snapshot = .empty(profileID: UUID(), createdAt: now)
            isAvailable = false
        }
    }

    /// Reads the collection again if it couldn't be read at launch (call it when protected data becomes available,
    /// or when the app becomes active).
    /// - Returns: Whether the store now holds the member's real collection where it held the placeholder.
    @discardableResult
    public func reloadIfUnavailable(now: Date = .now) -> Bool {
        guard !isAvailable else { return false }
        switch storage.read() {
        case .value(let saved):
            snapshot = saved
        case .absent:
            snapshot = .empty(profileID: UUID(), createdAt: now)
            storage.save(snapshot)
        case .unavailable:
            return false
        }
        isAvailable = true
        revision += 1
        return true
    }

    /// Schedule, permissions, shipped releases, calendar, hemisphere and the DEBUG season override.
    public var context: CollectionContext {
        get {
            _ = timeEpoch
            return contextStorage
        }
        set {
            contextStorage = newValue
            revision += 1
        }
    }

    /// The system clock or time zone changed (`NSSystemTimeZoneDidChange`, a significant time change): the live
    /// store moves to the new zone, its cached progress is rebuilt, and every screen that read it refreshes.
    public func systemTimeChanged() {
        guard followsSystemCalendar else { return }
        contextStorage.calendar = .autoupdatingCurrent
        revision += 1
        timeEpoch += 1
    }

    /// The member's weekday and weekend schedules. `ScheduleStore` keeps it in sync; screens change it through
    /// `ScheduleStore`.
    public var schedule: WeeklySleepSchedule {
        get { context.schedule }
        set { context.schedule = newValue }
    }

    // MARK: - Changes

    /// Adds to category counters (non-positive amounts are ignored), marks the day tended (except First steps and
    /// Community challenges) and runs the engine.
    /// - Returns: Leaves unlocked by this change.
    @discardableResult
    public func record(_ increases: [RewardCategoryID: Double], at date: Date) -> [LeafUnlock] {
        mutate { snapshot in
            snapshot.record(increases, at: date, calendar: context.calendar)
            return snapshot.runEngine(at: date, context: context, engine: engine)
        }
    }

    @discardableResult
    public func record(_ category: RewardCategoryID, by amount: Double = 1, at date: Date) -> [LeafUnlock] {
        record([category: amount], at: date)
    }

    /// Raises a counter to a high-water mark (lower values are ignored) and runs the engine.
    @discardableResult
    public func raise(_ category: RewardCategoryID, to value: Double, at date: Date) -> [LeafUnlock] {
        mutate { snapshot in
            snapshot.raise(category, to: value, at: date, calendar: context.calendar)
            return snapshot.runEngine(at: date, context: context, engine: engine)
        }
    }

    /// Runs the engine over the current counters (for example after another process changed them).
    @discardableResult
    public func runEngine(at date: Date) -> [LeafUnlock] {
        mutate { $0.runEngine(at: date, context: context, engine: engine) }
    }

    /// Opens leaves that may be opened now, in queue order: the given ids, or all of them. Held leaves, and any
    /// leaf in wind-down or at night (except First steps), stay closed.
    /// - Parameter eligibleAt: When the reveal began. Leaves that could be opened then are still placed if the
    ///   member taps "Place on your maple" after Evening has turned into Wind-down.
    /// - Returns: The opened leaves, for the reveal to show.
    @discardableResult
    public func openReveals(_ speciesIDs: [String]? = nil, at date: Date, eligibleAt: Date? = nil) -> [LeafUnlock] {
        mutate { $0.openReveals(speciesIDs, at: date, eligibleAt: eligibleAt, context: context) }
    }

    /// The member has looked at a leaf; its unseen dot goes.
    public func markSeen(_ speciesID: String) {
        guard isUnseen(speciesID) else { return }
        mutate { $0.markSeen(speciesID) }
    }

    public func markAllSeen() {
        guard snapshot.unlocks.contains(where: { $0.revealed && !$0.seen }) else { return }
        mutate { snapshot in
            for leaf in snapshot.earned where !leaf.seen { snapshot.markSeen(leaf.speciesID) }
        }
    }

    /// Pins a leaf as Home's next leaf; nil unpins.
    public func pin(_ speciesID: String?) {
        mutate { $0.pin(speciesID) }
    }

    public func unpin() {
        pin(nil)
    }

    /// Features an earned leaf on the crown and avatar; nil returns to the newest leaf.
    /// - Returns: False when the leaf isn't earned and opened.
    @discardableResult
    public func feature(_ speciesID: String?) -> Bool {
        mutate { $0.feature(speciesID) }
    }

    /// Records the answer to the rarity consent sheet or the Privacy toggle (D5).
    public func setRarityConsent(_ included: Bool) {
        mutate { $0.rarityConsent = included ? .included : .declined }
    }

    /// Adds or replaces a night's outcome for vitality.
    public func recordNight(_ night: NightRecord) {
        mutate { $0.recordNight(night) }
    }

    /// The one call M1's Apple Health importer makes: the nights it read, each reduced to its main episode with the
    /// best source available (`SleepNightObservation`). The sleep categories have no other source (spec D9), so a
    /// Goodnight tap never earns anything.
    ///
    /// Records the nights, then settles every night since the install night whose next morning has started by
    /// `date`: Nights tracked, On-time bedtimes, Steady mornings, Full nights, the bedtime run (the counter keeps
    /// the best), Steady weeks and Seasons in rhythm, and each night's vitality. Nights with nothing from Apple Health
    /// by then settle as untracked. Late data upgrades a settled night for 72 hours and never downgrades it; passing
    /// the same nights again changes nothing, so the importer can send the last few nights on every run. Nothing is
    /// recorded before the maple is planted.
    /// - Returns: Leaves unlocked, stamped `date`: pending at once in the morning and day, held from Evening on.
    @discardableResult
    public func recordSleep(_ nights: [SleepNightObservation], at date: Date) -> [LeafUnlock] {
        mutate { $0.recordSleep(nights, at: date, context: context, engine: engine) }
    }

    /// The member saved a schedule (`ScheduleStore.save`). Nights already under way keep being judged by the one
    /// they began with (`replacing`, nil for the first schedule ever); then the new one applies everywhere.
    public func scheduleSaved(_ schedule: WeeklySleepSchedule, replacing old: WeeklySleepSchedule?, at date: Date) {
        if let old, old != schedule, snapshot.hasPlantedMaple {
            mutate { $0.scheduleChanged(from: old, to: schedule, at: date, calendar: context.calendar) }
        }
        self.schedule = schedule
    }

    // MARK: - Reading

    public var unlocks: [LeafUnlock] { snapshot.unlocks }
    /// Opened leaves, in unlock order.
    public var earned: [LeafUnlock] { snapshot.earned }
    /// Earned leaves not opened yet, held or pending.
    public var waiting: [LeafUnlock] { snapshot.waiting }
    /// The collection's count, by the one rule (spec §5.2): "N of 155" counts opened leaves only, and waiting
    /// leaves are told apart ("1 waiting"). Every screen that shows N reads it here.
    public var leafCount: LeafCount { snapshot.leafCount }
    /// N in "N of 155": opened leaves, never waiting ones.
    public var openedCount: Int { leafCount.opened }
    /// The First-steps leaf is earned (the schedule was saved). The Sugar maple may still be waiting in the bud.
    public var hasPlantedMaple: Bool { snapshot.hasPlantedMaple }
    /// The First-steps unlock (the Sugar maple), opened or not.
    public var firstLeaf: LeafUnlock? { snapshot.firstLeaf }
    /// The Sugar maple is opened and on the tree: the first run is over (first-run gating, `FirstRunStep`).
    public var hasPlacedFirstLeaf: Bool { snapshot.hasPlacedFirstLeaf }
    public var pinnedSpeciesID: String? { snapshot.pinnedSpeciesID }
    /// The avatar's and crown's leaf: the member's choice, else the newest leaf.
    public var featuredLeaf: String? { snapshot.featuredLeaf }
    public var rarityConsent: RarityConsent { snapshot.rarityConsent }
    /// The first 3 reveals ever get the full ritual.
    public var revealsOpened: Int { snapshot.revealsOpened }
    public var tendedDays: Int { snapshot.tendedDayCount }
    /// Structural growth g.
    public var growth: Double { TreeGrowth.structure(tendedDays: snapshot.tendedDayCount) }
    public var stage: TreeStage { TreeStage(speciesCount: openedCount) }
    /// The tree's vitality on the day of `date`, from the week of nights before it (spec §4.8).
    public func vitality(at date: Date) -> Vitality { snapshot.vitality(at: date, calendar: context.calendar) }
    public var totals: ProfileTotals { snapshot.totals(context: context) }

    public func unlock(for speciesID: String) -> LeafUnlock? { snapshot.unlock(for: speciesID) }
    public func isUnseen(_ speciesID: String) -> Bool { snapshot.isUnseen(speciesID) }

    /// What the member has granted (`context.permissions`, which `HealthPermission` keeps real), plus a sleep
    /// tracker once Apple Health has delivered a night with asleep time.
    public var permissions: GrantedPermissions { snapshot.permissions(in: context) }

    public func availability(of category: RewardCategoryID) -> LeafAvailability {
        snapshot.availability(of: category, context: context)
    }

    public func phase(at date: Date) -> NowPhase { snapshot.phase(at: date, context: context) }
    public func season(at date: Date) -> Season { snapshot.season(at: date, context: context) }

    /// Leaves no longer held.
    public func pending(at date: Date) -> [LeafUnlock] { snapshot.pending(at: date, context: context) }
    /// Leaves earned from Evening on, held until Morning.
    public func held(at date: Date) -> [LeafUnlock] { snapshot.held(at: date, context: context) }
    /// What a reveal can open now. Home's waiting bud, row and CTA show exactly these.
    public func revealable(at date: Date) -> [LeafUnlock] { snapshot.revealable(at: date, context: context) }

    /// All 155 leaves, in canonical order.
    public func progress(at date: Date) -> [LeafProgress] { derived(at: date).rows }
    public func progress(for speciesID: String, at date: Date) -> LeafProgress? { derived(at: date).byID[speciesID] }
    /// Home's next leaf.
    public func nextLeaf(at date: Date) -> LeafProgress? {
        derived(at: date).picker.next(pinned: snapshot.pinnedSpeciesID)
    }
    /// The tree's buds: up to 3, Home's next leaf first.
    public func buds(at date: Date) -> [LeafProgress] {
        derived(at: date).picker.buds(pinned: snapshot.pinnedSpeciesID)
    }
    /// The Herbarium's "Almost there" rail (hide it when fewer than 2).
    public func almostThere(at date: Date) -> [LeafProgress] { derived(at: date).picker.almostThere() }
    /// Species drawn as "Next" tiles in the Herbarium.
    public func nextRungIDs(at date: Date) -> Set<String> { derived(at: date).picker.nextRungIDs }
    /// When no leaf can be earned for want of a permission (no Apple Health): the cheapest leaf turning it on would
    /// make earnable, for Home's needs-permission row. Nil whenever `nextLeaf(at:)` can pick a leaf.
    public func permissionPrompt(at date: Date) -> LeafProgress? { derived(at: date).picker.permissionPrompt() }

    /// Everything the maple scene needs except the phase.
    public func treeInputs(at date: Date) -> TreeInputs { snapshot.treeInputs(at: date, context: context) }

    /// Home's NowBlock and CTA. Apple Health's last night, the Goodnight tap (the phone-down time the morning shows
    /// without Apple Health, spec §3.4; it earns nothing) and focus are passed in once they exist.
    public func nowState(
        at date: Date, locale: Locale = .current, lastNight: LastNightSleep? = nil, goodnightAt: Date? = nil,
        focus: FocusStatus? = nil, windDownActive: Bool = false, checkInDue: Bool = false
    ) -> NowState {
        NowState.resolve(
            date: date, weekly: context.schedule, calendar: context.calendar, locale: locale,
            pending: pending(at: date).count, counters: snapshot.counters, features: context.features,
            lastNight: lastNight, goodnightAt: goodnightAt, focus: focus, windDownActive: windDownActive, checkInDue: checkInDue
        )
    }

    // MARK: - Private

    private func mutate<Result>(_ change: (inout CollectionSnapshot) -> Result) -> Result {
        // A change always lands on the member's real collection: read it first if launch couldn't.
        if !isAvailable { reloadIfUnavailable() }
        var copy = snapshot
        let result = change(&copy)
        if copy != snapshot {
            snapshot = copy
            revision += 1
            // The placeholder is never written over a file that couldn't be read.
            if isAvailable { storage.save(copy) }
        }
        return result
    }

    private func derived(at date: Date) -> (rows: [LeafProgress], byID: [String: LeafProgress], picker: NextLeafPicker) {
        let day = LocalDay(date, calendar: context.calendar)
        // Reading the snapshot registers the observation even when the cache answers.
        _ = snapshot.counters
        if let cache, cache.revision == revision, cache.day == day {
            return (cache.rows, cache.byID, cache.picker)
        }
        let rows = snapshot.progress(at: date, context: context)
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.speciesID, $0) })
        let picker = NextLeafPicker(progress: rows)
        cache = (revision, day, rows, byID, picker)
        return (rows, byID, picker)
    }
}
