# Core API for screen engineers

How a screen reads Maple's data. Everything here is built and tested in MapleCore (pure rules) and MapleServices (stores). Views never compute unlocks, estimates, phases or rarity themselves.

## The three stores and the clock

`App/MapleApp.swift` creates the stores once (`MapleStores.launch()`) and injects them. Read them from the environment:

```swift
import MapleCore
import MapleDesign
import MapleServices

struct HomeView: View {
    @Environment(CollectionStore.self) private var collection   // leaves, counters, reveals, tree inputs
    @Environment(ScheduleStore.self) private var schedule       // wake, bedtime, wind-down length
    @Environment(LeafShareStore.self) private var shares        // "% of members have this leaf"
    @Environment(\.mapleClock) private var clock               // "now"; never call Date()
    @Environment(\.season) private var season                  // real season, or -MapleDemoSeason
}
```

All three are `@Observable`, so a view that reads them re-renders when they change. Every reader takes the moment explicitly (`at:`). Inside a timeline use the timeline's date through the clock, so DEBUG `-MapleDemoPhase` launches freeze correctly:

```swift
TimelineView(.everyMinute) { context in
    let now = clock.date(forTimeline: context.date)
    let state = collection.nowState(at: now)
    ...
}
```

For a one-off action use `clock.now()`: `collection.openReveals(at: clock.now())`.

## Home: `NowState`

`collection.nowState(at:)` resolves the §3.4 table: phase, numeral, caption, next-leaf preference and the one primary action.

```swift
let state = collection.nowState(at: now)

StatNumber(state.numeral.parts.map { $0.isUnit ? .unit($0.text) : .value($0.text) },
           size: .hero, accessibilityText: state.spoken)
Text(state.caption)                                     // one line, 7 words or fewer
if let action = state.action {                         // nil: no capsule at all
    Button(action.title) { perform(action) }
        .buttonStyle(.moonlight(dimmed: state.actionIsDimmed))
}
```

- `state.phase` drives the sky (`SkyBackdrop(phase:…)`) and the tree's `phase`.
- `state.waitingCount > 0` (morning, day and evening only) switches the next-leaf row to its waiting variant; `state.waitingLine` is its text ("2 new leaves are waiting"), and the action becomes `.openReveals(count:)`.
- `state.contentOpacity` is 0.8 at night; `state.showsBelowTheFold` is false at night; `state.secondaryAction` is `.sleepSounds` at night once sounds ship.
- `state.refreshesEverySecond` is true while focus runs: switch the NowBlock's timeline to `.periodic(from:by: 1)`.
- Inputs that don't exist yet are optional and default to the documented fallbacks: `nowState(at:lastNight:goodnightAt:focus:windDownActive:checkInDue:)`. Morning without them shows the day's content; the day shows the countdown to wind-down until focus ships.
- Lower level: `NowPhase.resolve(date:schedule:calendar:)`, `PhaseWindows(schedule:)` (phase starts, `sampleDate(in:onDayOf:calendar:)` for previews), `HomeFormat` (durations "1h 20m", locale clock times).

## Leaves: progress, next leaf, buds, Almost there

```swift
let next = collection.nextLeaf(at: now)                    // Home's next-leaf row (pinned, phase-preferred, closest)
if let next {
    let remainder = LeafRemainder(next, phase: state.phase)
    Text(remainder.text)                                    // "3 nights", "Tonight", "1h 40m"
    if remainder.showsBar { ProgressHairline(fraction: next.fraction) }
}
```

- `collection.progress(at:)`: all 155 `LeafProgress` rows in canonical order (category, then rung). `progress(for:at:)` for one leaf. Each row has `state` (`.earned(unlock)`, `.waiting(unlock)`, `.locked`), `availability` (`.available`, `.needsAppleHealth`, `.needsSleepTracker`, `.needsScreenTime`, `.dormant`), `current` (clamped), `fraction`, `remaining` and `estimatedDays` (nil when earned, waiting or unavailable).
- `collection.buds(at:)`: the tree's 3 buds, Home's next leaf first.
- `collection.almostThere(at:)`: up to 6 leaves within 60 days (hide the rail below 2).
- `collection.nextRungIDs(at:)`: species drawn as "Next" tiles (3 per available category).
- Copy: `RewardCategoryInfo(progress.category)` has `definition`, `shortRule(_:)`, `earnedLine(_:)`, `action`; the leaf's rule is `RewardCatalog.shared.reward(forSpecies:)?.unlockText`. `LeafRemainder(progress, phase:).amount` is "11 of 14". Estimates ("about 5 nights at your pace") are for leaf detail only.
- Actions: `collection.pin(id)` / `unpin()`, `collection.feature(id)` (earned leaves only), `collection.markSeen(id)` / `markAllSeen()`, `collection.isUnseen(id)` for the amber dot, `collection.featuredLeaf` for the avatar.

## Reveals

