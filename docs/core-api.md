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
    @Environment(ScheduleStore.self) private var schedule       // weekday and weekend wake, bedtime, wind-down
    @Environment(LeafShareStore.self) private var shares        // "% of members have this leaf"
    @Environment(HealthPermission.self) private var health      // Apple Health: connected or not, and the prompt
    @Environment(HealthSleepImporter.self) private var sleep    // Apple Health's sleep: last night, the no-sleep hint
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

`collection.nowState(at:)` resolves the §3.4 table: phase, numeral, caption and the one primary action.

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
- `state.refreshesEverySecond` is true while a session runs (in every phase, night included): its time shows calm minutes ("18m"), with seconds only in the last minute.
- Inputs that don't exist yet are optional and default to the documented fallbacks: `nowState(at:lastNight:goodnightAt:focus:windDownActive:)`. Home passes `sleep.lastNightSleep(at: now)` as `lastNight` ("7h 12m" · "asleep 23:08 · up 06:20"; for iPhone's in-bed estimate the time in bed). A morning with neither last night's sleep nor a Goodnight shows tonight's wind-down start as a clock time ("22:15" · "wind-down tonight · bed 23:00"), never a countdown; once focus ships the day shows saved today ("1h 20m" · "saved today · 41h in all"), the lifetime total before the day's first session, and the wind-down countdown without Screen Time (with "Turn on blocking"); a morning with no sleep data shows what was saved yesterday. `focus` is a `FocusStatus`, which F1b builds from `FocusSessionStore.displayCredit(at:)` and the last-used preset's `FocusStart`; until then Home leaves it out (nil).
- Lower level: `NowPhase.resolve(date:weekly:calendar:)` (or `schedule:` for one schedule every night), `PhaseWindows(weekly:)` (`day(containing:calendar:)` for a day's phase starts, `sampleDate(in:onDayOf:calendar:)` for previews), `HomeFormat` (durations "1h 20m", locale clock times).

## Leaves: progress, next leaf, buds, Almost there

```swift
let next = collection.nextLeaf(at: now)                    // Home's next-leaf row (pinned, lowest hours rung, closest)
if let next {
    let remainder = LeafRemainder(next, phase: state.phase)
    Text(remainder.text)                                    // "3 nights", "Tonight", "1h 40m"
    if remainder.showsBar { ProgressHairline(fraction: next.fraction) }
}
```

- The 7 categories (`RewardCategoryID`, canonical order, rewards.md): `firstLeaf`, `hoursSaved`, `sessionsFinished`, `focusStreak`, `phoneFreeMornings`, `bedtimeKept`, `restedNights`. This build ships M1 and F1 (`ShippedFeatures.current`): First leaf, Hours saved, Sessions finished, Focus streak and Rested nights can be earned, and Phone-free mornings and Bedtime kept (F2) are dormant. A build that can't block (every free build) shows the three focus ladders as `.notInThisBuild`, so its Home keeps Rested nights.
- `collection.progress(at:)`: all 155 `LeafProgress` rows in canonical order (category, then rung). `progress(for:at:)` for one leaf. Each row has `state` (`.earned(unlock)`, `.waiting(unlock)`, `.locked`), `availability` (`.available`, `.needsAppleHealth`, `.needsScreenTime`, `.notInThisBuild` and `.dormant`), `current` (clamped), `fraction`, `floor`, `rungFraction`, `remaining` and `estimatedDays` (nil when earned, waiting or unavailable). `.notInThisBuild` reads "Not available in this build": a free build's Screen Time leaves, with no button; Home's pick treats it like `.dormant`. `floor` is the threshold of the rung below (0 for the first rung); `rungFraction` is progress within the rung, used only for the dial's leaf fill, and every other surface uses `fraction`.
- `collection.buds(at:)`: the tree's 3 buds, Home's next leaf first.
- `NextLeafPicker(progress:)` (MapleCore) holds the rule (focus spec §4.5): `next(pinned:)` is a pinned leaf while it is locked and available, otherwise the lowest hours-saved rung, otherwise the closest of `homeCandidates`; `buds(pinned:)` puts that leaf first; `homeCandidates` is every candidate, except that Rested nights is left out once any focus category has shipped; `permissionPrompt()` answers only when `homeCandidates` is empty. There is no phase preference.
- `collection.almostThere(at:)`: up to 6 leaves within 60 days (hide the rail below 2).
- `collection.nextRungIDs(at:)`: species drawn as "Next" tiles (3 per available category).
- `collection.permissionPrompt(at:)`: when `nextLeaf(at:)` is nil because nothing can be earned without a permission (on a build that can't block, no Apple Health: Rested nights needs it; on one that can, no Screen Time: once focus ships Rested nights is never Home's pick, and the hours ladder needs Screen Time), the cheapest leaf turning it on would make earnable, by design pace. Home draws it as `NextLeafRow(.needsPermission(prompt), action:, turnOn:)`: the neutral skeleton at 50%, the name with "Needs Apple Health", and a "Turn on Apple Health" `TextLink` that opens the primer; for Screen Time, "Needs Screen Time" and "Turn on Screen Time", which opens the Focus tab's Needs Screen Time. It is not a next leaf: D9 keeps needs-permission leaves out of the next leaf, buds, Almost there and pacing.
- Copy: `RewardCategoryInfo(progress.category)` has `definition`, `shortRule(_:)`, `earnedLine(_:)`, `action`; the leaf's rule is `RewardCatalog.shared.reward(forSpecies:)?.unlockText`. `LeafRemainder(progress, phase:).amount` is "11 of 14". Estimates ("about 5 nights at your pace") are for leaf detail only.
- Actions: `collection.pin(id)` / `unpin()`, `collection.feature(id)` (earned leaves only), `collection.markSeen(id)` / `markAllSeen()`, `collection.isUnseen(id)` for the amber dot, `collection.featuredLeaf` for the avatar.

## Reveals

```swift
let startedAt = clock.now()
let queue = collection.revealable(at: startedAt)                      // what can be opened now, oldest first
let opened = collection.openReveals(ids, at: clock.now(), eligibleAt: startedAt)   // marks them revealed and returns them
let firstThree = collection.revealsOpened < 3                         // full ritual for the first 3 reveals ever
```

Leaves earned from Wind-down until the next Morning are held (F1-12: a leaf earned in Evening can open that evening) (`collection.held(at:)`), and nothing opens in wind-down or at night, except the First-steps leaf at the end of onboarding (D12). A reveal passes its start as `eligibleAt`, so leaves the member watched open in Evening are still placed when "Place on your maple" comes after Wind-down has begun; before opening another bud it checks `revealable(at: now)` again (`RevealSession.mayOpen(all:openable:)`) and stops at "Opens in the morning" once it is empty. `collection.waiting` lists every unopened leaf (Herbarium "Waiting" tiles); when it is non-empty but `revealable` is empty, show "Opens in the morning". `openReveals(["rubrum"], at:)` opens just that one. After the first morning reveal, ask for rarity consent if `collection.rarityConsent == .notAsked`, and record the answer with `collection.setRarityConsent(_:)`.

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
    newLeafHalos: tree.newLeafHalos.map { .init(speciesID: $0.speciesID, placedAt: $0.placedAt) },
    unlockOrder: tree.unlockOrder
)
```

`tree.unlockOrder` lists every earned leaf (opened, waiting or held) in unlock order. Pass it on: each species' place on the crown is fixed by its unlock index (spec §4.5), so opening an older waiting leaf after a newer one moves nothing, and each waiting bud hangs where its leaf will grow.

The scene and Home's sky pause on their last frame (a paused timeline, never a repaint) off screen, while the app is inactive, in Low Power Mode, under a full-screen cover (`.environment(\.treeScenesPaused, true)`) and after a minute at Night without a tap. Put `.nightIdleFreeze(phase:)` (MapleDesign) on a screen that shows both, so they freeze and wake together; `SkyBackdrop(…, paused:)` takes the caller's own reasons.

Also on the store: `stage` (Seedling … Grand maple, from opened leaves), `tendedDays` ("grown over 41 days"), `vitality(at:)` (from the nights of the week before that day; `.isQuiet` is VoiceOver's "Resting."), and `totals` (Profile: hours saved, sessions, rested nights and phone-free mornings; a nil total means its category can't be earned yet).

**Counts.** "N of 155" counts opened leaves only, everywhere (spec §5.2): read `collection.leafCount` (`LeafCount`: `opened`, `waiting`, `total`, `text` "23 of 155", `waitingText` "1 waiting", `spoken`) or `collection.openedCount`. `LeafCount(progressRows)` counts one Herbarium section. Never use `earned.count + waiting.count`.

**First run.** `schedule.firstRun` (`FirstRunStep`: `.schedule`, `.recordFirstLeaf`, `.sprout`, `.finished`) decides whether onboarding shows; `MapleApp` calls `schedule.resumeFirstRun(at:)` once at launch, which also records the Sugar maple if an earlier launch was stopped between saving the schedule and saving the collection. `collection.hasPlantedMaple` is true once the First-steps leaf is earned; `collection.firstLeaf` and `collection.hasPlacedFirstLeaf` say whether it has been opened and placed.

**Fitting the first screen.** `HeroFit(preferred:minimum:visible:content:action:)` (MapleDesign) gives the hero's height at every text size, and whether the action must be pinned above the tab bar (Home's stage, the Focus start screen's dial). A page laid out around the hero fills `fit.pageMinHeight(visible:)`: the visible height while everything fits, nil once the action is pinned, so the page keeps its natural height and only real overflow scrolls under the pinned action.

## Rarity: "% of members have this leaf"

```swift
MemberShareLabel(share: shares.share(for: speciesID), layout: .detail)
MemberShareLabel(share: shares.share(for: id), layout: .tile, pressedOn: collection.unlock(for: id)?.date)
```

`share(for:)` returns every `MemberShare` state: `.loading`, `.value` (under 48 hours old), `.stale`, `.notEnoughMembers` (under 1,000), `.neverFetched`, `.newSpecies`, `.notEarnableYet`. The app refreshes on foreground (at most once a day). For sorting by rarity and "Your rarest", use `shares.estimate(for:)` (fresh values only). The explainer reads `shares.memberCount` (rounded down to 100) and `shares.weekStart`. Release builds use `UnconfiguredLeafShareProvider`, so every leaf reads "Rarity appears once 1,000 members take part" until the CloudKit provider exists (see the TODO on `LeafShareProvider`).

## Schedule

The member has a `WeeklySleepSchedule` (MapleCore): a `weekday` `SleepSchedule` and an optional `weekend` one (nil: the same every night). A night is named by its evening (`LocalDay`; nights run 18:00 to 18:00) and is a weekend night when the morning it wakes into is a weekend day in the member's calendar (`Calendar.isDateInWeekend`, so the region decides): with a Saturday–Sunday weekend that is Friday and Saturday nights, with a Friday–Saturday weekend Thursday and Friday nights.

```swift
@Environment(ScheduleStore.self) private var schedule

