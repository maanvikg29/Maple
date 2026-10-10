import Foundation
import MapleCore
import MapleDesign
import MapleServices

/// Everything Home shows at one moment, read from the collection once per minute (spec §3). Views never compute
/// unlocks, phases or estimates; this only gathers what the stores already decided.
struct HomeContent {
    let now: Date
    let state: NowState
    /// Home's next leaf; nil when no leaf can be earned (all earned, or Apple Health isn't on).
    let next: LeafProgress?
    /// With no next leaf for want of a permission (no Apple Health, D9): the cheapest leaf turning it on would make
    /// earnable, for the row's needs-permission variant.
    let permissionPrompt: LeafProgress?
    let tree: TreeSceneModel
    let stage: TreeStage
    /// N in "23 of 155": opened leaves (`CollectionStore.leafCount`), for the caption, Tree view and VoiceOver.
    let leaves: Int
    let total: Int
    let tendedDays: Int
    let streak: Int
    let avatar: HomeHeader.Avatar?
    let newestID: String?
    /// The leaf the tappable amber bud stands for.
    let waitingBudID: String?
    let grewToday: Bool
    /// Apple Health is connected but has sent no sleep for two nights: the no-sleep hint takes the next-leaf row's
    /// place (never the waiting row's).
    let showsNoSleepHint: Bool

    /// - Parameters:
    ///   - bedside: Wind-down mode's state, so the CTA says "Return to wind-down" while it is on and the morning can
    ///     show last night's Goodnight time.
    ///   - lastNight: Last night's sleep from Apple Health (`HealthSleepImporter.lastNightSleep(at:)`), the
    ///     morning's numeral (spec §3.4).
    ///   - noSleepHint: `HealthSleepImporter.showsNoSleepHint(at:)`.
    init(
        collection: CollectionStore, now: Date, bedside: BedsideState = BedsideState(), lastNight: LastNightSleep? = nil,
        noSleepHint: Bool = false
    ) {
        self.now = now
        let state = collection.nowState(at: now, lastNight: lastNight, goodnightAt: bedside.goodnightAt,
                                        windDownActive: bedside.windDownActive)
        self.state = state
        showsNoSleepHint = noSleepHint && state.waitingCount == 0
        let next = collection.nextLeaf(at: now)
        self.next = next
        permissionPrompt = next == nil ? collection.permissionPrompt(at: now) : nil
        let inputs = collection.treeInputs(at: now)
        #if DEBUG
        let vitality = Self.demoVitality ?? inputs.vitality
        #else
        let vitality = inputs.vitality
        #endif
        tree = TreeSceneModel(
            seed: inputs.seed, growth: inputs.growth,
            species: inputs.species.map { .init(speciesID: $0.speciesID, pressed: $0.pressed) },
            buds: inputs.buds.map { .init(speciesID: $0.speciesID, progress: $0.progress) },
            waiting: inputs.waiting, featured: inputs.featured,
            season: inputs.season, seasonDay: inputs.seasonDay, phase: state.phase, vitality: vitality,
            newLeafHalos: inputs.newLeafHalos.map { .init(speciesID: $0.speciesID, placedAt: $0.placedAt) },
            unlockOrder: inputs.unlockOrder
        )
        stage = inputs.stage
        // One count rule (spec §5.2): opened leaves only; a waiting leaf is the amber bud, not part of N.
        let count = collection.leafCount
        leaves = count.opened
        total = count.total
        tendedDays = inputs.tendedDays
        streak = collection.currentBedtimeRun
        if let featured = collection.featuredLeaf, let species = LeafCatalog.shared.species(id: featured),
           let unlock = collection.unlock(for: featured) {
            avatar = HomeHeader.Avatar(species: species, colourway: unlock.colourway)
        } else {
            avatar = nil
        }
        newestID = collection.earned.last?.speciesID
        waitingBudID = inputs.waiting.first
        let today = LocalDay(now, calendar: collection.context.calendar)
        grewToday = collection.snapshot.tendedDays.contains(today)
    }

    #if DEBUG
    /// DEBUG `-MapleDemoVitality 0.4…1`: shows the tree at that vitality (0.45 is the quiet tree, spec §4.8). It only
    /// changes what Home and the Tree view draw; no night is recorded, so the member's files are never touched.
    static var demoVitality: Double? {
        guard UserDefaults.standard.object(forKey: "MapleDemoVitality") != nil else { return nil }
        return min(1, max(Vitality.minimum, UserDefaults.standard.double(forKey: "MapleDemoVitality")))
    }
    #endif

    /// The tree's VoiceOver label (spec §4.11).
    var treeLabel: String {
        HomeSpeech.treeLabel(stage: stage, leaves: leaves, total: total, tendedDays: tendedDays)
    }

    /// The tree's VoiceOver value: newest, next, and "A new leaf is waiting.", "Grew today.", "Resting.".
    var treeValue: String {
        let newest = newestID.flatMap { LeafCatalog.shared.species(id: $0)?.displayName }
        return HomeSpeech.treeValue(
            newest: newest, next: next, waiting: tree.waiting.count, grewToday: grewToday, resting: tree.isQuiet
        )
    }

    /// The next-leaf row's content: the waiting variant while leaves can be opened, else the next leaf, else (with
    /// nothing earnable until Apple Health is on) the needs-permission variant. Nil when there is nothing at all, or
    /// when the no-sleep hint stands in its place.
    var row: NextLeafRow.Content? {
        if showsNoSleepHint { return nil }
        if state.waitingCount > 0 {
            return .waiting(count: state.waitingCount)
        }
        if let next {
            return .leaf(next, remainder: LeafRemainder(next, phase: state.phase))
        }
        return permissionPrompt.map { .needsPermission($0) }
    }
}