```swift
let queue = collection.revealable(at: clock.now())        // what can be opened now, oldest first
let opened = collection.openReveals(at: clock.now())       // marks them revealed and returns them
let firstThree = collection.revealsOpened < 3              // full ritual for the first 3 reveals ever
```

Leaves earned from Evening until the next Morning are held (`collection.held(at:)`), and nothing opens in wind-down or at night, except the First-steps leaf at the end of onboarding (D12). `collection.waiting` lists every unopened leaf (Herbarium "Waiting" tiles); when it is non-empty but `revealable` is empty, show "Opens in the morning". `openReveals(["rubrum"], at:)` opens just that one. After the first morning reveal, ask for rarity consent if `collection.rarityConsent == .notAsked`, and record the answer with `collection.setRarityConsent(_:)`.

## The tree

`collection.treeInputs(at:)` has everything but the phase. Map it onto the scene:

```swift
let tree = collection.treeInputs(at: now)
let model = TreeSceneModel(
    seed: tree.seed, growth: tree.growth,
    species: tree.species.map { .init(speciesID: $0.speciesID, pressed: $0.pressed) },
    buds: tree.buds.map { .init(speciesID: $0.speciesID, progress: $0.progress) },
    waiting: tree.waiting, featured: tree.featured,
    season: tree.season, seasonDay: tree.seasonDay, phase: state.phase, vitality: tree.vitality,
    newLeafHalos: tree.newLeafHalos.map { .init(speciesID: $0.speciesID, placedAt: $0.placedAt) }
)
```

Also on the store: `stage` (Seedling … Grand maple, from opened leaves), `earned.count` ("23 of 155"), `tendedDays` ("grown over 41 days"), `vitality.isQuiet` (VoiceOver "Resting."), `hasPlantedMaple` (first-run gating: show onboarding until it is true), `currentBedtimeRun` (Home's streak; hidden under 2) and `totals` (Profile; a nil total means its category doesn't exist yet).

## Rarity: "% of members have this leaf"

```swift
MemberShareLabel(share: shares.share(for: speciesID), layout: .detail)
MemberShareLabel(share: shares.share(for: id), layout: .tile, pressedOn: collection.unlock(for: id)?.date)
```

`share(for:)` returns every `MemberShare` state: `.loading`, `.value` (under 48 hours old), `.stale`, `.notEnoughMembers` (under 1,000), `.neverFetched`, `.newSpecies`, `.notEarnableYet`. The app refreshes on foreground (at most once a day). For sorting by rarity and "Your rarest", use `shares.estimate(for:)` (fresh values only). The explainer reads `shares.memberCount` (rounded down to 100) and `shares.weekStart`. Release builds use `UnconfiguredLeafShareProvider`, so every leaf reads "Rarity appears once 1,000 members take part" until the CloudKit provider exists (see the TODO on `LeafShareProvider`).

## Schedule

```swift
let unlocked = schedule.save(SleepSchedule(bedtime: ClockTime(hour: 23), wake: ClockTime(hour: 7), windDownMinutes: 45),
                             at: clock.now())
// First save: unlocked == [Sugar maple] (First steps), revealable at any hour. Later saves: [].
```

`schedule.schedule` is `.standard` until the member saves one; `schedule.hasSavedSchedule` says whether they have. Saving applies the schedule everywhere (phases, held reveals) at once. `windDownStart` and `minutesInBed` are on `SleepSchedule`.

## Recording behaviour

Data sources (Goodnight tap, Apple Health import, focus) call the collection; it runs the engine and returns new leaves:

```swift
collection.record([.nightsTracked: 1, .onTimeBedtimes: 1], at: now)   // increments
collection.raise(.bedtimeRun, to: 12, at: now)                         // high-water marks
collection.setCurrentBedtimeRun(12, at: now)
collection.recordNight(NightRecord(day: LocalDay(now, calendar: .current), onTime: true, fullNight: nil, scrollFree: nil))
```

Counters never go down. Any rise marks the day tended (tree growth), except First steps and Community challenges.

## Shipped features and permissions

`collection.context.features` is `ShippedFeatures.current` (M1 only): `.focus`, `.sleepSounds`, `.screenTime`, `.checkIns` are false and their categories are dormant ("Not earnable yet"). `collection.context.permissions` (`GrantedPermissions`) gates Apple Health and Screen Time categories; `collection.availability(of:)` gives a category's state. A feature that hasn't shipped is absent from every screen.

## Previews and demos

DEBUG launch arguments are in `docs/debug-launch-arguments.md`. In previews, build in-memory stores:

```swift
#Preview {
    let stores = MapleStores.make(DemoLaunchOptions(arguments: ["-MapleDemoSpecies", "23", "-MapleDemoPhase", "evening"]))
    HomeView()
        .environment(stores.collection).environment(stores.schedule).environment(stores.shares)
        .environment(\.mapleClock, stores.clock)
}
```

`DemoData.snapshot(species:tendedDays:waiting:now:)` gives a plausible collection directly, and `PreviewLeafShareProvider` gives tier-correlated rarity. Both exist only in DEBUG.