schedule.weekly                                   // WeeklySleepSchedule: what the member saved (.standard until then)
schedule.tonight(at: now)                         // SleepSchedule: tonight's times, in the collection's calendar
schedule.schedule                                 // the same on the store's clock (the frozen clock in DEBUG demos)
schedule.weekly.differsOnWeekends                 // a separate weekend exists

let unlocked = schedule.save(.everyNight(SleepSchedule(bedtime: ClockTime(hour: 23), wake: ClockTime(hour: 7), windDownMinutes: 45)),
                             at: clock.now())
// First save: unlocked == [Sugar maple] (First leaf), revealable at any hour. Later saves: [].
let split = WeeklySleepSchedule(weekday: weekday,
                                weekend: SleepSchedule(bedtime: ClockTime(hour: 0, minute: 30), wake: ClockTime(hour: 9)))
schedule.save(split, at: clock.now())
```

"Tonight" is the night named by today's evening, from this morning's start (an hour before today's wake-up) until the next morning's; at 02:00 it is still the night that began yesterday evening. So on a Friday, Settings' "Sleep schedule" row, Home's "bed 00:30" and wind-down use the weekend times from Friday morning until Saturday morning. Lower level, all pure and in the calendar you pass:

```swift
let weekly = schedule.weekly
let calendar = collection.context.calendar
weekly.currentNight(at: now, calendar: calendar)                   // LocalDay: tonight
weekly.tonight(at: now, calendar: calendar)                        // tonight's SleepSchedule
weekly.lastNight(at: now, calendar: calendar)                      // last night's (its wake-up is this morning's)
weekly.schedule(forNight: night, calendar: calendar)               // one night's schedule
WeeklySleepSchedule.variant(forNight: night, calendar: calendar)   // .weekday or .weekend
weekly.times(forNight: night, calendar: calendar)                  // one night's NightTimes

