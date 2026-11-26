# Syrup van, step 3: the scene and the clock timer — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The app opens on the van under the maple tree, the member enters the workshop, and the boiler's gauge opens a drawn analog clock that sets the length and starts today's session.

**Architecture:** The art is drawn in code by `Scripts/art` and exported as layered SVGs into the asset catalog. Three pure models in `MapleCore/Van` (the clock, the home's words, the canvas maths) carry the logic and are tested. The views live in `App/Features/Van` and are switched on by one flag, `ShippedFeatures.syrupVan`, so the tree home, the tab bar and the old start screen stay in the code and come back with `-MapleDemoShip f1`. Everything else is reused as it is: the running session, End early, the receipt, History, the Herbarium, Profile.

**Tech Stack:** Swift 6, SwiftUI (iOS 27), Swift Testing, Python 3 for the art generator (standard library only), SVG image sets.

**Spec:** `docs/superpowers/specs/2026-11-26-syrup-van-design.md` (§5, §6.1 to §6.4, §9, §10, §11, §12 step 3). The economy it builds on is in `docs/core-api.md`, "The syrup van's economy".

## Global Constraints

- iPhone only. Never design for, build for or mention another Apple platform.
- Zero compiler warnings, Swift 6 strict concurrency. The app target, `MapleDesign` and `MapleServices` are MainActor by default; `MapleCore` is nonisolated and `Sendable`. A `Shape` in the app target must be marked `nonisolated`.
- Tests use Swift Testing and are written first for logic. Views are checked in the simulator, and the screenshots are looked at.
- `Scripts/check-release.sh` fails on the string `Demo` anywhere in the Release binary. Every `"MapleDemo…"` key and every reference to `DemoLaunchOptions` sits inside `#if DEBUG`.
- Edits to `RootView.swift`, `MapleApp.swift`, `Tokens.swift` and `Package.swift` stay small. `App/` is a synchronized folder: new files need no project edit.
- Copy is sentence case and never says "fail" or "quit".
- The timer never shows a leaf count or a rate (§6.2). There are no presets, no breaks, no strictness levels and no "What's this for?" note (§6.3). Every session the van starts is Gentle with no break.
- Length limits are today's: 20 minutes to 3 hours in 5-minute steps (`DialLayout.minimumMinutes`, `maximumMinutes`, `stepMinutes`).
- Say "free-tier build without Apple's Family Controls permission" in docs, never "a build that can never block".
- Don't edit `MapleKit/Sources/MapleCore/Collection/NightLedger.swift`. Don't push or merge without the owner's yes.
- Commits end with a blank line and `Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>`.
- Build: `SIMULATOR="iPhone 17" Scripts/build.sh`. Tests: `SIMULATOR="iPhone 17" Scripts/test.sh -collect-test-diagnostics never`. The one `warning:` line from `appintentsmetadataprocessor` is Xcode's notice, not a compiler warning.

## What is out of scope (later steps)

- The tree view while a session runs, the falling leaves, Pip falling, the walk back and the summary (step 4). Until then a session runs, ends early and shows its receipt on today's screens.
- The shop, decorating, upgrades on screen, clothes (steps 5 and 6). Night (step 7).
- The bucket picture beside the clock (§6.2, Proposed): it needs Pip's bucket art from step 4.

## Review Focus

1. **Largest text sizes.** At the accessibility sizes the greeting, the clock's hub digits and the Start button must stay readable and on screen. Expected: text scales, the scene shrinks behind it, nothing is clipped. Pinned by Task 5 step 7 and Task 6 step 6 (screenshots at `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL`).
2. **A session already running when the app opens.** Expected: the app opens on the running session as today (`FocusArrival`), not on the van with a Start button that does nothing. Pinned by Task 6 step 7.
3. **The van's file can't be read yet** (a launch before the first unlock). Expected: the counters show nothing rather than zero, and tapping the pot does nothing. Pinned by `VanHomeModelTests.unavailable` (Task 4).
4. **Dragging the hand round and round past the limits.** Expected: it stops at 3 hours and at 20 minutes and never wraps. Pinned by `ClockSettingTests.limits` (Task 3).
5. **VoiceOver and Switch Control.** Expected: the length can be set without dragging (the adjustable action and the minus and plus buttons), and every picture button has a label. Pinned by Task 6 step 5 (`accessibilityAdjustableAction`) and Task 5's labels.

---

### Task 1: Export the art as layers into the asset catalog

The generator already draws both views. Home is `Scripts/art/vanart/build.py`. The workshop is `Scripts/art/vanart/inside.py`: the home scene's own room (`van.workshop`) drawn under a second camera, `inside.CAMERA`, which stands straight in front of the cut-away side at eye level (no turn, looking 6° down), like a dollhouse. Both rear doors are shut and edge-on, the maple and the sky are above the room and the lawn runs off the bottom (the owner asked for a front view that does not look down from above, was shown five, tried "between 2 and 3" and settled on the first, "actually 1 works"; a flat room with no van round it, a turned side view and home's own angle closer in were all tried before and turned down; the five are in `docs/design/art/2026-11-26-workshop-angles/`). The lawn's crate and bench use a second camera, `inside.GROUND`, that looks a little more down, because the grass in front is nearer and lower than the room. `inside.workshop_layers()` already returns the workshop as layers. This task splits home the same way and writes both into the asset catalog, so Pip, the smoke and the drifting leaves can move by themselves and the canopy isn't cut off at the top of the screen.

**Files:**
- Modify: `Scripts/art/vanart/build.py`
- Create: `Scripts/art/vanart/export.py`
- Modify: `Scripts/art/build_van_art.py`
- Create: `Scripts/art/check-van-art.sh`
- Create (generated): `App/Resources/Assets.xcassets/Van/*.imageset/`

**Interfaces:**
- Consumes (already in the repository): `Svg.text(viewbox=)`, `van.workshop(s, with_pip=, steam=)`, `van.roof_load(s, smoke=)`, `van.chimney_smoke(s)`, `van.pip_at_home(s)`, `inside.workshop_layers() -> (layers, marks)`, `inside.BOX`, `inside.CAMERA`, `core.using(camera)`.
- Produces: image sets named `VanHomeScene`, `VanHomeSmoke`, `VanHomeLeaves`, `VanHomePip`, `VanWorkshopRoom`, `VanWorkshopSteam`, `VanWorkshopSmoke`, `VanWorkshopPip`. Home layers share the view box `0 -1000 1600 3460`; workshop layers share `inside.BOX`, which is `0 0 852 1846` (the workshop has its own camera, so its own coordinates, starting at its corner). In those units the gauge is at (720, 881) with radius 44, the pot at (361, 904), the logbook at (764, 958) and the leaf basket at (163, 1060) (`marks` in `inside.py`). In home units the maple's trunk is at (320, 1050).

- [ ] **Step 1: Split the home scene into layers**

In `Scripts/art/vanart/build.py`, replace `home_scene` with:

```python
HOME_BOX = (0, -1000, 1600, 3460)


def home_layers():
    """The home view as layers, back to front. The sky is not drawn: the app paints it, edge to edge."""
    scene = Svg(W, H)
    outdoor.ground(scene)
    outdoor.trunk(scene)
    outdoor.canopy(scene)
    outdoor.string_lights(scene)
    outdoor.bunting(scene, to=(776, 668))
    van.shadow(scene)
    van.left_door(scene)
    van.workshop(scene, with_pip=False)
    van.cab_and_sill(scene)
    outdoor.crate(scene, -190, 236, -75, 150, 104, 80, "leaf-crate-1", 61)
    van.right_door(scene)
    van.wheels(scene)
    van.roof_load(scene, smoke=False)
    outdoor.basket(scene)
    outdoor.mushrooms(scene)
    outdoor.bench(scene)
    outdoor.logs(scene)
    outdoor.crate(scene, -50, 462, -75, 150, 110, 80, "leaf-crate-2", 67)
    outdoor.doormat(scene)

    smoke = Svg(W, H)
    van.chimney_smoke(smoke)
    leaves = Svg(W, H)
    outdoor.drifting_leaves(leaves)
    pip = Svg(W, H)
    van.pip_at_home(pip)
    return {"VanHomeScene": scene, "VanHomeSmoke": smoke, "VanHomeLeaves": leaves, "VanHomePip": pip}


def home_scene():
    """Everything in one drawing with its sky, for looking at outside the app."""
    s = Svg(W, H)
    s.begin("sky")
    s.fill(poly([(0, 0), (W, 0), (W, H), (0, H)]), BG)
    s.end()
    layers = home_layers()
    for name in ("VanHomeScene", "VanHomeSmoke", "VanHomePip", "VanHomeLeaves"):
        s.parts += layers[name].parts
    return s
```

- [ ] **Step 2: Write the exporter**

Create `Scripts/art/vanart/export.py`:

```python
"""Writes the app's image sets: one SVG per layer, with the catalog's Contents.json beside it."""

import json
import pathlib

from . import build, inside


def write_imagesets(catalog: pathlib.Path):
    folder = catalog / "Van"
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    written = []
    for layers, box in ((build.home_layers(), build.HOME_BOX), (inside.workshop_layers()[0], inside.BOX)):
        for name, drawing in layers.items():
            imageset = folder / f"{name}.imageset"
            imageset.mkdir(exist_ok=True)
            (imageset / f"{name}.svg").write_text(drawing.text(viewbox=box))
            contents = {
                "images": [{"filename": f"{name}.svg", "idiom": "universal"}],
                "info": {"author": "xcode", "version": 1},
                "properties": {"preserves-vector-representation": True, "template-rendering-intent": "original"},
            }
            (imageset / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
            written.append(name)
    return written
```

Replace the body of `Scripts/art/build_van_art.py` after the `sys.path.insert` line with:

```python
from vanart import build, export, inside  # noqa: E402

repo = pathlib.Path(__file__).resolve().parents[2]
names = export.write_imagesets(repo / "App" / "Resources" / "Assets.xcassets")
print("image sets:", ", ".join(names))
if len(sys.argv) > 1:
    out = pathlib.Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    (out / "home-scene.svg").write_text(build.home_scene().text())
    (out / "workshop-scene.svg").write_text(inside.workshop_scene().text(viewbox=inside.BOX))
    print("previews in", out)
```

