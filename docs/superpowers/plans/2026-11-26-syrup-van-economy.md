# Syrup Van Economy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the syrup van's economy as tested logic with no screens: sessions earn leaves, leaves are cooked into syrup or spent on machine upgrades, and the van's state is saved.

**Architecture:** The rules are pure values in `MapleCore/Workshop/`: `WorkshopTuning` (every number in one place), `LeafEarnings` (leaves from the session ledger) and `WorkshopBank` (what the member has done: cooked, spent, upgraded). The bank never stores a balance: leaves in the van are "earned so far, minus cooked, minus spent", and "earned so far" is the highest total the ledger has ever shown. `WorkshopStore` in `MapleServices/Workshop/` saves the bank as `workshop.json`, the same way `SubjectStore` saves subjects, and `FocusStores` carries it.

**Tech Stack:** Swift 6 (strict concurrency), Foundation, Observation, Swift Testing, the repo's `JSONStorage`. iOS 27, iPhone only.

**Spec:** `docs/superpowers/specs/2026-11-26-syrup-van-design.md` (§2 the loop, §13 answers 1 and 2, §14 what is left for later). This plan is step 2 of that document's §12.

## Where this plan sits

The design's §12 lists seven build steps. Each gets its own plan, written when the step before it has run in the simulator.

| Step | What | Plan | Waits on |
|---|---|---|---|
| 1 | The art list, and who draws it | Not written | The owner's answer to §13 question 5 |
| 2 | The economy, in logic only | **This plan** | The Study record branch (see Setup) |
| 3 | The scene shell: home, the entrance, the workshop, the clock that sets the timer (§6.2) | Not written | Step 2. Stand-in art is allowed (§13 answer 5) |
| 4 | The session: the tree, falling leaves, Pip's walk back, the summary | Not written | Step 3 |
| 5 | The shop and decorating (adds spending syrup) | Not written | Step 3, and the item list (§14) |
| 6 | Special syrups, the tasting shelf, Pip's clothes | Not written | Step 5, and the special list (§14) |
| 7 | Night | Not written | Step 3 |

Left out of this plan on purpose, because a later step owns it: spending syrup and owning decorations (step 5), special syrups (step 6), any screen, any DEBUG launch argument, the `ShippedFeatures` switch that shows the van (step 3), and the edit to `CLAUDE.md`'s "calm, restrained, dark" line (step 3, when the look changes).

## Setup

The economy reads `SessionRecord.focusedSeconds` and `FocusSessionStore.History`, which exist only on the Study record branch (`maanvik/f2-study-record`, not yet merged). The spec and this plan live on `maanvik/syrup-van-design`.

- If both have merged to `main`: branch `maanvik/syrup-van-economy` from `main`.
- If not: stack on them. From the repo's main checkout folder (never switch its branch):

```bash
git worktree add .worktrees/syrup-economy -b maanvik/syrup-van-economy maanvik/f2-study-record
```

```bash
git -C .worktrees/syrup-economy merge --no-edit maanvik/syrup-van-design
```

If `git worktree add` stops with `fatal: mmap failed: Operation canceled`, iCloud has evicted git files. Run `find .git -flags +dataless -type f -print0 | xargs -0 -n 20 brctl download`, then `git worktree prune`, remove the half-made folder, and add the worktree again.

All paths below are relative to the new worktree.

## Global Constraints

- iPhone only. Never mention or build for another Apple platform.
- Zero compiler warnings; Swift 6 strict concurrency.
- Swift Testing (`@Test`, `#expect`, `#require`). Each test is written and seen to fail before its code exists.
- `MapleCore` stays pure Foundation, `Sendable`, nonisolated. No SwiftUI, no file access.
- Demo and mock code compiles only under `#if DEBUG`. This plan adds none.
- Don't edit `MapleKit/Sources/MapleCore/Collection/NightLedger.swift`. Don't touch the `FoodAI` folder.
- Edits to shared files stay small. The only shared file this plan edits is `FocusStores.swift` (one property, two lines).
- Never commit a Team ID. Never push, merge or rewrite history without the owner's yes.
- Every commit message ends with a blank line and then `Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>`.
- The economy's numbers live only in `WorkshopTuning.starting`. Rule tests use their own tuning, so retuning never breaks them.
- Starting numbers from the spec, exact: one leaf per 300 seconds; one leaf cooks into one bottle (10 tenths) before any upgrade.
- Leaves and syrup are never bought with money (spec §2.6). Nothing in this plan touches purchases.
- Build: `SIMULATOR="iPhone 17" Scripts/build.sh`. Tests: `SIMULATOR="iPhone 17" Scripts/test.sh -collect-test-diagnostics never`.

## Review Focus

1. **A damaged `workshop.json`** (negative numbers, a number too big to multiply, a string where a number belongs, more leaves cooked than earned). Expected: the app doesn't crash, the member never sees a negative count, and the original file is copied aside before anything is saved. Pinned in Task 2 (`damaged`, `overspent`, `huge`) and Task 3 (`copiedAside`).
2. **A launch before the phone's first unlock**, when the file exists but can't be read. Expected: nothing is shown as earned, nothing is saved over the real file, and the first action after the unlock lands on the real values. Pinned in Task 3 (`unavailable`).
3. **The ledger shows fewer leaves than before** (History not read yet, a read that came back short). Expected: the van's leaves never go down. Pinned in Task 2 (`neverDown`) and Task 4 (`notLoaded`).
4. **A session that is still running, and a session removed from History.** Expected: the running session's leaves are not in the van until it ends; a removed session keeps everything it earned. Pinned in Task 1 (`running`, `removed`).
5. **The numbers are retuned after members have upgraded** (a ladder gets shorter than a saved level). Expected: the level reads as the new top, cooking uses today's numbers, syrup already made is untouched. Pinned in Task 2 (`retuned`).

**One consequence of the spec's rule to know about (the owner's call, not a defect):** a session that blocked apps earns from its *counted* time, and a plain timer from its *time focused* (§2, §13 answer 1). Counted time stops at 6 hours a day and shrinks when the member unlocks apps; time focused does neither. So on a heavy day a plain timer can earn more leaves than a blocking session of the same length. The rule is one function (`LeafEarnings.seconds(of:credit:)`), so changing it later is a one-line change with its tests.

---

## File Structure

| File | Responsibility |
|---|---|
| Create `MapleKit/Sources/MapleCore/Workshop/WorkshopTuning.swift` | The machines and every number: seconds per leaf, syrup per leaf, upgrade ladders |
| Create `MapleKit/Sources/MapleCore/Workshop/LeafEarnings.swift` | Leaves a session earned, and the total over the ledger |
| Create `MapleKit/Sources/MapleCore/Workshop/WorkshopBank.swift` | The van's saved state and its rules: earned, cook, upgrade |
| Create `MapleKit/Sources/MapleServices/Workshop/WorkshopStore.swift` | Saves the bank; refuses to write over a file it couldn't read |
| Create `MapleKit/Sources/MapleServices/Workshop/WorkshopStore+History.swift` | Fills the van from `FocusSessionStore.History` |
| Modify `MapleKit/Sources/MapleServices/Focus/FocusStores.swift` | Carries the `WorkshopStore` |
| Create `MapleKit/Tests/MapleCoreTests/WorkshopFixtures.swift` | A small tuning the rule tests share |
| Create `MapleKit/Tests/MapleCoreTests/WorkshopTuningTests.swift`, `LeafEarningsTests.swift`, `WorkshopBankTests.swift` | Rule tests |
| Create `MapleKit/Tests/MapleServicesTests/WorkshopStoreTests.swift` | Saving, unreadable files, the fill from History |
| Modify `docs/decisions.md`, `docs/core-api.md` | What was decided, and how screens read the van |

New folders under `MapleKit/Sources` and `MapleKit/Tests` are picked up by the package; `Package.swift` doesn't change.

---

### Task 1: The numbers, and leaves from sessions

**Files:**
- Create: `MapleKit/Sources/MapleCore/Workshop/WorkshopTuning.swift`
- Create: `MapleKit/Sources/MapleCore/Workshop/LeafEarnings.swift`
- Create: `MapleKit/Tests/MapleCoreTests/WorkshopFixtures.swift`
- Test: `MapleKit/Tests/MapleCoreTests/WorkshopTuningTests.swift`
- Test: `MapleKit/Tests/MapleCoreTests/LeafEarningsTests.swift`