// Reminders: tonight first, then each following night, as dates.
for night in weekly.upcoming(from: now, days: 7, calendar: calendar) {
    night.night          // LocalDay (the evening)
    night.variant        // .weekday or .weekend
    night.schedule       // the SleepSchedule it uses
    night.windDownStart  // bedtime − windDownMinutes
    night.bedtime        // that evening, or the next morning for a time before 18:00
    night.wake           // the first wake-up after bedtime
    night.morningStart   // wake − 1 h: the next morning phase, when the night settles
}
```

`upcoming` includes tonight even when some of its times have passed (keep those `> now`), and it reflects the schedule as it is now: call it again after a save. The phases (`PhaseWindows(weekly:)`), Home's captions, wind-down, the bedside log and the night ledger all read these same `NightTimes`, so they always agree.

- A day's morning and day come from last night's wake-up, its evening, wind-down and night from tonight's schedule, so a Saturday morning starts on the weekend wake-up and Sunday evening winds down on the weekday times. Each window is clamped into its day (this morning's start to the next), so no schedule can make two mornings overlap.
- Saving applies at once to phases and held reveals, but a night already under way (an edit after 18:00) is still judged by the schedule it began with: edits apply from the next night (rewards.md), so a bedtime can't be moved after the fact. A night is judged by the variant that schedule gives it: a Friday night by the weekend times.
- `windDownStart` and `minutesInBed` are on `SleepSchedule`.
- **Files.** `schedule.json` holds `SavedSchedule { schedule: WeeklySleepSchedule, savedAt }`. A weekly schedule encodes the weekday schedule's own fields (`bedtime`, `wake`, `windDownMinutes`) plus an optional `weekend` object, so a file from before weekends decodes as the same schedule every night with nothing lost, and an older build reading a newer file still gets the weekday schedule. The collection's record of past schedules (for nights under way) uses the same encoding.
- **Onboarding.** `OnboardingStore` (MapleServices, `onboarding.json`, injected by `MapleApp`) holds the first run's step and answers (`OnboardingProgress` and `OnboardingAnswers`, MapleCore): weekday wake-up, weekend wake-up (nil: the same), sleep need (7h to 9h, 7h 30m to start) and wind-down length, the adjusted schedule if any, and whether the Apple Health and notifications primers were answered. `OnboardingAnswers.proposedSchedule` is the schedule the answers propose: bedtime = wake − sleep need − 15 minutes, per variant. `onboarding.step(schedule:collection:)` gives the screen a relaunch resumes on (nil once the Sugar maple is revealed). The schedule step's "Save schedule" makes the one `schedule.save(_:at:)` call and writes the sleep need to `AppSettings.sleepGoalMinutes`; the Apple Health and notifications primers come after it.

## Reminders (local notifications)

Maple sends at most three kinds of notification: **"Time to wind down"** · "Bed at 23:00." at each night's wind-down start; **"Session done"** · "Study, 50 minutes" at a running session's planned end (a plain timer reads **"Timer done"** · "50 minutes"; scheduled with an absolute trigger, exempt from the night rule); and the opt-in **"Ready to study?"** once a day in the Day phase, skipped on a day a session started. There is no morning notification (rewards.md; focus spec §8). `App/Features/Notifications/ReminderUpkeep.swift` keeps them scheduled through `ReminderInputs` (MapleServices); screens only read the scheduler.

```swift
@Environment(NotificationScheduler.self) private var reminders   // MapleApp injects it
reminders.authorization                // .notDetermined, .denied or .allowed (read again on every foreground)
await reminders.requestAuthorization() // iOS's prompt: alerts and sounds, never badges
settings.windDownReminder              // AppSettings switch, on by default; sent only once iOS allows
settings.sessionEndReminder            // "Session done" at a session's planned end; on by default
settings.studyReminderTime             // the daily study reminder's ClockTime; nil while it is off (the default)
```

- **The plan.** `ReminderPlan(.init(nights:settings:windDownOpenedAt:now:calendar:locale:schedule:runningSession:lastSessionStart:))` (MapleCore, pure) gives `requests` (deterministic identifiers under three prefixes, `ReminderKind.identifierPrefix`: `maple.reminder.windDown.<night>`, `maple.reminder.sessionEnd.<session id>` and `maple.reminder.studyReminder.<day>`; fire dates as local wall-clock components, title, body, thread, interruption level) and `staleDelivered` (a delivered reminder that no longer holds, cleared from Notification Center). Nights are `UpcomingNight` values (wind-down start, bedtime, wake, morning start) from the member's weekly schedule: `UpcomingNight.nights(for: schedule.weekly, around:calendar:)`, so weekend nights wind down on the weekend schedule. Wind-down is skipped once wind-down mode has been opened that night (`BedsideLog`'s start). Nothing fires between bedtime and the morning start, except a session's end.
- **Scheduling.** `reminders.reschedule(plan:now:)` makes Maple's pending requests exactly the plan's (only `maple.reminder.` identifiers, so a morning reminder left by an earlier build is removed; at most the next 7 days; nothing while iOS doesn't allow it). `ReminderUpkeep` calls it on every foreground and whenever its inputs change: a schedule save, the switch, wind-down mode opening, iOS's answer, a time-zone or clock change, a session starting or ending. The plan is built, and filtered, at the session store's trusted time (`sessions.now`), and nothing is rescheduled before the store's first replay (`ReminderInputs.plan` is nil while `isLedgerReadable` is false), so the requests already pending stay. DEBUG demo launches never reschedule.
- **In the foreground, and taps.** `NotificationDelegate` (App, nonisolated, set in `MapleApp.init` before launch finishes) presents nothing while Maple is open, for all three kinds: a session's end has its receipt on screen. A tap on a session's end hands that session to `NotificationRouter` (`tappedReceipt`), and `RootView` opens its receipt on the Focus tab (`router.showFocus(.receipt(id))`), after a cold launch too. Wind-down and the study reminder just open Maple.
- **Asking.** Settings shows the switch with a status line: "Allow reminders" opens `NotificationsPrimerSheet` (`NotificationsPrimerView` in MapleDesign: the member's featured leaf, "A gentle reminder", "When a session ends, and when it's time to wind down. Nothing else.", "Allow reminders", "Not now") before iOS has been asked, and "Turn on in Settings" opens Maple's notification settings once the member has said no. In the first run, onboarding's notifications step (`OnboardingNotificationsStep`) shows `NotificationsPrimerStep(onContinue:)` full screen while iOS hasn't been asked, and continues at once once it has. The first session start also asks iOS once, if it hasn't been asked yet (F1-23).

## Recording behaviour

Data sources call the collection; it runs the engine and returns new leaves. Rested nights, the one sleep category, comes **only from Apple Health** (rewards.json data sources, spec D9: there is no manual self-report fallback). Wind-down mode's Goodnight tap is the phone-down time in the bedside log, for wind-down's own state and Home's "Morning, no Apple Health" numeral (§3.4); it feeds no counter, so no leaf can be earned by tapping.

M1's HealthKit importer (`HealthSleepImporter`, MapleServices) makes one call:

```swift
let observations: [SleepNightObservation] = …            // one per night: the main episode, best source available
collection.recordSleep(observations, at: clock.now())      // returns the leaves it unlocked
```

`MapleApp` creates it once (`HealthSleepImporter.launch(stores:backgroundDelivery:)`) and injects it; it runs on every foreground, right after Apple's prompt (`HealthPrimerSheet`), and from an `HKObserverQuery` while the app runs (background delivery only in builds with its entitlement: docs/entitlements.md). It does nothing until Apple Health is connected and the maple is planted.

```swift
@Environment(HealthSleepImporter.self) private var sleep

