# Maple

A calm iPhone app for better sleep and healthier screen habits. Keep your bedtime, finish focus sessions and skip late-night scrolling to earn **maple leaves**, which grow your own seasonal tree.

## Run it
- **Simulator:** open `Maple.xcodeproj`, pick an iPhone simulator, press Run. Or from Terminal:
  - `Scripts/build.sh`: build for the iPhone 17 simulator (`SIMULATOR="iPhone Air" Scripts/build.sh` for another).
  - `Scripts/test.sh`: run all unit tests.
- **Your iPhone:**
  1. Add your Apple ID in Xcode → Settings → Accounts.
  2. Copy `Config/Signing.local.example.xcconfig` to `Config/Signing.local.xcconfig`. Git ignores this file, so each person keeps their own.
  3. Put your Team ID in it. If you aren't the owner, also set your own bundle ID and App Group there.
  4. Select your iPhone and press Run.

## Working together
1. Pull `main` before you start.
2. Make a branch for your task, named `<yourname>/<topic>`.
3. Commit small changes and push the branch.
4. Open a pull request. The other person reviews and merges it.
5. Both of you pull `main` again.

Work in separate areas where you can. New Swift files don't touch the Xcode project file, so adding them never causes conflicts. `CLAUDE.md` holds the project rules for anyone using Claude Code.

## Layout
| Path | What's there |
|---|---|
| `App/` | The iPhone app: `MapleApp`, `RootView`, one folder per feature under `Features/` |
| `MapleKit/` | Local Swift package: `MapleCore` (pure domain logic), `MapleDesign` (tokens + components), `MapleData` (SwiftData), `MapleServices` (system services) |
| `Config/` | xcconfigs, Info.plist additions, entitlements per signing tier |
| `docs/` | `architecture.md` (approved plan), `entitlements.md`, `decisions.md` |

All colours, spacing, type and motion live in `MapleKit/Sources/MapleDesign/Tokens.swift`. Settings → Developer → Design system shows them live.
