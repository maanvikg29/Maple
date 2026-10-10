# Maple — notes for Claude

Maple is an **iPhone-only** SwiftUI app (iOS 27 minimum, Swift 6 language mode, Xcode 27). It's a **focus app** in the spirit of Opal: people collect **maple leaves** (155 real species, each a milestone reward) that grow a personal maple tree. Never design for, build for or mention other Apple platforms; the Apple Watch appears only as a sleep data source.

## Product direction
- Leaves come mostly from **hours saved**: awake time spent in sessions that block the apps you chose (Focus sessions you start, scheduled Morning blocks, Bedtime's wind-down). Sleep is secondary. The Study/Focus tab and the new reward ladder are being designed; check `docs/superpowers/specs/` before building in that area.
- `docs/design/spec.md` is the binding design spec for everything already built (Home, Herbarium, reveal, Profile): its "Overrides" box and Decisions table win over anything below them. `docs/design/rewards.md` explains the reward rules.
- Sleep leaves come **only from Apple Health** (spec D9): no self-report, and a Goodnight tap never earns a leaf.
- Calm, restrained, dark design. Amber is for rewards only, text is sentence case, and nothing is noisy or "gamified". Follow the anti-vibecode checklist in spec §1.

## Layout
- `App/`: the app target, with one folder per feature under `App/Features/`. Synchronized folders: adding a Swift file doesn't touch `project.pbxproj`.
- `MapleKit/`: a local Swift package.
  - `MapleCore` is pure Foundation (no SwiftUI), `Sendable` and nonisolated; it must stay small enough for Screen Time extensions.
  - `MapleDesign` holds the tokens in `Tokens.swift` plus components, leaves and the tree.
  - `MapleServices` holds the stores and system services.
  - `MapleDesign`, `MapleServices` and the app are MainActor by default.
- `Config/`: xcconfigs and entitlements per tier (`free` or `paid`). Each developer's own signing goes in `Config/Signing.local.xcconfig`, which git ignores; never commit a Team ID.
- `docs/`:
  - `core-api.md`: how screens read stores, the clock, `NowState`, progress, rarity and schedule.
  - `debug-launch-arguments.md`: DEBUG `-MapleDemo…` arguments that open any state in the simulator.
  - `architecture.md`, `decisions.md`, `entitlements.md`.

## Build and test
- Build: `SIMULATOR="iPhone 17" Scripts/build.sh`.
- Run all tests: `SIMULATOR="iPhone 17" Scripts/test.sh`.
- Build output goes to `~/Library/Developer/Xcode/DerivedData/Maple-<hash>`, outside the repo. The repo may live in iCloud Drive, and build products there break codesign.
- Zero compiler warnings and Swift 6 strict concurrency are required.
- Tests use Swift Testing (`@Test`, `#expect`, `#require`). Write tests first for logic.
- Demo and mock code compiles only under `#if DEBUG`. Release builds use real data only.
- Check UI changes in the simulator with the DEBUG launch arguments, and look at the screenshots.

## Working together
- Two people work on this repo. Make one branch per task, named `<name>/<topic>`, and merge to `main` through a pull request. Pull before starting.
- Stay inside the area you're working on. Edits to shared files such as `MapleApp.swift`, `RootView.swift`, `Tokens.swift` and `Package.swift` should be small.
- Ask before pushing, merging or rewriting history.