await sleep.importNow(at: clock.now())          // read what changed, rebuild the window's nights, record them
sleep.lastNightSleep(at: now)                   // Home's morning numeral; nil when Apple Health has nothing for last night
sleep.lastNight                                 // the most recent night it built (settled or provisional)
sleep.hasReceivedSleep                          // a sleep sample that counts has arrived since connecting
sleep.showsNoSleepHint(at: now)                 // connected 2+ nights with none: Privacy's line, and Home's row
sleep.lastImportAt
```

- The pure part is in MapleCore/Health: `SleepSample` (HealthKit's sample as plain values), `SleepSourceResolver` (the A/B/C ladder: an Apple Watch by product type "Watch…" or device model "Watch", an allow-listed tracker's bundle id, which is a list to review; other apps; iPhone's own in-bed samples; typed-in samples never count), `SleepNightBuilder` (nights cut at 18:00 local in the sample's zone, one source per night, the longest cluster with gaps under 60 minutes merged, onset at the first 20-minute asleep block, final wake at the end of the last, awake time left out of the minutes asleep), `SleepImportWindow` and `SleepDataHint`.
- It reads a bounded window: from the night before the install night (no backfill), at most the last 16 nights, so every night the ledger can still settle or upgrade is sent again on each run. An anchored query reads only what changed; deleted samples drop out and their nights are rebuilt (a night still pending takes the rebuilt observation when its source is as good; settled results only ever upgrade).
- Its cache (`LocalHealth/sleep-import.json`: the window's samples and the anchor) is health data, so it is local only: protected until first unlock, excluded from backups, never synced (guideline 5.1.3(ii)). A locked iPhone keeps everything and reads again on unlock; no error clears it.

`SleepNightObservation` (MapleCore) is the night (named by its evening; nights run 18:00 to 18:00), the main episode's sleep onset and final wake, the minutes asleep (nil for iPhone's in-bed estimate), its `SleepSource`, rewards.json's ladder: `.watchOrTracker` (A: asleep stages from an Apple Watch or an allow-listed tracker), `.otherApp` (B: asleep samples another app wrote), `.iPhoneInBed` (C: "estimated from iPhone", times only), and optionally `timeZoneIdentifier`, the zone the night was spent in (HealthKit's `HKMetadataKeyTimeZone` when the samples carry it). The importer resolves sources, groups samples into nights, drops user-entered samples and naps; `NightLedger` (MapleCore) judges what it is given:

- A night's bedtime and wake time are read in the zone it was spent in: the observation's own, or else the one in force when it is recorded (the ledger stamps it then), so flying between a night and its settling never turns an on-time night late. `SleepNightObservation(onset:finalWake:asleepMinutes:source:calendar:)` names the night and the zone from one calendar.
- Counting starts on the install night (the night the first schedule was saved in) when setup finished before sleep began. A night is judged by the schedule in force at 18:00 that evening, with the times it gives that night (weekend times on a weekend night; `ScheduleStore.save` tells the collection, which keeps the replaced one for nights under way); the very first schedule judges the install night only if it was saved at least 30 minutes before its bedtime (otherwise that night is tracked but unscheduled, which is neutral).
- Tracked: a main episode of 3 hours or more. On time: onset from bedtime − 2 h to bedtime + 30 min (earlier is early: neutral). Steady morning: final wake within 30 minutes of the wake time. Full night: asleep at least the sleep need − 30 minutes (`CollectionContext.sleepNeedMinutes`, from Settings › Sleep goal), only from sources with asleep time.
- A night settles once its next morning starts (wake − 60 min); a night with nothing from Apple Health by then is untracked (a slip for the run). Every night since the last settle is settled in turn, however long the app was closed; only an absence of more than two years skips straight to the last two, and never past a night Apple Health had already delivered. For 72 hours after that, late data (a Watch syncing) can upgrade a night, never downgrade it, and the run and a closed week are replayed with it. Recording the same nights again changes nothing, so the importer can send the last few nights on every run.
- Settling raises Rested nights (`rested_nights`) by one for each night judged on time, including a night a late upgrade turns on time; Apple Health's on-time nights raise nothing else. The ledger still keeps its own run, steady weeks and seasons, which no category reads. Each tracked night is also kept for vitality. Leaves are stamped with the call's time, so ones earned before Wind-down open at once and ones earned in Wind-down or at night are held until morning.
- Once a night with asleep time has arrived, the collection adds `.sleepTracker` to `collection.permissions`; no category needs it now.
- DEBUG demo stores are built with their counters and are never fed nights.

Lower-level calls (tests, demos, and later sources):

```swift
collection.record([.sessionsFinished: 1], at: now)                     // increments
collection.raise(.focusStreak, to: 12, at: now)                        // high-water marks
collection.recordNight(NightRecord(day: LocalDay(now, calendar: .current), onTime: true, fullNight: nil, scrollFree: nil))
```

Counters never go down. Any rise marks the day tended (tree growth), except First leaf.

## Focus (F1 design §3, §7)

Credit is a pure pipeline: the session ledger (`FocusLedger`, JSON lines per writer per month) → `SessionRecord` (one session's proof, breaks, overrides and end) → `HoursCredit` (counted seconds per session, with labelled stretches for Saved today) → `FocusBook` in the collection (per-day high-water marks, frozen 3 days on) → the counters, applied as dated marks so each leaf is dated when its credit was proven. Screens never compute any of it.

`MapleStores.focus` holds a launch's Focus stores (`FocusStores`): `sessions` (`FocusSessionStore`), `presets`, `appSets` and `notes`. `MapleApp` puts each store in the environment, and the struct itself as `\.focusStores` (a struct can't go through `.environment(_:)`); `.focusUpkeep()` keeps the session store current. How the screens read them is below, after the store's own rules.

```swift
let store = stores.focus.sessions
await store.refresh()                                   // on launch, every foreground, and from a running session's timeline
let outcome = await store.start(.init(preset: preset, minutes: 50, appSet: appSet, from: .focusTab))
// .started(id), .alreadyRunning, .ledgerUnavailable, .blockingFailed(failure) ("Couldn't lock your apps"), .notRecorded
store.running                                           // the running session (SessionRecord), drawn from the ledger
store.displayCredit(at: now)                            // today, yesterday and total seconds: counted plus provisional
await store.end(.endedEarly)                            // or .emergencyRelease; .completed happens on refresh at the planned end
await store.startBreak(); await store.endBreak()        // one locked break, inside the planned length
await store.releaseAllUnlessRunning()                   // Settings › Release all apps, confirmed: false means a session runs, so its way out opens first
await store.releaseAll()                                // clears every store and ends a running session's credit, as that way out completes
await store.reflect(.partly, on: id)                    // the receipt's "How did it go?"
```

- **Starting.** The block is applied and read back before anything is written; a second Start while one is starting is refused. Without an app set, or on a build that can't block, a session is a plain timer that counts nothing.
- **Proof.** Each `refresh()` reads the block back and writes a checkpoint at most once a minute, and at once on the first read-back in a boot. If the block has gone, the session is marked lost and runs on as a plain timer; credit stops at the last checkpoint.
- **Reading the ledger.** Each command reads the ledger once (the open months; `FileLedgerStore` decodes only what was appended since its last read) and merges what it writes into its replay in memory. When that read shows a sign of a missing start (events that can change a session's credit, without its `sessionStarted` or its end, or applied shields whose session it doesn't show running, as a clock set far forward can cause), the command also reads the whole ledger and adds every session it holds unended, and nothing else of the history; shields are cleared as orphaned only after that full read finds no unended session for them. An ended session whose start has left the open read (one that ran across the 1st), or a lone reflection, is no such sign.
- **Unknown state.** While the ledger can't be read (`isLedgerReadable` false) the store neither writes nor clears, except that Release all apps always clears. Nothing is written before the writer can read this install's device id and its last sequence number (both are locked before the first unlock after a restart): never under a stand-in.
- **Permissions.** The store grants `.screenTime` in `collection.context.permissions` while blocking is available and allowed, and sets `collection.context.blocking` to the build's capability. A free build's Screen Time leaves read "Not available in this build" (`LeafAvailability.notInThisBuild`), with no button.
- **Pure helpers for the screens:** `DialLayout` (marks, angles, turning), `FocusTimeText` (calm minutes), `SessionForecast` (the leaf dot's minute and the counts line), `StartReadiness` (Home's Start and Again), `RecentIntentions` (the intention chips), `FocusPreset` (presets and the strictness rule), `LeafProgress.rungFraction` (the dial's leaf fill) and `collection.currentRun(at:)` (the header streak).
- **Launch modes** (`LaunchMode`): live (files in the container; only `live` events credit), demo (memory, the preview blocker; its preview sessions credit in memory, and nothing is saved), and the DEBUG sandbox (`-MapleDemoSandbox YES`: its own container under `Sandbox/`, with the preview blocker; it credits preview sessions to its own files).

### How the Focus screens read the stores

```swift
@Environment(FocusSessionStore.self) private var sessions
@Environment(\.focusStores) private var focus                  // FocusStores?: the composer and the start command
@Environment(FocusTabState.self) private var tab               // the Focus tab's choices for this launch (App)

