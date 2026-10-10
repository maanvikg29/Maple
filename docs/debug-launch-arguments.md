# DEBUG launch arguments

DEBUG builds read these arguments, which `xcrun simctl launch <udid> com.maanvikgupta.maple <args…>` passes, so any screen state can be reached for screenshots without tapping through the app. Release builds ignore all of them. They arrive through the `UserDefaults` argument domain (`-Key value`).

| Argument | Values | Owner | Effect |
|---|---|---|---|
| `-MapleDemoTab` | `home`, `rest`, `herbarium` | App (`RootView`) | Opens on that tab. |
| `-MapleDemoSpecies` | `0`…`155` | Core (`DemoData`) | Opens with a deterministic demo collection of that many species (default 23 when only `-MapleDemoDays` or `-MapleDemoWaiting` is given), held in memory, with the standard schedule saved. The cheapest rungs come first, so the counters match the ladders; the Sugar maple is always there. `0` is an empty collection. The real collection file is never touched. |
| `-MapleDemoDays` | integer | Core | Tended days for the demo collection (default 41), which drive tree growth `g`. Unlock dates spread over about 1.6 × this many days, so pressed colourways mix seasons. |
| `-MapleDemoWaiting` | integer | Core | Number of earned leaves still waiting to be revealed: the newest ones, never the Sugar maple. They can be opened in morning, day and evening. |
| `-MapleDemoPhase` | `morning`, `day`, `evening`, `windDown`, `night` | Core (clock) | Freezes `\.mapleClock` at a time inside that phase of today's schedule: the wireframe moments where they fit (evening 1h 20m before wind-down, wind-down 38m before bed), otherwise mid-window. |
| `-MapleDemoSeason` | `spring`, `summer`, `autumn`, `winter` | Core (app wiring) | Overrides the season (`\.season` and the tree inputs). |
| `-MapleDemoRarity` | `YES` | Core | Uses `PreviewLeafShareProvider` (12,480 members, tier-correlated shares) with consent on, so "% of members" values show. |
| `-MapleDemoFresh` | `YES` | Core | Opens with an empty collection and no saved schedule, as on first run. Wins over `-MapleDemoSpecies`. |
| `-MapleDemoPermissions` | `none`, `health`, `all` | Core | Granted permissions: `health` is Apple Health plus a sleep tracker, `all` adds Screen Time. Demo collections default to `health`, other launches to `none`. Use `none` to see the "Needs Apple Health" states. |
| `-MapleDemoSchedule` | `HH:MM-HH:MM`, optionally `/minutes` (e.g. `00:30-08:30/60`) | Core (`DemoLaunchOptions`, added for Rest) | Replaces the saved sleep schedule (bedtime-wake, wind-down length; 45 minutes when left out), in memory. `-MapleDemoPhase` then freezes the clock inside that schedule's phase. Ignored with `-MapleDemoFresh`. |
| `-MapleDemoGoodnight` | `YES` | Rest (`WindDownView`) | Wind-down mode opens as if Goodnight had just been tapped: "Phone down at …", then black 10 seconds after launch. Pair it with `-MapleDemoPresent winddown`. |
| `-MapleDemoPresent` | see below | Each feature, in its own root view | Opens one sheet, cover or push on launch. |
| `-MapleDemoProfile` | `settings`, `privacy`, `rarity`, `about`, `design` | Profile (`ProfileView`) | With `-MapleDemoPresent profile`: opens the Profile sheet pushed to that page. `rarity` opens Privacy and then its "How rarity works" explainer sheet; `design` is the DEBUG design system screen. |
| `-MapleDemoDesignSection` | `colours`, `surfaces`, `type`, `controls`, `specimens`, `rarity`, `cells`, `trees`, `species` | Profile (`DesignSystemView`) | With `-MapleDemoProfile design`: scrolls the design system screen to that section once it opens. |
| `-MapleDemoScroll` | a category id (e.g. `steady_mornings`) or `dormant` | Herbarium | With `-MapleDemoTab herbarium`: scrolls the grid until that section's header is pinned at the top. |
| `-MapleDemoRevealAt` | seconds, e.g. `0.3`, `0.9`, `1.6`, `3` | Reveal (`RevealDemoOptions`) | Taps the first bud open on launch and freezes the ritual that many seconds after the tap, so mid-frames can be screenshotted. Also freezes the onboarding end's reveal with `-MapleDemoOnboardingStep reveal`. |
| `-MapleDemoRevealOpenAll` | seconds, e.g. `0.5`, `4` | Reveal | Opens the first leaf, taps "Open all" and freezes that many seconds into it (`0.5` the row mid-opening, `4` the list). Needs `-MapleDemoWaiting 2` or more. |
| `-MapleDemoRevealConsent` | `YES` | Reveal | Opens the first leaf and shows the rarity consent sheet over it. |
| `-MapleDemoRevealLeaf` | species id | Reveal | The waiting leaf `-MapleDemoPresent reveal` opens first (`RevealFlow(startingWith:)`); ignored when it isn't waiting. |
| `-MapleDemoReduceMotion` | `YES` | Reveal, Onboarding | The reveal and the onboarding end render as under Reduce Motion (0.6 s crossfade; "Open all" goes straight to the list). `simctl ui` has no Reduce Motion switch. |
| `-MapleDemoOnboardingStep` | `seed`, `sprout`, `reveal`, `placed` | Onboarding (`PlantYourMapleView`) | Starts the onboarding end past the schedule step, saving the default schedule (in memory): `seed` holds the neutral bud, `sprout` lets it turn amber, `reveal` opens the Sugar maple (freeze it with `-MapleDemoRevealAt`), `placed` shows the grafted seedling and stays there. Pair with `-MapleDemoFresh YES -MapleDemoPresent onboarding`. |