**Interfaces:**
- Consumes (already in the repo): `SessionRecord` (`id`, `plan.kind`, `focusedSeconds`), `SessionKind.plainTimer`, `SessionCredit` (`id`, `seconds`), `HoursCredit.credit(_:crediting:now:)`, and the test helpers `FocusDay`, `FocusFixtures.plan(minutes:kind:selection:day:window:)`, `FocusFixtures.window(_:month:)`, `FocusFixtures.blockSix`, `FocusLedger(_:).sessions()`, `at(_:_:_:_:)`.
- Produces:
  - `enum WorkshopMachine: String, Sendable, CaseIterable, Codable { case evaporator, filterPress }`
  - `struct WorkshopTuning: Sendable, Equatable` with `secondsPerLeaf: Int`, `baseTenthsPerLeaf: Int`, `ladders: [WorkshopMachine: Ladder]`, `static let starting`, `func topLevel(of: WorkshopMachine) -> Int`, `func price(of: WorkshopMachine, after level: Int) -> Int?`, `func tenthsPerLeaf(levels: [WorkshopMachine: Int]) -> Int`
  - `struct WorkshopTuning.Ladder: Sendable, Equatable` with `init(prices: [Int], bonusTenths: [Int])`, `topLevel: Int`
  - `enum LeafEarnings` with `static func seconds(of: SessionRecord, credit: SessionCredit?) -> Int`, `static func leaves(forSeconds: Int, tuning: WorkshopTuning = .starting) -> Int`, `static func leaves(of: SessionRecord, credit: SessionCredit?, tuning: WorkshopTuning = .starting) -> Int`, `static func total(_: [SessionRecord], credits: [SessionCredit], running: UUID?, tuning: WorkshopTuning = .starting) -> Int`
  - Test fixture `WorkshopFixtures.small: WorkshopTuning` (evaporator: prices 5 then 8, bonus 2 then 5 tenths; filter press: price 3, bonus 1 tenth)

- [ ] **Step 1: Write the shared test tuning**

`MapleKit/Tests/MapleCoreTests/WorkshopFixtures.swift`:

```swift
import Foundation
@testable import MapleCore

enum WorkshopFixtures {
    /// A small tuning for the rule tests, so retuning the app's own numbers never changes them.
    /// Evaporator: level 1 for 5 leaves (+0.2 bottles a leaf), level 2 for 8 (+0.5). Filter press: level 1 for 3 (+0.1).
    static let small = WorkshopTuning(
        secondsPerLeaf: 300, baseTenthsPerLeaf: 10,
        ladders: [
            .evaporator: WorkshopTuning.Ladder(prices: [5, 8], bonusTenths: [2, 5]),
            .filterPress: WorkshopTuning.Ladder(prices: [3], bonusTenths: [1]),
        ]
    )
}
```

- [ ] **Step 2: Write the failing tuning tests**

`MapleKit/Tests/MapleCoreTests/WorkshopTuningTests.swift`:

```swift
import Foundation
import Testing
@testable import MapleCore

@Suite("The syrup van's numbers")
struct WorkshopTuningTests {
    private let small = WorkshopFixtures.small

    @Test("The starting pace is the design's: a leaf every 5 minutes, and one bottle a leaf before any upgrade")
    func startingPace() {
        #expect(WorkshopTuning.starting.secondsPerLeaf == 300)
        #expect(WorkshopTuning.starting.baseTenthsPerLeaf == 10)
    }

    @Test("Every machine has a ladder whose prices and syrup both rise with each level")
    func startingLadders() throws {
        for machine in WorkshopMachine.allCases {
            let ladder = try #require(WorkshopTuning.starting.ladders[machine])
            #expect(ladder.prices.count == ladder.bonusTenths.count)
            #expect(ladder.topLevel >= 1)
            #expect(ladder.prices.allSatisfy { $0 > 0 })
            #expect(zip(ladder.prices, ladder.prices.dropFirst()).allSatisfy { $0 < $1 })
            #expect(ladder.bonusTenths.first.map { $0 > 0 } == true)
            #expect(zip(ladder.bonusTenths, ladder.bonusTenths.dropFirst()).allSatisfy { $0 < $1 })
        }
    }

    @Test("A price is the leaves for the next level, and there is none at the top")
    func prices() {
        #expect(small.price(of: .evaporator, after: 0) == 5)
        #expect(small.price(of: .evaporator, after: 1) == 8)
        #expect(small.price(of: .evaporator, after: 2) == nil)
        #expect(small.price(of: .evaporator, after: 9) == nil)
        #expect(small.price(of: .evaporator, after: -1) == 5)
        #expect(small.topLevel(of: .filterPress) == 1)
    }

    @Test("Syrup per leaf is the base plus each machine's bonus at its level")
    func yield() {
        #expect(small.tenthsPerLeaf(levels: [:]) == 10)
        #expect(small.tenthsPerLeaf(levels: [.evaporator: 1]) == 12)
        #expect(small.tenthsPerLeaf(levels: [.evaporator: 2, .filterPress: 1]) == 16)
    }

    @Test("A level outside a ladder reads as its nearest end")
    func clamped() {
        #expect(small.tenthsPerLeaf(levels: [.evaporator: 7]) == 15)
        #expect(small.tenthsPerLeaf(levels: [.evaporator: -3]) == 10)
    }

    @Test("A machine with no ladder can't be upgraded and adds nothing")
    func noLadder() {
        let bare = WorkshopTuning(secondsPerLeaf: 300, baseTenthsPerLeaf: 10, ladders: [:])
        #expect(bare.topLevel(of: .evaporator) == 0)
        #expect(bare.price(of: .evaporator, after: 0) == nil)
        #expect(bare.tenthsPerLeaf(levels: [.evaporator: 2]) == 10)
    }
}
```

- [ ] **Step 3: Write the failing leaf tests**

`MapleKit/Tests/MapleCoreTests/LeafEarningsTests.swift`:

```swift
import Foundation
import Testing
@testable import MapleCore
@testable import MapleFocusCore

/// Sessions written the way the app writes them, on one clock, for the leaf rules. Add them in time order.
private final class EarningsFixture {
    private let clock = FocusDay(at(2026, 11, 1, 6))
    private var count = 0

    /// A session on `day` November 2026 at `hour`:00, `planned` minutes long, that ran its whole length or `ranSeconds`.
    /// A blocking session is confirmed half-way, so it counts.
    @discardableResult
    func add(
        day: Int, hour: Int = 10, planned: Int = 50, ranSeconds: Int? = nil, plain: Bool = false, hide: Bool = false,
        ended: Bool = true
    ) -> UUID {
        count += 1
        let id = UUID(uuidString: "00000000-0000-4000-8000-\(String(format: "%012d", count))")!
        let plan = FocusFixtures.plan(
            minutes: planned, kind: plain ? .plainTimer : .blocking, selection: plain ? nil : FocusFixtures.blockSix,
            day: String(format: "2026-11-%02d", day), window: FocusFixtures.window(day, month: 11)
        )
        let length = TimeInterval(ranSeconds ?? planned * 60)
        clock.at(at(2026, 11, day, hour))
        clock.write(.sessionStarted(plan), session: id)
        if plain {
            clock.time.advance(length)
        } else {
            clock.write(.shieldApplied, session: id)
            clock.time.advance(length / 2)
            clock.write(.shieldVerified, session: id)
            clock.time.advance(length / 2)
        }
        if ended {
            clock.write(.sessionEnded(ranSeconds == nil ? .completed : .endedEarly, verified: !plain), session: id)
        }
        if hide {
            clock.time.advance(60)
            clock.write(.sessionHidden, session: id)
        }
        return id
    }

    var records: [SessionRecord] { FocusLedger(clock.events).sessions() }
    var credits: [SessionCredit] { HoursCredit.credit(records, crediting: [.live], now: at(2026, 12, 1)) }

    func total(running: UUID? = nil, tuning: WorkshopTuning = WorkshopFixtures.small) -> Int {
        LeafEarnings.total(records, credits: credits, running: running, tuning: tuning)
    }
}

@Suite("Leaves from sessions")
struct LeafEarningsTests {
    @Test("A 50-minute session that blocked apps gives 10 leaves")
    func blocking() {
        let fixture = EarningsFixture()
        fixture.add(day: 10)
        #expect(fixture.total() == 10)
    }

    @Test("A plain timer earns from its time focused, though it counts nothing as saved")
    func plainTimer() throws {
        let fixture = EarningsFixture()
        let id = fixture.add(day: 10, plain: true)
        let record = try #require(fixture.records.first { $0.id == id })
        let credit = fixture.credits.first { $0.id == id }
        #expect((credit?.seconds ?? 0) == 0)
        #expect(LeafEarnings.seconds(of: record, credit: credit) == 3000)
        #expect(LeafEarnings.leaves(of: record, credit: credit, tuning: WorkshopFixtures.small) == 10)
        #expect(fixture.total() == 10)
    }

    @Test("A session that blocked apps earns from its counted time, never from the clock alone")
    func countedOnly() throws {
        let fixture = EarningsFixture()
        let id = fixture.add(day: 10)
        let record = try #require(fixture.records.first { $0.id == id })
        #expect(LeafEarnings.seconds(of: record, credit: nil) == 0)
        var credit = try #require(fixture.credits.first { $0.id == id })
        credit.seconds = 1500
        #expect(LeafEarnings.seconds(of: record, credit: credit) == 1500)
        credit.seconds = -40
        #expect(LeafEarnings.seconds(of: record, credit: credit) == 0)
    }

    @Test("Leaves are counted session by session: two 9-minute sessions give one each, not three between them")
    func perSession() {
        let fixture = EarningsFixture()
        fixture.add(day: 10, hour: 9, planned: 20, ranSeconds: 540, plain: true)
        fixture.add(day: 10, hour: 11, planned: 20, ranSeconds: 540, plain: true)
        #expect(fixture.total() == 2)
    }

    @Test("A session ended early keeps the leaves that had already fallen")
    func endedEarly() {
        let fixture = EarningsFixture()
        fixture.add(day: 10, ranSeconds: 780)
        #expect(fixture.total() == 2)
    }

    @Test("A session removed from History keeps the leaves it earned")
    func removed() {
        let fixture = EarningsFixture()
        fixture.add(day: 10, hide: true)
        fixture.add(day: 11, plain: true)
        #expect(fixture.total() == 20)
    }

    @Test("The running session's leaves aren't in the van until it ends")
    func running() {
        let fixture = EarningsFixture()
        fixture.add(day: 10)
        let now = fixture.add(day: 11, ranSeconds: 1500, plain: true, ended: false)
        #expect(fixture.total(running: now) == 10)
    }

    @Test("The pace comes from the tuning, and a pace of nothing earns nothing")
    func pace() {
        let fixture = EarningsFixture()
        fixture.add(day: 10)
        var slow = WorkshopFixtures.small
        slow.secondsPerLeaf = 600
        #expect(fixture.total(tuning: slow) == 5)
        slow.secondsPerLeaf = 0
        #expect(fixture.total(tuning: slow) == 0)
    }

    @Test("Seconds round down to whole leaves, and time below nothing earns nothing")
    func wholeLeaves() {
        #expect(LeafEarnings.leaves(forSeconds: 299, tuning: WorkshopFixtures.small) == 0)
        #expect(LeafEarnings.leaves(forSeconds: 300, tuning: WorkshopFixtures.small) == 1)
        #expect(LeafEarnings.leaves(forSeconds: 3299, tuning: WorkshopFixtures.small) == 10)
        #expect(LeafEarnings.leaves(forSeconds: -600, tuning: WorkshopFixtures.small) == 0)
    }
}
```

- [ ] **Step 4: Run the tests to see them fail**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -collect-test-diagnostics never -only-testing:MapleCoreTests 2>&1 | tail -30`
Expected: the build fails with `cannot find 'WorkshopTuning' in scope` (and the same for `WorkshopMachine` and `LeafEarnings`), ending `** TEST FAILED **`.

- [ ] **Step 5: Write the numbers**

`MapleKit/Sources/MapleCore/Workshop/WorkshopTuning.swift`:

```swift
import Foundation

/// A machine in the van that leaves can upgrade (syrup van design §2, §7). Saved by its raw name.
public enum WorkshopMachine: String, Sendable, CaseIterable, Codable {
    /// The pan the sap boils in.
    case evaporator
    /// Strains the finished syrup.
    case filterPress
}

/// Every number in the van's economy, in one place (syrup van design §2). The pace is tuned in its own pass (§14), by
/// editing `starting` and nothing else. The rules take a tuning, so their tests bring their own.
public struct WorkshopTuning: Sendable, Equatable {
    /// One machine's upgrade steps. Level 0 is the machine as it comes.
    public struct Ladder: Sendable, Equatable {
        /// Leaves for each step: `prices[0]` buys level 1.
        public var prices: [Int]
        /// Extra syrup a leaf gives at each level, in tenths of a bottle: `bonusTenths[0]` is level 1's whole bonus.
        public var bonusTenths: [Int]

        public init(prices: [Int], bonusTenths: [Int]) {
            self.prices = prices
            self.bonusTenths = bonusTenths
        }

        public var topLevel: Int { min(prices.count, bonusTenths.count) }
    }

    /// Seconds of a session for one leaf.
    public var secondsPerLeaf: Int
    /// Syrup one leaf cooks into before any upgrade, in tenths of a bottle.
    public var baseTenthsPerLeaf: Int
    public var ladders: [WorkshopMachine: Ladder]

    public init(secondsPerLeaf: Int, baseTenthsPerLeaf: Int, ladders: [WorkshopMachine: Ladder]) {
        self.secondsPerLeaf = secondsPerLeaf
        self.baseTenthsPerLeaf = baseTenthsPerLeaf
        self.ladders = ladders
    }

    /// The app's numbers. A leaf every 5 minutes and one bottle a leaf are the design's (§2); the ladders are starting
    /// values for the tuning pass.
    public static let starting = WorkshopTuning(
        secondsPerLeaf: 300, baseTenthsPerLeaf: 10,
        ladders: [
            .evaporator: Ladder(prices: [10, 25, 50, 100, 200], bonusTenths: [2, 5, 10, 15, 20]),
            .filterPress: Ladder(prices: [20, 60, 150], bonusTenths: [1, 3, 5]),
        ]
    )

    public func topLevel(of machine: WorkshopMachine) -> Int {
        ladders[machine]?.topLevel ?? 0
    }

    /// Leaves for the level after `level`; nil at the top.
    public func price(of machine: WorkshopMachine, after level: Int) -> Int? {
        guard let ladder = ladders[machine] else { return nil }
        let level = max(0, level)
        return level < ladder.topLevel ? ladder.prices[level] : nil
    }

    /// Tenths of a bottle one leaf cooks into with the machines at `levels`. A level outside a ladder reads as its
    /// nearest end.
    public func tenthsPerLeaf(levels: [WorkshopMachine: Int]) -> Int {
        ladders.reduce(baseTenthsPerLeaf) { sum, entry in
            let level = min(max(0, levels[entry.key] ?? 0), entry.value.topLevel)
            return level > 0 ? sum + entry.value.bonusTenths[level - 1] : sum
        }
    }
}
```

- [ ] **Step 6: Write the leaf rules**

`MapleKit/Sources/MapleCore/Workshop/LeafEarnings.swift`:

```swift
import Foundation
import MapleFocusCore

/// Plain leaves from sessions (syrup van design §2, §13 answers 1 and 2). Pure.
///
/// Special leaves are not this: the 155 species still come from the reward table's milestones.
public enum LeafEarnings {
    /// The seconds of a session that earn leaves: its counted time when it blocked apps, its time focused when it was a
    /// plain timer (which counts nothing as saved).
    public static func seconds(of record: SessionRecord, credit: SessionCredit?) -> Int {
        record.plan.kind == .plainTimer ? record.focusedSeconds : max(0, credit?.seconds ?? 0)
    }

