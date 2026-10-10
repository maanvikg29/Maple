import Foundation
import MapleCore
import MapleDesign
import MapleServices

/// Everything Home shows at one moment, read from the collection once per minute (spec §3). Views never compute
/// unlocks, phases or estimates; this only gathers what the stores already decided.
struct HomeContent {
    let now: Date
    let state: NowState
    /// Home's next leaf; nil when every available leaf is earned.
    let next: LeafProgress?
    let tree: TreeSceneModel
    let stage: TreeStage
    let leaves: Int
    let total: Int
    let tendedDays: Int
    let streak: Int
    let avatar: HomeHeader.Avatar?
    let newestID: String?
    /// The leaf the tappable amber bud stands for.
    let waitingBudID: String?
    let grewToday: Bool

    /// - Parameter bedside: Wind-down mode's state, so the CTA says "Return to wind-down" while it is on and the
    ///   morning can show last night's Goodnight time.
    init(collection: CollectionStore, now: Date, bedside: BedsideState = BedsideState()) {
        self.now = now
        let state = collection.nowState(at: now, goodnightAt: bedside.goodnightAt, windDownActive: bedside.windDownActive)
        self.state = state
        next = collection.nextLeaf(at: now)
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
            newLeafHalos: inputs.newLeafHalos.map { .init(speciesID: $0.speciesID, placedAt: $0.placedAt) }
        )
        stage = inputs.stage
        leaves = inputs.species.count
        total = LeafCatalog.shared.species.count
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

    /// The next-leaf row's content: the waiting variant while leaves can be opened, else the next leaf.
    var row: NextLeafRow.Content? {
        if state.waitingCount > 0 {
            return .waiting(count: state.waitingCount)
        }
        return next.map { .leaf($0, remainder: LeafRemainder($0, phase: state.phase)) }
    }
}