let status = focus?.status(at: sessions.now, collection: collection, settings: settings)    // FocusStatus, for Home
let model = focus?.startScreen(preset: preset, minutes: 50, at: sessions.now, collection: collection,
                               settings: settings, stage: .choosing, hasTurned: tab.hasTurnedDial, locale: locale)
let outcome = await focus?.start(request, intention: tab.intention, settings: settings)  // also marks the preset used
router.showFocus(.selectPreset(id))                            // or .needsScreenTime, .receipt(id), .returnToSession, .releaseAll
```

- **Upkeep.** `.focusUpkeep()` refreshes the session store on launch, every foreground, when protected data becomes available, every 15 seconds while a session runs, and at the planned end and the break end (`FocusRefresh`). Screens never call `refresh()` themselves (only `.focusArrival(isOnboarding:)`, below, asks for one more on a return from the background, before it decides). A running dial samples once a second from `sessions.now`, in a `TimelineView` inside the screen that shows it.
- **Arrival.** `.focusArrival(isOnboarding:)` (applied in `RootView`) brings the Focus tab forward as the member arrives, by `FocusLanding.opensFocus(_:running:sessions:seen:isOnboarding:isPresenting:now:)` (MapleCore, pure). At launch, once `sessions.isLoaded`, a running session or a waiting receipt (`ReceiptPicker.pending`) selects the Focus tab (§5.4, §5.8). On a return from the background it refreshes, then selects it for a waiting receipt only: a return mid-session moves no one. Never during the first run, or while a sheet, cover or alert is up; a DEBUG launch with `-MapleDemoTab` keeps its tab. A session ending while Maple is open moves no one either: its receipt waits on the Focus tab, and `ReceiptView` marks it seen (and plays its finish) only once the Focus tab is selected.
- **Routes.** `FocusView` shows one destination, from `FocusRoute.resolve(isLoaded:running:receipt:isMinimised:canBlock:usesPlainTimer:now:)`: `.settling` (nothing drawn: before the store's first refresh, `sessions.isLoaded`; for a session found more than `FocusRoute.endGrace` past its planned end, one that ended while away; and while the ledger can't be read), `.start`, `.needsScreenTime`, `.running(id)`, `.minimised(id)`, `.breakTime(id)` or `.receipt(id)`. `FocusRoute.nextChange(running:now:)` is when the route changes by itself. At the planned end the running screens keep their last frame, never 0:00, by drawing at `FocusRoute.frameTime(_:now:)` until the refresh that ends the session brings the receipt. The receipt is `ReceiptPicker.pending(_:seen:now:)`: the newest session that ended within 24 hours and isn't `settings.lastReceiptSeen`. `ReceiptView` marks it seen as it appears, and `tab.shownReceipt` keeps it on screen until Done or the next start.
- **`FocusTabState`** (App, `@Observable`, never saved): `selectedPresetID`, `minutes`, `intention`, `hasTurnedDial`, `isMinimised`, `plainTimer` (`PlainTimerReason`: `.chosen`, `.lockFailed`; a start clears it), `shownReceipt`, `lastStarted`, `releasesAll` (Settings' Release all apps during a session), and the tab's one sheet, `sheet` (`FocusTabSheet`: `.blocking`, `.preset(UUID?)`, `.intention`, `.saved`, `.streak`). `plainTimer(settings:capability:)` is the reason the start screen and the route read: the tab's own, else `.chosen` when `settings.opensPlainTimer(capability:)`, which only a build that can never block answers yes, once `settings.choosePlainTimer(capability:)` saved the member's first "Use a plain timer" (F1-29).
- **The strictness that applies.** `Strictness.applying(to:)` (MapleCore, pure) and `FocusPlan.appliedStrictness`: a plain timer is Gentle whatever its preset, a session that locks apps keeps its own (F1-30). `StartScreenModel.strictness` applies it (without blocking, a start is a plain timer), and so Home's Start and the receipt's Again; `FocusStartLines` never holds a plain-timer start, or a failed lock's, whatever the model's strictness; `SessionEndPath(_:)` on a plan picks every way out with it, Release all apps included.
- **A session's numbers.** `sessions.running` is a `SessionRecord`, with `secondsLeft(at:)` (0 once ended), `isInBreak(at:)`, `breakSecondsLeft(at:)` and `endedAt`. `sessions.countedSoFar(id)` is its counted plus provisional seconds, `sessions.credit(for:)` the `SessionCredit` the receipt and Saved today read, and `sessions.sessionUnlocks` the leaves the running or last-ended session opened.
- **Words and decisions are MapleCore values:** `StartScreenModel` and `FocusStartLines` (the start screen, and Home's Start, built from the same model), `NeedsScreenTimeState` with `FocusCopy.card(_:)`, `RunningSessionModel` and `BreakScreenModel`, `BreakDialLayout`, `ReceiptModel` and `ReceiptFlow`, `SavedTodayModel`, `StreakWeek`, `FocusSheetCopy`, `FocusSettingsCopy` and `SelectionText`. `RunningSessionModel` and `BreakScreenModel` also carry F1 design §4.9's VoiceOver reads and announcements. The dial is a `DialFrame` drawn by `MinuteDial` (MapleDesign), and every hold is a `HoldButton` with its named accessibility action.
- **Home and the Herbarium.** Home passes `focus.status(at:collection:settings:)` to `collection.nowState(at:…focus:)`. Until the session store's first refresh has run (`sessions.isLoaded`, carried as `FocusStatus.isLoaded`) the state is `.settling`, and Home draws nothing below the stage (no numeral, next leaf or action), so a relaunch mid-session never flashes Start. Its Start begins a session at once only when start readiness allows it, and otherwise opens the Focus tab (`router.showFocus(.selectPreset(id))`). The next-leaf row adds a running session's provisional time (`LeafProgress.displaying(provisionalSeconds:)`), and the Herbarium shows the session's bar (`SessionMiniBar`, nil once no time is left).
- **Release all apps.** `FocusReleaseRouter(router:).releaseAll(from: sessions)` clears every store at once when no session runs, and returns true. During a session it opens that session's own end path (Locked: the emergency release; a plain timer: Gentle's End early, whatever its preset) and returns false.
- **The Live Activity.** `ActivityKitController` (App) is the `LiveActivityController` the session store calls after every change. It describes the running state with `FocusActivityState.described(intention:tint:leafID:)`: the intention from `session-notes.json`, capped at 40 characters; the season tint as `Theme.SeasonTints.leafColor(for:)`, never gold; and the next hours leaf, sent as a `LeafSketch`, whose thinned outlines keep each outline's extreme points, so every species stays within 1 unit of its box (`LiveActivitySketchTests.keepsShape`, over all 155). It words it in MapleCore, `FocusActivityState.lines(locale:calendar:)` ("until 14:52 · Study", "Study · Chemistry ch. 4", "Study · break until 14:28", "Session complete"; during a break `breakSpoken`, "Study, break until 14:28", is how VoiceOver reads either line, F1-27), because the widget links only MapleActivity. `LiveActivityPlan.make(activities:wanted:contentChanged:mayRequest:)` (MapleCore, pure) decides the upkeep: end every activity that isn't the running session's, update the running one when its content changed, and request one only when none shows and `mayRequest`. `LiveActivityAsks` (MapleCore, pure) answers `mayRequest`: an activity is asked for once per session per launch; one that showed, was found again, or was dismissed isn't asked for again in this launch; one ActivityKit refused is asked for once more after Maple next comes to the front (`FocusSessionStore.mapleBecameActive()`, which `.focusUpkeep()` calls before the return's refresh). An intention typed before Start reaches the activity before `start(_:intention:settings:)` returns (`sessions.resendLiveActivity()`). `LiveActivities.sync` applies the plan off the main actor, because ActivityKit's `Activity` isn't `Sendable`.
- **DEBUG.** The Focus demo arguments are in `docs/debug-launch-arguments.md`. Settings' "Ledger inspector" (`-MapleDemoProfile ledger`) lists the ledger's events by kind, time, session and sequence, never content (`LedgerInspection`).

## Files, unlocks and time zones

- `JSONStorage.read()` tells a missing file (`.absent`, a first run) from one that can't be read yet (`.unavailable`: a launch before the first unlock after a restart, or another I/O error). Only a file that reads but won't decode is set aside as `<name>.damaged-<time>.json`; an unreadable one is left alone and every save to it is refused until a read works. A missing file with a cleanly decoding set-aside copy beside it is restored; if a newer set-aside copy can't be read yet (a protection or permission error), the read is `.unavailable` rather than `.absent`, so no empty file is created in its place before the first unlock.
- `CollectionStore`, `ScheduleStore` and `AppSettings` expose `isAvailable` and `reloadIfUnavailable()`. While unavailable they hold an in-memory placeholder that is never saved; any change reads the file first. `ThemedRoot` reloads when protected data becomes available or the app becomes active, then decides the first-run step again and rebuilds the root (`MapleStores.reloadIfUnavailable()`).
- The live store uses `Calendar.autoupdatingCurrent`. `ThemedRoot` calls `collection.systemTimeChanged()` on `NSSystemTimeZoneDidChange` and significant time changes, which rebuilds cached progress and refreshes every screen that read `collection.context`. The `\.season` environment is read every minute.

## Shipped features and permissions

`collection.context.features` is `ShippedFeatures.current`, M1 and F1: `.focus` and `.screenTime` are true, `.sleepSounds` (F2) is false, and F2's categories (Phone-free mornings, Bedtime kept) are dormant ("Not earnable yet"). A feature that hasn't shipped is absent from every screen. DEBUG `-MapleDemoShip m1` shows the build before F1 in demo stores; tests of that build pass `ShippedFeatures(releases: [.m1])`.

`collection.context.blocking` (`BlockingCapability`) says what the build can block with: `.unavailableInBuild` on free builds (and paid ones until F1-paid), `.preview` in DEBUG demo and sandbox launches.

`collection.context.permissions` (`GrantedPermissions`) is real: empty until the member has been through Apple's Health prompt, then `.appleHealth`. `collection.availability(of:)` gives a category's state: Rested nights needs Apple Health (`.needsAppleHealth`), the focus categories (once they ship) read `.notInThisBuild` on a build that can't block (every free build, `collection.context.blocking == .unavailableInBuild`) and otherwise need Screen Time (`.needsScreenTime`), and First leaf needs nothing. Needs-permission leaves show "Needs Apple Health" (tiles, section headers with "Turn on", leaf detail with "Turn on Apple Health"), have no estimate, and are left out of the next leaf, buds, Almost there, pacing and Profile's totals (D9).

`HealthPermission` (MapleServices) owns Apple Health:

```swift
@Environment(HealthPermission.self) private var health

