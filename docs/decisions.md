# Decisions log

Newest first. Each entry: what was decided, why, and what it affects.

## 2026-10-10 — Sleep leaves come only from Apple Health (D9)
The M1 sleep categories (Nights tracked, On-time bedtimes, Bedtime runs, Steady weeks, Seasons in rhythm, Steady mornings, Full nights) are earned only from Apple Health's nights, as rewards.json's data sources say and spec D9 settles: there is no manual self-report fallback. Why: a tap is self-report, so a leaf earned by tapping would mean nothing, and the leaves are worth having only because they reflect real sleep. Affects: the Goodnight tap in wind-down mode only logs the phone-down time (wind-down's own state and Home's "Morning, no Apple Health" numeral) and feeds no counter; `NightLedger` judges `SleepNightObservation`s from M1's importer (`CollectionStore.recordSleep(_:at:)`), each in the time zone the night was spent in; without Apple Health these leaves show "Needs Apple Health" and are left out of the next leaf, buds, Almost there, pacing and Profile totals, and Home's next-leaf row offers "Turn on Apple Health" (spec Overrides #4). Full nights also need asleep time (a Watch, a tracker or another app). HealthKit never reveals read access, so finishing Apple's prompt counts as connected.

## 2026-10-10 — One count rule: "N of 155" counts opened leaves
Every surface that shows how many leaves the member has (Home's caption, Tree view, the Herbarium's count, owned bar, "Earned" chip and section counts, Profile, onboarding, VoiceOver) counts opened (placed) leaves only. Waiting leaves are buds and are mentioned apart ("1 waiting"), never added to N. Why: the count and the tree must agree; a leaf counts once it is on the maple. Affects: `LeafCount` (MapleCore) is the single rule, read through `CollectionStore.leafCount` / `openedCount`; the tree's stage name follows the same N (spec §5.2).

## 2026-10-10 — A morning with no sleep data shows tonight's wind-down start
When there is neither last night's sleep from Apple Health nor a Goodnight time, Home's morning numeral is tonight's wind-down start as a locale-aware clock time ("22:15" / "10:15 PM") with "wind-down tonight · bed 23:00", never a countdown. Why: a 14-hour countdown in the morning reads as a chore, and "0" or "—" would break spec §1.12 (every no-data case has a designed state). Affects: `NowState` (`Content.windDownTonight`) and spec §3.4's "Morning, no data for last night" row; the day still counts down to wind-down until focus ships.

## 2026-10-10 — "% of members who have this leaf" uses CloudKit
Each leaf shows the share of Maple members who own it (like Opal gems). Counts live in Maple's CloudKit public database: only anonymous per-leaf unlock counts leave the device, never health data. No third-party processor. Needs the paid Developer Program, so until then the app shows "Not enough members yet" (never a made-up number). The stats sit behind a `LeafOwnershipStats` protocol so the backend can change.

## 2026-10-10 — Leaves are milestone rewards; catalogue is the supplied 155 species
Every species in `MapleCore/Resources/species.json` (supplied catalogue, 155 living *Acer* species) is a one-time reward unlocked by a specific milestone, like Opal's gems. Leaves are drawn natively by a Swift port of the supplied `leaf-generator.js`, so they can appear in any colour and size. Reference material lives in `Catalog/`.

## 2026-10-10 — Build output lives outside the repo
The repo sits in `~/Documents`, which iCloud Drive syncs. iCloud adds file-provider attributes that make `codesign` reject build products ("resource fork, Finder information, or similar detritus not allowed"). Scripts build into `~/Library/Developer/Xcode/DerivedData/Maple`, which is also Xcode's default.

## 2026-10-10 — Hand-written Xcode project
No project generator is installed. `Maple.xcodeproj` is kept minimal: synchronized folders (new files under `App/` are picked up automatically), build settings in `Config/*.xcconfig`, code in the `MapleKit` package. Validate edits with `xcodebuild -list` and a build.

## 2026-10-10 — iPhone only, iOS 27 minimum
Scope is iPhone only (`TARGETED_DEVICE_FAMILY = 1`), minimum iOS 27. Gives access to `PrivateCloudComputeLanguageModel` and avoids availability branches.

## 2026-10-10 — Free Apple developer account for now
Everything through M2 is testable on a free personal team. Blocking (M3) needs the paid program to test on device; join during M1 and file the Family Controls distribution request then.

## 2026-10-10 — Approved defaults from the plan
- Leaves come only from behaviour, never purchase. Blocking stays free (App Store guideline 4.10). Premium = cosmetics, AI coaching, advanced insights, audio library, family plans.
- MVP sounds are generated in code (no licensing). Recorded content source to be chosen by M6.
- Smart wake: overnight-audio fade-in + AlarmKit backup (AlarmKit can't ramp volume).
- Health-derived data lives in a local-only store (guideline 5.1.3(ii)).