- [ ] **Step 3: Write the check that the committed art matches the generator**

Create `Scripts/art/check-van-art.sh` and make it executable (`chmod +x`):

```sh
#!/bin/sh
# Fails when the image sets in the catalog differ from what the generator draws.
set -e
cd "$(dirname "$0")/../.."
python3 -I Scripts/art/build_van_art.py >/dev/null
if ! git diff --quiet -- App/Resources/Assets.xcassets/Van; then
    echo "The van's image sets are out of date: run python3 -I Scripts/art/build_van_art.py and commit." >&2
    git diff --stat -- App/Resources/Assets.xcassets/Van >&2
    exit 1
fi
echo "The van's image sets match the generator."
```

- [ ] **Step 4: Generate, and see the check pass**

Run: `python3 -I Scripts/art/build_van_art.py && git add App/Resources/Assets.xcassets/Van && Scripts/art/check-van-art.sh`
Expected: `image sets: VanHomeScene, VanHomeSmoke, VanHomeLeaves, VanHomePip, VanWorkshopRoom, VanWorkshopSteam, VanWorkshopSmoke, VanWorkshopPip`, then `The van's image sets match the generator.`

- [ ] **Step 5: Build, to prove the catalog accepts the SVGs**

Run: `SIMULATOR="iPhone 17" Scripts/build.sh 2>&1 | grep -E "error|warning: |BUILD"`
Expected: `** BUILD SUCCEEDED **`, and no line naming an `.svg`. If the asset compiler rejects a file, it names the element; remove that SVG feature in the generator. The drawings use only `path`, `g` (one with a `transform`, for the leaf basket), fills, strokes, `opacity`, `fill-rule` and `stroke-dasharray`. If `transform` on a group is what it rejects, draw the basket at its final place instead: give `outdoor.basket` an offset and scale argument.

- [ ] **Step 6: Commit**

```bash
git add Scripts/art App/Resources/Assets.xcassets/Van
git commit -m "Syrup van art: layered image sets for the home view and the workshop"
```

---

### Task 2: The switch, `ShippedFeatures.syrupVan`

**Files:**
- Modify: `MapleKit/Sources/MapleCore/Collection/ShippedFeatures.swift`
- Modify: `MapleKit/Sources/MapleServices/Demo/DemoLaunchOptions.swift:126-130`
- Test: `MapleKit/Tests/MapleCoreTests/VanFeatureTests.swift`, `MapleKit/Tests/MapleServicesTests/VanDemoOptionsTests.swift`

**Interfaces:**
- Produces: `ShippedFeatures.syrupVan: Bool`; `ShippedFeatures.init(releases: Set<RewardRelease>, syrupVan: Bool = false)`; `.current` and `.all` have it on. DEBUG: `-MapleDemoShip f1` and `m1` are the app without the van, `-MapleDemoShip van` is today's releases with it.

- [ ] **Step 1: Write the failing tests**

`MapleKit/Tests/MapleCoreTests/VanFeatureTests.swift`:

```swift
import Testing
@testable import MapleCore

@Suite("The syrup van's switch")
struct VanFeatureTests {
    @Test("The app ships with the van; a set of releases alone leaves it off, so older screens can still be opened")
    func shipped() {
        #expect(ShippedFeatures.current.syrupVan)
        #expect(ShippedFeatures.all.syrupVan)
        #expect(!ShippedFeatures(releases: [.m1, .f1]).syrupVan)
        #expect(ShippedFeatures.current.releases == [.m1, .f1])
        #expect(ShippedFeatures.current != ShippedFeatures(releases: [.m1, .f1]))
    }
}
```

`MapleKit/Tests/MapleServicesTests/VanDemoOptionsTests.swift`:

```swift
#if DEBUG
import Testing
@testable import MapleCore
@testable import MapleServices

@Suite("The van in demo launches")
struct VanDemoOptionsTests {
    @Test("-MapleDemoShip f1 opens the app as it was before the van, and van opens it with the van")
    func ship() {
        #expect(DemoLaunchOptions(arguments: ["-MapleDemoShip", "f1"]).ship == ShippedFeatures(releases: [.m1, .f1]))
        #expect(DemoLaunchOptions(arguments: ["-MapleDemoShip", "van"]).ship == ShippedFeatures(releases: [.m1, .f1], syrupVan: true))
        #expect(DemoLaunchOptions(arguments: []).ship == nil)
    }
}
#endif
```

- [ ] **Step 2: Run them and see them fail**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -collect-test-diagnostics never -only-testing:MapleCoreTests 2>&1 | grep -E "error:" | sort -u | head`
Expected: `error: value of type 'ShippedFeatures' has no member 'syrupVan'`.

- [ ] **Step 3: Add the switch**

In `ShippedFeatures.swift`, replace the stored property, the initialiser and the two statics:

```swift
    public var releases: Set<RewardRelease>
    /// The syrup van is the app's home: the scene replaces the tree home's stage, the tab bar and the start screen
    /// (syrup van design §9, §12 step 3). Off, the app is as it was before the van.
    public var syrupVan: Bool

    public init(releases: Set<RewardRelease>, syrupVan: Bool = false) {
        self.releases = releases
        self.syrupVan = syrupVan
    }
```

```swift
    public static let current = ShippedFeatures(releases: [.m1, .f1], syrupVan: true)
```

```swift
    public static let all = ShippedFeatures(releases: Set(RewardRelease.allCases), syrupVan: true)
```

Keep each static's existing doc comment above it.

In `DemoLaunchOptions.swift`, replace the `ship = switch` block:

```swift
        ship = switch value("MapleDemoShip")?.lowercased() {
        case "f1": ShippedFeatures(releases: [.m1, .f1])
        case "m1": ShippedFeatures(releases: [.m1])
        case "van": ShippedFeatures(releases: [.m1, .f1], syrupVan: true)
        default: nil
        }
```

- [ ] **Step 4: Run the whole suite**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -collect-test-diagnostics never 2>&1 | grep -E "error:|Test run with|recorded an issue" | sort -u`
Expected: three `✔ Test run with … passed` lines. A test that fails here compared a value against `ShippedFeatures(releases: [.m1, .f1])` where it meant `.current`: change that test's expectation to `.current`, and nothing else.

- [ ] **Step 5: Commit**

```bash
git add MapleKit
git commit -m "Syrup van: one switch for the scene, on by default, off under -MapleDemoShip f1"
```

---

### Task 3: The clock's logic, `ClockSetting`

**Files:**
- Create: `MapleKit/Sources/MapleCore/Van/ClockSetting.swift`
- Test: `MapleKit/Tests/MapleCoreTests/ClockSettingTests.swift`

