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
    @Environment(HealthPermission.self) private var health      // Apple Health: connected or not, and the prompt
    @Environment(\.mapleClock) private var clock               // "now"; never call Date()
    @Environment(\.season) private var season                  // real season, or -MapleDemoSeason
}
```

All of them are `@Observable`, so a view that reads them re-renders when they change. Every reader takes the moment explicitly (`at:`). Inside a timeline use the timeline's date through the clock, so DEBUG `-MapleDemoPhase` launches freeze correctly:

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
- Inputs that don't exist yet are optional and default to the documented fallbacks: `nowState(at:lastNight:goodnightAt:focus:windDownActive:checkInDue:)`. A morning with neither last night's sleep nor a Goodnight shows tonight's wind-down start as a clock time ("22:15" · "wind-down tonight · bed 23:00"), never a countdown; the day shows the countdown to wind-down until focus ships.
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
- `collection.permissionPrompt(at:)`: when `nextLeaf(at:)` is nil because nothing can be earned without a permission (no Apple Health: every M1 sleep category needs it), the cheapest leaf turning it on would make earnable, by design pace. Home draws it as `NextLeafRow(.needsPermission(prompt), action:, turnOn:)`: the neutral skeleton at 50%, the name with "Needs Apple Health", and a "Turn on Apple Health" `TextLink` that opens the primer. It is not a next leaf: D9 keeps needs-permission leaves out of the next leaf, buds, Almost there and pacing.
- Copy: `RewardCategoryInfo(progress.category)` has `definition`, `shortRule(_:)`, `earnedLine(_:)`, `action`; the leaf's rule is `RewardCatalog.shared.reward(forSpecies:)?.unlockText`. `LeafRemainder(progress, phase:).amount` is "11 of 14". Estimates ("about 5 nights at your pace") are for leaf detail only.
- Actions: `collection.pin(id)` / `unpin()`, `collection.feature(id)` (earned leaves only), `collection.markSeen(id)` / `markAllSeen()`, `collection.isUnseen(id)` for the amber dot, `collection.featuredLeaf` for the avatar.

## Reveals

```swift
let startedAt = clock.now()
let queue = collection.revealable(at: startedAt)                      // what can be opened now, oldest first
let opened = collection.openReveals(ids, at: clock.now(), eligibleAt: startedAt)   // marks them revealed and returns them
let firstThree = collection.revealsOpened < 3                         // full ritual for the first 3 reveals ever
```

Leaves earned from Evening until the next Morning are held (`collection.held(at:)`), and nothing opens in wind-down or at night, except the First-steps leaf at the end of onboarding (D12). A reveal passes its start as `eligibleAt`, so leaves the member watched open in Evening are still placed when "Place on your maple" comes after Wind-down has begun; before opening another bud it checks `revealable(at: now)` again (`RevealSession.mayOpen(all:openable:)`) and stops at "Opens in the morning" once it is empty. `collection.waiting` lists every unopened leaf (Herbarium "Waiting" tiles); when it is non-empty but `revealable` is empty, show "Opens in the morning". `openReveals(["rubrum"], at:)` opens just that one. After the first morning reveal, ask for rarity consent if `collection.rarityConsent == .notAsked`, and record the answer with `collection.setRarityConsent(_:)`.

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

Also on the store: `stage` (Seedling … Grand maple, from opened leaves), `tendedDays` ("grown over 41 days"), `vitality(at:)` (from the nights of the week before that day; `.isQuiet` is VoiceOver's "Resting."), `currentBedtimeRun` (Home's streak; hidden under 2) and `totals` (Profile; a nil total means its category doesn't exist yet).

**Counts.** "N of 155" counts opened leaves only, everywhere (spec §5.2): read `collection.leafCount` (`LeafCount`: `opened`, `waiting`, `total`, `text` "23 of 155", `waitingText` "1 waiting", `spoken`) or `collection.openedCount`. `LeafCount(progressRows)` counts one Herbarium section. Never use `earned.count + waiting.count`.

**First run.** `schedule.firstRun` (`FirstRunStep`: `.schedule`, `.recordFirstLeaf`, `.sprout`, `.finished`) decides whether onboarding shows; `MapleApp` calls `schedule.resumeFirstRun(at:)` once at launch, which also records the Sugar maple if an earlier launch was stopped between saving the schedule and saving the collection. `collection.hasPlantedMaple` is true once the First-steps leaf is earned; `collection.firstLeaf` and `collection.hasPlacedFirstLeaf` say whether it has been opened and placed.

**Fitting the first screen.** `HeroFit(preferred:minimum:visible:content:action:)` (MapleDesign) gives the hero's height at every text size, and whether the action must be pinned above the tab bar (Home's stage, Rest's dial).

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

Data sources call the collection; it runs the engine and returns new leaves. The M1 sleep categories (Nights tracked, On-time bedtimes, Bedtime runs, Steady weeks, Seasons in rhythm, Steady mornings, Full nights) come **only from Apple Health** (rewards.json data sources, spec D9: there is no manual self-report fallback). Wind-down mode's Goodnight tap is the phone-down time in the bedside log, for wind-down's own state and Home's "Morning, no Apple Health" numeral (§3.4); it feeds no counter, so no leaf can be earned by tapping.

M1's HealthKit importer makes one call, and nothing in the app makes it yet:

```swift
let observations: [SleepNightObservation] = …            // one per night: the main episode, best source available
collection.recordSleep(observations, at: clock.now())      // returns the leaves it unlocked
```

`SleepNightObservation` (MapleCore) is the night (named by its evening; nights run 18:00 to 18:00), the main episode's sleep onset and final wake, the minutes asleep (nil for iPhone's in-bed estimate) and its `SleepSource`, rewards.json's ladder: `.watchOrTracker` (A: asleep stages from an Apple Watch or an allow-listed tracker), `.otherApp` (B: asleep samples another app wrote), `.iPhoneInBed` (C: "estimated from iPhone", times only). The importer resolves sources, groups samples into nights, drops user-entered samples and naps; `NightLedger` (MapleCore) judges what it is given:

- Counting starts on the install night (the night the first schedule was saved in) when setup finished before sleep began. A night is judged by the schedule in force at 18:00 that evening (`ScheduleStore.save` tells the collection, which keeps the replaced one for nights under way); the very first schedule judges the install night only if it was saved at least 30 minutes before its bedtime (otherwise that night is tracked but unscheduled, which is neutral).
- Tracked: a main episode of 3 hours or more. On time: onset from bedtime − 2 h to bedtime + 30 min (earlier is early: neutral). Steady morning: final wake within 30 minutes of the wake time. Full night: asleep at least the sleep need − 30 minutes (`CollectionContext.sleepNeedMinutes`, from Settings › Sleep goal), only from sources with asleep time.
- A night settles once its next morning starts (wake − 60 min); a night with nothing from Apple Health by then is untracked (a slip for the run). For 72 hours after that, late data (a Watch syncing) can upgrade a night, never downgrade it, and the run and a closed week are replayed with it. Recording the same nights again changes nothing, so the importer can send the last few nights on every run.
- Settling records Nights tracked, On-time bedtimes, Steady mornings and Full nights per night, the live bedtime run (5 of every 7 nights on time: two slips in 7 forgiven, a third ends it; early and unscheduled nights are neutral) with the best run as the counter, Steady weeks (5+ on-time nights, counted as the calendar week closes) and Seasons in rhythm (a season's 8th steady week; a week belongs to the season of its Thursday), plus each tracked night for vitality. Leaves are stamped with the call's time, so ones earned in the morning or day open at once and ones earned from Evening on are held until morning.
- Once a night with asleep time has arrived, the collection adds `.sleepTracker` to Apple Health (`collection.permissions`), so Full nights become earnable; with iPhone in-bed data only they show "Needs a sleep tracker".
- DEBUG demo stores are built with their counters and are never fed nights.

Lower-level calls (tests, demos, and later sources):

```swift
collection.record([.focusDays: 1], at: now)                            // increments
collection.raise(.bedtimeRun, to: 12, at: now)                         // high-water marks
collection.setCurrentBedtimeRun(12, at: now)
collection.recordNight(NightRecord(day: LocalDay(now, calendar: .current), onTime: true, fullNight: nil, scrollFree: nil))
```

Counters never go down. Any rise marks the day tended (tree growth), except First steps and Community challenges. A locked Bedtime-runs leaf shows progress from the live run (`currentBedtimeRun`), not the best one, so "Tonight" appears only when tonight can finish it.

## Files, unlocks and time zones

- `JSONStorage.read()` tells a missing file (`.absent`, a first run) from one that can't be read yet (`.unavailable`: a launch before the first unlock after a restart, or another I/O error). Only a file that reads but won't decode is set aside as `<name>.damaged-<time>.json`; an unreadable one is left alone and every save to it is refused until a read works. A missing file with a cleanly decoding set-aside copy beside it is restored.
- `CollectionStore`, `ScheduleStore` and `AppSettings` expose `isAvailable` and `reloadIfUnavailable()`. While unavailable they hold an in-memory placeholder that is never saved; any change reads the file first. `ThemedRoot` reloads when protected data becomes available or the app becomes active, then decides the first-run step again and rebuilds the root (`MapleStores.reloadIfUnavailable()`).
- The live store uses `Calendar.autoupdatingCurrent`. `ThemedRoot` calls `collection.systemTimeChanged()` on `NSSystemTimeZoneDidChange` and significant time changes, which rebuilds cached progress and refreshes every screen that read `collection.context`. The `\.season` environment is read every minute.

## Shipped features and permissions

`collection.context.features` is `ShippedFeatures.current` (M1 only): `.focus`, `.sleepSounds`, `.screenTime`, `.checkIns` are false and their categories are dormant ("Not earnable yet"). A feature that hasn't shipped is absent from every screen.

`collection.context.permissions` (`GrantedPermissions`) is real: empty until the member has been through Apple's Health prompt, then `.appleHealth`. `collection.permissions` adds `.sleepTracker` once Apple Health has delivered a night with asleep time. `collection.availability(of:)` gives a category's state: every M1 sleep category but Full nights needs Apple Health (`.needsAppleHealth`), Full nights needs a sleep tracker too (`.needsSleepTracker`), and First steps needs nothing. Needs-permission leaves show "Needs Apple Health" (tiles, section headers with "Turn on", leaf detail with "Turn on Apple Health"), have no estimate, and are left out of the next leaf, buds, Almost there, pacing and Profile's totals (D9).

`HealthPermission` (MapleServices) owns Apple Health:

```swift
@Environment(HealthPermission.self) private var health

