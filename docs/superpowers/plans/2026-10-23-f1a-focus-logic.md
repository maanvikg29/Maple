# F1a Focus Logic Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build everything F1's Focus tab needs under the screens: the session ledger, credit, `FocusBook` and counters, the reveal-hold change, reminders, `NowState`, and the MapleServices stores with preview blocking, all tested with Swift Testing and with no new screens.

**Architecture:**
- **New targets:**
  - `MapleFocusCore`: pure, nonisolated, no resources. It holds the types the F1-paid extensions will share: events, plans, time sources, the ledger and the reconciler.
  - `MapleStorage`: nonisolated. It holds the container, JSON-lines files and ledger stores.
- **Re-exports:** MapleCore re-exports MapleFocusCore, and MapleServices re-exports MapleStorage, so app code keeps importing MapleCore and MapleServices only.
- **Credit** is a pure pipeline: `FocusLedger` → `SessionRecord` → `HoursCredit` → `FocusBook` → dated marks → `CollectionSnapshot.applyFocus`.
- **`FocusSessionStore`** (MainActor) turns commands into ledger events and blocking operations, one at a time.

**Tech Stack:** Swift 6, iOS 27, SwiftPM local package `MapleKit`, Swift Testing, Xcode 27 (`Scripts/test.sh`).

**Spec:** `docs/superpowers/specs/2026-10-23-f1-focus-design.md` (the F1 design; §3 is the counting rules and §7 the architecture), with `docs/superpowers/specs/2026-10-11-focus-hours-saved-design.md` (the focus spec, R1–R14).

## Global Constraints
- iPhone only. Never mention or build for other Apple platforms.
- Swift 6 language mode, strict concurrency, zero compiler warnings.
- **Isolation by module:**
  - MapleCore, MapleFocusCore and MapleStorage are pure Foundation, nonisolated and `Sendable`, with no SwiftUI, SwiftData or UIKit.
  - MapleServices and MapleDesign are MainActor by default.
- **Tests:**
  - Swift Testing only (`@Test`, `#expect`, `#require`), written first and watched failing.
  - Use the existing `utc` calendar and `at(...)` helpers from each test target's `TestSupport.swift`.
- **DEBUG code:** demo and preview code compiles only under `#if DEBUG`. That includes `PreviewBlockingService`, `DemoLaunchOptions` and demo scenarios.
- **Files not to edit:** `MapleKit/Sources/MapleCore/Collection/NightLedger.swift` (another branch is simplifying it; read only `NightLedger.schedule(for:current:)`), and anything in the FoodAI folder.
- **Copy:**
  - sentence case, no "!", no emoji;
  - never "fail", "quit" or "streak lost";
  - amber and gold words only for rewards.
- **Counting constants (F1 design §3):**
  - daily cap 21,600 s;
  - a finished session needs 1,200 counted seconds and at least ¾ of its planned length;
  - at most 3 finished sessions count per Maple day;
  - at most 2 rest days in any 7 days in a row;
  - days freeze 3 days after the later of their end and their first credit;
  - sessions run 20 to 180 minutes, in 5-minute steps.
- **Tests run from the worktree root:**
  - all: `SIMULATOR="iPhone 17" Scripts/test.sh > "$WS/test.log" 2>&1; tail -5 "$WS/test.log"`;
  - one suite: append `-only-testing:<TestTarget>/<SuiteStruct>`.

  `$WS` is the plan's workspace folder; any scratch folder works. Read failures with `grep -E "error:|failed|✘" "$WS/test.log" | head -40`.
- **Commits:** one per task. The message ends with a blank line and then `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Pushing:** never push or merge (CLAUDE.md: ask first).

## Review Focus
These inputs aren't fully exercised by the spec's own test list and are the likeliest to hurt a member. Each has a test in its owning task.
1. **The boot id can't be read** (`sysctl` fails). The fallback must be unique per launch, so credit never joins two launches by mistake. (Task 4)
2. **The clock is set back across a month boundary.** New events land in an older-named month file, and reading the open ledger must still find them. (Task 8)
3. **The app is killed after the shields are applied but before `sessionStarted` is written.** The next refresh must clear the orphan shields. (Task 22)
4. **The schedule is edited during a session.** The running session keeps its frozen window, and its credit doesn't change. (Task 22)
5. **Start is tapped twice quickly.** The store must refuse a second start while one is starting or running. (Task 22)

## File Structure
**MapleFocusCore** (new target): `MapleKit/Sources/MapleFocusCore/`
- `FocusRules.swift`: schema and rules versions.
- `FocusEvent.swift`: `EventStamp`, `FocusWriter`, `FocusSource`, `EndReason`, `ShieldClearReason`, `Reflection`, `FocusEventKind`, `FocusEvent`.
- `FocusPlan.swift`: `FocusVerb`, `Strictness`, `SessionKind`, `StartSource`, `AwakeWindow`, `SelectionSummary`, `FocusPlan`.
- `FocusTimeSource.swift`: the protocol, `LiveFocusTime`, `ManualFocusTime` and `ShiftedFocusTime`.
- `FocusLedger.swift`: merge, order and placement (`PlacedEvent`).
- `SessionRecord.swift`: one session's replay (proof, overrides, breaks, end).
- `Blocking.swift`: `MapleTier`, `BlockingCapability`, `BlockingProbe`, `ShieldOp`, `ShieldStoreState` and `ShieldReconciler`.

**MapleStorage** (new target): `MapleKit/Sources/MapleStorage/`
- `MapleContainer.swift`: moved unchanged from `MapleServices/Storage/JSONStorage.swift`.
- `JSONLinesFile.swift`: append with the newline guard, and a tolerant read.
- `FocusLedgerStore.swift`: the protocol, `FileLedgerStore` and `MemoryLedgerStore`.
- `LedgerWriter.swift`: stamps and numbers one process's events.

**MapleCore** (existing): `MapleKit/Sources/MapleCore/`
- `Focus/FocusCoreExport.swift`: `@_exported import MapleFocusCore`.
- `Focus/AwakeWindow+Schedule.swift`: the frozen window; `FocusPlan.day`; `LocalDay.init?(label:)`.
- `Focus/HoursCredit.swift`: `CreditRule`, `CreditStretch`, `SessionCredit`, `HoursCredit`.
- `Focus/FocusBook.swift`: `SessionTally`, `DayCredit`, `FocusTotals`, `FocusBook`.
- `Focus/FocusRuns.swift`: the streak (current and best run).
- `Focus/FocusCounters.swift`: `FocusMark`, `FocusCounters.marks`.
- `Focus/CollectionSnapshot+Focus.swift`: `applyFocus`, `focusWindow`, `currentRun`.
- `Focus/FocusPreset.swift`: presets and the strictness change rule.
- `Focus/DialLayout.swift`, `Focus/FocusTimeText.swift`, `Focus/SessionForecast.swift`, `Focus/StartReadiness.swift`, `Focus/RecentIntentions.swift`.
- **Edits:**
  - `Collection/CollectionSnapshot.swift`: version 2, the `focus` field, tolerant decoding.
  - `Collection/LeafEngine.swift`: `RevealSchedule`.
  - `Collection/CollectionModels.swift`: `LeafAvailability.notInThisBuild`, `LeafProgress.floor`.
  - `Collection/ShippedFeatures.swift`: the availability rule.
  - `Collection/NextLeafPicker.swift`, `Collection/LeafProgressBuilder.swift`, `Collection/LocalDay.swift`.
  - `Collection/CollectionSnapshot+Rules.swift`: `CollectionContext.blocking`.
  - `Home/LeafRemainder.swift`, `Home/NowState.swift`.
  - `Clock/MapleClock.swift`: `shifted(by:)`.
  - `Notifications/ReminderPlan.swift`.
  - `Rewards/RewardCategoryInfo.swift`.

**MapleServices** (existing): `MapleKit/Sources/MapleServices/`
- `Storage/StorageExport.swift`: `@_exported import MapleStorage`.
- `Focus/BlockingService.swift`: the protocol, `ShieldResult`, `MapleBuild` and `UnavailableBlockingService`.
- `Focus/PreviewBlockingService.swift` (DEBUG).
- `Focus/PresetStore.swift`, `Focus/AppSetStore.swift`, `Focus/SessionNotesStore.swift`.
- `Focus/LiveActivityController.swift`: the protocol, the display value and `RecordingLiveActivityController`.
- `Focus/FocusSessionStore.swift`.
- `Demo/FocusDemoScenario.swift` (DEBUG).
- `Notifications/ReminderInputs.swift`: moved from `App/Features/Notifications/ReminderInputs.swift`.
- **Edits:** `MapleStores.swift`, `Settings/AppSettings.swift`, `Notifications/NotificationScheduler.swift`, `Collection/CollectionStore.swift`, `Demo/DemoLaunchOptions.swift`, `Demo/DemoData.swift`, and the files that use `MapleContainer`.

**App:**
- Edits: `App/Features/Home/HomeView.swift` (the action switch), `App/Features/Notifications/ReminderUpkeep.swift`, `App/Features/Health/HealthPrimerSheet.swift`.
- Delete: `App/Features/Notifications/ReminderInputs.swift`.

**MapleDesign** (switch exhaustiveness only): `Herbarium/HerbariumCopy.swift`, `Herbarium/HerbariumModel.swift`.

**Scripts and docs:**
- `Scripts/generate-rewards.py` and `MapleKit/Sources/MapleCore/Resources/rewards.json`;
- `Scripts/check-release.sh` (new);
- `docs/design/spec.md`, `docs/core-api.md`, `docs/design/rewards.md`, `docs/debug-launch-arguments.md`, `docs/architecture.md`.

**Tests:**
- New suites in `MapleKit/Tests/MapleCoreTests/` and `MapleKit/Tests/MapleServicesTests/`, named per task.
- Edits to `LeafEngineTests`, `NowStateTests`, `RewardCatalogTests`, `StoreTests`, `ReminderPlanTests`, `NotificationSchedulerTests` and `SettingsTests`.

---

### Task 1: Package wiring for MapleFocusCore and MapleStorage

**Files:**
- Modify: `MapleKit/Package.swift`
- Create: `MapleKit/Sources/MapleFocusCore/FocusRules.swift`
- Create: `MapleKit/Sources/MapleCore/Focus/FocusCoreExport.swift`
- Create: `MapleKit/Sources/MapleStorage/MapleContainer.swift`
- Modify: `MapleKit/Sources/MapleServices/Storage/JSONStorage.swift:1-23` (remove `MapleContainer`)
- Create: `MapleKit/Sources/MapleServices/Storage/StorageExport.swift`
- Modify (add `import MapleStorage` under the existing imports): `MapleKit/Sources/MapleServices/MapleStores.swift`, `Settings/AppSettings.swift`, `Health/HealthPermission.swift`, `Health/HealthSleepImporter.swift`, `Onboarding/OnboardingStore.swift`
- Test: `MapleKit/Tests/MapleCoreTests/FocusModuleTests.swift`, `MapleKit/Tests/MapleServicesTests/StorageModuleTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `FocusRules.schemaVersion: Int` (1) and `FocusRules.version: Int` (1);
  - module `MapleFocusCore`, re-exported by `MapleCore`;
  - module `MapleStorage` (with `MapleContainer`), re-exported by `MapleServices`;
  - test targets can `@testable import MapleFocusCore` and `@testable import MapleStorage`.

- [ ] **Step 1: Write the failing tests**

`MapleKit/Tests/MapleCoreTests/FocusModuleTests.swift`:
```swift
import Testing
@testable import MapleCore

@Suite("Focus module")
struct FocusModuleTests {
    @Test("MapleCore re-exports MapleFocusCore")
    func reexport() {
        #expect(FocusRules.schemaVersion == 1)
        #expect(FocusRules.version == 1)
    }
}
```

`MapleKit/Tests/MapleServicesTests/StorageModuleTests.swift`:
```swift
import Foundation
import Testing
@testable import MapleServices

@Suite("Storage module")
struct StorageModuleTests {
    @Test("MapleServices re-exports MapleStorage's container")
    func container() {
        #expect(MapleContainer.directory().lastPathComponent == "Maple")
        #expect(!MapleContainer.appGroupIdentifier.isEmpty)
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -only-testing:MapleCoreTests/FocusModuleTests > "$WS/test.log" 2>&1; grep -E "error:" "$WS/test.log" | head -5`
Expected: `error: cannot find 'FocusRules' in scope`

- [ ] **Step 3: Add the targets**

In `MapleKit/Package.swift`:
- add two products after `MapleServices`'s:
  ```swift
          .library(name: "MapleFocusCore", targets: ["MapleFocusCore"]),
          .library(name: "MapleStorage", targets: ["MapleStorage"]),
  ```
- replace the `MapleCore` target and add the two new targets before it:
  ```swift
          // The types the F1-paid extensions share (events, plans, time, the ledger and the reconciler). No
          // resources, so the ~6 MB DeviceActivityMonitor extension can link it on its own. MapleCore re-exports it.
          .target(
              name: "MapleFocusCore",
              swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
          ),
          // The App Group container and the JSON-lines ledger files every Maple process writes. Nonisolated.
          .target(
              name: "MapleStorage",
              dependencies: ["MapleFocusCore"],
              swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
          ),
          // Pure Foundation. No SwiftUI/SwiftData: it must fit in the ~6 MB DeviceActivityMonitor extension.
          .target(
              name: "MapleCore",
              dependencies: ["MapleFocusCore"],
              resources: [.copy("Resources/species.json"), .copy("Resources/rewards.json")],
              swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
          ),
  ```
- change `MapleServices`' dependencies to `["MapleCore", "MapleData", "MapleStorage"]`;
- change the test targets:
  ```swift
          .testTarget(name: "MapleCoreTests", dependencies: ["MapleCore", "MapleFocusCore"]),
          .testTarget(name: "MapleDesignTests", dependencies: ["MapleDesign", "MapleCore"]),
          .testTarget(name: "MapleServicesTests", dependencies: ["MapleServices", "MapleCore", "MapleStorage", "MapleFocusCore"]),
  ```

`MapleKit/Sources/MapleFocusCore/FocusRules.swift`:
```swift
import Foundation

/// Versions of the focus ledger's format and of the counting rules (F1 design §3).
public enum FocusRules {
    /// The ledger event format. New kinds and fields don't change it; only an incompatible change would.
    public static let schemaVersion = 1
    /// The counting rules a day is counted under (R11): a rule change applies only to later days.
    public static let version = 1
}
```

`MapleKit/Sources/MapleCore/Focus/FocusCoreExport.swift`:
```swift
// MapleCore's clients see the focus types without importing MapleFocusCore themselves.
@_exported import MapleFocusCore
```

- [ ] **Step 4: Move `MapleContainer`**

Create `MapleKit/Sources/MapleStorage/MapleContainer.swift` with lines 1–23 of `JSONStorage.swift` moved unchanged (the `import Foundation` line and the whole `MapleContainer` enum with its doc comment). Then delete the enum from `JSONStorage.swift`, keeping `import Foundation` and `import os` there.

`MapleKit/Sources/MapleServices/Storage/StorageExport.swift`:
```swift
// The app and its views see MapleStorage's container and files through MapleServices.
@_exported import MapleStorage
```

Add `import MapleStorage` after the existing imports in each MapleServices file that names `MapleContainer`: `MapleStores.swift`, `Settings/AppSettings.swift`, `Health/HealthPermission.swift`, `Health/HealthSleepImporter.swift`, `Onboarding/OnboardingStore.swift`. With MemberImportVisibility on, each file needs its own import. `App/Features/Rest/BedsideLog.swift` already imports MapleServices, which re-exports MapleStorage, so it doesn't change.

- [ ] **Step 5: Run both suites to verify they pass**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -only-testing:MapleCoreTests/FocusModuleTests -only-testing:MapleServicesTests/StorageModuleTests > "$WS/test.log" 2>&1; tail -3 "$WS/test.log"`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: Run the whole suite**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh > "$WS/test.log" 2>&1; tail -3 "$WS/test.log"`
Expected: `** TEST SUCCEEDED **`, with no new warnings (`grep -c "warning:" "$WS/test.log"` the same as on `main`).

- [ ] **Step 7: Commit**

```bash
git add MapleKit/Package.swift MapleKit/Sources/MapleFocusCore MapleKit/Sources/MapleStorage MapleKit/Sources/MapleCore/Focus MapleKit/Sources/MapleServices MapleKit/Tests
git commit -m "MapleFocusCore and MapleStorage targets, re-exported by MapleCore and MapleServices

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Plans and qualifying selections

**Files:**
- Create: `MapleKit/Sources/MapleFocusCore/FocusPlan.swift`
- Create: `MapleKit/Tests/MapleCoreTests/FocusFixtures.swift` (shared test builders; later tasks extend it)
- Test: `MapleKit/Tests/MapleCoreTests/FocusPlanTests.swift`

**Interfaces:**
- Consumes: `FocusRules.version`.
- Produces (tests): `FocusFixtures.device`, `.session`, `.window(_:month:)`, `.blockSix`, `.plan(minutes:breakMinutes:strictness:kind:selection:day:window:)`.
- Produces:
  - `FocusVerb` (`.study`, `.quick`, `.deep`, `.reading`, `.focus`), with `startTitle: String`;
  - `Strictness` (`.gentle`, `.steady`, `.locked`; `Comparable`);
  - `SessionKind` (`.blocking`, `.plainTimer`);
  - `StartSource` (`.focusTab`, `.home`, `.again`);
  - `AwakeWindow(start:end:windDown:)`, with `contains(_:)` and `interval`;
  - `SelectionSummary(mode:apps:sites:categories:)`, with `.Mode` (`.blockThese`, `.onlyThese`), `qualifies`, `withinTokenLimit`, `isEmpty`, and the static `tokenLimit = 50` and `onlyTheseLimit = 20`;
  - `FocusPlan(presetID:presetName:verb:plannedSeconds:breakSeconds:strictness:kind:appSetID:selection:startedFrom:mapleDay:window:zone:appBuild:rulesVersion:)`, with `canCount: Bool` and `plannedMinutes: Int`;
  - `FocusPlan.minimumSeconds = 1200` and `maximumSeconds = 10800`.

- [ ] **Step 1: Write the failing tests**

`MapleKit/Tests/MapleCoreTests/FocusFixtures.swift`:
```swift
import Foundation
@testable import MapleCore

/// Shared builders for focus tests. Later suites add to it in their own files.
enum FocusFixtures {
    static let device = UUID(uuidString: "00000000-0000-4000-8000-0000000000D1")!
    static let session = UUID(uuidString: "00000000-0000-4000-8000-0000000000A1")!

    static func window(_ day: Int = 23, month: Int = 10) -> AwakeWindow {
        AwakeWindow(start: at(2026, month, day, 6), end: at(2026, month, day, 23), windDown: at(2026, month, day, 22, 15))
    }

    static let blockSix = SelectionSummary(mode: .blockThese, apps: 6, sites: 0, categories: 0)

    static func plan(
        minutes: Int = 50, breakMinutes: Int = 0, strictness: Strictness = .steady, kind: SessionKind = .blocking,
        selection: SelectionSummary? = FocusFixtures.blockSix, day: String = "2026-10-23",
        window: AwakeWindow = FocusFixtures.window()
    ) -> FocusPlan {
        FocusPlan(
            presetID: UUID(uuidString: "00000000-0000-4000-8000-00000000F001")!, presetName: "Study", verb: .study,
            plannedSeconds: minutes * 60, breakSeconds: breakMinutes * 60, strictness: strictness, kind: kind,
            appSetID: nil, selection: selection, startedFrom: .focusTab, mapleDay: day, window: window, zone: "UTC",
            appBuild: "1", rulesVersion: FocusRules.version
        )
    }
}
```

`MapleKit/Tests/MapleCoreTests/FocusPlanTests.swift`:
```swift
import Foundation
import Testing
@testable import MapleCore

@Suite("Focus plans")
struct FocusPlanTests {
    @Test("Block these: any app, site or category qualifies; an empty list doesn't (R3, F1-14)")
    func blockThese() {
        #expect(SelectionSummary(mode: .blockThese, apps: 1, sites: 0, categories: 0).qualifies)
        #expect(SelectionSummary(mode: .blockThese, apps: 0, sites: 1, categories: 0).qualifies)
        #expect(SelectionSummary(mode: .blockThese, apps: 0, sites: 0, categories: 1).qualifies)
        #expect(!SelectionSummary(mode: .blockThese, apps: 0, sites: 0, categories: 0).qualifies)
        #expect(SelectionSummary(mode: .blockThese, apps: 0, sites: 0, categories: 0).isEmpty)
    }

    @Test("Only these: no allowed categories and at most 20 apps or sites")
    func onlyThese() {
        #expect(SelectionSummary(mode: .onlyThese, apps: 20, sites: 0, categories: 0).qualifies)
        #expect(SelectionSummary(mode: .onlyThese, apps: 12, sites: 8, categories: 0).qualifies)
        #expect(!SelectionSummary(mode: .onlyThese, apps: 21, sites: 0, categories: 0).qualifies)
        #expect(!SelectionSummary(mode: .onlyThese, apps: 3, sites: 0, categories: 1).qualifies)
    }

    @Test("More than 50 app or web tokens never qualifies, because iOS would block nothing")
    func tokenLimit() {
        #expect(SelectionSummary(mode: .blockThese, apps: 50, sites: 50, categories: 0).qualifies)
        #expect(!SelectionSummary(mode: .blockThese, apps: 51, sites: 0, categories: 0).qualifies)
        #expect(!SelectionSummary(mode: .blockThese, apps: 0, sites: 51, categories: 0).withinTokenLimit)
    }

    @Test("A plan counts only when it blocks a qualifying selection")
    func canCount() {
        #expect(FocusFixtures.plan().canCount)
        #expect(!FocusFixtures.plan(kind: .plainTimer).canCount)
        #expect(!FocusFixtures.plan(selection: nil).canCount)
        #expect(!FocusFixtures.plan(selection: SelectionSummary(mode: .blockThese, apps: 0, sites: 0, categories: 0)).canCount)
    }

    @Test("Plans round-trip through JSON")
    func codable() throws {
        let plan = FocusFixtures.plan(minutes: 90, breakMinutes: 5, strictness: .locked)
        let decoded = try JSONDecoder().decode(FocusPlan.self, from: try JSONEncoder().encode(plan))
        #expect(decoded == plan)
        #expect(decoded.plannedMinutes == 90)
    }

    @Test("Strictness orders gentle, steady, locked")
    func strictnessOrder() {
        #expect(Strictness.gentle < .steady)
        #expect(Strictness.steady < .locked)
    }

    @Test("The awake window holds its start and not its end")
    func window() {
        let window = FocusFixtures.window()
        #expect(window.contains(at(2026, 10, 23, 6)))
        #expect(window.contains(at(2026, 10, 23, 22, 59)))
        #expect(!window.contains(at(2026, 10, 23, 23)))
        #expect(window.interval.duration == 17 * 3600)
    }

    @Test("Each verb's capsule title")
    func verbs() {
        #expect(FocusVerb.study.startTitle == "Start study")
        #expect(FocusVerb.quick.startTitle == "Start a quick session")
        #expect(FocusVerb.deep.startTitle == "Start a deep session")
        #expect(FocusVerb.reading.startTitle == "Start reading")
        #expect(FocusVerb.focus.startTitle == "Start focus")
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -only-testing:MapleCoreTests/FocusPlanTests > "$WS/test.log" 2>&1; grep -E "error:" "$WS/test.log" | head -5`
Expected: `error: cannot find type 'AwakeWindow' in scope` (and similar)

- [ ] **Step 3: Write the plan types**

`MapleKit/Sources/MapleFocusCore/FocusPlan.swift`:
```swift
import Foundation

/// The verb a preset's capsule uses (F1 design §5.1).
public enum FocusVerb: String, Codable, Sendable, CaseIterable {
    case study, quick, deep, reading, focus

    /// "Start study", "Start a quick session", …
    public var startTitle: String {
        switch self {
        case .study: "Start study"
        case .quick: "Start a quick session"
        case .deep: "Start a deep session"
        case .reading: "Start reading"
        case .focus: "Start focus"
        }
    }
}

/// How hard a session is to leave (focus spec §5.3).
public enum Strictness: String, Codable, Sendable, CaseIterable, Comparable {
    case gentle, steady, locked

    private var rank: Int {
        switch self {
        case .gentle: 0
        case .steady: 1
        case .locked: 2
        }
    }

    public static func < (lhs: Strictness, rhs: Strictness) -> Bool { lhs.rank < rhs.rank }
}

/// A session that locks apps, or a plain timer that counts nothing (R12).
public enum SessionKind: String, Codable, Sendable {
    case blocking, plainTimer
}

/// Where the member started the session.
public enum StartSource: String, Codable, Sendable {
    case focusTab, home, again
}

/// The part of a Maple day that can count, frozen into a session when it starts (F1 design §3.3 step 6).
public struct AwakeWindow: Codable, Sendable, Hashable {
    /// 60 minutes before last night's wake (widened for a short night).
    public var start: Date
    /// Tonight's bedtime.
    public var end: Date
    /// Tonight's wind-down start.
    public var windDown: Date

    public init(start: Date, end: Date, windDown: Date) {
        self.start = start
        self.end = end
        self.windDown = windDown
    }

    public func contains(_ date: Date) -> Bool {
        start <= date && date < end
    }

    public var interval: DateInterval {
        DateInterval(start: start, end: max(start, end))
    }
}

/// What a selection holds, without its tokens (focus spec §5.2). It decides whether a session can count (R3).
public struct SelectionSummary: Codable, Sendable, Hashable {
    public enum Mode: String, Codable, Sendable {
        /// A block list.
        case blockThese
        /// An allow list: everything else is blocked.
        case onlyThese
    }

    /// iOS blocks nothing when a store holds more than this many app or web tokens.
    public static let tokenLimit = 50
    /// "Only these" counts with at most this many apps and sites.
    public static let onlyTheseLimit = 20

    public var mode: Mode
    public var apps: Int
    public var sites: Int
    public var categories: Int

    public init(mode: Mode, apps: Int, sites: Int, categories: Int) {
        self.mode = mode
        self.apps = apps
        self.sites = sites
        self.categories = categories
    }

    public var isEmpty: Bool { apps == 0 && sites == 0 && categories == 0 }

    public var withinTokenLimit: Bool { apps <= Self.tokenLimit && sites <= Self.tokenLimit }

    /// R3 as F1-14 relaxed it: any non-empty "Block these"; "Only these" with no allowed categories and at most 20
    /// apps or sites; never over the token limit.
    public var qualifies: Bool {
        guard withinTokenLimit else { return false }
        switch mode {
        case .blockThese: return !isEmpty
        case .onlyThese: return categories == 0 && apps + sites <= Self.onlyTheseLimit
        }
    }
}

/// Everything about a session that is fixed when it starts, written into `sessionStarted` (F1 design §7.1).
/// It holds no free text beyond the preset's name; intentions live in `session-notes.json`.
public struct FocusPlan: Codable, Sendable, Hashable {
    /// The shortest and longest sessions (R8, F1-15).
    public static let minimumSeconds = 20 * 60
    public static let maximumSeconds = 3 * 3600

    public var presetID: UUID
    public var presetName: String
    public var verb: FocusVerb
    public var plannedSeconds: Int
    /// One locked break inside the planned length, or 0 (F1-11).
    public var breakSeconds: Int
    public var strictness: Strictness
    public var kind: SessionKind
    public var appSetID: UUID?
    /// Frozen at start (R3); nil for a plain timer.
    public var selection: SelectionSummary?
    public var startedFrom: StartSource
    /// The Maple day the session counts toward, as "yyyy-MM-dd" (`FocusPlan.day` in MapleCore reads it as a `LocalDay`).
    public var mapleDay: String
    public var window: AwakeWindow
    public var zone: String
    public var appBuild: String
    public var rulesVersion: Int

    public init(
        presetID: UUID, presetName: String, verb: FocusVerb, plannedSeconds: Int, breakSeconds: Int,
        strictness: Strictness, kind: SessionKind, appSetID: UUID?, selection: SelectionSummary?,
        startedFrom: StartSource, mapleDay: String, window: AwakeWindow, zone: String, appBuild: String,
        rulesVersion: Int
    ) {
        self.presetID = presetID
        self.presetName = presetName
        self.verb = verb
        self.plannedSeconds = plannedSeconds
        self.breakSeconds = breakSeconds
        self.strictness = strictness
        self.kind = kind
        self.appSetID = appSetID
        self.selection = selection
        self.startedFrom = startedFrom
        self.mapleDay = mapleDay
        self.window = window
        self.zone = zone
        self.appBuild = appBuild
        self.rulesVersion = rulesVersion
    }

    /// A blocking session whose selection qualifies: the only kind that can count (R2, R3, R12).
    public var canCount: Bool {
        kind == .blocking && (selection?.qualifies ?? false)
    }

    public var plannedMinutes: Int { plannedSeconds / 60 }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -only-testing:MapleCoreTests/FocusPlanTests > "$WS/test.log" 2>&1; tail -3 "$WS/test.log"`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add MapleKit/Sources/MapleFocusCore/FocusPlan.swift MapleKit/Tests/MapleCoreTests/FocusFixtures.swift MapleKit/Tests/MapleCoreTests/FocusPlanTests.swift
git commit -m "Focus plans, frozen windows and the relaxed qualifying rule

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Ledger events

**Files:**
- Create: `MapleKit/Sources/MapleFocusCore/FocusEvent.swift`
- Test: `MapleKit/Tests/MapleCoreTests/FocusEventTests.swift`

**Interfaces:**
- Consumes: `FocusRules.schemaVersion`, `FocusPlan` (Task 2), `FocusFixtures` (Task 2).
- Produces:
  - `EventStamp(wall:continuous:boot:zone:)` and `seconds(since:) -> TimeInterval`;
  - `FocusWriter` (`.app`, `.monitor`, `.shieldAction`; `Comparable`);
  - `FocusSource` (`.live`, `.preview`);
  - `EndReason` (`.completed`, `.endedEarly`, `.emergencyRelease`, `.releaseAll`);
  - `ShieldClearReason` (`.sessionEnded`, `.releaseAll`, `.expired`, `.orphaned`);
  - `Reflection` (`.allDone`, `.partly`, `.notYet`);
  - `FocusEventKind`, with `type: String`, `affectsCredit: Bool`, `isTerminal: Bool` and `isCheckpoint: Bool`;
  - `FocusEvent(id:kind:sessionID:deviceID:writer:seq:source:stamp:affectsCredit:version:)`;
  - `FocusEvent.derivedID(session:kind:) -> String`.

- [ ] **Step 1: Write the failing tests**

`MapleKit/Tests/MapleCoreTests/FocusEventTests.swift`:
```swift
import Foundation
import Testing
@testable import MapleCore

extension FocusFixtures {
    static func stamp(_ wall: Date, cont: UInt64 = 1_000_000_000_000, boot: String = "b1", zone: String = "UTC") -> EventStamp {
        EventStamp(wall: wall, continuous: cont, boot: boot, zone: zone)
    }

    static func event(
        _ kind: FocusEventKind, at stamp: EventStamp, seq: Int, session: UUID = FocusFixtures.session, writer: FocusWriter = .app,
        source: FocusSource = .live, id: String? = nil
    ) -> FocusEvent {
        FocusEvent(id: id ?? "e\(seq)-\(session.uuidString.prefix(4))", kind: kind, sessionID: session, deviceID: device,
                   writer: writer, seq: seq, source: source, stamp: stamp)
    }
}

@Suite("Focus events")
struct FocusEventTests {
    private func roundTrip(_ event: FocusEvent) throws -> FocusEvent {
        let data = try JSONEncoder().encode(event)
        return try JSONDecoder().decode(FocusEvent.self, from: data)
    }

    @Test("Every kind round-trips through JSON")
    func roundTrips() throws {
        let stamp = FocusFixtures.stamp(at(2026, 10, 23, 14))
        let kinds: [FocusEventKind] = [
            .shieldApplied, .shieldVerified, .shieldLost, .breakStarted(seconds: 300), .breakEnded,
            .overrideStarted(seconds: 60), .overrideEnded, .sessionEnded(.completed, verified: true),
            .sessionEnded(.emergencyRelease, verified: false), .shieldCleared(.releaseAll), .reflected(.partly),
            .sessionHidden,
        ]
        for (index, kind) in kinds.enumerated() {
            let event = FocusFixtures.event(kind, at: stamp, seq: index + 1)
            #expect(try roundTrip(event) == event)
        }
    }

    @Test("A kind this build doesn't know is kept as unknown, and keeps its credit flag")
    func unknownKind() throws {
        let line = """
        {"id":"x1","v":1,"type":"phoneBreakStarted","session":"00000000-0000-4000-8000-0000000000A1",\
        "device":"00000000-0000-4000-8000-0000000000D1","writer":"app","seq":7,"source":"live","credit":true,\
        "at":{"wall":1792764000,"cont":5,"boot":"b1","zone":"UTC"},"seconds":120}
        """
        let event = try JSONDecoder().decode(FocusEvent.self, from: Data(line.utf8))
        #expect(event.kind == .unknown("phoneBreakStarted"))
        #expect(event.affectsCredit)
        #expect(event.seq == 7)
        let again = try roundTrip(event)
        #expect(again.kind == .unknown("phoneBreakStarted"))
    }

    @Test("A known kind with a payload this build can't read becomes unknown instead of being lost")
    func unreadablePayload() throws {
        let line = """
        {"id":"x2","v":1,"type":"sessionEnded","session":"00000000-0000-4000-8000-0000000000A1",\
        "device":"00000000-0000-4000-8000-0000000000D1","writer":"monitor","seq":3,"source":"live",\
        "at":{"wall":1792764000,"cont":5,"boot":"b1","zone":"UTC"},"reason":"timedOut"}
        """
        let event = try JSONDecoder().decode(FocusEvent.self, from: Data(line.utf8))
        #expect(event.kind == .unknown("sessionEnded"))
        #expect(event.writer == .monitor)
        #expect(event.affectsCredit)
    }

    @Test("The stamp's wall time is seconds since 1970, and continuous time is in nanoseconds")
    func stampFormat() throws {
        let stamp = EventStamp(wall: Date(timeIntervalSince1970: 1_792_764_000), continuous: 42, boot: "b", zone: "Asia/Kolkata")
        let json = try #require(String(data: try JSONEncoder().encode(stamp), encoding: .utf8))
        #expect(json.contains("\"wall\":1792764000"))
        #expect(json.contains("\"cont\":42"))
        let later = EventStamp(wall: stamp.wall, continuous: 42 + 2_500_000_000, boot: "b", zone: "Asia/Kolkata")
        #expect(later.seconds(since: stamp) == 2.5)
        #expect(stamp.seconds(since: later) == -2.5)
    }

    @Test("Reflections and hiding never affect credit; everything else does")
    func creditFlags() {
        #expect(!FocusEventKind.reflected(.allDone).affectsCredit)
        #expect(!FocusEventKind.sessionHidden.affectsCredit)
        #expect(FocusEventKind.shieldVerified.affectsCredit)
        #expect(FocusEventKind.unknown("future").affectsCredit)
    }

    @Test("Checkpoints are the read-backs after the start; a verified end is one too")
    func checkpoints() {
        #expect(FocusEventKind.shieldVerified.isCheckpoint)
        #expect(FocusEventKind.breakStarted(seconds: 300).isCheckpoint)
        #expect(FocusEventKind.breakEnded.isCheckpoint)
        #expect(FocusEventKind.overrideEnded.isCheckpoint)
        #expect(FocusEventKind.shieldApplied.isCheckpoint)
        #expect(FocusEventKind.sessionEnded(.completed, verified: true).isCheckpoint)
        #expect(!FocusEventKind.sessionEnded(.completed, verified: false).isCheckpoint)
        #expect(!FocusEventKind.overrideStarted(seconds: 60).isCheckpoint)
        #expect(!FocusEventKind.shieldLost.isCheckpoint)
        #expect(FocusEventKind.sessionEnded(.endedEarly, verified: false).isTerminal)
    }

    @Test("Derived ids are the same for any process that derives them")
    func derivedIDs() {
        let a = FocusEvent.derivedID(session: FocusFixtures.session, kind: .sessionEnded(.completed, verified: true))
        let b = FocusEvent.derivedID(session: FocusFixtures.session, kind: .sessionEnded(.completed, verified: false))
        #expect(a == b)
        #expect(a == "00000000-0000-4000-8000-0000000000a1.sessionEnded")
    }

    @Test("Writers sort app, monitor, shield action")
    func writerOrder() {
        #expect(FocusWriter.allCases.sorted() == [.app, .monitor, .shieldAction])
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -only-testing:MapleCoreTests/FocusEventTests > "$WS/test.log" 2>&1; grep -E "error:" "$WS/test.log" | head -5`
Expected: `error: cannot find type 'EventStamp' in scope` (and similar)

- [ ] **Step 3: Write the event model**

`MapleKit/Sources/MapleFocusCore/FocusEvent.swift`:
```swift
import Foundation

/// The process that wrote an event. Each writes its own ledger file, so no two ever write the same file (F1 design §7.3).
public enum FocusWriter: String, Codable, Sendable, CaseIterable, Comparable {
    case app, monitor, shieldAction

    private var rank: Int {
        switch self {
        case .app: 0
        case .monitor: 1
        case .shieldAction: 2
        }
    }

    public static func < (lhs: FocusWriter, rhs: FocusWriter) -> Bool { lhs.rank < rhs.rank }
}

/// Where an event came from: the real blocker, or DEBUG's preview blocker, which only the sandbox credits (§3.3).
public enum FocusSource: String, Codable, Sendable, CaseIterable {
    case live, preview
}

/// When an event happened, on the clocks Maple can trust (F1 design §3.1–3.2).
public struct EventStamp: Sendable, Hashable, Codable {
    /// The wall clock, which the member can change.
    public var wall: Date
    /// Nanoseconds on the continuous clock, which keeps counting while the phone sleeps and restarts at boot.
    public var continuous: UInt64
    /// This boot, hashed with the device id (`LiveFocusTime`), so it can't be matched across installs.
    public var boot: String
    /// The time zone in force (`TimeZone.identifier`).
    public var zone: String

    public init(wall: Date, continuous: UInt64, boot: String, zone: String) {
        self.wall = wall
        self.continuous = continuous
        self.boot = boot
        self.zone = zone
    }

    /// Seconds from `other` to this stamp on the continuous clock. Only meaningful within one boot.
    public func seconds(since other: EventStamp) -> TimeInterval {
        if continuous >= other.continuous { return TimeInterval(continuous - other.continuous) / 1e9 }
        return -TimeInterval(other.continuous - continuous) / 1e9
    }

    private enum CodingKeys: String, CodingKey {
        case wall, continuous = "cont", boot, zone
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        wall = Date(timeIntervalSince1970: try c.decode(Double.self, forKey: .wall))
        continuous = try c.decode(UInt64.self, forKey: .continuous)
        boot = try c.decode(String.self, forKey: .boot)
        zone = try c.decode(String.self, forKey: .zone)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(wall.timeIntervalSince1970, forKey: .wall)
        try c.encode(continuous, forKey: .continuous)
        try c.encode(boot, forKey: .boot)
        try c.encode(zone, forKey: .zone)
    }
}

/// How a session ended. Only `completed` can be finished (R13).
public enum EndReason: String, Codable, Sendable, CaseIterable {
    /// It reached its planned end.
    case completed
    /// Gentle's or Steady's End early.
    case endedEarly
    /// Locked's 10-second hold.
    case emergencyRelease
    /// Settings › Release all apps.
    case releaseAll
}

/// Why shields came off.
public enum ShieldClearReason: String, Codable, Sendable, CaseIterable {
    case sessionEnded
    case releaseAll
    /// The reconciler found a session past its planned end.
    case expired
    /// Shields with no running session (the app was killed mid-start).
    case orphaned
}

/// The receipt's "How did it go?" answer.
public enum Reflection: String, Codable, Sendable, CaseIterable {
    case allDone, partly, notYet
}

/// What happened (F1 design §3.1).
public enum FocusEventKind: Sendable, Hashable {
    case sessionStarted(FocusPlan)
    /// Written only after Maple read its own block back: credit starts here.
    case shieldApplied
    /// A later read-back that succeeded: a checkpoint.
    case shieldVerified
    /// A read-back that didn't find the block: credit stops at the checkpoint before it.
    case shieldLost
    case breakStarted(seconds: Int)
    case breakEnded
    /// A Gentle or Steady unlock from the shield ("Need it?"); its whole window is removed.
    case overrideStarted(seconds: Int)
    case overrideEnded
    case sessionEnded(EndReason, verified: Bool)
    case shieldCleared(ShieldClearReason)
    case reflected(Reflection)
    /// Reserved for History's delete (F2): hides a session, never its leaves.
    case sessionHidden
    /// A kind this build doesn't know, kept so the session can stop crediting at it.
    case unknown(String)

    /// The kind's name in the ledger file.
    public var type: String {
        switch self {
        case .sessionStarted: "sessionStarted"
        case .shieldApplied: "shieldApplied"
        case .shieldVerified: "shieldVerified"
        case .shieldLost: "shieldLost"
        case .breakStarted: "breakStarted"
        case .breakEnded: "breakEnded"
        case .overrideStarted: "overrideStarted"
        case .overrideEnded: "overrideEnded"
        case .sessionEnded: "sessionEnded"
        case .shieldCleared: "shieldCleared"
        case .reflected: "reflected"
        case .sessionHidden: "sessionHidden"
        case .unknown(let type): type
        }
    }

    /// Whether this kind can change credit. Reflections and hiding never do; unknown kinds are assumed to.
    public var affectsCredit: Bool {
        switch self {
        case .reflected, .sessionHidden: false
        default: true
        }
    }

    /// Ends the session. Only the first one counts.
    public var isTerminal: Bool {
        if case .sessionEnded = self { return true }
        return false
    }

    /// Written right after a read-back that found the block (§3.3 step 2).
    public var isCheckpoint: Bool {
        switch self {
        case .shieldApplied, .shieldVerified, .breakStarted, .breakEnded, .overrideEnded: true
        case .sessionEnded(_, let verified): verified
        default: false
        }
    }
}

/// One line of the append-only focus ledger (F1 design §3.1).
public struct FocusEvent: Sendable, Hashable, Identifiable, Codable {
    public var id: String
    /// The format version, `FocusRules.schemaVersion` when written.
    public var version: Int
    public var kind: FocusEventKind
    public var sessionID: UUID
    /// A random UUID made once per install and kept in the container.
    public var deviceID: UUID
    public var writer: FocusWriter
    /// This writer's sequence number, which only ever goes up (its true append order, whatever the clock says).
    public var seq: Int
    public var source: FocusSource
    public var affectsCredit: Bool
    public var stamp: EventStamp

    public init(
        id: String, kind: FocusEventKind, sessionID: UUID, deviceID: UUID, writer: FocusWriter, seq: Int,
        source: FocusSource, stamp: EventStamp, affectsCredit: Bool? = nil, version: Int = FocusRules.schemaVersion
    ) {
        self.id = id
        self.version = version
        self.kind = kind
        self.sessionID = sessionID
        self.deviceID = deviceID
        self.writer = writer
        self.seq = seq
        self.source = source
        self.affectsCredit = affectsCredit ?? kind.affectsCredit
        self.stamp = stamp
    }

    /// The id any process gives `kind` for `session`, so the same event written twice merges as one (§3.1).
    public static func derivedID(session: UUID, kind: FocusEventKind) -> String {
        session.uuidString.lowercased() + "." + kind.type
    }

    // MARK: Codable: one flat JSON object per line

    private enum CodingKeys: String, CodingKey {
        case id, version = "v", type, sessionID = "session", deviceID = "device", writer, seq, source
        case affectsCredit = "credit", stamp = "at"
        case plan, seconds, reason, verified, answer
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        version = (try? c.decodeIfPresent(Int.self, forKey: .version)) ?? FocusRules.schemaVersion
        sessionID = try c.decode(UUID.self, forKey: .sessionID)
        deviceID = try c.decode(UUID.self, forKey: .deviceID)
        writer = (try? c.decodeIfPresent(FocusWriter.self, forKey: .writer)) ?? .app
        seq = (try? c.decodeIfPresent(Int.self, forKey: .seq)) ?? 0
        // A source this build doesn't know is never credited.
        source = (try? c.decodeIfPresent(FocusSource.self, forKey: .source)) ?? .preview
        stamp = try c.decode(EventStamp.self, forKey: .stamp)
        let type = try c.decode(String.self, forKey: .type)
        // A payload this build can't read keeps the event as `unknown` rather than dropping the line.
        let decoded: FocusEventKind? = switch type {
        case "sessionStarted": (try? c.decode(FocusPlan.self, forKey: .plan)).map { .sessionStarted($0) }
        case "shieldApplied": .shieldApplied
        case "shieldVerified": .shieldVerified
        case "shieldLost": .shieldLost
        case "breakStarted": (try? c.decode(Int.self, forKey: .seconds)).map { .breakStarted(seconds: $0) }
        case "breakEnded": .breakEnded
        case "overrideStarted": (try? c.decode(Int.self, forKey: .seconds)).map { .overrideStarted(seconds: $0) }
        case "overrideEnded": .overrideEnded
        case "sessionEnded":
            (try? c.decode(EndReason.self, forKey: .reason)).map {
                .sessionEnded($0, verified: (try? c.decodeIfPresent(Bool.self, forKey: .verified)) ?? false)
            }
        case "shieldCleared": (try? c.decode(ShieldClearReason.self, forKey: .reason)).map { .shieldCleared($0) }
        case "reflected": (try? c.decode(Reflection.self, forKey: .answer)).map { .reflected($0) }
        case "sessionHidden": .sessionHidden
        default: nil
        }
        kind = decoded ?? .unknown(type)
        affectsCredit = (try? c.decodeIfPresent(Bool.self, forKey: .affectsCredit)) ?? kind.affectsCredit
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(version, forKey: .version)
        try c.encode(kind.type, forKey: .type)
        try c.encode(sessionID, forKey: .sessionID)
        try c.encode(deviceID, forKey: .deviceID)
        try c.encode(writer, forKey: .writer)
        try c.encode(seq, forKey: .seq)
        try c.encode(source, forKey: .source)
        try c.encode(affectsCredit, forKey: .affectsCredit)
        try c.encode(stamp, forKey: .stamp)
        switch kind {
        case .sessionStarted(let plan): try c.encode(plan, forKey: .plan)
        case .breakStarted(let seconds), .overrideStarted(let seconds): try c.encode(seconds, forKey: .seconds)
        case .sessionEnded(let reason, let verified):
            try c.encode(reason, forKey: .reason)
            try c.encode(verified, forKey: .verified)
        case .shieldCleared(let reason): try c.encode(reason, forKey: .reason)
        case .reflected(let answer): try c.encode(answer, forKey: .answer)
        case .shieldApplied, .shieldVerified, .shieldLost, .breakEnded, .overrideEnded, .sessionHidden, .unknown: break
        }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -only-testing:MapleCoreTests/FocusEventTests > "$WS/test.log" 2>&1; tail -3 "$WS/test.log"`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add MapleKit/Sources/MapleFocusCore MapleKit/Tests/MapleCoreTests/FocusEventTests.swift
git commit -m "Focus ledger events: stamps, kinds and tolerant JSON lines

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Time sources

**Files:**
- Create: `MapleKit/Sources/MapleFocusCore/FocusTimeSource.swift`
- Test: `MapleKit/Tests/MapleCoreTests/FocusTimeSourceTests.swift`

**Interfaces:**
- Consumes: `EventStamp`.
- Produces:
  - `protocol FocusTimeSource: Sendable { func stamp() -> EventStamp }`;
  - `LiveFocusTime(deviceID:bootSession:)`, with `boot`, the static `bootSessionID() -> String?` and the internal static `hashedBoot(_:deviceID:)`;
  - `ManualFocusTime(wall:zone:boot:continuous:)`, with `advance(_:)`, `setWall(_:)`, `setZone(_:)`, `reboot(_:wall:)` and `now: Date`;
  - `ShiftedFocusTime(base:offset:)`.

- [ ] **Step 1: Write the failing tests**

`MapleKit/Tests/MapleCoreTests/FocusTimeSourceTests.swift`:
```swift
import Foundation
import Testing
@testable import MapleCore
@testable import MapleFocusCore

@Suite("Focus time sources")
struct FocusTimeSourceTests {
    @Test("Manual time moves the wall and continuous clocks together")
    func manualAdvance() {
        let time = ManualFocusTime(wall: at(2026, 10, 23, 14))
        let first = time.stamp()
        time.advance(90)
        let second = time.stamp()
        #expect(second.wall == at(2026, 10, 23, 14, 1, 30))
        #expect(second.seconds(since: first) == 90)
        #expect(second.boot == first.boot)
    }

    @Test("Setting the wall clock moves only the wall clock")
    func manualWall() {
        let time = ManualFocusTime(wall: at(2026, 10, 23, 14))
        let first = time.stamp()
        time.setWall(at(2026, 10, 22, 9))
        let second = time.stamp()
        #expect(second.wall == at(2026, 10, 22, 9))
        #expect(second.continuous == first.continuous)
    }

    @Test("A reboot starts a new boot with a small continuous clock")
    func manualReboot() {
        let time = ManualFocusTime(wall: at(2026, 10, 23, 14))
        let before = time.stamp()
        time.reboot("b2")
        let after = time.stamp()
        #expect(after.boot == "b2")
        #expect(after.continuous < before.continuous)
        #expect(after.wall == before.wall)
    }

    @Test("Live time: one boot id per launch, continuous time never goes back")
    func live() {
        let time = LiveFocusTime(deviceID: FocusFixtures.device)
        let a = time.stamp()
        let b = time.stamp()
        #expect(a.boot == b.boot)
        #expect(!a.boot.isEmpty)
        #expect(b.continuous >= a.continuous)
        #expect(a.zone == TimeZone.current.identifier)
    }

    @Test("The boot id is hashed with the device id, so two installs never share one")
    func hashed() {
        let one = LiveFocusTime.hashedBoot("ABC", deviceID: FocusFixtures.device)
        let other = LiveFocusTime.hashedBoot("ABC", deviceID: UUID())
        #expect(one != other)
        #expect(one == LiveFocusTime.hashedBoot("ABC", deviceID: FocusFixtures.device))
        #expect(!one.contains("ABC"))
    }

    @Test("When the boot id can't be read, each launch gets its own, so credit never joins two launches")
    func unreadableBoot() {
        let first = LiveFocusTime(deviceID: FocusFixtures.device, bootSession: nil)
        let second = LiveFocusTime(deviceID: FocusFixtures.device, bootSession: nil)
        #expect(first.boot != second.boot)
    }

    @Test("Shifted time keeps running, offset on the wall clock only")
    func shifted() {
        let base = LiveFocusTime(deviceID: FocusFixtures.device, bootSession: "fixed")
        let shifted = ShiftedFocusTime(base: base, offset: -3600)
        let stamp = shifted.stamp()
        #expect(abs(stamp.wall.timeIntervalSinceNow + 3600) < 5)
        #expect(stamp.boot == base.boot)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -only-testing:MapleCoreTests/FocusTimeSourceTests > "$WS/test.log" 2>&1; grep -E "error:" "$WS/test.log" | head -5`
Expected: `error: cannot find 'ManualFocusTime' in scope`

- [ ] **Step 3: Write the time sources**

`MapleKit/Sources/MapleFocusCore/FocusTimeSource.swift`:
```swift
import Foundation
import Synchronization

/// Where event stamps come from (F1 design §7.1). Injected, so tests and demos can move time.
public protocol FocusTimeSource: Sendable {
    func stamp() -> EventStamp
}

/// The real clocks: the wall clock, the continuous clock and this boot.
public struct LiveFocusTime: FocusTimeSource {
    /// This boot, hashed with the device id.
    public let boot: String

    /// - Parameter bootSession: `kern.bootsessionuuid`. When it can't be read, a random id stands in, so this launch's
    ///   credit can never be joined to another's.
    public init(deviceID: UUID, bootSession: String? = LiveFocusTime.bootSessionID()) {
        boot = Self.hashedBoot(bootSession ?? "unread-" + UUID().uuidString, deviceID: deviceID)
    }

    public func stamp() -> EventStamp {
        // CLOCK_MONOTONIC keeps counting while the phone sleeps (it is ContinuousClock's clock) and restarts at boot.
        EventStamp(wall: Date(), continuous: clock_gettime_nsec_np(CLOCK_MONOTONIC), boot: boot,
                   zone: TimeZone.current.identifier)
    }

    /// `kern.bootsessionuuid`, which changes at every restart; nil when it can't be read.
    public static func bootSessionID() -> String? {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.bootsessionuuid", &buffer, &size, nil, 0) == 0 else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        let text = String(decoding: bytes, as: UTF8.self)
        return text.isEmpty ? nil : text
    }

    /// FNV-1a over the boot id and the device id: stable within a boot, never the same across installs.
    static func hashedBoot(_ boot: String, deviceID: UUID) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in (boot + "|" + deviceID.uuidString).utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}

/// Clocks moved by hand, for tests and demo scenarios. The wall and continuous clocks advance together; `setWall`
/// changes only the wall clock, as the member can; `reboot` starts a new boot.
public final class ManualFocusTime: FocusTimeSource {
    private let state: Mutex<EventStamp>

    public init(wall: Date, zone: String = "UTC", boot: String = "b1", continuous: UInt64 = 1_000_000_000_000) {
        state = Mutex(EventStamp(wall: wall, continuous: continuous, boot: boot, zone: zone))
    }

    public func stamp() -> EventStamp {
        state.withLock { $0 }
    }

    public var now: Date { stamp().wall }

    public func advance(_ seconds: TimeInterval) {
        state.withLock { stamp in
            stamp.wall = stamp.wall.addingTimeInterval(seconds)
            stamp.continuous += UInt64((seconds * 1e9).rounded())
        }
    }

    public func setWall(_ date: Date) {
        state.withLock { $0.wall = date }
    }

    public func setZone(_ zone: String) {
        state.withLock { $0.zone = zone }
    }

    /// A restart: a new boot whose continuous clock starts small. The wall clock carries on unless `wall` is given.
    public func reboot(_ boot: String, wall: Date? = nil) {
        state.withLock { stamp in
            stamp.boot = boot
            stamp.continuous = 5_000_000_000
            if let wall { stamp.wall = wall }
        }
    }
}

/// The real clocks with the wall clock moved by `offset`: DEBUG demos that start inside a chosen phase and keep running.
public struct ShiftedFocusTime: FocusTimeSource {
    public let base: LiveFocusTime
    public let offset: TimeInterval

    public init(base: LiveFocusTime, offset: TimeInterval) {
        self.base = base
        self.offset = offset
    }

    public func stamp() -> EventStamp {
        var stamp = base.stamp()
        stamp.wall = stamp.wall.addingTimeInterval(offset)
        return stamp
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -only-testing:MapleCoreTests/FocusTimeSourceTests > "$WS/test.log" 2>&1; tail -3 "$WS/test.log"`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add MapleKit/Sources/MapleFocusCore/FocusTimeSource.swift MapleKit/Tests/MapleCoreTests/FocusTimeSourceTests.swift
git commit -m "Focus time sources: live clocks with a hashed boot id, manual and shifted clocks

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 5: The ledger: merge, order and trusted time

**Files:**
- Create: `MapleKit/Sources/MapleFocusCore/FocusLedger.swift`
- Test: `MapleKit/Tests/MapleCoreTests/FocusLedgerTests.swift`

**Interfaces:**
- Consumes: `FocusEvent`, `EventStamp`, `FocusWriter` (Task 3).
- Produces:
  - `PlacedEvent(event:placed:)`;
  - `FocusLedger(_:)`, with `events`, `merge(_:)` and `placed() -> [PlacedEvent]`;
  - internal `FocusLedger.BootKey`, `bootRanks(_:)`, `ordered(_:)` and `prefers(_:over:)`.

- [ ] **Step 1: Write the failing tests**

`MapleKit/Tests/MapleCoreTests/FocusLedgerTests.swift`:
```swift
import Foundation
import Testing
@testable import MapleCore
@testable import MapleFocusCore

/// A deterministic generator for shuffles (a linear congruential generator).
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}

@Suite("Focus ledger")
struct FocusLedgerTests {
    private let base = at(2026, 10, 23, 14)

    /// Two sessions across two boots, as the app would write them.
    private func sample() -> [FocusEvent] {
        let s1 = UUID(uuidString: "00000000-0000-4000-8000-0000000000A1")!
        let s2 = UUID(uuidString: "00000000-0000-4000-8000-0000000000A2")!
        func stamp(_ minutes: Double, boot: String = "b1", cont: UInt64? = nil) -> EventStamp {
            FocusFixtures.stamp(base.addingTimeInterval(minutes * 60), cont: cont ?? UInt64(minutes * 60 * 1e9) + 1_000_000_000, boot: boot)
        }
        return [
            FocusFixtures.event(.sessionStarted(FocusFixtures.plan()), at: stamp(0), seq: 1, session: s1),
            FocusFixtures.event(.shieldApplied, at: stamp(0.1), seq: 2, session: s1),
            FocusFixtures.event(.shieldVerified, at: stamp(20), seq: 3, session: s1),
            FocusFixtures.event(.sessionEnded(.completed, verified: true), at: stamp(50.1), seq: 4, session: s1,
                                id: FocusEvent.derivedID(session: s1, kind: .sessionEnded(.completed, verified: true))),
            FocusFixtures.event(.sessionStarted(FocusFixtures.plan()), at: stamp(120, boot: "b2", cont: 9_000_000_000), seq: 5, session: s2),
            FocusFixtures.event(.shieldApplied, at: stamp(120.1, boot: "b2", cont: 15_000_000_000), seq: 6, session: s2),
        ]
    }

    @Test("Merging is order-free and idempotent")
    func orderFree() {
        let events = sample()
        let reference = FocusLedger(events)
        var generator = SeededGenerator(state: 7)
        for _ in 0..<20 {
            var shuffled = events
            shuffled.shuffle(using: &generator)
            var ledger = FocusLedger(Array(shuffled.prefix(3)))
            ledger.merge(Array(shuffled.dropFirst(3)))
            ledger.merge(shuffled)
            #expect(ledger == reference)
        }
        #expect(reference.events.count == 6)
    }

    @Test("Two different events under one id: the same one wins in any order")
    func sameIDDeterministic() {
        let id = FocusEvent.derivedID(session: FocusFixtures.session, kind: .sessionEnded(.completed, verified: true))
        let fromApp = FocusFixtures.event(.sessionEnded(.completed, verified: true), at: FocusFixtures.stamp(base, cont: 50), seq: 9, id: id)
        let fromMonitor = FocusFixtures.event(.sessionEnded(.completed, verified: false), at: FocusFixtures.stamp(base, cont: 40), seq: 2,
                                              writer: .monitor, id: id)
        let one = FocusLedger([fromApp, fromMonitor])
        let other = FocusLedger([fromMonitor, fromApp])
        #expect(one == other)
        #expect(one.events.count == 1)
        #expect(one.events.first?.writer == .app)
    }

    @Test("Within a boot, events are placed by continuous time, so a clock change moves nothing")
    func clockChangeInsideBoot() {
        let start = FocusFixtures.event(.sessionStarted(FocusFixtures.plan()), at: FocusFixtures.stamp(base, cont: 1_000_000_000), seq: 1)
        // The member sets the clock back a day, ten minutes later.
        let later = FocusFixtures.event(.shieldVerified,
                                        at: FocusFixtures.stamp(base.addingTimeInterval(-86400 + 600), cont: 601_000_000_000), seq: 2)
        let placed = FocusLedger([start, later]).placed()
        #expect(placed.map(\.placed) == [base, base.addingTimeInterval(600)])
    }

    @Test("A new boot is never placed before the last event of the boot before it")
    func newBootFloor() {
        let first = FocusFixtures.event(.sessionStarted(FocusFixtures.plan()), at: FocusFixtures.stamp(base, cont: 1_000_000_000), seq: 1)
        let second = FocusFixtures.event(.shieldVerified, at: FocusFixtures.stamp(base.addingTimeInterval(3600), cont: 3_601_000_000_000), seq: 2)
        // After a restart the clock reads a day earlier.
        let rebooted = FocusFixtures.event(.shieldVerified,
                                           at: FocusFixtures.stamp(base.addingTimeInterval(-86400), cont: 5_000_000_000, boot: "b2"), seq: 3)
        let placed = FocusLedger([first, second, rebooted]).placed()
        #expect(placed.last?.placed == base.addingTimeInterval(3600))
    }

    @Test("Boots are ordered by the app's own sequence numbers, not by what the clock said")
    func bootOrderBySeq() {
        // Boot b2 really came second (seq 3), though its clock was set to the day before.
        let a = FocusFixtures.event(.sessionStarted(FocusFixtures.plan()), at: FocusFixtures.stamp(base, cont: 1_000_000_000, boot: "b1"), seq: 1)
        let b = FocusFixtures.event(.shieldApplied, at: FocusFixtures.stamp(base.addingTimeInterval(10), cont: 11_000_000_000, boot: "b1"), seq: 2)
        let c = FocusFixtures.event(.shieldVerified, at: FocusFixtures.stamp(base.addingTimeInterval(-86400), cont: 5_000_000_000, boot: "b2"), seq: 3)
        let ledger = FocusLedger([c, b, a])
        #expect(ledger.events.map(\.seq) == [1, 2, 3])
        #expect(ledger.placed().last?.placed == base.addingTimeInterval(10))
    }

    @Test("Within one boot and instant, the writer and sequence break ties")
    func ties() {
        let stamp = FocusFixtures.stamp(base, cont: 7)
        let monitor = FocusFixtures.event(.shieldVerified, at: stamp, seq: 1, writer: .monitor)
        let app = FocusFixtures.event(.shieldVerified, at: stamp, seq: 5)
        #expect(FocusLedger([monitor, app]).events.map(\.writer) == [.app, .monitor])
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -only-testing:MapleCoreTests/FocusLedgerTests > "$WS/test.log" 2>&1; grep -E "error:" "$WS/test.log" | head -5`
Expected: `error: cannot find 'FocusLedger' in scope`

- [ ] **Step 3: Write the ledger**

`MapleKit/Sources/MapleFocusCore/FocusLedger.swift`:
```swift
import Foundation

/// An event and where it falls on trusted time (F1 design §3.2).
public struct PlacedEvent: Sendable, Hashable {
    public let event: FocusEvent
    /// Its boot's anchor plus the continuous time elapsed since.
    public let placed: Date

    public init(event: FocusEvent, placed: Date) {
        self.event = event
        self.placed = placed
    }
}

/// Every focus event, merged by id and put in order (F1 design §3.2). Pure and deterministic: merging in any order,
/// any number of times, gives the same ledger.
public struct FocusLedger: Sendable, Equatable {
    public private(set) var events: [FocusEvent]

    public init(_ events: [FocusEvent] = []) {
        self.events = []
        merge(events)
    }

    /// Adds events, keeping one per id. When two differ under one id (a derived id written by two processes), the
    /// one that sorts first by writer, continuous time and sequence wins, whatever order they arrive in.
    public mutating func merge(_ more: [FocusEvent]) {
        var byID: [String: FocusEvent] = Dictionary(minimumCapacity: events.count + more.count)
        for event in events + more {
            if let kept = byID[event.id], !Self.prefers(event, over: kept) { continue }
            byID[event.id] = event
        }
        events = Self.ordered(Array(byID.values))
    }

    /// The events on trusted time, in ledger order. Within a boot each is placed at the boot's first wall time plus
    /// the continuous time since, so a clock change inside a boot moves nothing; a boot's anchor is never earlier
    /// than the last placed event of the boot before it on the same device.
    public func placed() -> [PlacedEvent] {
        var result: [PlacedEvent] = []
        result.reserveCapacity(events.count)
        var lastPlaced: [UUID: Date] = [:]
        var anchorKey: BootKey?
        var anchorWall = Date.distantPast
        var anchorStamp: EventStamp?
        for event in events {
            let key = BootKey(device: event.deviceID, boot: event.stamp.boot)
            if key != anchorKey {
                anchorKey = key
                anchorWall = max(event.stamp.wall, lastPlaced[event.deviceID] ?? .distantPast)
                anchorStamp = event.stamp
            }
            let since = anchorStamp.map { event.stamp.seconds(since: $0) } ?? 0
            let placed = anchorWall.addingTimeInterval(since)
            lastPlaced[event.deviceID] = max(lastPlaced[event.deviceID] ?? .distantPast, placed)
            result.append(PlacedEvent(event: event, placed: placed))
        }
        return result
    }

    // MARK: Order

    struct BootKey: Hashable {
        let device: UUID
        let boot: String
    }

    static func prefers(_ a: FocusEvent, over b: FocusEvent) -> Bool {
        if a.writer != b.writer { return a.writer < b.writer }
        if a.stamp.continuous != b.stamp.continuous { return a.stamp.continuous < b.stamp.continuous }
        if a.seq != b.seq { return a.seq < b.seq }
        if a.stamp.wall != b.stamp.wall { return a.stamp.wall < b.stamp.wall }
        if a.stamp.boot != b.stamp.boot { return a.stamp.boot < b.stamp.boot }
        return a.kind.type < b.kind.type
    }

    /// Each device's boots in order: by the app writer's first sequence number in the boot (its true append order),
    /// then by the boot's first wall time. Boots only extensions saw sort after the app's (F1-paid revisits this).
    static func bootRanks(_ events: [FocusEvent]) -> [BootKey: Int] {
        var firstAppSeq: [BootKey: Int] = [:]
        var firstWall: [BootKey: Date] = [:]
        for event in events {
            let key = BootKey(device: event.deviceID, boot: event.stamp.boot)
            if event.writer == .app { firstAppSeq[key] = min(firstAppSeq[key] ?? .max, event.seq) }
            firstWall[key] = min(firstWall[key] ?? .distantFuture, event.stamp.wall)
        }
        let keys = firstWall.keys.sorted { a, b in
            let sa = firstAppSeq[a] ?? .max, sb = firstAppSeq[b] ?? .max
            if sa != sb { return sa < sb }
            let wa = firstWall[a] ?? .distantFuture, wb = firstWall[b] ?? .distantFuture
            if wa != wb { return wa < wb }
            return a.boot < b.boot
        }
        return Dictionary(uniqueKeysWithValues: keys.enumerated().map { ($0.element, $0.offset) })
    }

    static func ordered(_ events: [FocusEvent]) -> [FocusEvent] {
        let ranks = bootRanks(events)
        return events.sorted { a, b in
            if a.deviceID != b.deviceID { return a.deviceID.uuidString < b.deviceID.uuidString }
            let ra = ranks[BootKey(device: a.deviceID, boot: a.stamp.boot)] ?? 0
            let rb = ranks[BootKey(device: b.deviceID, boot: b.stamp.boot)] ?? 0
            if ra != rb { return ra < rb }
            if a.stamp.continuous != b.stamp.continuous { return a.stamp.continuous < b.stamp.continuous }
            if a.writer != b.writer { return a.writer < b.writer }
            if a.seq != b.seq { return a.seq < b.seq }
            return a.id < b.id
        }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -only-testing:MapleCoreTests/FocusLedgerTests > "$WS/test.log" 2>&1; tail -3 "$WS/test.log"`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add MapleKit/Sources/MapleFocusCore/FocusLedger.swift MapleKit/Tests/MapleCoreTests/FocusLedgerTests.swift
git commit -m "Focus ledger: order-free merge and same-boot placement on trusted time

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Replaying a session

**Files:**
- Create: `MapleKit/Sources/MapleFocusCore/SessionRecord.swift`
- Modify: `MapleKit/Sources/MapleFocusCore/FocusLedger.swift` (add `sessions()`)
- Create: `MapleKit/Tests/MapleCoreTests/SessionScript.swift` (a test helper that writes a session with a manual clock)
- Test: `MapleKit/Tests/MapleCoreTests/SessionRecordTests.swift`

**Interfaces:**
- Consumes: `FocusLedger.placed()`, `PlacedEvent`, `FocusPlan`, `ManualFocusTime`.
- Produces:
  - `SessionRecord`: `id`, `plan`, `source`, `started`, `events`, `applied`, `end`, `endReason`, `endVerified`, `reflection`, `isHidden`, `lostAt`, `lastCheckpoint`, `provenIntervals`, `overrides`, `breaks`, `countdownStart`, `plannedEnd`, `isEnded`, `breakEnd(at:) -> Date?` and `breakUsed`;
  - `SessionRecord.Break` (`start`, `plannedEnd`, `end`);
  - `FocusLedger.sessions() -> [SessionRecord]`;
  - tests: `SessionScript(start:session:plan:source:)`, with `write(_:writer:id:)`, `after(_:_:)`, `time`, `events`, `ledger` and `record`.

- [ ] **Step 1: Write the test helper and the failing tests**

`MapleKit/Tests/MapleCoreTests/SessionScript.swift`:
```swift
import Foundation
@testable import MapleCore

/// Writes one session's events with a manual clock, as the app would: `after(60, .shieldVerified)` advances the
/// clocks a minute and writes a read-back.
final class SessionScript {
    let time: ManualFocusTime
    let session: UUID
    let source: FocusSource
    private(set) var events: [FocusEvent] = []
    private var seq: Int

    init(start: Date, session: UUID = FocusFixtures.session, plan: FocusPlan = FocusFixtures.plan(), source: FocusSource = .live,
         time: ManualFocusTime? = nil, firstSeq: Int = 0) {
        self.time = time ?? ManualFocusTime(wall: start)
        self.session = session
        self.source = source
        seq = firstSeq
        if time != nil { self.time.setWall(start) }
        write(.sessionStarted(plan))
    }

    func write(_ kind: FocusEventKind, writer: FocusWriter = .app, id: String? = nil) {
        seq += 1
        events.append(FocusEvent(id: id ?? "\(session.uuidString.prefix(8))-\(seq)", kind: kind, sessionID: session,
                                 deviceID: FocusFixtures.device, writer: writer, seq: seq, source: source, stamp: time.stamp()))
    }

    func after(_ seconds: TimeInterval, _ kind: FocusEventKind) {
        time.advance(seconds)
        write(kind)
    }

    var ledger: FocusLedger { FocusLedger(events) }
    var record: SessionRecord? { ledger.sessions().first }
}
```

`MapleKit/Tests/MapleCoreTests/SessionRecordTests.swift`:
```swift
import Foundation
import Testing
@testable import MapleCore

@Suite("Session replay")
struct SessionRecordTests {
    private let start = at(2026, 10, 23, 14)

    /// Started at 14:00, with the block confirmed 5 seconds later.
    private func confirmed(plan: FocusPlan = FocusFixtures.plan()) -> SessionScript {
        let script = SessionScript(start: start, plan: plan)
        script.after(5, .shieldApplied)
        return script
    }

    @Test("Credit runs from the confirmed block to the last checkpoint, and the countdown starts at the block")
    func provenToEnd() throws {
        let script = confirmed()
        script.after(20 * 60, .shieldVerified)
        script.after(30 * 60, .sessionEnded(.completed, verified: true))
        let record = try #require(script.record)
        let applied = start.addingTimeInterval(5)
        #expect(record.countdownStart == applied)
        #expect(record.plannedEnd == applied.addingTimeInterval(3000))
        #expect(record.provenIntervals == [DateInterval(start: applied, end: applied.addingTimeInterval(3000))])
        #expect(record.endReason == .completed)
        #expect(record.endVerified)
        #expect(record.lastCheckpoint == applied.addingTimeInterval(3000))
    }

    @Test("A killed app reopened after the end credits up to the planned end")
    func reopenedLate() throws {
        let script = confirmed()
        script.after(2 * 3600, .shieldVerified)
        script.write(.sessionEnded(.completed, verified: true))
        let record = try #require(script.record)
        let applied = start.addingTimeInterval(5)
        #expect(record.provenIntervals == [DateInterval(start: applied, duration: 3000)])
    }

    @Test("Credit never crosses a boot: after a restart it starts again at the first read-back")
    func reboot() throws {
        let script = confirmed()
        script.after(10 * 60, .shieldVerified)                       // 14:10:05
        script.time.reboot("b2", wall: start.addingTimeInterval(12 * 60))
        script.after(60, .shieldVerified)                            // 14:13:00 in the new boot
        script.time.advance(37 * 60 + 5)                             // 14:50:05, the planned end
        script.write(.sessionEnded(.completed, verified: true))
        let record = try #require(script.record)
        let applied = start.addingTimeInterval(5)
        #expect(record.provenIntervals == [
            DateInterval(start: applied, end: applied.addingTimeInterval(600)),
            DateInterval(start: start.addingTimeInterval(13 * 60), end: applied.addingTimeInterval(3000)),
        ])
    }

    @Test("A failed read-back stops credit at the checkpoint before it")
    func lost() throws {
        let script = confirmed()
        script.after(10 * 60, .shieldVerified)
        script.after(10 * 60, .shieldLost)
        script.after(10 * 60, .shieldVerified)
        script.after(20 * 60, .sessionEnded(.completed, verified: true))
        let record = try #require(script.record)
        let applied = start.addingTimeInterval(5)
        #expect(record.provenIntervals == [DateInterval(start: applied, duration: 600)])
        #expect(record.lastCheckpoint == applied.addingTimeInterval(600))
        #expect(record.lostAt == applied.addingTimeInterval(1200))
        #expect(record.endReason == .completed)
        #expect(record.isEnded)
    }

    @Test("An event this build doesn't know, that affects credit, stops credit the same way")
    func unknownStops() throws {
        let script = confirmed()
        script.after(10 * 60, .shieldVerified)
        script.after(5 * 60, .unknown("phoneBreakStarted"))
        script.after(35 * 60, .sessionEnded(.completed, verified: true))
        let record = try #require(script.record)
        #expect(record.provenIntervals.map(\.duration) == [600])
    }

    @Test("Overrides are kept as whole windows")
    func overrides() throws {
        let script = confirmed()
        script.after(10 * 60, .overrideStarted(seconds: 60))
        script.after(2 * 60, .overrideEnded)
        script.after(38 * 60, .sessionEnded(.completed, verified: true))
        let record = try #require(script.record)
        let applied = start.addingTimeInterval(5)
        #expect(record.overrides == [DateInterval(start: applied.addingTimeInterval(600), duration: 120)])
        #expect(record.provenIntervals == [DateInterval(start: applied, duration: 3000)])
    }

    @Test("A break never moves the end, and a late break stops at it (F1-11)")
    func breakInside() throws {
        let script = confirmed()
        script.after(47 * 60, .breakStarted(seconds: 300))
        let record = try #require(script.record)
        let applied = start.addingTimeInterval(5)
        #expect(record.plannedEnd == applied.addingTimeInterval(3000))
        #expect(record.breakEnd(at: applied.addingTimeInterval(47 * 60 + 30)) == applied.addingTimeInterval(3000))
        #expect(record.breakUsed)
        script.after(60, .breakEnded)
        #expect(script.record?.breakEnd(at: applied.addingTimeInterval(48 * 60 + 30)) == nil)
    }

    @Test("Only the first end counts")
    func secondTerminal() throws {
        let script = confirmed()
        script.after(10 * 60, .sessionEnded(.endedEarly, verified: true))
        script.after(60, .sessionEnded(.completed, verified: true))
        let record = try #require(script.record)
        #expect(record.endReason == .endedEarly)
        #expect(record.provenIntervals.map(\.duration) == [600])
    }

    @Test("A plain timer has no proof, and its countdown starts at the tap")
    func plainTimer() throws {
        let script = SessionScript(start: start, plan: FocusFixtures.plan(kind: .plainTimer, selection: nil))
        script.after(50 * 60, .sessionEnded(.completed, verified: false))
        let record = try #require(script.record)
        #expect(record.provenIntervals.isEmpty)
        #expect(record.plannedEnd == start.addingTimeInterval(3000))
    }

    @Test("Reflections and hiding are read after the end without changing credit")
    func afterTheEnd() throws {
        let script = confirmed()
        script.after(50 * 60, .sessionEnded(.completed, verified: true))
        script.after(30, .reflected(.partly))
        script.after(30, .sessionHidden)
        let record = try #require(script.record)
        #expect(record.reflection == .partly)
        #expect(record.isHidden)
        #expect(record.provenIntervals.map(\.duration) == [3000])
    }

    @Test("Sessions come back in start order")
    func sessionsInOrder() {
        let a = SessionScript(start: at(2026, 10, 23, 9), session: UUID())
        let b = SessionScript(start: at(2026, 10, 23, 8), session: UUID(), time: ManualFocusTime(wall: at(2026, 10, 23, 8), boot: "b0"))
        let ledger = FocusLedger(a.events + b.events)
        #expect(ledger.sessions().map(\.id) == [b.session, a.session])
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -only-testing:MapleCoreTests/SessionRecordTests > "$WS/test.log" 2>&1; grep -E "error:" "$WS/test.log" | head -5`
Expected: `error: value of type 'FocusLedger' has no member 'sessions'`

- [ ] **Step 3: Write the replay**

`MapleKit/Sources/MapleFocusCore/SessionRecord.swift`:
```swift
import Foundation

/// One session replayed from the ledger (F1 design §3.3, steps 1–5). Pure: everything is worked out once, from the
/// session's placed events.
public struct SessionRecord: Sendable, Equatable, Identifiable {
    /// A locked break: inside the planned length, never moving the end (F1-11).
    public struct Break: Sendable, Equatable {
        public let start: Date
        public let plannedEnd: Date
        public let end: Date?
    }

    public let id: UUID
    public let plan: FocusPlan
    public let source: FocusSource
    /// The `sessionStarted` event.
    public let started: PlacedEvent
    /// The session's events in ledger order, from `sessionStarted` on.
    public let events: [PlacedEvent]
    /// The confirmed block, where credit and the countdown start.
    public let applied: PlacedEvent?
    /// The first terminal event; later ones are ignored.
    public let end: PlacedEvent?
    public let reflection: Reflection?
    public let isHidden: Bool
    /// When proof stopped: a failed read-back, or an event this build doesn't know that can change credit.
    public let lostAt: Date?
    /// The last checkpoint before proof stopped (the receipt's "Couldn't confirm the block after 14:10").
    public let lastCheckpoint: Date?
    /// Proven locked time: per boot, from its first read-back (or the confirmed block) to its last checkpoint, never
    /// past the planned end or the end.
    public let provenIntervals: [DateInterval]
    /// Override windows, each removed whole.
    public let overrides: [DateInterval]
    public let breaks: [Break]

    /// Builds the session from its events; nil without a `sessionStarted`.
    public init?(events placed: [PlacedEvent]) {
        guard let index = placed.firstIndex(where: { if case .sessionStarted = $0.event.kind { true } else { false } }),
              case .sessionStarted(let plan) = placed[index].event.kind
        else { return nil }
        let started = placed[index]
        let events = Array(placed[index...])
        id = started.event.sessionID
        self.plan = plan
        source = started.event.source
        self.started = started
        self.events = events

        var applied: PlacedEvent?
        var end: PlacedEvent?
        var reflection: Reflection?
        var hidden = false
        var lost: Date?
        var lastCheckpoint: Date?
        var intervals: [DateInterval] = []
        var open: (start: Date, last: Date, boot: String)?
        var overrides: [DateInterval] = []
        var overrideStart: Date?
        var breaks: [Break] = []

        for item in events.dropFirst() {
            let kind = item.event.kind
            switch kind {
            case .reflected(let answer):
                reflection = answer
                continue
            case .sessionHidden:
                hidden = true
                continue
            default:
                break
            }
            guard end == nil, item.event.affectsCredit else { continue }
            if lost != nil {
                // Nothing after lost proof counts, but the session can still end.
                if kind.isTerminal { end = item }
                continue
            }
            switch kind {
            case .unknown, .shieldLost:
                lost = item.placed
                continue
            case .overrideStarted:
                overrideStart = overrideStart ?? item.placed
            case .overrideEnded:
                if let from = overrideStart { overrides.append(DateInterval(start: from, end: max(from, item.placed))) }
                overrideStart = nil
            case .breakStarted(let seconds):
                breaks.append(Break(start: item.placed, plannedEnd: item.placed.addingTimeInterval(TimeInterval(seconds)), end: nil))
            case .breakEnded:
                if let last = breaks.last, last.end == nil {
                    breaks[breaks.count - 1] = Break(start: last.start, plannedEnd: last.plannedEnd, end: item.placed)
                }
            default:
                break
            }
            if kind == .shieldApplied, applied == nil {
                applied = item
                open = (item.placed, item.placed, item.event.stamp.boot)
                lastCheckpoint = item.placed
            } else if kind.isCheckpoint, applied != nil {
                if let current = open, current.boot == item.event.stamp.boot {
                    open = (current.start, item.placed, current.boot)
                } else {
                    if let current = open { intervals.append(DateInterval(start: current.start, end: current.last)) }
                    open = (item.placed, item.placed, item.event.stamp.boot)
                }
                lastCheckpoint = item.placed
            }
            if kind.isTerminal { end = item }
        }
        if let current = open { intervals.append(DateInterval(start: current.start, end: current.last)) }

        let countdownStart = applied?.placed ?? started.placed
        let plannedEnd = countdownStart.addingTimeInterval(TimeInterval(plan.plannedSeconds))
        if let from = overrideStart {
            overrides.append(DateInterval(start: from, end: max(from, min(end?.placed ?? plannedEnd, plannedEnd))))
        }
        let limit = min(plannedEnd, end?.placed ?? plannedEnd)
        self.applied = applied
        self.end = end
        self.reflection = reflection
        isHidden = hidden
        lostAt = lost
        self.lastCheckpoint = lastCheckpoint.map { min($0, plannedEnd) }
        provenIntervals = plan.kind == .blocking ? intervals.compactMap { interval in
            let from = max(interval.start, countdownStart), to = min(interval.end, limit)
            return to > from ? DateInterval(start: from, end: to) : nil
        } : []
        self.overrides = overrides
        self.breaks = breaks
    }

    /// Where the countdown runs from: the confirmed block, or the tap for a plain timer.
    public var countdownStart: Date { applied?.placed ?? started.placed }
    /// The countdown start plus the planned length. Breaks never move it (F1-11).
    public var plannedEnd: Date { countdownStart.addingTimeInterval(TimeInterval(plan.plannedSeconds)) }
    public var isEnded: Bool { end != nil }

    public var endReason: EndReason? {
        if case .sessionEnded(let reason, _) = end?.event.kind { return reason }
        return nil
    }

    public var endVerified: Bool {
        if case .sessionEnded(_, let verified) = end?.event.kind { return verified }
        return false
    }

    /// The preset's one break has been taken.
    public var breakUsed: Bool { !breaks.isEmpty }

    /// When the break running at `date` ends (cut short at the planned end); nil when no break is running.
    public func breakEnd(at date: Date) -> Date? {
        guard end == nil, let last = breaks.last, last.end == nil else { return nil }
        let until = min(last.plannedEnd, plannedEnd)
        return date < until ? until : nil
    }
}
```

Add to `FocusLedger` (in `FocusLedger.swift`, after `placed()`):
```swift
    /// Every session in the ledger, in start order (F1 design §3.3).
    public func sessions() -> [SessionRecord] {
        var grouped: [UUID: [PlacedEvent]] = [:]
        for item in placed() { grouped[item.event.sessionID, default: []].append(item) }
        return grouped.values.compactMap { SessionRecord(events: $0) }
            .sorted { ($0.started.placed, $0.id.uuidString) < ($1.started.placed, $1.id.uuidString) }
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -only-testing:MapleCoreTests/SessionRecordTests -only-testing:MapleCoreTests/FocusLedgerTests > "$WS/test.log" 2>&1; tail -3 "$WS/test.log"`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add MapleKit/Sources/MapleFocusCore MapleKit/Tests/MapleCoreTests/SessionScript.swift MapleKit/Tests/MapleCoreTests/SessionRecordTests.swift
git commit -m "Session replay: proven intervals per boot, checkpoints, overrides and breaks

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Blocking types and the reconciler

**Files:**
- Create: `MapleKit/Sources/MapleFocusCore/Blocking.swift`
- Test: `MapleKit/Tests/MapleCoreTests/ShieldReconcilerTests.swift`

**Interfaces:**
- Consumes: `SessionRecord` (Task 6).
- Produces:
  - `MapleTier` (`.free`, `.paid`);
  - `BlockingCapability` (`.unavailableInBuild`, `.preview`, `.screenTime`), with `canBlock`;
  - `BlockingProbe` (`.allowed`, `.notDetermined`, `.declined`, `.restricted`, `.noPasscode`, `.unavailable`), with `isAllowed`;
  - `ShieldOp` (`.apply(session:)`, `.verify(session:)`, `.clear(session:)`, `.clearAll`);
  - `ShieldStoreState` (`.unknown`, `.empty`, `.applied(session:)`);
  - `ShieldReconciler.ops(running:store:now:) -> [ShieldOp]` and `ShieldReconciler.applying(_:to:) -> ShieldStoreState`.

- [ ] **Step 1: Write the failing tests**

`MapleKit/Tests/MapleCoreTests/ShieldReconcilerTests.swift`:
```swift
import Foundation
import Testing
@testable import MapleCore

@Suite("Shield reconciler")
struct ShieldReconcilerTests {
    private let start = at(2026, 10, 23, 14)

    private func running() throws -> SessionRecord {
        let script = SessionScript(start: start)
        script.after(5, .shieldApplied)
        return try #require(script.record)
    }

    @Test("An unknown store state never leads to an action")
    func unknown() throws {
        #expect(ShieldReconciler.ops(running: try running(), store: .unknown, now: start.addingTimeInterval(60)).isEmpty)
        #expect(ShieldReconciler.ops(running: nil, store: .unknown, now: start).isEmpty)
    }

    @Test("A running session's shields stay as they are")
    func steady() throws {
        let session = try running()
        #expect(ShieldReconciler.ops(running: session, store: .applied(session: session.id), now: start.addingTimeInterval(60)).isEmpty)
    }

    @Test("Missing shields for a running session are applied again")
    func reapply() throws {
        let session = try running()
        #expect(ShieldReconciler.ops(running: session, store: .empty, now: start.addingTimeInterval(60)) == [.apply(session: session.id)])
    }

    @Test("Past the planned end, the session's shields are cleared")
    func expired() throws {
        let session = try running()
        #expect(ShieldReconciler.ops(running: session, store: .applied(session: session.id), now: start.addingTimeInterval(3006))
            == [.clear(session: session.id)])
    }

    @Test("Shields with no running session are cleared")
    func orphan() {
        let stray = UUID()
        #expect(ShieldReconciler.ops(running: nil, store: .applied(session: stray), now: start) == [.clear(session: stray)])
    }

    @Test("A plain timer never wants shields")
    func plain() throws {
        let script = SessionScript(start: start, plan: FocusFixtures.plan(kind: .plainTimer, selection: nil))
        let session = try #require(script.record)
        #expect(ShieldReconciler.ops(running: session, store: .empty, now: start.addingTimeInterval(60)).isEmpty)
    }

    @Test("Applying the answer and asking again gives nothing")
    func idempotent() throws {
        let session = try running()
        for store in [ShieldStoreState.empty, .applied(session: session.id), .applied(session: UUID())] {
            for now in [start.addingTimeInterval(60), start.addingTimeInterval(4000)] {
                let after = ShieldReconciler.applying(ShieldReconciler.ops(running: session, store: store, now: now), to: store)
                #expect(ShieldReconciler.ops(running: session, store: after, now: now).isEmpty)
            }
        }
    }

    @Test("Capabilities and probes")
    func capability() {
        #expect(!BlockingCapability.unavailableInBuild.canBlock)
        #expect(BlockingCapability.preview.canBlock)
        #expect(BlockingProbe.allowed.isAllowed)
        #expect(!BlockingProbe.restricted.isAllowed)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -only-testing:MapleCoreTests/ShieldReconcilerTests > "$WS/test.log" 2>&1; grep -E "error:" "$WS/test.log" | head -5`
Expected: `error: cannot find 'ShieldReconciler' in scope`

- [ ] **Step 3: Write the types**

`MapleKit/Sources/MapleFocusCore/Blocking.swift`:
```swift
import Foundation

/// The build's tier, from the `MapleTier` Info.plist key (F1 design §7.4).
public enum MapleTier: String, Sendable, Codable {
    case free, paid
}

/// What this build can do about blocking, apart from whether the member allowed it (F1 design §7.1).
public enum BlockingCapability: String, Sendable, Codable {
    /// Free builds have no Screen Time entitlement.
    case unavailableInBuild
    /// DEBUG's preview blocker.
    case preview
    /// Screen Time (F1-paid).
    case screenTime

    public var canBlock: Bool { self != .unavailableInBuild }
}

/// What a Screen Time probe found; each state has its own Needs Screen Time copy (F1 design §5.3).
public enum BlockingProbe: String, Sendable, Codable, CaseIterable {
    case allowed, notDetermined, declined
    /// A parent manages Screen Time on this iPhone.
    case restricted
    case noPasscode
    /// This build can't block.
    case unavailable

    public var isAllowed: Bool { self == .allowed }
}

/// One thing to do to the shields.
public enum ShieldOp: Sendable, Hashable {
    case apply(session: UUID)
    case verify(session: UUID)
    case clear(session: UUID)
    case clearAll
}

/// What the shield store holds, as read back.
public enum ShieldStoreState: Sendable, Hashable {
    /// It couldn't be read: nothing is done.
    case unknown
    case empty
    case applied(session: UUID)
}

/// What to do so the shields match the ledger (focus spec §9.4). Pure: it takes no action on an unknown state, and
/// asking again after applying its answer gives nothing.
public enum ShieldReconciler {
    public static func ops(running: SessionRecord?, store: ShieldStoreState, now: Date) -> [ShieldOp] {
        let wanted: UUID? = running.flatMap { session in
            session.end == nil && session.plan.kind == .blocking && session.lostAt == nil && now < session.plannedEnd
                ? session.id : nil
        }
        switch store {
        case .unknown:
            return []
        case .empty:
            return wanted.map { [.apply(session: $0)] } ?? []
        case .applied(let session):
            if session == wanted { return [] }
            return [.clear(session: session)] + (wanted.map { [.apply(session: $0)] } ?? [])
        }
    }

    /// The store after `ops`, for tests and the preview blocker.
    public static func applying(_ ops: [ShieldOp], to store: ShieldStoreState) -> ShieldStoreState {
        ops.reduce(store) { state, op in
            switch op {
            case .apply(let session): .applied(session: session)
            case .verify: state
            case .clear(let session): state == .applied(session: session) ? .empty : state
            case .clearAll: .empty
            }
        }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -only-testing:MapleCoreTests/ShieldReconcilerTests > "$WS/test.log" 2>&1; tail -3 "$WS/test.log"`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add MapleKit/Sources/MapleFocusCore/Blocking.swift MapleKit/Tests/MapleCoreTests/ShieldReconcilerTests.swift
git commit -m "Blocking capability, probes and the pure shield reconciler

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Ledger files, stores and the writer

**Files:**
- Create: `MapleKit/Sources/MapleStorage/JSONLinesFile.swift`
- Create: `MapleKit/Sources/MapleStorage/FocusLedgerStore.swift`
- Create: `MapleKit/Sources/MapleStorage/LedgerWriter.swift`
- Create: `MapleKit/Sources/MapleStorage/DeviceIdentity.swift`
- Test: `MapleKit/Tests/MapleServicesTests/LedgerStorageTests.swift`

**Interfaces:**
- Consumes: `FocusEvent`, `FocusWriter`, `FocusSource`, `FocusTimeSource`, `ManualFocusTime`.
- Produces:
  - `LinesRead<Value>` (`.lines([Value], damaged: Int)`, `.unavailable`);
  - `JSONLinesFile(url:)`, with `append(_:) throws`, `read(_:) -> LinesRead<Value>` and `last(_:) -> Value?`;
  - `protocol FocusLedgerStore: Sendable`, with `append(_:) throws`, `readOpen(now:) -> [FocusEvent]?`, `readAll() -> [FocusEvent]?` and `lastSeq(of:) -> Int`;
  - `FileLedgerStore(directory:)`, with the static `fileName(writer:wall:)`;
  - `MemoryLedgerStore(_:)`, with `events`, `failsWrites`, `unreadable` and `WriteFailed`;
  - `LedgerWriter(store:time:deviceID:writer:source:)`, with `write(_:session:id:) throws -> FocusEvent` and `time`;
  - `DeviceIdentity.load(in:) -> UUID?`.

- [ ] **Step 1: Write the failing tests**

`MapleKit/Tests/MapleServicesTests/LedgerStorageTests.swift`:
```swift
import Foundation
import Testing
@testable import MapleCore
@testable import MapleStorage

@Suite("Ledger storage")
struct LedgerStorageTests {
    private let device = UUID(uuidString: "00000000-0000-4000-8000-0000000000D1")!

    private func event(_ seq: Int, wall: Date, writer: FocusWriter = .app, kind: FocusEventKind = .shieldVerified) -> FocusEvent {
        FocusEvent(id: "e\(seq)-\(writer.rawValue)", kind: kind, sessionID: device, deviceID: device, writer: writer, seq: seq,
                   source: .live, stamp: EventStamp(wall: wall, continuous: UInt64(seq) * 1_000_000_000, boot: "b1", zone: "UTC"))
    }

    @Test("Appended lines read back in order")
    func appendRead() throws {
        let file = JSONLinesFile(url: try temporaryDirectory().appending(path: "lines.jsonl"))
        try file.append(event(1, wall: at(2026, 10, 23, 9)))
        try file.append(event(2, wall: at(2026, 10, 23, 10)))
        guard case .lines(let values, let damaged) = file.read(FocusEvent.self) else { Issue.record("unreadable"); return }
        #expect(values.map(\.seq) == [1, 2])
        #expect(damaged == 0)
        #expect(file.last(FocusEvent.self)?.seq == 2)
    }

    @Test("A torn tail is skipped, and the next append still decodes")
    func tornTail() throws {
        let url = try temporaryDirectory().appending(path: "lines.jsonl")
        let file = JSONLinesFile(url: url)
        try file.append(event(1, wall: at(2026, 10, 23, 9)))
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"id\":\"half".utf8))
        try handle.close()
        try file.append(event(2, wall: at(2026, 10, 23, 10)))
        guard case .lines(let values, let damaged) = file.read(FocusEvent.self) else { Issue.record("unreadable"); return }
        #expect(values.map(\.seq) == [1, 2])
        #expect(damaged == 1)
    }

    @Test("A missing file reads as empty")
    func missing() throws {
        let file = JSONLinesFile(url: try temporaryDirectory().appending(path: "none.jsonl"))
        guard case .lines(let values, _) = file.read(FocusEvent.self) else { Issue.record("unreadable"); return }
        #expect(values.isEmpty)
    }

    @Test("One file per writer per month, by the event's wall time in UTC")
    func fileNames() throws {
        #expect(FileLedgerStore.fileName(writer: .app, wall: at(2026, 10, 23, 9)) == "ledger-app-2026-10.jsonl")
        #expect(FileLedgerStore.fileName(writer: .shieldAction, wall: at(2026, 2, 1)) == "ledger-shieldAction-2026-02.jsonl")
        let folder = try temporaryDirectory()
        let store = FileLedgerStore(directory: folder)
        try store.append(event(1, wall: at(2026, 9, 30, 23)))
        try store.append(event(2, wall: at(2026, 10, 1, 1)))
        try store.append(event(1, wall: at(2026, 10, 1, 2), writer: .monitor))
        #expect(Set(files(in: folder)) == ["ledger-app-2026-09.jsonl", "ledger-app-2026-10.jsonl", "ledger-monitor-2026-10.jsonl"])
        #expect(store.readAll()?.count == 3)
    }

    @Test("Reading the open ledger takes this month and last, skips old files, and finds a recent file under an old name")
    func openFiles() throws {
        let folder = try temporaryDirectory()
        let store = FileLedgerStore(directory: folder)
        try store.append(event(1, wall: at(2026, 6, 10)))       // an old month, written long ago
        try store.append(event(2, wall: at(2026, 9, 20)))       // last month
        try store.append(event(3, wall: at(2026, 10, 22)))      // this month
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-100 * 86400)],
                                              ofItemAtPath: folder.appending(path: "ledger-app-2026-06.jsonl").path)
        // The clock was set back to August before this append: it lands in August's file.
        try store.append(event(4, wall: at(2026, 8, 3)))
        let open = try #require(store.readOpen(now: at(2026, 10, 23)))
        #expect(Set(open.map(\.seq)) == [2, 3, 4])
    }

    @Test("The next sequence number carries on after the highest across every month")
    func lastSeq() throws {
        let store = FileLedgerStore(directory: try temporaryDirectory())
        try store.append(event(41, wall: at(2026, 10, 2)))
        try store.append(event(42, wall: at(2026, 8, 2)))        // a clock set back
        try store.append(event(7, wall: at(2026, 10, 2), writer: .monitor))
        #expect(store.lastSeq(of: .app) == 42)
        #expect(store.lastSeq(of: .monitor) == 7)
        #expect(store.lastSeq(of: .shieldAction) == 0)
    }

    @Test("The writer stamps and numbers events, and records nothing when a write fails")
    func writer() throws {
        let store = MemoryLedgerStore([event(9, wall: at(2026, 10, 23, 9))])
        let time = ManualFocusTime(wall: at(2026, 10, 23, 14))
        let writer = LedgerWriter(store: store, time: time, deviceID: device, writer: .app, source: .preview)
        let first = try writer.write(.shieldVerified, session: device)
        #expect(first.seq == 10)
        #expect(first.source == .preview)
        #expect(first.stamp.wall == at(2026, 10, 23, 14))
        store.failsWrites = true
        #expect(throws: MemoryLedgerStore.WriteFailed.self) { try writer.write(.shieldVerified, session: device) }
        store.failsWrites = false
        #expect(try writer.write(.shieldVerified, session: device).seq == 11)
        #expect(store.events.map(\.seq) == [9, 10, 11])
    }

    @Test("An unreadable memory store reads as nil")
    func unreadable() {
        let store = MemoryLedgerStore()
        store.unreadable = true
        #expect(store.readOpen(now: .now) == nil)
        #expect(store.readAll() == nil)
    }

    @Test("The device id is made once and kept")
    func deviceIdentity() throws {
        let folder = try temporaryDirectory()
        let first = try #require(DeviceIdentity.load(in: folder))
        #expect(DeviceIdentity.load(in: folder) == first)
        #expect(files(in: folder).contains(DeviceIdentity.file))
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -only-testing:MapleServicesTests/LedgerStorageTests > "$WS/test.log" 2>&1; grep -E "error:" "$WS/test.log" | head -5`
Expected: `error: cannot find 'JSONLinesFile' in scope`

- [ ] **Step 3: Write the storage types**

`MapleKit/Sources/MapleStorage/JSONLinesFile.swift`:
```swift
import Foundation

/// What reading a JSON-lines file found.
public enum LinesRead<Value> {
    /// The lines that decoded, in file order, and how many didn't.
    case lines([Value], damaged: Int)
    /// The file is there but can't be read now (before the first unlock after a restart).
    case unavailable
}

/// One append-only file of JSON lines (F1 design §7.3). Appends never rewrite earlier lines, and reading skips lines
/// that don't decode (a torn tail after a crash) instead of setting the file aside.
public struct JSONLinesFile: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// Appends `value` as one line, protected until first unlock. If the file doesn't end in a newline (a torn
    /// append), this line starts on a fresh one so it still decodes.
    public func append<Value: Encodable>(_ value: Value) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var line = try encoder.encode(value)
        line.append(0x0A)
        let manager = FileManager.default
        if !manager.fileExists(atPath: url.path) {
            try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            #if os(iOS)
            let attributes: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            #else
            let attributes: [FileAttributeKey: Any] = [:]
            #endif
            guard manager.createFile(atPath: url.path, contents: nil, attributes: attributes) else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
            }
        }
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        let end = try handle.seekToEnd()
        if end > 0 {
            try handle.seek(toOffset: end - 1)
            if try handle.read(upToCount: 1) != Data([0x0A]) { line.insert(0x0A, at: line.startIndex) }
            try handle.seekToEnd()
        }
        try handle.write(contentsOf: line)
    }

    /// Every line that decodes as `Value`, in order. A missing file is empty.
    public func read<Value: Decodable>(_ type: Value.Type) -> LinesRead<Value> {
        guard FileManager.default.fileExists(atPath: url.path) else { return .lines([], damaged: 0) }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return .unavailable
        }
        let decoder = JSONDecoder()
        var values: [Value] = []
        var damaged = 0
        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            if let value = try? decoder.decode(Value.self, from: Data(line)) {
                values.append(value)
            } else {
                damaged += 1
            }
        }
        return .lines(values, damaged: damaged)
    }

    /// The last line that decodes, or nil.
    public func last<Value: Decodable>(_ type: Value.Type) -> Value? {
        guard case .lines(let values, _) = read(type) else { return nil }
        return values.last
    }
}
```

`MapleKit/Sources/MapleStorage/FocusLedgerStore.swift`:
```swift
import Foundation
import MapleFocusCore
import Synchronization

/// Where focus events live (F1 design §7.3).
public protocol FocusLedgerStore: Sendable {
    /// Appends one event to its writer's file. Throws when it can't be written; the caller then acts on nothing.
    func append(_ event: FocusEvent) throws
    /// The events that can still change an open day: this month's and last month's files, plus any file changed in
    /// the last 40 days (a clock set back writes into an older month's file). Nil when a file can't be read now.
    func readOpen(now: Date) -> [FocusEvent]?
    /// Every event, for a full rebuild. Nil when a file can't be read now.
    func readAll() -> [FocusEvent]?
    /// The highest sequence number `writer` has written, so a new writer carries on after it.
    func lastSeq(of writer: FocusWriter) -> Int
}

/// The ledger as files in the container: one per writer per month ("ledger-app-2026-10.jsonl"), so each process
/// appends only to its own files and a replay of the open days reads only the last two months.
public struct FileLedgerStore: FocusLedgerStore {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static func fileName(writer: FocusWriter, wall: Date) -> String {
        "ledger-\(writer.rawValue)-\(month(of: wall)).jsonl"
    }

    public func append(_ event: FocusEvent) throws {
        try JSONLinesFile(url: directory.appending(path: Self.fileName(writer: event.writer, wall: event.stamp.wall))).append(event)
    }

    public func readOpen(now: Date) -> [FocusEvent]? {
        let previous = Self.utc.date(byAdding: .month, value: -1, to: now) ?? now
        let months = [Self.month(of: now), Self.month(of: previous)]
        let recent = now.addingTimeInterval(-40 * 86400)
        let open = files().filter { url in
            if months.contains(where: { url.lastPathComponent.hasSuffix("-\($0).jsonl") }) { return true }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return (modified ?? .distantPast) >= recent
        }
        return read(open)
    }

    public func readAll() -> [FocusEvent]? {
        read(files())
    }

    public func lastSeq(of writer: FocusWriter) -> Int {
        files()
            .filter { $0.lastPathComponent.hasPrefix("ledger-\(writer.rawValue)-") }
            .compactMap { JSONLinesFile(url: $0).last(FocusEvent.self)?.seq }
            .max() ?? 0
    }

    // MARK: Private

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    static func month(of date: Date) -> String {
        let parts = utc.dateComponents([.year, .month], from: date)
        let month = parts.month ?? 1
        return "\(parts.year ?? 1970)-" + (month < 10 ? "0" : "") + "\(month)"
    }

    private func files() -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasPrefix("ledger-") && $0.hasSuffix(".jsonl") }.sorted().map { directory.appending(path: $0) }
    }

    private func read(_ urls: [URL]) -> [FocusEvent]? {
        var events: [FocusEvent] = []
        for url in urls {
            switch JSONLinesFile(url: url).read(FocusEvent.self) {
            case .lines(let values, _): events += values
            case .unavailable: return nil
            }
        }
        return events
    }
}

/// The ledger in memory: demo launches and tests. Writes can be made to fail, and reads to find the ledger
/// unreadable, to test the store's unknown state.
public final class MemoryLedgerStore: FocusLedgerStore {
    public struct WriteFailed: Error {}

    private struct State {
        var events: [FocusEvent]
        var failsWrites = false
        var unreadable = false
    }

    private let state: Mutex<State>

    public init(_ events: [FocusEvent] = []) {
        state = Mutex(State(events: events))
    }

    public func append(_ event: FocusEvent) throws {
        try state.withLock { state in
            if state.failsWrites { throw WriteFailed() }
            state.events.append(event)
        }
    }

    public func readOpen(now: Date) -> [FocusEvent]? {
        state.withLock { $0.unreadable ? nil : $0.events }
    }

    public func readAll() -> [FocusEvent]? {
        state.withLock { $0.unreadable ? nil : $0.events }
    }

    public func lastSeq(of writer: FocusWriter) -> Int {
        state.withLock { $0.events.filter { $0.writer == writer }.map(\.seq).max() ?? 0 }
    }

    public var events: [FocusEvent] {
        state.withLock { $0.events }
    }

    public var failsWrites: Bool {
        get { state.withLock { $0.failsWrites } }
        set { state.withLock { $0.failsWrites = newValue } }
    }

    public var unreadable: Bool {
        get { state.withLock { $0.unreadable } }
        set { state.withLock { $0.unreadable = newValue } }
    }
}
```

`MapleKit/Sources/MapleStorage/LedgerWriter.swift`:
```swift
import Foundation
import MapleFocusCore
import Synchronization

/// Stamps, numbers and appends one process's events (F1 design §3.1). Sequence numbers carry on after the highest
/// this writer has ever written, so they keep the true append order whatever the clock says.
public final class LedgerWriter: Sendable {
    public let deviceID: UUID
    public let writer: FocusWriter
    public let source: FocusSource
    public let time: any FocusTimeSource
    private let store: any FocusLedgerStore
    private let lastSeq: Mutex<Int>

    public init(store: any FocusLedgerStore, time: any FocusTimeSource, deviceID: UUID, writer: FocusWriter, source: FocusSource) {
        self.store = store
        self.time = time
        self.deviceID = deviceID
        self.writer = writer
        self.source = source
        lastSeq = Mutex(store.lastSeq(of: writer))
    }

    /// Writes `kind` for `session`, stamped now. Throws when the store can't write; then nothing is recorded.
    @discardableResult
    public func write(_ kind: FocusEventKind, session: UUID, id: String? = nil) throws -> FocusEvent {
        try lastSeq.withLock { seq in
            let event = FocusEvent(
                id: id ?? UUID().uuidString.lowercased(), kind: kind, sessionID: session, deviceID: deviceID, writer: writer,
                seq: seq + 1, source: source, stamp: time.stamp()
            )
            try store.append(event)
            seq += 1
            return event
        }
    }
}
```

`MapleKit/Sources/MapleStorage/DeviceIdentity.swift`:
```swift
import Foundation

/// This install's device id: a random UUID made once and kept in the container (F1 design §7.8). It never leaves the
/// device in F1 and isn't derived from anything about the phone.
public enum DeviceIdentity {
    public static let file = "device-id.txt"

    /// The kept id, made and saved on first use. Nil when the file is there but can't be read yet.
    public static func load(in directory: URL) -> UUID? {
        let url = directory.appending(path: file)
        if FileManager.default.fileExists(atPath: url.path) {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            if let id = UUID(uuidString: text.trimmingCharacters(in: .whitespacesAndNewlines)) { return id }
        }
        let id = UUID()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            #if os(iOS)
            try Data(id.uuidString.utf8).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try Data(id.uuidString.utf8).write(to: url, options: [.atomic])
            #endif
        } catch {
            return nil
        }
        return id
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -only-testing:MapleServicesTests/LedgerStorageTests > "$WS/test.log" 2>&1; tail -3 "$WS/test.log"`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add MapleKit/Sources/MapleStorage MapleKit/Tests/MapleServicesTests/LedgerStorageTests.swift
git commit -m "Ledger storage: JSON-lines files per writer per month, memory store, writer and device id

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 9: The frozen awake window

**Files:**
- Modify: `MapleKit/Sources/MapleCore/Collection/LocalDay.swift` (add `init?(label:)` and `ordinal`; decode through `init?(label:)`)
- Create: `MapleKit/Sources/MapleCore/Focus/AwakeWindow+Schedule.swift`
- Create: `MapleKit/Sources/MapleCore/Focus/CollectionSnapshot+Focus.swift` (with `focusWindow`; Task 13 adds to it)
- Test: `MapleKit/Tests/MapleCoreTests/AwakeWindowTests.swift`

**Interfaces:**
- Consumes: `AwakeWindow`, `FocusPlan`, `WeeklySleepSchedule.times(forNight:calendar:)`, `NightLedger.schedule(for:current:)`.
- Produces:
  - `LocalDay(label:) -> LocalDay?` and `LocalDay.ordinal: Int` (days since 1970-01-01, with no `Calendar`);
  - `AwakeWindow.minimumSleep` (6 h);
  - `AwakeWindow.window(for:schedule:calendar:) -> AwakeWindow`;
  - `AwakeWindow.frozen(at:schedule:calendar:) -> (day: LocalDay, window: AwakeWindow)`;
  - `FocusPlan.day: LocalDay`;
  - `CollectionSnapshot.focusWindow(at:context:) -> (day: LocalDay, window: AwakeWindow)`.

- [ ] **Step 1: Write the failing tests**

`MapleKit/Tests/MapleCoreTests/AwakeWindowTests.swift`:
```swift
import Foundation
import Testing
@testable import MapleCore

@Suite("Awake window")
struct AwakeWindowTests {
    private let standard: (LocalDay) -> WeeklySleepSchedule = { _ in .standard }
    private let oct23 = LocalDay(year: 2026, month: 10, day: 23)

    @Test("A day's window runs from an hour before last night's wake to tonight's bedtime")
    func standardDay() {
        let window = AwakeWindow.window(for: oct23, schedule: standard, calendar: utc)
        #expect(window.start == at(2026, 10, 23, 6))
        #expect(window.end == at(2026, 10, 23, 23))
        #expect(window.windDown == at(2026, 10, 23, 22, 15))
    }

    @Test("A session belongs to the day whose window holds its start")
    func daytime() {
        let frozen = AwakeWindow.frozen(at: at(2026, 10, 23, 14), schedule: standard, calendar: utc)
        #expect(frozen.day == oct23)
    }

    @Test("A session that starts in the sleep window takes the next day's window, counting from wake − 60")
    func dawn() {
        let frozen = AwakeWindow.frozen(at: at(2026, 10, 23, 5, 30), schedule: standard, calendar: utc)
        #expect(frozen.day == oct23)
        #expect(frozen.window.start == at(2026, 10, 23, 6))
        let late = AwakeWindow.frozen(at: at(2026, 10, 23, 23, 30), schedule: standard, calendar: utc)
        #expect(late.day == LocalDay(year: 2026, month: 10, day: 24))
        #expect(late.window.start == at(2026, 10, 24, 6))
    }

    @Test("A 23:40 start with bed at 01:00 stays on its day, across midnight")
    func lateBed() {
        let late = WeeklySleepSchedule.everyNight(SleepSchedule(bedtime: ClockTime(hour: 1), wake: ClockTime(hour: 9), windDownMinutes: 45))
        let frozen = AwakeWindow.frozen(at: at(2026, 10, 23, 23, 40), schedule: { _ in late }, calendar: utc)
        #expect(frozen.day == oct23)
        #expect(frozen.window.end == at(2026, 10, 24, 1))
    }

    @Test("A sleep window under 6 hours is widened at the wake end")
    func shortNight() {
        let short = WeeklySleepSchedule.everyNight(SleepSchedule(bedtime: ClockTime(hour: 1), wake: ClockTime(hour: 5), windDownMinutes: 30))
        let window = AwakeWindow.window(for: oct23, schedule: { _ in short }, calendar: utc)
        // Last night: bed 01:00, wake 05:00 (4 h) is widened to 07:00, so the day starts at 06:00.
        #expect(window.start == at(2026, 10, 23, 6))
    }

    @Test("Each night uses the schedule that judges it, so an edit after 18:00 leaves tonight alone")
    func pastSchedule() {
        let early = WeeklySleepSchedule.everyNight(SleepSchedule(bedtime: ClockTime(hour: 21), wake: ClockTime(hour: 6), windDownMinutes: 30))
        var snapshot = CollectionSnapshot.empty(profileID: UUID(), createdAt: at(2026, 10, 1))
        snapshot.nights.pastSchedules = [NightLedger.PastSchedule(through: oct23, schedule: .standard)]
        let context = CollectionContext(schedule: early, calendar: utc, hemisphere: .northern)
        let tonight = snapshot.focusWindow(at: at(2026, 10, 23, 20, 30), context: context)
        #expect(tonight.window.end == at(2026, 10, 23, 23))
        let tomorrow = snapshot.focusWindow(at: at(2026, 10, 24, 12), context: context)
        #expect(tomorrow.window.end == at(2026, 10, 24, 21))
    }

    @Test("A weekend night uses the weekend bedtime")
    func weekend() {
        let weekly = WeeklySleepSchedule(weekday: .standard,
                                         weekend: SleepSchedule(bedtime: ClockTime(hour: 0, minute: 30), wake: ClockTime(hour: 9), windDownMinutes: 60))
        // 23 October 2026 is a Friday: its night wakes into Saturday.
        let window = AwakeWindow.window(for: oct23, schedule: { _ in weekly }, calendar: utc)
        #expect(window.end == at(2026, 10, 24, 0, 30))
        #expect(window.start == at(2026, 10, 23, 6))
    }

    @Test("Daylight-saving days: windows keep their local times on 23- and 25-hour days")
    func daylightSaving() {
        var london = Calendar(identifier: .gregorian)
        london.timeZone = TimeZone(identifier: "Europe/London")!
        let spring = AwakeWindow.window(for: LocalDay(year: 2026, month: 3, day: 29), schedule: standard, calendar: london)
        #expect(spring.start == at(2026, 3, 29, 6, in: london))
        #expect(spring.end == at(2026, 3, 29, 23, in: london))
        let autumn = AwakeWindow.window(for: LocalDay(year: 2026, month: 10, day: 25), schedule: standard, calendar: london)
        #expect(autumn.start == at(2026, 10, 25, 6, in: london))
        #expect(autumn.interval.duration == 17 * 3600)
    }

    @Test("Day labels and ordinals")
    func labels() {
        #expect(LocalDay(label: "2026-10-23") == oct23)
        #expect(LocalDay(label: "2026-13-01") == nil)
        #expect(LocalDay(label: "soon") == nil)
        #expect(LocalDay(year: 1970, month: 1, day: 1).ordinal == 0)
        #expect(LocalDay(year: 2026, month: 10, day: 24).ordinal - oct23.ordinal == 1)
        #expect(LocalDay(year: 2028, month: 3, day: 1).ordinal - LocalDay(year: 2028, month: 2, day: 28).ordinal == 2)
        #expect(FocusFixtures.plan().day == oct23)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -only-testing:MapleCoreTests/AwakeWindowTests > "$WS/test.log" 2>&1; grep -E "error:" "$WS/test.log" | head -5`
Expected: `error: type 'AwakeWindow' has no member 'window'`

- [ ] **Step 3: Write the window rules**

In `MapleKit/Sources/MapleCore/Collection/LocalDay.swift`, add after `init(_ date:calendar:)`:
```swift
    /// A "yyyy-MM-dd" day, as `description` writes it; nil when `label` isn't one.
    public init?(label: String) {
        let parts = label.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    /// Days since 1970-01-01 in the proleptic Gregorian calendar, worked out without a `Calendar` (Howard Hinnant's
    /// days_from_civil), so streak arithmetic over years of days stays fast.
    public var ordinal: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }
```
and replace the body of `init(from decoder:)` with:
```swift
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let day = LocalDay(label: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected a yyyy-MM-dd day, got \(text)")
        }
        self = day
```

`MapleKit/Sources/MapleCore/Focus/AwakeWindow+Schedule.swift`:
```swift
import Foundation
import MapleFocusCore

extension AwakeWindow {
    /// The shortest sleep window credit allows (F1 design §3.3 step 6).
    public static let minimumSleep: TimeInterval = 6 * 3600

    /// One Maple day's awake window: from 60 minutes before last night's wake (moved later when that night was under
    /// 6 hours) to tonight's bedtime.
    /// - Parameter schedule: The weekly schedule that judges each night, named by its evening (the one in force at
    ///   18:00 that evening, `NightLedger.schedule(for:current:)`).
    public static func window(for day: LocalDay, schedule: (LocalDay) -> WeeklySleepSchedule, calendar: Calendar) -> AwakeWindow {
        let lastNight = day.adding(days: -1, calendar: calendar)
        let previous = schedule(lastNight).times(forNight: lastNight, calendar: calendar)
        let tonight = schedule(day).times(forNight: day, calendar: calendar)
        let wake = max(previous.wake, previous.bedtime.addingTimeInterval(minimumSleep))
        return AwakeWindow(start: wake.addingTimeInterval(-3600), end: tonight.bedtime, windDown: tonight.windDownStart)
    }

    /// The Maple day and window a session starting at `start` counts in, frozen into its plan: the latest day whose
    /// window holds the start, or, for a start inside a sleep window, the next day's (it counts from wake − 60).
    public static func frozen(at start: Date, schedule: (LocalDay) -> WeeklySleepSchedule, calendar: Calendar) -> (day: LocalDay, window: AwakeWindow) {
        let today = LocalDay(start, calendar: calendar)
        let candidates = (-1...2).map { offset -> (day: LocalDay, window: AwakeWindow) in
            let day = today.adding(days: offset, calendar: calendar)
            return (day, window(for: day, schedule: schedule, calendar: calendar))
        }
        if let holding = candidates.last(where: { $0.window.contains(start) }) { return holding }
        return candidates.first(where: { $0.window.start > start }) ?? candidates[candidates.count - 1]
    }
}

extension FocusPlan {
    /// The Maple day the session counts toward.
    public var day: LocalDay {
        LocalDay(label: mapleDay) ?? LocalDay(window.start, calendar: Calendar(identifier: .gregorian))
    }
}
```

`MapleKit/Sources/MapleCore/Focus/CollectionSnapshot+Focus.swift`:
```swift
import Foundation
import MapleFocusCore

extension CollectionSnapshot {
    /// The Maple day and frozen awake window for a session starting at `start` (F1 design §3.3 step 6). Each night is
    /// judged by the schedule in force at 18:00 that evening, so a bedtime edit after 18:00 applies from the next night.
    public func focusWindow(at start: Date, context: CollectionContext) -> (day: LocalDay, window: AwakeWindow) {
        AwakeWindow.frozen(at: start, schedule: { nights.schedule(for: $0, current: context.schedule) }, calendar: context.calendar)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -only-testing:MapleCoreTests/AwakeWindowTests -only-testing:MapleCoreTests/FoundationModelTests > "$WS/test.log" 2>&1; tail -3 "$WS/test.log"`
Expected: `** TEST SUCCEEDED **` (FoundationModelTests covers `LocalDay`'s coding, which now goes through `init?(label:)`).

- [ ] **Step 5: Commit**

```bash
git add MapleKit/Sources/MapleCore MapleKit/Tests/MapleCoreTests/AwakeWindowTests.swift
git commit -m "Frozen awake windows: wake − 60 to bedtime, 6-hour nights, 18:00 edits and sleep-window starts

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Hours credit

**Files:**
- Create: `MapleKit/Sources/MapleCore/Focus/HoursCredit.swift`
- Create: `MapleKit/Tests/MapleCoreTests/FocusDay.swift` (a test helper that writes a day of sessions on one clock)
- Test: `MapleKit/Tests/MapleCoreTests/HoursCreditTests.swift`

**Interfaces:**
- Consumes: `SessionRecord`, `FocusLedger.sessions()`, `FocusPlan.day`, `ManualFocusTime`.
- Produces:
  - `CreditRule` (`afterBedtime`, `beforeMorning`, `dailyCap`, `override`, `unconfirmed`, `plainTimer`, `notQualifying`, `overlap`);
  - `CreditStretch(_:_:)`, with `interval`, `rule` and `counted`;
  - `SessionCredit`: `id`, `day`, `zone`, `seconds`, `awakeSeconds`, `finished`, `provenAt`, `endedAt`, `dayEnd`, `stretches`;
  - `HoursCredit` constants: `dailyCap` (21,600), `finishedMinimum` (1,200), `finishedShare` (0.75), `finishedPerDay` (3);
  - `HoursCredit.credit(_:crediting:now:) -> [SessionCredit]`;
  - `HoursCredit.provisionalSeconds(for:now:roomLeftToday:) -> Int`;
  - `HoursCredit.subtract(_:_:)`;
  - tests: `FocusDay(_:)`, with `time`, `at(_:)`, `session(minutes:planned:reason:plan:overrides:source:) -> UUID`, `write(_:session:)`, `ledger` and `credits(now:sources:)`.

- [ ] **Step 1: Write the test helper and the failing tests**

`MapleKit/Tests/MapleCoreTests/FocusDay.swift`:
```swift
import Foundation
@testable import MapleCore

/// A day of sessions written on one clock, as the app would write them.
final class FocusDay {
    let time: ManualFocusTime
    private(set) var events: [FocusEvent] = []
    private var seq = 0

    init(_ start: Date) {
        time = ManualFocusTime(wall: start)
    }

    /// Moves the clocks forward to `date`.
    func at(_ date: Date) {
        time.advance(date.timeIntervalSince(time.now))
    }

    func write(_ kind: FocusEventKind, session: UUID, source: FocusSource = .live) {
        seq += 1
        events.append(FocusEvent(id: "\(session.uuidString.prefix(8))-\(seq)", kind: kind, sessionID: session,
                                 deviceID: FocusFixtures.device, writer: .app, seq: seq, source: source, stamp: time.stamp()))
    }

    /// A session from now: the block is confirmed 5 seconds after the tap, overrides happen at the given minutes, and
    /// after `minutes` it ends with a verified `reason` (nil leaves it running).
    @discardableResult
    func session(
        minutes: Int, planned: Int? = nil, reason: EndReason? = .completed, plan: FocusPlan? = nil,
        overrides: [(minute: Int, seconds: Int)] = [], source: FocusSource = .live
    ) -> UUID {
        let id = UUID()
        write(.sessionStarted(plan ?? FocusFixtures.plan(minutes: planned ?? minutes)), session: id, source: source)
        time.advance(5)
        write(.shieldApplied, session: id, source: source)
        var elapsed = 0
        for override in overrides.sorted(by: { $0.minute < $1.minute }) {
            time.advance(TimeInterval(override.minute * 60 - elapsed))
            write(.overrideStarted(seconds: override.seconds), session: id, source: source)
            time.advance(TimeInterval(override.seconds))
            write(.overrideEnded, session: id, source: source)
            elapsed = override.minute * 60 + override.seconds
        }
        time.advance(TimeInterval(minutes * 60 - elapsed))
        if let reason { write(.sessionEnded(reason, verified: true), session: id, source: source) }
        return id
    }

    var ledger: FocusLedger { FocusLedger(events) }

    func credits(now: Date? = nil, sources: Set<FocusSource> = [.live]) -> [SessionCredit] {
        HoursCredit.credit(ledger.sessions(), crediting: sources, now: now ?? time.now)
    }
}
```

`MapleKit/Tests/MapleCoreTests/HoursCreditTests.swift`:
```swift
import Foundation
import Testing
@testable import MapleCore

@Suite("Hours credit")
struct HoursCreditTests {
    private func one(_ day: FocusDay, now: Date? = nil) throws -> SessionCredit {
        try #require(day.credits(now: now).first)
    }

    @Test("A session proven to its planned end credits exactly its length")
    func exact() throws {
        let day = FocusDay(at(2026, 10, 23, 14))
        day.session(minutes: 50)
        let credit = try one(day)
        #expect(credit.seconds == 3000)
        #expect(credit.awakeSeconds == 3000)
        #expect(credit.day == LocalDay(year: 2026, month: 10, day: 23))
        #expect(credit.stretches.allSatisfy(\.counted))
    }

    @Test("3,600 seconds is an hour; 3,599 isn't")
    func hourBoundary() throws {
        let full = FocusDay(at(2026, 10, 23, 9))
        full.session(minutes: 60)
        #expect(try one(full).seconds == 3600)
        let short = FocusDay(at(2026, 10, 23, 9))
        let id = short.session(minutes: 0, planned: 60, reason: nil)
        short.time.advance(3599)
        short.write(.sessionEnded(.endedEarly, verified: true), session: id)
        #expect(try one(short).seconds == 3599)
    }

    @Test("Overlapping sessions count once")
    func overlap() throws {
        let day = FocusDay(at(2026, 10, 23, 14))
        let a = UUID(), b = UUID()
        day.write(.sessionStarted(FocusFixtures.plan()), session: a)
        day.write(.shieldApplied, session: a)                                  // 14:00
        day.at(at(2026, 10, 23, 14, 10))
        day.write(.sessionStarted(FocusFixtures.plan()), session: b)
        day.write(.shieldApplied, session: b)                                  // 14:10
        day.at(at(2026, 10, 23, 14, 50))
        day.write(.sessionEnded(.completed, verified: true), session: a)
        day.at(at(2026, 10, 23, 15))
        day.write(.sessionEnded(.completed, verified: true), session: b)
        let credits = day.credits()
        #expect(credits.map(\.seconds) == [3000, 600])
        #expect(credits[1].stretches.contains { $0.rule == .overlap && $0.interval.duration == 2400 })
    }

    @Test("A 23:40–00:30 session with bed at 01:00 counts whole, on one Maple day")
    func acrossMidnight() throws {
        let window = AwakeWindow(start: at(2026, 10, 23, 8), end: at(2026, 10, 24, 1), windDown: at(2026, 10, 24, 0, 15))
        let day = FocusDay(at(2026, 10, 23, 23, 40))
        day.session(minutes: 50, plan: FocusFixtures.plan(window: window))
        let credit = try one(day)
        #expect(credit.seconds == 3000)
        #expect(credit.day == LocalDay(year: 2026, month: 10, day: 23))
    }

    @Test("A session across the autumn clock change credits its real length")
    func clockChangeDay() throws {
        var london = Calendar(identifier: .gregorian)
        london.timeZone = TimeZone(identifier: "Europe/London")!
        let window = AwakeWindow(start: at(2026, 10, 24, 6, in: london), end: at(2026, 10, 25, 4, in: london),
                                 windDown: at(2026, 10, 25, 3, in: london))
        let day = FocusDay(at(2026, 10, 25, 0, 40, in: london))
        day.session(minutes: 90, plan: FocusFixtures.plan(minutes: 90, day: "2026-10-24", window: window))
        #expect(try one(day).seconds == 5400)
    }

    @Test("A flight mid-session changes nothing: the day and zone are the plan's")
    func flight() throws {
        let day = FocusDay(at(2026, 10, 23, 14))
        let id = day.session(minutes: 25, planned: 50, reason: nil)
        day.time.setZone("America/New_York")
        day.time.advance(25 * 60)
        day.write(.sessionEnded(.completed, verified: true), session: id)
        let credit = try one(day)
        #expect(credit.seconds == 3000)
        #expect(credit.zone == "UTC")
    }

    @Test("Time after the last checkpoint is unconfirmed while running, and never counted")
    func provisional() throws {
        let day = FocusDay(at(2026, 10, 23, 14))
        let id = day.session(minutes: 20, planned: 50, reason: nil)
        day.write(.shieldVerified, session: id)                                // 14:20:05
        day.time.advance(10 * 60)
        let credit = try one(day)
        #expect(credit.seconds == 1200)
        #expect(credit.stretches.last?.rule == .unconfirmed)
        #expect(credit.stretches.last?.interval.duration == 600)
        let session = try #require(day.ledger.sessions().first)
        #expect(HoursCredit.provisionalSeconds(for: session, now: day.time.now, roomLeftToday: 21_600 - 1200) == 600)
        #expect(HoursCredit.provisionalSeconds(for: session, now: day.time.now, roomLeftToday: 100) == 100)
    }

    @Test("Revoked access earns credit up to the last checkpoint")
    func revoked() throws {
        let day = FocusDay(at(2026, 10, 23, 14))
        let id = day.session(minutes: 10, planned: 50, reason: nil)
        day.write(.shieldVerified, session: id)
        day.time.advance(60)
        day.write(.shieldLost, session: id)
        day.time.advance(39 * 60)
        day.write(.sessionEnded(.completed, verified: false), session: id)
        let credit = try one(day)
        #expect(credit.seconds == 600)
        #expect(!credit.finished)
    }

    @Test("A plain timer earns nothing, and preview events earn nothing in live launches")
    func nothingCounts() throws {
        let plain = FocusDay(at(2026, 10, 23, 14))
        plain.session(minutes: 50, plan: FocusFixtures.plan(kind: .plainTimer, selection: nil))
        let credit = try one(plain)
        #expect(credit.seconds == 0)
        #expect(credit.stretches.first?.rule == .plainTimer)

        let preview = FocusDay(at(2026, 10, 23, 14))
        preview.session(minutes: 50, source: .preview)
        #expect(preview.credits().isEmpty)
        #expect(preview.credits(sources: [.live, .preview]).first?.seconds == 3000)
    }

    @Test("A selection that doesn't qualify, run to its end, earns nothing and doesn't finish")
    func notQualifying() throws {
        let day = FocusDay(at(2026, 10, 23, 14))
        day.session(minutes: 50, plan: FocusFixtures.plan(selection: SelectionSummary(mode: .onlyThese, apps: 24, sites: 0, categories: 0)))
        let credit = try one(day)
        #expect(credit.seconds == 0)
        #expect(!credit.finished)
        #expect(credit.stretches.first?.rule == .notQualifying)
    }

    @Test("A 50-minute session with a break at minute 30 credits 50 minutes and ends on time")
    func breakCounts() throws {
        let day = FocusDay(at(2026, 10, 23, 14))
        let id = day.session(minutes: 30, planned: 50, reason: nil)
        day.write(.breakStarted(seconds: 300), session: id)
        day.time.advance(300)
        day.write(.breakEnded, session: id)
        day.time.advance(15 * 60)
        day.write(.sessionEnded(.completed, verified: true), session: id)
        let credit = try one(day)
        #expect(credit.seconds == 3000)
        #expect(credit.endedAt == at(2026, 10, 23, 14, 50, 5))
        #expect(credit.finished)
    }

    @Test("Before 60 minutes before wake and after bedtime don't count")
    func awakeWindow() throws {
        let evening = FocusDay(at(2026, 10, 23, 22, 30))
        evening.session(minutes: 50)
        let crossing = try one(evening)
        #expect(crossing.seconds == 1795)                                      // 22:30:05 to 23:00
        #expect(crossing.stretches.contains { $0.rule == .afterBedtime && $0.interval.duration == 1205 })

        let night = FocusDay(at(2026, 10, 23, 23, 10))
        night.session(minutes: 50)
        let after = try one(night)
        #expect(after.seconds == 0)
        #expect(!after.finished)

        let dawn = FocusDay(at(2026, 10, 23, 5, 30))
        dawn.session(minutes: 50)
        let early = try one(dawn)
        #expect(early.seconds == 1205)                                         // 06:00 to 06:20:05
        #expect(early.stretches.first?.rule == .beforeMorning)
    }

    @Test("At most 6 hours count a day, earlier time first")
    func dailyCap() throws {
        let day = FocusDay(at(2026, 10, 23, 7))
        for _ in 0..<7 { day.session(minutes: 60) }
        let credits = day.credits()
        #expect(credits.reduce(0) { $0 + $1.seconds } == 21_600)
        #expect(credits.last?.seconds == 0)
        #expect(credits.last?.stretches.first?.rule == .dailyCap)
    }

    @Test("An override removes its whole window")
    func override() throws {
        let day = FocusDay(at(2026, 10, 23, 14))
        day.session(minutes: 50, overrides: [(minute: 10, seconds: 120)])
        let credit = try one(day)
        #expect(credit.seconds == 2880)
        #expect(credit.stretches.contains { $0.rule == .override && $0.interval.duration == 120 })
    }

    @Test("Finished needs 20 counted minutes, ¾ of the plan and the planned end")
    func finished() throws {
        let gentle = FocusDay(at(2026, 10, 23, 14))
        gentle.session(minutes: 20, plan: FocusFixtures.plan(minutes: 20, strictness: .gentle),
                       overrides: [(minute: 2, seconds: 60), (minute: 6, seconds: 60), (minute: 10, seconds: 60), (minute: 14, seconds: 60)])
        #expect(try !one(gentle).finished)

        for reason in [EndReason.endedEarly, .emergencyRelease, .releaseAll] {
            let day = FocusDay(at(2026, 10, 23, 14))
            day.session(minutes: 50, reason: reason)
            #expect(try !one(day).finished, "\(reason)")
        }

        let quick = FocusDay(at(2026, 10, 23, 14))
        quick.session(minutes: 25)
        #expect(try one(quick).finished)
    }

    @Test("Over the daily cap still finishes")
    func overCapFinishes() throws {
        let day = FocusDay(at(2026, 10, 23, 7))
        day.session(minutes: 175, reason: .endedEarly)
        day.session(minutes: 175, reason: .endedEarly)
        day.session(minutes: 50)
        let last = try #require(day.credits().last)
        #expect(last.seconds == 600)
        #expect(last.finished)
    }

    @Test("At most 3 finished sessions count a day, in the order they ended")
    func threeADay() {
        let day = FocusDay(at(2026, 10, 23, 9))
        for _ in 0..<4 { day.session(minutes: 25) }
        #expect(day.credits().map(\.finished) == [true, true, true, false])
    }

    @Test("Subtracting a window splits and reports what it removed")
    func subtract() {
        let piece = DateInterval(start: at(2026, 10, 23, 14), duration: 3600)
        let (kept, removed) = HoursCredit.subtract([piece], DateInterval(start: at(2026, 10, 23, 14, 10), duration: 600))
        #expect(kept.map(\.duration) == [600, 2400])
        #expect(removed.map(\.duration) == [600])
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -only-testing:MapleCoreTests/HoursCreditTests > "$WS/test.log" 2>&1; grep -E "error:" "$WS/test.log" | head -5`
Expected: `error: cannot find 'HoursCredit' in scope`

- [ ] **Step 3: Write the credit rules**

`MapleKit/Sources/MapleCore/Focus/HoursCredit.swift`:
```swift
import Foundation
import MapleFocusCore

/// Why a stretch of a session didn't count (F1 design §3.3 step 10). The ids are stable: Saved today and the receipt
/// turn them into words.
public enum CreditRule: String, Codable, Sendable, CaseIterable {
    case afterBedtime, beforeMorning, dailyCap, override, unconfirmed, plainTimer, notQualifying, overlap
}

/// A stretch of a session's time and whether it counted.
public struct CreditStretch: Sendable, Hashable {
    public var interval: DateInterval
    /// Nil when it counted; otherwise why not.
    public var rule: CreditRule?

    public init(_ interval: DateInterval, _ rule: CreditRule?) {
        self.interval = interval
        self.rule = rule
    }

    public var counted: Bool { rule == nil }
}

/// One session's credit (F1 design §3.3–3.4).
public struct SessionCredit: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var day: LocalDay
    public var zone: String
    /// Counted seconds, after the daily cap.
    public var seconds: Int
    /// Locked awake seconds before the cap, which decide whether it finished.
    public var awakeSeconds: Int
    public var finished: Bool
    /// When its credit was last proven (its last checkpoint): the moment its leaves are dated.
    public var provenAt: Date
    public var endedAt: Date?
    /// Its awake window's end, from which its day freezes.
    public var dayEnd: Date
    /// Counted and uncounted stretches, in time order.
    public var stretches: [CreditStretch]
}

/// Credit from replayed sessions (F1 design §3.3–3.4, focus spec R1–R13). Pure; works in seconds and rounds once per
/// session.
public enum HoursCredit {
    public static let dailyCap = 6 * 3600
    public static let finishedMinimum = 20 * 60
    public static let finishedShare = 0.75
    public static let finishedPerDay = 3

    /// Credit for every session from a credited source, in start order.
    /// - Parameter now: A running session's time after its last checkpoint shows as `unconfirmed` up to `now`.
    public static func credit(_ sessions: [SessionRecord], crediting sources: Set<FocusSource>, now: Date) -> [SessionCredit] {
        var countedByDay: [String: [DateInterval]] = [:]
        var usedByDay: [String: TimeInterval] = [:]
        var results: [SessionCredit] = []
        var candidates: [(index: Int, endedAt: Date, key: String)] = []

        for session in sessions where sources.contains(session.source) {
            let plan = session.plan
            let key = "\(plan.day)|\(plan.zone)"
            let visibleEnd = max(session.countdownStart, min(session.end?.placed ?? now, session.plannedEnd))
            var stretches: [CreditStretch] = []
            func result(seconds: Int, awake: Int) -> SessionCredit {
                SessionCredit(id: session.id, day: plan.day, zone: plan.zone, seconds: seconds, awakeSeconds: awake, finished: false,
                              provenAt: session.lastCheckpoint ?? session.countdownStart, endedAt: session.end?.placed,
                              dayEnd: plan.window.end, stretches: stretches.sorted { $0.interval.start < $1.interval.start })
            }

            guard plan.canCount else {
                let whole = DateInterval(start: session.countdownStart, end: visibleEnd)
                if whole.duration > 0 { stretches.append(CreditStretch(whole, plan.kind == .plainTimer ? .plainTimer : .notQualifying)) }
                results.append(result(seconds: 0, awake: 0))
                continue
            }

            // Time after the last proof: provisional while running, unconfirmed once ended.
            let provenEnd = session.provenIntervals.last?.end ?? session.countdownStart
            if visibleEnd > provenEnd { stretches.append(CreditStretch(DateInterval(start: provenEnd, end: visibleEnd), .unconfirmed)) }

            var pieces = session.provenIntervals
            for window in session.overrides {
                let (kept, removed) = subtract(pieces, window)
                pieces = kept
                stretches += removed.map { CreditStretch($0, .override) }
            }

            var awake: [DateInterval] = []
            for piece in pieces {
                if piece.start < plan.window.start {
                    stretches.append(CreditStretch(DateInterval(start: piece.start, end: min(piece.end, plan.window.start)), .beforeMorning))
                }
                if piece.end > plan.window.end {
                    stretches.append(CreditStretch(DateInterval(start: max(piece.start, plan.window.end), end: piece.end), .afterBedtime))
                }
                let start = max(piece.start, plan.window.start), end = min(piece.end, plan.window.end)
                if end > start { awake.append(DateInterval(start: start, end: end)) }
            }

            var fresh: [DateInterval] = []
            for piece in awake {
                var remaining = [piece]
                for counted in countedByDay[key, default: []] {
                    let (kept, removed) = subtract(remaining, counted)
                    remaining = kept
                    stretches += removed.map { CreditStretch($0, .overlap) }
                }
                fresh += remaining
            }
            countedByDay[key, default: []] += fresh

            var counted: TimeInterval = 0
            var used = usedByDay[key, default: 0]
            for piece in fresh {
                let take = min(max(0, TimeInterval(dailyCap) - used), piece.duration)
                if take > 0 { stretches.append(CreditStretch(DateInterval(start: piece.start, duration: take), nil)) }
                if take < piece.duration {
                    stretches.append(CreditStretch(DateInterval(start: piece.start.addingTimeInterval(take), end: piece.end), .dailyCap))
                }
                counted += take
                used += take
            }
            usedByDay[key] = used

            let awakeSeconds = Int(fresh.reduce(0) { $0 + $1.duration }.rounded())
            results.append(result(seconds: Int(counted.rounded()), awake: awakeSeconds))
            if session.endReason == .completed, let endedAt = session.end?.placed, awakeSeconds >= finishedMinimum,
               Double(awakeSeconds) >= finishedShare * Double(plan.plannedSeconds) {
                candidates.append((results.count - 1, endedAt, key))
            }
        }

        var finishedByDay: [String: Int] = [:]
        for candidate in candidates.sorted(by: { $0.endedAt < $1.endedAt }) where finishedByDay[candidate.key, default: 0] < finishedPerDay {
            results[candidate.index].finished = true
            finishedByDay[candidate.key, default: 0] += 1
        }
        return results
    }

    /// The provisional seconds a running session would add after its last checkpoint: shown on the dial and Home, never
    /// given to the counters (§3.3 step 9). Inside its awake window, outside overrides, within the room left today.
    public static func provisionalSeconds(for session: SessionRecord, now: Date, roomLeftToday: Int) -> Int {
        guard session.plan.canCount, session.end == nil, session.lostAt == nil, session.applied != nil else { return 0 }
        let from = max(session.provenIntervals.last?.end ?? session.countdownStart, session.plan.window.start)
        let to = min(now, session.plannedEnd, session.plan.window.end)
        guard to > from else { return 0 }
        var pieces = [DateInterval(start: from, end: to)]
        for window in session.overrides { pieces = subtract(pieces, window).kept }
        let seconds = Int(pieces.reduce(0) { $0 + $1.duration }.rounded(.down))
        return min(max(0, roomLeftToday), seconds)
    }

    /// `pieces` without `window`, and the parts it removed.
    static func subtract(_ pieces: [DateInterval], _ window: DateInterval) -> (kept: [DateInterval], removed: [DateInterval]) {
        var kept: [DateInterval] = []
        var removed: [DateInterval] = []
        for piece in pieces {
            let start = max(piece.start, window.start), end = min(piece.end, window.end)
            guard end > start else {
                kept.append(piece)
                continue
            }
            removed.append(DateInterval(start: start, end: end))
            if piece.start < start { kept.append(DateInterval(start: piece.start, end: start)) }
            if end < piece.end { kept.append(DateInterval(start: end, end: piece.end)) }
        }
        return (kept, removed)
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -only-testing:MapleCoreTests/HoursCreditTests > "$WS/test.log" 2>&1; tail -3 "$WS/test.log"`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add MapleKit/Sources/MapleCore/Focus/HoursCredit.swift MapleKit/Tests/MapleCoreTests/FocusDay.swift MapleKit/Tests/MapleCoreTests/HoursCreditTests.swift
git commit -m "Hours credit: awake window, overrides, overlap, the daily cap, labels and finished sessions

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: The focus book

**Files:**
- Create: `MapleKit/Sources/MapleCore/Focus/FocusBook.swift`
- Test: `MapleKit/Tests/MapleCoreTests/FocusBookTests.swift`

**Interfaces:**
- Consumes: `SessionCredit`, `HoursCredit.dailyCap` and `finishedPerDay`, `FocusRules.version`.
- Produces:
  - `SessionTally(seconds:finished:provenAt:)`;
  - `DayCredit`: `day`, `zone`, `sessions` (`[String: SessionTally]`, keyed by the lowercased session uuid), `seconds`, `finished`, `firstCountedAt`, `dayEnd`, `rulesVersion`, `frozen`, `id`, `freezesAt`, `isFocusDay`;
  - `FocusTotals(seconds:finished:)` and `.zero`;
  - `FocusBook(days:baseline:bestRun:startedAt:)`, with `recountDays`, `totalSeconds`, `totalFinished`, `focusDays: [(day: LocalDay, zone: String)]`, `seconds(on:)`, `record(_:) -> Bool` and `freeze(at:) -> Bool`, and tolerant `Codable`.

- [ ] **Step 1: Write the failing tests**

`MapleKit/Tests/MapleCoreTests/FocusBookTests.swift`:
```swift
import Foundation
import Testing
@testable import MapleCore

@Suite("Focus book")
struct FocusBookTests {
    private let oct23 = LocalDay(year: 2026, month: 10, day: 23)

    private func credit(_ id: UUID, seconds: Int, finished: Bool = false, provenAt: Date = at(2026, 10, 23, 15),
                        day: LocalDay = LocalDay(year: 2026, month: 10, day: 23)) -> SessionCredit {
        SessionCredit(id: id, day: day, zone: "UTC", seconds: seconds, awakeSeconds: seconds, finished: finished, provenAt: provenAt,
                      endedAt: provenAt, dayEnd: at(2026, 10, 23, 23), stretches: [])
    }

    @Test("Each session keeps its highest credit, so a later loss doesn't stall a later session")
    func highWater() {
        var book = FocusBook()
        let a = UUID(), b = UUID()
        book.record([credit(a, seconds: 3000, finished: true)])
        book.record([credit(a, seconds: 0), credit(b, seconds: 600)])
        #expect(book.days.count == 1)
        #expect(book.days[0].seconds == 3600)
        #expect(book.days[0].finished == 1)
        #expect(book.totalSeconds == 3600)
    }

    @Test("A day's total is capped at 6 hours and 3 finished sessions")
    func caps() {
        var book = FocusBook()
        book.record((0..<5).map { _ in credit(UUID(), seconds: 3 * 3600, finished: true) })
        #expect(book.days[0].seconds == 21_600)
        #expect(book.days[0].finished == 3)
    }

    @Test("Days freeze 3 days after their end, keep only their totals, and then never change")
    func freezing() {
        var book = FocusBook()
        let a = UUID()
        book.record([credit(a, seconds: 3000, finished: true)])
        #expect(!book.freeze(at: at(2026, 10, 26, 22, 59)))
        #expect(book.freeze(at: at(2026, 10, 26, 23)))
        #expect(book.days[0].frozen)
        #expect(book.days[0].sessions.isEmpty)
        #expect(book.days[0].seconds == 3000)
        #expect(!book.record([credit(UUID(), seconds: 600)]))
        #expect(book.totalSeconds == 3000)
    }

    @Test("Proof that arrives late keeps its day open for 3 days from then")
    func lateProof() {
        var book = FocusBook()
        book.record([credit(UUID(), seconds: 1800, provenAt: at(2026, 10, 28, 9))])
        #expect(!book.freeze(at: at(2026, 10, 30, 9)))
        #expect(book.freeze(at: at(2026, 10, 31, 9)))
    }

    @Test("Totals include the baseline")
    func baseline() {
        var book = FocusBook(baseline: FocusTotals(seconds: 36_000, finished: 12))
        book.record([credit(UUID(), seconds: 1800, finished: true)])
        #expect(book.totalSeconds == 37_800)
        #expect(book.totalFinished == 13)
    }

    @Test("Focus days are the days with a finished session")
    func focusDays() {
        var book = FocusBook()
        book.record([credit(UUID(), seconds: 1800, finished: true)])
        book.record([credit(UUID(), seconds: 900, day: LocalDay(year: 2026, month: 10, day: 24))])
        #expect(book.focusDays.map(\.day) == [oct23])
        #expect(book.seconds(on: LocalDay(year: 2026, month: 10, day: 24)) == 900)
    }

    @Test("Decoding is tolerant: a damaged day is skipped, unknown keys are ignored")
    func tolerant() throws {
        var book = FocusBook(bestRun: 4, startedAt: at(2026, 10, 1))
        book.record([credit(UUID(), seconds: 1800, finished: true)])
        var json = try #require(String(data: try JSONEncoder().encode(book), encoding: .utf8))
        json = json.replacingOccurrences(of: "\"days\":[", with: "\"future\":1,\"days\":[{\"day\":\"bad\"},")
        let decoded = try JSONDecoder().decode(FocusBook.self, from: Data(json.utf8))
        #expect(decoded == book)
        let empty = try JSONDecoder().decode(FocusBook.self, from: Data("{}".utf8))
        #expect(empty == FocusBook())
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -only-testing:MapleCoreTests/FocusBookTests > "$WS/test.log" 2>&1; grep -E "error:" "$WS/test.log" | head -5`
Expected: `error: cannot find 'FocusBook' in scope`

- [ ] **Step 3: Write the book**

`MapleKit/Sources/MapleCore/Focus/FocusBook.swift`:
```swift
import Foundation
import MapleFocusCore

/// One session's credit as the book keeps it: high-water marks (F1 design §3.5).
public struct SessionTally: Codable, Sendable, Equatable {
    public var seconds: Int
    public var finished: Bool
    public var provenAt: Date

    public init(seconds: Int, finished: Bool, provenAt: Date) {
        self.seconds = seconds
        self.finished = finished
        self.provenAt = provenAt
    }
}

/// One Maple day's credit (R11). Facts only: its streak status is worked out, never stored.
public struct DayCredit: Codable, Sendable, Equatable, Identifiable {
    public var day: LocalDay
    public var zone: String
    /// Each session's high-water credit, keyed by the lowercased session id. Emptied once the day is frozen.
    public var sessions: [String: SessionTally]
    /// Never falls; at most 6 hours.
    public var seconds: Int
    /// Never falls; at most 3.
    public var finished: Int
    public var firstCountedAt: Date
    /// The day's awake window's end (its bedtime).
    public var dayEnd: Date
    public var rulesVersion: Int
    public var frozen: Bool

    public init(
        day: LocalDay, zone: String, sessions: [String: SessionTally] = [:], seconds: Int = 0, finished: Int = 0,
        firstCountedAt: Date, dayEnd: Date, rulesVersion: Int = FocusRules.version, frozen: Bool = false
    ) {
        self.day = day
        self.zone = zone
        self.sessions = sessions
        self.seconds = seconds
        self.finished = finished
        self.firstCountedAt = firstCountedAt
        self.dayEnd = dayEnd
        self.rulesVersion = rulesVersion
        self.frozen = frozen
    }

    public var id: String { "\(day)|\(zone)" }
    /// 3 days after the later of the day's end and its first credit.
    public var freezesAt: Date { max(dayEnd, firstCountedAt).addingTimeInterval(FocusBook.recountDays * 86400) }
    public var isFocusDay: Bool { finished > 0 }
}

public struct FocusTotals: Codable, Sendable, Equatable {
    public var seconds: Int
    public var finished: Int

    public init(seconds: Int, finished: Int) {
        self.seconds = seconds
        self.finished = finished
    }

    public static let zero = FocusTotals(seconds: 0, finished: 0)
}

/// Every Maple day's focus credit, kept in `CollectionSnapshot` beside the counters (F1 design §3.5). Counters are the
/// baseline plus the sum of the days, so a recount, a lost ledger or an older build can never lower them or stall
/// new leaves.
public struct FocusBook: Codable, Sendable, Equatable {
    /// Days a day can still be recounted upward.
    public static let recountDays: TimeInterval = 3

    /// In day order.
    public var days: [DayCredit]
    /// Totals the book can't recount: whatever the counters held when it started, less what the replay recounted.
    public var baseline: FocusTotals
    /// The best Focus streak run ever: a high-water mark.
    public var bestRun: Int
    /// When the book began; nil means it must take its baseline from the counters.
    public var startedAt: Date?

    public init(days: [DayCredit] = [], baseline: FocusTotals = .zero, bestRun: Int = 0, startedAt: Date? = nil) {
        self.days = days
        self.baseline = baseline
        self.bestRun = bestRun
        self.startedAt = startedAt
    }

    public var totalSeconds: Int { baseline.seconds + days.reduce(0) { $0 + $1.seconds } }
    public var totalFinished: Int { baseline.finished + days.reduce(0) { $0 + $1.finished } }

    /// Days with a finished session, with the zone each was spent in, in order.
    public var focusDays: [(day: LocalDay, zone: String)] {
        days.filter(\.isFocusDay).map { ($0.day, $0.zone) }
    }

    /// Seconds counted on `day`, in every zone.
    public func seconds(on day: LocalDay) -> Int {
        days.filter { $0.day == day }.reduce(0) { $0 + $1.seconds }
    }

    /// Records sessions' credit as high-water marks; frozen days don't change.
    /// - Returns: Whether anything changed.
    @discardableResult
    public mutating func record(_ credits: [SessionCredit]) -> Bool {
        let before = self
        for credit in credits where credit.seconds > 0 || credit.finished {
            let key = "\(credit.day)|\(credit.zone)"
            let index: Int
            if let found = days.firstIndex(where: { $0.id == key }) {
                index = found
            } else {
                days.append(DayCredit(day: credit.day, zone: credit.zone, firstCountedAt: credit.provenAt, dayEnd: credit.dayEnd))
                index = days.count - 1
            }
            guard !days[index].frozen else { continue }
            var day = days[index]
            let id = credit.id.uuidString.lowercased()
            let old = day.sessions[id]
            day.sessions[id] = SessionTally(
                seconds: max(old?.seconds ?? 0, credit.seconds), finished: (old?.finished ?? false) || credit.finished,
                provenAt: max(old?.provenAt ?? .distantPast, credit.provenAt)
            )
            day.seconds = max(day.seconds, min(HoursCredit.dailyCap, day.sessions.values.reduce(0) { $0 + $1.seconds }))
            day.finished = max(day.finished, min(HoursCredit.finishedPerDay, day.sessions.values.filter(\.finished).count))
            day.firstCountedAt = min(day.firstCountedAt, credit.provenAt)
            days[index] = day
        }
        days.sort { ($0.day, $0.zone) < ($1.day, $1.zone) }
        return self != before
    }

    /// Freezes days 3 days after the later of their end and their first credit, keeping only their totals.
    /// - Returns: Whether any day froze.
    @discardableResult
    public mutating func freeze(at now: Date) -> Bool {
        var changed = false
        for index in days.indices where !days[index].frozen && now >= days[index].freezesAt {
            days[index].frozen = true
            days[index].sessions = [:]
            changed = true
        }
        return changed
    }

    // MARK: Codable (tolerant: a damaged day is skipped, missing fields take their defaults)

    private enum CodingKeys: String, CodingKey {
        case days, baseline, bestRun, startedAt
    }

    private struct Lossy<Value: Decodable>: Decodable {
        let value: Value?

        init(from decoder: any Decoder) throws {
            value = try? Value(from: decoder)
        }
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        days = ((try? c.decodeIfPresent([Lossy<DayCredit>].self, forKey: .days)) ?? []).compactMap(\.value)
        baseline = (try? c.decodeIfPresent(FocusTotals.self, forKey: .baseline)) ?? .zero
        bestRun = (try? c.decodeIfPresent(Int.self, forKey: .bestRun)) ?? 0
        startedAt = (try? c.decodeIfPresent(Date.self, forKey: .startedAt)) ?? nil
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(days, forKey: .days)
        try c.encode(baseline, forKey: .baseline)
        try c.encode(bestRun, forKey: .bestRun)
        try c.encodeIfPresent(startedAt, forKey: .startedAt)
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -only-testing:MapleCoreTests/FocusBookTests > "$WS/test.log" 2>&1; tail -3 "$WS/test.log"`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add MapleKit/Sources/MapleCore/Focus/FocusBook.swift MapleKit/Tests/MapleCoreTests/FocusBookTests.swift
git commit -m "Focus book: per-session high-water marks per Maple day, freezing and a tolerant format

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: The Focus streak

**Files:**
- Create: `MapleKit/Sources/MapleCore/Focus/FocusRuns.swift`
- Test: `MapleKit/Tests/MapleCoreTests/FocusRunsTests.swift`

**Interfaces:**
- Consumes: `LocalDay.ordinal` (Task 9).
- Produces: `FocusRuns(focusDays:today:)`, with `current: Int` and `best: Int`, and the static `restDays = 2`, `restWindow = 7` and `fits(_:) -> Bool`.

- [ ] **Step 1: Write the failing tests**

`MapleKit/Tests/MapleCoreTests/FocusRunsTests.swift`:
```swift
import Foundation
import Testing
@testable import MapleCore

@Suite("Focus streak")
struct FocusRunsTests {
    /// Day `n` of a run of days starting on Monday 5 October 2026.
    private func day(_ n: Int) -> LocalDay {
        LocalDay(year: 2026, month: 10, day: 5).adding(days: n, calendar: utc)
    }

    private func runs(_ days: [Int], today: Int, zones: [Int: String] = [:]) -> FocusRuns {
        FocusRuns(focusDays: days.map { (day($0), zones[$0] ?? "UTC") }, today: day(today))
    }

    @Test("Monday to Friday keeps the run going, weekends bridged as rest days")
    func weekdays() {
        let weeks = [0, 1, 2, 3, 4, 7, 8, 9, 10, 11, 14, 15, 16, 17, 18]
        let result = runs(weeks, today: 18)
        #expect(result.current == 19)
        #expect(result.best == 19)
    }

    @Test("A third miss in 7 days breaks the run")
    func thirdMiss() {
        let result = runs([0, 2, 4, 6], today: 6)
        #expect(result.best == 5)
        #expect(result.current == 1)
    }

    @Test("One session then misses never makes a run longer than 1")
    func trailing() {
        #expect(runs([0], today: 2).current == 1)
        #expect(runs([0], today: 3).current == 1)
        #expect(runs([0], today: 4).current == 0)
        #expect(runs([0], today: 4).best == 1)
    }

    @Test("Misses are bridged once a finished day follows")
    func bridged() {
        #expect(runs([0, 3], today: 3).current == 4)
    }

    @Test("Today stays pending")
    func pending() {
        #expect(runs([0, 1, 2], today: 3).current == 3)
        #expect(runs([0, 1, 2, 3], today: 3).current == 4)
    }

    @Test("A one-day gap across a time-zone change is neutral")
    func travel() {
        let result = runs([0, 2], today: 2, zones: [0: "Europe/London", 2: "America/Los_Angeles"])
        #expect(result.current == 2)
        // In one zone the same gap is a rest day and counts toward the length.
        #expect(runs([0, 2], today: 2).current == 3)
    }

    @Test("A day spent in two zones counts once")
    func twoZones() {
        let result = FocusRuns(focusDays: [(day(0), "UTC"), (day(0), "Asia/Tokyo"), (day(1), "UTC")], today: day(1))
        #expect(result.current == 2)
    }

    @Test("At most 2 rest days in any 7 days in a row")
    func fits() {
        #expect(FocusRuns.fits([1, 2]))
        #expect(!FocusRuns.fits([1, 2, 7]))
        #expect(FocusRuns.fits([1, 2, 8]))
    }

    @Test("Nothing yet")
    func empty() {
        let result = runs([], today: 3)
        #expect(result.current == 0)
        #expect(result.best == 0)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -only-testing:MapleCoreTests/FocusRunsTests > "$WS/test.log" 2>&1; grep -E "error:" "$WS/test.log" | head -5`
Expected: `error: cannot find 'FocusRuns' in scope`

- [ ] **Step 3: Write the streak**

`MapleKit/Sources/MapleCore/Focus/FocusRuns.swift`:
```swift
import Foundation

/// The Focus streak (F1 design §3.4). A run starts and ends on a focus day (a Maple day with a finished session), and
/// every day between is a rest day, with at most 2 rest days in any 7 days in a row. Rest days only bridge: misses
/// after the last focus day neither count nor break the run while the allowance still covers them. A one-day gap
/// across a time-zone change is neutral. Pure, with day arithmetic on `LocalDay.ordinal`.
public struct FocusRuns: Sendable, Equatable {
    public static let restDays = 2
    public static let restWindow = 7

    /// The run ending at the latest focus day, or 0 once the misses since can't be rest days.
    public let current: Int
    /// The longest run.
    public let best: Int

    /// - Parameters:
    ///   - focusDays: Maple days with a finished session, with the zone each was spent in.
    ///   - today: The Maple day now. It stays pending until it ends.
    public init(focusDays: [(day: LocalDay, zone: String)], today: LocalDay) {
        let todayOrdinal = today.ordinal
        var seen = Set<Int>()
        let days = focusDays
            .map { (ordinal: $0.day.ordinal, zone: $0.zone) }
            .filter { $0.ordinal <= todayOrdinal }
            .sorted { $0.ordinal < $1.ordinal }
            .filter { seen.insert($0.ordinal).inserted }

        var best = 0
        var length = 0
        var rests: [Int] = []
        var last: (ordinal: Int, zone: String)?
        for entry in days {
            if let previous = last {
                let misses = entry.ordinal - previous.ordinal - 1
                let gap = misses > 0 ? Array((previous.ordinal + 1)..<entry.ordinal) : []
                if misses == 0 {
                    length += 1
                } else if misses == 1, previous.zone != entry.zone {
                    length += 1
                } else if misses <= Self.restDays, Self.fits(rests + gap) {
                    length += misses + 1
                    rests += gap
                } else {
                    length = 1
                    rests = []
                }
            } else {
                length = 1
            }
            best = max(best, length)
            last = entry
        }

        if let previous = last {
            let trailing = todayOrdinal - previous.ordinal - 1
            if trailing <= 0 {
                current = length
            } else {
                let gap = Array((previous.ordinal + 1)..<todayOrdinal)
                current = trailing <= Self.restDays && Self.fits(rests + gap) ? length : 0
            }
        } else {
            current = 0
        }
        self.best = best
    }

    /// Whether `rests` (day ordinals) has at most 2 days in any 7 days in a row.
    public static func fits(_ rests: [Int]) -> Bool {
        let sorted = rests.sorted()
        guard sorted.count > restDays else { return true }
        for index in 0..<(sorted.count - restDays) where sorted[index + restDays] - sorted[index] < restWindow {
            return false
        }
        return true
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -only-testing:MapleCoreTests/FocusRunsTests > "$WS/test.log" 2>&1; tail -3 "$WS/test.log"`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add MapleKit/Sources/MapleCore/Focus/FocusRuns.swift MapleKit/Tests/MapleCoreTests/FocusRunsTests.swift
git commit -m "Focus streak: rest days only bridge gaps, at most 2 in any 7 days

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 13: Counters from the book, and collection version 2

**Files:**
- Create: `MapleKit/Sources/MapleCore/Focus/FocusCounters.swift`
- Modify: `MapleKit/Sources/MapleCore/Collection/CollectionSnapshot.swift` (the `focus` field, version 2, tolerant decoding)
- Modify: `MapleKit/Sources/MapleCore/Focus/CollectionSnapshot+Focus.swift` (`applyFocus`, `currentRun`)
- Modify: `MapleKit/Sources/MapleServices/Collection/CollectionStore.swift` (`applyFocus`, `focus`, and never saving over a newer file)
- Modify: `MapleKit/Sources/MapleServices/Demo/DemoData.swift` (seed the book from the counters)
- Test: `MapleKit/Tests/MapleCoreTests/FocusCountersTests.swift`
- Test: `MapleKit/Tests/MapleServicesTests/StoreSafetyTests.swift` (a newer file is never overwritten)
- Test: `MapleKit/Tests/MapleServicesTests/DemoTests.swift` (the demo book matches the counters)

**Interfaces:**
- Consumes: `FocusBook`, `SessionCredit`, `FocusRuns`, `CollectionSnapshot.focusWindow(at:context:)`, `raise(_:to:at:calendar:)`, `runEngine(at:context:engine:)`.
- Produces:
  - `FocusMark(instant:hours:sessions:)`;
  - `FocusCounters.marks(book:) -> [FocusMark]`;
  - `CollectionSnapshot.focus: FocusBook`, `currentVersion == 2`, `isFromNewerBuild: Bool`;
  - `CollectionSnapshot.applyFocus(_:at:context:engine:) -> [LeafUnlock]` and `currentRun(at:context:) -> Int`;
  - `CollectionStore.applyFocus(_:at:) -> [LeafUnlock]`, `CollectionStore.focus: FocusBook` and `CollectionStore.currentRun(at:) -> Int`.

**Rulings this task carries:**
- "Today" for the streak is the Maple day of `focusWindow(at: now)`: a day stops being pending at its bedtime, the end of its awake window (§3.3 step 6, §3.4).
- Marks come only from days that still have their sessions. Frozen days and the baseline are already in the counters, so they're added as a constant. After the marks, the final totals are raised at `now`, so the counters always equal the book even when a mark can't be placed.

- [ ] **Step 1: Write the failing tests**

`MapleKit/Tests/MapleCoreTests/FocusCountersTests.swift`:
```swift
import Foundation
import Testing
@testable import MapleCore

@Suite("Focus counters")
struct FocusCountersTests {
    private let context = CollectionContext(schedule: .standard, permissions: [.appleHealth], calendar: utc, hemisphere: .northern)

    private func planted() -> CollectionSnapshot {
        var snapshot = CollectionSnapshot.empty(profileID: UUID(), createdAt: at(2026, 10, 1))
        snapshot.raise(.firstLeaf, to: 1, at: at(2026, 10, 1, 21), calendar: utc)
        snapshot.runEngine(at: at(2026, 10, 1, 21), context: context)
        return snapshot
    }

    private func credit(seconds: Int, finished: Bool = true, provenAt: Date, day: LocalDay = LocalDay(year: 2026, month: 10, day: 23)) -> SessionCredit {
        SessionCredit(id: UUID(), day: day, zone: "UTC", seconds: seconds, awakeSeconds: seconds, finished: finished,
                      provenAt: provenAt, endedAt: provenAt, dayEnd: at(2026, 10, 23, 23), stretches: [])
    }

    @Test("Marks add up session by session, in the order credit was proven, after the baseline")
    func marks() {
        var book = FocusBook(baseline: FocusTotals(seconds: 7200, finished: 2), startedAt: at(2026, 10, 1))
        book.record([credit(seconds: 1800, provenAt: at(2026, 10, 23, 15)), credit(seconds: 3600, provenAt: at(2026, 10, 23, 10))])
        let marks = FocusCounters.marks(book: book)
        #expect(marks.map(\.instant) == [at(2026, 10, 23, 10), at(2026, 10, 23, 15)])
        #expect(marks.map(\.hours) == [3, 3.5])
        #expect(marks.map(\.sessions) == [3, 4])
    }

    @Test("Marks respect the daily cap")
    func cappedMarks() {
        var book = FocusBook()
        book.record((0..<4).map { credit(seconds: 2 * 3600, provenAt: at(2026, 10, 23, 9 + 2 * $0)) })
        #expect(FocusCounters.marks(book: book).map(\.hours) == [2, 4, 6, 6])
        #expect(FocusCounters.marks(book: book).map(\.sessions) == [1, 2, 3, 3])
    }

    @Test("A leaf is dated when its credit was proven, not when the app caught up")
    func dated() throws {
        var snapshot = planted()
        let added = snapshot.applyFocus([credit(seconds: 3600, provenAt: at(2026, 10, 23, 10, 0, 5))], at: at(2026, 10, 23, 21, 30), context: context)
        let hours = try #require(added.first { $0.speciesID == species(.hoursSaved, rung: 0) })
        #expect(hours.date == at(2026, 10, 23, 10, 0, 5))
        #expect(snapshot.counters[.hoursSaved] == 1)
        #expect(snapshot.counters[.sessionsFinished] == 1)
        #expect(snapshot.focus.startedAt == at(2026, 10, 23, 21, 30))
    }

    @Test("Applying the same credit again changes nothing")
    func idempotent() {
        var snapshot = planted()
        let credits = [credit(seconds: 3000, provenAt: at(2026, 10, 23, 14, 50))]
        snapshot.applyFocus(credits, at: at(2026, 10, 23, 15), context: context)
        let before = snapshot
        #expect(snapshot.applyFocus(credits, at: at(2026, 10, 23, 15, 5), context: context).isEmpty)
        #expect(snapshot == before)
    }

    @Test("A book an older build dropped is rebuilt from the counters, and new credit adds on top")
    func droppedBook() {
        var snapshot = planted()
        snapshot.counters[.hoursSaved] = 10
        snapshot.counters[.sessionsFinished] = 4
        snapshot.counters[.focusStreak] = 6
        let old = credit(seconds: 3600, provenAt: at(2026, 10, 22, 10), day: LocalDay(year: 2026, month: 10, day: 22))
        snapshot.applyFocus([old], at: at(2026, 10, 23, 9), context: context)
        #expect(snapshot.focus.baseline == FocusTotals(seconds: 9 * 3600, finished: 3))
        #expect(snapshot.focus.bestRun == 6)
        #expect(snapshot.counters[.hoursSaved] == 10)
        snapshot.applyFocus([old, credit(seconds: 1800, provenAt: at(2026, 10, 23, 11))], at: at(2026, 10, 23, 11, 5), context: context)
        #expect(snapshot.counters[.hoursSaved] == 10.5)
        #expect(snapshot.counters[.sessionsFinished] == 5)
    }

    @Test("The best run is a high-water mark; the current run follows the misses")
    func runs() {
        var snapshot = planted()
        let days = [19, 20, 21].map { LocalDay(year: 2026, month: 10, day: $0) }
        snapshot.applyFocus(days.map { credit(seconds: 1800, provenAt: at(2026, 10, $0.day, 12), day: $0) }, at: at(2026, 10, 21, 13), context: context)
        #expect(snapshot.counters[.focusStreak] == 3)
        #expect(snapshot.currentRun(at: at(2026, 10, 23, 12), context: context) == 3)
        // 22 and 23 October fit as rest days while nothing follows them; a third miss doesn't.
        #expect(snapshot.currentRun(at: at(2026, 10, 24, 12), context: context) == 3)
        #expect(snapshot.currentRun(at: at(2026, 10, 25, 12), context: context) == 0)
        snapshot.applyFocus([], at: at(2026, 10, 30, 12), context: context)
        #expect(snapshot.focus.bestRun == 3)
        #expect(snapshot.counters[.focusStreak] == 3)
    }

    @Test("Nothing is recorded before the maple is planted")
    func unplanted() {
        var snapshot = CollectionSnapshot.empty(profileID: UUID(), createdAt: at(2026, 10, 1))
        #expect(snapshot.applyFocus([credit(seconds: 3600, provenAt: at(2026, 10, 23, 10))], at: at(2026, 10, 23, 11), context: context).isEmpty)
        #expect(snapshot.focus == FocusBook())
    }

    @Test("Version 2: the book is saved; a version 1 file opens and saves as version 2")
    func versionTwo() throws {
        var snapshot = planted()
        snapshot.applyFocus([credit(seconds: 3600, provenAt: at(2026, 10, 23, 10))], at: at(2026, 10, 23, 11), context: context)
        let data = try JSONEncoder().encode(snapshot)
        #expect(try JSONDecoder().decode(CollectionSnapshot.self, from: data) == snapshot)

        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["version"] = 1
        object["focus"] = nil
        let old = try JSONDecoder().decode(CollectionSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(old.version == 1)
        #expect(old.focus == FocusBook())
        #expect(!old.isFromNewerBuild)
        let resaved = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        #expect(resaved["version"] as? Int == 2)
    }

    @Test("Decoding is field by field: a damaged field takes its default, and a newer file says so")
    func tolerant() throws {
        let data = try JSONEncoder().encode(planted())
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["history"] = "damaged"
        object["focus"] = ["days": "damaged", "bestRun": 4]
        object["version"] = 3
        object["somethingNew"] = true
        let decoded = try JSONDecoder().decode(CollectionSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.history.isEmpty)
        #expect(decoded.focus.bestRun == 4)
        #expect(decoded.hasPlantedMaple)
        #expect(decoded.isFromNewerBuild)
    }
}
```

In `MapleKit/Tests/MapleServicesTests/StoreSafetyTests.swift`, add inside the suite:
```swift
    @Test("A collection saved by a newer build is read but never written over")
    func newerCollection() throws {
        let folder = try temporaryDirectory()
        let url = folder.appendingPathComponent(MapleStores.collectionFile)
        _ = savedCollection(in: folder)
        var object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        object["version"] = CollectionSnapshot.currentVersion + 1
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        let before = try Data(contentsOf: url)

        let store = CollectionStore(storage: JSONStorage(.file(url)), context: testContext, now: at(2026, 10, 9, 9))
        #expect(store.isAvailable)
        #expect(store.hasPlantedMaple)
        store.record([.restedNights: 1], at: at(2026, 10, 9, 9))
        #expect(store.snapshot.counters[.restedNights] == 1)
        #expect(try Data(contentsOf: url) == before)
    }
```

In `MapleKit/Tests/MapleServicesTests/DemoTests.swift`, add inside the suite:
```swift
    @Test("A demo collection's focus book matches its counters")
    func demoBook() {
        let snapshot = DemoData.snapshot(species: 40, tendedDays: 60, waiting: 0, now: at(2026, 10, 23, 12), calendar: utc,
                                         hemisphere: .northern, features: .all)
        #expect(snapshot.focus.startedAt != nil)
        #expect(Double(snapshot.focus.totalSeconds) == ((snapshot.counters[.hoursSaved] ?? 0) * 3600).rounded())
        #expect(Double(snapshot.focus.totalFinished) == snapshot.counters[.sessionsFinished] ?? 0)
        #expect(Double(snapshot.focus.bestRun) == snapshot.counters[.focusStreak] ?? 0)
    }
```

- [ ] **Step 2: Run them to verify they fail**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -only-testing:MapleCoreTests/FocusCountersTests -only-testing:MapleServicesTests/StoreSafetyTests -only-testing:MapleServicesTests/DemoTests > "$WS/test.log" 2>&1; grep -E "error:" "$WS/test.log" | head -5`
Expected: `error: cannot find 'FocusCounters' in scope` (and `value of type 'CollectionSnapshot' has no member 'focus'`).

- [ ] **Step 3: Write the marks**

`MapleKit/Sources/MapleCore/Focus/FocusCounters.swift`:
```swift
import Foundation

/// The focus counters at one instant: what they were once a session's credit was proven (F1 design §7.2).
public struct FocusMark: Sendable, Equatable {
    public var instant: Date
    public var hours: Double
    public var sessions: Int

    public init(instant: Date, hours: Double, sessions: Int) {
        self.instant = instant
        self.hours = hours
        self.sessions = sessions
    }
}

/// Turns the book into dated marks, so each leaf is unlocked at the moment its credit was proven: unlock dates,
/// tended days and the reveal hold all follow that moment (F1-12).
public enum FocusCounters {
    /// One mark per session still held by an open day, in the order its credit was proven. Each carries the running
    /// totals: the baseline and frozen days, plus each open day's sessions so far within the daily caps.
    public static func marks(book: FocusBook) -> [FocusMark] {
        var fixedSeconds = book.baseline.seconds
        var fixedFinished = book.baseline.finished
        var tallies: [(day: String, tally: SessionTally)] = []
        for day in book.days {
            if day.frozen || day.sessions.isEmpty {
                fixedSeconds += day.seconds
                fixedFinished += day.finished
            } else {
                tallies += day.sessions.values.map { (day.id, $0) }
            }
        }
        tallies.sort { ($0.tally.provenAt, $0.day) < ($1.tally.provenAt, $1.day) }

        var seconds: [String: Int] = [:]
        var finished: [String: Int] = [:]
        return tallies.map { entry in
            seconds[entry.day, default: 0] += entry.tally.seconds
            if entry.tally.finished { finished[entry.day, default: 0] += 1 }
            let totalSeconds = fixedSeconds + seconds.values.reduce(0) { $0 + min(HoursCredit.dailyCap, $1) }
            let totalFinished = fixedFinished + finished.values.reduce(0) { $0 + min(HoursCredit.finishedPerDay, $1) }
            return FocusMark(instant: entry.tally.provenAt, hours: Double(totalSeconds) / 3600, sessions: totalFinished)
        }
    }
}
```

- [ ] **Step 4: Make the collection version 2**

In `MapleKit/Sources/MapleCore/Collection/CollectionSnapshot.swift`:
- change `public static let currentVersion = 1` to `public static let currentVersion = 2`;
- add after `public var nights: NightLedger`:
```swift
    /// Every Maple day's focus credit (F1 design §3.5). The focus counters are its totals.
    public var focus: FocusBook
```
- add the init parameter `focus: FocusBook = FocusBook()` after `nights: NightLedger = NightLedger()`, and `self.focus = focus` after `self.nights = nights`;
- add after `treeSeed`:
```swift
    /// Saved by a newer build: read what this build knows, but never save over it.
    public var isFromNewerBuild: Bool { version > Self.currentVersion }
```
- replace the `// MARK: Codable` section's heading comment, `CodingKeys`, `init(from:)` and `encode(to:)` with:
```swift
    // MARK: Codable (tolerant, field by field: a missing or damaged field takes its default)

    private enum CodingKeys: String, CodingKey {
        case version, profileID, createdAt, unlocks, revealedAt, counters, history, tendedDays, recentNights
        case pinnedSpeciesID, featuredSpeciesID, rarityConsent, revealsOpened, nights, focus
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func field<Value: Decodable>(_ key: CodingKeys, _ fallback: Value) -> Value {
            (try? c.decodeIfPresent(Value.self, forKey: key)) ?? fallback
        }
        // Only these two can't be defaulted: they are the member's maple.
        profileID = try c.decode(UUID.self, forKey: .profileID)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        version = field(.version, 1)
        unlocks = field(.unlocks, [])
        revealedAt = field(.revealedAt, [:])
        counters = (try? CategoryCounterCoding.decode(c, forKey: .counters)) ?? [:]
        history = field(.history, [])
        tendedDays = field(.tendedDays, [])
        recentNights = field(.recentNights, [])
        pinnedSpeciesID = field(.pinnedSpeciesID, String?.none)
        featuredSpeciesID = field(.featuredSpeciesID, String?.none)
        rarityConsent = field(.rarityConsent, RarityConsent.notAsked)
        revealsOpened = field(.revealsOpened, 0)
        nights = field(.nights, NightLedger())
        focus = field(.focus, FocusBook())
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(max(version, Self.currentVersion), forKey: .version)
        try c.encode(profileID, forKey: .profileID)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(unlocks, forKey: .unlocks)
        try c.encode(revealedAt, forKey: .revealedAt)
        try CategoryCounterCoding.encode(counters, to: &c, forKey: .counters)
        try c.encode(history, forKey: .history)
        try c.encode(tendedDays, forKey: .tendedDays)
        try c.encode(recentNights, forKey: .recentNights)
        try c.encodeIfPresent(pinnedSpeciesID, forKey: .pinnedSpeciesID)
        try c.encodeIfPresent(featuredSpeciesID, forKey: .featuredSpeciesID)
        try c.encode(rarityConsent, forKey: .rarityConsent)
        try c.encode(revealsOpened, forKey: .revealsOpened)
        try c.encode(nights, forKey: .nights)
        try c.encode(focus, forKey: .focus)
    }
```
A file with no `version` was written before versions existed, so it decodes as version 1. `version` keeps what the file said: the "never save over" check reads it, and `encode` writes at least the current version.

- [ ] **Step 5: Apply focus credit to the collection**

Append to `MapleKit/Sources/MapleCore/Focus/CollectionSnapshot+Focus.swift`:
```swift
extension CollectionSnapshot {
    /// Records replayed sessions' credit in the book and raises the focus counters to its totals (F1 design §3.5,
    /// §7.2). Each session's credit is applied at the moment it was proven, so leaves are dated then; then the final
    /// totals and the best run are raised at `now`. Counters never fall. Applying the same credit again changes
    /// nothing. Ignored before the maple is planted.
    ///
    /// When the book has no start (a first run, or an older build dropped it) it takes as its baseline whatever the
    /// counters hold beyond what this replay recounts.
    /// - Returns: Leaves unlocked, each dated by the credit that earned it.
    @discardableResult
    public mutating func applyFocus(
        _ credits: [SessionCredit], at now: Date, context: CollectionContext, engine: LeafEngine = LeafEngine()
    ) -> [LeafUnlock] {
        guard hasPlantedMaple else { return [] }
        let calendar = context.calendar
        var book = focus
        book.record(credits)
        if book.startedAt == nil {
            let recounted = FocusBook(days: book.days)
            book.baseline = FocusTotals(
                seconds: max(0, Int(((counters[.hoursSaved] ?? 0) * 3600).rounded()) - recounted.totalSeconds),
                finished: max(0, Int(counters[.sessionsFinished] ?? 0) - recounted.totalFinished)
            )
            book.bestRun = max(book.bestRun, Int(counters[.focusStreak] ?? 0))
            book.startedAt = now
        }
        book.freeze(at: now)
        book.bestRun = max(book.bestRun, FocusRuns(focusDays: book.focusDays, today: focusWindow(at: now, context: context).day).best)
        focus = book

        var added: [LeafUnlock] = []
        for mark in FocusCounters.marks(book: book) where mark.instant <= now {
            raise(.hoursSaved, to: mark.hours, at: mark.instant, calendar: calendar)
            raise(.sessionsFinished, to: Double(mark.sessions), at: mark.instant, calendar: calendar)
            added += runEngine(at: mark.instant, context: context, engine: engine)
        }
        raise(.hoursSaved, to: Double(book.totalSeconds) / 3600, at: now, calendar: calendar)
        raise(.sessionsFinished, to: Double(book.totalFinished), at: now, calendar: calendar)
        raise(.focusStreak, to: Double(book.bestRun), at: now, calendar: calendar)
        added += runEngine(at: now, context: context, engine: engine)
        return added
    }

    /// The current Focus streak run at `date` (§3.4): today is the Maple day whose awake window holds `date`, or the
    /// next one in a sleep window, and stays pending.
    public func currentRun(at date: Date, context: CollectionContext) -> Int {
        FocusRuns(focusDays: focus.focusDays, today: focusWindow(at: date, context: context).day).current
    }
}
```

- [ ] **Step 6: The store and the demo book**

In `MapleKit/Sources/MapleServices/Collection/CollectionStore.swift`, add after `recordSleep(_:at:)`:
```swift
    /// The one call `FocusSessionStore` makes: replayed sessions' credit (`HoursCredit`). Records it in the focus book
    /// and raises the focus counters to its totals, each leaf dated when its credit was proven. Passing the same
    /// credit again changes nothing, so the session store sends every open day's sessions on each replay.
    /// - Returns: Leaves unlocked.
    @discardableResult
    public func applyFocus(_ credits: [SessionCredit], at date: Date) -> [LeafUnlock] {
        mutate { $0.applyFocus(credits, at: date, context: context, engine: engine) }
    }
```
add to the Reading section after `totals`:
```swift
    /// Every Maple day's focus credit.
    public var focus: FocusBook { snapshot.focus }
    /// The Focus streak's current run at `date`.
    public func currentRun(at date: Date) -> Int { snapshot.currentRun(at: date, context: context) }
```
and in `mutate`, replace
```swift
            // The placeholder is never written over a file that couldn't be read.
            if isAvailable { storage.save(copy) }
```
with
```swift
            // The placeholder is never written over a file that couldn't be read, and a newer build's file is never
            // written over at all (F1 design §3.5): changes then last until the app quits.
            if isAvailable, !copy.isFromNewerBuild { storage.save(copy) }
```

In `MapleKit/Sources/MapleServices/Demo/DemoData.swift`, after `snapshot.counters = counters`, add:
```swift
        // The focus book carries the focus counters as its baseline, as a real collection's would after an update.
        snapshot.focus = FocusBook(
            baseline: FocusTotals(seconds: Int(((counters[.hoursSaved] ?? 0) * 3600).rounded()),
                                  finished: Int(counters[.sessionsFinished] ?? 0)),
            bestRun: Int(counters[.focusStreak] ?? 0), startedAt: noon(of: start, calendar: calendar)
        )
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -only-testing:MapleCoreTests -only-testing:MapleServicesTests > "$WS/test.log" 2>&1; tail -3 "$WS/test.log"`
Expected: `** TEST SUCCEEDED **`. Every existing collection test still passes: version 2 changes only what is saved, and `focus` defaults to an empty book.

- [ ] **Step 8: Commit**

```bash
git add MapleKit/Sources/MapleCore MapleKit/Sources/MapleServices MapleKit/Tests
git commit -m "Focus counters: dated marks from the book, collection version 2, never saving over a newer file

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 14: Leaves earned in Evening open at once

F1-12: a leaf carries the moment its credit was earned, and is held until morning only if that moment falls in Wind-down or at night. Pending leaves still open only in Morning, Day and Evening.

**Files:**
- Modify: `MapleKit/Sources/MapleCore/Collection/LeafEngine.swift` (`RevealSchedule.releaseDate` and its doc comment)
- Modify: `MapleKit/Sources/MapleServices/Collection/CollectionStore.swift:190` and `:253` (doc comments)
- Modify: `MapleKit/Tests/MapleCoreTests/LeafEngineTests.swift` (`evening`, `wrap`, `partition`)
- Modify: `MapleKit/Tests/MapleCoreTests/CollectionLogicTests.swift` (`heldAndPending`, `unlockOrder`)
- Modify: `MapleKit/Tests/MapleCoreTests/NightLedgerTests.swift` (`revealAcrossWindDown`)
- Modify: `MapleKit/Tests/MapleCoreTests/WeeklyScheduleTests.swift` (`heldUntilTheWeekendMorning`)
- Modify: `MapleKit/Tests/MapleServicesTests/StoreTests.swift` (`derived`)
- Modify: `MapleKit/Tests/MapleCoreTests/TreeLayoutTests.swift:209` (a comment)
- Modify: `docs/core-api.md:90` and `:232`, `docs/design/spec.md:268` and `:855`, `docs/design/rewards.md:114`

**Interfaces:**
- Consumes: `NowPhase`, `PhaseWindows.nextStart(of:after:calendar:)`.
- Produces: `RevealSchedule.releaseDate(for:schedule:calendar:)` with the new rule; no signature changes.

- [ ] **Step 1: Change the tests to the new rule**

In `MapleKit/Tests/MapleCoreTests/LeafEngineTests.swift`, replace the `evening()` test with:
```swift
    @Test("Unlocks in Evening are pending at once; from Wind-down start they are held until the next Morning start")
    func evening() {
        #expect(release(at(2026, 10, 10, 20, 15)) == at(2026, 10, 10, 20, 15))
        #expect(release(at(2026, 10, 10, 22, 14)) == at(2026, 10, 10, 22, 14))
        #expect(release(at(2026, 10, 10, 22, 15)) == at(2026, 10, 11, 6))
        #expect(release(at(2026, 10, 10, 23, 30)) == at(2026, 10, 11, 6))
        #expect(release(at(2026, 10, 11, 2)) == at(2026, 10, 11, 6))
        #expect(release(at(2026, 10, 11, 5, 59)) == at(2026, 10, 11, 6))
    }
```
in `wrap()`, replace
```swift
        #expect(release(at(2026, 10, 10, 22)) == at(2026, 10, 11, 8))
```
with
```swift
        #expect(release(at(2026, 10, 10, 22)) == at(2026, 10, 10, 22))            // Evening: at once
        #expect(release(at(2026, 10, 11, 0)) == at(2026, 10, 11, 8))              // Wind-down: held
```
and in `partition()`, replace
```swift
        let night = unlock("nigrum", at: at(2026, 10, 10, 21))
        let opened = unlock("saccharinum", at: at(2026, 10, 10, 9), revealed: true)
        let all = [day, night, opened]
        let evening = at(2026, 10, 10, 21, 30)
```
with
```swift
        let night = unlock("nigrum", at: at(2026, 10, 10, 22, 20))                 // Wind-down
        let opened = unlock("saccharinum", at: at(2026, 10, 10, 9), revealed: true)
        let all = [day, night, opened]
        let evening = at(2026, 10, 10, 22, 30)
```

In `MapleKit/Tests/MapleCoreTests/CollectionLogicTests.swift`, in `heldAndPending()`, replace
```swift
        snapshot.record([.sessionsFinished: 1], at: at(2026, 10, 2, 21), calendar: utc)
        snapshot.runEngine(at: at(2026, 10, 2, 21), context: context)               // evening: held

        let evening = at(2026, 10, 2, 21, 30)
        #expect(snapshot.waiting.map(\.speciesID) == ["rubrum", "buergerianum"])
        #expect(snapshot.pending(at: evening, context: context).map(\.speciesID) == ["rubrum"])
        #expect(snapshot.held(at: evening, context: context).map(\.speciesID) == ["buergerianum"])
        #expect(snapshot.revealable(at: evening, context: context).map(\.speciesID) == ["rubrum"])
        #expect(snapshot.revealable(at: at(2026, 10, 2, 22, 30), context: context).isEmpty)  // wind-down
```
with
```swift
        snapshot.record([.sessionsFinished: 1], at: at(2026, 10, 2, 22, 20), calendar: utc)
        snapshot.runEngine(at: at(2026, 10, 2, 22, 20), context: context)           // wind-down: held

        let evening = at(2026, 10, 2, 21, 30)
        let windDown = at(2026, 10, 2, 22, 30)
        #expect(snapshot.waiting.map(\.speciesID) == ["rubrum", "buergerianum"])
        #expect(snapshot.pending(at: windDown, context: context).map(\.speciesID) == ["rubrum"])
        #expect(snapshot.held(at: windDown, context: context).map(\.speciesID) == ["buergerianum"])
        #expect(snapshot.revealable(at: evening, context: context).map(\.speciesID) == ["rubrum"])
        #expect(snapshot.revealable(at: windDown, context: context).isEmpty)
```
and in `unlockOrder()`, replace `let evening = at(2026, 10, 4, 21)` with `let evening = at(2026, 10, 4, 22, 30)                    // wind-down: held`.

Add to `CollectionLogicTests` (inside the suite, after `heldAndPending`):
```swift
    @Test("A leaf earned in Evening can be opened that evening")
    func eveningLeaf() {
        var snapshot = planted()
        snapshot.openReveals(nil, at: at(2026, 10, 1, 21, 5), context: context)
        snapshot.record([.hoursSaved: 1], at: at(2026, 10, 2, 21), calendar: utc)
        snapshot.runEngine(at: at(2026, 10, 2, 21), context: context)
        #expect(snapshot.held(at: at(2026, 10, 2, 21, 30), context: context).isEmpty)
        #expect(snapshot.revealable(at: at(2026, 10, 2, 21, 30), context: context).map(\.speciesID) == ["rubrum"])
    }
```

In `MapleKit/Tests/MapleCoreTests/NightLedgerTests.swift`, in `revealAcrossWindDown()`, replace
```swift
        snapshot.raise(.restedNights, to: 14, at: at(2026, 10, 2, 21), calendar: utc)   // evening: held
        snapshot.runEngine(at: at(2026, 10, 2, 21), context: context)

        let sessionStart = at(2026, 10, 2, 22, 14)                     // Evening; wind-down starts 22:15
        let place = at(2026, 10, 2, 22, 16)
```
with
```swift
        snapshot.raise(.restedNights, to: 14, at: at(2026, 10, 2, 22, 20), calendar: utc)   // wind-down: held
        snapshot.runEngine(at: at(2026, 10, 2, 22, 20), context: context)

        let sessionStart = at(2026, 10, 2, 22, 14)                     // Evening; wind-down starts 22:15
        let place = at(2026, 10, 2, 22, 30)
```

In `MapleKit/Tests/MapleCoreTests/WeeklyScheduleTests.swift`, replace the `heldUntilTheWeekendMorning()` test with:
```swift
    @Test("Leaves earned in a Friday wind-down are held until the weekend morning")
    func heldUntilTheWeekendMorning() {
        // Friday's evening already runs to the weekend bedtime (00:30), so wind-down starts at 23:30.
        let leaf = LeafUnlock(speciesID: "rubrum", date: at(2026, 10, 9, 23, 45), season: .autumn, colourway: .autumn)
        #expect(RevealSchedule.releaseDate(for: leaf, schedule: week, calendar: utc) == at(2026, 10, 10, 8))
        #expect(RevealSchedule.isHeld(leaf, at: at(2026, 10, 10, 7, 59), schedule: week, calendar: utc))
        #expect(!RevealSchedule.isHeld(leaf, at: at(2026, 10, 10, 8), schedule: week, calendar: utc))
        let evening = LeafUnlock(speciesID: "rubrum", date: at(2026, 10, 9, 22), season: .autumn, colourway: .autumn)
        #expect(RevealSchedule.releaseDate(for: evening, schedule: week, calendar: utc) == at(2026, 10, 9, 22))
    }
```

In `MapleKit/Tests/MapleServicesTests/StoreTests.swift`, in `derived()`, replace
```swift
        store.record([.hoursSaved: 1], at: at(2026, 10, 2, 21))         // evening: held until morning
        #expect(store.revealable(at: at(2026, 10, 2, 21, 30)).isEmpty)
        #expect(store.held(at: at(2026, 10, 2, 21, 30)).map(\.speciesID) == ["rubrum"])
        // Moving bedtime later makes 21:00 part of the day, so the leaf is pending at once.
        store.schedule = .everyNight(SleepSchedule(bedtime: ClockTime(hour: 1), wake: ClockTime(hour: 9), windDownMinutes: 60))
        #expect(store.revealable(at: at(2026, 10, 2, 21, 30)).map(\.speciesID) == ["rubrum"])
```
with
```swift
        store.record([.hoursSaved: 1], at: at(2026, 10, 2, 22, 20))     // wind-down: held until morning
        #expect(store.revealable(at: at(2026, 10, 2, 22, 30)).isEmpty)
        #expect(store.held(at: at(2026, 10, 2, 22, 30)).map(\.speciesID) == ["rubrum"])
        // Moving bedtime later makes 22:20 part of the evening, so the leaf is pending at once.
        store.schedule = .everyNight(SleepSchedule(bedtime: ClockTime(hour: 1), wake: ClockTime(hour: 9), windDownMinutes: 60))
        #expect(store.revealable(at: at(2026, 10, 2, 22, 30)).map(\.speciesID) == ["rubrum"])
```

In `MapleKit/Tests/MapleCoreTests/TreeLayoutTests.swift:209`, change the comment's "very last was earned in the evening, so it is held" to "very last was earned in wind-down, so it is held".

- [ ] **Step 2: Run them to verify they fail**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -only-testing:MapleCoreTests/LeafEngineTests -only-testing:MapleCoreTests/CollectionLogicTests -only-testing:MapleCoreTests/WeeklyScheduleTests > "$WS/test.log" 2>&1; grep -E "Expectation failed|TEST (SUCCEEDED|FAILED)" "$WS/test.log" | head -5`
Expected: `** TEST FAILED **`, with `evening()` failing on `release(at(2026, 10, 10, 20, 15))` (still held until 06:00) and `eveningLeaf()` failing.

- [ ] **Step 3: Change the rule**

In `MapleKit/Sources/MapleCore/Collection/LeafEngine.swift`, replace the `RevealSchedule` doc comment and `releaseDate` with:
```swift
/// When an earned leaf may be opened (spec §3.3, §5.8, D8, D12; F1 design F1-12).
///
/// A leaf carries the moment its credit was earned. Leaves unlocked from the start of Wind-down until the next Morning
/// start are *held* and become *pending* at Morning start; all others, Evening's included, are pending at once.
/// Pending leaves open only in Morning, Day and Evening, never in Wind-down or Night. The first leaf is the exception:
/// it opens at the end of onboarding, at any hour.
public enum RevealSchedule {
    /// The moment `unlock` stops being held.
    public static func releaseDate(for unlock: LeafUnlock, schedule: WeeklySleepSchedule, calendar: Calendar) -> Date {
        if isFirstLeaf(unlock.speciesID) { return unlock.date }
        switch NowPhase.resolve(date: unlock.date, weekly: schedule, calendar: calendar) {
        case .morning, .day, .evening:
            return unlock.date
        case .windDown, .night:
            return PhaseWindows(weekly: schedule).nextStart(of: .morning, after: unlock.date, calendar: calendar)
        }
    }
```

In `MapleKit/Sources/MapleServices/Collection/CollectionStore.swift`, change the `recordSleep` doc line
`/// - Returns: Leaves unlocked, stamped `date`: pending at once in the morning and day, held from Evening on.`
to
`/// - Returns: Leaves unlocked, stamped `date`: pending at once until Wind-down, held from Wind-down until morning.`
and the `held(at:)` doc line `/// Leaves earned from Evening on, held until Morning.` to `/// Leaves earned in Wind-down or at night, held until Morning.`

- [ ] **Step 4: Update the docs**

- `docs/core-api.md:90`: change "Leaves earned from Evening until the next Morning are held" to "Leaves earned from Wind-down until the next Morning are held (F1-12: a leaf earned in Evening can open that evening)".
- `docs/core-api.md:232`: change "ones earned in the morning or day open at once and ones earned from Evening on are held until morning" to "ones earned before Wind-down open at once and ones earned in Wind-down or at night are held until morning".
- `docs/design/spec.md:268`: change "Unlocks with a timestamp from the start of Evening until the next Morning start are *held*" to "Unlocks with a timestamp from the start of Wind-down until the next Morning start are *held* (F1 design F1-12, which overrides the earlier Evening hold)".
- `docs/design/spec.md:855`: change "Leaves earned from Evening onward are held." to "Leaves earned from Wind-down onward are held."
- `docs/design/rewards.md:114`: change "Evening and overnight unlocks are held" to "Wind-down and overnight unlocks are held".

- [ ] **Step 5: Run the tests to verify they pass**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -only-testing:MapleCoreTests -only-testing:MapleServicesTests > "$WS/test.log" 2>&1; tail -3 "$WS/test.log"`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add MapleKit docs/core-api.md docs/design/spec.md docs/design/rewards.md
git commit -m "Leaves earned in Evening open at once; only Wind-down and night hold until morning (F1-12)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 15: Free builds, rung fill, rounded remainders, streak progress and the shifted clock

**Files:**
- Modify: `MapleKit/Sources/MapleCore/Collection/CollectionModels.swift` (`LeafAvailability.notInThisBuild`; `LeafProgress.floor` and `rungFraction`)
- Modify: `MapleKit/Sources/MapleCore/Collection/ShippedFeatures.swift` (the availability rule takes the blocking capability)
- Modify: `MapleKit/Sources/MapleCore/Collection/CollectionSnapshot+Rules.swift` (`CollectionContext.blocking`; `progress` and `availability`)
- Modify: `MapleKit/Sources/MapleCore/Collection/LeafProgressBuilder.swift` (`blocking`, `floor`)
- Modify: `MapleKit/Sources/MapleCore/Collection/NextLeafPicker.swift` (`homeCandidates`)
- Modify: `MapleKit/Sources/MapleCore/Home/LeafRemainder.swift` (hours round up)
- Modify: `MapleKit/Sources/MapleCore/Clock/MapleClock.swift` (`shifted(by:)`)
- Modify: `MapleKit/Sources/MapleDesign/Herbarium/HerbariumCopy.swift:17-31`, `MapleKit/Sources/MapleDesign/Herbarium/HerbariumModel.swift:60`, `App/Features/Health/HealthPrimerSheet.swift:83`
- Test: `MapleKit/Tests/MapleCoreTests/LeafProgressTests.swift`, `NextLeafPickerTests.swift`, `NowStateTests.swift`, `FocusCountersTests.swift`; `MapleKit/Tests/MapleDesignTests/HerbariumTests.swift`

**Interfaces:**
- Consumes: `BlockingCapability` (Task 7), `CollectionSnapshot.currentRun(at:context:)` (Task 13).
- Produces:
  - `LeafAvailability.notInThisBuild`;
  - `LeafAvailability(category:permissions:features:blocking:)`, where `blocking` defaults to `.screenTime`;
  - `CollectionContext.blocking: BlockingCapability` (default `.screenTime`);
  - `LeafProgressBuilder(permissions:features:blocking:catalog:)`;
  - `LeafProgress.floor: Double` (an init parameter defaulting to 0) and `LeafProgress.rungFraction: Double`;
  - `MapleClock.shifted(by:) -> MapleClock` and `MapleClock.offset: TimeInterval`.

**Rulings this task carries:**
- On a free build the Screen Time leaves read "Not available in this build" through the Herbarium's existing needs-permission state, with `turnOnTitle` nil, so no new `Status` case is needed and every view switch stays exhaustive.
- Focus streak rows show the current run as their progress (§3.4). Their unlocks still follow the counter, which is the best run.

- [ ] **Step 1: Write the failing tests**

In `MapleKit/Tests/MapleCoreTests/LeafProgressTests.swift`, add inside `AvailabilityTests`:
```swift
    @Test("A build that can't block shows Screen Time leaves as not in this build, whatever is granted")
    func notInThisBuild() {
        let all = ShippedFeatures.all
        #expect(LeafAvailability(category: .hoursSaved, permissions: [.screenTime], features: all, blocking: .unavailableInBuild) == .notInThisBuild)
        #expect(LeafAvailability(category: .hoursSaved, permissions: [], features: all, blocking: .preview) == .needsScreenTime)
        #expect(LeafAvailability(category: .restedNights, permissions: [.appleHealth], features: all, blocking: .unavailableInBuild) == .available)
        #expect(LeafAvailability(category: .hoursSaved, permissions: [], features: .current, blocking: .unavailableInBuild) == .dormant)
        #expect(!LeafAvailability.notInThisBuild.canBeTurnedOn)
    }
```
and inside `LeafProgressBuilderTests`:
```swift
    @Test("Each rung knows the rung below it, for the dial's fill")
    func rungFloor() {
        let rows = LeafProgressBuilder(permissions: [.screenTime], features: .all)
            .progress(counters: [.hoursSaved: 2.5], unlocks: [], history: [], today: today, calendar: utc)
        let hours = rows.filter { $0.category == .hoursSaved }
        #expect(hours.prefix(4).map(\.floor) == [0, 1, 2, 3])
        #expect(hours[0].rungFraction == 1)
        #expect(hours[2].rungFraction == 0.5)                                    // 2 → 3, at 2.5
        #expect(hours[3].rungFraction == 0)                                      // 3 → 5, not started
        #expect(hours[2].fraction == 2.5 / 3)                                    // other surfaces keep the whole ladder
    }
```

In `MapleKit/Tests/MapleCoreTests/NextLeafPickerTests.swift`, add inside the suite:
```swift
    @Test("A free build keeps Rested nights as Home's next leaf and asks for nothing it can't use")
    func freeBuild() {
        let rows = [
            progressRow("h1", .hoursSaved, threshold: 1, availability: .notInThisBuild, estimate: nil),
            progressRow("s1", .sessionsFinished, threshold: 1, availability: .notInThisBuild, estimate: nil),
            progressRow("r1", .restedNights, threshold: 3, current: 1, estimate: 2),
        ]
        let picker = NextLeafPicker(progress: rows)
        #expect(picker.next(pinned: nil)?.speciesID == "r1")
        #expect(picker.next(pinned: "h1")?.speciesID == "r1")
        #expect(NextLeafPicker(progress: Array(rows.prefix(2))).permissionPrompt() == nil)
    }
```

In `MapleKit/Tests/MapleCoreTests/NowStateTests.swift`, add inside `LeafRemainderTests`:
```swift
    @Test("Hours round up to the next minute, so a leaf a few seconds away never reads 0m")
    func hoursRoundUp() {
        #expect(remainder(.hoursSaved, 1, 1 - 10.0 / 3600) == "1m")
        #expect(remainder(.hoursSaved, 1, 1 - 61.0 / 3600) == "2m")
        #expect(remainder(.hoursSaved, 2, 1) == "1h")
    }
```
and inside `MapleClockTests`:
```swift
    @Test("A shifted clock runs from a demo instant and keeps ticking")
    func shifted() {
        let target = at(2030, 1, 1, 9)
        let clock = MapleClock.shifted(by: target.timeIntervalSinceNow)
        #expect(abs(clock.now().timeIntervalSince(target)) < 1)
        #expect(!clock.isFixed)
        #expect(clock.date(forTimeline: at(2026, 1, 1)) == at(2026, 1, 1).addingTimeInterval(clock.offset))
        #expect(MapleClock.live.offset == 0)
        #expect(MapleClock.fixed(target).offset == 0)
    }
```

In `MapleKit/Tests/MapleCoreTests/FocusCountersTests.swift`, add inside the suite:
```swift
    @Test("Streak progress shows the current run; streak leaves follow the best run")
    func streakProgress() {
        var snapshot = planted()
        var all = context
        all.features = .all
        all.permissions = [.appleHealth, .screenTime]
        let days = [19, 20, 21].map { LocalDay(year: 2026, month: 10, day: $0) }
        snapshot.applyFocus(days.map { credit(seconds: 1800, provenAt: at(2026, 10, $0.day, 12), day: $0) }, at: at(2026, 10, 21, 13), context: all)
        func sevenDays(_ date: Date) -> Double? {
            snapshot.progress(at: date, context: all).first { $0.category == .focusStreak && $0.threshold == 7 }?.current
        }
        #expect(sevenDays(at(2026, 10, 23, 12)) == 3)
        #expect(sevenDays(at(2026, 10, 25, 12)) == 0)
        #expect(snapshot.counters[.focusStreak] == 3)
    }

    @Test("A free build's context makes Screen Time leaves not in this build")
    func freeContext() {
        var free = context
        free.features = .all
        free.blocking = .unavailableInBuild
        #expect(planted().availability(of: .hoursSaved, context: free) == .notInThisBuild)
        #expect(planted().progress(at: at(2026, 10, 23, 12), context: free).first { $0.category == .hoursSaved }?.availability == .notInThisBuild)
    }
```

In `MapleKit/Tests/MapleDesignTests/HerbariumTests.swift`, in `permissions()`, add:
```swift
        #expect(HerbariumCopy.permissionLine(.notInThisBuild) == "Not available in this build")
        #expect(HerbariumCopy.turnOnTitle(.notInThisBuild) == nil)
```

- [ ] **Step 2: Run them to verify they fail**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -only-testing:MapleCoreTests -only-testing:MapleDesignTests/HerbariumTests > "$WS/test.log" 2>&1; grep -E "error:" "$WS/test.log" | head -5`
Expected: `error: type 'LeafAvailability' has no member 'notInThisBuild'`

- [ ] **Step 3: Write the availability rule**

In `MapleKit/Sources/MapleCore/Collection/CollectionModels.swift`, add to `LeafAvailability` after `case needsScreenTime`:
```swift
    /// The category needs Screen Time, which this build can't use (a free build): "Not available in this build",
    /// with no button. Home's pick treats it like `dormant`.
    case notInThisBuild
```

In `MapleKit/Sources/MapleCore/Collection/ShippedFeatures.swift`, replace the first `extension LeafAvailability` with:
```swift
extension LeafAvailability {
    /// Whether `category` can be earned: shipped first, then whether this build can block, then the required
    /// permission.
    /// - Parameter blocking: What this build can do (`MapleBuild`); a free build can't block at all.
    public init(
        category: RewardCategoryID, permissions: GrantedPermissions, features: ShippedFeatures,
        blocking: BlockingCapability = .screenTime
    ) {
        guard features.isShipped(category) else {
            self = .dormant
            return
        }
        switch RewardCategoryInfo(category).requirement {
        case .none:
            self = .available
        case .appleHealth:
            self = permissions.contains(.appleHealth) ? .available : .needsAppleHealth
        case .screenTime:
            guard blocking.canBlock else {
                self = .notInThisBuild
                return
            }
            self = permissions.contains(.screenTime) ? .available : .needsScreenTime
        }
    }
}
```
and add `import MapleFocusCore` under `import Foundation` in that file (`BlockingCapability` lives there).

In `MapleKit/Sources/MapleCore/Collection/CollectionSnapshot+Rules.swift`:
- add `import MapleFocusCore` under `import Foundation`;
- add to `CollectionContext`, after `sleepNeedMinutes`:
```swift
    /// What this build can do about blocking (`MapleBuild`). A free build's Screen Time leaves are "not in this build".
    public var blocking: BlockingCapability
```
- add the init parameter `blocking: BlockingCapability = .screenTime` after `sleepNeedMinutes`, and `self.blocking = blocking`;
- replace `progress(at:context:)` with:
```swift
    /// All 155 leaves. Focus streak rows show the current run as their progress (§3.4); their leaves follow the
    /// counter, which keeps the best run.
    public func progress(at date: Date, context: CollectionContext) -> [LeafProgress] {
        var shown = counters
        shown[.focusStreak] = Double(currentRun(at: date, context: context))
        return LeafProgressBuilder(permissions: permissions(in: context), features: context.features, blocking: context.blocking)
            .progress(counters: shown, unlocks: unlocks, history: history, today: LocalDay(date, calendar: context.calendar),
                      calendar: context.calendar)
    }
```
- in `availability(of:context:)`, pass `blocking: context.blocking`.

In `MapleKit/Sources/MapleCore/Collection/LeafProgressBuilder.swift`:
- add `import MapleFocusCore`;
- add `public var blocking: BlockingCapability` after `features`, the init parameter `blocking: BlockingCapability = .screenTime` after `features`, and `self.blocking = blocking`;
- pass `blocking: blocking` to `LeafAvailability(category:permissions:features:)`;
- replace `for rung in catalog.rungs(in: category.id) {` with
```swift
            var floor = 0.0
            for rung in catalog.rungs(in: category.id) {
                defer { floor = rung.threshold }
```
  and add `floor: floor` to the `LeafProgress(...)` call after `estimatedDays: estimate`.

In `MapleKit/Sources/MapleCore/Collection/CollectionModels.swift`, in `LeafProgress`:
- add after `estimatedDays`:
```swift
    /// The threshold of the rung below in this category's ladder, 0 for the first rung.
    public let floor: Double
```
- add the init parameter `floor: Double = 0` after `estimatedDays: Double?`, and `self.floor = floor`;
- add after `fraction`:
```swift
    /// Progress within this rung, from the rung below to the threshold, 0...1: the dial's leaf fill (F1 design §4.3).
    /// Every other surface uses `fraction`.
    public var rungFraction: Double {
        let span = threshold - floor
        return span > 0 ? min(1, max(0, (current - floor) / span)) : (current >= threshold ? 1 : 0)
    }
```

In `MapleKit/Sources/MapleCore/Collection/NextLeafPicker.swift`, in `homeCandidates`, replace `$0.availability != .dormant` with `$0.availability != .dormant && $0.availability != .notInThisBuild`, and add to its doc comment: "A free build's focus categories are `notInThisBuild`, so it keeps Rested nights."

In `MapleKit/Sources/MapleCore/Home/LeafRemainder.swift`, replace
```swift
            text = HomeFormat.duration(minutes: Int((remaining * 60).rounded()))
```
with
```swift
            // Up to the next minute: a leaf seconds away reads "1m", never "0m" (F1 design §3.6).
            text = HomeFormat.duration(minutes: Int((remaining * 60 - 1e-9).rounded(.up)))
```

- [ ] **Step 4: The shifted clock**

In `MapleKit/Sources/MapleCore/Clock/MapleClock.swift`:
- add `case shifted(TimeInterval)` to `Source`;
- add after `fixed(_:)`:
```swift
    /// The real time moved by `offset`, still ticking: a demo launch puts "now" inside the phase it asks for and lets
    /// a session run (F1 design §7.6). The demo focus time source uses the same offset, so Home and the dial agree.
    public static func shifted(by offset: TimeInterval) -> MapleClock {
        MapleClock(source: .shifted(offset))
    }

    /// How far a shifted clock is moved; 0 for the live and fixed clocks.
    public var offset: TimeInterval {
        if case .shifted(let offset) = source { offset } else { 0 }
    }
```
- in `now()`, add `case .shifted(let offset): Date().addingTimeInterval(offset)`;
- in `date(forTimeline:)`, add `case .shifted(let offset): timelineDate.addingTimeInterval(offset)`.

- [ ] **Step 5: Keep every switch exhaustive**

In `MapleKit/Sources/MapleDesign/Herbarium/HerbariumCopy.swift`, in `permissionLine`, add `case .notInThisBuild: "Not available in this build"` before `case .available, .dormant: nil`; in `turnOnTitle`, change `case .available, .dormant: nil` to `case .available, .dormant, .notInThisBuild: nil`. Update the doc line above `permissionLine` to `/// "Needs Apple Health", "Needs Screen Time", "Not available in this build"; nil when nothing is missing.`

In `MapleKit/Sources/MapleDesign/Herbarium/HerbariumModel.swift:60`, change `case .needsAppleHealth, .needsScreenTime: return .needsPermission(progress.availability)` to `case .needsAppleHealth, .needsScreenTime, .notInThisBuild: return .needsPermission(progress.availability)`.

In `App/Features/Health/HealthPrimerSheet.swift:83`, change `case .available, .dormant:` to `case .available, .dormant, .notInThisBuild:`.

- [ ] **Step 6: Run the tests and the build**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh > "$WS/test.log" 2>&1; tail -3 "$WS/test.log"; grep -c "warning:" "$WS/test.log"`
Expected: `** TEST SUCCEEDED **` and a warning count of `0`. The full suite runs here because the app target's switch changed.

- [ ] **Step 7: Commit**

```bash
git add MapleKit App/Features/Health/HealthPrimerSheet.swift
git commit -m "Free builds show Screen Time leaves as not in this build; rung fill, rounded-up hours, streak progress, shifted clock

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 16: The dial's arithmetic, the words and the start rules

Pure helpers F1b's screens read, each tested here so the screens stay thin.

**Files:**
- Create: `MapleKit/Sources/MapleCore/Focus/DialLayout.swift`
- Create: `MapleKit/Sources/MapleCore/Focus/FocusTimeText.swift`
- Create: `MapleKit/Sources/MapleCore/Focus/SessionForecast.swift`
- Create: `MapleKit/Sources/MapleCore/Focus/StartReadiness.swift`
- Create: `MapleKit/Sources/MapleCore/Focus/RecentIntentions.swift`
- Create: `MapleKit/Sources/MapleCore/Focus/FocusPreset.swift`
- Test: `MapleKit/Tests/MapleCoreTests/FocusScreenLogicTests.swift`

**Interfaces:**
- Consumes: `FocusVerb`, `Strictness`, `SelectionSummary`, `AwakeWindow`, `Reflection` (Tasks 2–3); `HomeFormat`, `NowPhase`, `LocalDay`.
- Produces:
  - `DialLayout(plannedMinutes:)`: `minutesPerMark`, `markCount`, `angle(ofMark:)`, `isLong(_:)`, `mark(atElapsed:)`, `angle(atMinute:)`, the proportions, and `DialLayout.length(turning:from:)`, `stepped(_:by:)`, `minimumMinutes` (20), `maximumMinutes` (180), `stepMinutes` (5), `degreesPerStep` (30);
  - `FocusTimeText.remaining(_:)`, `spokenRemaining(_:locale:)`, `length(minutes:)`, `spokenLength(minutes:locale:)`;
  - `SessionForecast(start:plannedSeconds:window:now:canCount:secondsToLeaf:leafName:roomLeftToday:firstEver:)`, with `leafMinute: Int?` and `countsLine: SessionForecast.CountsLine`; `CountsLine.text(locale:calendar:) -> String?`; `SessionForecast.leafLine(leaf:secondsToGo:)`, `openedLine(leaf:heldUntilMorning:)`, `openedLine(count:)`;
  - `StartReadiness` (`.ready(needsHold:)`, `.needsStartScreen(Reason)`) and `StartReadiness.check(strictness:blockingAllowed:selection:expiredTokens:isFirstSession:phase:countsLine:)`;
  - `RecentIntentions.Entry(text:reflection:at:)`, `RecentIntentions.chips(_:) -> [String]`, `RecentIntentions.normalized(_:) -> String?`, `limit` (3), `maximumLength` (60);
  - `FocusPreset` (`id`, `name`, `verb`, `minutes`, `hasBreak`, `appSetID`, `strictness`, `pendingStrictness`, `pendingFrom`), `FocusPreset.defaults(appSetID:)`, `strictness(on:)`, `changeStrictness(to:on:calendar:)`, `breakSeconds` (300), `nameLimit` (24), `maximumCount` (6), `normalizedName(_:)`.

- [ ] **Step 1: Write the failing tests**

`MapleKit/Tests/MapleCoreTests/FocusScreenLogicTests.swift`:
```swift
import Foundation
import Testing
@testable import MapleCore

@Suite("Dial layout")
struct DialLayoutTests {
    @Test("One mark a minute to an hour, then one per 2 and per 3 minutes; never more than 60")
    func marks() {
        #expect(DialLayout(plannedMinutes: 50).markCount == 50)
        #expect(DialLayout(plannedMinutes: 60).minutesPerMark == 1)
        #expect(DialLayout(plannedMinutes: 90).minutesPerMark == 2)
        #expect(DialLayout(plannedMinutes: 90).markCount == 45)
        #expect(DialLayout(plannedMinutes: 65).markCount == 33)
        #expect(DialLayout(plannedMinutes: 180).markCount == 60)
        #expect((20...180).allSatisfy { DialLayout(plannedMinutes: $0).markCount <= 60 })
    }

    @Test("Marks go clockwise from 12 o'clock; every 5th is long")
    func placement() {
        let dial = DialLayout(plannedMinutes: 50)
        #expect(dial.angle(ofMark: 0) == 0)
        #expect(abs(dial.angle(ofMark: 25) - .pi) < 1e-9)
        #expect(dial.isLong(0) && dial.isLong(5) && !dial.isLong(6))
        #expect(dial.mark(atElapsed: 0) == 0)
        #expect(dial.mark(atElapsed: 59.9) == 0)
        #expect(dial.mark(atElapsed: 60) == 1)
        #expect(dial.mark(atElapsed: 50 * 60) == 49)
        #expect(DialLayout(plannedMinutes: 90).mark(atElapsed: 3 * 60) == 1)
        #expect(abs(dial.angle(atMinute: 35) - 2 * .pi * 35 / 50) < 1e-9)
    }

    @Test("A 30° turn is 5 minutes, between 20 minutes and 3 hours")
    func turning() {
        #expect(DialLayout.length(turning: 30, from: 50) == 55)
        #expect(DialLayout.length(turning: 359, from: 50) == 105)
        #expect(DialLayout.length(turning: -29, from: 50) == 50)
        #expect(DialLayout.length(turning: -360, from: 50) == 20)
        #expect(DialLayout.length(turning: 3600, from: 50) == 180)
        #expect(DialLayout.stepped(50, by: -1) == 45)
        #expect(DialLayout.stepped(20, by: -1) == 20)
    }
}

@Suite("Focus time text")
struct FocusTimeTextTests {
    @Test("Whole minutes rounded up; seconds only in the last minute; 60 seconds reads 1m")
    func remaining() {
        #expect(FocusTimeText.remaining(32 * 60) == "32m")
        #expect(FocusTimeText.remaining(31 * 60 + 1) == "32m")
        #expect(FocusTimeText.remaining(90 * 60) == "1h 30m")
        #expect(FocusTimeText.remaining(60) == "1m")
        #expect(FocusTimeText.remaining(59.5) == "1m")
        #expect(FocusTimeText.remaining(59) == "0:59")
        #expect(FocusTimeText.remaining(4.2) == "0:05")
        #expect(FocusTimeText.remaining(0) == "0:00")
        #expect(FocusTimeText.remaining(-3) == "0:00")
    }

    @Test("Lengths and spoken forms")
    func lengths() {
        #expect(FocusTimeText.length(minutes: 50) == "50m")
        #expect(FocusTimeText.length(minutes: 60) == "1h")
        #expect(FocusTimeText.length(minutes: 90) == "1h 30m")
        #expect(FocusTimeText.spokenRemaining(32 * 60, locale: enGB) == "32 minutes left")
        #expect(FocusTimeText.spokenRemaining(45, locale: enGB) == "45 seconds left")
        #expect(FocusTimeText.spokenRemaining(1, locale: enGB) == "1 second left")
        #expect(FocusTimeText.spokenLength(minutes: 90, locale: enGB).contains("1 hour"))
    }
}

@Suite("Session forecast")
struct SessionForecastTests {
    private let window = AwakeWindow(start: at(2026, 10, 23, 6), end: at(2026, 10, 23, 23), windDown: at(2026, 10, 23, 22, 15))

    private func forecast(
        start: Date = at(2026, 10, 23, 14), minutes: Int = 50, now: Date? = nil, canCount: Bool = true, toLeaf: Int? = 35 * 60,
        room: Int = 21_600, firstEver: Bool = false
    ) -> SessionForecast {
        SessionForecast(start: start, plannedSeconds: minutes * 60, window: window, now: now ?? start, canCount: canCount,
                        secondsToLeaf: toLeaf, leafName: "Field maple", roomLeftToday: room, firstEver: firstEver)
    }

    private func line(_ forecast: SessionForecast) -> String? {
        forecast.countsLine.text(locale: enGB, calendar: utc)
    }

    @Test("A leaf in reach: the minute it opens")
    func reaches() {
        let result = forecast()
        #expect(result.leafMinute == 35)
        #expect(line(result) == "You'll reach Field maple at minute 35")
        #expect(forecast(start: at(2026, 10, 23, 14), now: at(2026, 10, 23, 14, 20), toLeaf: 15 * 60).leafMinute == 35)
    }

    @Test("Out of reach: no dot, and how far there is to go")
    func toward() {
        let far = forecast(toLeaf: 80 * 60)
        #expect(far.leafMinute == nil)
        #expect(line(far) == "Counts toward Field maple · 1h 20m to go")
        #expect(forecast(room: 20 * 60).leafMinute == nil)
    }

    @Test("Bedtime, the cap, a plain timer and the first session change the line")
    func states() {
        let crossing = forecast(start: at(2026, 10, 23, 22, 30), toLeaf: 10 * 60)
        #expect(crossing.leafMinute == 10)
        #expect(line(crossing) == "Counts until bed at 23:00")
        let late = forecast(start: at(2026, 10, 23, 23, 10))
        #expect(late.leafMinute == nil)
        #expect(line(late) == "After bedtime · this won't count")
        #expect(line(forecast(room: 0)) == "6h counted today · more won't add")
        #expect(line(forecast(canCount: false)) == nil)
        #expect(forecast(canCount: false).leafMinute == nil)
        #expect(line(forecast(firstEver: true)) == "Time your chosen apps stayed locked while you were awake.")
        #expect(forecast(start: at(2026, 10, 23, 5, 30), toLeaf: 10 * 60).leafMinute == 40)
    }

    @Test("Leaf lines")
    func leafLines() {
        #expect(SessionForecast.leafLine(leaf: "Field maple", secondsToGo: 17 * 60 - 20) == "Field maple · 17m to go")
        #expect(SessionForecast.openedLine(leaf: "Field maple", heldUntilMorning: false) == "Field maple is yours · it opens after this session")
        #expect(SessionForecast.openedLine(leaf: "Field maple", heldUntilMorning: true) == "Field maple is yours · it opens in the morning")
        #expect(SessionForecast.openedLine(count: 2) == "2 new leaves are yours")
    }
}

@Suite("Start readiness")
struct StartReadinessTests {
    private let reaches = SessionForecast.CountsLine.reaches(leaf: "Field maple", minute: 35)

    private func check(
        strictness: Strictness = .steady, allowed: Bool = true, selection: SelectionSummary? = FocusFixtures.blockSix,
        expired: Bool = false, first: Bool = false, phase: NowPhase = .day, line: SessionForecast.CountsLine? = nil
    ) -> StartReadiness {
        StartReadiness.check(strictness: strictness, blockingAllowed: allowed, selection: selection, expiredTokens: expired,
                             isFirstSession: first, phase: phase, countsLine: line ?? reaches)
    }

    @Test("Nothing to warn about: one tap, or a hold for Locked")
    func ready() {
        #expect(check() == .ready(needsHold: false))
        #expect(check(strictness: .locked) == .ready(needsHold: true))
    }

    @Test("Anything the start screen would warn about opens it instead")
    func warnings() {
        #expect(check(allowed: false) == .needsStartScreen(.blockingUnavailable))
        #expect(check(selection: nil) == .needsStartScreen(.noAppSet))
        #expect(check(selection: SelectionSummary(mode: .blockThese, apps: 0, sites: 0, categories: 0)) == .needsStartScreen(.noAppSet))
        #expect(check(selection: SelectionSummary(mode: .onlyThese, apps: 24, sites: 0, categories: 0)) == .needsStartScreen(.notQualifying))
        #expect(check(expired: true) == .needsStartScreen(.expiredTokens))
        #expect(check(first: true) == .needsStartScreen(.firstSession))
        #expect(check(phase: .windDown) == .needsStartScreen(.windDown))
        #expect(check(line: .afterBedtime) == .needsStartScreen(.afterBedtime))
        #expect(check(line: .capReached) == .needsStartScreen(.capReached))
        #expect(check(line: .untilBed(at(2026, 10, 23, 23))) == .needsStartScreen(.crossesBedtime))
    }
}

@Suite("Recent intentions")
struct RecentIntentionsTests {
    @Test("The last 3 distinct, carried-forward ones first, finished ones dropped")
    func chips() {
        let entries = [
            RecentIntentions.Entry(text: "Essay", reflection: .partly, at: at(2026, 10, 20, 9)),
            RecentIntentions.Entry(text: "Chemistry ch. 4", reflection: nil, at: at(2026, 10, 21, 9)),
            RecentIntentions.Entry(text: "Maths sheet", reflection: .allDone, at: at(2026, 10, 22, 9)),
            RecentIntentions.Entry(text: "chemistry ch. 4 ", reflection: nil, at: at(2026, 10, 22, 12)),
            RecentIntentions.Entry(text: "Spanish", reflection: .notYet, at: at(2026, 10, 23, 8)),
            RecentIntentions.Entry(text: "Reading", reflection: nil, at: at(2026, 10, 23, 9)),
        ]
        #expect(RecentIntentions.chips(entries) == ["Spanish", "Essay", "Reading"])
    }

    @Test("Intentions are trimmed and kept to 60 characters")
    func normalized() {
        #expect(RecentIntentions.normalized("  Essay  ") == "Essay")
        #expect(RecentIntentions.normalized("   ") == nil)
        #expect(RecentIntentions.normalized(String(repeating: "a", count: 80))?.count == 60)
    }
}

@Suite("Focus presets")
struct FocusPresetTests {
    @Test("Four presets to start: Study and Deep with a break")
    func defaults() {
        let presets = FocusPreset.defaults(appSetID: nil)
        #expect(presets.map(\.name) == ["Study", "Quick", "Deep", "Read"])
        #expect(presets.map(\.minutes) == [50, 25, 90, 30])
        #expect(presets.map(\.hasBreak) == [true, false, true, false])
        #expect(presets.map(\.verb) == [.study, .quick, .deep, .reading])
        #expect(presets.allSatisfy { $0.strictness == .steady })
    }

    @Test("Tighter strictness applies now; looser applies from the next day")
    func strictness() {
        let today = LocalDay(year: 2026, month: 10, day: 23)
        var preset = FocusPreset.defaults(appSetID: nil)[0]
        preset.changeStrictness(to: .locked, on: today, calendar: utc)
        #expect(preset.strictness(on: today) == .locked)
        preset.changeStrictness(to: .gentle, on: today, calendar: utc)
        #expect(preset.strictness(on: today) == .locked)
        #expect(preset.pendingStrictness == .gentle)
        let tomorrow = LocalDay(year: 2026, month: 10, day: 24)
        #expect(preset.strictness(on: tomorrow) == .gentle)
        preset.changeStrictness(to: .steady, on: tomorrow, calendar: utc)
        #expect(preset.strictness(on: tomorrow) == .steady)
        #expect(preset.pendingStrictness == nil)
    }

    @Test("Names are trimmed and kept to 24 characters; lengths stay in range")
    func limits() throws {
        #expect(FocusPreset.normalizedName("  Deep work  ") == "Deep work")
        #expect(FocusPreset.normalizedName("") == nil)
        #expect(FocusPreset.normalizedName(String(repeating: "x", count: 30))?.count == 24)
        var preset = FocusPreset.defaults(appSetID: nil)[0]
        preset.minutes = 500
        let data = try JSONEncoder().encode(preset)
        #expect(try JSONDecoder().decode(FocusPreset.self, from: data).minutes == 180)
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -only-testing:MapleCoreTests/DialLayoutTests -only-testing:MapleCoreTests/FocusTimeTextTests -only-testing:MapleCoreTests/SessionForecastTests -only-testing:MapleCoreTests/StartReadinessTests -only-testing:MapleCoreTests/RecentIntentionsTests -only-testing:MapleCoreTests/FocusPresetTests > "$WS/test.log" 2>&1; grep -E "error:" "$WS/test.log" | head -5`
Expected: `error: cannot find 'DialLayout' in scope`

- [ ] **Step 3: Write the dial layout and the time text**

`MapleKit/Sources/MapleCore/Focus/DialLayout.swift`:
```swift
import Foundation

/// The minute-marks dial's arithmetic (F1 design §4.1, §4.5). Angles are radians clockwise from 12 o'clock.
public struct DialLayout: Sendable, Equatable {
    public static let minimumMinutes = 20
    public static let maximumMinutes = 180
    public static let stepMinutes = 5
    /// 30° of turn is one 5-minute step, so a full turn is an hour.
    public static let degreesPerStep = 30.0

    /// Proportions on a 200-unit box.
    public static let box = 200.0
    public static let outerRadius = 92.0
    public static let longInnerRadius = 80.0
    public static let shortInnerRadius = 84.0
    public static let gapInnerRadius = 86.0
    public static let stroke = 1.6
    public static let currentStroke = 2.2
    public static let dotRadius = 99.0
    public static let dotSize = 2.6

    public let plannedMinutes: Int
    /// 1 up to an hour, 2 up to 2 hours, 3 beyond.
    public let minutesPerMark: Int
    public let markCount: Int

    public init(plannedMinutes: Int) {
        let minutes = max(1, plannedMinutes)
        self.plannedMinutes = minutes
        minutesPerMark = minutes <= 60 ? 1 : minutes <= 120 ? 2 : 3
        markCount = (minutes + minutesPerMark - 1) / minutesPerMark
    }

    /// Mark `index` of `markCount` sits at index / markCount of a full turn.
    public func angle(ofMark index: Int) -> Double {
        2 * .pi * Double(index) / Double(markCount)
    }

    public func isLong(_ index: Int) -> Bool { index % 5 == 0 }

    /// The mark the session is in after `seconds`, from 0 to the last mark.
    public func mark(atElapsed seconds: Double) -> Int {
        min(markCount - 1, max(0, Int(seconds / Double(60 * minutesPerMark))))
    }

    /// Where `minute` of the session falls (the leaf dot).
    public func angle(atMinute minute: Double) -> Double {
        2 * .pi * minute / Double(plannedMinutes)
    }

    /// The length after turning the dial by `degrees` from `minutes`: whole 5-minute steps, 20 minutes to 3 hours.
    public static func length(turning degrees: Double, from minutes: Int) -> Int {
        stepped(minutes, by: Int((degrees / degreesPerStep).rounded(.towardZero)))
    }

    /// `minutes` moved by `steps` 5-minute steps (VoiceOver's adjustable action), within the range.
    public static func stepped(_ minutes: Int, by steps: Int) -> Int {
        min(maximumMinutes, max(minimumMinutes, minutes + steps * stepMinutes))
    }
}
```

`MapleKit/Sources/MapleCore/Focus/FocusTimeText.swift`:
```swift
import Foundation

/// The Focus tab's time words (F1 design §4.4, F1-5): calm minutes, with seconds only in the last minute.
public enum FocusTimeText {
    /// "32m" (whole minutes, rounded up) from 60 seconds left; "0:SS" (seconds rounded up) below. 60 seconds reads
    /// "1m", never "0:60".
    public static func remaining(_ seconds: Double) -> String {
        let left = max(0, seconds)
        let wholeSeconds = Int((left - 1e-9).rounded(.up))
        if wholeSeconds >= 60 {
            return HomeFormat.duration(minutes: Int((left / 60 - 1e-9).rounded(.up)))
        }
        return wholeSeconds < 10 ? "0:0\(max(0, wholeSeconds))" : "0:\(wholeSeconds)"
    }

    /// "32 minutes left", "45 seconds left".
    public static func spokenRemaining(_ seconds: Double, locale: Locale) -> String {
        let left = max(0, seconds)
        let wholeSeconds = Int((left - 1e-9).rounded(.up))
        if wholeSeconds >= 60 {
            return HomeFormat.spokenDuration(minutes: Int((left / 60 - 1e-9).rounded(.up)), locale: locale) + " left"
        }
        return "\(max(0, wholeSeconds)) \(wholeSeconds == 1 ? "second" : "seconds") left"
    }

    /// "50m", "1h", "1h 30m".
    public static func length(minutes: Int) -> String {
        HomeFormat.duration(minutes: minutes)
    }

    /// "1 hour, 30 minutes".
    public static func spokenLength(minutes: Int, locale: Locale) -> String {
        HomeFormat.spokenDuration(minutes: minutes, locale: locale)
    }
}
```

- [ ] **Step 4: Write the forecast and start readiness**

`MapleKit/Sources/MapleCore/Focus/SessionForecast.swift`:
```swift
import Foundation
import MapleFocusCore

/// What a session can still count: the minute the next hours leaf would open (the dial's leaf dot), and the start
/// screen's counts line (F1 design §4.1, §5.1, §5.4, §5.8).
public struct SessionForecast: Sendable, Equatable {
    /// The start screen's counts line.
    public enum CountsLine: Sendable, Equatable {
        /// A plain timer, a selection that doesn't qualify, or nothing to say.
        case hidden
        /// The first session ever: the definition (focus spec §3.3).
        case definition
        case afterBedtime
        case capReached
        /// The session runs past bedtime, so it counts until then.
        case untilBed(Date)
        case reaches(leaf: String, minute: Int)
        case toward(leaf: String, minutesToGo: Int)

        public func text(locale: Locale, calendar: Calendar) -> String? {
            switch self {
            case .hidden: nil
            case .definition: "Time your chosen apps stayed locked while you were awake."
            case .afterBedtime: "After bedtime · this won't count"
            case .capReached: "6h counted today · more won't add"
            case .untilBed(let bedtime):
                "Counts until bed at \(HomeFormat.clock(HomeFormat.clockTime(of: bedtime, calendar: calendar), locale: locale))"
            case .reaches(let leaf, let minute): "You'll reach \(leaf) at minute \(minute)"
            case .toward(let leaf, let minutes): "Counts toward \(leaf) · \(HomeFormat.duration(minutes: minutes)) to go"
            }
        }
    }

    /// The minute from the countdown's start at which the next hours leaf would open; nil when it is out of this
    /// session's reach (the dot is hidden).
    public let leafMinute: Int?
    public let countsLine: CountsLine

    /// - Parameters:
    ///   - start: The countdown's start (now, on the start screen).
    ///   - now: The present; time before it has already been counted.
    ///   - secondsToLeaf: Counted seconds still needed for the next hours leaf (display credit included), or nil
    ///     when there is none.
    ///   - roomLeftToday: Seconds of today's 6 hours still free.
    public init(
        start: Date, plannedSeconds: Int, window: AwakeWindow, now: Date, canCount: Bool, secondsToLeaf: Int?,
        leafName: String?, roomLeftToday: Int, firstEver: Bool
    ) {
        let plannedEnd = start.addingTimeInterval(TimeInterval(plannedSeconds))
        let from = max(now, window.start)
        let countable = max(0, min(plannedEnd, window.end).timeIntervalSince(from))
        let reach = min(Double(max(0, roomLeftToday)), countable)
        if canCount, let needed = secondsToLeaf, needed > 0, Double(needed) <= reach {
            leafMinute = Int(((from.timeIntervalSince(start) + Double(needed)) / 60 - 1e-9).rounded(.up))
        } else {
            leafMinute = nil
        }

        if !canCount {
            countsLine = .hidden
        } else if now >= window.end {
            countsLine = .afterBedtime
        } else if roomLeftToday <= 0 {
            countsLine = .capReached
        } else if firstEver {
            countsLine = .definition
        } else if plannedEnd > window.end {
            countsLine = .untilBed(window.end)
        } else if let leafName, let minute = leafMinute {
            countsLine = .reaches(leaf: leafName, minute: minute)
        } else if let leafName, let needed = secondsToLeaf, needed > 0 {
            countsLine = .toward(leaf: leafName, minutesToGo: Int((Double(needed) / 60 - 1e-9).rounded(.up)))
        } else {
            countsLine = .hidden
        }
    }

    /// "Field maple · 17m to go".
    public static func leafLine(leaf: String, secondsToGo: Int) -> String {
        "\(leaf) · \(HomeFormat.duration(minutes: Int((Double(max(0, secondsToGo)) / 60 - 1e-9).rounded(.up)))) to go"
    }

    /// "Field maple is yours · it opens after this session", or "… opens in the morning" when it is held.
    public static func openedLine(leaf: String, heldUntilMorning: Bool) -> String {
        "\(leaf) is yours · it opens \(heldUntilMorning ? "in the morning" : "after this session")"
    }

    /// "2 new leaves are yours".
    public static func openedLine(count: Int) -> String {
        "\(count) new leaves are yours"
    }
}
```

`MapleKit/Sources/MapleCore/Focus/StartReadiness.swift`:
```swift
import Foundation
import MapleFocusCore

/// Whether a start from Home or the receipt's Again can go straight ahead, or must open the start screen to say
/// something first (F1 design §5.1, F1-20).
public enum StartReadiness: Sendable, Hashable {
    /// One tap starts it; Locked needs a hold, everywhere.
    case ready(needsHold: Bool)
    case needsStartScreen(Reason)

    /// What the start screen would show, in the order it is checked.
    public enum Reason: Sendable, Hashable {
        case blockingUnavailable, noAppSet, notQualifying, expiredTokens, firstSession, windDown
        case afterBedtime, capReached, crossesBedtime
    }

    public static func check(
        strictness: Strictness, blockingAllowed: Bool, selection: SelectionSummary?, expiredTokens: Bool,
        isFirstSession: Bool, phase: NowPhase, countsLine: SessionForecast.CountsLine
    ) -> StartReadiness {
        guard blockingAllowed else { return .needsStartScreen(.blockingUnavailable) }
        guard let selection, !selection.isEmpty else { return .needsStartScreen(.noAppSet) }
        guard selection.qualifies else { return .needsStartScreen(.notQualifying) }
        if expiredTokens { return .needsStartScreen(.expiredTokens) }
        if isFirstSession { return .needsStartScreen(.firstSession) }
        if phase == .windDown || phase == .night { return .needsStartScreen(.windDown) }
        switch countsLine {
        case .afterBedtime: return .needsStartScreen(.afterBedtime)
        case .capReached: return .needsStartScreen(.capReached)
        case .untilBed: return .needsStartScreen(.crossesBedtime)
        case .hidden, .definition, .reaches, .toward: return .ready(needsHold: strictness == .locked)
        }
    }
}
```

- [ ] **Step 5: Write intentions and presets**

`MapleKit/Sources/MapleCore/Focus/RecentIntentions.swift`:
```swift
import Foundation
import MapleFocusCore

/// The intention chips above the "What's this for?" field (F1 design §5.16, §5.8): the last 3 distinct intentions,
/// with ones the member said were "Partly" or "Not yet" done first. "All done" drops an intention.
public enum RecentIntentions {
    public static let limit = 3
    public static let maximumLength = 60

    public struct Entry: Sendable, Equatable {
        public var text: String
        public var reflection: Reflection?
        public var at: Date

        public init(text: String, reflection: Reflection?, at: Date) {
            self.text = text
            self.reflection = reflection
            self.at = at
        }
    }

    public static func chips(_ entries: [Entry]) -> [String] {
        var seen = Set<String>()
        var carried: [String] = []
        var others: [String] = []
        for entry in entries.sorted(by: { $0.at > $1.at }) {
            guard let text = normalized(entry.text), seen.insert(text.lowercased()).inserted else { continue }
            switch entry.reflection {
            case .allDone: continue
            case .partly, .notYet: carried.append(text)
            case nil: others.append(text)
            }
        }
        return Array((carried + others).prefix(limit))
    }

    /// Trimmed and kept to 60 characters; nil when empty.
    public static func normalized(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(maximumLength))
    }
}
```

`MapleKit/Sources/MapleCore/Focus/FocusPreset.swift`:
```swift
import Foundation
import MapleFocusCore

/// A Focus preset (F1 design §5.13): a named length, verb, optional locked break, app set and strictness.
public struct FocusPreset: Codable, Sendable, Equatable, Identifiable {
    public static let nameLimit = 24
    public static let maximumCount = 6
    /// One 5-minute locked break inside the planned length (§5.5).
    public static let breakSeconds = 5 * 60

    public var id: UUID
    public var name: String
    public var verb: FocusVerb
    public var minutes: Int
    public var hasBreak: Bool
    public var appSetID: UUID?
    public var strictness: Strictness
    /// A looser strictness waiting for the next day ("Steady starts tomorrow").
    public var pendingStrictness: Strictness?
    public var pendingFrom: LocalDay?

    public init(
        id: UUID = UUID(), name: String, verb: FocusVerb, minutes: Int, hasBreak: Bool, appSetID: UUID?,
        strictness: Strictness = .steady, pendingStrictness: Strictness? = nil, pendingFrom: LocalDay? = nil
    ) {
        self.id = id
        self.name = name
        self.verb = verb
        self.minutes = minutes
        self.hasBreak = hasBreak
        self.appSetID = appSetID
        self.strictness = strictness
        self.pendingStrictness = pendingStrictness
        self.pendingFrom = pendingFrom
    }

    /// Study 50m and Deep 90m with a break, Quick 25m and Read 30m without.
    public static func defaults(appSetID: UUID?) -> [FocusPreset] {
        [
            FocusPreset(name: "Study", verb: .study, minutes: 50, hasBreak: true, appSetID: appSetID),
            FocusPreset(name: "Quick", verb: .quick, minutes: 25, hasBreak: false, appSetID: appSetID),
            FocusPreset(name: "Deep", verb: .deep, minutes: 90, hasBreak: true, appSetID: appSetID),
            FocusPreset(name: "Read", verb: .reading, minutes: 30, hasBreak: false, appSetID: appSetID),
        ]
    }

    /// The strictness a session started on `day` uses.
    public func strictness(on day: LocalDay) -> Strictness {
        if let pendingStrictness, let pendingFrom, day >= pendingFrom { return pendingStrictness }
        return strictness
    }

    /// A tighter level applies at once; a looser one from the next day.
    public mutating func changeStrictness(to new: Strictness, on day: LocalDay, calendar: Calendar) {
        let current = strictness(on: day)
        strictness = current
        if new >= current {
            strictness = new
            pendingStrictness = nil
            pendingFrom = nil
        } else {
            pendingStrictness = new
            pendingFrom = day.adding(days: 1, calendar: calendar)
        }
    }

    /// Trimmed and kept to 24 characters; nil when empty.
    public static func normalizedName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(nameLimit))
    }

    // MARK: Codable (a length outside the range is brought into it)

    private enum CodingKeys: String, CodingKey {
        case id, name, verb, minutes, hasBreak, appSetID, strictness, pendingStrictness, pendingFrom
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        verb = (try? c.decode(FocusVerb.self, forKey: .verb)) ?? .focus
        let minutes = (try? c.decode(Int.self, forKey: .minutes)) ?? 50
        self.minutes = min(DialLayout.maximumMinutes, max(DialLayout.minimumMinutes, minutes))
        hasBreak = (try? c.decode(Bool.self, forKey: .hasBreak)) ?? false
        appSetID = try? c.decodeIfPresent(UUID.self, forKey: .appSetID)
        strictness = (try? c.decode(Strictness.self, forKey: .strictness)) ?? .steady
        pendingStrictness = try? c.decodeIfPresent(Strictness.self, forKey: .pendingStrictness)
        pendingFrom = try? c.decodeIfPresent(LocalDay.self, forKey: .pendingFrom)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(verb, forKey: .verb)
        try c.encode(minutes, forKey: .minutes)
        try c.encode(hasBreak, forKey: .hasBreak)
        try c.encodeIfPresent(appSetID, forKey: .appSetID)
        try c.encode(strictness, forKey: .strictness)
        try c.encodeIfPresent(pendingStrictness, forKey: .pendingStrictness)
        try c.encodeIfPresent(pendingFrom, forKey: .pendingFrom)
    }
}
```
`LocalDay` must be `Comparable` for `day >= pendingFrom`; it already is (the snapshot sorts `tendedDays`).

- [ ] **Step 6: Run the tests to verify they pass**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -only-testing:MapleCoreTests > "$WS/test.log" 2>&1; tail -3 "$WS/test.log"`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add MapleKit/Sources/MapleCore/Focus MapleKit/Tests/MapleCoreTests/FocusScreenLogicTests.swift
git commit -m "Focus screen logic: dial layout, calm time text, session forecast, start readiness, intentions and presets

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 17: Reward wording follows the counting rules

**Files:**
- Modify: `Scripts/generate-rewards.py:24` (`LANDMARKS`), `:37` and `:40` (the two metrics), `:104` (`unlock_text`)
- Regenerate: `MapleKit/Sources/MapleCore/Resources/rewards.json`
- Modify: `MapleKit/Sources/MapleCore/Rewards/RewardCategoryInfo.swift` (the two definitions)
- Modify: `docs/design/rewards.md:22`, `:103`, `:107`, `:187`, `:188`
- Test: `MapleKit/Tests/MapleCoreTests/RewardCatalogTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: rung `unlockText` without landmark lines ("Save 24 hours"); the new `sessions_finished` and `focus_streak` metrics; the new Herbarium definitions.

- [ ] **Step 1: Change the tests**

In `MapleKit/Tests/MapleCoreTests/RewardCatalogTests.swift`, in `pins()`, replace the last two expectations with:
```swift
        // Landmark rungs keep their famous maples but carry no figurative line (F1 design §3.6).
        #expect(RewardCatalog.shared.rungs(in: .hoursSaved).first { $0.threshold == 24 }?.unlockText == "Save 24 hours")
        #expect(RewardCatalog.shared.rungs(in: .hoursSaved).last?.unlockText == "Save 2,000 hours")
        #expect(RewardCatalog.shared.assignments.allSatisfy { !$0.unlockText.contains(" · ") })
```
and in `info()`, add:
```swift
        #expect(RewardCategoryInfo(.sessionsFinished).definition
            == "A session you started that ran to its planned end, with at least 20 minutes locked while you were awake. Up to 3 count a day.")
        #expect(RewardCategoryInfo(.focusStreak).definition
            == "Days in a row with a finished session. Up to 2 rest days in any 7 can bridge a gap.")
        #expect(RewardCatalog.shared.category(.sessionsFinished)?.metric.contains("At most 3 a day") == true)
        #expect(RewardCatalog.shared.category(.focusStreak)?.metric.contains("calendar week") == false)
```

- [ ] **Step 2: Run them to verify they fail**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -only-testing:MapleCoreTests/RewardCatalogTests > "$WS/test.log" 2>&1; grep -E "Expectation failed" "$WS/test.log" | head -3`
Expected: failures on `"Save 24 hours · A day back"` against `"Save 24 hours"`, and on the definitions.

- [ ] **Step 3: Change the generator and regenerate**

In `Scripts/generate-rewards.py`:
- delete the line `LANDMARKS = {24: "A day back", 168: "A week back", 720: "A month back", 2000: "A working year back"}`;
- in `unlock_text`, replace
```python
        text = "Save 1 hour" if n == 1 else f"Save {n:,} hours"
        return f"{text} · {LANDMARKS[n]}" if n in LANDMARKS else text
```
with
```python
        return "Save 1 hour" if n == 1 else f"Save {n:,} hours"
```
- replace the `sessions_finished` metric string with
```python
     "Sessions the member started that ran to their planned end, with at least 20 locked awake minutes making up at "
     "least 3/4 of the planned length. At most 3 a day, in the order they ended. F1 design §3.4.",
```
- replace the `focus_streak` metric string with
```python
     "The best run of Maple days with a finished session. Missed days between finished days are rest days, at most 2 "
     "in any 7 days in a row; a one-day gap across a time-zone change is neutral. F1 design §3.4.",
```
- in the `PINS` comments, change `# Japanese maple: "A day back"`, `# Paperbark maple: "A week back"` and `# Fullmoon maple: "A month back"` to `# Japanese maple, 24 h`, `# Paperbark maple, 168 h` and `# Fullmoon maple, 720 h`.

Run: `python3 -I Scripts/generate-rewards.py && git diff --stat MapleKit/Sources/MapleCore/Resources/rewards.json`
Expected: `rewards.json` changes in exactly 6 places: the 4 landmark unlock texts and the 2 metrics. Check with `git diff MapleKit/Sources/MapleCore/Resources/rewards.json | grep -c '^-[^-]'` → `6`.

- [ ] **Step 4: Change the definitions**

In `MapleKit/Sources/MapleCore/Rewards/RewardCategoryInfo.swift`, change the `sessionsFinished` definition to
`"A session you started that ran to its planned end, with at least 20 minutes locked while you were awake. Up to 3 count a day."`
and the `focusStreak` definition to
`"Days in a row with a finished session. Up to 2 rest days in any 7 can bridge a gap."`

- [ ] **Step 5: Update rewards.md**

In `docs/design/rewards.md`:
- `:22`: replace `Landmark rungs carry a line: 24h "A day back", 168h "A week back", 720h "A month back" and 2,000h "A working year back".` with `Landmark rungs (24h, 168h, 720h, 2,000h) hold famous maples but carry no extra line (F1 design §3.6).`
- `:103`: replace `planned at 15 min to 3 h` with `planned at 20 min to 3 h (F1-15)`.
- `:107`: replace `at most 4 finished sessions count a day, any 2 days a week are rest days for the Focus streak, and Away pauses it.` with `at most 3 finished sessions count a day, and the Focus streak bridges up to 2 rest days in any 7 days in a row (F1 design §3.4).`
- `:187` and `:188`: replace the two category descriptions with the new metrics' wording.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -only-testing:MapleCoreTests > "$WS/test.log" 2>&1; tail -3 "$WS/test.log"`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add Scripts/generate-rewards.py MapleKit/Sources/MapleCore/Resources/rewards.json MapleKit/Sources/MapleCore/Rewards/RewardCategoryInfo.swift MapleKit/Tests/MapleCoreTests/RewardCatalogTests.swift docs/design/rewards.md
git commit -m "Reward wording: no landmark lines; finished sessions and the streak follow the F1 counting rules

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 18: Session-end and study reminders

**Files:**
- Modify: `MapleKit/Sources/MapleCore/Notifications/ReminderPlan.swift`
- Modify: `MapleKit/Sources/MapleServices/Notifications/NotificationScheduler.swift` (absolute triggers)
- Modify: `MapleKit/Sources/MapleServices/Settings/AppSettings.swift` (two fields)
- Create: `MapleKit/Sources/MapleServices/Notifications/ReminderInputs.swift` (moved from the app)
- Delete: `App/Features/Notifications/ReminderInputs.swift`
- Modify: `App/Features/Notifications/ReminderUpkeep.swift` (the new call)
- Test: `MapleKit/Tests/MapleCoreTests/ReminderPlanTests.swift`, `MapleKit/Tests/MapleServicesTests/NotificationSchedulerTests.swift`

**Interfaces:**
- Consumes: `UpcomingNight`, `NowPhase`, `WeeklySleepSchedule`, `CollectionStore`, `ScheduleStore`, `AppSettings`.
- Produces:
  - `ReminderKind.sessionEnd` and `.studyReminder`;
  - `ReminderRequest.isAbsolute: Bool` (an init parameter defaulting to false);
  - `ReminderSettings(windDown:sessionEnd:studyReminder:)`, with `sessionEnd` defaulting to true and `studyReminder: ClockTime?` to nil;
  - `ReminderPlan.RunningSession(id:plannedEnd:presetName:plannedMinutes:isPlainTimer:)`;
  - `ReminderPlan.Input` gains `schedule`, `runningSession` and `lastSessionStart` (all defaulted);
  - `ReminderCopy.sessionDoneTitle`, `timerDoneTitle`, `sessionEndBody(presetName:minutes:isPlainTimer:)`, `studyTitle`, `studyBody`;
  - `AppSettings.sessionEndReminder: Bool` and `AppSettings.studyReminderTime: ClockTime?`;
  - `ReminderInputs.plan(collection:schedule:settings:windDownOpenedAt:runningSession:lastSessionStart:now:locale:) -> ReminderPlan` (MapleServices).

**Rulings this task carries:**
- `ReminderUpkeep` passes no running session or last start yet: F1b wires `FocusSessionStore` into the app's environment and passes them then. Until then the app schedules exactly what it does today.
- The notifications primer's new copy (§6) is a screen change, so it is in F1b.

- [ ] **Step 1: Write the failing tests**

In `MapleKit/Tests/MapleCoreTests/ReminderPlanTests.swift`, change the `onlyWindDown()` test's name to `"Without a session or a study time, wind-down is the only reminder: nothing in the morning, ever"` and its first line to `#expect(ReminderKind.allCases == [.windDown, .sessionEnd, .studyReminder])`; then add at the end of the file:
```swift
@Suite("Session and study reminders")
struct FocusReminderTests {
    private func plan(
        now: Date, settings: ReminderSettings = .allOn, running: ReminderPlan.RunningSession? = nil, lastStart: Date? = nil
    ) -> ReminderPlan {
        ReminderPlan(.init(
            nights: UpcomingNight.nights(for: .standard, around: now, calendar: utc), settings: settings, now: now,
            calendar: utc, locale: enGB, schedule: .standard, runningSession: running, lastSessionStart: lastStart
        ))
    }

    private func session(endingAt end: Date, plain: Bool = false) -> ReminderPlan.RunningSession {
        ReminderPlan.RunningSession(id: FocusFixtures.session, plannedEnd: end, presetName: "Study", plannedMinutes: 50, isPlainTimer: plain)
    }

    @Test("A running session's end is one absolute request, even after bedtime")
    func sessionEnd() throws {
        let result = plan(now: at(2026, 10, 12, 22, 50), running: session(endingAt: at(2026, 10, 12, 23, 40)))
        let end = try #require(result.of(.sessionEnd).first)
        #expect(result.of(.sessionEnd).count == 1)
        #expect(end.fireDate == at(2026, 10, 12, 23, 40))
        #expect(end.isAbsolute)
        #expect(end.id == "maple.reminder.sessionEnd.\(FocusFixtures.session.uuidString.lowercased())")
        #expect(end.title == "Session done")
        #expect(end.body == "Study, 50 minutes")
        let timer = try #require(plan(now: at(2026, 10, 12, 14), running: session(endingAt: at(2026, 10, 12, 14, 50), plain: true)).of(.sessionEnd).first)
        #expect(timer.title == "Timer done")
        #expect(timer.body == "50 minutes")
    }

    @Test("No end reminder when it's switched off or the end has passed")
    func noSessionEnd() {
        let running = session(endingAt: at(2026, 10, 12, 14, 50))
        #expect(plan(now: at(2026, 10, 12, 14), settings: ReminderSettings(sessionEnd: false), running: running).of(.sessionEnd).isEmpty)
        #expect(plan(now: at(2026, 10, 12, 14, 51), running: running).of(.sessionEnd).isEmpty)
    }

    @Test("The study reminder comes once a day in the Day phase, skipping days a session has started")
    func study() {
        let settings = ReminderSettings(studyReminder: ClockTime(hour: 16))
        let week = plan(now: at(2026, 10, 12, 9), settings: settings).of(.studyReminder)
        #expect(week.count == 7)
        #expect(week.first?.fireDate == at(2026, 10, 12, 16))
        #expect(week.first?.title == "Ready to study?")
        #expect(week.first?.body == "Your apps can rest for a while.")
        #expect(!(week.first?.isAbsolute ?? true))
        let started = plan(now: at(2026, 10, 12, 9), settings: settings, lastStart: at(2026, 10, 12, 8, 30)).of(.studyReminder)
        #expect(started.first?.fireDate == at(2026, 10, 13, 16))
        #expect(plan(now: at(2026, 10, 12, 9), settings: ReminderSettings(studyReminder: ClockTime(hour: 21))).of(.studyReminder).isEmpty)
        #expect(plan(now: at(2026, 10, 12, 9), settings: ReminderSettings(studyReminder: ClockTime(hour: 8))).of(.studyReminder).isEmpty)
        #expect(plan(now: at(2026, 10, 12, 9)).of(.studyReminder).isEmpty)
    }
}
```

In `MapleKit/Tests/MapleServicesTests/NotificationSchedulerTests.swift`:
- in `ReminderSettingsTests.persisted()`, change `#expect(reloaded.reminders == .allOff)` to `#expect(reloaded.reminders == ReminderSettings(windDown: false))`;
- add inside `NotificationSchedulerTests`:
```swift
    @Test("A session's end is scheduled after its real time left, and goes when the session does")
    func sessionEnd() async throws {
        let center = FakeNotificationCenter()
        let scheduler = NotificationScheduler(center: center, clock: .fixed(now))
        let running = ReminderPlan.RunningSession(id: UUID(), plannedEnd: now.addingTimeInterval(50 * 60), presetName: "Study",
                                                  plannedMinutes: 50, isPlainTimer: false)
        let withSession = ReminderPlan(.init(
            nights: UpcomingNight.nights(for: .standard, around: now, calendar: utc), settings: .allOn, now: now,
            calendar: utc, locale: Locale(identifier: "en_GB"), runningSession: running
        ))
        await scheduler.reschedule(plan: withSession)
        let end = try #require(center.pending.values.first { $0.request.kind == .sessionEnd })
        #expect(end.trigger == .after(50 * 60))
        await scheduler.reschedule(plan: plan(at: now))
        #expect(!center.pending.values.contains { $0.request.kind == .sessionEnd })
    }
```
- add inside `ReminderSettingsTests`:
```swift
    @Test("The session-end switch is on and the study reminder off by default; both are saved")
    func focusReminders() throws {
        let url = try temporaryDirectory().appendingPathComponent(AppSettings.file)
        let settings = AppSettings(storage: JSONStorage(.file(url)), regionCode: "GB")
        #expect(settings.sessionEndReminder)
        #expect(settings.studyReminderTime == nil)
        settings.sessionEndReminder = false
        settings.studyReminderTime = ClockTime(hour: 16)
        let reloaded = AppSettings(storage: JSONStorage(.file(url)), regionCode: "GB")
        #expect(reloaded.reminders == ReminderSettings(windDown: true, sessionEnd: false, studyReminder: ClockTime(hour: 16)))
        let old = #"{"version":1,"hemisphere":"northern","sleepGoalMinutes":450,"revealSound":false,"windDownReminder":true}"#
        let snapshot = try JSONDecoder().decode(SettingsSnapshot.self, from: Data(old.utf8))
        #expect(snapshot.sessionEndReminder)
        #expect(snapshot.studyReminder == nil)
    }

    @Test("Reminder inputs come from the stores")
    func inputs() {
        let collection = CollectionStore(storage: JSONStorage(.memory), context: testContext, now: at(2026, 10, 12, 9))
        let schedule = ScheduleStore(storage: JSONStorage(.memory), collection: collection)
        let settings = AppSettings(storage: JSONStorage(.memory), regionCode: "GB")
        let running = ReminderPlan.RunningSession(id: UUID(), plannedEnd: at(2026, 10, 12, 14, 50), presetName: "Study",
                                                  plannedMinutes: 50, isPlainTimer: false)
        let plan = ReminderInputs.plan(collection: collection, schedule: schedule, settings: settings, windDownOpenedAt: nil,
                                       runningSession: running, lastSessionStart: nil, now: at(2026, 10, 12, 14),
                                       locale: Locale(identifier: "en_GB"))
        #expect(plan.requests.contains { $0.kind == .sessionEnd })
        #expect(plan.requests.contains { $0.kind == .windDown })
    }
```

- [ ] **Step 2: Run them to verify they fail**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -only-testing:MapleCoreTests/FocusReminderTests -only-testing:MapleServicesTests/NotificationSchedulerTests -only-testing:MapleServicesTests/ReminderSettingsTests > "$WS/test.log" 2>&1; grep -E "error:" "$WS/test.log" | head -5`
Expected: `error: type 'ReminderPlan' has no member 'RunningSession'`

- [ ] **Step 3: Extend the plan**

In `MapleKit/Sources/MapleCore/Notifications/ReminderPlan.swift`:
- change the `ReminderKind` doc comment to `/// Maple's local notifications: wind-down, a session's end, and the opt-in study reminder. There is no morning notification (rewards.md; focus spec §8), so a waiting leaf is only ever shown in the app.` and add after `case windDown`:
```swift
    /// "Session done · Study, 50 minutes" at a running session's planned end (F1 design §6, F1-16).
    case sessionEnd
    /// "Ready to study?", once a day at the member's time, in the Day phase; off by default (F1-4).
    case studyReminder
```
- add to `ReminderRequest`, after `playsSound`:
```swift
    /// Fires after the real time left rather than at a wall-clock time, so a clock or time-zone change can't move it
    /// (a session's end).
    public var isAbsolute: Bool
```
  with the init parameter `isAbsolute: Bool = false` after `playsSound: Bool`, and `self.isAbsolute = isAbsolute`;
- replace `ReminderSettings` with:
```swift
/// Which reminders the member wants (Settings). Wind-down and a session's end are on until turned off; the study
/// reminder is off until the member picks its time. Nothing is sent until iOS allows Maple's notifications.
public struct ReminderSettings: Sendable, Hashable {
    public var windDown: Bool
    public var sessionEnd: Bool
    /// The study reminder's time; nil when it is off.
    public var studyReminder: ClockTime?

    public init(windDown: Bool = true, sessionEnd: Bool = true, studyReminder: ClockTime? = nil) {
        self.windDown = windDown
        self.sessionEnd = sessionEnd
        self.studyReminder = studyReminder
    }

    public static let allOn = ReminderSettings()
    public static let allOff = ReminderSettings(windDown: false, sessionEnd: false, studyReminder: nil)

    public func allows(_ kind: ReminderKind) -> Bool {
        switch kind {
        case .windDown: windDown
        case .sessionEnd: sessionEnd
        case .studyReminder: studyReminder != nil
        }
    }
}
```
- add to `ReminderCopy`:
```swift
    public static let sessionDoneTitle = "Session done"
    public static let timerDoneTitle = "Timer done"
    public static let studyTitle = "Ready to study?"
    public static let studyBody = "Your apps can rest for a while."

    /// "Study, 50 minutes", or "50 minutes" for a plain timer. Fixed when the session starts, so it never says "saved".
    public static func sessionEndBody(presetName: String, minutes: Int, isPlainTimer: Bool) -> String {
        isPlainTimer ? "\(minutes) minutes" : "\(presetName), \(minutes) minutes"
    }
```
- in `ReminderPlan`, add before `public struct Input`:
```swift
    /// The session running now, for its end reminder.
    public struct RunningSession: Sendable, Hashable {
        public var id: UUID
        public var plannedEnd: Date
        public var presetName: String
        public var plannedMinutes: Int
        public var isPlainTimer: Bool

        public init(id: UUID, plannedEnd: Date, presetName: String, plannedMinutes: Int, isPlainTimer: Bool) {
            self.id = id
            self.plannedEnd = plannedEnd
            self.presetName = presetName
            self.plannedMinutes = plannedMinutes
            self.isPlainTimer = isPlainTimer
        }
    }
```
- add to `Input`, after `locale`:
```swift
        /// The weekly schedule, for the study reminder's Day phase.
        public var schedule: WeeklySleepSchedule
        public var runningSession: RunningSession?
        /// When the latest session started: the study reminder skips that day.
        public var lastSessionStart: Date?
```
  with the init parameters `schedule: WeeklySleepSchedule = .standard, runningSession: RunningSession? = nil, lastSessionStart: Date? = nil` after `locale: Locale`, and their assignments;
- in `init(_ input:)`, after the `for night in nights { … }` loop, add:
```swift
        if let end = Self.sessionEnd(input: input), end.fireDate > input.now, end.fireDate <= horizon {
            requests.append(end)                       // a session's end is exempt from the night rule
        }
        for study in Self.studyReminders(input: input) where study.fireDate > input.now && study.fireDate <= horizon {
            requests.append(study)
        }
```
- add to the `// MARK: Rules` section:
```swift
    private static func sessionEnd(input: Input) -> ReminderRequest? {
        guard input.settings.sessionEnd, let session = input.runningSession else { return nil }
        let kind = ReminderKind.sessionEnd
        return ReminderRequest(
            id: kind.identifierPrefix + session.id.uuidString.lowercased(), kind: kind, fireDate: session.plannedEnd,
            calendar: input.calendar,
            title: session.isPlainTimer ? ReminderCopy.timerDoneTitle : ReminderCopy.sessionDoneTitle,
            body: ReminderCopy.sessionEndBody(presetName: session.presetName, minutes: session.plannedMinutes,
                                              isPlainTimer: session.isPlainTimer),
            threadID: kind.threadID, interruption: .active, playsSound: true, isAbsolute: true
        )
    }

    /// One a day at the member's time while it falls in the Day phase, skipping the day the latest session started.
    private static func studyReminders(input: Input) -> [ReminderRequest] {
        guard let time = input.settings.studyReminder else { return [] }
        let calendar = input.calendar
        let today = LocalDay(input.now, calendar: calendar)
        let startedDay = input.lastSessionStart.map { LocalDay($0, calendar: calendar) }
        let kind = ReminderKind.studyReminder
        return (0...horizonDays).compactMap { offset -> ReminderRequest? in
            let day = today.adding(days: offset, calendar: calendar)
            guard day != startedDay,
                  let fire = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day.startDate(in: calendar)),
                  NowPhase.resolve(date: fire, weekly: input.schedule, calendar: calendar) == .day
            else { return nil }
            return ReminderRequest(
                id: kind.identifierPrefix + day.description, kind: kind, fireDate: fire, calendar: calendar,
                title: ReminderCopy.studyTitle, body: ReminderCopy.studyBody, threadID: kind.threadID,
                interruption: .active, playsSound: true
            )
        }
    }
```
- update the type's doc comment's rule list with two lines: `/// - **Session end** at a running session's planned end, with an absolute trigger; exempt from the night rule.` and `/// - **Study reminder** (opt-in) once a day at the member's time, only in the Day phase, skipped on a day a session started.`

`ClockTime` must expose `hour` and `minute`; it does (`HomeFormat.clockParts` reads them).

- [ ] **Step 4: Absolute triggers, settings and the moved inputs**

In `MapleKit/Sources/MapleServices/Notifications/NotificationScheduler.swift`, in `apply(_:)`, replace
```swift
                try await center.add(request, trigger: .date(request.fireComponents))
```
with
```swift
                let trigger: ReminderTrigger = request.isAbsolute
                    ? .after(request.fireDate.timeIntervalSince(now)) : .date(request.fireComponents)
                try await center.add(request, trigger: trigger)
```

In `MapleKit/Sources/MapleServices/Settings/AppSettings.swift`:
- add to `SettingsSnapshot`, after `windDownReminder`: `public var sessionEndReminder: Bool` and `public var studyReminder: ClockTime?`;
- add the init parameters `sessionEndReminder: Bool = true, studyReminder: ClockTime? = nil` after `windDownReminder: Bool = true`, and their assignments;
- add `sessionEndReminder, studyReminder` to `CodingKeys`;
- in `init(from:)`, add
```swift
        sessionEndReminder = (try? c.decodeIfPresent(Bool.self, forKey: .sessionEndReminder)) ?? true
        studyReminder = try? c.decodeIfPresent(ClockTime.self, forKey: .studyReminder)
```
- in `encode(to:)`, add `try c.encode(sessionEndReminder, forKey: .sessionEndReminder)` and `try c.encodeIfPresent(studyReminder, forKey: .studyReminder)`;
- add to `AppSettings`, after `windDownReminder`:
```swift
    /// "Session done" at a session's planned end. On by default (F1-23).
    public var sessionEndReminder: Bool {
        get { snapshot.sessionEndReminder }
        set { change { $0.sessionEndReminder = newValue } }
    }

    /// The daily study reminder's time; nil while it is off (the default, F1-4).
    public var studyReminderTime: ClockTime? {
        get { snapshot.studyReminder }
        set { change { $0.studyReminder = newValue } }
    }
```
- change `reminders` to `ReminderSettings(windDown: windDownReminder, sessionEnd: sessionEndReminder, studyReminder: studyReminderTime)`.

Create `MapleKit/Sources/MapleServices/Notifications/ReminderInputs.swift`:
```swift
import Foundation
import MapleCore

/// Builds `ReminderPlan`'s input from the app's stores: the coming nights of the member's weekly schedule, the
/// reminder switches, whether wind-down mode has been opened, and the running session. `ReminderUpkeep` reschedules
/// with it whenever one of those changes.
public enum ReminderInputs {
    /// - Parameters:
    ///   - windDownOpenedAt: When wind-down mode was last opened (the bedside log's start); nil if never.
    ///   - runningSession: The session running now, for its end reminder.
    ///   - lastSessionStart: When the latest session started, so the study reminder skips that day.
    public static func plan(
        collection: CollectionStore, schedule: ScheduleStore, settings: AppSettings, windDownOpenedAt: Date?,
        runningSession: ReminderPlan.RunningSession?, lastSessionStart: Date?, now: Date, locale: Locale
    ) -> ReminderPlan {
        let calendar = collection.context.calendar
        return ReminderPlan(.init(
            nights: UpcomingNight.nights(for: schedule.weekly, around: now, calendar: calendar), settings: settings.reminders,
            windDownOpenedAt: windDownOpenedAt, now: now, calendar: calendar, locale: locale, schedule: schedule.weekly,
            runningSession: runningSession, lastSessionStart: lastSessionStart
        ))
    }
}
```
`ScheduleStore.weekly` is what the app's copy already reads.

Delete `App/Features/Notifications/ReminderInputs.swift`, and in `App/Features/Notifications/ReminderUpkeep.swift` replace the body of `reschedule()` with:
```swift
        let plan = ReminderInputs.plan(
            collection: collection, schedule: schedule, settings: settings, windDownOpenedAt: bedside.session.startedAt,
            runningSession: nil, lastSessionStart: nil, now: clock.now(), locale: locale
        )
        await reminders.reschedule(plan: plan)
```
and change the type's doc comment's first line to `/// Keeps Maple's reminders in step with the member's day: reschedules`.

- [ ] **Step 5: Run the tests and the build**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh > "$WS/test.log" 2>&1; tail -3 "$WS/test.log"; grep -c "warning:" "$WS/test.log"`
Expected: `** TEST SUCCEEDED **` and `0`. The full suite runs because the app target changed.

- [ ] **Step 6: Commit**

```bash
git add MapleKit App/Features/Notifications
git commit -m "Reminders: a session's end (absolute trigger) and the opt-in study reminder; ReminderInputs moves to MapleServices

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 19: Home's NowState for focus

Home's numeral, caption and action follow F1 design §5.10. The screens that draw them change in F1b; here only the state and its tests change, and `HomeView`'s switch is kept compiling.

**Files:**
- Modify (rewrite): `MapleKit/Sources/MapleCore/Home/NowState.swift`
- Modify: `MapleKit/Sources/MapleServices/Collection/CollectionStore.swift:282-292` (`nowState` drops `counters`)
- Modify: `App/Features/Home/HomeView.swift:249` (the action switch)
- Test: `MapleKit/Tests/MapleCoreTests/NowStateTests.swift`

**Interfaces:**
- Consumes: `FocusVerb`, `Strictness` (Task 2), `StartReadiness` (Task 16), `FocusTimeText` (Task 16), `HomeFormat`.
- Produces:
  - `FocusStart(presetID:verb:minutes:strictness:readiness:)`, with `title`;
  - `FocusStatus(savedTodaySeconds:savedYesterdaySeconds:savedTotalSeconds:remaining:start:blocking:)` and `FocusStatus.Blocking` (`.ready`, `.needsPermission`, `.notInThisBuild`);
  - `NowState.Content` gains `.savedToday`, `.savedInAll` and `.savedYesterday`, and loses `.focusToday`;
  - `NowState.Action`: `.startWindDown`, `.returnToWindDown`, `.startFocus(FocusStart)`, `.returnToSession`, `.turnOnBlocking`, `.openReveals(count:)`;
  - `NowState.resolve(date:weekly:calendar:locale:pending:features:lastNight:goodnightAt:focus:windDownActive:)` (no `counters`), and the same with `schedule:`.

**Rulings this task carries:**
- In the morning a Goodnight tap still comes before "saved yesterday": it is last night's data, and §5.10 replaces only the no-data state.
- A day with less than a minute saved reads as no session yet, so "0m saved today" never shows.
- `HomeView` maps the new actions to what Home can do today (the Rest tab, which F1b replaces with the Focus tab), so the app still builds.

- [ ] **Step 1: Rewrite the focus tests**

In `MapleKit/Tests/MapleCoreTests/NowStateTests.swift`:
- in the `state(...)` helper, delete the `counters: [RewardCategoryID: Double] = [:],` parameter and the `counters: counters,` argument;
- replace the `dayFocus()` and `focusRunning()` tests with:
```swift
    private let study = FocusStart(presetID: FocusFixtures.session, verb: .study, minutes: 50, strictness: .steady,
                                   readiness: .ready(needsHold: false))

    @Test("Day once focus ships: saved today and in all, and Start with the last-used preset")
    func dayFocus() {
        let now = state(13, 40, features: .all,
                        focus: FocusStatus(savedTodaySeconds: 80 * 60 + 30, savedTotalSeconds: 41 * 3600 + 600, start: study))
        #expect(now.content == .savedToday)
        #expect(now.numeral.text == "1h 20m")
        #expect(now.caption == "saved today · 41h in all")
        #expect(now.spoken.contains("saved today"))
        #expect(now.action == .startFocus(study))
        #expect(now.action?.title == "Start study · 50m")
        var locked = study
        locked.strictness = .locked
        #expect(NowState.Action.startFocus(locked).title == "Hold to start · Locked 50m")
    }

    @Test("Before the day's first session: the lifetime total; with nothing ever saved, the countdown")
    func dayBeforeFirstSession() {
        let total = state(13, 40, features: .all, focus: FocusStatus(savedTodaySeconds: 20, savedTotalSeconds: 41 * 3600, start: study))
        #expect(total.content == .savedInAll)
        #expect(total.numeral.text == "41h")
        #expect(total.caption == "saved in all · none yet today")
        let small = state(13, 40, features: .all, focus: FocusStatus(savedTotalSeconds: 35 * 60, start: study))
        #expect(small.numeral.text == "35m")
        let none = state(13, 40, features: .all, focus: FocusStatus(start: study))
        #expect(none.content == .untilWindDown)
        #expect(none.action == .startFocus(study))
    }

    @Test("Without Screen Time the day keeps its countdown and offers Turn on blocking; a free build offers nothing")
    func dayWithoutBlocking() {
        let needs = state(13, 40, features: .all, focus: FocusStatus(savedTotalSeconds: 3600, start: study, blocking: .needsPermission))
        #expect(needs.content == .untilWindDown)
        #expect(needs.action == .turnOnBlocking)
        #expect(needs.action?.title == "Turn on blocking")
        let free = state(13, 40, features: .all, focus: FocusStatus(start: study, blocking: .notInThisBuild))
        #expect(free.content == .untilWindDown)
        #expect(free.action == nil)
    }

    @Test("A running session shows calm minutes in every phase, night included")
    func focusRunning() {
        let running = FocusStatus(savedTodaySeconds: 600, remaining: 18 * 60 + 42)
        let now = state(20, 55, features: .all, focus: running)
        #expect(now.content == .focusRunning)
        #expect(now.numeral.text == "19m")
        #expect(now.caption == "left in this session")
        #expect(now.spoken == "19 minutes left in this session.")
        #expect(now.action == .returnToSession)
        #expect(now.action?.title == "Return to session")
        #expect(now.refreshesEverySecond)
        #expect(state(23, 30, features: .all, focus: running).content == .focusRunning)
        #expect(state(23, 30, features: .all, focus: running).action == .returnToSession)
        let last = state(13, 40, features: .all, focus: FocusStatus(remaining: 42))
        #expect(last.numeral.parts == [.value("0:42")])
        // Before focus ships nothing runs.
        #expect(state(20, 55, focus: running).content == .untilWindDown)
    }

    @Test("Morning with no sleep data: saved yesterday, when something was")
    func morningSavedYesterday() {
        let now = state(7, 40, features: .all, focus: FocusStatus(savedYesterdaySeconds: 110 * 60, savedTotalSeconds: 41 * 3600))
        #expect(now.content == .savedYesterday)
        #expect(now.numeral.text == "1h 50m")
        #expect(now.caption == "saved yesterday · 41h in all")
        #expect(now.action == nil)
        #expect(state(7, 40, features: .all, focus: FocusStatus(savedTotalSeconds: 41 * 3600)).content == .windDownTonight)
        #expect(state(7, 40, features: .all, goodnightAt: at(2026, 10, 9, 23, 4),
                      focus: FocusStatus(savedYesterdaySeconds: 3600)).content == .goodnight)
    }
```
- in `pending()`, replace
```swift
        let focusing = state(13, 40, pending: 1, features: .all, focus: FocusStatus(todayMinutes: 0, weekMinutes: 0, remaining: 60))
        #expect(focusing.action == .returnToFocus)
```
with
```swift
        let focusing = state(13, 40, pending: 1, features: .all, focus: FocusStatus(remaining: 60))
        #expect(focusing.action == .returnToSession)
```
- in `captionLength()`, replace the two `FocusStatus(todayMinutes: …)` states with:
```swift
                state(13, 40, locale: locale, features: .all, focus: FocusStatus(savedTodaySeconds: 85 * 60, savedTotalSeconds: 41 * 3600)),
                state(13, 40, locale: locale, features: .all, focus: FocusStatus(savedTotalSeconds: 41 * 3600)),
                state(7, 40, locale: locale, features: .all, focus: FocusStatus(savedYesterdaySeconds: 3600, savedTotalSeconds: 41 * 3600)),
                state(13, 40, locale: locale, features: .all, focus: FocusStatus(remaining: 300)),
```

- [ ] **Step 2: Run them to verify they fail**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -only-testing:MapleCoreTests/NowStateTests > "$WS/test.log" 2>&1; grep -E "error:" "$WS/test.log" | head -5`
Expected: `error: cannot find 'FocusStart' in scope`

- [ ] **Step 3: Rewrite NowState**

Replace everything in `MapleKit/Sources/MapleCore/Home/NowState.swift` from `/// Today's focus, once the focus timer ships.` down to the end of `NowState.Action` (its closing brace after `title`) with:
```swift
/// What Home's Start would begin (F1 design §5.10): the last-used preset, and whether it can start at once.
public struct FocusStart: Sendable, Hashable {
    public var presetID: UUID
    public var verb: FocusVerb
    public var minutes: Int
    public var strictness: Strictness
    /// Ready starts at once (a hold for Locked); otherwise Start opens the Focus tab with this preset selected.
    public var readiness: StartReadiness

    public init(presetID: UUID, verb: FocusVerb, minutes: Int, strictness: Strictness, readiness: StartReadiness) {
        self.presetID = presetID
        self.verb = verb
        self.minutes = minutes
        self.strictness = strictness
        self.readiness = readiness
    }

    /// "Start study · 50m", or "Hold to start · Locked 50m".
    public var title: String {
        let length = HomeFormat.duration(minutes: minutes)
        return strictness == .locked ? "Hold to start · Locked \(length)" : "\(verb.startTitle) · \(length)"
    }
}

/// Today's focus, for Home (F1 design §5.10). Seconds are display credit: counted, plus a running session's
/// provisional time, so Home and the dial agree.
public struct FocusStatus: Sendable, Hashable {
    public enum Blocking: Sendable, Hashable {
        case ready
        /// Screen Time isn't allowed for Maple yet: Home offers "Turn on blocking".
        case needsPermission
        /// A build that can't block: no action.
        case notInThisBuild
    }

    public var savedTodaySeconds: Int
    public var savedYesterdaySeconds: Int
    public var savedTotalSeconds: Int
    /// Seconds left in a running session; nil when none is running.
    public var remaining: TimeInterval?
    /// What Start would begin; nil when there is no preset.
    public var start: FocusStart?
    public var blocking: Blocking

    public init(
        savedTodaySeconds: Int = 0, savedYesterdaySeconds: Int = 0, savedTotalSeconds: Int = 0, remaining: TimeInterval? = nil,
        start: FocusStart? = nil, blocking: Blocking = .ready
    ) {
        self.savedTodaySeconds = savedTodaySeconds
        self.savedYesterdaySeconds = savedYesterdaySeconds
        self.savedTotalSeconds = savedTotalSeconds
        self.remaining = remaining
        self.start = start
        self.blocking = blocking
    }
}

/// What Home's NowBlock, next-leaf row and primary capsule show right now (spec §3.3–3.4, F1 design §5.10). Pure:
/// build it with `NowState.resolve(…)` inside a `TimelineView(.everyMinute)` (every second while a session runs).
public struct NowState: Sendable, Equatable {
    /// Which row of the table the numeral and caption come from.
    public enum Content: Sendable, Equatable {
        /// Morning with Apple Health: "7h 12m" · "asleep 23:08 · up 06:20".
        case lastNightSleep
        /// Morning without Apple Health: "23:04" · "in bed · bedtime 23:00".
        case goodnight
        /// Morning with no sleep data, once something was saved yesterday: "1h 50m" · "saved yesterday · 41h in all".
        case savedYesterday
        /// Morning with no data for last night: tonight's wind-down start as a clock time, "22:15" ·
        /// "wind-down tonight · bed 23:00" (a countdown would read "14h 45m" at 7 AM).
        case windDownTonight
        /// Day: "1h 20m" · "saved today · 41h in all".
        case savedToday
        /// Day before its first session: "41h" · "saved in all · none yet today" (F1-25).
        case savedInAll
        /// Day before focus ships, without blocking, or with nothing ever saved; and evening: "1h 20m" ·
        /// "until wind-down · bed 23:00".
        case untilWindDown
        /// A session running, in every phase: "18m" · "left in this session".
        case focusRunning
        /// Wind-down: "38m" · "until bed · phone down at 23:00".
        case untilBed
        /// Night: "07:00" · "wake-up · your maple is resting".
        case wake
    }

    /// Home's one primary action. Nil when there is none: the capsule disappears and nothing replaces it.
    public enum Action: Sendable, Hashable {
        case startWindDown
        case returnToWindDown
        /// Begins the preset at once when its readiness allows; otherwise opens the Focus tab with it selected. There
        /// is no long-press menu (F1-20).
        case startFocus(FocusStart)
        case returnToSession
        /// Opens Needs Screen Time.
        case turnOnBlocking
        /// Opens the reveal for the waiting leaves.
        case openReveals(count: Int)

        /// The capsule's label.
        public var title: String {
            switch self {
            case .startWindDown: "Start wind-down"
            case .returnToWindDown: "Return to wind-down"
            case .startFocus(let start): start.title
            case .returnToSession: "Return to session"
            case .turnOnBlocking: "Turn on blocking"
            case .openReveals(let count): count == 1 ? "Open your new leaf" : "Open \(count) new leaves"
            }
        }
    }
```
then:
- delete `public static let defaultFocusMinutes = 25`;
- in both `resolve` overloads, delete the `counters: [RewardCategoryID: Double] = [:],` parameter, the `counters: counters,` argument and the `///   - counters:` doc line; change the `///   - focus:` doc line to `///   - focus: Today's focus, once the timer ships (display credit).`;
- in the weekly `resolve`, replace everything from `func dayContent()` through the end of the `let action: Action?` block (the closing brace of its `else`) with:
```swift
        func inAll(_ seconds: Int) -> [NumeralPart] {
            seconds >= 3600 ? [.value("\(seconds / 3600)"), .unit("h")] : HomeFormat.durationParts(minutes: seconds / 60)
        }
        func spokenInAll(_ seconds: Int) -> String {
            HomeFormat.spokenDuration(minutes: seconds >= 3600 ? seconds / 3600 * 60 : seconds / 60, locale: locale)
        }

        func dayContent() -> (Content, [NumeralPart], String, String) {
            guard features.focus, let focus, focus.blocking == .ready else { return untilWindDown() }
            let total = Numeral(parts: inAll(focus.savedTotalSeconds)).text
            if focus.savedTodaySeconds >= 60 {
                let minutes = focus.savedTodaySeconds / 60
                return (.savedToday, HomeFormat.durationParts(minutes: minutes), "saved today · \(total) in all",
                        "\(HomeFormat.spokenDuration(minutes: minutes, locale: locale)) saved today. "
                            + "\(spokenInAll(focus.savedTotalSeconds)) in all.")
            }
            if focus.savedTotalSeconds >= 60 {
                return (.savedInAll, inAll(focus.savedTotalSeconds), "saved in all · none yet today",
                        "\(spokenInAll(focus.savedTotalSeconds)) saved in all. None yet today.")
            }
            return untilWindDown()
        }

        let runningFocus = features.focus ? focus?.remaining.flatMap { $0 > 0 ? $0 : nil } : nil
        let content: (Content, [NumeralPart], String, String)
        if let remaining = runningFocus {
            let text = FocusTimeText.remaining(remaining)
            let parts: [NumeralPart] = text.hasPrefix("0:")
                ? [.value(text)] : HomeFormat.durationParts(minutes: Int((remaining / 60 - 1e-9).rounded(.up)))
            content = (.focusRunning, parts, "left in this session",
                       "\(FocusTimeText.spokenRemaining(remaining, locale: locale)) in this session.")
        } else {
            switch phase {
            case .morning:
                if let lastNight {
                    let minutes = Int((lastNight.duration / 60).rounded())
                    let asleep = HomeFormat.clock(HomeFormat.clockTime(of: lastNight.asleep, calendar: calendar), locale: locale)
                    let up = HomeFormat.clock(HomeFormat.clockTime(of: lastNight.awake, calendar: calendar), locale: locale)
                    content = (.lastNightSleep, HomeFormat.durationParts(minutes: minutes), "asleep \(asleep) · up \(up)",
                               "\(HomeFormat.spokenDuration(minutes: minutes, locale: locale)) asleep last night. Asleep at \(asleep), up at \(up).")
                } else if let goodnightAt {
                    let time = HomeFormat.clockTime(of: goodnightAt, calendar: calendar)
                    let text = HomeFormat.clock(time, locale: locale)
                    let lastBed = HomeFormat.clock(previous.bedtime, locale: locale)
                    content = (.goodnight, HomeFormat.clockParts(time, locale: locale), "in bed · bedtime \(lastBed)",
                               "In bed at \(text). Bedtime \(lastBed).")
                } else if features.focus, let focus, focus.savedYesterdaySeconds >= 60 {
                    let minutes = focus.savedYesterdaySeconds / 60
                    let total = Numeral(parts: inAll(focus.savedTotalSeconds)).text
                    content = (.savedYesterday, HomeFormat.durationParts(minutes: minutes), "saved yesterday · \(total) in all",
                               "\(HomeFormat.spokenDuration(minutes: minutes, locale: locale)) saved yesterday. "
                                   + "\(spokenInAll(focus.savedTotalSeconds)) in all.")
                } else {
                    let windDown = HomeFormat.clock(schedule.windDownStart, locale: locale)
                    content = (.windDownTonight, HomeFormat.clockParts(schedule.windDownStart, locale: locale),
                               "wind-down tonight · bed \(bed)", "Wind-down tonight at \(windDown). Bed at \(bed).")
                }
            case .day:
                content = dayContent()
            case .evening:
                content = untilWindDown()
            case .windDown:
                let bedtime = windows.nextStart(of: .night, after: date, calendar: calendar)
                let minutes = HomeFormat.minutesUntil(bedtime, from: date)
                content = (.untilBed, HomeFormat.durationParts(minutes: minutes), "until bed · phone down at \(bed)",
                           "\(HomeFormat.spokenDuration(minutes: minutes, locale: locale)) until bed. Phone down at \(bed).")
            case .night:
                let wake = HomeFormat.clock(schedule.wake, locale: locale)
                content = (.wake, HomeFormat.clockParts(schedule.wake, locale: locale), "wake-up · your maple is resting",
                           "Wake-up at \(wake). Your maple is resting.")
            }
        }

        let waiting = RevealSchedule.opensIn(phase) ? max(0, pending) : 0
        let action: Action?
        if runningFocus != nil {
            action = .returnToSession
        } else if waiting > 0 {
            action = .openReveals(count: waiting)
        } else {
            switch phase {
            case .morning, .night:
                action = nil
            case .day:
                if features.focus, let focus {
                    switch focus.blocking {
                    case .ready: action = focus.start.map { .startFocus($0) }
                    case .needsPermission: action = .turnOnBlocking
                    case .notInThisBuild: action = nil
                    }
                } else {
                    action = nil
                }
            case .evening, .windDown:
                action = windDownActive ? .returnToWindDown : .startWindDown
            }
        }
```
- add `import MapleFocusCore` under `import Foundation`.

The morning, wind-down and night branches are today's, unchanged; only the session (every phase now), the day and the morning's saved-yesterday case are new.

In `MapleKit/Sources/MapleServices/Collection/CollectionStore.swift`, in `nowState(…)`, delete `counters: snapshot.counters,` from the `NowState.resolve` call, and change its doc comment's last sentence to "Apple Health's last night, the Goodnight tap (the phone-down time the morning shows without Apple Health, spec §3.4; it earns nothing) and the focus status (display credit) are passed in."

In `App/Features/Home/HomeView.swift`, replace
```swift
        case .startFocus, .returnToFocus:
            // Focus lives in Rest (spec §2.2); Home offers it only once it ships.
            router.selectedTab = .rest
```
with
```swift
        case .startFocus, .returnToSession, .turnOnBlocking:
            // Until F1b adds the Focus tab, focus lives in Rest; Home offers these only once focus ships.
            router.selectedTab = .rest
```

- [ ] **Step 4: Run the tests and the build**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh > "$WS/test.log" 2>&1; tail -3 "$WS/test.log"; grep -c "warning:" "$WS/test.log"`
Expected: `** TEST SUCCEEDED **` and `0`.

- [ ] **Step 5: Commit**

```bash
git add MapleKit App/Features/Home/HomeView.swift
git commit -m "Home's state for focus: saved today and in all, a running session in every phase, Start with readiness

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 20: Presets, app sets and session notes

Three small JSON stores beside the collection, each tolerant and never saving over a file it couldn't read (the `AppSettings` pattern).

**Files:**
- Create: `MapleKit/Sources/MapleServices/Focus/PresetStore.swift`
- Create: `MapleKit/Sources/MapleServices/Focus/AppSetStore.swift`
- Create: `MapleKit/Sources/MapleServices/Focus/SessionNotesStore.swift`
- Test: `MapleKit/Tests/MapleServicesTests/FocusStoresTests.swift`

**Interfaces:**
- Consumes: `FocusPreset`, `RecentIntentions` (Task 16), `SelectionSummary` (Task 2), `JSONStorage`.
- Produces:
  - `PresetsFile(presets:lastUsedID:)`; `PresetStore(storage:defaultAppSetID:)`, with `presets`, `lastUsed`, `canAdd`, `preset(id:)`, `add(_:) -> Bool`, `update(_:)`, `delete(id:) -> Bool`, `markUsed(_:)`, `isAvailable`, `PresetStore.file` (`presets.json`);
  - `AppSet(id:name:selection:summary:tokensExpired:)`, `AppSet.distractionsID`, `AppSet.starters()`; `AppSetsFile(sets:)`; `AppSetStore(storage:)`, with `sets`, `set(id:)`, `save(selection:summary:to:) -> AppSetSaveResult`, `markExpired(_:_:)`, `totalTokens`, `AppSetStore.file` (`app-sets.json`);
  - `AppSetSaveResult` (`.saved`, `.wouldEmpty`, `.overTokenLimit`, `.unknownSet`);
  - `SessionNote(text:at:)`, `SessionNotesFile(notes:)`; `SessionNotesStore(storage:)`, with `intention(for:)`, `setIntention(_:for:at:)`, `eraseAll()`, `entries(reflections:) -> [RecentIntentions.Entry]`, `SessionNotesStore.file` (`session-notes.json`), `SessionNotesStore.kept` (200).

- [ ] **Step 1: Write the failing tests**

`MapleKit/Tests/MapleServicesTests/FocusStoresTests.swift`:
```swift
import Foundation
import Testing
@testable import MapleCore
@testable import MapleServices

@Suite("Focus stores")
@MainActor
struct FocusStoresTests {
    private func url(_ name: String) throws -> URL {
        try temporaryDirectory().appendingPathComponent(name)
    }

    @Test("Presets start with the four defaults on Distractions, and changes are saved")
    func presets() throws {
        let file = try url(PresetStore.file)
        let store = PresetStore(storage: JSONStorage(.file(file)), defaultAppSetID: AppSet.distractionsID)
        #expect(store.presets.map(\.name) == ["Study", "Quick", "Deep", "Read"])
        #expect(store.presets.allSatisfy { $0.appSetID == AppSet.distractionsID })
        #expect(store.lastUsed?.name == "Study")
        let deep = try #require(store.presets.first { $0.name == "Deep" })
        store.markUsed(deep.id)
        var renamed = deep
        renamed.name = "   Deep work, the long kind of session   "
        renamed.minutes = 999
        store.update(renamed)
        let reloaded = PresetStore(storage: JSONStorage(.file(file)), defaultAppSetID: nil)
        #expect(reloaded.lastUsed?.id == deep.id)
        #expect(reloaded.lastUsed?.name == "Deep work, the long kind")
        #expect(reloaded.lastUsed?.minutes == 180)
    }

    @Test("At most 6 presets, and the last one can't be deleted")
    func presetLimits() {
        let store = PresetStore(storage: JSONStorage(.memory), defaultAppSetID: nil)
        #expect(store.add(FocusPreset(name: "Essay", verb: .focus, minutes: 40, hasBreak: false, appSetID: nil)))
        #expect(store.add(FocusPreset(name: "Revision", verb: .study, minutes: 60, hasBreak: true, appSetID: nil)))
        #expect(!store.canAdd)
        #expect(!store.add(FocusPreset(name: "Seventh", verb: .focus, minutes: 30, hasBreak: false, appSetID: nil)))
        for preset in store.presets.dropLast() { #expect(store.delete(id: preset.id)) }
        #expect(store.presets.count == 1)
        #expect(!store.delete(id: store.presets[0].id))
        #expect(store.lastUsed?.id == store.presets[0].id)
    }

    @Test("A damaged preset is skipped; an unreadable file is never written over")
    func presetFiles() throws {
        let file = try url(PresetStore.file)
        let good = FocusPreset(name: "Read", verb: .reading, minutes: 30, hasBreak: false, appSetID: nil)
        let json = #"{"presets":[{"name":"broken"},"# + String(decoding: try JSONEncoder().encode(good), as: UTF8.self) + "]}"
        try Data(json.utf8).write(to: file)
        #expect(PresetStore(storage: JSONStorage(.file(file)), defaultAppSetID: nil).presets.map(\.name) == ["Read"])

        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path) }
        let locked = PresetStore(storage: JSONStorage(.file(file)), defaultAppSetID: nil)
        #expect(!locked.isAvailable)
        locked.markUsed(locked.presets[0].id)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        #expect(try String(contentsOf: file, encoding: .utf8) == json)
    }

    @Test("App sets: three starters; an empty selection never replaces a full one; 50 tokens across every set")
    func appSets() throws {
        let store = AppSetStore(storage: JSONStorage(.memory))
        #expect(store.sets.map(\.name) == ["Distractions", "Study apps", "Bedtime"])
        #expect(store.set(id: AppSet.distractionsID)?.summary.isEmpty == true)
        let six = SelectionSummary(mode: .blockThese, apps: 6, sites: 1, categories: 0)
        #expect(store.save(selection: Data("six".utf8), summary: six, to: AppSet.distractionsID) == .saved)
        #expect(store.set(id: AppSet.distractionsID)?.summary == six)
        let empty = SelectionSummary(mode: .blockThese, apps: 0, sites: 0, categories: 0)
        #expect(store.save(selection: Data(), summary: empty, to: AppSet.distractionsID) == .wouldEmpty)
        #expect(store.set(id: AppSet.distractionsID)?.summary == six)
        let study = try #require(store.sets.first { $0.name == "Study apps" })
        let big = SelectionSummary(mode: .blockThese, apps: 45, sites: 0, categories: 0)
        #expect(store.save(selection: Data("big".utf8), summary: big, to: study.id) == .overTokenLimit)
        #expect(store.totalTokens == 6)                                         // 6 apps; 1 site counts separately
        #expect(store.save(selection: Data("x".utf8), summary: six, to: UUID()) == .unknownSet)
        store.markExpired(AppSet.distractionsID, true)
        #expect(store.set(id: AppSet.distractionsID)?.tokensExpired == true)
        #expect(store.save(selection: Data("six".utf8), summary: six, to: AppSet.distractionsID) == .saved)
        #expect(store.set(id: AppSet.distractionsID)?.tokensExpired == false)
    }

    @Test("Session notes: one intention per session, cleared by an empty field, erased on request, newest 200 kept")
    func notes() throws {
        let file = try url(SessionNotesStore.file)
        let store = SessionNotesStore(storage: JSONStorage(.file(file)))
        let a = UUID(), b = UUID()
        store.setIntention("  Chemistry ch. 4 ", for: a, at: at(2026, 10, 23, 14))
        store.setIntention("Essay", for: b, at: at(2026, 10, 23, 16))
        #expect(SessionNotesStore(storage: JSONStorage(.file(file))).intention(for: a) == "Chemistry ch. 4")
        store.setIntention("   ", for: b, at: at(2026, 10, 23, 16, 5))
        #expect(store.intention(for: b) == nil)
        #expect(store.entries(reflections: [a: .partly]) == [RecentIntentions.Entry(text: "Chemistry ch. 4", reflection: .partly, at: at(2026, 10, 23, 14))])
        for index in 0..<210 { store.setIntention("Note \(index)", for: UUID(), at: at(2026, 10, 1).addingTimeInterval(Double(index))) }
        #expect(store.entries(reflections: [:]).count == SessionNotesStore.kept)
        #expect(store.intention(for: a) == "Chemistry ch. 4")
        store.eraseAll()
        #expect(SessionNotesStore(storage: JSONStorage(.file(file))).entries(reflections: [:]).isEmpty)
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -only-testing:MapleServicesTests/FocusStoresTests > "$WS/test.log" 2>&1; grep -E "error:" "$WS/test.log" | head -5`
Expected: `error: cannot find 'PresetStore' in scope`

- [ ] **Step 3: Write the preset store**

`MapleKit/Sources/MapleServices/Focus/PresetStore.swift`:
```swift
import Foundation
import MapleCore
import Observation

/// What `presets.json` holds. Decoding is tolerant: a damaged preset is skipped.
nonisolated public struct PresetsFile: Codable, Sendable, Equatable {
    public var presets: [FocusPreset]
    public var lastUsedID: UUID?

    public init(presets: [FocusPreset], lastUsedID: UUID? = nil) {
        self.presets = presets
        self.lastUsedID = lastUsedID
    }

    private enum CodingKeys: String, CodingKey {
        case presets, lastUsedID
    }

    private struct Lossy: Decodable {
        let preset: FocusPreset?

        init(from decoder: any Decoder) throws {
            preset = try? FocusPreset(from: decoder)
        }
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        presets = ((try? c.decodeIfPresent([Lossy].self, forKey: .presets)) ?? []).compactMap(\.preset)
        lastUsedID = try? c.decodeIfPresent(UUID.self, forKey: .lastUsedID)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(presets, forKey: .presets)
        try c.encodeIfPresent(lastUsedID, forKey: .lastUsedID)
    }
}

/// The member's Focus presets (F1 design §5.13): up to 6, never none. Home's Start uses the last-used one.
@Observable
public final class PresetStore {
    nonisolated public static let file = "presets.json"

    public private(set) var presets: [FocusPreset]
    public private(set) var lastUsedID: UUID?
    /// False while the file exists but can't be read yet: the defaults are shown and nothing is saved.
    public private(set) var isAvailable: Bool

    @ObservationIgnored private let storage: JSONStorage<PresetsFile>
    @ObservationIgnored private let defaultAppSetID: UUID?

    /// - Parameter defaultAppSetID: The app set new and default presets block (Distractions).
    public init(storage: JSONStorage<PresetsFile>, defaultAppSetID: UUID?) {
        self.storage = storage
        self.defaultAppSetID = defaultAppSetID
        switch storage.read() {
        case .value(let saved) where !saved.presets.isEmpty:
            presets = Array(saved.presets.prefix(FocusPreset.maximumCount))
            lastUsedID = saved.lastUsedID
            isAvailable = true
        case .value, .absent:
            presets = FocusPreset.defaults(appSetID: defaultAppSetID)
            isAvailable = true
        case .unavailable:
            presets = FocusPreset.defaults(appSetID: defaultAppSetID)
            isAvailable = false
        }
    }

    /// The preset Start begins: the last used, else the first.
    public var lastUsed: FocusPreset? {
        lastUsedID.flatMap(preset(id:)) ?? presets.first
    }

    public var canAdd: Bool { presets.count < FocusPreset.maximumCount }

    public func preset(id: UUID) -> FocusPreset? {
        presets.first { $0.id == id }
    }

    /// - Returns: False at 6 presets.
    @discardableResult
    public func add(_ preset: FocusPreset) -> Bool {
        guard canAdd else { return false }
        change { $0.append(Self.cleaned(preset)) }
        return true
    }

    /// Replaces the preset with the same id; the name is trimmed to 24 characters and the length kept in range.
    public func update(_ preset: FocusPreset) {
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        change { $0[index] = Self.cleaned(preset) }
    }

    /// - Returns: False for the last preset, which can't be deleted.
    @discardableResult
    public func delete(id: UUID) -> Bool {
        guard presets.count > 1, let index = presets.firstIndex(where: { $0.id == id }) else { return false }
        change { $0.remove(at: index) }
        if lastUsedID == id { setLastUsed(nil) }
        return true
    }

    public func markUsed(_ id: UUID) {
        guard preset(id: id) != nil else { return }
        setLastUsed(id)
    }

    // MARK: Private

    private static func cleaned(_ preset: FocusPreset) -> FocusPreset {
        var copy = preset
        copy.name = FocusPreset.normalizedName(preset.name) ?? preset.verb.rawValue.capitalized
        copy.minutes = DialLayout.stepped(preset.minutes, by: 0)
        return copy
    }

    private func change(_ edit: (inout [FocusPreset]) -> Void) {
        var copy = presets
        edit(&copy)
        guard copy != presets else { return }
        presets = copy
        save()
    }

    private func setLastUsed(_ id: UUID?) {
        guard id != lastUsedID else { return }
        lastUsedID = id
        save()
    }

    private func save() {
        guard isAvailable else { return }
        storage.save(PresetsFile(presets: presets, lastUsedID: lastUsedID))
    }
}
```
`DialLayout.stepped(_:by: 0)` clamps to 20–180 without moving a valid length.

- [ ] **Step 4: Write the app set store**

`MapleKit/Sources/MapleServices/Focus/AppSetStore.swift`:
```swift
import Foundation
import MapleCore
import Observation

/// A named selection of apps, sites and categories (F1 design §5.14). The selection itself is opaque: the blocking
/// service encodes it (Apple's `FamilyActivitySelection` in F1-paid, the DEBUG fake picker's choices in F1).
nonisolated public struct AppSet: Codable, Sendable, Equatable, Identifiable {
    public static let distractionsID = UUID(uuidString: "6D61706C-6500-4153-4554-000000000001")!
    public static let studyAppsID = UUID(uuidString: "6D61706C-6500-4153-4554-000000000002")!
    public static let bedtimeID = UUID(uuidString: "6D61706C-6500-4153-4554-000000000003")!

    public var id: UUID
    public var name: String
    public var selection: Data
    public var summary: SelectionSummary
    /// iOS no longer recognises some of its tokens: "Some apps need choosing again".
    public var tokensExpired: Bool

    public init(id: UUID, name: String, selection: Data = Data(), summary: SelectionSummary, tokensExpired: Bool = false) {
        self.id = id
        self.name = name
        self.selection = selection
        self.summary = summary
        self.tokensExpired = tokensExpired
    }

    /// Distractions, Study apps and Bedtime, empty.
    public static func starters() -> [AppSet] {
        let empty = SelectionSummary(mode: .blockThese, apps: 0, sites: 0, categories: 0)
        return [
            AppSet(id: distractionsID, name: "Distractions", summary: empty),
            AppSet(id: studyAppsID, name: "Study apps", summary: empty),
            AppSet(id: bedtimeID, name: "Bedtime", summary: empty),
        ]
    }
}

nonisolated public struct AppSetsFile: Codable, Sendable, Equatable {
    public var sets: [AppSet]

    public init(sets: [AppSet]) {
        self.sets = sets
    }
}

public enum AppSetSaveResult: Sendable, Equatable {
    case saved
    /// An empty selection is never saved over a non-empty one.
    case wouldEmpty
    /// More than 50 app or 50 web tokens across every set: iOS would silently block nothing.
    case overTokenLimit
    case unknownSet
}

@Observable
public final class AppSetStore {
    nonisolated public static let file = "app-sets.json"

    public private(set) var sets: [AppSet]
    public private(set) var isAvailable: Bool

    @ObservationIgnored private let storage: JSONStorage<AppSetsFile>

    public init(storage: JSONStorage<AppSetsFile>) {
        self.storage = storage
        switch storage.read() {
        case .value(let saved) where !saved.sets.isEmpty:
            sets = saved.sets
            isAvailable = true
        case .value, .absent:
            sets = AppSet.starters()
            isAvailable = true
        case .unavailable:
            sets = AppSet.starters()
            isAvailable = false
        }
    }

    public func set(id: UUID) -> AppSet? {
        sets.first { $0.id == id }
    }

    /// App and web tokens across every set (the larger of the two counts against the 50-token cap).
    public var totalTokens: Int {
        max(sets.reduce(0) { $0 + $1.summary.apps }, sets.reduce(0) { $0 + $1.summary.sites })
    }

    public func save(selection: Data, summary: SelectionSummary, to id: UUID) -> AppSetSaveResult {
        guard let index = sets.firstIndex(where: { $0.id == id }) else { return .unknownSet }
        if summary.isEmpty, !sets[index].summary.isEmpty { return .wouldEmpty }
        let others = sets.enumerated().filter { $0.offset != index }.map(\.element.summary)
        let apps = others.reduce(summary.apps) { $0 + $1.apps }
        let sites = others.reduce(summary.sites) { $0 + $1.sites }
        guard apps <= SelectionSummary.tokenLimit, sites <= SelectionSummary.tokenLimit else { return .overTokenLimit }
        sets[index].selection = selection
        sets[index].summary = summary
        sets[index].tokensExpired = false
        persist()
        return .saved
    }

    public func markExpired(_ id: UUID, _ expired: Bool) {
        guard let index = sets.firstIndex(where: { $0.id == id }), sets[index].tokensExpired != expired else { return }
        sets[index].tokensExpired = expired
        persist()
    }

    private func persist() {
        guard isAvailable else { return }
        storage.save(AppSetsFile(sets: sets))
    }
}
```

- [ ] **Step 5: Write the session notes store**

`MapleKit/Sources/MapleServices/Focus/SessionNotesStore.swift`:
```swift
import Foundation
import MapleCore
import Observation

/// One session's intention. Free text never goes into the ledger (F1-19).
nonisolated public struct SessionNote: Codable, Sendable, Equatable {
    public var text: String
    public var at: Date

    public init(text: String, at: Date) {
        self.text = text
        self.at = at
    }
}

nonisolated public struct SessionNotesFile: Codable, Sendable, Equatable {
    /// Keyed by the lowercased session id.
    public var notes: [String: SessionNote]

    public init(notes: [String: SessionNote] = [:]) {
        self.notes = notes
    }
}

/// Intentions by session (`session-notes.json`, F1 design §5.16): the member can edit and erase them, and only the
/// newest 200 are kept.
@Observable
public final class SessionNotesStore {
    nonisolated public static let file = "session-notes.json"
    nonisolated public static let kept = 200

    public private(set) var notes: [String: SessionNote]
    public private(set) var isAvailable: Bool

    @ObservationIgnored private let storage: JSONStorage<SessionNotesFile>

    public init(storage: JSONStorage<SessionNotesFile>) {
        self.storage = storage
        switch storage.read() {
        case .value(let saved):
            notes = saved.notes
            isAvailable = true
        case .absent:
            notes = [:]
            isAvailable = true
        case .unavailable:
            notes = [:]
            isAvailable = false
        }
    }

    public func intention(for session: UUID) -> String? {
        notes[session.uuidString.lowercased()]?.text
    }

    /// Sets a session's intention (trimmed, at most 60 characters); an empty one removes it.
    public func setIntention(_ text: String?, for session: UUID, at date: Date) {
        let key = session.uuidString.lowercased()
        if let text = text.flatMap(RecentIntentions.normalized) {
            notes[key] = SessionNote(text: text, at: notes[key]?.at ?? date)
        } else {
            notes[key] = nil
        }
        if notes.count > Self.kept {
            let oldest = notes.sorted { $0.value.at < $1.value.at }.prefix(notes.count - Self.kept).map(\.key)
            for key in oldest { notes[key] = nil }
        }
        persist()
    }

    public func eraseAll() {
        notes = [:]
        persist()
    }

    /// Every intention with the session's reflection, for `RecentIntentions.chips`.
    public func entries(reflections: [UUID: Reflection]) -> [RecentIntentions.Entry] {
        let byKey = Dictionary(uniqueKeysWithValues: reflections.map { ($0.key.uuidString.lowercased(), $0.value) })
        return notes.map { RecentIntentions.Entry(text: $0.value.text, reflection: byKey[$0.key], at: $0.value.at) }
            .sorted { $0.at < $1.at }
    }

    private func persist() {
        guard isAvailable else { return }
        storage.save(SessionNotesFile(notes: notes))
    }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -only-testing:MapleServicesTests/FocusStoresTests > "$WS/test.log" 2>&1; tail -3 "$WS/test.log"`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add MapleKit/Sources/MapleServices/Focus MapleKit/Tests/MapleServicesTests/FocusStoresTests.swift
git commit -m "Focus stores: presets (up to 6, never none), app sets (never empty over full, 50 tokens), session notes

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 21: The blocking boundary, the build's tier and the preview blocker

**Files:**
- Create: `MapleKit/Sources/MapleServices/Focus/BlockingService.swift`
- Create: `MapleKit/Sources/MapleServices/Focus/PreviewBlockingService.swift` (DEBUG)
- Modify: `Config/Maple-Info.plist` (the `MapleTier` key)
- Test: `MapleKit/Tests/MapleServicesTests/BlockingServiceTests.swift`

**Interfaces:**
- Consumes: `MapleTier`, `BlockingCapability`, `BlockingProbe`, `ShieldOp`, `ShieldStoreState`, `ShieldReconciler`, `FocusSource` (Tasks 3, 7).
- Produces:
  - `ShieldFailure` (`.notAllowed`, `.applyFailed`, `.readBack`, `.expiredTokens`) and `ShieldResult(store:failure:)`, with `isVerified`;
  - `protocol BlockingService: AnyObject` (MainActor): `capability`, `source`, `probe()`, `requestAuthorization()`, `readStore()`, `perform(_:selection:)`, `releaseAll()`, all `async`;
  - `MapleBuild.tier(infoValue:)`, `MapleBuild.tier` (from the bundle), `MapleBuild.capability(tier:usesPreview:)`;
  - `UnavailableBlockingService()`;
  - DEBUG: `PreviewBlockingService(authorization:failures:)`, with `PreviewBlockingService.Failure` (`.tokenOverflow`, `.revoked`, `.applyFails`, `.expiredTokens`), `failures`, `authorization`, `store`, `operations`, and `revoke()`.

**Rulings this task carries:**
- An ordinary DEBUG launch behaves like its tier (§7.6), so it can't block on a free account; only demo and sandbox launches use the preview blocker (`usesPreview`, decided in Task 23).
- Until F1-paid adds `ScreenTimeBlockingService`, a paid build can't block either. `capability(tier:usesPreview:)` keeps the paid case separate so F1-paid changes one line.
- A failed ledger write is not a blocker failure: it is `MemoryLedgerStore.failsWrites` (Task 8), exercised in Task 22.

- [ ] **Step 1: Write the failing tests**

`MapleKit/Tests/MapleServicesTests/BlockingServiceTests.swift`:
```swift
import Foundation
import Testing
@testable import MapleCore
@testable import MapleServices

@Suite("Blocking service")
@MainActor
struct BlockingServiceTests {
    private let session = UUID()

    @Test("The tier comes from Info.plist; anything unexpanded or missing is free")
    func tier() {
        #expect(MapleBuild.tier(infoValue: "paid") == .paid)
        #expect(MapleBuild.tier(infoValue: "free") == .free)
        #expect(MapleBuild.tier(infoValue: nil) == .free)
        #expect(MapleBuild.tier(infoValue: "$(MAPLE_TIER)") == .free)
        #expect(MapleBuild.capability(tier: .free, usesPreview: true) == .preview)
        #expect(MapleBuild.capability(tier: .free, usesPreview: false) == .unavailableInBuild)
        #expect(MapleBuild.capability(tier: .paid, usesPreview: false) == .unavailableInBuild)
    }

    @Test("A build that can't block says so and never claims a shield")
    func unavailable() async {
        let service = UnavailableBlockingService()
        #expect(service.capability == .unavailableInBuild)
        #expect(await service.probe() == .unavailable)
        #expect(await service.requestAuthorization() == .unavailable)
        let result = await service.perform(.apply(session: session), selection: Data("x".utf8))
        #expect(!result.isVerified)
        #expect(result.failure == .notAllowed)
        #expect(await service.readStore() == .empty)
    }

    @Test("The preview blocker applies, verifies and clears, reading back each time")
    func preview() async {
        let service = PreviewBlockingService(authorization: .notDetermined)
        #expect(service.source == .preview)
        #expect(await service.probe() == .notDetermined)
        #expect(await service.requestAuthorization() == .allowed)
        #expect(await service.perform(.apply(session: session), selection: Data("x".utf8)) == ShieldResult(store: .applied(session: session)))
        #expect(await service.perform(.verify(session: session), selection: nil).isVerified)
        #expect(await service.perform(.clear(session: session), selection: nil) == ShieldResult(store: .empty))
        #expect(service.operations == [.apply(session: session), .verify(session: session), .clear(session: session)])
        #expect(await service.releaseAll().isVerified)
    }

    @Test("Each real failure mode reads back as a failure")
    func failures() async {
        let overflow = PreviewBlockingService(failures: [.tokenOverflow])
        let full = await overflow.perform(.apply(session: session), selection: Data("x".utf8))
        #expect(full == ShieldResult(store: .empty, failure: .readBack))

        let failing = PreviewBlockingService(failures: [.applyFails])
        #expect(await failing.perform(.apply(session: session), selection: Data("x".utf8)).failure == .applyFailed)

        let expired = PreviewBlockingService(failures: [.expiredTokens])
        #expect(await expired.perform(.apply(session: session), selection: Data("x".utf8)).failure == .expiredTokens)

        let declined = PreviewBlockingService(authorization: .declined)
        #expect(await declined.perform(.apply(session: session), selection: Data("x".utf8)).failure == .notAllowed)

        // Revoked mid-session: the status still says allowed, but the shields are gone on the next read-back.
        let revoked = PreviewBlockingService()
        _ = await revoked.perform(.apply(session: session), selection: Data("x".utf8))
        revoked.revoke()
        #expect(await revoked.probe() == .allowed)
        #expect(await revoked.perform(.verify(session: session), selection: nil) == ShieldResult(store: .empty, failure: .readBack))
        #expect(await revoked.readStore() == .empty)
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -only-testing:MapleServicesTests/BlockingServiceTests > "$WS/test.log" 2>&1; grep -E "error:" "$WS/test.log" | head -5`
Expected: `error: cannot find 'MapleBuild' in scope`

- [ ] **Step 3: Write the boundary**

`MapleKit/Sources/MapleServices/Focus/BlockingService.swift`:
```swift
import Foundation
import MapleCore

/// Why a shield operation didn't verify.
public enum ShieldFailure: Sendable, Equatable {
    /// Screen Time isn't allowed for Maple (or this build can't block).
    case notAllowed
    case applyFailed
    /// The store read back differently from what was written: iOS blocks nothing (over 50 tokens), or the shields
    /// were removed (Screen Time was turned off for Maple).
    case readBack
    /// Some of the selection's apps need choosing again.
    case expiredTokens
}

/// What a shield operation left in the store, read back, and whether it did what was asked.
public struct ShieldResult: Sendable, Equatable {
    public var store: ShieldStoreState
    public var failure: ShieldFailure?

    public init(store: ShieldStoreState, failure: ShieldFailure? = nil) {
        self.store = store
        self.failure = failure
    }

    public var isVerified: Bool { failure == nil }
}

/// Maple's only door to blocking (F1 design §7.4). No FamilyControls or ManagedSettings types cross it: a selection
/// is opaque `Data` plus a `SelectionSummary`. Every operation reads the store back.
public protocol BlockingService: AnyObject {
    var capability: BlockingCapability { get }
    /// The source this service's sessions are written with: `preview` for the DEBUG blocker, which only the sandbox
    /// credits.
    var source: FocusSource { get }
    func probe() async -> BlockingProbe
    /// Asks iOS (or the preview) once; returns the state after.
    func requestAuthorization() async -> BlockingProbe
    func readStore() async -> ShieldStoreState
    /// Performs `op` and reads the store back. `selection` is the app set's data, for `.apply`.
    func perform(_ op: ShieldOp, selection: Data?) async -> ShieldResult
    /// Clears every store Maple has written to (Settings › Release all apps).
    func releaseAll() async -> ShieldResult
}

/// What this build is (F1 design §7.4): its tier, from the `MapleTier` Info.plist key, and what it can block with.
public enum MapleBuild {
    /// The tier this build was signed for; free when the key is missing or unexpanded.
    public static var tier: MapleTier {
        tier(infoValue: Bundle.main.object(forInfoDictionaryKey: "MapleTier") as? String)
    }

    public static func tier(infoValue: String?) -> MapleTier {
        infoValue.flatMap(MapleTier.init(rawValue:)) ?? .free
    }

    /// - Parameter usesPreview: A DEBUG demo or sandbox launch, which blocks with the preview blocker. An ordinary
    ///   launch behaves like its tier.
    public static func capability(tier: MapleTier, usesPreview: Bool) -> BlockingCapability {
        if usesPreview { return .preview }
        switch tier {
        case .free: return .unavailableInBuild
        // `ScreenTimeBlockingService` arrives with F1-paid; until then a paid build can't block either.
        case .paid: return .unavailableInBuild
        }
    }
}

/// A build that can't block: free Release builds (F1-17). The timer still runs, as a plain timer.
public final class UnavailableBlockingService: BlockingService {
    public init() {}

    public var capability: BlockingCapability { .unavailableInBuild }
    public var source: FocusSource { .live }
    public func probe() async -> BlockingProbe { .unavailable }
    public func requestAuthorization() async -> BlockingProbe { .unavailable }
    public func readStore() async -> ShieldStoreState { .empty }

    public func perform(_ op: ShieldOp, selection: Data?) async -> ShieldResult {
        switch op {
        case .apply, .verify: ShieldResult(store: .empty, failure: .notAllowed)
        case .clear, .clearAll: ShieldResult(store: .empty)
        }
    }

    public func releaseAll() async -> ShieldResult { ShieldResult(store: .empty) }
}
```

`MapleKit/Sources/MapleServices/Focus/PreviewBlockingService.swift`:
```swift
#if DEBUG
import Foundation
import MapleCore

/// DEBUG only: a blocker with its "store" in memory, for demo and sandbox launches and tests (F1 design §7.4). Its
/// sessions carry `source: preview`, which only the sandbox credits. It can inject the real failure modes.
public final class PreviewBlockingService: BlockingService {
    public enum Failure: Sendable, Hashable {
        /// Over 50 tokens: iOS accepts the write and blocks nothing, so the read-back is empty.
        case tokenOverflow
        /// Screen Time turned off for Maple: the status stays "allowed" (stale) and the shields vanish.
        case revoked
        case applyFails
        case expiredTokens
    }

    public var authorization: BlockingProbe
    public var failures: Set<Failure>
    public private(set) var store: ShieldStoreState = .empty
    /// Every operation asked for, in order.
    public private(set) var operations: [ShieldOp] = []

    public init(authorization: BlockingProbe = .allowed, failures: Set<Failure> = []) {
        self.authorization = authorization
        self.failures = failures
    }

    public var capability: BlockingCapability { .preview }
    public var source: FocusSource { .preview }

    /// Turns Screen Time off for Maple mid-session, as Settings would.
    public func revoke() {
        failures.insert(.revoked)
        store = .empty
    }

    public func probe() async -> BlockingProbe {
        failures.contains(.revoked) ? .allowed : authorization
    }

    public func requestAuthorization() async -> BlockingProbe {
        if authorization == .notDetermined { authorization = .allowed }
        return authorization
    }

    public func readStore() async -> ShieldStoreState { store }

    public func perform(_ op: ShieldOp, selection: Data?) async -> ShieldResult {
        operations.append(op)
        switch op {
        case .apply(let session):
            guard authorization.isAllowed, !failures.contains(.revoked) else { return ShieldResult(store: store, failure: .notAllowed) }
            if failures.contains(.applyFails) { return ShieldResult(store: store, failure: .applyFailed) }
            if failures.contains(.expiredTokens) { return ShieldResult(store: store, failure: .expiredTokens) }
            if failures.contains(.tokenOverflow) {
                store = .empty
                return ShieldResult(store: store, failure: .readBack)
            }
            store = .applied(session: session)
            return ShieldResult(store: store)
        case .verify(let session):
            return ShieldResult(store: store, failure: store == .applied(session: session) ? nil : .readBack)
        case .clear, .clearAll:
            store = ShieldReconciler.applying([op], to: store)
            return ShieldResult(store: store)
        }
    }

    public func releaseAll() async -> ShieldResult {
        store = .empty
        return ShieldResult(store: store)
    }
}
#endif
```

- [ ] **Step 4: Put the tier in Info.plist**

In `Config/Maple-Info.plist`, add after the `MapleHealthBackgroundDelivery` string:
```xml
	<key>MapleTier</key>
	<string>$(MAPLE_TIER)</string>
```

- [ ] **Step 5: Run the tests and the build**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh > "$WS/test.log" 2>&1; tail -3 "$WS/test.log"; grep -c "warning:" "$WS/test.log"`
Expected: `** TEST SUCCEEDED **` and `0`.

- [ ] **Step 6: Commit**

```bash
git add MapleKit/Sources/MapleServices/Focus MapleKit/Tests/MapleServicesTests/BlockingServiceTests.swift Config/Maple-Info.plist
git commit -m "Blocking boundary: verified shield results, the build's tier, an unavailable service and the DEBUG preview blocker

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 22: The session store

`FocusSessionStore` turns commands into ledger events and verified shield operations, one at a time, replays the ledger after every change, and hands credit to the collection.

**Files:**
- Create: `MapleKit/Sources/MapleCore/Focus/FocusActivityState.swift`
- Create: `MapleKit/Sources/MapleServices/Focus/LiveActivityController.swift`
- Create: `MapleKit/Sources/MapleServices/Focus/FocusSessionStore.swift`
- Test: `MapleKit/Tests/MapleServicesTests/FocusSessionStoreTests.swift`

**Interfaces:**
- Consumes: `FocusLedgerStore`, `MemoryLedgerStore`, `LedgerWriter` (Task 8); `FocusLedger.sessions()`, `SessionRecord` (Task 6); `ShieldReconciler` (Task 7); `HoursCredit` (Task 10); `CollectionStore.applyFocus`, `CollectionSnapshot.focusWindow` (Tasks 9, 13); `BlockingService`, `PreviewBlockingService`, `ShieldResult` (Task 21); `FocusPreset`, `DialLayout` (Task 16); `AppSet` (Task 20); `ReminderPlan.RunningSession` (Task 18).
- Produces:
  - `FocusActivityState(session:now:)` (MapleCore): `sessionID`, `presetName`, `start`, `plannedEnd`, `isPlainTimer`, `breakEnd`;
  - `protocol LiveActivityController: AnyObject` with `reconcile(running:) async`; `NoLiveActivityController`; DEBUG `RecordingLiveActivityController` (`current`, `shownSessions`);
  - `FocusSessionStore(ledger:writer:blocking:collection:credited:liveActivity:appBuild:)`, with:
    - state: `isLedgerReadable`, `isStarting`, `running`, `lastEnded`, `sessions`, `probe`, `blocking`, `now`, `reflections`, `reminderSession`, `lastSessionStart`;
    - commands (all `async`, run one at a time): `refresh()`, `start(_:) -> StartOutcome`, `end(_:)`, `releaseAll()`, `startBreak() -> Bool`, `endBreak()`, `reflect(_:on:)`, `requestAuthorization() -> BlockingProbe`;
    - `displayCredit(at:) -> DisplayCredit` (`today`, `yesterday`, `total`);
    - `StartRequest(preset:minutes:appSet:plainTimer:from:)` and `StartOutcome` (`.started(UUID)`, `.alreadyRunning`, `.ledgerUnavailable`, `.blockingFailed(ShieldFailure)`, `.notRecorded`);
    - `checkpointInterval` (60 s).

**Rulings this task carries:**
- **Order at start:** apply and read back first, then write `sessionStarted` and `shieldApplied` (§7.9: `shieldApplied` only after a read-back). A kill between the two leaves orphan shields, which the next refresh clears (Review Focus 3). A write that fails clears the shields at once.
- **Shields found missing** for a running session write `shieldLost`; they are never silently re-applied, so the session carries on as a plain timer and credit stops at the last checkpoint (§3.3).
- **Overrides** ("Need it?" unlocks) come from the F1-paid shield action extension, so the store has no override command yet. The ledger, credit and tests already handle override events.
- **Checkpoints** are written at most once a minute, on refresh, while the read-back still shows the block. F1b's screens call `refresh()` from their timeline.
- **"Release all apps"** clears every store first, then ends a running session as `releaseAll`, unverified, which ends its credit (R4).

- [ ] **Step 1: Write the failing tests**

`MapleKit/Tests/MapleServicesTests/FocusSessionStoreTests.swift`:
```swift
import Foundation
import MapleStorage
import Testing
@testable import MapleCore
@testable import MapleServices

/// A session store on a manual clock, an in-memory ledger and the preview blocker, over a planted collection.
@MainActor
private final class Harness {
    let time = ManualFocusTime(wall: at(2026, 10, 23, 14))
    let ledger = MemoryLedgerStore()
    let blocking: PreviewBlockingService
    let collection: CollectionStore
    let activity = RecordingLiveActivityController()
    let store: FocusSessionStore

    let six = AppSet(id: AppSet.distractionsID, name: "Distractions", selection: Data("six".utf8),
                     summary: SelectionSummary(mode: .blockThese, apps: 6, sites: 0, categories: 0))

    init(authorization: BlockingProbe = .allowed) {
        blocking = PreviewBlockingService(authorization: authorization)
        collection = CollectionStore(storage: JSONStorage(.memory), context: testContext, now: at(2026, 10, 1, 9))
        collection.raise(.firstLeaf, to: 1, at: at(2026, 10, 1, 9))
        collection.openReveals(at: at(2026, 10, 1, 9, 5))
        let writer = LedgerWriter(store: ledger, time: time, deviceID: UUID(), writer: .app, source: blocking.source)
        store = FocusSessionStore(ledger: ledger, writer: writer, blocking: blocking, collection: collection,
                                  credited: [.live, .preview], liveActivity: activity, appBuild: "test")
    }

    func preset(_ index: Int = 0) -> FocusPreset {
        FocusPreset.defaults(appSetID: AppSet.distractionsID)[index]
    }

    func request(minutes: Int = 50, preset index: Int = 0, plain: Bool = false) -> FocusSessionStore.StartRequest {
        FocusSessionStore.StartRequest(preset: preset(index), minutes: minutes, appSet: six, plainTimer: plain, from: .focusTab)
    }

    func advance(minutes: Double) {
        time.advance(minutes * 60)
    }

    var kinds: [String] { ledger.events.map(\.kind.type) }
}

@Suite("Focus session store")
@MainActor
struct FocusSessionStoreTests {
    @Test("A session starts with the block confirmed, completes at its planned end, and its credit reaches the collection")
    func wholeSession() async throws {
        let h = Harness()
        await h.store.refresh()
        let outcome = await h.store.start(h.request())
        guard case .started(let id) = outcome else { Issue.record("\(outcome)"); return }
        #expect(h.kinds == ["sessionStarted", "shieldApplied"])
        #expect(h.blocking.store == .applied(session: id))
        #expect(h.store.running?.id == id)
        #expect(h.activity.current?.sessionID == id)
        #expect(h.store.reminderSession?.plannedEnd == at(2026, 10, 23, 14, 50))

        h.advance(minutes: 50)
        await h.store.refresh()
        #expect(h.store.running == nil)
        #expect(h.store.lastEnded?.id == id)
        #expect(h.store.lastEnded?.endReason == .completed)
        #expect(h.store.lastEnded?.endVerified == true)
        #expect(h.blocking.store == .empty)
        #expect(h.kinds.suffix(2) == ["sessionEnded", "shieldCleared"])
        #expect(h.collection.focus.totalSeconds == 3000)
        #expect(h.collection.snapshot.counters[.sessionsFinished] == 1)
        #expect(h.activity.current == nil)
    }

    @Test("Review Focus 5: a second Start while one is starting or running is refused")
    func doubleStart() async {
        let h = Harness()
        let request = h.request()
        async let first = h.store.start(request)
        async let second = h.store.start(request)
        let outcomes = await [first, second]
        #expect(outcomes.filter { if case .started = $0 { true } else { false } }.count == 1)
        #expect(outcomes.contains(.alreadyRunning))
        #expect(h.kinds.filter { $0 == "sessionStarted" }.count == 1)
        #expect(await h.store.start(h.request()) == .alreadyRunning)
    }

    @Test("Review Focus 3: shields applied before the app was killed, with no session written, are cleared")
    func orphanShields() async {
        let h = Harness()
        let orphan = UUID()
        _ = await h.blocking.perform(.apply(session: orphan), selection: Data("six".utf8))
        await h.store.refresh()
        #expect(h.blocking.store == .empty)
        #expect(h.ledger.events.contains { $0.sessionID == orphan && $0.kind == .shieldCleared(.orphaned) })
        #expect(h.store.running == nil)
    }

    @Test("Review Focus 4: editing the schedule mid-session keeps the session's frozen window")
    func scheduleEdit() async {
        let h = Harness()
        _ = await h.store.start(h.request())
        h.collection.schedule = .everyNight(SleepSchedule(bedtime: ClockTime(hour: 14, minute: 30), wake: ClockTime(hour: 6), windDownMinutes: 30))
        h.advance(minutes: 50)
        await h.store.refresh()
        #expect(h.collection.focus.totalSeconds == 3000)
    }

    @Test("A ledger that can't be read leaves everything alone: no writes, no clears, no start")
    func unreadable() async {
        let h = Harness()
        let orphan = UUID()
        _ = await h.blocking.perform(.apply(session: orphan), selection: Data())
        h.ledger.unreadable = true
        await h.store.refresh()
        #expect(!h.store.isLedgerReadable)
        #expect(h.blocking.store == .applied(session: orphan))
        #expect(await h.store.start(h.request()) == .ledgerUnavailable)
        #expect(h.ledger.events.isEmpty)
    }

    @Test("A block that doesn't verify starts nothing; a session that can't be written lifts its block at once")
    func startFailures() async {
        let failing = Harness()
        failing.blocking.failures = [.applyFails]
        #expect(await failing.store.start(failing.request()) == .blockingFailed(.applyFailed))
        #expect(failing.ledger.events.isEmpty)

        let overflow = Harness()
        overflow.blocking.failures = [.tokenOverflow]
        #expect(await overflow.store.start(overflow.request()) == .blockingFailed(.readBack))

        let unwritable = Harness()
        unwritable.ledger.failsWrites = true
        #expect(await unwritable.store.start(unwritable.request()) == .notRecorded)
        #expect(unwritable.blocking.store == .empty)
        #expect(unwritable.store.running == nil)
    }

    @Test("A plain timer touches no shields and counts nothing")
    func plainTimer() async throws {
        let h = Harness()
        _ = await h.store.start(h.request(plain: true))
        #expect(h.kinds == ["sessionStarted"])
        #expect(h.store.running?.plan.kind == .plainTimer)
        h.advance(minutes: 50)
        await h.store.refresh()
        #expect(h.blocking.operations.isEmpty)
        #expect(h.store.lastEnded?.endReason == .completed)
        #expect(h.collection.focus.totalSeconds == 0)
    }

    @Test("Checkpoints prove time once a minute; revoked access stops credit at the last one")
    func revoked() async {
        let h = Harness()
        _ = await h.store.start(h.request())
        h.advance(minutes: 5)
        await h.store.refresh()
        #expect(h.kinds.last == "shieldVerified")
        await h.store.refresh()
        #expect(h.kinds.filter { $0 == "shieldVerified" }.count == 1)
        h.advance(minutes: 5)
        h.blocking.revoke()
        await h.store.refresh()
        #expect(h.kinds.last == "shieldLost")
        #expect(h.store.running?.lostAt != nil)
        h.advance(minutes: 40)
        await h.store.refresh()
        #expect(h.store.lastEnded?.endVerified == false)
        #expect(h.collection.focus.totalSeconds == 300)
    }

    @Test("Ending early keeps the counted minutes but never finishes")
    func endEarly() async {
        let h = Harness()
        _ = await h.store.start(h.request())
        h.advance(minutes: 20)
        await h.store.end(.endedEarly)
        #expect(h.store.lastEnded?.endReason == .endedEarly)
        #expect(h.blocking.store == .empty)
        #expect(h.collection.focus.totalSeconds == 1200)
        #expect((h.collection.snapshot.counters[.sessionsFinished] ?? 0) == 0)
        #expect(h.activity.current == nil)
    }

    @Test("Release all apps clears every store and ends the session's credit")
    func releaseAll() async {
        let h = Harness()
        _ = await h.store.start(h.request())
        h.advance(minutes: 10)
        await h.store.releaseAll()
        #expect(h.blocking.store == .empty)
        #expect(h.store.lastEnded?.endReason == .releaseAll)
        #expect(h.store.lastEnded?.endVerified == false)
        #expect(h.ledger.events.contains { $0.kind == .shieldCleared(.releaseAll) })
    }

    @Test("One locked break, inside the planned length")
    func breaks() async {
        let h = Harness()
        _ = await h.store.start(h.request())
        h.advance(minutes: 10)
        #expect(await h.store.startBreak())
        #expect(h.ledger.events.last?.kind == .breakStarted(seconds: 300))
        #expect(!(await h.store.startBreak()))
        h.advance(minutes: 2)
        await h.store.endBreak()
        #expect(h.ledger.events.last?.kind == .breakEnded)

        let quick = Harness()
        _ = await quick.store.start(quick.request(minutes: 25, preset: 1))
        #expect(!(await quick.store.startBreak()))
    }

    @Test("Display credit adds the running session's provisional time to what the book has counted")
    func displayCredit() async {
        let h = Harness()
        _ = await h.store.start(h.request())
        h.advance(minutes: 20)
        await h.store.refresh()
        h.advance(minutes: 5)
        let display = h.store.displayCredit(at: h.store.now)
        #expect(display.today == 1500)
        #expect(display.total == 1500)
        #expect(display.yesterday == 0)
        #expect(h.collection.focus.totalSeconds == 1200)
    }

    @Test("Screen Time shows as granted in the collection only while blocking is available and allowed")
    func permissionBridge() async {
        let allowed = Harness()
        await allowed.store.refresh()
        #expect(allowed.collection.context.permissions.contains(.screenTime))
        #expect(allowed.collection.context.blocking == .preview)

        let asking = Harness(authorization: .notDetermined)
        await asking.store.refresh()
        #expect(!asking.collection.context.permissions.contains(.screenTime))
        #expect(await asking.store.requestAuthorization() == .allowed)
        #expect(asking.collection.context.permissions.contains(.screenTime))
    }

    @Test("Reflections are written to the ledger and read back by session")
    func reflections() async throws {
        let h = Harness()
        guard case .started(let id) = await h.store.start(h.request()) else { Issue.record("not started"); return }
        h.advance(minutes: 50)
        await h.store.refresh()
        await h.store.reflect(.partly, on: id)
        #expect(h.store.reflections[id] == .partly)
        #expect(h.store.lastSessionStart == at(2026, 10, 23, 14))
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -only-testing:MapleServicesTests/FocusSessionStoreTests > "$WS/test.log" 2>&1; grep -E "error:" "$WS/test.log" | head -5`
Expected: `error: cannot find 'RecordingLiveActivityController' in scope`

- [ ] **Step 3: Write the Live Activity boundary**

`MapleKit/Sources/MapleCore/Focus/FocusActivityState.swift`:
```swift
import Foundation
import MapleFocusCore

/// What the Live Activity shows for a running session (F1 design §5.11): display only, no buttons. The preset name,
/// never the intention, appears on the Lock Screen.
public struct FocusActivityState: Sendable, Hashable {
    public var sessionID: UUID
    public var presetName: String
    public var start: Date
    public var plannedEnd: Date
    public var isPlainTimer: Bool
    /// When a running break ends ("Break · back at 14:28"); nil outside a break.
    public var breakEnd: Date?

    public init(session: SessionRecord, now: Date) {
        sessionID = session.id
        presetName = session.plan.presetName
        start = session.countdownStart
        plannedEnd = session.plannedEnd
        isPlainTimer = session.plan.kind == .plainTimer
        breakEnd = session.breakEnd(at: now)
    }
}
```

`MapleKit/Sources/MapleServices/Focus/LiveActivityController.swift`:
```swift
import Foundation
import MapleCore

/// The running session's Live Activity, behind a protocol so the store never imports ActivityKit. F1b adds the
/// ActivityKit controller.
public protocol LiveActivityController: AnyObject {
    /// Shows `state`, or ends every Maple activity when it is nil, reconnecting to one already running. Called
    /// after every change; calling it again with the same state changes nothing.
    func reconcile(running state: FocusActivityState?) async
}

/// No Live Activity: tests, and builds before F1b.
public final class NoLiveActivityController: LiveActivityController {
    public init() {}
    public func reconcile(running state: FocusActivityState?) async {}
}

#if DEBUG
/// DEBUG only: remembers what it was asked to show.
public final class RecordingLiveActivityController: LiveActivityController {
    public private(set) var current: FocusActivityState?
    /// Each session it began showing, in order.
    public private(set) var shownSessions: [UUID] = []

    public init() {}

    public func reconcile(running state: FocusActivityState?) async {
        if let state, state.sessionID != current?.sessionID { shownSessions.append(state.sessionID) }
        current = state
    }
}
#endif
```

- [ ] **Step 4: Write the store**

`MapleKit/Sources/MapleServices/Focus/FocusSessionStore.swift`:
```swift
import Foundation
import MapleCore
import MapleStorage
import Observation

/// Focus sessions (F1 design §7.4). Turns the member's commands into ledger events and verified shield operations,
/// replays the ledger after every change, and hands each replay's credit to `CollectionStore.applyFocus`.
///
/// - Commands run one at a time, in order.
/// - The block is applied and read back before `sessionStarted` is written; a session that can't be written lifts its
///   block at once. Final clears (a session's end, "Release all apps") always run, written or not.
/// - While the ledger can't be read the store is in an unknown state: it neither writes nor clears.
/// - A running session whose shields go missing is marked `shieldLost` and carries on as a plain timer.
@Observable
public final class FocusSessionStore {
    public struct StartRequest: Sendable {
        public var preset: FocusPreset
        /// This session's length (the dial can differ from the preset's); kept to 20 minutes–3 hours.
        public var minutes: Int
        /// The app set to block; nil starts a plain timer.
        public var appSet: AppSet?
        /// The member chose "Use a plain timer".
        public var plainTimer: Bool
        public var from: StartSource

        public init(preset: FocusPreset, minutes: Int, appSet: AppSet?, plainTimer: Bool = false, from: StartSource) {
            self.preset = preset
            self.minutes = minutes
            self.appSet = appSet
            self.plainTimer = plainTimer
            self.from = from
        }
    }

    public enum StartOutcome: Sendable, Equatable {
        case started(UUID)
        /// A session is starting or running: a second tap does nothing.
        case alreadyRunning
        case ledgerUnavailable
        /// "Couldn't lock your apps · Start as a plain timer?"
        case blockingFailed(ShieldFailure)
        /// The ledger couldn't be written; the block was lifted.
        case notRecorded
    }

    /// Seconds saved, counted plus the running session's provisional time: what the dial and Home show.
    public struct DisplayCredit: Sendable, Equatable {
        public var today: Int
        public var yesterday: Int
        public var total: Int
    }

    /// The shortest gap between two written checkpoints.
    public static let checkpointInterval: TimeInterval = 60

    public private(set) var isLedgerReadable = false
    public private(set) var isStarting = false
    public private(set) var sessions: [SessionRecord] = []
    public private(set) var running: SessionRecord?
    /// The session that ended last while this store watched: the receipt's.
    public private(set) var lastEnded: SessionRecord?
    public private(set) var probe: BlockingProbe = .notDetermined

    @ObservationIgnored public let blocking: any BlockingService
    @ObservationIgnored private let ledger: any FocusLedgerStore
    @ObservationIgnored private let writer: LedgerWriter
    @ObservationIgnored private let collection: CollectionStore
    @ObservationIgnored private let credited: Set<FocusSource>
    @ObservationIgnored private let liveActivity: any LiveActivityController
    @ObservationIgnored private let appBuild: String
    @ObservationIgnored private var queue: Task<Void, Never>?

    /// - Parameters:
    ///   - writer: The app's writer, whose time source is the store's clock (a shifted one in demos).
    ///   - credited: The sources whose events earn credit: `live`, plus `preview` in the sandbox (§7.6).
    public init(
        ledger: any FocusLedgerStore, writer: LedgerWriter, blocking: any BlockingService, collection: CollectionStore,
        credited: Set<FocusSource>, liveActivity: any LiveActivityController, appBuild: String
    ) {
        self.ledger = ledger
        self.writer = writer
        self.blocking = blocking
        self.collection = collection
        self.credited = credited
        self.liveActivity = liveActivity
        self.appBuild = appBuild
    }

    /// The store's "now", from the writer's time source.
    public var now: Date { writer.time.stamp().wall }

    /// Each session's reflection, for the intention chips.
    public var reflections: [UUID: Reflection] {
        Dictionary(sessions.compactMap { session in session.reflection.map { (session.id, $0) } }, uniquingKeysWith: { $1 })
    }

    /// The running session, for its end reminder.
    public var reminderSession: ReminderPlan.RunningSession? {
        running.map {
            ReminderPlan.RunningSession(id: $0.id, plannedEnd: $0.plannedEnd, presetName: $0.plan.presetName,
                                        plannedMinutes: $0.plan.plannedMinutes, isPlainTimer: $0.plan.kind == .plainTimer)
        }
    }

    /// When the latest session started, so the study reminder skips that day.
    public var lastSessionStart: Date? { sessions.last?.started.placed }

    // MARK: Commands

    /// Replays the ledger, ends a session whose planned end has passed, writes a checkpoint, matches the shields to the
    /// ledger, applies credit and updates the Live Activity. Call it on launch, on every return to the foreground and
    /// from a running session's timeline.
    public func refresh() async {
        await serially { [self] in
            guard replay() else { return }
            let now = self.now
            probe = await blocking.probe()
            syncPermission()
            if let session = running {
                if now >= session.plannedEnd {
                    await finish(session, reason: .completed)
                } else if session.plan.kind == .blocking, session.lostAt == nil {
                    await checkpoint(session, now: now)
                }
            }
            await reconcileShields(now: now)
            await settle(now: now)
        }
    }

    public func start(_ request: StartRequest) async -> StartOutcome {
        // Checked before any await, so a second tap during the first start is refused.
        guard !isStarting, running == nil else { return .alreadyRunning }
        isStarting = true
        defer { isStarting = false }
        return await serially { [self] in await performStart(request) }
    }

    /// Ends the running session now: `.completed` at its end, `.endedEarly` or `.emergencyRelease` before it.
    public func end(_ reason: EndReason) async {
        await serially { [self] in
            guard replay(), let session = running else { return }
            await finish(session, reason: reason)
            await settle(now: now)
        }
    }

    /// Settings › Release all apps: clears every store, then ends a running session's credit (R4).
    public func releaseAll() async {
        await serially { [self] in
            _ = await blocking.releaseAll()
            guard replay() else { return }
            if let session = running {
                _ = try? writer.write(.sessionEnded(.releaseAll, verified: false), session: session.id)
                _ = try? writer.write(.shieldCleared(.releaseAll), session: session.id)
                replay()
                lastEnded = sessions.first { $0.id == session.id }
            }
            await settle(now: now)
        }
    }

    /// Starts the preset's one locked break, cut short at the planned end (F1-11).
    /// - Returns: False when there is no break to take.
    public func startBreak() async -> Bool {
        await serially { [self] in
            guard replay(), let session = running, session.plan.breakSeconds > 0, !session.breakUsed else { return false }
            let seconds = min(session.plan.breakSeconds, Int(session.plannedEnd.timeIntervalSince(now)))
            guard seconds > 0, (try? writer.write(.breakStarted(seconds: seconds), session: session.id)) != nil else { return false }
            await settle(now: now)
            return true
        }
    }

    /// "Back to studying" before the break runs out.
    public func endBreak() async {
        await serially { [self] in
            guard replay(), let session = running, session.breakEnd(at: now) != nil else { return }
            _ = try? writer.write(.breakEnded, session: session.id)
            await settle(now: now)
        }
    }

    /// The receipt's "How did it go?".
    public func reflect(_ reflection: Reflection, on session: UUID) async {
        await serially { [self] in
            guard replay() else { return }
            _ = try? writer.write(.reflected(reflection), session: session)
            replay()
        }
    }

    /// Asks for Screen Time once (Needs Screen Time's "Turn on Screen Time").
    public func requestAuthorization() async -> BlockingProbe {
        await serially { [self] in
            probe = await blocking.requestAuthorization()
            syncPermission()
            return probe
        }
    }

    // MARK: Reading

    public func displayCredit(at date: Date) -> DisplayCredit {
        let today = collection.snapshot.focusWindow(at: date, context: collection.context).day
        let yesterday = today.adding(days: -1, calendar: collection.context.calendar)
        let book = collection.focus
        var provisional = 0
        if let running, running.plan.day == today {
            provisional = HoursCredit.provisionalSeconds(for: running, now: date, roomLeftToday: HoursCredit.dailyCap - book.seconds(on: today))
        }
        return DisplayCredit(today: book.seconds(on: today) + provisional, yesterday: book.seconds(on: yesterday),
                             total: book.totalSeconds + provisional)
    }

    // MARK: Private

    private func serially<Result: Sendable>(_ body: @escaping @MainActor @Sendable () async -> Result) async -> Result {
        let previous = queue
        let task = Task { @MainActor in
            await previous?.value
            return await body()
        }
        queue = Task { _ = await task.value }
        return await task.value
    }

    /// Reads the open ledger and rebuilds the sessions. False, with nothing changed, when it can't be read.
    @discardableResult
    private func replay() -> Bool {
        guard let events = ledger.readOpen(now: now) else {
            isLedgerReadable = false
            return false
        }
        isLedgerReadable = true
        sessions = FocusLedger(events).sessions()
        running = sessions.last { !$0.isEnded && !$0.isHidden }
        return true
    }

    private func performStart(_ request: StartRequest) async -> StartOutcome {
        guard replay() else { return .ledgerUnavailable }
        guard running == nil else { return .alreadyRunning }
        let now = self.now
        let context = collection.context
        let frozen = collection.snapshot.focusWindow(at: now, context: context)
        let blocks = !request.plainTimer && blocking.capability.canBlock && request.appSet != nil
        let minutes = DialLayout.stepped(request.minutes, by: 0)
        let plan = FocusPlan(
            presetID: request.preset.id, presetName: request.preset.name, verb: request.preset.verb, plannedSeconds: minutes * 60,
            breakSeconds: request.preset.hasBreak ? FocusPreset.breakSeconds : 0, strictness: request.preset.strictness(on: frozen.day),
            kind: blocks ? .blocking : .plainTimer, appSetID: blocks ? request.appSet?.id : nil,
            selection: blocks ? request.appSet?.summary : nil, startedFrom: request.from, mapleDay: frozen.day.description,
            window: frozen.window, zone: context.calendar.timeZone.identifier, appBuild: appBuild, rulesVersion: FocusRules.version
        )
        let id = UUID()
        if blocks, let appSet = request.appSet {
            let result = await blocking.perform(.apply(session: id), selection: appSet.selection)
            guard result.isVerified else {
                if result.store == .applied(session: id) { _ = await blocking.perform(.clear(session: id), selection: nil) }
                return .blockingFailed(result.failure ?? .applyFailed)
            }
        }
        do {
            try writer.write(.sessionStarted(plan), session: id)
            if blocks { try writer.write(.shieldApplied, session: id) }
        } catch {
            if blocks { _ = await blocking.perform(.clear(session: id), selection: nil) }
            replay()
            return .notRecorded
        }
        await settle(now: now)
        return .started(id)
    }

    /// Ends `session`: a last read-back, the end event, then the final clear, which always runs.
    private func finish(_ session: SessionRecord, reason: EndReason) async {
        let blocks = session.plan.kind == .blocking
        var verified = false
        if blocks, session.lostAt == nil {
            verified = await blocking.perform(.verify(session: session.id), selection: nil).isVerified
        }
        _ = try? writer.write(.sessionEnded(reason, verified: verified), session: session.id)
        if blocks {
            _ = await blocking.perform(.clear(session: session.id), selection: nil)
            _ = try? writer.write(.shieldCleared(.sessionEnded), session: session.id)
        }
        replay()
        lastEnded = sessions.first { $0.id == session.id }
    }

    /// Proves the block is still there (at most once a minute), or marks it lost.
    private func checkpoint(_ session: SessionRecord, now: Date) async {
        let result = await blocking.perform(.verify(session: session.id), selection: nil)
        if result.isVerified {
            let last = session.lastCheckpoint ?? session.countdownStart
            if now.timeIntervalSince(last) >= Self.checkpointInterval {
                _ = try? writer.write(.shieldVerified, session: session.id)
            }
        } else {
            _ = try? writer.write(.shieldLost, session: session.id)
        }
        replay()
    }

    /// Clears shields the ledger doesn't explain (orphans); marks a running session's missing shields as lost.
    private func reconcileShields(now: Date) async {
        let store = await blocking.readStore()
        let wanted = running.flatMap { $0.plan.kind == .blocking && $0.lostAt == nil ? $0 : nil }
        for op in ShieldReconciler.ops(running: wanted, store: store, now: now) {
            switch op {
            case .clear(let session):
                _ = await blocking.perform(op, selection: nil)
                _ = try? writer.write(.shieldCleared(.orphaned), session: session)
            case .apply(let session):
                // Never re-applied silently: proof stops at the last checkpoint (§3.3).
                _ = try? writer.write(.shieldLost, session: session)
            case .verify, .clearAll:
                break
            }
        }
        replay()
    }

    /// Credit to the collection, then the Live Activity.
    private func settle(now: Date) async {
        replay()
        collection.applyFocus(HoursCredit.credit(sessions, crediting: credited, now: now), at: now)
        await liveActivity.reconcile(running: running.map { FocusActivityState(session: $0, now: now) })
    }

    /// Grants `.screenTime` in the collection while blocking is available and allowed, as `HealthPermission` does
    /// for Apple Health, and tells it what this build can do.
    private func syncPermission() {
        var context = collection.context
        context.blocking = blocking.capability
        if blocking.capability.canBlock, probe.isAllowed {
            context.permissions.insert(.screenTime)
        } else {
            context.permissions.remove(.screenTime)
        }
        if context != collection.context { collection.context = context }
    }
}
```

`FocusRules` is in MapleFocusCore, which MapleCore re-exports. If the compiler asks for it under `MemberImportVisibility`, add `import MapleFocusCore` beside the other imports.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -only-testing:MapleServicesTests/FocusSessionStoreTests > "$WS/test.log" 2>&1; tail -3 "$WS/test.log"`
Expected: `** TEST SUCCEEDED **`. If the double-start test is flaky, the guard in `start(_:)` is running after an `await`; it must stay the first statement.

- [ ] **Step 6: Run everything**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh > "$WS/test.log" 2>&1; tail -3 "$WS/test.log"; grep -c "warning:" "$WS/test.log"`
Expected: `** TEST SUCCEEDED **` and `0`.

- [ ] **Step 7: Commit**

```bash
git add MapleKit/Sources/MapleCore/Focus/FocusActivityState.swift MapleKit/Sources/MapleServices/Focus MapleKit/Tests/MapleServicesTests/FocusSessionStoreTests.swift
git commit -m "Focus session store: verified starts, serial commands, checkpoints, orphan clears, credit and display credit

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 23: Live, demo and sandbox launches

Each launch gets its Focus stores (F1 design §7.6): live ones on files, demo ones in memory, and a DEBUG sandbox with its own complete container where whole sessions run against the preview blocker.

**Files:**
- Create: `MapleKit/Sources/MapleServices/Focus/FocusStores.swift`
- Modify: `MapleKit/Sources/MapleServices/MapleStores.swift` (a `focus` field; the sandbox launch)
- Modify: `MapleKit/Sources/MapleServices/Demo/DemoLaunchOptions.swift` (`sandbox`, `sessionSeconds`)
- Modify: `MapleKit/Sources/MapleServices/Focus/FocusSessionStore.swift` (`plannedSecondsOverride`)
- Test: `MapleKit/Tests/MapleServicesTests/LaunchModeTests.swift`

**Interfaces:**
- Consumes: Tasks 8, 20, 21 and 22.
- Produces:
  - `LaunchMode` (`.live`, `.demo`, `.sandbox`), with `credited: Set<FocusSource>` and `usesPreview`;
  - `FocusStores` (`sessions`, `presets`, `appSets`, `notes`, `mode`), with `FocusStores.live(directory:collection:tier:)` and DEBUG `FocusStores.demo(collection:clock:)` and `FocusStores.sandbox(directory:collection:sessionSeconds:)`;
  - `FocusStores.ledgerFolder` (`Ledger`) and `MapleStores.sandboxFolder` (`Sandbox`);
  - `MapleStores.focus: FocusStores`, and `MapleStores.live(directory:calendar:now:healthAuthorizer:focusMode:sessionSeconds:)`;
  - `FocusSessionStore`'s init gains `plannedSecondsOverride: Int? = nil`;
  - `DemoLaunchOptions.sandbox: Bool` (`-MapleDemoSandbox YES`) and `DemoLaunchOptions.sessionSeconds: Int?` (`-MapleDemoSessionSeconds <n>`).

**Rulings this task carries:**
- **Demo launches credit `live` and `preview` events in memory.** The §7.6 table's "nothing new" means nothing new is saved; crediting the in-memory collection keeps a demo session's dial and leaves honest, and nothing reaches the live files.
- **The other Focus DEBUG arguments** (`-MapleDemoShip`, `-MapleDemoFocus` and the rest of §8.2) arrive with F1b's screens, which are what they open. The stores already accept any seeded ledger and time source, which is all a scenario needs.
- **`MapleApp` doesn't inject the Focus stores yet;** F1b does, with the screens that read them. Building them at launch has one side effect: `device-id.txt` is created in the container.
- **A device id that can't be read yet** (before the first unlock) gets a random id for that launch. Its events stay valid and simply carry a different device id.

- [ ] **Step 1: Write the failing tests**

`MapleKit/Tests/MapleServicesTests/LaunchModeTests.swift`:
```swift
import Foundation
import Testing
@testable import MapleCore
@testable import MapleServices

@Suite("Launch modes")
@MainActor
struct LaunchModeTests {
    @Test("Each mode credits its own sources and blocks with the right service")
    func modes() {
        #expect(LaunchMode.live.credited == [.live])
        #expect(LaunchMode.demo.credited == [.live, .preview])
        #expect(LaunchMode.sandbox.credited == [.live, .preview])
        #expect(!LaunchMode.live.usesPreview && LaunchMode.demo.usesPreview && LaunchMode.sandbox.usesPreview)
    }

    @Test("Sandbox arguments are demo arguments")
    func arguments() {
        let options = DemoLaunchOptions(arguments: ["Maple", "-MapleDemoSandbox", "YES", "-MapleDemoSessionSeconds", "90"])
        #expect(options.sandbox)
        #expect(options.sessionSeconds == 90)
        #expect(options.isActive)
        #expect(!DemoLaunchOptions(arguments: ["Maple"]).sandbox)
    }

    @Test("A live launch keeps its ledger in the container and can't block on a free build")
    func live() throws {
        let folder = try temporaryDirectory()
        let stores = MapleStores.live(directory: folder, calendar: utc, now: at(2026, 10, 23, 9), healthAuthorizer: FakeHealthAuthorizer())
        #expect(stores.focus.mode == .live)
        #expect(stores.focus.sessions.blocking.capability == .unavailableInBuild)
        #expect(files(in: folder).contains(DeviceIdentity.file))
    }

    @Test("A demo launch runs a session in memory and writes nothing to the live files")
    func demo() async throws {
        let folder = try temporaryDirectory()
        let stores = MapleStores.make(DemoLaunchOptions(arguments: ["-MapleDemoSpecies", "10"]), directory: folder, calendar: utc,
                                      now: at(2026, 10, 23, 9))
        #expect(stores.focus.mode == .demo)
        #expect(stores.focus.sessions.blocking.capability == .preview)
        let preset = try #require(stores.focus.presets.lastUsed)
        let outcome = await stores.focus.sessions.start(.init(preset: preset, minutes: 25,
                                                              appSet: stores.focus.appSets.set(id: AppSet.distractionsID), from: .focusTab))
        #expect(stores.focus.sessions.running != nil, "\(outcome)")
        #expect(files(in: folder).isEmpty)
    }

    @Test("The sandbox is a complete parallel container, with short sessions when asked")
    func sandbox() async throws {
        let folder = try temporaryDirectory()
        let stores = MapleStores.live(directory: folder.appending(path: MapleStores.sandboxFolder), calendar: utc, now: at(2026, 10, 23, 9),
                                      healthAuthorizer: FakeHealthAuthorizer(), focusMode: .sandbox, sessionSeconds: 90)
        #expect(stores.focus.mode == .sandbox)
        #expect(stores.focus.sessions.blocking.capability == .preview)
        let preset = try #require(stores.focus.presets.lastUsed)
        _ = await stores.focus.sessions.start(.init(preset: preset, minutes: 50, appSet: stores.focus.appSets.set(id: AppSet.distractionsID),
                                                    from: .focusTab))
        #expect(stores.focus.sessions.running?.plan.plannedSeconds == 90)
        #expect(files(in: folder) == [MapleStores.sandboxFolder])
        #expect(files(in: folder.appending(path: MapleStores.sandboxFolder)).contains(FocusStores.ledgerFolder))
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -only-testing:MapleServicesTests/LaunchModeTests > "$WS/test.log" 2>&1; grep -E "error:" "$WS/test.log" | head -5`
Expected: `error: cannot find 'LaunchMode' in scope`

- [ ] **Step 3: Write the Focus stores and modes**

`MapleKit/Sources/MapleServices/Focus/FocusStores.swift`:
```swift
import Foundation
import MapleCore
import MapleStorage

/// Where a launch's Focus data lives and what it credits (F1 design §7.6).
public enum LaunchMode: Sendable, Equatable {
    /// Files in the container; `live` events credit. Release and ordinary DEBUG runs.
    case live
    /// DEBUG `-MapleDemo…` launches: memory only, with the preview blocker. Nothing touches the live files.
    case demo
    /// DEBUG `-MapleDemoSandbox YES`: its own folder, the preview blocker, and preview events credit.
    case sandbox

    public var credited: Set<FocusSource> { self == .live ? [.live] : [.live, .preview] }
    public var usesPreview: Bool { self != .live }
}

/// A launch's Focus stores.
public struct FocusStores {
    /// The ledger's folder inside the container.
    public static let ledgerFolder = "Ledger"

    public let sessions: FocusSessionStore
    public let presets: PresetStore
    public let appSets: AppSetStore
    public let notes: SessionNotesStore
    public let mode: LaunchMode

    /// Files in `directory`. The blocker follows the build's tier (an ordinary DEBUG launch behaves like its tier).
    public static func live(
        directory: URL, collection: CollectionStore, tier: MapleTier = MapleBuild.tier
    ) -> FocusStores {
        // F1-paid: ScreenTimeBlockingService when MapleBuild.capability(tier:usesPreview: false) is .screenTime. Until
        // then no live launch can block.
        return files(directory: directory, collection: collection, mode: .live, blocking: UnavailableBlockingService(), sessionSeconds: nil)
    }

    private static func files(
        directory: URL, collection: CollectionStore, mode: LaunchMode, blocking: any BlockingService, sessionSeconds: Int?
    ) -> FocusStores {
        let deviceID = DeviceIdentity.load(in: directory) ?? UUID()
        let ledger = FileLedgerStore(directory: directory.appending(path: ledgerFolder, directoryHint: .isDirectory))
        let writer = LedgerWriter(store: ledger, time: LiveFocusTime(deviceID: deviceID), deviceID: deviceID, writer: .app,
                                  source: blocking.source)
        return FocusStores(
            sessions: FocusSessionStore(ledger: ledger, writer: writer, blocking: blocking, collection: collection, credited: mode.credited,
                                        liveActivity: NoLiveActivityController(), appBuild: appBuild,
                                        plannedSecondsOverride: sessionSeconds),
            presets: PresetStore(storage: JSONStorage(.file(directory.appending(path: PresetStore.file))), defaultAppSetID: AppSet.distractionsID),
            appSets: AppSetStore(storage: JSONStorage(.file(directory.appending(path: AppSetStore.file)))),
            notes: SessionNotesStore(storage: JSONStorage(.file(directory.appending(path: SessionNotesStore.file)))),
            mode: mode
        )
    }

    private static var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev"
    }

    #if DEBUG
    /// Memory only, on the demo clock's offset, with the preview blocker.
    public static func demo(collection: CollectionStore, clock: MapleClock) -> FocusStores {
        let deviceID = UUID()
        let ledger = MemoryLedgerStore()
        let blocking = PreviewBlockingService()
        let time = ShiftedFocusTime(base: LiveFocusTime(deviceID: deviceID), offset: clock.offset)
        let writer = LedgerWriter(store: ledger, time: time, deviceID: deviceID, writer: .app, source: blocking.source)
        return FocusStores(
            sessions: FocusSessionStore(ledger: ledger, writer: writer, blocking: blocking, collection: collection,
                                        credited: LaunchMode.demo.credited, liveActivity: NoLiveActivityController(), appBuild: appBuild),
            presets: PresetStore(storage: JSONStorage(.memory), defaultAppSetID: AppSet.distractionsID),
            appSets: AppSetStore(storage: JSONStorage(.memory)),
            notes: SessionNotesStore(storage: JSONStorage(.memory)),
            mode: .demo
        )
    }

    /// Files in the sandbox's own folder, with the preview blocker; `sessionSeconds` makes sessions short, in real time.
    public static func sandbox(directory: URL, collection: CollectionStore, sessionSeconds: Int?) -> FocusStores {
        files(directory: directory, collection: collection, mode: .sandbox, blocking: PreviewBlockingService(), sessionSeconds: sessionSeconds)
    }
    #endif
}
```
The `tier` parameter is the F1-paid hook: `ScreenTimeBlockingService` replaces the unavailable one there.

- [ ] **Step 4: Wire the launches**

In `MapleKit/Sources/MapleServices/Focus/FocusSessionStore.swift`:
- add `@ObservationIgnored private let plannedSecondsOverride: Int?` after `appBuild`;
- add the init parameter `plannedSecondsOverride: Int? = nil` after `appBuild: String`, with the doc line `///   - plannedSecondsOverride: DEBUG sandbox only: every session lasts this long (`-MapleDemoSessionSeconds`).` and `self.plannedSecondsOverride = plannedSecondsOverride`;
- in `performStart`, change `plannedSeconds: minutes * 60` to `plannedSeconds: plannedSecondsOverride ?? minutes * 60`.

In `MapleKit/Sources/MapleServices/Demo/DemoLaunchOptions.swift`:
- add `public var sandbox = false` and `public var sessionSeconds: Int?` after `day`, each with a doc line (`/// -MapleDemoSandbox YES: the sandbox container (F1 design §7.6).`, `/// -MapleDemoSessionSeconds <n>: sandbox sessions last n seconds, in real time.`);
- in `init(arguments:)`, add `sandbox = flag("MapleDemoSandbox")` and `sessionSeconds = count("MapleDemoSessionSeconds").flatMap { $0 > 0 ? $0 : nil }`.

In `MapleKit/Sources/MapleServices/MapleStores.swift`:
- add `public let focus: FocusStores` after `health`, and `public static let sandboxFolder = "Sandbox"` after `sharesFile`;
- give `live(...)` two more parameters, `focusMode: LaunchMode = .live, sessionSeconds: Int? = nil`, and before `var stores = …` build
```swift
        let focus: FocusStores
        #if DEBUG
        focus = focusMode == .sandbox
            ? .sandbox(directory: directory, collection: collection, sessionSeconds: sessionSeconds)
            : .live(directory: directory, collection: collection)
        #else
        focus = .live(directory: directory, collection: collection)
        #endif
```
  then pass `focus: focus` in the `MapleStores(...)` call (after `health: health`), and set `stores.isLive = focusMode == .live`;
- in `make(...)`, at the top, add
```swift
        if options.sandbox {
            return live(directory: directory.appending(path: sandboxFolder, directoryHint: .isDirectory), calendar: calendar,
                        now: now, focusMode: .sandbox, sessionSeconds: options.sessionSeconds)
        }
```
  and pass `focus: .demo(collection: collection, clock: clock)` in its `MapleStores(...)` call.

`isLive` stays false for the sandbox, so nothing that treats the live store specially (the system calendar, Health's background delivery) runs against the sandbox's files.

- [ ] **Step 5: Run the tests and the build**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh > "$WS/test.log" 2>&1; tail -3 "$WS/test.log"; grep -c "warning:" "$WS/test.log"`
Expected: `** TEST SUCCEEDED **` and `0`.

- [ ] **Step 6: Commit**

```bash
git add MapleKit/Sources/MapleServices MapleKit/Tests/MapleServicesTests/LaunchModeTests.swift
git commit -m "Launch modes: live Focus stores on files, demo ones in memory, and a DEBUG sandbox container with short sessions

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 24: Speed limits and the Release check

**Files:**
- Test: `MapleKit/Tests/MapleCoreTests/FocusPerformanceTests.swift`
- Create: `Scripts/check-release.sh`

**Interfaces:**
- Consumes: `FocusDay` (Task 10), `FocusLedger`, `HoursCredit`, `FocusBook`, `FocusRuns`, `FocusCounters`.
- Produces: `Scripts/check-release.sh`, which exits non-zero when a Release build contains demo or preview code.

- [ ] **Step 1: Write the speed tests**

`MapleKit/Tests/MapleCoreTests/FocusPerformanceTests.swift`:
```swift
import Foundation
import Testing
@testable import MapleCore

/// F1 design §8.1: replaying the open days stays well inside a frame budget, and a full rebuild of years of sessions
/// stays under a second, in the Debug simulator.
@Suite("Focus performance")
struct FocusPerformanceTests {
    /// Two sessions a day (50 and 25 minutes) for `days` days, each in its own day's awake window.
    private func synthetic(days: Int) -> [FocusEvent] {
        let first = at(2023, 10, 23, 9)
        let day = FocusDay(first)
        for index in 0..<days {
            let morning = first.addingTimeInterval(Double(index) * 86_400)
            let label = LocalDay(morning, calendar: utc).description
            let window = AwakeWindow(start: morning.addingTimeInterval(-3 * 3600), end: morning.addingTimeInterval(14 * 3600),
                                     windDown: morning.addingTimeInterval(13 * 3600))
            day.at(morning)
            day.session(minutes: 50, plan: FocusFixtures.plan(day: label, window: window))
            day.at(morning.addingTimeInterval(4 * 3600))
            day.session(minutes: 25, plan: FocusFixtures.plan(minutes: 25, day: label, window: window))
        }
        return day.events
    }

    private func rebuild(_ events: [FocusEvent]) -> FocusBook {
        var book = FocusBook()
        book.record(HoursCredit.credit(FocusLedger(events).sessions(), crediting: [.live], now: .distantFuture))
        _ = FocusCounters.marks(book: book)
        _ = FocusRuns(focusDays: book.focusDays, today: LocalDay(year: 2026, month: 10, day: 23))
        return book
    }

    @Test("Replaying two months of open days takes under 50 ms")
    func openDays() {
        let events = synthetic(days: 62)
        var book = FocusBook()
        let elapsed = ContinuousClock().measure { book = rebuild(events) }
        #expect(book.days.count == 62)
        #expect(elapsed < .milliseconds(50), "\(elapsed)")
    }

    @Test("Rebuilding 3 years of sessions takes under a second")
    func threeYears() {
        let events = synthetic(days: 3 * 365)
        var book = FocusBook()
        let elapsed = ContinuousClock().measure { book = rebuild(events) }
        #expect(book.days.count == 3 * 365)
        #expect(book.totalFinished == 2 * 3 * 365)
        #expect(elapsed < .seconds(1), "\(elapsed)")
    }
}
```

- [ ] **Step 2: Run them**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -only-testing:MapleCoreTests/FocusPerformanceTests > "$WS/test.log" 2>&1; tail -3 "$WS/test.log"; grep -E "Expectation failed" "$WS/test.log" | head -3`
Expected: `** TEST SUCCEEDED **`. They test code that already exists, so they may pass at once; a limit's job is to catch a later slowdown. If either limit fails, profile before changing anything: the likely costs are `FocusLedger`'s placement (it must sort once, not per event) and `FocusRuns.fits` (it sorts the run's rest days on every gap). Fix the slow step, keep every other test green, and record the change as a ruling.

- [ ] **Step 3: Write the Release check**

`Scripts/check-release.sh`:
```zsh
#!/bin/zsh
# Builds Maple in Release for the iPhone simulator and fails if any DEBUG-only demo or preview type made it into the
# binary (F1 design §8.4). Run from anywhere: Scripts/check-release.sh
set -euo pipefail
cd "${0:A:h}/.."
SIMULATOR="${SIMULATOR:-iPhone 17}"
DERIVED_DATA="${DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/Maple-release-$(pwd -P | shasum | cut -c1-8)}"
xcodebuild build \
  -project Maple.xcodeproj -scheme Maple -configuration Release \
  -destination "platform=iOS Simulator,name=$SIMULATOR" \
  -derivedDataPath "$DERIVED_DATA" CODE_SIGNING_ALLOWED=NO -quiet
BINARY="$DERIVED_DATA/Build/Products/Release-iphonesimulator/Maple.app/Maple"
FORBIDDEN='PreviewBlockingService|RecordingLiveActivityController|DemoLaunchOptions|DemoData|PreviewLeafShareProvider|HealthSleepSeeder|FocusDemo'
FOUND=$( { nm "$BINARY" | xcrun swift-demangle; strings - "$BINARY"; } | grep -Eo "$FORBIDDEN" | sort -u || true)
if [[ -n "$FOUND" ]]; then
  echo "Release build contains DEBUG-only code:"
  echo "$FOUND"
  exit 1
fi
echo "Release build has no demo or preview code."
```

Run: `chmod +x Scripts/check-release.sh && Scripts/check-release.sh > "$WS/release.log" 2>&1; tail -3 "$WS/release.log"`
Expected: `Release build has no demo or preview code.`

If the Release build itself fails, read the first `error:` in the log. A DEBUG-only type used outside `#if DEBUG` is the usual cause; wrap the use, never the type's definition, and record it as a ruling.

- [ ] **Step 4: Prove the check can fail**

Temporarily delete the `#if DEBUG` line and its matching `#endif` in `MapleKit/Sources/MapleServices/Focus/PreviewBlockingService.swift`, run `Scripts/check-release.sh > "$WS/release.log" 2>&1; tail -3 "$WS/release.log"`, and expect `PreviewBlockingService` under "Release build contains DEBUG-only code:". Then restore the file with `git checkout MapleKit/Sources/MapleServices/Focus/PreviewBlockingService.swift` and run the check again to see it pass.

- [ ] **Step 5: Commit**

```bash
git add MapleKit/Tests/MapleCoreTests/FocusPerformanceTests.swift Scripts/check-release.sh
git commit -m "Focus speed limits (open days under 50 ms, 3 years under 1 s) and a Release check for DEBUG-only code

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 25: The docs

**Files:**
- Modify: `docs/core-api.md` (a Focus section; the Home, Reminders and Shipped features sections)
- Modify: `docs/debug-launch-arguments.md` (two rows)
- Modify: `docs/architecture.md` (the new modules)

**Interfaces:**
- Consumes: everything above.
- Produces: docs only.

- [ ] **Step 1: Add the Focus section to core-api.md**

In `docs/core-api.md`, insert before `## Files, unlocks and time zones`:
````markdown
## Focus (F1 design §3, §7)

Credit is a pure pipeline: the session ledger (`FocusLedger`, JSON lines per writer per month) → `SessionRecord` (one session's proof, breaks, overrides and end) → `HoursCredit` (counted seconds per session, with labelled stretches for Saved today) → `FocusBook` in the collection (per-day high-water marks, frozen 3 days on) → the counters, applied as dated marks so each leaf is dated when its credit was proven. Screens never compute any of it.

`MapleStores.focus` holds a launch's Focus stores (`FocusStores`): `sessions` (`FocusSessionStore`), `presets`, `appSets` and `notes`. F1b injects them; until then nothing reads them.

```swift
let store = stores.focus.sessions
await store.refresh()                                   // on launch, every foreground, and from a running session's timeline
let outcome = await store.start(.init(preset: preset, minutes: 50, appSet: appSet, from: .focusTab))
// .started(id), .alreadyRunning, .ledgerUnavailable, .blockingFailed(failure) ("Couldn't lock your apps"), .notRecorded
store.running                                           // the running session (SessionRecord), drawn from the ledger
store.displayCredit(at: now)                            // today, yesterday and total seconds: counted plus provisional
await store.end(.endedEarly)                            // or .emergencyRelease; .completed happens on refresh at the planned end
await store.startBreak(); await store.endBreak()        // one locked break, inside the planned length
await store.releaseAll()                                // Settings › Release all apps
await store.reflect(.partly, on: id)                    // the receipt's "How did it go?"
```

- **Starting.** The block is applied and read back before anything is written; a second Start while one is starting is refused. Without an app set, or on a build that can't block, a session is a plain timer that counts nothing.
- **Proof.** Each `refresh()` reads the block back and writes a checkpoint at most once a minute. If the block has gone, the session is marked lost and runs on as a plain timer; credit stops at the last checkpoint.
- **Unknown state.** While the ledger can't be read (`isLedgerReadable` false) the store neither writes nor clears.
- **Permissions.** The store grants `.screenTime` in `collection.context.permissions` while blocking is available and allowed, and sets `collection.context.blocking` to the build's capability. A free build's Screen Time leaves read "Not available in this build" (`LeafAvailability.notInThisBuild`), with no button.
- **Pure helpers for the screens:** `DialLayout` (marks, angles, turning), `FocusTimeText` (calm minutes), `SessionForecast` (the leaf dot's minute and the counts line), `StartReadiness` (Home's Start and Again), `RecentIntentions` (the intention chips), `FocusPreset` (presets and the strictness rule), `LeafProgress.rungFraction` (the dial's leaf fill) and `collection.currentRun(at:)` (the header streak).
- **Launch modes** (`LaunchMode`): live (files, `live` events credit), demo (memory, the preview blocker), and the DEBUG sandbox (`-MapleDemoSandbox YES`: its own container under `Sandbox/`, where preview sessions credit).
````

- [ ] **Step 2: Update the Home, Reminders and Shipped features sections**

In `docs/core-api.md`:
- in `## Home: \`NowState\``, replace the bullet that begins `- \`state.refreshesEverySecond\`` with `- \`state.refreshesEverySecond\` is true while a session runs (in every phase, night included): its time shows calm minutes ("18m"), with seconds only in the last minute.`, and replace the sentence `the day shows the countdown to wind-down until focus ships.` with `once focus ships the day shows saved today ("1h 20m" · "saved today · 41h in all"), the lifetime total before the day's first session, and the wind-down countdown without Screen Time (with "Turn on blocking"); a morning with no sleep data shows what was saved yesterday. \`focus\` is a \`FocusStatus\` built from \`FocusSessionStore.displayCredit(at:)\` and the last-used preset's \`FocusStart\`.`;
- in `## Reminders (local notifications)`, replace the first sentence with `Maple sends at most three kinds of notification: **"Time to wind down"** · "Bed at 23:00." at each night's wind-down start; **"Session done"** · "Study, 50 minutes" at a running session's planned end (scheduled with an absolute trigger, exempt from the night rule); and the opt-in **"Ready to study?"** once a day in the Day phase, skipped on a day a session started. There is no morning notification (rewards.md; focus spec §8).`, and change `\`ReminderPlan(.init(nights:settings:windDownOpenedAt:now:calendar:locale:))\`` to `\`ReminderPlan(.init(nights:settings:windDownOpenedAt:now:calendar:locale:schedule:runningSession:lastSessionStart:))\`` and `\`App/Features/Notifications/ReminderUpkeep.swift\` keeps it scheduled` to `\`App/Features/Notifications/ReminderUpkeep.swift\` keeps them scheduled through \`ReminderInputs\` (MapleServices)`;
- in `## Shipped features and permissions`, after the first paragraph, add: `\`collection.context.blocking\` (\`BlockingCapability\`) says what the build can block with: \`.unavailableInBuild\` on free builds (and paid ones until F1-paid), \`.preview\` in DEBUG demo and sandbox launches.`

- [ ] **Step 3: Add the DEBUG arguments**

In `docs/debug-launch-arguments.md`, add two rows to the table after `-MapleDemoDay`:
```markdown
| `-MapleDemoSandbox` | `YES` | Core (`MapleStores`, F1 design §7.6) | Opens a complete parallel container under `Sandbox/` in the app's container: its own collection, schedule, ledger, presets and app sets, with the preview blocker, where preview sessions earn credit. Whole sessions can be run and relaunched end to end. Nothing touches the live files. |
| `-MapleDemoSessionSeconds` | integer, e.g. `90` | Core (`FocusStores`) | With `-MapleDemoSandbox YES`: every session lasts that many seconds, in real time, whatever its preset. A session under 20 minutes never counts as finished. |
```

- [ ] **Step 4: Describe the new modules in architecture.md**

In `docs/architecture.md`, under `## 1. Architecture`, add before `**Key data flows**`:
```markdown
- **MapleFocusCore** (F1) is pure, `Sendable` and nonisolated, with no resources, so the Screen Time extensions can link it alone: focus events and plans, time sources (the wall clock, the continuous clock and a hashed boot id), the ledger's merge and placement, `SessionRecord`, and the shield reconciler. MapleCore re-exports it.
- **MapleStorage** (F1) is nonisolated: the App Group container, JSON-lines files and the ledger stores (`FileLedgerStore`, one file per writer per month; `MemoryLedgerStore`). MapleServices re-exports it.
```

- [ ] **Step 5: Run the whole suite one last time**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh > "$WS/test.log" 2>&1; tail -3 "$WS/test.log"; grep -c "warning:" "$WS/test.log"`
Expected: `** TEST SUCCEEDED **` and `0`.

- [ ] **Step 6: Commit**

```bash
git add docs/core-api.md docs/debug-launch-arguments.md docs/architecture.md
git commit -m "Docs: Focus in core-api, the sandbox arguments, and the new modules

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
