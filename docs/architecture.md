> Approved plan (2026-10-10). Source of truth for architecture and milestone scope. Update this file when a decision changes.

# Maple — iPhone App: Architecture, Project Structure & Milestone Plan

## Context
Greenfield build of **Maple**, an iPhone digital-wellbeing app. Users earn **maple leaves** for healthy sleep and screen habits, and the leaves grow a personal seasonal tree. The full spec was pasted in chat. This plan covers the architecture, Xcode structure and milestones. Nothing is built until you approve it. After that I build one milestone at a time, and each one must compile and run before I move on.

**Your setup:** free Apple ID (personal team), an iPhone and an Apple Watch to test on, minimum iOS 27.
**Toolchain (checked):** Xcode 27.0, Swift 6.4, iOS 27 SDK, iPhone 17 simulator already booted. No signing certificates installed; no XcodeGen or Tuist.

## What iOS 27 allows (checked with SDK typechecks and Apple docs/forums)
| Capability | Status | Notes |
|---|---|---|
| Screen Time (FamilyControls, ManagedSettings, DeviceActivity) | ✅ | **The paid Developer Program is required.** Free teams can't provision it, and it doesn't work meaningfully in the Simulator. |
| Custom shield (ManagedSettingsUI) | ✅ | A title, subtitle, icon, colours and buttons only, not custom SwiftUI views (I'll confirm on a device). |
| DeviceActivityReport extension | ✅ | **Can't write anything the app can read**: no App Group writes, no network. Last-Scroll numbers can only be displayed inside the extension. |
| DeviceActivityMonitor extension | ✅ | Roughly a 6 MB memory limit, so no SwiftData or SwiftUI inside it. |
| HealthKit (sleep, heart rate, mindful minutes, workouts) | ✅ | Works on free teams. Sleep data from the Watch arrives through the iPhone's Health store. |
| On-device AI (`SystemLanguageModel`) | ✅ on Apple Intelligence iPhones | Older iPhones need a rule-based fallback. |
| `PrivateCloudComputeLanguageModel` (new in iOS 27) | ✅ | **Managed entitlement.** You must be in the Small Business Program and have under 2M downloads. Not possible on a free account. |
| AlarmKit | ✅ | Plays at the system ringer volume, so gradual volume isn't possible with it. |
| SwiftData + CloudKit | ✅ | Sync needs the paid program. Models need every property optional or defaulted, and no unique constraints. |

## Decisions (my recommendation first; please reply on any you disagree with)
1. **Paid Developer Program, needed before M3 (blocking).** You can't test blocking on a device without it. The Family Controls *distribution* entitlement also has to be requested for 5 bundle IDs, and approval can take weeks. **Recommendation:** join during M1 and file the request then. Until then I build the blocking code against a mock.
2. **Bundle IDs.** The default is `com.maanvikgupta.maple`, plus `.monitor`, `.report`, `.shield`, `.shieldaction`, and the app group `group.com.maanvikgupta.maple`. These are hard to change after the Family Controls request, so please confirm them before M3.
3. **Monetisation.** Guideline 4.10 forbids charging for Screen Time API features, and your spec already keeps blocking free. **Recommendation:** every leaf, including the rare ones, comes only from behaviour, never from purchase. Premium adds cosmetic leaf varieties and themes, AI coaching, advanced insights, the audio library and family plans.
4. **Sound content.** For the MVP I'll *generate* white, pink and brown noise, ocean and rain in code. That means no licensing, offline by default and a tiny app. Recorded loops and stories need a licensed source, which you'd pick by M6.
5. **Smart wake.** AlarmKit can't ramp volume. If sleep sounds are playing overnight, the app is still running, so it can fade in its own wake sound and brighten the screen in bedside mode. A fixed AlarmKit alarm stays as the backup. Waking during light sleep needs the Watch app (M8).

## 1. Architecture

**Layers** (one-way dependencies: App → Services → Data → Core; Design is used by the app and the extensions):

- **MapleCore** is pure Foundation, `Sendable`, with no SwiftUI or SwiftData, so it fits inside the 6 MB monitor extension.
  - Domain types: Leaf, LeafVariety, Rarity, Season, SleepSchedule, Night.
  - **LeafEngine**: a pure function from (events, nights, sessions, date, hemisphere) to awards.
  - Hemisphere-aware season logic and sleep-night grouping (clusters HealthKit samples into nights and resolves overlaps between Watch and iPhone).
  - Schedule maths, and the WellbeingScore calculator, which returns its full breakdown.
  - **EventStore**: one atomic JSON file per event in the App Group, named by a deterministic ID, so concurrent extension writes never corrupt each other.
- **MapleDesign** holds all design tokens in `Tokens.swift`: colours (#05070D, #0B1426, #111D35, #F2F5FA, #8A96AD, amber #E8A35C), type (SF Pro/SF Rounded via Dynamic Type styles), spacing, radii, glow, and slow motion curves. A `Theme` value is passed through the SwiftUI Environment. It also holds components: GlowCard, PrimaryButton, StatNumber, LeafGlyph, PermissionPrimer. Everything respects Reduce Motion, Dynamic Type and VoiceOver.
- **MapleData** holds the SwiftData `VersionedSchema` (V1) with two configurations:
  - **synced** (CloudKit-ready, `cloudKitDatabase: .none` until you're on the paid program): Profile, SleepSchedule, Leaf, FocusSession, Settings.
  - **localHealth** (never synced, in line with guideline 5.1.3(ii)): SleepNightSummary, and later HR and mindful minutes.
  - The store lives in the App Group container, so extensions and widgets can share it later.
- **MapleServices** puts a protocol in front of each service, with a live and a mock version:
  - `HealthService`; `ScreenTimeService` (reports `.unavailable(reason)` on free builds).
  - `AudioMixer`: AVAudioEngine with one `AVAudioSourceNode` per noise layer, volume per layer, fade-out timer, background audio.
  - `NotificationService`, `AlarmService`, `StoreService`.
  - `WellbeingAI`, with three implementations:
    - `OnDeviceAI`: SystemLanguageModel, `@Generable` structured output, and Tools that read your data.
    - `PrivateCloudAI`: optional, only when entitled.
    - `TemplateAI`: rule-based fallback.
    - All AI output carries a visible "AI-generated" label.
- **App target**: feature folders (Onboarding, Today, Grove [tree + herbarium], Sleep, Sounds, Focus, Insights, Settings/Privacy). Each feature has one view-model and small views, with tab navigation.

**Key data flows**
- **Leaf earning:**
  1. HealthKit import, monitor and shield-action events, and focus sessions feed the LeafEngine.
  2. The engine awards leaves with **deterministic IDs** (`date|reason|source`), so re-running it or merging later CloudKit sync never duplicates leaves.
- **"No scrolling after wind-down":**
  1. A DeviceActivity schedule covers the wind-down window, with a usage threshold (e.g. 5 min) on the chosen apps.
  2. If the threshold is hit, the monitor writes an event.
  3. The app awards the leaf only when the interval started, no threshold event exists, and the end time has passed. It doesn't rely on `intervalDidEnd` alone.
  4. Thresholds at 5, 15, 30 and 60 min give the app (and the AI) a rough late-night usage signal *without* raw usage data.
- **Last-Scroll Analytics:** computed and drawn entirely inside the DeviceActivityReport extension and embedded in the app with `DeviceActivityReport(context)`. The app and the AI never see those numbers.
- **Concurrency:** Swift 6 language mode. The App, Design and Services modules use `.defaultIsolation(MainActor.self)`; Core stays nonisolated.
- **Privacy:**
  - File protection `completeUntilFirstUserAuthentication`, because extensions need access while the phone is locked.
  - CloudKit fields marked `.allowsCloudEncryption`.
  - Export to JSON/CSV and "delete everything" covering both stores, the App Group, and CloudKit.
  - A permission primer screen before every system prompt.

**Leaf system v1** (the full table goes in `docs/leaves.md`):
- A leaf is a **variety** (its shape) × a **season colour** (spring green, summer deep green, autumn gold or crimson, winter frost; flipped for the southern hemisphere) × a **rarity**:
  - common: daily behaviour
  - rare: 7- and 21-night streaks, and challenges
  - legendary frosted: winter streaks and referrals
- Streaks forgive one missed night per week.
- Leaves are never lost. After bad nights the tree just looks quieter, with dimmer light and less sway.

## 2. Xcode project structure
New folder `Maple/` beside FoodAI, which stays untouched, with its own git repo.
```
Maple/
├─ Maple.xcodeproj           hand-authored, minimal: objectVersion 77, synchronized folders, settings in xcconfigs
├─ Config/
│  ├─ Base.xcconfig          bundle prefix, iOS 27, iPhone only, Swift 6
│  ├─ Signing.xcconfig       ← you edit: DEVELOPMENT_TEAM, MAPLE_TIER = free | paid
│  └─ Entitlements/          Maple-free.entitlements, Maple-paid.entitlements, one per extension
├─ App/                      "Maple" iPhone app target
│  ├─ MapleApp.swift, AppEnvironment.swift
│  ├─ Features/{Onboarding,Today,Grove,Sleep,Sounds,Focus,Insights,Settings}/
│  └─ Resources/ (Assets.xcassets, Localizable.xcstrings)
├─ Extensions/               added in M3
│  ├─ MapleMonitor/  MapleReport/  MapleShield/  MapleShieldAction/
│  └─ MapleWidgets/          (M8: widgets + Live Activities)
├─ Watch/                    (M8)
├─ MapleKit/                 local Swift package: MapleCore · MapleDesign · MapleData · MapleServices + Tests/
├─ docs/                     architecture.md (this plan), leaves.md, entitlements.md, decisions.md
└─ Scripts/                  build.sh, test.sh
```
- **Signing tiers.** `free` gives HealthKit and App Groups. `paid` adds Family Controls, iCloud/CloudKit and push. The Screen Time extensions are embedded **only in the paid tier**, so they don't use up your 10 free App IDs. The Simulator needs no signing at all.
- **Project file.** I'll hand-write a minimal `project.pbxproj`, because no project generator is installed and downloading one needs your OK. I'll check it after every change with `xcodebuild -list` and real builds.

## 3. Milestones
Each milestone ends with: unit tests pass, a clean build for the iPhone simulator, the app launched with screenshots, and a git commit. Before each milestone I post a short task list.

**MVP = M0 to M3.**

- **M0 Foundation.**
  - Repo, xcconfigs, project file and MapleKit package.
  - Design tokens and core components.
  - Tab shell with placeholder screens.
  - `docs/architecture.md`, `docs/entitlements.md`.
- **M1 Sleep loop (fully testable on a free account).**
  - Onboarding: questions, proposed schedule, permission primers.
  - Sleep schedule editor (weekday/weekend, wind-down length).
  - HealthKit sleep import with night grouping, plus a debug sample-data seeder for the Simulator.
  - LeafEngine (bedtime, focus, streaks, seasons) with tests written first.
  - Procedural seasonal **Maple tree** drawn with Canvas.
  - **Today** screen: morning reveal of last night's leaf, tonight's countdown.
  - Local notifications for wind-down and the morning check-in.
- **M2 Calm & insight.**
  - Sounds mixer: 5 generated layers, volume per layer, fade-out timer, background audio.
  - Focus timer (without blocking yet) that awards leaves.
  - **Herbarium**: every leaf with its date and reason.
  - Basic Swift Charts insights: sleep duration, bedtime consistency, leaves per day.
- **M3 Blocking (paid program needed to test on a device).**
  - Screen Time authorization and FamilyActivityPicker app sets for bedtime, focus and morning.
  - DeviceActivity schedules and ManagedSettings shields.
  - Maple-styled ShieldConfiguration, and a ShieldAction for "close" or "5 more minutes" (which logs the unlock).
  - Monitor events that award leaves. Morning Mode (phone-free first 30 min).
  - Last-Scroll v1 inside the report extension. Device checks of memory use and schedule limits.
- **M4 Score & journal:**
  - Transparent Wellbeing Score: tap to see the inputs, weights and maths.
  - Mood and energy check-ins; habit and caffeine journal with correlations.
  - Achievements; leaf and tree share cards (ImageRenderer).
  - Adaptive schedule suggestions from 14 nights of data.
- **M5 AI:**
  - Coach (structured recommendations), weekly report, and a Personal Sleep AI chat that answers using your data.
  - Sleep stories: on-device and written in chapters; PCC only if you're entitled. Narrated with AVSpeechSynthesizer premium voices over a background sound.
- **M6 Rituals & wake:**
  - Animated breathing, meditations, journaling prompts.
  - AlarmKit alarms and bedside sunrise mode (overnight-audio fade-in).
  - Offline library, once the content source is decided.
- **M7 Privacy & business:**
  - CloudKit backup of non-health data; JSON/CSV export; delete-everything.
  - StoreKit 2 with Family Sharing and an honest paywall (StoreKit config file for local testing).
  - Referral codes via the CloudKit public database.
- **M8 Glanceables:** widgets, Live Activities (bedtime countdown, focus timer), Apple Watch app with Watch-based smart wake.
- **M9 Social:** shared routines (CloudKit sharing), opt-in community challenges, themes and ambient visuals.
- **M10 Launch polish:** accessibility audit, localization, performance, App Store screenshots.

## Entitlements to request early (paid program)
- **Family Controls distribution**: one request per bundle ID: the app, `.monitor`, `.report`, `.shield`, `.shieldaction`.
- **Private Cloud Compute model** (optional, M5): managed entitlement; requires the Small Business Program and under 2M downloads.
- **Standard, no approval:** HealthKit, App Groups, iCloud/CloudKit, Push, In-App Purchase. AlarmKit needs a usage string; I'll confirm on a device whether provisioning needs anything more.

## Things only you can do
- Sign into Xcode (Settings → Accounts) and put your team ID in `Config/Signing.xcconfig` to run on your iPhone. Free-team builds expire after 7 days: re-run from Xcode, and don't delete the app or you lose its data.
- Join the paid program and file the entitlement requests (decision 1).

## Verification
- **Logic:** tests written first for LeafEngine, night grouping, season/hemisphere, schedule maths, score and EventStore, run with `xcodebuild test` on the iPhone 17 simulator.
- **Builds:** `xcodebuild` for the `iPhone 17` simulator, aiming for zero warnings.
- **Running app:** I launch it in the booted iPhone 17 simulator with the iOS Simulator tool, walk through onboarding → seed sample sleep → see the leaf and tree, and share screenshots.
- **On device (M3+):** a checklist for you to run on your iPhone, since I can't drive a physical device. Shields appear on schedule, the shield action works, monitor events produce leaves, and the report shows Last-Scroll.
