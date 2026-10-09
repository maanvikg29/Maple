# Decisions log

Newest first. Each entry: what was decided, why, and what it affects.

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