    /// Whole leaves in `seconds`.
    public static func leaves(forSeconds seconds: Int, tuning: WorkshopTuning = .starting) -> Int {
        guard tuning.secondsPerLeaf > 0 else { return 0 }
        return max(0, seconds) / tuning.secondsPerLeaf
    }

    /// The leaves one session earned. A session ended early keeps the ones that had fallen.
    public static func leaves(of record: SessionRecord, credit: SessionCredit?, tuning: WorkshopTuning = .starting) -> Int {
        leaves(forSeconds: seconds(of: record, credit: credit), tuning: tuning)
    }

    /// Every leaf the ledger's sessions have earned, counted session by session.
    /// - Parameters:
    ///   - records: The whole ledger's sessions, the ones removed from History included: removing a session keeps what
    ///     it earned.
    ///   - credits: `HoursCredit.credit` over the same records.
    ///   - running: The session running now. Its leaves aren't in the van until it ends.
    public static func total(
        _ records: [SessionRecord], credits: [SessionCredit], running: UUID?, tuning: WorkshopTuning = .starting
    ) -> Int {
        var byID: [UUID: SessionCredit] = [:]
        for credit in credits where byID[credit.id] == nil { byID[credit.id] = credit }
        return records.reduce(0) { sum, record in
            record.id == running ? sum : sum + leaves(of: record, credit: byID[record.id], tuning: tuning)
        }
    }
}
```

- [ ] **Step 7: Run the tests to see them pass**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -collect-test-diagnostics never -only-testing:MapleCoreTests 2>&1 | tail -30`
Expected: `** TEST SUCCEEDED **`, with the suites "The syrup van's numbers" (6 tests) and "Leaves from sessions" (9 tests) passing and no other suite failing.

- [ ] **Step 8: Commit**

```bash
git add MapleKit/Sources/MapleCore/Workshop MapleKit/Tests/MapleCoreTests/WorkshopFixtures.swift MapleKit/Tests/MapleCoreTests/WorkshopTuningTests.swift MapleKit/Tests/MapleCoreTests/LeafEarningsTests.swift
git commit -m "Syrup van: the economy's numbers, and leaves from sessions

Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>"
```

---

### Task 2: The bank

**Files:**
- Create: `MapleKit/Sources/MapleCore/Workshop/WorkshopBank.swift`
- Test: `MapleKit/Tests/MapleCoreTests/WorkshopBankTests.swift`

**Interfaces:**
- Consumes: `WorkshopMachine`, `WorkshopTuning` (`topLevel(of:)`, `price(of:after:)`, `tenthsPerLeaf(levels:)`), `WorkshopFixtures.small` from Task 1.
- Produces: `struct WorkshopBank: Sendable, Codable, Equatable` with
  - `init()`
  - `private(set) var earned`, `cooked`, `spentOnUpgrades`, `syrupMadeTenths: Int`, `levels: [String: Int]`, `decodedWithLosses: Bool`
  - `static let limit = 1_000_000_000`
  - `var leaves: Int` (in the van now), `var syrupTenths: Int` (syrup in the van now)
  - `func level(of: WorkshopMachine, tuning: WorkshopTuning = .starting) -> Int`
  - `func price(of: WorkshopMachine, tuning: WorkshopTuning = .starting) -> Int?`
  - `func tenthsPerLeaf(tuning: WorkshopTuning = .starting) -> Int`
  - `@discardableResult mutating func noteEarned(_ total: Int) -> Int` (leaves newly in the van)
  - `@discardableResult mutating func cook(_ count: Int, tuning: WorkshopTuning = .starting) -> Int` (leaves cooked)
  - `enum UpgradeOutcome: Sendable, Equatable { case upgraded(level: Int), short(by: Int), atTop }`
  - `@discardableResult mutating func upgrade(_: WorkshopMachine, tuning: WorkshopTuning = .starting) -> UpgradeOutcome`
  - Equality ignores `decodedWithLosses`. Saved keys: `earned`, `cooked`, `spentOnUpgrades`, `syrupMadeTenths`, `levels`.

- [ ] **Step 1: Write the failing tests**

`MapleKit/Tests/MapleCoreTests/WorkshopBankTests.swift`:

```swift
import Foundation
import Testing
@testable import MapleCore

private let small = WorkshopFixtures.small

private func decode(_ json: String) throws -> WorkshopBank {
    try JSONDecoder().decode(WorkshopBank.self, from: Data(json.utf8))
}

private func reopened(_ bank: WorkshopBank) throws -> WorkshopBank {
    try JSONDecoder().decode(WorkshopBank.self, from: JSONEncoder().encode(bank))
}

@Suite("The syrup van's bank")
struct WorkshopBankTests {
    @Test("A new van is empty, with every machine as it comes")
    func empty() {
        let bank = WorkshopBank()
        #expect(bank.leaves == 0 && bank.syrupTenths == 0)
        #expect(bank.level(of: .evaporator, tuning: small) == 0)
        #expect(bank.tenthsPerLeaf(tuning: small) == 10)
        #expect(bank.price(of: .evaporator, tuning: small) == 5)
    }

    @Test("Leaves arrive as the ledger's total grows, and only the new ones are reported")
    func earning() {
        var bank = WorkshopBank()
        #expect(bank.noteEarned(10) == 10)
        #expect(bank.leaves == 10)
        #expect(bank.noteEarned(12) == 2)
        #expect(bank.leaves == 12)
    }

    @Test("The van's leaves never go down when the ledger shows fewer")
    func neverDown() {
        var bank = WorkshopBank()
        bank.noteEarned(10)
        #expect(bank.noteEarned(7) == 0)
        #expect(bank.noteEarned(-3) == 0)
        #expect(bank.leaves == 10)
    }

    @Test("Cooking turns leaves into syrup, a bottle a leaf before any upgrade")
    func cooking() {
        var bank = WorkshopBank()
        bank.noteEarned(10)
        #expect(bank.cook(3, tuning: small) == 3)
        #expect(bank.leaves == 7)
        #expect(bank.syrupTenths == 30)
    }

    @Test("Cooking never takes more leaves than the van holds, and nothing or less cooks nothing")
    func cookingBounds() {
        var bank = WorkshopBank()
        bank.noteEarned(4)
        #expect(bank.cook(0, tuning: small) == 0)
        #expect(bank.cook(-2, tuning: small) == 0)
        #expect(bank.leaves == 4 && bank.syrupTenths == 0)
        #expect(bank.cook(100, tuning: small) == 4)
        #expect(bank.leaves == 0 && bank.syrupTenths == 40)
        #expect(bank.cook(1, tuning: small) == 0)
    }

    @Test("An upgrade costs leaves and makes each later leaf give more syrup; syrup already made stays as it was")
    func upgrading() {
        var bank = WorkshopBank()
        bank.noteEarned(10)
        bank.cook(1, tuning: small)
        #expect(bank.upgrade(.evaporator, tuning: small) == .upgraded(level: 1))
        #expect(bank.leaves == 4)
        #expect(bank.level(of: .evaporator, tuning: small) == 1)
        #expect(bank.syrupTenths == 10)
        #expect(bank.tenthsPerLeaf(tuning: small) == 12)
        bank.cook(1, tuning: small)
        #expect(bank.syrupTenths == 22)
        #expect(bank.price(of: .evaporator, tuning: small) == 8)
    }

    @Test("An upgrade the van can't afford changes nothing and says how many leaves it is short")
    func short() {
        var bank = WorkshopBank()
        bank.noteEarned(4)
        let before = bank
        #expect(bank.upgrade(.evaporator, tuning: small) == .short(by: 1))
        #expect(bank == before)
    }

    @Test("A machine at the top of its ladder can't be upgraded, and costs nothing to ask")
    func atTop() {
        var bank = WorkshopBank()
        bank.noteEarned(50)
        #expect(bank.upgrade(.filterPress, tuning: small) == .upgraded(level: 1))
        let before = bank
        #expect(bank.upgrade(.filterPress, tuning: small) == .atTop)
        #expect(bank == before)
        #expect(bank.price(of: .filterPress, tuning: small) == nil)
    }

    @Test("Machines add up: both upgraded give the base plus both bonuses")
    func bothMachines() {
        var bank = WorkshopBank()
        bank.noteEarned(50)
        bank.upgrade(.evaporator, tuning: small)
        bank.upgrade(.evaporator, tuning: small)
        bank.upgrade(.filterPress, tuning: small)
        #expect(bank.leaves == 50 - 5 - 8 - 3)
        #expect(bank.tenthsPerLeaf(tuning: small) == 16)
    }

    @Test("The van is saved and read back as it was")
    func roundTrip() throws {
        var bank = WorkshopBank()
        bank.noteEarned(40)
        bank.cook(6, tuning: small)
        bank.upgrade(.evaporator, tuning: small)
        let again = try reopened(bank)
        #expect(again == bank)
        #expect(!again.decodedWithLosses)
        #expect(again.leaves == 29 && again.syrupTenths == 60)
    }

    @Test("An empty or older file reads as a new van, with nothing lost")
    func missingKeys() throws {
        let bank = try decode("{}")
        #expect(bank == WorkshopBank())
        #expect(!bank.decodedWithLosses)
    }

    @Test("A machine this build doesn't know is kept as it was saved")
    func unknownMachine() throws {
        var bank = try decode(#"{"earned":20,"levels":{"evaporator":1,"centrifuge":3}}"#)
        #expect(!bank.decodedWithLosses)
        bank.cook(1, tuning: small)
        let saved = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(bank)) as? [String: Any])
        #expect((saved["levels"] as? [String: Int])?["centrifuge"] == 3)
    }

    @Test("Damaged numbers read as the nearest sane value, and the van says it lost something")
    func damaged() throws {
        let bank = try decode(#"{"earned":"lots","cooked":-4,"spentOnUpgrades":2,"syrupMadeTenths":-9,"levels":{"evaporator":-2}}"#)
        #expect(bank.decodedWithLosses)
        #expect(bank.leaves == 0)
        #expect(bank.syrupTenths == 0)
        #expect(bank.level(of: .evaporator, tuning: small) == 0)
        let unreadableLevels = try decode(#"{"earned":5,"levels":[1,2]}"#)
        #expect(unreadableLevels.decodedWithLosses)
        #expect(unreadableLevels.leaves == 5)
    }

    @Test("A file that cooked or spent more than it earned never shows fewer than no leaves")
    func overspent() throws {
        var bank = try decode(#"{"earned":3,"cooked":8,"spentOnUpgrades":5}"#)
        #expect(bank.decodedWithLosses)
        #expect(bank.leaves == 0)
        #expect(bank.noteEarned(10) == 0)
        #expect(bank.noteEarned(15) == 2)
        #expect(bank.leaves == 2)
    }

    @Test("Numbers too big to be real are capped, so cooking them can't overflow")
    func huge() throws {
        var bank = try decode(#"{"earned":9223372036854775807}"#)
        #expect(bank.decodedWithLosses)
        #expect(bank.leaves == WorkshopBank.limit)
        #expect(bank.cook(Int.max, tuning: small) == WorkshopBank.limit)
        #expect(bank.syrupTenths == WorkshopBank.limit * 10)
        var fresh = WorkshopBank()
        #expect(fresh.noteEarned(Int.max) == WorkshopBank.limit)
    }

    @Test("After a retune that shortens a ladder, a saved level reads as the new top")
    func retuned() throws {
        var bank = try decode(#"{"earned":30,"syrupMadeTenths":70,"levels":{"evaporator":2}}"#)
        var shorter = small
        shorter.ladders[.evaporator] = WorkshopTuning.Ladder(prices: [5], bonusTenths: [2])
        #expect(bank.level(of: .evaporator, tuning: shorter) == 1)
        #expect(bank.tenthsPerLeaf(tuning: shorter) == 12)
        #expect(bank.upgrade(.evaporator, tuning: shorter) == .atTop)
        bank.cook(1, tuning: shorter)
        #expect(bank.syrupTenths == 82)
        #expect(!bank.decodedWithLosses)
    }

    @Test("Two vans with the same contents are equal, whether or not one was read with losses")
    func equality() throws {
        #expect(try decode(#"{"earned":0,"cooked":-1}"#) == WorkshopBank())
    }
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -collect-test-diagnostics never -only-testing:MapleCoreTests 2>&1 | tail -30`
Expected: the build fails with `cannot find type 'WorkshopBank' in scope`, ending `** TEST FAILED **`.

- [ ] **Step 3: Write the bank**

`MapleKit/Sources/MapleCore/Workshop/WorkshopBank.swift`:

```swift
import Foundation

/// The van's saved state (`workshop.json`, syrup van design §2): what the member has earned, cooked and spent, and each
/// machine's level. Pure.
///
/// No balance is stored. Leaves in the van are `earned - cooked - spentOnUpgrades`, and `earned` is the highest total
/// the session ledger has ever shown (`LeafEarnings.total`), so a leaf can't be counted twice or lost to a missed
/// delivery, and a short read of the ledger can't take leaves away.
public struct WorkshopBank: Sendable, Codable {
    /// No count is ever above this, so a damaged file can't overflow the sums.
    public static let limit = 1_000_000_000

    /// Leaves ever earned. It only goes up.
    public private(set) var earned = 0
    /// Leaves cooked into syrup.
    public private(set) var cooked = 0
    /// Leaves spent on upgrades.
    public private(set) var spentOnUpgrades = 0
    /// Syrup ever made, in tenths of a bottle.
    public private(set) var syrupMadeTenths = 0
    /// Each machine's level, by its raw name. A machine this build doesn't know is kept as it is.
    public private(set) var levels: [String: Int] = [:]
    /// Decoding met a number it had to repair. Not saved, and not part of equality.
    public private(set) var decodedWithLosses = false

    public init() {}

    /// Leaves in the van now, waiting to be cooked or spent.
    public var leaves: Int { max(0, earned - cooked - spentOnUpgrades) }
    /// Syrup in the van now, in tenths of a bottle.
    public var syrupTenths: Int { syrupMadeTenths }

    /// A machine's level, never above the top of its ladder in `tuning`.
    public func level(of machine: WorkshopMachine, tuning: WorkshopTuning = .starting) -> Int {
        min(max(0, levels[machine.rawValue] ?? 0), tuning.topLevel(of: machine))
    }

    /// Leaves for the machine's next level; nil at the top.
    public func price(of machine: WorkshopMachine, tuning: WorkshopTuning = .starting) -> Int? {
        tuning.price(of: machine, after: level(of: machine, tuning: tuning))
    }

    /// Tenths of a bottle a leaf cooks into now.
    public func tenthsPerLeaf(tuning: WorkshopTuning = .starting) -> Int {
        var current: [WorkshopMachine: Int] = [:]
        for machine in WorkshopMachine.allCases { current[machine] = level(of: machine, tuning: tuning) }
        return tuning.tenthsPerLeaf(levels: current)
    }

    /// Tells the van the ledger's total (`LeafEarnings.total`). A total below what the van already knows changes
    /// nothing.
    /// - Returns: The leaves newly in the van.
    @discardableResult
    public mutating func noteEarned(_ total: Int) -> Int {
        let total = min(total, Self.limit)
        guard total > earned else { return 0 }
        let new = total - earned
        earned = total
        return new
    }

    /// Cooks up to `count` leaves into syrup at today's yield.
    /// - Returns: The leaves cooked: fewer than `count` when the van holds fewer.
    @discardableResult
    public mutating func cook(_ count: Int, tuning: WorkshopTuning = .starting) -> Int {
        let cooking = min(max(0, count), leaves)
        guard cooking > 0 else { return 0 }
        cooked += cooking
        syrupMadeTenths += cooking * tenthsPerLeaf(tuning: tuning)
        return cooking
    }

    public enum UpgradeOutcome: Sendable, Equatable {
        case upgraded(level: Int)
        /// The van holds this many leaves too few. Nothing changed.
        case short(by: Int)
        case atTop
    }

    /// Spends leaves on the machine's next level.
    @discardableResult
    public mutating func upgrade(_ machine: WorkshopMachine, tuning: WorkshopTuning = .starting) -> UpgradeOutcome {
        let current = self.level(of: machine, tuning: tuning)
        guard let price = tuning.price(of: machine, after: current) else { return .atTop }
        guard leaves >= price else { return .short(by: price - leaves) }
        spentOnUpgrades += price
        levels[machine.rawValue] = current + 1
        return .upgraded(level: current + 1)
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case earned, cooked, spentOnUpgrades, syrupMadeTenths, levels
    }

    /// Reads what it can. A missing number is 0; a number that is unreadable, negative or above `limit` is repaired and
    /// `decodedWithLosses` is set, so the store copies the file aside before saving over it.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var losses = false
        func amount(_ key: CodingKeys) -> Int {
            guard c.contains(key) else { return 0 }
            guard let value = try? c.decode(Int.self, forKey: key) else {
                losses = true
                return 0
            }
            if value < 0 || value > Self.limit { losses = true }
            return min(max(0, value), Self.limit)
        }
        cooked = amount(.cooked)
        spentOnUpgrades = amount(.spentOnUpgrades)
        syrupMadeTenths = amount(.syrupMadeTenths)
        let saved = amount(.earned)
        earned = max(saved, cooked + spentOnUpgrades)
        if earned != saved { losses = true }
        if c.contains(.levels) {
            if let saved = try? c.decode([String: Int].self, forKey: .levels) {
                if saved.values.contains(where: { $0 < 0 }) { losses = true }
                levels = saved.mapValues { max(0, $0) }
            } else {
                losses = true
            }
        }
        decodedWithLosses = losses
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(earned, forKey: .earned)
        try c.encode(cooked, forKey: .cooked)
        try c.encode(spentOnUpgrades, forKey: .spentOnUpgrades)
        try c.encode(syrupMadeTenths, forKey: .syrupMadeTenths)
        try c.encode(levels, forKey: .levels)
    }
}

extension WorkshopBank: Equatable {
    public static func == (a: WorkshopBank, b: WorkshopBank) -> Bool {
        a.earned == b.earned && a.cooked == b.cooked && a.spentOnUpgrades == b.spentOnUpgrades
            && a.syrupMadeTenths == b.syrupMadeTenths && a.levels == b.levels
    }
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -collect-test-diagnostics never -only-testing:MapleCoreTests 2>&1 | tail -30`
Expected: `** TEST SUCCEEDED **`, with "The syrup van's bank" (17 tests) passing and no other suite failing.

