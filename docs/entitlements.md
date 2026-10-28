# Entitlements & capabilities

Signing is driven by `Config/Signing.xcconfig`:

| `MAPLE_TIER` | Entitlements file | What it unlocks | Needs |
|---|---|---|---|
| `free` (current) | `Config/Entitlements/Maple-free.entitlements` | HealthKit, App Group | Any Apple ID (personal team) |
| `paid` | `Config/Entitlements/Maple-paid.entitlements` | + Family Controls, iCloud/CloudKit, Push, HealthKit background delivery | Apple Developer Program |

The Simulator needs no signing; it applies the entitlements of the selected tier automatically.

## HealthKit background delivery (checked 2026-10-10)

What Apple documents:
- [Supported capabilities (iOS)](https://developer.apple.com/help/account/reference/supported-capabilities-ios) ticks **HealthKit** for all three account types, including "Apple Developer" (a free Apple Account that has agreed to the developer agreement: a Personal Team). "HealthKit Estimate Recalibration" is ADP/ADEP only.
- Background delivery is not a row of its own there. It is the nested "Background Delivery" option of the HealthKit capability ([Configuring HealthKit access](https://developer.apple.com/documentation/xcode/configuring-healthkit-access)), which adds `com.apple.developer.healthkit.background-delivery` (iOS 15+; without it `enableBackgroundDelivery(for:frequency:)` observer queries don't run in the background).
- Nothing Apple publishes says whether a Personal Team's profile can carry that key. (A 2021 DTS forum answer says adding the HealthKit capability put it in the profile's allow-list, but that predates Xcode 13's separate checkbox and doesn't speak to free teams.)

So it is **not clearly allowed on a free team**, and Maple treats it as paid-only:
- The key is only in `Maple-paid.entitlements`.
- `MAPLE_HEALTH_BACKGROUND_DELIVERY` (`Config/Maple.xcconfig`: `NO` for `free`, `YES` for `paid`) is written to the Info.plist key `MapleHealthBackgroundDelivery`. `MapleApp` reads it, and `HealthSleepImporter` calls `enableBackgroundDelivery` only when it is `YES`.
- Free builds import Apple Health's sleep on every foreground, right after Apple's prompt, and through an `HKObserverQuery` while the app runs. Late Watch data is picked up on the next foreground (the ledger accepts upgrades for 72 hours).
- To try it on the free team: add the key to `Maple-free.entitlements`, set `MAPLE_HEALTH_BACKGROUND_DELIVERY_free = YES`, and build to a device. If Xcode can't create a provisioning profile, revert both.

## Identifiers
| Purpose | Identifier |
|---|---|
| App | `com.maanvikgupta.maple` |
| DeviceActivityMonitor extension (M3) | `com.maanvikgupta.maple.monitor` |
| DeviceActivityReport extension (M3) | `com.maanvikgupta.maple.report` |
| ShieldConfiguration extension (M3) | `com.maanvikgupta.maple.shield` |
| ShieldAction extension (M3) | `com.maanvikgupta.maple.shieldaction` |
| App Group | `group.com.maanvikgupta.maple` |
| iCloud container (M7) | `iCloud.com.maanvikgupta.maple` |

Confirm these before filing the Family Controls request; they're hard to change afterwards.

## Requests to file once on the paid program
1. **Family Controls (Distribution)**: one request per bundle ID above that uses Screen Time: the app, `.monitor`, `.report`, `.shield`, `.shieldaction`. Approval can take weeks; development builds work without it.
2. **Private Cloud Compute model** (optional, M5): managed entitlement; requires the App Store Small Business Program and under 2M first-time downloads.

## No approval needed
HealthKit (including background delivery, on the paid program), App Groups, iCloud/CloudKit, Push Notifications, In-App Purchase, Background Modes (audio). AlarmKit needs `NSAlarmKitUsageDescription`; confirm on device in M6 whether provisioning needs more.

## Free-account limits to remember
- Builds expire after 7 days: re-run from Xcode. Don't delete the app, or its data goes with it.
- 10 App IDs per 7 days and 3 apps per device. Screen Time extensions are only embedded in the `paid` tier so they don't use these up.