**Interfaces:**
- Produces:
  - `public struct ClockSetting: Sendable, Equatable`
  - `init(minutes: Int)` (snaps to 5, clamps to 20...180)
  - `var minutes: Int { get }`, `var minuteAngle: Double`, `var hourAngle: Double` (degrees clockwise from 12)
  - `var hubText: String` ("0:50"), `var wholeHours: Int`, `var faceFill: Double` (0...1, the part of the hour the long hand has swept)
  - `@discardableResult mutating func turn(toAngle degrees: Double) -> Bool`
  - `@discardableResult mutating func nudge(_ steps: Int) -> Bool`
  - `static func angle(dx: Double, dy: Double) -> Double` (a touch's angle, clockwise from 12)

- [ ] **Step 1: Write the failing tests**

`MapleKit/Tests/MapleCoreTests/ClockSettingTests.swift`:

```swift
import Testing
@testable import MapleCore

@Suite("The clock that sets a session's length")
struct ClockSettingTests {
    @Test("A length snaps to 5 minutes and stays between 20 minutes and 3 hours")
    func snapped() {
        #expect(ClockSetting(minutes: 52).minutes == 50)
        #expect(ClockSetting(minutes: 53).minutes == 55)
        #expect(ClockSetting(minutes: 7).minutes == 20)
        #expect(ClockSetting(minutes: 500).minutes == 180)
        #expect(ClockSetting(minutes: -30).minutes == 20)
    }

    @Test("The long hand shows the minutes past the hour, the short hand the whole length as on any clock")
    func hands() {
        #expect(ClockSetting(minutes: 50).minuteAngle == 300)
        #expect(ClockSetting(minutes: 50).hourAngle == 25)
        #expect(ClockSetting(minutes: 90).minuteAngle == 180)
        #expect(ClockSetting(minutes: 90).hourAngle == 45)
        #expect(ClockSetting(minutes: 120).minuteAngle == 0)
        #expect(ClockSetting(minutes: 120).hourAngle == 60)
    }

    @Test("The hub reads hours and minutes: 0:50, 1:05, 1:30, 3:00")
    func hub() {
        #expect(ClockSetting(minutes: 50).hubText == "0:50")
        #expect(ClockSetting(minutes: 65).hubText == "1:05")
        #expect(ClockSetting(minutes: 90).hubText == "1:30")
        #expect(ClockSetting(minutes: 180).hubText == "3:00")
        #expect(ClockSetting(minutes: 125).wholeHours == 2)
        #expect(ClockSetting(minutes: 45).faceFill == 0.75)
        #expect(ClockSetting(minutes: 60).faceFill == 0)
    }

    @Test("Turning the long hand moves by the shortest way, and passing the top adds or takes away an hour")
    func turning() {
        var clock = ClockSetting(minutes: 50)
        #expect(clock.turn(toAngle: 330))
        #expect(clock.minutes == 55)
        #expect(clock.turn(toAngle: 0))
        #expect(clock.minutes == 60)
        #expect(clock.turn(toAngle: 30))
        #expect(clock.minutes == 65)
        #expect(clock.turn(toAngle: 330))
        #expect(clock.minutes == 55)
        #expect(!clock.turn(toAngle: 331))
        #expect(clock.minutes == 55)
    }

    @Test("An angle outside one turn, or a touch that isn't a number, is handled")
    func oddAngles() {
        var clock = ClockSetting(minutes: 50)
        clock.turn(toAngle: 690)
        #expect(clock.minutes == 55)
        clock.turn(toAngle: -60)
        #expect(clock.minutes == 50)
        #expect(!clock.turn(toAngle: .nan))
        #expect(!clock.turn(toAngle: .infinity))
        #expect(clock.minutes == 50)
    }

    @Test("The hand stops at 3 hours and at 20 minutes and never wraps round")
    func limits() {
        var long = ClockSetting(minutes: 180)
        #expect(!long.turn(toAngle: 90))
        #expect(long.minutes == 180)
        #expect(long.turn(toAngle: 270))
        #expect(long.minutes == 165)
        var short = ClockSetting(minutes: 20)
        #expect(!short.turn(toAngle: 0))
        #expect(short.minutes == 20)
        for _ in 0 ..< 100 { long.turn(toAngle: 90); long.turn(toAngle: 180); long.turn(toAngle: 270); long.turn(toAngle: 0) }
        #expect(long.minutes == 180)
    }

    @Test("The minus and plus buttons move 5 minutes and stop at the limits")
    func nudging() {
        var clock = ClockSetting(minutes: 50)
        #expect(clock.nudge(1))
        #expect(clock.minutes == 55)
        #expect(clock.nudge(-10))
        #expect(clock.minutes == 20)
        #expect(!clock.nudge(-1))
        #expect(clock.nudge(100))
        #expect(clock.minutes == 180)
    }

    @Test("A touch's angle is measured clockwise from 12")
    func touchAngle() {
        #expect(ClockSetting.angle(dx: 0, dy: -10) == 0)
        #expect(ClockSetting.angle(dx: 10, dy: 0) == 90)
        #expect(ClockSetting.angle(dx: 0, dy: 10) == 180)
        #expect(ClockSetting.angle(dx: -10, dy: 0) == 270)
    }
}
```

- [ ] **Step 2: Run and see it fail**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -collect-test-diagnostics never -only-testing:MapleCoreTests 2>&1 | grep -E "error:" | sort -u | head -3`
Expected: `error: cannot find 'ClockSetting' in scope`.

- [ ] **Step 3: Write it**

`MapleKit/Sources/MapleCore/Van/ClockSetting.swift`:

```swift
import Foundation

/// The drawn clock that sets a session's length (syrup van design §6.2). Pure.
///
/// The long hand is the minutes past the hour and the short hand follows it, as on any clock, so a length reads as a
/// time: 1 hour 30 has the long hand at 6 and the short hand half-way between 1 and 2. Lengths keep today's limits and
/// step (`DialLayout`).
public struct ClockSetting: Sendable, Equatable {
    public private(set) var minutes: Int

    public init(minutes: Int) {
        self.minutes = Self.allowed(minutes)
    }

    /// The long hand, in degrees clockwise from 12.
    public var minuteAngle: Double { Double(minutes % 60) * 6 }
    /// The short hand, in degrees clockwise from 12: 30 degrees an hour.
    public var hourAngle: Double { Double(minutes) * 0.5 }
    /// The digits in the hub: "0:50", "1:30".
    public var hubText: String {
        let part = minutes % 60
        return "\(minutes / 60):\(part < 10 ? "0" : "")\(part)"
    }

    public var wholeHours: Int { minutes / 60 }
    /// How much of the face the syrup colour fills: the part of the hour the long hand has swept.
    public var faceFill: Double { Double(minutes % 60) / 60 }

    /// Moves the long hand to `degrees` (clockwise from 12) by the shortest way round. Passing the top adds or takes
    /// away an hour. The hand stops at the limits.
    /// - Returns: Whether the length changed, for the tick.
    @discardableResult
    public mutating func turn(toAngle degrees: Double) -> Bool {
        guard degrees.isFinite else { return false }
        let wrapped = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let step = DialLayout.stepMinutes
        let target = (Int((wrapped / 6 / Double(step)).rounded()) * step) % 60
        var delta = (target - minutes % 60 + 60) % 60
        if delta >= 30 { delta -= 60 }
        return set(minutes + delta)
    }

    /// Moves by whole steps of 5 minutes: the minus and plus buttons, and VoiceOver's adjust.
    @discardableResult
    public mutating func nudge(_ steps: Int) -> Bool {
        let (moved, overflow) = steps.multipliedReportingOverflow(by: DialLayout.stepMinutes)
        return set(overflow ? (steps < 0 ? DialLayout.minimumMinutes : DialLayout.maximumMinutes) : minutes + moved)
    }

    /// The angle of a touch `dx` to the right of and `dy` below the clock's centre, clockwise from 12.
    public static func angle(dx: Double, dy: Double) -> Double {
        let degrees = atan2(dx, -dy) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }

    private mutating func set(_ value: Int) -> Bool {
        let next = min(max(value, DialLayout.minimumMinutes), DialLayout.maximumMinutes)
        guard next != minutes else { return false }
        minutes = next
        return true
    }

    private static func allowed(_ value: Int) -> Int {
        let step = DialLayout.stepMinutes
        let snapped = Int((Double(value) / Double(step)).rounded()) * step
        return min(max(snapped, DialLayout.minimumMinutes), DialLayout.maximumMinutes)
    }
}
```

- [ ] **Step 4: Run and see it pass**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -collect-test-diagnostics never -only-testing:MapleCoreTests 2>&1 | grep -E "error:|Test run with|recorded an issue" | sort -u`
Expected: `✔ Test run with … passed`. If `nudging`'s `nudge(-10)` expectation fails with 5, the clamp is wrong: 55 minus 50 is 5, clamped to 20.

- [ ] **Step 5: Commit**

```bash
git add MapleKit
git commit -m "Syrup van: the clock's logic (hands, hub digits, turning past the top, limits)"
```

---

### Task 4: The home's words, the van's session, the entrance and the canvas maths

**Files:**
- Create: `MapleKit/Sources/MapleCore/Van/VanHomeModel.swift`, `VanTimer.swift`, `VanEntrance.swift`, `VanCanvas.swift`
- Test: `MapleKit/Tests/MapleCoreTests/VanHomeModelTests.swift`, `VanTimerTests.swift`, `VanCanvasTests.swift`

**Interfaces:**
- Produces:
  - `VanHomeModel(phase: NowPhase, leaves: Int, syrupTenths: Int, isAvailable: Bool, minutesLeft: Int?)` with `greeting: String`, `status: String`, `leavesText: String?`, `syrupText: String?`, `gaugeText: String(minutes:)` as a static.
  - `VanTimer.preset(from: FocusPreset?) -> FocusPreset`, `VanTimer.startTitle(minutes: Int) -> String`, `VanTimer.blockingLine(canBlock: Bool, wantsBlock: Bool, hasApps: Bool) -> String`
  - `VanEntrance { full, short, crossFade }` with `seconds: Double` and `static func style(lastFull: Date?, now: Date, calendar: Calendar, reduceMotion: Bool) -> VanEntrance`
  - `VanCanvas(width:height:originX:originY:)` with `.home`, `.workshop`, `scale(width:height:) -> Double`, `point(x:y:width:height:) -> (x: Double, y: Double)`, `length(_:width:height:) -> Double`

- [ ] **Step 1: Write the failing tests**

`MapleKit/Tests/MapleCoreTests/VanHomeModelTests.swift`:

```swift
import Foundation
import Testing
@testable import MapleCore

@Suite("The van's home view: its words")
struct VanHomeModelTests {
    private func model(_ phase: NowPhase = .day, leaves: Int = 0, syrup: Int = 0, available: Bool = true, left: Int? = nil) -> VanHomeModel {
        VanHomeModel(phase: phase, leaves: leaves, syrupTenths: syrup, isAvailable: available, minutesLeft: left)
    }

    @Test("The greeting follows the member's own day", arguments: [
        (NowPhase.morning, "Good morning"), (.day, "Good afternoon"), (.evening, "Good evening"), (.windDown, "Winding down"),
        (.night, "Good night"),
    ])
    func greeting(phase: NowPhase, words: String) {
        #expect(model(phase).greeting == words)
    }

    @Test("One line says what is waiting: no leaves, one leaf, several")
    func waiting() {
        #expect(model(leaves: 0).status == "Pip is out of leaves")
        #expect(model(leaves: 1).status == "1 leaf waiting to cook")
        #expect(model(leaves: 45).status == "45 leaves waiting to cook")
    }

    @Test("While a session runs the line says so, with the time left and no leaf count")
    func running() {
        let line = model(leaves: 12, left: 32).status
        #expect(line == "Session running · \(FocusTimeText.length(minutes: 32)) left")
        #expect(!line.contains("leaf") && !line.contains("leaves"))
    }

    @Test("The counters read whole leaves and syrup to one decimal")
    func counters() {
        let shown = model(leaves: 45, syrup: 127)
        #expect(shown.leavesText == "45")
        #expect(shown.syrupText == "12.7")
        #expect(model(syrup: 30).syrupText == "3.0")
        #expect(model(syrup: 5).syrupText == "0.5")
    }

    @Test("Before the van's file can be read, the counters are absent rather than zero, and the line is empty")
    func unavailable() {
        let shown = model(leaves: 0, syrup: 0, available: false)
        #expect(shown.leavesText == nil)
        #expect(shown.syrupText == nil)
        #expect(shown.status.isEmpty)
    }

    @Test("The gauge's face reads the length that would start now")
    func gauge() {
        #expect(VanHomeModel.gaugeText(minutes: 50) == FocusTimeText.length(minutes: 50))
    }
}
```

`MapleKit/Tests/MapleCoreTests/VanTimerTests.swift`:

```swift
import Foundation
import Testing
@testable import MapleCore
@testable import MapleFocusCore

@Suite("The session the van starts")
struct VanTimerTests {
    @Test("It is Gentle with no break whatever the member's last preset was, and keeps that preset's apps and identity")
    func preset() {
        let apps = UUID()
        let deep = FocusPreset(name: "Deep", verb: .deep, minutes: 90, hasBreak: true, appSetID: apps, strictness: .locked,
                               pendingStrictness: .steady, pendingFrom: nil)
        let made = VanTimer.preset(from: deep)
        #expect(made.id == deep.id)
        #expect(made.appSetID == apps)
        #expect(made.strictness == .gentle)
        #expect(made.pendingStrictness == nil)
        #expect(!made.hasBreak)
        #expect(made.name == "Focus")
        #expect(made.verb == .focus)
    }

    @Test("With no preset at all it still makes one, with no apps to block")
    func noPreset() {
        let made = VanTimer.preset(from: nil)
        #expect(made.strictness == .gentle)
        #expect(!made.hasBreak)
        #expect(made.appSetID == nil)
    }

    @Test("The button reads Start and the length, and never a leaf count")
    func title() {
        #expect(VanTimer.startTitle(minutes: 50) == "Start · \(FocusTimeText.length(minutes: 50))")
        #expect(!VanTimer.startTitle(minutes: 50).lowercased().contains("lea"))
    }

    @Test("The line under the switch says what will happen to the member's apps")
    func blockingLine() {
        #expect(VanTimer.blockingLine(canBlock: false, wantsBlock: true, hasApps: true) == "Plain timer · apps aren't locked")
        #expect(VanTimer.blockingLine(canBlock: true, wantsBlock: false, hasApps: true) == "Block mode is off · apps aren't locked")
        #expect(VanTimer.blockingLine(canBlock: true, wantsBlock: true, hasApps: false) == "Choose apps to block")
        #expect(VanTimer.blockingLine(canBlock: true, wantsBlock: true, hasApps: true) == "Blocking your chosen apps")
    }

    @Test("The full entrance plays once a day; after that it is short, and Reduce Motion always cross-fades")
    func entrance() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let noon = Date(timeIntervalSince1970: 1_795_000_000)
        #expect(VanEntrance.style(lastFull: nil, now: noon, calendar: calendar, reduceMotion: false) == .full)
        #expect(VanEntrance.style(lastFull: noon.addingTimeInterval(-60), now: noon, calendar: calendar, reduceMotion: false) == .short)
        #expect(VanEntrance.style(lastFull: noon.addingTimeInterval(-86_400 * 2), now: noon, calendar: calendar, reduceMotion: false) == .full)
        #expect(VanEntrance.style(lastFull: nil, now: noon, calendar: calendar, reduceMotion: true) == .crossFade)
        #expect(VanEntrance.full.seconds == 1.2)
        #expect(VanEntrance.short.seconds < 0.5)
    }
}
```

`MapleKit/Tests/MapleCoreTests/VanCanvasTests.swift`:

```swift
import Testing
@testable import MapleCore

@Suite("Placing the van's art on a screen")
struct VanCanvasTests {
    @Test("The art fills the screen: it is scaled by whichever side needs more, and centred")
    func fills() {
        let canvas = VanCanvas(width: 1600, height: 3460, originX: 0, originY: -1000)
        // A screen of the same shape: scale is exact and nothing is cut.
        #expect(canvas.scale(width: 400, height: 865) == 0.25)
        let origin = canvas.point(x: 0, y: -1000, width: 400, height: 865)
        #expect(origin.x == 0 && origin.y == 0)
        // A wider screen: the width decides, and the art is centred top to bottom.
        #expect(canvas.scale(width: 800, height: 865) == 0.5)
        let middle = canvas.point(x: 800, y: 730, width: 800, height: 865)
        #expect(middle.x == 400 && middle.y == 432.5)
        #expect(canvas.length(104, width: 400, height: 865) == 26)
    }

    @Test("A canvas that doesn't start at zero places its own corner at the screen's")
    func corner() {
        let canvas = VanCanvas(width: 1140, height: 2470, originX: 150, originY: -80)
        let corner = canvas.point(x: 150, y: -80, width: 285, height: 617.5)
        #expect(corner.x == 0 && corner.y == 0)
        let inside = canvas.point(x: 921, y: 985, width: 285, height: 617.5)
        #expect(inside.x == 192.75 && inside.y == 266.25)
    }

    @Test("The workshop's gauge lands where it is drawn")
    func workshopGauge() {
        let gauge = VanCanvas.workshop.point(x: 720, y: 881, width: 426, height: 923)
        #expect(gauge.x == 360 && gauge.y == 440.5)
    }

    @Test("A screen with no size places everything at the origin instead of dividing by nothing")
    func empty() {
        let canvas = VanCanvas.workshop
        #expect(canvas.scale(width: 0, height: 0) == 0)
        let point = canvas.point(x: 720, y: 881, width: 0, height: 0)
        #expect(point.x == 0 && point.y == 0)
    }
}
```

- [ ] **Step 2: Run and see them fail**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -collect-test-diagnostics never -only-testing:MapleCoreTests 2>&1 | grep -E "error:" | sort -u | head -4`
Expected: `cannot find 'VanHomeModel' in scope`, and the same for `VanTimer`, `VanEntrance`, `VanCanvas`.

- [ ] **Step 3: Write the four files**

`MapleKit/Sources/MapleCore/Van/VanHomeModel.swift`:

```swift
import Foundation

/// The words on the van's home view (syrup van design §5.1). Pure.
public struct VanHomeModel: Sendable, Equatable {
    public let greeting: String
    /// One line about what is waiting; empty while the van can't be read.
    public let status: String
    /// The counters; nil while the van's file can't be read, so nothing is shown rather than a zero that isn't true.
    public let leavesText: String?
    public let syrupText: String?

    /// - Parameters:
    ///   - leaves: `WorkshopStore.leaves`.
    ///   - syrupTenths: `WorkshopStore.syrupTenths`.
    ///   - isAvailable: `WorkshopStore.isAvailable`.
    ///   - minutesLeft: The running session's minutes left; nil when none runs.
    public init(phase: NowPhase, leaves: Int, syrupTenths: Int, isAvailable: Bool, minutesLeft: Int?) {
        greeting = switch phase {
        case .morning: "Good morning"
        case .day: "Good afternoon"
        case .evening: "Good evening"
        case .windDown: "Winding down"
        case .night: "Good night"
        }
        if let minutesLeft {
            // No leaf count while a session runs (§6.5).
            status = "Session running · \(FocusTimeText.length(minutes: max(0, minutesLeft))) left"
        } else if !isAvailable {
            status = ""
        } else {
            status = switch max(0, leaves) {
            case 0: "Pip is out of leaves"
            case 1: "1 leaf waiting to cook"
            default: "\(leaves) leaves waiting to cook"
            }
        }
        leavesText = isAvailable ? "\(max(0, leaves))" : nil
        let tenths = max(0, syrupTenths)
        syrupText = isAvailable ? "\(tenths / 10).\(tenths % 10)" : nil
    }

    /// The gauge's face in the workshop: the length that would start now.
    public static func gaugeText(minutes: Int) -> String {
        FocusTimeText.length(minutes: minutes)
    }
}
```

`MapleKit/Sources/MapleCore/Van/VanTimer.swift`:

```swift
import Foundation

/// The session the van's clock starts (syrup van design §6.3, §6.4). Pure.
public enum VanTimer {
    /// The preset a start is made with. The van has no presets, breaks or strictness levels, but a start still needs a
    /// `FocusPreset`: this one is always Gentle with no break, and keeps the member's own app list and identity so the
    /// subject and the app list they chose carry on.
    public static func preset(from base: FocusPreset?) -> FocusPreset {
        var preset = base ?? FocusPreset(name: "Focus", verb: .focus, minutes: 50, hasBreak: false, appSetID: nil, strictness: .gentle)
        preset.name = "Focus"
        preset.verb = .focus
        preset.hasBreak = false
        preset.strictness = .gentle
        preset.pendingStrictness = nil
        preset.pendingFrom = nil
        return preset
    }

    /// "Start · 50m". Never a leaf count or a rate (§6.2).
    public static func startTitle(minutes: Int) -> String {
        "Start · \(FocusTimeText.length(minutes: minutes))"
    }

    /// The line under the block mode switch.
    public static func blockingLine(canBlock: Bool, wantsBlock: Bool, hasApps: Bool) -> String {
        if !canBlock { return "Plain timer · apps aren't locked" }
        if !wantsBlock { return "Block mode is off · apps aren't locked" }
        return hasApps ? "Blocking your chosen apps" : "Choose apps to block"
    }
}
```

`MapleKit/Sources/MapleCore/Van/VanEntrance.swift`:

```swift
import Foundation

/// How the camera goes into the van (syrup van design §5.3). Pure.
public enum VanEntrance: Sendable, Equatable {
    /// The whole entrance: once a day.
    case full
    /// Every other time that day.
    case short
    /// With Reduce Motion on.
    case crossFade

    public var seconds: Double {
        switch self {
        case .full: 1.2
        case .short: 0.45
        case .crossFade: 0.3
        }
    }

    public static func style(lastFull: Date?, now: Date, calendar: Calendar, reduceMotion: Bool) -> VanEntrance {
        if reduceMotion { return .crossFade }
        guard let lastFull, calendar.isDate(lastFull, inSameDayAs: now) else { return .full }
        return .short
    }
}
```

`MapleKit/Sources/MapleCore/Van/VanCanvas.swift`:

```swift
import Foundation

/// One of the van's drawings, and where its points land on a screen (syrup van design §10). Pure.
///
/// Every layer of a view is drawn on the same canvas, so the layers stack without any layout. The canvas fills the
/// screen like a photo set to fill: scaled by whichever side needs more, centred, the rest cut off.
public struct VanCanvas: Sendable, Equatable {
    public let width: Double
    public let height: Double
    /// The canvas's left and top edges in the drawing's own units: the drawings keep their coordinates, and the canvas
    /// is a window onto them.
    public let originX: Double
    public let originY: Double

    public init(width: Double, height: Double, originX: Double, originY: Double) {
        self.width = width
        self.height = height
        self.originX = originX
        self.originY = originY
    }

    /// The home view: `Scripts/art/vanart/build.py`, `HOME_BOX`.
    public static let home = VanCanvas(width: 1600, height: 3460, originX: 0, originY: -1000)
    /// The workshop, the same room from the front: `Scripts/art/vanart/inside.py`, `BOX`.
    public static let workshop = VanCanvas(width: 852, height: 1846, originX: 0, originY: 0)

    public func scale(width screenWidth: Double, height screenHeight: Double) -> Double {
        guard width > 0, height > 0, screenWidth > 0, screenHeight > 0 else { return 0 }
        return max(screenWidth / width, screenHeight / height)
    }

    /// Where the drawing's point (x, y) is on a screen of that size.
    public func point(x: Double, y: Double, width screenWidth: Double, height screenHeight: Double) -> (x: Double, y: Double) {
        let scale = scale(width: screenWidth, height: screenHeight)
        guard scale > 0 else { return (0, 0) }
        return ((screenWidth - width * scale) / 2 + (x - originX) * scale, (screenHeight - height * scale) / 2 + (y - originY) * scale)
    }

    /// A length in the drawing's units, on that screen.
    public func length(_ value: Double, width screenWidth: Double, height screenHeight: Double) -> Double {
        value * scale(width: screenWidth, height: screenHeight)
    }
}
```

- [ ] **Step 4: Run and see them pass**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -collect-test-diagnostics never -only-testing:MapleCoreTests 2>&1 | grep -E "error:|Test run with|recorded an issue" | sort -u`
Expected: `✔ Test run with … passed`.

- [ ] **Step 5: Commit**

```bash
git add MapleKit
git commit -m "Syrup van: the home's words, the session the van starts, the entrance and the canvas maths"
```

---

### Task 5: The scene on screen: home, the entrance, the workshop

**Files:**
- Create: `App/Features/Van/VanPalette.swift`, `VanLayers.swift`, `VanHomeView.swift`, `VanWorkshopView.swift`, `VanSceneView.swift`
- Modify: `App/Features/Home/HomeView.swift:58-60` (the `GeometryReader` in `body`)
- Modify: `App/RootView.swift` (the three tabs in `tabs`)
- Modify: `App/MapleApp.swift` (one `.environment` line)

**Interfaces:**
- Consumes: `VanCanvas`, `VanHomeModel`, `VanEntrance` (Task 4); the image sets (Task 1); `ShippedFeatures.syrupVan` (Task 2); `WorkshopStore` (`leaves`, `syrupTenths`, `isAvailable`, `cook()`, `collect(from:)`); `FocusSessionStore` (`running`, `loadHistory()`, `history`); `AppRouter` (`selectedTab`, `showHerbarium()`, `showFocus(.returnToSession)`); `CollectionStore.phase(at:)`; `PresetStore` (`presets`, `lastUsedID`).
- Produces: `VanSceneView(now: Date, onProfile: () -> Void, onTree: () -> Void, onStreak: () -> Void)`, `VanBackButton(title: String, action: () -> Void)`, `VanPalette` colours, `VanLayers(canvas:names:)`.

- [ ] **Step 1: Put the van's store in the environment**

In `App/MapleApp.swift`, after the line `.environment(stores.focus.subjects)`, add:

```swift
                .environment(stores.focus.workshop)
```

- [ ] **Step 2: The palette and the layer stack**

`App/Features/Van/VanPalette.swift`:

```swift
import MapleDesign
import SwiftUI

/// The van's colours, the same values the art is drawn with (`Scripts/art/vanart/core.py`).
enum VanPalette {
    static let sky = Color(hex: 0xFFDDC2)
    static let outline = Color(hex: 0x3A1C0E)
    static let cream = Color(hex: 0xF8E1B7)
    static let creamShade = Color(hex: 0xECD09F)
    static let stripe = Color(hex: 0xC75438)
    static let wood = Color(hex: 0xD69761)
    static let gold = Color(hex: 0xEDA04F)
    static let goldLight = Color(hex: 0xF6C16A)
    static let syrup = Color(hex: 0xC9662A)
    static let syrupLight = Color(hex: 0xE59A45)
    static let face = Color(hex: 0xFFF4E2)
    static let grass = Color(hex: 0xA09F5F)
    static let copper = Color(hex: 0xC87445)
}

/// A rounded, outlined plate: the look of every button and label that sits over the scene.
struct VanPlate: ViewModifier {
    var fill = VanPalette.cream

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(fill, in: Capsule())
            .overlay(Capsule().strokeBorder(VanPalette.outline, lineWidth: 2.5))
    }
}

/// The way back, top-left of any screen reached from the scene.
struct VanBackButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "chevron.backward")
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(VanPalette.outline)
                .modifier(VanPlate())
        }
        .buttonStyle(.plain)
    }
}
```

`App/Features/Van/VanLayers.swift`:

```swift
import MapleCore
import SwiftUI

/// The layers of one of the van's drawings, filling the space they are given. Every layer is drawn on the same
/// canvas, so they stack exactly. `motion` lets a caller move one layer (Pip's bob, the smoke's drift).
struct VanLayers<Moved: View>: View {
    let canvas: VanCanvas
    let names: [String]
    @ViewBuilder let motion: (String, Image) -> Moved

    var body: some View {
        GeometryReader { proxy in
            let scale = canvas.scale(width: proxy.size.width, height: proxy.size.height)
            ZStack {
                ForEach(names, id: \.self) { name in
                    motion(name, Image(name).resizable())
                        .frame(width: canvas.width * scale, height: canvas.height * scale)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .accessibilityHidden(true)
    }
}

extension VanCanvas {
    /// A point of the drawing, in a view of `size`.
    func point(_ x: Double, _ y: Double, in size: CGSize) -> CGPoint {
        let at = point(x: x, y: y, width: size.width, height: size.height)
        return CGPoint(x: at.x, y: at.y)
    }
}
```

- [ ] **Step 3: The home view**

`App/Features/Van/VanHomeView.swift`:

```swift
import MapleCore
import MapleDesign
import SwiftUI

/// Home: the van under the maple, a welcome, the time, what is waiting, and one way in (syrup van design §5.1).
struct VanHomeView: View {
    let model: VanHomeModel
    let now: Date
    let streak: Int
    let onEnter: () -> Void
    let onHerbarium: () -> Void
    let onProfile: () -> Void
    let onTree: () -> Void
    let onStreak: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathes = false

    var body: some View {
        ZStack {
            VanPalette.sky.ignoresSafeArea()
            VanLayers(canvas: .home, names: ["VanHomeScene", "VanHomeSmoke", "VanHomePip", "VanHomeLeaves"]) { name, image in
                switch name {
                case "VanHomePip": image.offset(y: breathes ? -2 : 0)
                case "VanHomeSmoke": image.offset(x: breathes ? 3 : -1, y: breathes ? -5 : 0).opacity(breathes ? 0.82 : 1)
                case "VanHomeLeaves": image.offset(y: breathes ? 6 : -4)
                default: image
                }
            }
            .ignoresSafeArea()
            // The maple opens the tree and its leaves, as the old home's tree did.
            GeometryReader { proxy in
                let trunk = VanCanvas.home.point(320, 1050, in: proxy.size)
                Button(action: onTree) { Color.clear }
                    .frame(width: 150, height: 220)
                    .contentShape(Rectangle())
                    .position(trunk)
                    .accessibilityLabel("Your maple")
            }
            .ignoresSafeArea()
            words
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { breathes = true }
        }
    }

    private var words: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if let leaves = model.leavesText { counter(leaves, image: "leaf.fill", label: "leaves") }
                if let syrup = model.syrupText { counter(syrup, image: "drop.fill", label: "bottles of syrup") }
                Spacer(minLength: 0)
                if streak >= 2 {
                    Button(action: onStreak) { counter("\(streak)", image: "flame.fill", label: "day streak") }
                        .buttonStyle(.plain)
                }
                roundButton("book.closed.fill", label: "Herbarium", action: onHerbarium)
                roundButton("person.fill", label: "Profile and settings", action: onProfile)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            VStack(spacing: 2) {
                Text(model.greeting)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                Text(now, format: .dateTime.hour().minute())
                    .font(.system(size: 64, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if !model.status.isEmpty {
                    Text(model.status)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .multilineTextAlignment(.center)
                }
            }
            .foregroundStyle(VanPalette.outline)
            .padding(.top, 18)
            .padding(.horizontal, 24)
            Spacer(minLength: 0)
            Button(action: onEnter) {
                Text("Open the van")
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                    .foregroundStyle(VanPalette.outline)
                    .frame(maxWidth: 260)
                    .modifier(VanPlate(fill: VanPalette.goldLight))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 20)
        }
    }

    private func counter(_ value: String, image: String, label: String) -> some View {
        Label(value, systemImage: image)
            .font(.system(.subheadline, design: .rounded).weight(.heavy))
            .foregroundStyle(VanPalette.outline)
            .modifier(VanPlate())
            .accessibilityLabel("\(value) \(label)")
    }

    private func roundButton(_ image: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: image)
                .font(.system(.body, design: .rounded).weight(.bold))
                .foregroundStyle(VanPalette.outline)
                .frame(width: 44, height: 44)
                .background(VanPalette.cream, in: Circle())
                .overlay(Circle().strokeBorder(VanPalette.outline, lineWidth: 2.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
```

- [ ] **Step 4: The workshop**

`App/Features/Van/VanWorkshopView.swift`:

```swift
import MapleCore
import MapleDesign
import MapleServices
import SwiftUI

/// The workshop: the van's cut-away room, seen from the front (syrup van design §5.2). The gauge is the Focus button, the pot
/// cooks a leaf, and the logbook opens History.
struct VanWorkshopView: View {
    let model: VanHomeModel
    /// The gauge's face: the length that would start, or the time left while a session runs.
    let gaugeText: String
    let onGauge: () -> Void
    let onBack: () -> Void

    @Environment(WorkshopStore.self) private var workshop
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathes = false
    @State private var showsHistory = false
    @State private var cooked = 0

    var body: some View {
        ZStack {
            VanPalette.sky.ignoresSafeArea()
            VanLayers(canvas: .workshop, names: ["VanWorkshopRoom", "VanWorkshopSteam", "VanWorkshopSmoke", "VanWorkshopPip"]) { name, image in
                switch name {
                case "VanWorkshopPip": image.offset(y: breathes ? -3 : 0)
                case "VanWorkshopSteam": image.offset(y: breathes ? -6 : 0).opacity(breathes ? 0.7 : 1)
                case "VanWorkshopSmoke": image.offset(x: breathes ? 4 : -1, y: breathes ? -6 : 0).opacity(breathes ? 0.82 : 1)
                default: image
                }
            }
            .ignoresSafeArea()
            GeometryReader { proxy in
                let canvas = VanCanvas.workshop
                let radius = canvas.length(44, width: proxy.size.width, height: proxy.size.height)
                Button(action: onGauge) {
                    // The face is small on a phone, so it carries the length alone; the line under the room names it.
                    Text(gaugeText)
                        .font(.system(size: max(11, radius * 0.5), weight: .heavy, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .foregroundStyle(VanPalette.outline)
                        .frame(width: radius * 1.4, height: radius * 1.4)
                        .background(VanPalette.face, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .frame(width: max(44, radius * 2), height: max(44, radius * 2))
                .position(canvas.point(720, 881, in: proxy.size))
                .accessibilityLabel("Focus timer, \(gaugeText)")
                .accessibilityHint("Opens the clock")

                Button(action: cook) { Color.clear }
                    .frame(width: max(44, canvas.length(120, width: proxy.size.width, height: proxy.size.height)),
                           height: max(44, canvas.length(90, width: proxy.size.width, height: proxy.size.height)))
                    .contentShape(Rectangle())
                    .position(canvas.point(361, 904, in: proxy.size))
                    .accessibilityLabel("Cooking pot")
                    .accessibilityHint(workshop.leaves > 0 ? "Cooks one leaf into syrup" : "No leaves to cook")
                    .sensoryFeedback(.impact(weight: .light), trigger: cooked)

                Button { showsHistory = true } label: { Color.clear }
                    .frame(width: max(44, canvas.length(70, width: proxy.size.width, height: proxy.size.height)),
                           height: max(44, canvas.length(60, width: proxy.size.width, height: proxy.size.height)))
                    .contentShape(Rectangle())
                    .position(canvas.point(764, 958, in: proxy.size))
                    .accessibilityLabel("Logbook")
                    .accessibilityHint("Opens your study record")
            }
            .ignoresSafeArea()
            VStack {
                HStack(spacing: 10) {
                    VanBackButton(title: "Outside", action: onBack)
                    Spacer(minLength: 0)
                    if let leaves = model.leavesText { counter(leaves, image: "leaf.fill", label: "leaves") }
                    if let syrup = model.syrupText { counter(syrup, image: "drop.fill", label: "bottles of syrup") }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                Spacer(minLength: 0)
                Text(workshop.leaves > 0 ? "Tap the gauge to set the timer, or the pot to cook a leaf" : "Tap the gauge to set the timer")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(VanPalette.outline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { breathes = true }
        }
        .sheet(isPresented: $showsHistory) {
            NavigationStack { HistoryView() }
        }
    }

    private func cook() {
        if workshop.cook() > 0 { cooked += 1 }
    }

    private func counter(_ value: String, image: String, label: String) -> some View {
        Label(value, systemImage: image)
            .font(.system(.subheadline, design: .rounded).weight(.heavy))
            .foregroundStyle(VanPalette.outline)
            .modifier(VanPlate())
            .accessibilityLabel("\(value) \(label)")
    }
}
```

- [ ] **Step 5: The scene: one place, two cameras, and the way between them**

`App/Features/Van/VanSceneView.swift`:

```swift
import MapleCore
import MapleDesign
import MapleServices
import SwiftUI

/// The van's scene: home outside, the workshop inside, and the entrance between them (syrup van design §5).
struct VanSceneView: View {
    let now: Date
    let streak: Int
    let onProfile: () -> Void
    let onTree: () -> Void
    let onStreak: () -> Void

    @Environment(AppRouter.self) private var router
    @Environment(CollectionStore.self) private var collection
    @Environment(FocusSessionStore.self) private var sessions
    @Environment(PresetStore.self) private var presets
    @Environment(WorkshopStore.self) private var workshop
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("van.lastFullEntrance") private var lastFullEntrance = 0.0
    @State private var isInside = VanSceneView.startsInside
    @State private var pushIn = 0.0

    var body: some View {
        let running = sessions.running
        let minutesLeft = running.map { max(0, Int(($0.plannedEnd.timeIntervalSince(now) / 60).rounded(.up))) }
        let model = VanHomeModel(
            phase: collection.phase(at: now), leaves: workshop.leaves, syrupTenths: workshop.syrupTenths,
            isAvailable: workshop.isAvailable, minutesLeft: minutesLeft
        )
        let length = presets.presets.first { $0.id == presets.lastUsedID }?.minutes ?? presets.presets.first?.minutes ?? 50
        ZStack {
            if isInside {
                VanWorkshopView(
                    model: model,
                    gaugeText: minutesLeft.map { FocusTimeText.length(minutes: $0) } ?? VanHomeModel.gaugeText(minutes: length),
                    onGauge: openTimer, onBack: { move(inside: false) }
                )
                .transition(.opacity)
            } else {
                VanHomeView(
                    model: model, now: now, streak: streak,
                    onEnter: { running == nil ? move(inside: true) : openTimer() },
                    onHerbarium: { router.showHerbarium() }, onProfile: onProfile, onTree: onTree, onStreak: onStreak
                )
                // The camera pushes in toward the van before the cut.
                .scaleEffect(1 + pushIn * 0.9, anchor: UnitPoint(x: 0.55, y: 0.62))
                .transition(.opacity)
            }
        }
        .task {
            // The van's leaves come from the whole ledger; a second look at the same ledger adds nothing.
            await sessions.loadHistory()
            workshop.collect(from: sessions.history)
        }
        .onChange(of: sessions.running?.id) { _, _ in
            Task {
                await sessions.loadHistory()
                workshop.collect(from: sessions.history)
            }
        }
    }

    /// The gauge: the clock that sets the length, or the running session.
    private func openTimer() {
        if sessions.running != nil {
            router.showFocus(.returnToSession)
        } else {
            router.selectedTab = .focus
        }
    }

    private func move(inside: Bool) {
        guard inside else {
            withAnimation(.easeInOut(duration: VanEntrance.short.seconds)) { isInside = false }
            return
        }
        let lastFull = lastFullEntrance > 0 ? Date(timeIntervalSince1970: lastFullEntrance) : nil
        let style = VanEntrance.style(lastFull: lastFull, now: now, calendar: .current, reduceMotion: reduceMotion)
        if style == .full { lastFullEntrance = now.timeIntervalSince1970 }
        guard style != .crossFade else {
            withAnimation(.easeInOut(duration: style.seconds)) { isInside = true }
            return
        }
        withAnimation(.easeIn(duration: style.seconds * 0.6)) { pushIn = 1 }
        Task {
            try? await Task.sleep(for: .seconds(style.seconds * 0.55))
            withAnimation(.easeOut(duration: style.seconds * 0.45)) { isInside = true }
            try? await Task.sleep(for: .seconds(style.seconds * 0.45))
            pushIn = 0
        }
    }

    /// DEBUG: `-MapleDemoPresent van:workshop` opens inside the van.
    private static var startsInside: Bool {
        #if DEBUG
        UserDefaults.standard.string(forKey: "MapleDemoPresent") == "van:workshop"
        #else
        false
        #endif
    }
}
```

- [ ] **Step 6: Wire it into Home, and hide the tab bar**

In `App/Features/Home/HomeView.swift`, replace

```swift
            GeometryReader { proxy in
                screen(content, proxy: proxy)
            }
```

with

```swift
            if collection.context.features.syrupVan {
                // The van is home (syrup van design §5.1). The sheets, covers and requests below stay this view's.
                VanSceneView(
                    now: now, streak: content.streak, onProfile: { sheet = .profile },
                    onTree: { cover = .tree(focusing: nil) }, onStreak: { sheet = .streak }
                )
            } else {
                GeometryReader { proxy in
                    screen(content, proxy: proxy)
                }
            }
```

In `App/RootView.swift`:
- add `@Environment(CollectionStore.self) private var collection` beside the other `@Environment` properties, and `import MapleServices` if the file doesn't import it;
- add this helper to `RootView`:

```swift
    /// With the van as home, the scene is the navigation and the tab bar is gone (syrup van design §9).
    private var hidesTabBar: Visibility { collection.context.features.syrupVan ? .hidden : .automatic }
```

- give each tab's content the modifier `.toolbarVisibility(hidesTabBar, for: .tabBar)`: on `HomeView()`, on `FocusView()`, and on `HerbariumView()`;
- give `HerbariumView()` a way back, since there is no tab bar to leave it by:

```swift
                    HerbariumView()
                        .toolbarVisibility(hidesTabBar, for: .tabBar)
                        .overlay(alignment: .bottomLeading) {
                            if collection.context.features.syrupVan {
                                VanBackButton(title: "Van") { router.selectedTab = .home }
                                    .padding(16)
                            }
                        }
```

- [ ] **Step 7: Build, run, and look**

Run: `SIMULATOR="iPhone 17" Scripts/build.sh 2>&1 | grep -E "error|warning: |BUILD"`
Expected: `** BUILD SUCCEEDED **` and only the `appintentsmetadataprocessor` line.

Then launch in the simulator and take screenshots (attach the simulator panel first; `docs/debug-launch-arguments.md` has the launch recipe the other screens use):
1. `-MapleDemoTab home -MapleDemoSpecies 12` — home: the van under the tree fills the screen, the canopy runs off the top, greeting and time are readable over the sky, "Open the van" is at the bottom.
2. Tap "Open the van" — the camera pushes in and the picture cross-fades to the workshop: the van's room seen from the front fills the width, with the maple above and the lawn below, and the gauge on the boiler reads a length.
3. `-MapleDemoTab home -MapleDemoPresent van:workshop` — opens straight in the workshop.
4. `-MapleDemoTab home -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL` — nothing is clipped; the time may shrink.
5. `-MapleDemoShip f1 -MapleDemoTab home` — the tree home and the tab bar, exactly as before.

What to adjust if a screenshot shows it, each in the named place and nowhere else:
- The van is too small or too low on screen: change `HOME_BOX` in `build.py` or `BOX` in `inside.py` (a smaller box zooms in; its first two numbers move the scene), re-run Task 1 step 4, and change `VanCanvas.home` or `.workshop` to the same numbers.
- The status bar's white text is hard to read on the sky: add `.overlay(alignment: .top) { LinearGradient(colors: [VanPalette.outline.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom).frame(height: 110).ignoresSafeArea().allowsHitTesting(false) }` to `VanHomeView`'s and `VanWorkshopView`'s `ZStack`.
- A tap target misses its picture: the numbers passed to `canvas.point` are the drawing's own coordinates. For the workshop they are `marks` in `Scripts/art/vanart/inside.py`; print them with `python3 -I -c "import sys; sys.path.insert(0,'Scripts/art'); from vanart import inside; print(inside.workshop_layers()[1])"`.

- [ ] **Step 8: Commit**

```bash
git add App
git commit -m "Syrup van: the home view, the entrance and the workshop, in place of the tree home and the tab bar"
```

---

### Task 6: The clock timer

**Files:**
- Create: `App/Features/Van/ClockFace.swift`, `App/Features/Van/ClockTimerView.swift`
- Modify: `App/Features/Focus/FocusView.swift:83-102` (the `destination` function), and one `@Environment` line

**Interfaces:**
- Consumes: `ClockSetting` (Task 3); `VanTimer` (Task 4); `VanPalette`, `VanPlate`, `VanBackButton` (Task 5); `FocusTabState` (`minutes`, `sheet`, `selectedPresetID`, `subjectPick`, `lastStarted`, `plainTimer`, `subjectID(preset:subjects:)`); `FocusSessionStore.StartRequest(preset:minutes:appSet:plainTimer:from:subject:)`; `FocusStores.start(_:intention:settings:)`; `FocusStartLines.couldntStart`; `SubjectStore.name(for:)`; `AppSetStore.set(id:)`.
- Produces: `ClockFace(setting: Binding<ClockSetting>)`, `ClockTimerView()`.

- [ ] **Step 1: The drawn clock**

`App/Features/Van/ClockFace.swift`:

```swift
import MapleCore
import SwiftUI

/// A slice of the face, from 12 clockwise.
nonisolated struct ClockSector: Shape {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        guard fraction > 0 else { return path }
        path.move(to: centre)
        path.addArc(center: centre, radius: min(rect.width, rect.height) / 2, startAngle: .degrees(-90),
                    endAngle: .degrees(-90 + 360 * min(1, fraction)), clockwise: false)
        path.closeSubpath()
        return path
    }
}

/// The clock that sets a session's length: a thick rim, a face set back inside it, hands that cast a shadow, and the
/// length as digits in the hub the hands start from (syrup van design §6.2).
struct ClockFace: View {
    @Binding var setting: ClockSetting

    @Environment(\.locale) private var locale

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let centre = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            ZStack {
                // The rim: an outline, the brass, a bright edge, and the shadow the rim throws on the face.
                Circle().fill(VanPalette.outline)
                Circle().fill(LinearGradient(colors: [VanPalette.goldLight, VanPalette.gold, VanPalette.copper],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    .padding(side * 0.014)
                Circle().strokeBorder(VanPalette.face.opacity(0.55), lineWidth: side * 0.012).padding(side * 0.03)
                Circle().fill(VanPalette.outline).padding(side * 0.085)
                Circle().fill(VanPalette.face).padding(side * 0.098)
                // Syrup colour, from the top to the long hand.
                ClockSector(fraction: setting.faceFill)
                    .fill(VanPalette.syrupLight.opacity(0.55))
                    .padding(side * 0.098)
                Circle()
                    .strokeBorder(
                        LinearGradient(colors: [VanPalette.outline.opacity(0.34), .clear], startPoint: .top, endPoint: .center),
                        lineWidth: side * 0.05
                    )
                    .padding(side * 0.098)
                ticks(side: side)
                drops(side: side)
                hand(length: side * 0.2, width: side * 0.042, angle: setting.hourAngle, side: side)
                hand(length: side * 0.32, width: side * 0.03, angle: setting.minuteAngle, side: side)
                // The hub, with the length in it.
                Circle().fill(VanPalette.outline).frame(width: side * 0.3, height: side * 0.3)
                Circle().fill(VanPalette.cream).frame(width: side * 0.272, height: side * 0.272)
                Text(setting.hubText)
                    .font(.system(size: side * 0.1, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(VanPalette.outline)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .frame(width: side * 0.24)
            }
            .frame(width: side, height: side)
            .position(centre)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let dx = value.location.x - centre.x, dy = value.location.y - centre.y
                        // A touch on the hub itself has no direction worth following.
                        guard (dx * dx + dy * dy).squareRoot() > side * 0.16 else { return }
                        setting.turn(toAngle: ClockSetting.angle(dx: dx, dy: dy))
                    }
            )
            .animation(.snappy(duration: 0.18), value: setting.minutes)
            .sensoryFeedback(.selection, trigger: setting.minutes)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Session length")
        .accessibilityValue(FocusTimeText.spokenLength(minutes: setting.minutes, locale: locale))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: setting.nudge(1)
            case .decrement: setting.nudge(-1)
            @unknown default: break
            }
        }
    }

    private func ticks(side: Double) -> some View {
        ForEach(0 ..< 60, id: \.self) { index in
            let major = index % 5 == 0
            Capsule()
                .fill(VanPalette.outline.opacity(major ? 1 : 0.45))
                .frame(width: side * (major ? 0.014 : 0.006), height: side * (major ? 0.05 : 0.024))
                .offset(y: -side * (major ? 0.355 : 0.368))
                .rotationEffect(.degrees(Double(index) * 6))
        }
    }

    /// Three drops under 12: one fills for each whole hour, so the length reads without the digits.
    private func drops(side: Double) -> some View {
        HStack(spacing: side * 0.022) {
            ForEach(1 ... 3, id: \.self) { hour in
                Image(systemName: setting.wholeHours >= hour ? "drop.fill" : "drop")
                    .font(.system(size: side * 0.05, weight: .bold))
                    .foregroundStyle(setting.wholeHours >= hour ? VanPalette.syrup : VanPalette.outline.opacity(0.4))
            }
        }
        .offset(y: -side * 0.24)
        .accessibilityHidden(true)
    }

    private func hand(length: Double, width: Double, angle: Double, side: Double) -> some View {
        Capsule()
            .fill(VanPalette.outline)
            .frame(width: width, height: length)
            .offset(y: -length / 2 - side * 0.1)
            .rotationEffect(.degrees(angle))
            .shadow(color: VanPalette.outline.opacity(0.28), radius: side * 0.012, x: side * 0.012, y: side * 0.018)
    }
}
```

- [ ] **Step 2: The timer screen**

`App/Features/Van/ClockTimerView.swift`:

```swift
import MapleCore
import MapleDesign
import MapleServices
import SwiftUI

/// The gauge, grown to fill the screen: choose the length, the subject and block mode, then start
/// (syrup van design §6.2 to §6.4). It stands where the Focus tab's start screen stood.
struct ClockTimerView: View {
    @Environment(\.focusStores) private var focusStores
    @Environment(FocusTabState.self) private var tab
    @Environment(FocusSessionStore.self) private var sessions
    @Environment(PresetStore.self) private var presets
    @Environment(AppSetStore.self) private var appSets
    @Environment(SubjectStore.self) private var subjects
    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router
    @AppStorage("van.blocksApps") private var wantsBlock = true
    @State private var setting = ClockSetting(minutes: 50)
    @State private var notice: String?

    private var base: FocusPreset? { presets.presets.first { $0.id == presets.lastUsedID } ?? presets.presets.first }
    private var canBlock: Bool { sessions.blocking.capability.canBlock && sessions.probe.isAllowed }

    var body: some View {
        let preset = VanTimer.preset(from: base)
        let appSet = preset.appSetID.flatMap { appSets.set(id: $0) }
        ZStack {
            VanPalette.sky.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    HStack {
                        VanBackButton(title: "Workshop") { router.selectedTab = .home }
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 12) {
                        stepButton("minus", label: "Five minutes less") { setting.nudge(-1) }
                        ClockFace(setting: $setting)
                            .frame(maxWidth: 420)
                        stepButton("plus", label: "Five minutes more") { setting.nudge(1) }
                    }
                    options(preset: preset, hasApps: appSet != nil)
                    if let notice {
                        Text(notice)
                            .font(.system(.footnote, design: .rounded).weight(.semibold))
                            .foregroundStyle(VanPalette.outline)
                            .multilineTextAlignment(.center)
                    }
                    Button { start(preset: preset, appSet: appSet) } label: {
                        Text(VanTimer.startTitle(minutes: setting.minutes))
                            .font(.system(.title3, design: .rounded).weight(.heavy))
                            .foregroundStyle(VanPalette.outline)
                            .frame(maxWidth: 280)
                            .modifier(VanPlate(fill: VanPalette.goldLight))
                    }
                    .buttonStyle(.plain)
                    .disabled(sessions.isStarting)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .onAppear { setting = ClockSetting(minutes: tab.minutes ?? base?.minutes ?? 50) }
        .onChange(of: setting.minutes) { _, minutes in tab.minutes = minutes }
    }

    private func options(preset: FocusPreset, hasApps: Bool) -> some View {
        VStack(spacing: 0) {
            Button { tab.selectedPresetID = preset.id; tab.sheet = .subject } label: {
                row("Subject", value: subjects.name(for: tab.subjectID(preset: preset.id, subjects: subjects)) ?? "None")
            }
            .buttonStyle(.plain)
            Divider().overlay(VanPalette.outline.opacity(0.25))
            Toggle(isOn: Binding(get: { canBlock && wantsBlock }, set: { wantsBlock = $0 })) {
                Text("Block mode")
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundStyle(VanPalette.outline)
            }
            .tint(VanPalette.syrup)
            .disabled(!canBlock)
            .padding(.vertical, 12)
            Button { tab.selectedPresetID = preset.id; tab.sheet = .blocking } label: {
                row(VanTimer.blockingLine(canBlock: canBlock, wantsBlock: wantsBlock, hasApps: hasApps), value: canBlock && wantsBlock ? "Change" : "")
            }
            .buttonStyle(.plain)
            .disabled(!(canBlock && wantsBlock))
        }
        .padding(.horizontal, 16)
        .background(VanPalette.cream, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(VanPalette.outline, lineWidth: 2.5))
        .frame(maxWidth: 460)
    }

    private func row(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(.body, design: .rounded).weight(.bold))
            Spacer(minLength: 8)
            Text(value)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .opacity(0.7)
            if !value.isEmpty { Image(systemName: "chevron.forward").font(.footnote.weight(.bold)).opacity(0.5) }
        }
        .foregroundStyle(VanPalette.outline)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func stepButton(_ image: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: image)
                .font(.system(.body, design: .rounded).weight(.heavy))
                .foregroundStyle(VanPalette.outline)
                .frame(width: 44, height: 44)
                .background(VanPalette.cream, in: Circle())
                .overlay(Circle().strokeBorder(VanPalette.outline, lineWidth: 2.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func start(preset: FocusPreset, appSet: AppSet?) {
        guard let focusStores, !sessions.isStarting else { return }
        let plain = !(canBlock && wantsBlock)
        // Block mode with no apps chosen: choosing them comes first.
        if !plain, appSet == nil {
            tab.selectedPresetID = preset.id
            tab.sheet = .blocking
            return
        }
        let request = FocusSessionStore.StartRequest(
            preset: preset, minutes: setting.minutes, appSet: plain ? nil : appSet, plainTimer: plain, from: .focusTab,
            subject: tab.subjectID(preset: preset.id, subjects: subjects)
        )
        notice = nil
        Task {
            switch await focusStores.start(request, intention: nil, settings: settings) {
            case .started(let id):
                tab.lastStarted = id
                tab.minutes = nil
                tab.subjectPick = nil
            case .alreadyRunning:
                break
            case .blockingFailed:
                notice = "Couldn't lock your apps. Turn block mode off to start a plain timer."
            case .ledgerUnavailable, .notRecorded:
                notice = FocusStartLines.couldntStart
            }
        }
    }
}
```

- [ ] **Step 3: Send the Focus tab's start routes to the clock**

In `App/Features/Focus/FocusView.swift`:
- add `@Environment(CollectionStore.self) private var collection` beside the other `@Environment` properties;
- replace the first four cases of `destination(_:now:)`:

```swift
        case .settling:
            Color.clear
        case .start, .needsScreenTime:
            // With the van, the clock stands where the start screen stood, and starts a plain timer when Maple can't
            // block (syrup van design §6.4).
            if collection.context.features.syrupVan {
                ClockTimerView()
            } else if route == .start {
                FocusStartView()
            } else {
                NeedsScreenTimeView()
            }
        case .minimised(let id):
            if collection.context.features.syrupVan {
                // A minimised session waits on the van's gauge (§6.5).
                Color.clear.onAppear { router.selectedTab = .home }
            } else {
                FocusStartView(minimised: id)
            }
```

- where `destination(route, now:)` is called, add this modifier to the result, so that closing a receipt goes home to the van and not to the clock:

```swift
                .onChange(of: route) { old, new in
                    guard collection.context.features.syrupVan, case .receipt = old, new == .start || new == .needsScreenTime else { return }
                    router.selectedTab = .home
                }
```

- [ ] **Step 4: Build**

Run: `SIMULATOR="iPhone 17" Scripts/build.sh 2>&1 | grep -E "error|warning: |BUILD"`
Expected: `** BUILD SUCCEEDED **` and only the `appintentsmetadataprocessor` line. If `route` isn't in scope where the `.onChange` goes, attach it one level up, on the view that computes `route`.

- [ ] **Step 5: Run, turn the clock, and look**

Launch with `-MapleDemoTab focus` and take screenshots:
1. The clock fills the width: a brass rim, a cream face set back, two hands, "0:50" in the hub, one empty-to-filled drop row, minus and plus either side, the options card, "Start · 50m".
2. Drag the long hand clockwise past 12: the hub goes 0:55, 1:00, 1:05 and the first drop fills; the phone ticks at each step.
3. Drag backwards to the limit: it stops at 0:20.
4. With VoiceOver on (or the Accessibility Inspector): the clock reads "Session length, 50 minutes, adjustable", and swiping up and down changes it by 5 minutes.
5. Tap "Workshop": the van's home tab returns.

- [ ] **Step 6: Largest text**

Launch with `-MapleDemoTab focus -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL`.
Expected: the options card and the Start button grow and the screen scrolls; the clock keeps its size; nothing overlaps.

- [ ] **Step 7: Start, end, and the running session at launch**

1. Launch with `-MapleDemoTab focus -MapleDemoScreenTime unavailable`: the Block mode switch is off and disabled, the line reads "Plain timer · apps aren't locked". Tap Start: today's running-session screen appears with "Focus" in its header.
2. Tap End early: one sheet, one breath, "Still want to end?" (Gentle's way out, with no hold and no emergency release). End the session: the receipt shows; tap Done: the van's home appears.
3. Launch with `-MapleDemoFocus running`: the app opens on the running session, not on the van.
4. Minimise the session: the van's home appears, the status line reads "Session running · … left", and "Open the van" returns to the session.

- [ ] **Step 8: Commit**

```bash
git add App
git commit -m "Syrup van: the drawn clock sets the length and starts the session"
```

---

### Task 7: Documents, the release check, and the whole suite

**Files:**
- Modify: `docs/debug-launch-arguments.md`, `docs/core-api.md`, `docs/decisions.md`, `docs/superpowers/specs/2026-11-26-syrup-van-design.md` (§12), `CLAUDE.md` (the "Product direction" bullet about a calm dark design)

- [ ] **Step 1: Write the documents**

`docs/debug-launch-arguments.md`: in the table, change the `-MapleDemoShip` row's values to `` `f1`, `m1`, `van` `` and its effect to say that `f1` and `m1` open the app as it was before the van (tree home, tab bar, start screen) and `van` opens today's releases with the van; with no argument the app ships with the van. Under the `-MapleDemoPresent` list add: `- **Van** (`App/Features/Van/VanSceneView.swift`, on the home tab): `van:workshop` opens inside the van.` Add one example paragraph: `-MapleDemoTab focus` shows the clock timer; `-MapleDemoTab home -MapleDemoPresent van:workshop` shows the workshop.

`docs/core-api.md`: add a section "The syrup van's screens" after "The syrup van's economy", saying:
- the switch is `collection.context.features.syrupVan`; off, nothing of the van is on screen;
- `VanSceneView` is Home's stage and owns the two cameras; `HomeView` still owns the sheets and covers;
- every layer of a view is drawn on one `VanCanvas`; a tap target is placed with `canvas.point(x, y, in: size)` using the drawing's own coordinates (`marks` in `Scripts/art/vanart/inside.py` for the workshop);
- the workshop's room is not a separate drawing: `inside.py` draws `van.workshop` under its own camera (`inside.CAMERA`, straight on from the front), with `van.rear_closed` in place of the open doors, so a piece added to `van.py` appears in both views; only the garden round the room is drawn in `inside.py`;
- the art is generated: `python3 -I Scripts/art/build_van_art.py` rewrites the image sets, and `Scripts/art/check-van-art.sh` fails when they are stale; never edit an SVG in the catalog by hand;
- the clock is `ClockSetting` (pure) drawn by `ClockFace`; a start goes through `VanTimer.preset(from:)`, which is always Gentle with no break;
- `workshop.collect(from:)` is called by `VanSceneView` after `loadHistory()`, at appearance and when the running session changes.

`docs/decisions.md`: a new entry at the top, "2026-11-26 — The syrup van: the scene and the clock timer (step 3)", recording: the van is home behind one switch and the old screens are kept; the tab bar is hidden, not removed, so the router and every request that names a tab keep working; the clock stands in the Focus tab's start route; a van session is always Gentle with no break, made by copying the member's last preset, because a start still needs a preset; the art is drawn in code and generated into the catalog; what step 3 leaves on today's screens (running, End early, receipt).

The spec's §12: mark step 3 as built, and name this plan.

`CLAUDE.md`: replace the bullet "Calm, restrained, dark design. Amber is for rewards only, text is sentence case, and nothing is noisy or "gamified". Follow the anti-vibecode checklist in spec §1." with: "The app's home is the syrup van (`docs/superpowers/specs/2026-11-26-syrup-van-design.md`): warm, hand-drawn, thick outlines. Screens the van hasn't replaced yet keep the calm dark design and the anti-vibecode checklist in spec §1. Text is sentence case everywhere."

- [ ] **Step 2: The whole suite, the build and the release check**

Run: `SIMULATOR="iPhone 17" Scripts/test.sh -collect-test-diagnostics never 2>&1 | grep -E "error:|Test run with|recorded an issue" | sort -u`
Expected: three `✔ Test run with … passed` lines.

Run: `SIMULATOR="iPhone 17" Scripts/build.sh 2>&1 | grep -c "warning: "`
Expected: `1` (the `appintentsmetadataprocessor` notice).

Run: `Scripts/check-release.sh | tail -1`
Expected: `Release build has no demo or preview code (Maple and MapleWidgets).`

Run: `Scripts/art/check-van-art.sh`
Expected: `The van's image sets match the generator.`

- [ ] **Step 3: Commit**

```bash
git add docs CLAUDE.md
git commit -m "Syrup van: documents for the scene and the clock timer"
```

---

## Self-review notes

- **Spec coverage.** §5.1 home (Task 5 step 3), §5.2 workshop (step 4), §5.3 entering (step 5 and `VanEntrance`), §6.1 the gauge (step 4), §6.2 the clock (Tasks 3 and 6), §6.3 options (Task 6 step 2, `VanTimer`), §6.4 starting (Task 6), §9 the tab bar (Task 5 step 6), §10 art as separate pieces (Task 1), §11 accessibility (labels, the adjustable clock, Reduce Motion in the entrance and the idle motion, text sizes). Not built here, on purpose: §5.4 decorating, §6.5 to §6.7, §7, §8, the bucket picture.
- **Names.** `ClockSetting`, `VanHomeModel`, `VanTimer`, `VanEntrance`, `VanCanvas`, `VanLayers`, `VanPalette`, `VanPlate`, `VanBackButton`, `VanHomeView`, `VanWorkshopView`, `VanSceneView`, `ClockSector`, `ClockFace`, `ClockTimerView` are each defined once and used with the same spelling.
- **One thing a reader may trip on.** The art task gives drawing code only where it changes structure (layers, view boxes). The drawings themselves are already in the repository and were checked by eye against the concept image; changing how they look is a matter of editing `Scripts/art/vanart/*.py`, rendering, and looking.