If `damaged` fails on `bank.leaves == 0`: the file there has earned unreadable (0), cooked repaired to 0 and 2 spent, so `earned` is raised to 2 and `leaves` is 0. If `overspent` fails on `noteEarned(15) == 2`: the file's earned is raised to 13 (8 cooked + 5 spent), so 15 brings 2.

- [ ] **Step 5: Commit**

```bash
git add MapleKit/Sources/MapleCore/Workshop/WorkshopBank.swift MapleKit/Tests/MapleCoreTests/WorkshopBankTests.swift
git commit -m "Syrup van: the bank (earn, cook, upgrade) and its saved form

Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>"
```

---

### Task 3: The store

**Files:**
- Create: `MapleKit/Sources/MapleServices/Workshop/WorkshopStore.swift`
- Test: `MapleKit/Tests/MapleServicesTests/WorkshopStoreTests.swift`

**Interfaces:**
- Consumes: `WorkshopBank`, `WorkshopMachine`, `WorkshopTuning` from Tasks 1 and 2; the repo's `JSONStorage<Value>` (`read() -> StorageRead<Value>`, `save(_:)`, `copyAside()`), `StorageRead` (`.value`, `.absent`, `.unavailable`), and the test helpers `temporaryDirectory()` and `files(in:)`.
- Produces: `@Observable public final class WorkshopStore` (MainActor, like every store in `MapleServices`) with
  - `nonisolated static let file = "workshop.json"`
  - `init(storage: JSONStorage<WorkshopBank>, tuning: WorkshopTuning = .starting)`
  - `private(set) var bank: WorkshopBank`, `private(set) var isAvailable: Bool`, `let tuning: WorkshopTuning`
  - `@discardableResult func reloadIfUnavailable() -> Bool`
  - `var leaves: Int`, `var syrupTenths: Int`, `var tenthsPerLeaf: Int`
  - `func level(of: WorkshopMachine) -> Int`, `func price(of: WorkshopMachine) -> Int?`
  - `@discardableResult func noteEarned(_ total: Int) -> Int` (0 while the file can't be read)
  - `@discardableResult func cook(_ count: Int = 1) -> Int` (0 while the file can't be read)
  - `@discardableResult func upgrade(_: WorkshopMachine) -> WorkshopBank.UpgradeOutcome?` (nil while the file can't be read)

- [ ] **Step 1: Write the failing tests**

`MapleKit/Tests/MapleServicesTests/WorkshopStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import MapleCore
@testable import MapleServices

/// Evaporator: level 1 for 5 leaves (+0.2 bottles a leaf). Filter press: level 1 for 3 (+0.1).
private let small = WorkshopTuning(
    secondsPerLeaf: 300, baseTenthsPerLeaf: 10,
    ladders: [
        .evaporator: WorkshopTuning.Ladder(prices: [5], bonusTenths: [2]),
        .filterPress: WorkshopTuning.Ladder(prices: [3], bonusTenths: [1]),
    ]
)

@Suite("The syrup van's store")
@MainActor
struct WorkshopStoreTests {
    private func url() throws -> URL {
        try temporaryDirectory().appendingPathComponent(WorkshopStore.file)
    }

    private func open(_ file: URL) -> WorkshopStore {
        WorkshopStore(storage: JSONStorage(.file(file)), tuning: small)
    }

    private func lock(_ file: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
    }

    private func unlock(_ file: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
    }

    @Test("A first launch has an empty van and writes nothing until something changes")
    func firstLaunch() throws {
        let file = try url()
        let store = open(file)
        #expect(store.isAvailable)
        #expect(store.leaves == 0 && store.syrupTenths == 0 && store.tenthsPerLeaf == 10)
        #expect(store.noteEarned(0) == 0)
        #expect(store.cook() == 0)
        #expect(files(in: file.deletingLastPathComponent()).isEmpty)
    }

    @Test("Leaves, syrup and upgrades are saved as they change")
    func saved() throws {
        let file = try url()
        let store = open(file)
        #expect(store.noteEarned(20) == 20)
        #expect(store.cook(3) == 3)
        #expect(store.upgrade(.evaporator) == .upgraded(level: 1))
        #expect(store.cook() == 1)

        let reopened = open(file)
        #expect(reopened.bank == store.bank)
        #expect(reopened.leaves == 11)
        #expect(reopened.syrupTenths == 42)
        #expect(reopened.level(of: .evaporator) == 1)
        #expect(reopened.price(of: .evaporator) == nil)
        #expect(reopened.price(of: .filterPress) == 3)
        #expect(reopened.tenthsPerLeaf == 12)
    }

    @Test("An upgrade the van can't afford is reported and nothing is saved")
    func cannotAfford() throws {
        let file = try url()
        let store = open(file)
        store.noteEarned(2)
        let before = try Data(contentsOf: file)
        #expect(store.upgrade(.evaporator) == .short(by: 3))
        #expect(try Data(contentsOf: file) == before)
    }

    @Test("A van that can't be read yet is never overwritten: nothing changes until it can")
    func unavailable() throws {
        let file = try url()
        let saved = open(file)
        saved.noteEarned(20)
        saved.cook(4)
        let before = try Data(contentsOf: file)

        try lock(file)
        defer { try? unlock(file) }
        let store = open(file)
        #expect(!store.isAvailable)
        #expect(store.leaves == 0)
        #expect(store.noteEarned(30) == 0)
        #expect(store.cook() == 0)
        #expect(store.upgrade(.evaporator) == nil)

        try unlock(file)
        #expect(try Data(contentsOf: file) == before)
        #expect(store.noteEarned(30) == 10)
        #expect(store.isAvailable)
        #expect(store.leaves == 26)
        #expect(open(file).leaves == 26)
    }

    @Test("A file read with losses is copied aside before the van saves over it")
    func copiedAside() throws {
        let file = try url()
        try Data(#"{"earned":12,"cooked":-5,"levels":{"evaporator":1}}"#.utf8).write(to: file)
        let store = open(file)
        #expect(store.isAvailable)
        #expect(store.leaves == 12)
        #expect(store.level(of: .evaporator) == 1)
        let folder = files(in: file.deletingLastPathComponent())
        #expect(folder.contains { $0.hasPrefix("workshop.damaged-") })
        store.cook(2)
        #expect(open(file).leaves == 10)
    }
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -collect-test-diagnostics never -only-testing:MapleServicesTests 2>&1 | tail -30`
Expected: the build fails with `cannot find 'WorkshopStore' in scope`, ending `** TEST FAILED **`.

- [ ] **Step 3: Write the store**

`MapleKit/Sources/MapleServices/Workshop/WorkshopStore.swift`:

```swift
import Foundation
import MapleCore
import Observation

/// The syrup van's leaves, syrup and machines (`workshop.json`, syrup van design §2). The rules are `WorkshopBank`'s;
/// this saves it.
///
/// While the file exists but can't be read yet, the van shows empty and nothing is saved, so a later save never writes
/// over the member's real van. Every change reads again first.
@Observable
public final class WorkshopStore {
    nonisolated public static let file = "workshop.json"

    public private(set) var bank: WorkshopBank
    public private(set) var isAvailable: Bool
    /// The economy's numbers for this launch.
    public let tuning: WorkshopTuning

    @ObservationIgnored private let storage: JSONStorage<WorkshopBank>

    public init(storage: JSONStorage<WorkshopBank>, tuning: WorkshopTuning = .starting) {
        self.storage = storage
        self.tuning = tuning
        let loaded = Self.contents(of: storage.read(), in: storage)
        bank = loaded ?? WorkshopBank()
        isAvailable = loaded != nil
    }

    /// Reads the van again if it couldn't be read at launch.
    /// - Returns: Whether the store now holds the member's real van (or knows there is none yet).
    @discardableResult
    public func reloadIfUnavailable() -> Bool {
        guard !isAvailable else { return false }
        guard let loaded = Self.contents(of: storage.read(), in: storage) else { return false }
        bank = loaded
        isAvailable = true
        return true
    }

    /// Leaves in the van now.
    public var leaves: Int { bank.leaves }
    /// Syrup in the van now, in tenths of a bottle.
    public var syrupTenths: Int { bank.syrupTenths }
    /// Tenths of a bottle a leaf cooks into now.
    public var tenthsPerLeaf: Int { bank.tenthsPerLeaf(tuning: tuning) }

    public func level(of machine: WorkshopMachine) -> Int { bank.level(of: machine, tuning: tuning) }
    /// Leaves for the machine's next level; nil at the top.
    public func price(of machine: WorkshopMachine) -> Int? { bank.price(of: machine, tuning: tuning) }

    /// Tells the van the ledger's total (`LeafEarnings.total`).
    /// - Returns: The leaves newly in the van; 0 while the saved van still can't be read.
    @discardableResult
    public func noteEarned(_ total: Int) -> Int {
        guard isAvailable || reloadIfUnavailable() else { return 0 }
        return change { $0.noteEarned(total) }
    }

    /// Cooks up to `count` leaves: one tap of the pot.
    /// - Returns: The leaves cooked; 0 while the saved van still can't be read.
    @discardableResult
    public func cook(_ count: Int = 1) -> Int {
        guard isAvailable || reloadIfUnavailable() else { return 0 }
        return change { $0.cook(count, tuning: tuning) }
    }

    /// - Returns: Nil while the saved van still can't be read (nothing changes then).
    @discardableResult
    public func upgrade(_ machine: WorkshopMachine) -> WorkshopBank.UpgradeOutcome? {
        guard isAvailable || reloadIfUnavailable() else { return nil }
        return change { $0.upgrade(machine, tuning: tuning) }
    }

    // MARK: Private

    /// What a read means for the store: the saved van (a file that read with losses is copied aside first, so a later
    /// save never destroys the original), or a new one; nil while the file can't be read.
    private static func contents(of read: StorageRead<WorkshopBank>, in storage: JSONStorage<WorkshopBank>) -> WorkshopBank? {
        switch read {
        case .value(let saved):
            if saved.decodedWithLosses { storage.copyAside() }
            return saved
        case .absent:
            return WorkshopBank()
        case .unavailable:
            return nil
        }
    }

    @discardableResult
    private func change<Result>(_ edit: (inout WorkshopBank) -> Result) -> Result {
        var copy = bank
        let result = edit(&copy)
        if copy != bank {
            bank = copy
            storage.save(copy)
        }
        return result
    }
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -collect-test-diagnostics never -only-testing:MapleServicesTests 2>&1 | tail -30`
Expected: `** TEST SUCCEEDED **`, with "The syrup van's store" (5 tests) passing and no other suite failing.

- [ ] **Step 5: Commit**

```bash
git add MapleKit/Sources/MapleServices/Workshop/WorkshopStore.swift MapleKit/Tests/MapleServicesTests/WorkshopStoreTests.swift
git commit -m "Syrup van: WorkshopStore saves the bank and never writes over a file it couldn't read

Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>"
```

---

### Task 4: Filling the van from History, the wiring and the docs

**Files:**
- Create: `MapleKit/Sources/MapleServices/Workshop/WorkshopStore+History.swift`
- Modify: `MapleKit/Sources/MapleServices/Focus/FocusStores.swift` (the property list near line 50, the `files` factory near line 83, the `demo` factory near line 122)
- Modify: `MapleKit/Tests/MapleServicesTests/WorkshopStoreTests.swift`
- Modify: `docs/decisions.md` (a new entry above the `2026-11-15` one), `docs/core-api.md` (a new section before `## Files, unlocks and time zones`)

**Interfaces:**
- Consumes: `WorkshopStore.noteEarned(_:)` and `tuning` (Task 3); `LeafEarnings.total(_:credits:running:tuning:)` (Task 1); the repo's `FocusSessionStore.History` (`records: [SessionRecord]`, `credits: [SessionCredit]`, `sessions: [StudySession]`), `FocusSessionStore.loadHistory()`, `history`, `running`, `refresh()`; `MapleStores.make(_:directory:calendar:now:)`, `DemoLaunchOptions(arguments:)`, `MapleStores.focus`.
- Produces:
  - `extension WorkshopStore { @discardableResult public func collect(from history: FocusSessionStore.History?, running: UUID?) -> Int }` (leaves newly in the van; 0 when `history` is nil)
  - `FocusStores.workshop: WorkshopStore` (a file in the launch's folder for `live` and `sandbox`, memory for `demo`)

- [ ] **Step 1: Write the failing tests**

Add to `MapleKit/Tests/MapleServicesTests/WorkshopStoreTests.swift`, above the suite, a launch helper:

```swift
/// A demo launch with seventeen days of sessions (`-MapleDemoHistory`) on Friday 23 October 2026, refreshed once as the
/// app does at launch.
@MainActor
private func launchWithHistory(_ arguments: [String] = []) async throws -> MapleStores {
    let all = ["-MapleDemoShip", "f1", "-MapleDemoFocus", "idle", "-MapleDemoHistory", "YES"] + arguments
    let stores = MapleStores.make(DemoLaunchOptions(arguments: all), directory: try temporaryDirectory(), calendar: utc,
                                  now: at(2026, 10, 23, 9))
    await stores.focus.sessions.refresh()
    return stores
}
```

and inside the suite, these tests:

```swift
    @Test("History fills the van once: a second read of the same ledger brings nothing new")
    func collects() async throws {
        let stores = try await launchWithHistory()
        let workshop = stores.focus.workshop
        #expect(workshop.leaves == 0)
        await stores.focus.sessions.loadHistory()
        let history = try #require(stores.focus.sessions.history)
        let running = stores.focus.sessions.running?.id

        let gained = workshop.collect(from: history, running: running)
        #expect(gained > 0)
        #expect(gained == LeafEarnings.total(history.records, credits: history.credits, running: running))
        #expect(workshop.leaves == gained)
        #expect(workshop.collect(from: history, running: running) == 0)
        #expect(workshop.leaves == gained)
    }

    @Test("In a free-tier build every session is a plain timer, and each still earns a leaf per 5 minutes focused")
    func freeTier() async throws {
        let stores = try await launchWithHistory(["-MapleDemoScreenTime", "unavailable"])
        await stores.focus.sessions.loadHistory()
        let history = try #require(stores.focus.sessions.history)
        #expect(history.sessions.allSatisfy { $0.savedSeconds == 0 })
        let expected = history.sessions.reduce(0) { $0 + $1.focusedSeconds / 300 }
        #expect(expected > 0)
        #expect(stores.focus.workshop.collect(from: history, running: nil) == expected)
    }

    @Test("Before History has been read, the van is left as it is")
    func notLoaded() throws {
        let store = open(try url())
        store.noteEarned(12)
        #expect(store.collect(from: nil, running: nil) == 0)
        #expect(store.collect(from: FocusSessionStore.History(records: [], credits: [], sessions: []), running: nil) == 0)
        #expect(store.leaves == 12)
    }
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -collect-test-diagnostics never -only-testing:MapleServicesTests 2>&1 | tail -30`
Expected: the build fails with `value of type 'FocusStores' has no member 'workshop'` and `value of type 'WorkshopStore' has no member 'collect'`, ending `** TEST FAILED **`.

- [ ] **Step 3: Write the fill from History**

`MapleKit/Sources/MapleServices/Workshop/WorkshopStore+History.swift`:

```swift
import Foundation
import MapleCore

extension WorkshopStore {
    /// Brings the van's leaves up to what the whole ledger shows (syrup van design §2). Call it after
    /// `FocusSessionStore.loadHistory()`: at launch, and when a session ends. Calling it again with the same ledger
    /// changes nothing.
    /// - Parameters:
    ///   - history: `FocusSessionStore.history`; nil before History has been read, which changes nothing.
    ///   - running: The session running now (`FocusSessionStore.running?.id`). Its leaves arrive when it ends.
    /// - Returns: The leaves newly in the van.
    @discardableResult
    public func collect(from history: FocusSessionStore.History?, running: UUID?) -> Int {
        guard let history else { return 0 }
        return noteEarned(LeafEarnings.total(history.records, credits: history.credits, running: running, tuning: tuning))
    }
}
```

- [ ] **Step 4: Carry the store in `FocusStores`**

In `MapleKit/Sources/MapleServices/Focus/FocusStores.swift`, three small edits.

After the line `public let subjects: SubjectStore`, add:

```swift
    /// The syrup van's leaves, syrup and machines.
    public let workshop: WorkshopStore
```

In the `files` factory, after the line `subjects: SubjectStore(storage: JSONStorage(.file(directory.appending(path: SubjectStore.file)))),`, add:

```swift
            workshop: WorkshopStore(storage: JSONStorage(.file(directory.appending(path: WorkshopStore.file)))),
```

In the `demo` factory, after the line `subjects: SubjectStore(storage: JSONStorage(.memory, initial: seed?.subjects)),`, add:

```swift
            workshop: WorkshopStore(storage: JSONStorage(.memory)),
```

Then check nothing else builds a `FocusStores` by hand:

Run: `grep -rn "FocusStores(" App MapleKit/Sources MapleKit/Tests | grep -v "FocusStores.swift"`
Expected: no output. If a line appears, add the same `workshop:` argument there, after its `subjects:` argument, with `JSONStorage(.memory)`.

- [ ] **Step 5: Run the tests to see them pass**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -collect-test-diagnostics never -only-testing:MapleServicesTests 2>&1 | tail -30`
Expected: `** TEST SUCCEEDED **`, with "The syrup van's store" (8 tests) passing and no other suite failing.

- [ ] **Step 6: Record the decision**

In `docs/decisions.md`, add this entry directly above the line `## 2026-11-15 — F2's first slice: the Study record (subjects and History)`:

```markdown
## 2026-11-26 — The syrup van: the economy's rules (logic only, no screens yet)
The owner approved the syrup van design (`docs/superpowers/specs/2026-11-26-syrup-van-design.md`) with "yes to all, drop the tab bar". This entry covers its step 2, the economy; nothing is on screen yet.
- **Leaves.** One leaf for every 5 minutes, counted session by session. A session that blocked apps earns from its counted time; a plain timer earns from its time focused, so a free-tier build without Apple's Family Controls permission plays the whole game. A session ended early keeps the leaves that had fallen, and a session removed from History keeps what it earned. The running session's leaves arrive when it ends.
- **No balance is stored.** `workshop.json` holds what the member did (cooked, spent, each machine's level) and the highest total the ledger has shown. Leaves in the van are that total minus what was cooked and spent, so a leaf can't be counted twice, and a short read of the ledger can't take leaves away.
- **Syrup is counted in tenths of a bottle**, so an upgrade can add a fraction without rounding. One leaf is one bottle before any upgrade.
- **Upgrades.** Two machines, the evaporator and the filter press. Each level costs leaves and adds syrup per leaf; the machines' bonuses add up. Cooking uses the yield at the moment of cooking; syrup already made never changes.
- **The numbers are in one place,** `WorkshopTuning.starting`. The ladders' prices and bonuses are starting values: the design leaves the pace for its own pass (§14).
- **Consequence to know:** counted time stops at 6 hours a day and shrinks with unlocks, and time focused does neither, so a plain timer can out-earn a blocking session on a heavy day. The rule is `LeafEarnings.seconds(of:credit:)`.
- Spending syrup, decorations, special syrups and every screen come in later steps.
```

- [ ] **Step 7: Document how screens read the van**

In `docs/core-api.md`, add this section directly above the line `## Files, unlocks and time zones`:

```markdown
## The syrup van's economy

The rules are pure and live in `MapleCore/Workshop/`; `WorkshopStore` (`focus.workshop` on `FocusStores`) saves them as `workshop.json`.

- **Read:** `workshop.leaves` (in the van now), `workshop.syrupTenths` (tenths of a bottle; show `syrupTenths / 10` and one decimal), `workshop.tenthsPerLeaf`, `workshop.level(of:)`, and `workshop.price(of:)` (nil at the top of a ladder).
- **Fill:** after `await sessions.loadHistory()`, call `workshop.collect(from: sessions.history, running: sessions.running?.id)`. It returns the leaves that are new, which is what Pip carries back. Call it at launch and when a session ends; calling it again changes nothing.
- **Act:** `workshop.cook()` cooks one leaf (pass a count for more) and returns the leaves cooked. `workshop.upgrade(.evaporator)` returns `.upgraded(level:)`, `.short(by:)` or `.atTop`.
- **While the file can't be read** (a launch before the first unlock), `isAvailable` is false, the van shows empty, and every call changes nothing: `collect`, `noteEarned` and `cook` return 0, `upgrade` returns nil.
- **One session's leaves,** for the running view and the summary: `LeafEarnings.leaves(of:credit:)`, or `LeafEarnings.leaves(forSeconds:)` for a length on the clock ("about 10 leaves").
- **Numbers:** only in `WorkshopTuning.starting`. Never write a price or a pace into a screen.
```

- [ ] **Step 8: Run everything**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -collect-test-diagnostics never 2>&1 | tail -15`
Expected: `** TEST SUCCEEDED **`.

Run: `SIMULATOR="iPhone 17" Scripts/build.sh 2>&1 | grep -c "warning:"`
Expected: `0`.

Run: `Scripts/check-release.sh`
Expected: it ends without reporting a problem (the same output as on the branch this one started from).

- [ ] **Step 9: Commit**

```bash
git add MapleKit/Sources/MapleServices/Workshop/WorkshopStore+History.swift MapleKit/Sources/MapleServices/Focus/FocusStores.swift MapleKit/Tests/MapleServicesTests/WorkshopStoreTests.swift docs/decisions.md docs/core-api.md
git commit -m "Syrup van: History fills the van, FocusStores carries it, and the docs

Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>"
```

---

## When this plan is done

- The van's economy exists and is tested, with nothing on screen and no change a member can see.
- The branch is not pushed. Pushing and opening its pull request wait for the owner's yes, and for the Study record's pull request to merge first if this branch was stacked on it.
- Next is step 3, the scene shell, which needs its own plan. It adds the `ShippedFeatures` switch for the van, the DEBUG launch arguments that seed leaves and syrup, the clock that sets the timer, and the first call to `workshop.collect`.