health.isConnected                                // the member has been through Apple's prompt
await health.requestAccess(at: clock.now())       // Apple's sheet: HKHealthStore.requestAuthorization(toShare: [], read: [sleepAnalysis])
health.apply(to: collection)                      // grants (or withdraws) .appleHealth in the collection's context
```

HealthKit never says whether reading was allowed, only whether its prompt was answered, so `requestAccess` records that the member completed it (`health.json`) and Apple Health counts as connected from then on; M1's importer reads whatever they allowed. `ThemedRoot` calls `health.refresh(at:)` and `apply(to:)` on every foreground, so a reset of the member's Health answers shows as not connected again. Every "Turn on Apple Health" presents `HealthPrimerSheet` (App), the calm primer (`HealthPrimerView` in MapleDesign: one leaf, two sentences, "Continue", "Not now"), whose Continue calls `requestAccess`; every "Turn on Screen Time" opens the Focus tab's Needs Screen Time, through `turnOnPermission(_:speciesID:showHealthPrimer:router:)` and `router.showFocus(.needsScreenTime)`.

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

DEBUG `-MapleDemoSeedHealth` seeds synthetic sleep (into the simulator's Apple Health, or with `-MapleDemoSeedStore memory` straight into a demo launch's importer); demo collections (`-MapleDemoSpecies`…) are never fed nights. `DemoData.snapshot(species:tendedDays:waiting:now:)` gives a plausible collection directly, and `PreviewLeafShareProvider` gives tier-correlated rarity. Both exist only in DEBUG. Demo stores are granted Apple Health and a sleep tracker unless `-MapleDemoPermissions` says otherwise, so a demo collection shows earned progress; add `.environment(stores.health)` for screens that offer "Turn on Apple Health".