health.isConnected                                // the member has been through Apple's prompt
await health.requestAccess(at: clock.now())       // Apple's sheet: HKHealthStore.requestAuthorization(toShare: [], read: [sleepAnalysis])
health.apply(to: collection)                      // grants (or withdraws) .appleHealth in the collection's context
```

HealthKit never says whether reading was allowed, only whether its prompt was answered, so `requestAccess` records that the member completed it (`health.json`) and Apple Health counts as connected from then on; M1's importer reads whatever they allowed. `ThemedRoot` calls `health.refresh(at:)` and `apply(to:)` on every foreground, so a reset of the member's Health answers shows as not connected again. Every "Turn on Apple Health" presents `HealthPrimerSheet` (App), the calm primer (`HealthPrimerView` in MapleDesign: one leaf, two sentences, "Continue", "Not now"), whose Continue calls `requestAccess`; Screen Time's "Turn on" will open Settings once it ships (`turnOnPermission(_:speciesID:showHealthPrimer:openURL:)`).

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

`DemoData.snapshot(species:tendedDays:waiting:now:)` gives a plausible collection directly, and `PreviewLeafShareProvider` gives tier-correlated rarity. Both exist only in DEBUG. Demo stores are granted Apple Health and a sleep tracker unless `-MapleDemoPermissions` says otherwise, so a demo collection shows earned progress; add `.environment(stores.health)` for screens that offer "Turn on Apple Health".
