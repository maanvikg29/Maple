# Maple

A calm iPhone app for better sleep and healthier screen habits. Keep your bedtime, finish focus sessions and skip late-night scrolling to earn **maple leaves**, which grow your own seasonal tree.

## Run it
- **Simulator:** open `Maple.xcodeproj`, pick an iPhone simulator, press Run. Or from Terminal:
  - `Scripts/build.sh`: build for the iPhone 17 simulator (`SIMULATOR="iPhone Air" Scripts/build.sh` for another).
  - `Scripts/test.sh`: run all unit tests.
- **Your iPhone:** add your Apple ID in Xcode → Settings → Accounts, put your Team ID in `Config/Signing.xcconfig`, select your iPhone, press Run.

## Layout
| Path | What's there |
|---|---|
| `App/` | The iPhone app: `MapleApp`, `RootView`, one folder per feature under `Features/` |
| `MapleKit/` | Local Swift package: `MapleCore` (pure domain logic), `MapleDesign` (tokens + components), `MapleData` (SwiftData), `MapleServices` (system services) |
| `Config/` | xcconfigs, Info.plist additions, entitlements per signing tier |
| `docs/` | `architecture.md` (approved plan), `entitlements.md`, `decisions.md` |

All colours, spacing, type and motion live in `MapleKit/Sources/MapleDesign/Tokens.swift`. Settings → Developer → Design system shows them live.