`-MapleDemoPresent` values:
- **App-level** (`App/DemoPresenter.swift`, over any tab): `reveal` (cover), `onboarding` (cover; pair it with `-MapleDemoFresh YES`), `profile` (sheet; add `-MapleDemoProfile` for a page inside it), `winddown` (cover)
- **Home:** `tree`, `streak`, `leaf:<speciesID>`
- **Herbarium:** `leaf:<speciesID>` (pushes leaf detail), `share:<speciesID>` (leaf detail, then the rendered share-card PNG at its point size), `rarity` (leaf detail of the rarest earned leaf, or the featured one, with the rarity explainer open), `filter`, `search` or `search:<query>` (the Search sheet, already searching)
- **Rest:** `schedule` (the schedule editor at `.medium`), `schedule:bedtime` and `schedule:wake` (the editor at `.large` with that time's wheel open)

Feature-level values are checked only by the feature that owns them, on its own tab, so combine them with `-MapleDemoTab`.

Any Core argument makes the launch a demo: every store (collection, schedule, rarity cache, settings) is held in memory, so nothing a demo does is ever saved. With only `-MapleDemoPhase`, `-MapleDemoSeason`, `-MapleDemoRarity`, `-MapleDemoPermissions` or `-MapleDemoSchedule`, the stores start from an in-memory copy of the member's own files. The wiring is `MapleStores.make(_:)` in MapleServices (settings: `AppSettings.launch()`). Any `-MapleDemo…` argument also keeps wind-down mode's log (`bedside.json`) in memory.

Rest example (a non-default schedule in wind-down): `xcrun simctl launch booted com.maanvikgupta.maple -MapleDemoTab rest -MapleDemoSpecies 23 -MapleDemoPhase windDown -MapleDemoSchedule 00:30-08:30/60`

The Reveal and Onboarding arguments act only on a demo launch (with at least one Core argument), so they never touch the member's files.

Example: `xcrun simctl launch booted com.maanvikgupta.maple -MapleDemoSpecies 23 -MapleDemoDays 41 -MapleDemoWaiting 1 -MapleDemoPhase morning`

Example (Privacy with consent on): `xcrun simctl launch booted com.maanvikgupta.maple -MapleDemoSpecies 23 -MapleDemoRarity YES -MapleDemoPresent profile -MapleDemoProfile privacy`

Reveal examples (the demo collection's newest leaves are the waiting ones): `-MapleDemoSpecies 23 -MapleDemoWaiting 3 -MapleDemoPhase morning -MapleDemoPresent reveal` opens three common leaves (short ritual, "Open all 3"); `-MapleDemoSpecies 80 -MapleDemoWaiting 1` makes the waiting leaf the legendary Smoothbark maple (full ritual); `-MapleDemoSpecies 40 -MapleDemoWaiting 1` an uncommon, approximate one.
