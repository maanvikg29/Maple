# DEBUG launch arguments

DEBUG builds read these arguments, which `xcrun simctl launch <udid> com.maanvikgupta.maple <args…>` passes, so any screen state can be reached for screenshots without tapping through the app. Release builds ignore all of them. They arrive through the `UserDefaults` argument domain (`-Key value`).

| Argument | Values | Owner | Effect |
|---|---|---|---|
| `-MapleDemoTab` | `home`, `rest`, `herbarium` | App (`RootView`) | Opens on that tab. |
| `-MapleDemoSpecies` | `0`…`155` | Core (`DemoData`) | Opens with a deterministic demo collection of that many species, held in memory. The real collection file is never touched. |
| `-MapleDemoDays` | integer | Core | Tended days for the demo collection, which drive tree growth `g`. |
| `-MapleDemoWaiting` | integer | Core | Number of earned leaves still waiting to be revealed. |
| `-MapleDemoPhase` | `morning`, `day`, `evening`, `windDown`, `night` | Core (clock) | Freezes "now" at a time inside that phase of today's schedule. |
| `-MapleDemoSeason` | `spring`, `summer`, `autumn`, `winter` | Core (app wiring) | Overrides the season. |
| `-MapleDemoRarity` | `YES` | Core | Uses `PreviewLeafShareProvider` with consent on, so "% of members" values show. |
| `-MapleDemoFresh` | `YES` | Core | Opens with an empty collection, as on first run. |
| `-MapleDemoPresent` | see below | Each feature, in its own root view | Opens one sheet, cover or push on launch. |

`-MapleDemoPresent` values:
- **App-level** (`App/DemoPresenter.swift`, over any tab): `reveal` (cover), `onboarding` (cover; pair it with `-MapleDemoFresh YES`), `profile` (sheet), `winddown` (cover)
- **Home:** `tree`, `streak`, `leaf:<speciesID>`
- **Herbarium:** `leaf:<speciesID>`, `share:<speciesID>`, `rarity`, `filter`, `search`
- **Rest:** `schedule`

Feature-level values are checked only by the feature that owns them, on its own tab, so combine them with `-MapleDemoTab`.

Example: `xcrun simctl launch booted com.maanvikgupta.maple -MapleDemoSpecies 23 -MapleDemoDays 41 -MapleDemoWaiting 1 -MapleDemoPhase morning`
