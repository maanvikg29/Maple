# Entitlements & capabilities

Signing is driven by `Config/Signing.xcconfig`:

| `MAPLE_TIER` | Entitlements file | What it unlocks | Needs |
|---|---|---|---|
| `free` (current) | `Config/Entitlements/Maple-free.entitlements` | HealthKit, App Group | Any Apple ID (personal team) |
| `paid` | `Config/Entitlements/Maple-paid.entitlements` | + Family Controls, iCloud/CloudKit, Push | Apple Developer Program |

The Simulator needs no signing; it applies the entitlements of the selected tier automatically.

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
HealthKit, App Groups, iCloud/CloudKit, Push Notifications, In-App Purchase, Background Modes (audio). AlarmKit needs `NSAlarmKitUsageDescription`; confirm on device in M6 whether provisioning needs more.

## Free-account limits to remember
- Builds expire after 7 days: re-run from Xcode. Don't delete the app, or its data goes with it.
- 10 App IDs per 7 days and 3 apps per device. Screen Time extensions are only embedded in the `paid` tier so they don't use these up.
