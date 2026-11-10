# Maple: Home, Tree and Herbarium final design spec

Status: binding for the next build. It replaces the M0 Today/Sleep/Focus/Grove/Insights screens and their GlowCard design system.
Sources: the user's visual spec, the Opal research, the M0 critique, the three proposals and both judge verdicts, the rewards architect's draft, and `MapleKit/Sources/MapleCore/Resources/species.json`. Facts checked in that file: 155 species; confidence 89 k, 55 i, 11 u; 24 evergreens; 78 with a common name; all 11 u species have no common name.

Example data in this document (species names, counts, times) only illustrates layout. Real values always come from `species.json`, `rewards.json` and the user's own data.

> **Overrides applied after synthesis (2026-10-10). These win over anything below.**
> 1. **Rarity backend is CloudKit** (product owner's decision; supersedes D14 and the §5.7 pipeline). Maple's CloudKit public database holds one counter record per species plus a member counter. An opted-in install increments the member counter once, and increments a species counter when it unlocks that species (on opt-in it backfills its existing leaves; on opt-out it decrements, best effort). Writes use optimistic-locking retries. Nothing else is stored: no per-user record, no health data. `share = count / members`, with a Wilson 95% interval feeding `MemberShareFormatter`. The 1,000-member threshold (D4), opt-in consent (D5) and all `MemberShare` states are unchanged. CloudKit needs the paid Developer Program, so until then the app ships `UnconfiguredLeafShareProvider` (`.notEnoughMembers(nil)`). The explainer copy drops the "randomly flips some of its answers" sentence.
> 2. **The category table in §5.1 is superseded by `MapleCore/Resources/rewards.json`** (the finalised reward table: 19 categories including `focus_weeks` and `reflection_weeks`, with the final ladders). Per-leaf rule text is the assignment's `unlock_text`. Category copy and behaviour metadata (short rule, earned line, definition, requirement, time of day, design pace, action) live in code as `RewardCategoryInfo`, keyed by category id, in the voice of the §5.1 table.
> 3. **Platform:** iPhone only. Ignore any mention of other devices in the inputs.
> 4. **Sleep leaves come only from Apple Health** (product owner's decision, with rewards.json's data sources and D9). Nights tracked, On-time bedtimes, Bedtime runs, Steady weeks, Seasons in rhythm and Steady mornings need Apple Health; Full nights also need asleep-stage data. The Goodnight tap is never a source: it records the phone-down time for wind-down and for "Morning, no Apple Health" (§3.4) only, so §5.1's "or your Goodnight tap" no longer applies. Without Apple Health these leaves show their "Needs Apple Health" states and are left out of next-leaf, buds, Almost there, pacing and Profile totals. When that leaves Home's next-leaf row with no candidate, the row shows its needs-permission variant: the cheapest such leaf (by design pace) as a neutral skeleton at 50% with "Needs Apple Health" on the right, and a "Turn on Apple Health" `TextLink` in place of the hairline. Every "Turn on Apple Health" first shows a calm `.medium` primer (one leaf, two sentences on what Maple reads and that it stays on the iPhone, "Continue", `TextLink` "Not now"); Continue shows Apple's Health sheet, and once it is closed Apple Health counts as connected (HealthKit never reveals read access).
> 5. **Focus-first (2026-10-11).** `docs/superpowers/specs/2026-10-11-focus-hours-saved-design.md` wins over this document where they disagree. Already in the build: the reward table is its 7 categories (§4); Home's next leaf is the next hours-saved rung, with no phase preference (§3.5 → its §4.5); the bedtime-run streak and the Streak sheet are gone (Home's header streak returns as the Focus streak in F1); the first leaf is "Plant your maple". Coming with F1 and F2: tabs Home · Focus · Herbarium (D10), §3.4's day and session states (its §6), and the Rest tab retired into Focus (§8.1 → its §5).

---

## Decisions this spec settles

Where the inputs disagreed, this spec decides as follows. Nothing below is left open.

| # | Topic | Decision | Overrides |
|---|---|---|---|
| D1 | Tree growth | **Two axes.** Branch structure grows with *tended days*: it changes daily, only ever grows, and never shrinks. *Species unlocked* decide which leaves the tree carries and the stage name (Seedling … Grand maple). | Rewards draft, where species count drives structure |
| D2 | Next-leaf bud on the tree | Neutral (`budNeutral`) and swells with progress. It turns amber only once the leaf is earned and waiting to be opened. | Rewards draft "amber bud" |
| D3 | u-confidence species | Stay where the rewards table puts them, on the legendary top rungs, because the reward model is settled. Everywhere they appear they are presented as **Uncharted**: a "≈ Uncharted" chip, a placeholder-drawing note, and the same label on share cards and in VoiceOver. All presentation keys off `confidence`, not category, so moving them later needs no UI change. | Judge request for a separate Uncharted path |
| D4 | Rarity sample threshold | No percentage until a week has **1,000 reports**. Below that, show progress toward it ("· 640 so far"). | Proposals' 500 |
| D5 | Rarity consent | **Opt-in.** Asked once, at the end of the first morning reveal. Nothing is sent before the user taps "Include my leaves". | Rewards draft "default-on" |
| D6 | Rarity formatting | One CI-aware formatter (§5.7). It never shows 0% or 100%, and shows honest bounds ("Under 1%") when the interval is wide. This replaces the separate small-owner-count floor. | All per-proposal formatters |
| D7 | Calendar-limited leaves | None. The settled reward model has no calendar windows, and evergreens sit on year-round consistency ladders. | P2/P3 seasonal paths |
| D8 | Reveal interaction | Tap to open, no hold. The full ritual plays for the first 3 reveals ever and always for uncommon, rare and legendary leaves; other reveals use a short ritual. "Open all" handles queues. Nothing is ever revealed in the wind-down or night phases. | P1 hold-to-open |
| D9 | Screen Time and Apple Health paths | If permission is missing, show a designed "Needs Screen Time" / "Needs Apple Health" state. There is no manual self-report fallback. These leaves are excluded from next-leaf, Almost there and pacing until permission is granted. | P2's open question |
| D10 | Tabs | Home · Rest · Herbarium. | M0's 5 tabs |
| D11 | Primary button | Moonlight gradient capsule with the spec's thin border and soft glow. It has a dimmed variant in the evening and wind-down, and there is none at night. | P1 solid #EEF2F8 |
| D12 | First leaf | The First-steps leaf ("Plant your maple") is revealed as the last step of onboarding, at any hour, like Opal's first gem. This is the only reveal that can happen at night, so Home always has at least 1 species. | — |
| D13 | Serif | New York italic for scientific names only. Sentence case everywhere, with no tracked caps anywhere, including the reveal. | P3 "TAP TO UNFURL" |
| D14 | Rarity backend | Cloudflare Worker with one Durable Object per ISO week (155 counters + total), behind an Oblivious HTTP relay, with App Attest and DeviceCheck. A nightly Cron Trigger writes `rarity.json` to R2 behind the CDN. The production client ships with `UnconfiguredLeafShareProvider` until that endpoint is live. | Rewards draft offered two options |

---

## 1. Design principles

1. **One hero object per screen, never boxed.** Home is the tree, Rest › Sleep is the moon dial, Rest › Focus is the timer ring, Herbarium is the specimens, the reveal is the bud. A hero never sits inside a card, border or fill.
2. **Black does the work; light is local.** Every screen sits on `#05070D`. Colour and glow come only from content: the tree's bloom, leaf blooms, the moon, and the amber reward glow. Containers never glow and never cast shadows. Navy belongs to the night sky, sheets and selected states, not to card fills.
3. **Amber means "you earned something", and nothing else.** The complete list of places amber may appear:
   - the streak glyph and count, and the streak sheet's numeral and run circles;
   - the waiting bud (on the tree, as the next-leaf-row glyph, and the reveal bud's glow);
   - the reveal bloom, before it crossfades to the leaf's colour;
   - the new-leaf halo on the tree (decays over 24h) and the unseen-leaf dot on tiles;
   - the Herbarium owned-count bar.

   Amber never appears on button fills, borders, labels or glyphs, on progress toward locked leaves, in charts, in body text, as a season tint, or in leaf colours.
4. **The hero sets the tint.** The season tint (§6.1) colours progress hairlines, the score strokes, the season word in the header, insight highlights and next-rung skeletons. It is the only accent outside amber and the leaves themselves.
5. **State, not description.** A feature appears only when it has real state. No placeholder or roadmap UI anywhere: no "coming soon", "Arrives in M1", "onboarding", "feature" or milestone codes. Leaves from categories that have not shipped are visible but labelled "Not earnable yet".
6. **One number, one line, one action.** Home's first screen is exactly: header, tree stage with its caption, one hero numeral with one caption, one next-leaf row, and at most one button.
7. **Honest numbers.**
   - "%" is used only for the share of members who own a leaf. Personal progress is always an amount ("3 nights", "1h 40m").
   - Estimates say "about".
   - Rarity values come only from the server, with a sufficient sample.
   - Approximate drawings (confidence i or u) always carry "≈".
8. **Nothing is ever taken away.** No leaf, rosette, bud or branch is ever removed, browned, drooped or greyed out. A rough week only makes the tree dimmer and stiller. Autumn particles are samaras (winged seeds), never leaves. Copy never blames: no "missed", "failed", "late", and no red.
9. **Sleepy motion; all the drama goes to the reveal.** Nothing moves faster than 0.6s except press feedback (0.2s). Ambient loops run at 4–20s periods. There are no springs with overshoot, no confetti, no bursts and no shakes. Under Reduce Motion every screen is a complete, still frame.
10. **One specimen grammar.** Every leaf larger than 40pt is drawn by `LeafView` from species data at its resting tilt, on a radial bloom of its own colour, above a contact-shadow ellipse. This applies in tiles, detail, reveal, share card and avatar. Locked leaves are vein-only skeletons of their real shape, never padlocks or grey copies. The flag polygon, emoji and the SF `leaf` symbol are banned.

### Anti-vibecode rules (PR checklist; every screen must pass)

1. Home's first screen has zero cards, zero bordered containers and zero list rows.
2. Exactly one numeral of 48pt or more on any screen. Every other number on Home's first screen is 15pt or smaller.
3. At most one bordered-and-glowing element per screen: either the primary capsule or the Level-2 share-card frame.
4. No outer glow or shadow on any card, tile or row. Shadows exist only as contact shadows under the tree and leaves.
5. No SF Symbol above a heading. No icon that restates its label. SF Symbols appear only inside system-style controls (§6.8).
6. No component template stacked more than twice vertically, grids excepted.
7. Home copy: every line fits on one line at default text size and is 7 words or fewer. No paragraphs on Home.
8. No system large titles. No greeting as a title ("Good morning", "Rest well").
9. Radii come only from the token set (20, 28, 40, capsule, circle), all continuous. Spacing comes only from the 4pt scale.
10. Spacing is never uniform. The hero gets air; grouped rows sit 12pt apart; groups sit 32pt apart.
11. Mock data and preview providers compile only under `#if DEBUG`.
12. Every no-data case uses its designed state (§3.4, §5.7). Never use "0" or "—" where a drawn state exists.
13. Grids have at most 3 columns.

---

## 2. Navigation

### 2.1 Tabs

The system floating Liquid Glass tab bar (`TabView` + `Tab`), in this order:

| Order | Label | Symbol | Root view | Notes |
|---|---|---|---|---|
| 1 | Home | custom template symbol `maple.tree` (a round-crowned maple on a short trunk, 1.5pt rounded stroke drawn to SF Symbols Regular) | `HomeView` in its own `NavigationStack` | Nav bar hidden; custom header |
| 2 | Rest | SF `moon` (outline, regular) | `RestView` in its own `NavigationStack` | Sleep and focus tools |
| 3 | Herbarium | custom template symbol `maple.herbarium` (a pressed 5-lobed leaf on a page, same stroke) | `HerbariumView` in its own `NavigationStack` | The 155-species collection |

Tab bar styling:
- `.tint(textPrimary)`. Unselected items use `textSecondary`.
- `.tabBarMinimizeBehavior(.onScrollDown)`.
- The bar must render darker than the primary capsule over the evening scene; this is verified by snapshot. If the default glass is brighter, apply a `#0B1426` tint at 50%.
- Under Reduce Transparency it becomes solid `surface2`.

### 2.2 Where every feature lives

A feature appears only from the release that ships it. Before that it is absent.

| Feature | Lives in | Entry point |
|---|---|---|
| Tree, collection count, today's number, next leaf, pending reveals | Home first screen | — |
| Full tree with tappable leaves | Tree view (full-screen cover) | Tap the tree |
| Streak (bedtime runs) | Home header → Streak sheet | Tap the streak |
| Profile, totals, featured leaf, Settings, Privacy, rarity consent toggle, About, Design System (DEBUG) | Profile sheet | Tap the avatar |
| Wellbeing score with a plain-language breakdown | Home below the fold → Score sheet | Scroll |
| Weekly insights | Home below the fold → Insights (push) | "All insights ›" |
| Bedtime schedule, wind-down mode, Goodnight, alarm | Rest › Sleep | Tab, or Home's evening CTA |
| Sleep sounds | Rest › Sleep → Sounds sheet | Row, or Home's night capsule |
| Wind-down apps and shield | Rest › Sleep row | — |
| Focus timer | Rest › Focus | Tab, or Home's day CTA |
| Morning check-in (mood and energy) | Check-in sheet | Home's morning CTA |
| Caffeine log | Rest › Sleep row "Caffeine curfew" | — |
| Wind-down ritual steps | Wind-down mode | — |
| Community challenges | Profile sheet row "Challenges" | — |
| 155 leaves, filters, search, detail, share | Herbarium | Tab, tree caption, next-leaf row |
| Leaf reveal | Full-screen cover | Home CTA, the waiting bud, a waiting tile, the focus summary |

### 2.3 Presentation rules

- **Push with zoom transition:** leaf detail (from a tile, next-leaf row, Almost-there card or Tree-view rosette), Insights.
- **Full-screen cover:** reveal, Tree view, wind-down mode, running focus session.
- **Sheets:** Profile (`.large`), Streak (`.medium`), Score breakdown (`.large`), Sounds (`.medium`), Filter (`.medium`), Search (`.large`), Rarity explainer (`.medium`), consent (`.medium`).
- Sheets use `presentationBackground(surface2)` and the system corner radius.

---

## 3. Home screen

### 3.1 Wireframe

iPhone 17, 402 × 874pt, evening phase, autumn, 23 species. Top safe area 62, bottom 34. Side margin 24. y values are top edges.

```
y=0   +----------------------------------------------------+
      | 9:41                            ( island )   ..l = |  status bar 0-62; the scene shows through
y=62  | Autumn . Sat 10 Oct              (moon) 12   (av)  |  HomeHeader 44pt
y=106 |         .        .            .          .         |  TreeStage 106-516 (410pt = 47%), no container
      |           .     _.-~*~~*~~*~~*~-._     .           |  stars only in evening and night
      |          .-~ * * * o * * * * * * ~-.               |  * leaf rosette (an earned species)
      |         ( * * * * * * * * * * * * o )              |  o closed bud (next 3 leaves)
      |          '-. * * \ * * | * * / * .-'               |  crown centroid ~(201, 300)
      |             '~-._  \   |   /  _.-~'                |  canopy bloom behind the crown
      |                     \ \ | / /                      |
      |                      \ \|/ /                       |
y=470 |       ___....----~~~~~ |||| ~~~~~----....___       |  ground crest; trunk base (201, 470)
y=484 |             Young maple . 23 of 155 >              |  TreeCaption 13pt, sits on the ground
y=516 |  :::::: scene fades to #05070D, y 460-540 ::::::   |
y=524 |                       1h 20m                       |  NowBlock numeral 64pt (line box 72)
y=600 |            until wind-down . bed 23:00             |  caption 15pt (line box 20)
y=636 | [leaf] Red maple                         3 nights  |  NextLeafRow 56pt
      | [32pt] ===================-----------              |  2pt progress hairline, season tint
y=704 |      (           Start wind-down            )      |  primary capsule 52 x 354
y=756 |                                                    |  30pt gap
y=786 |         (  Home  |  Rest  |  Herbarium  )          |  system floating tab bar (~62pt)
y=848 |                       ______                       |  home indicator
y=874 +----------------------------------------------------+

Below the fold (40pt after the last first-screen element; groups 32pt apart; 120pt bottom padding):

      | Score                              How it works >  |  ScoreBlock (only once the score ships)
      |                      72  ^ +3                      |  48pt numeral; trend in season tint
      |              /          |          \               |  1pt twig connectors, white 14%
      |     ( Sleep 81 )  ( Focus 64 )  ( Screen 70 )      |  104x40 capsules; stroke = progress
      | Last 7 days . updated 07:10                        |  13pt secondary
      | This week                          All insights >  |  WeekBlock (after 3 tracked nights)
      |          M    T    W    T    F    S    S           |  11pt initials
      |          *    *    o    *    *    *    .           |  10pt markers
      | In bed by 23:00 on 5 of 7 nights.                  |  17pt rounded semibold; value in tint
      | Your steadiest week since August.                  |  15pt secondary, only when true
```

Vertical rhythm:

| Item | Height | Gap after |
|---|---|---|
| Header | 44 | — |
| Stage | 410 | 8 |
| Numeral | 72 | 4 |
| Caption | 20 | 16 |
| Next-leaf row | 56 | 12 |
| Primary capsule | 52 | — |

Stage height = `min(410, max(320, availableHeight × 0.47))`. At larger text sizes the stage yields height (down to 150pt, `HeroFit`) so the numeral, caption, next-leaf row and capsule stay above the tab bar on the first screen; when even 150pt leaves no room, the capsule is pinned just above the tab bar and the rest scrolls under it. The sky shrinks with the stage, so its top edge comes into view under the header; `SkyBackdropExtension` continues it upward (the gradient's top colour with the morning and day light pools carried across), so no seam shows there.

### 3.2 Elements

**HomeHeader** (y 62–106, pinned with `safeAreaBar(edge: .top)`, `scrollEdgeEffectStyle(.soft, for: .top)`, no background)
- **Left:** "Autumn" in `contextEmphasis` (15 SF Rounded semibold) in the season tint, then " · Sat 10 Oct" in `callout` (15 SF Pro regular) `textSecondary`. VoiceOver: "Autumn, Saturday 10 October".
- **Right, streak button:** SF `moon.fill` 12pt plus the current bedtime-run count in 17 SF Rounded semibold monospacedDigit, both `reward`, 6pt apart, 44×44 hit area.
  - Hidden while the run is under 2.
  - Opens the Streak sheet. VoiceOver: "12-night bedtime run, button".
- **Right, avatar:** 12pt after the streak. A 32pt circle: `surface2` fill, 1pt ring of white at 14%, the featured leaf drawn at 20pt in its pressed colourway.
  - The featured leaf defaults to the most recently earned leaf until the user features one.
  - Opens the Profile sheet. VoiceOver: "Profile".
- No wordmark, greeting, large title or gear.

**TreeStage** (y 106–516; the scene layer runs y 0–560 behind the header). See §4.
- Tapping the tree opens Tree view.
- Tapping the waiting amber bud (44pt hit area, which takes priority) opens the reveal.

**TreeCaption** (centred on the ground, y 484–504, 44pt hit area)
- Text: stage name in `footnote` `textSecondary`, " · ", the count "23" in 13 SF Rounded semibold `textPrimary`, " of 155" `textSecondary`, then `chevron.right` 10pt semibold `textSecondary`.
- Tapping switches to the Herbarium tab, scrolled to the top.
- The count changes with `.contentTransition(.numericText())` using `gentle`.
- VoiceOver: "23 of 155 leaves, young maple. Opens the herbarium."

**NowBlock** (centred)
- **Numeral:** `StatNumber(.hero)`: 64pt SF Rounded semibold, tracking −1.5, monospacedDigit, `textPrimary`.
  - Duration units ("h", "m") are 32pt SF Rounded medium `textSecondary` on the same baseline ("1h 20m").
  - Clock times are all digits ("07:00").
  - `@ScaledMetric(relativeTo: .largeTitle)`, capped at 88.
  - Changes use `.contentTransition(.numericText())` with `gentle`.
- **Caption:** 4pt below. `callout` `textSecondary`, one line, 7 words or fewer.
- Content per state is in §3.4.
- VoiceOver reads the pair as one element with full units: "One hour twenty minutes until wind-down. Bed at 11 PM."

**NextLeafRow** (56pt, Level 0, 24pt margins)
- **Left:** a 32pt `LeafView` skeleton of the target species. Outline is 1pt in the season tint at 60%. Its pressed colourway fills upward from the petiole to the progress fraction, at 40% opacity.
- **12pt gap, then line 1:**
  - The name: common name in 15 SF Rounded semibold `textPrimary`. If there is no common name, the scientific name in 15 New York italic. For confidence i or u, append " ≈" in 13 `textSecondary`.
  - Right-aligned: the remainder in `footnote` monospacedDigit `textSecondary` (§3.6).
  - The name truncates (tail) first; the remainder never truncates.
- **Line 2, 8pt below:** `ProgressHairline` (2pt; track white 8%; fill season tint) from the text's leading edge to the trailing margin.
- Tapping pushes Leaf detail with a zoom from the 32pt leaf.
- VoiceOver: "Next leaf: Red maple. 11 of 14 on-time bedtimes, 3 to go."
- **Waiting variant:** a 32pt `BudGlyph` with a static amber glow, the text "A new leaf is waiting" or "2 new leaves are waiting" (15 SF Rounded semibold), no remainder and no bar. Tapping opens the reveal.

**Primary capsule** (`MoonlightButtonStyle`, §7)
- 52pt minimum height, growing with Dynamic Type. Width = screen − 48 (354).
- At most one, and absent in some states.
- Evening and wind-down use the `.dimmed` variant.

**ScoreBlock** (below the fold; only from the release that ships the wellbeing score)
- "Score" in `callout` `textSecondary`.
- `StatNumber(.score)` (48pt), then a 13pt ▲ or ▼ and "+3", both in the season tint.
- Three 1pt quadratic "twig" connectors (white 14%) from under the numeral to three 104×40 outline capsules: "Sleep 81", "Focus 64", "Screen 70" in 15 SF Rounded semibold.
  - Each capsule's 1.5pt stroke is trimmed to its sub-score fraction, in the season tint, over a white 10% track.
- Under the capsules: "Last 7 days · updated 07:10" (`footnote` secondary) on the left and "How it works ›" (`TextLink`) on the right.
- Tapping a capsule or the link opens the Score sheet (§8.5).

**WeekBlock** (below the fold; hidden until 3 tracked nights exist)
- Header row: "This week" (17 SF Rounded semibold) and "All insights ›" (`TextLink`), which pushes Insights.
- Seven 10pt night markers under 11pt weekday initials:
  - kept (on-time): filled season tint;
  - tracked but not on time: 1pt ring at white 20%;
  - tonight: season-tint ring at 60%;
  - future: white 8% dot.
- One insight sentence in 17 SF Rounded semibold, with the key value in the season tint. One optional supporting line in 15 secondary, shown only when the data supports it.
- Level 0: no card and no icon.

### 3.3 Phase resolver

`NowState.resolve(date:schedule:pending:held:counters:features:) -> NowState` is pure and snapshot-tested. Times come from the user's schedule (weekday and weekend sets, device time zone): wake **W**, wind-down start **D**, bedtime **B**.

| Phase | Window |
|---|---|
| Morning | W − 60m → W + 3h |
| Day | W + 3h → D − 2h (empty if negative) |
| Evening | D − 2h → D |
| Wind-down | D → B |
| Night | B → W − 60m |

- **Held vs pending.** Unlocks with a timestamp from the start of Evening until the next Morning start are *held* and become *pending* at Morning start. All other unlocks are pending at once.
- **Pending overlay.** Pending reveals change Home only in Morning, Day and Evening. They never surface in Wind-down or Night.
- **Phase changes.** The NowBlock and CTA crossfade over `gentle`; the sky interpolates over `drift` (3.2s). Under Reduce Motion both change instantly.

### 3.4 States

All states share the header, tree and caption. Only the scene light (§4.4), the NowBlock, the next-leaf row and the CTA change.

| State | Numeral | Caption | Next-leaf row | Action |
|---|---|---|---|---|
| **Morning**, with sleep data | Last night's sleep, "7h 12m" (Apple Health) | "asleep 23:08 · up 06:20" | Normal | None, unless pending (below) or check-in is due ("Check in", once mood check-ins ship) |
| Morning, no Apple Health | Goodnight time, "23:04" | "in bed · bedtime 23:00" | Normal | Same |
| Morning, no data for last night | Tonight's wind-down start as a clock time, "22:15" ("10:15 PM" in 12-hour locales), never a countdown | "wind-down tonight · bed 23:00" | Normal | Same |
| **Day**, focus shipped | Focus today, "1h 25m" (or "0m") | "focused today · 4h 10m this week" | Prefers day leaves (§3.5) | "Start focus · 25m". Starts the session at once and presents it full-screen. A long-press menu offers 15, 25, 45 and 60m. |
| Day, before focus ships | Countdown to D, "6h 20m" | "until wind-down · bed 23:00" | Normal | None |
| **Focus running** (any phase except Night) | Remaining, "18:42" (mm:ss, 1s timeline) | "left in this focus" | Normal | "Return to focus" |
| **Evening** | Countdown to D, "1h 20m", refreshed every minute | "until wind-down · bed 23:00" | Prefers "tonight counts" leaves | "Start wind-down" (dimmed). Opens wind-down mode; starting early is allowed. |
| **Wind-down** | Countdown to B, "38m" | "until bed · phone down at 23:00" | Same as evening | "Start wind-down", or "Return to wind-down" if the mode is active (dimmed) |
| **Night** | Wake time, "07:00" | "wake-up · your maple is resting" | Shown at 80% opacity | No primary. A 44pt `GlassCapsule` "Sleep sounds" once sounds ship. All Home text is at 80% opacity and below-the-fold content is hidden. |
| **Pending reveal** (overlay in Morning, Day, Evening) | Per phase | Per phase | Waiting variant | "Open your new leaf" / "Open 2 new leaves" (neutral; no amber in the button) |
| **Quiet** (vitality below 0.55) | No copy or layout change | | | The tree only (§4.8) |

The primary capsule disappears entirely when there is no action. Nothing replaces it.

**New user.** The first Home view comes right after onboarding: 0 tended days and 1 species, the First-steps leaf revealed at the end of onboarding (D12). A Home with 0 species cannot occur.

- **Tree:** Seedling. A 140pt sapling carrying 24 copies of the first species. Next to them hang the next 3 buds, which are neutral.
- **Header:** no streak.
- **Caption:** "Seedling · 1 of 155 ›".
- **NowBlock:** follows the phase.
- **Next-leaf row:** the cheapest reachable first rung (§3.5). In the evening this is the "Nights tracked" or "On-time bedtimes" first rung, with the remainder "Tonight" and no bar. In the day, once focus ships, it is the "Focus days" first rung with the remainder "25m focus", and the CTA reads "Start a 25-minute focus".
- **Below the fold:** absent. The scroll ends after the CTA.
- **First morning:** pending; "2 new leaves are waiting".

### 3.5 Next-leaf selection (`NextLeafPicker`, pure, unit-tested)

**Candidates**
- For each category: its lowest locked rung.
- The category must be *available*: shipped, and its required permission (Apple Health or Screen Time) granted.
- Candidates are never earned or held leaves.

**Estimate**
- `remaining = threshold − current`.
- `rate` = units gained over the last 14 days ÷ 14.
- If `rate == 0`, use `designPace` for the category from `rewards.json` (units per day for a committed user). This is what points a new user at a first rung rather than a far one.
- `estimatedDays = remaining / rate`.

**Choice**
1. A pinned leaf (pinned from leaf detail), if it is still locked and available.
2. Phase preference. In Evening, Wind-down and Night, prefer candidates whose category has `timeOfDay == .night`. In Day, prefer `.day`. In Morning, prefer `.morning`. A preferred candidate wins only if its estimate is 7 days or less; otherwise go to step 3.
3. Otherwise the global minimum `estimatedDays`.

**Ties:** higher fraction complete, then canonical category order (§5.1), then lower threshold.

**Other consumers**
- **Tree buds:** the top 3 by global estimate. The Home pick is always one of them, drawn as the largest bud.
- **Herbarium "Almost there":** same estimate, `estimatedDays ≤ 60`, up to 6, unavailable categories excluded.

### 3.6 Copy rules for Home

- Durations are written "7h 12m" or "38m". Clock times follow the locale (24-hour shown here).
- **Remainders by unit:**
  - "3 nights" / "1 night", "4 mornings", "2 weeks", "1 season", "5 days", "3 evenings", "2 challenges", "1h 40m".
  - When the remaining amount is 1 and tonight can complete it in Evening or Wind-down, it reads "Tonight".
  - When the remaining amount is 1 and today can complete it in Day, it reads "Today".
- Estimates always say "about" ("about 5 nights at your pace") and appear only in leaf detail.
- No exclamation marks. No "Great job". No blame words.

### 3.7 SwiftUI structure

```swift
NavigationStack {
  ScrollView {
    VStack(spacing: 0) {
      TreeStage(...).frame(height: stageHeight)          // includes TreeCaption
      NowBlock(state).padding(.top, 8)
      NextLeafRow(...).padding(.top, 16)
      if let action { PrimaryAction(action).padding(.top, 12) }
      BelowTheFold(...).padding(.top, 40)                // ScoreBlock, WeekBlock; hidden at Night
    }
    .padding(.bottom, 120)
  }
  .background(alignment: .top) { SkyBackdrop(phase:season:vitality:).frame(height: 560).ignoresSafeArea(edges: .top) }
  .safeAreaBar(edge: .top) { HomeHeader(...) }
  .scrollEdgeEffectStyle(.soft, for: .top)
  .toolbarVisibility(.hidden, for: .navigationBar)
}
```

- **Parallax:** `onScrollGeometryChange` moves the stage and backdrop by −0.4 × offset and fades the bloom to 0 by 300pt of scroll. Disabled under Reduce Motion.
- **Timelines:** a single `TimelineView(.everyMinute)` drives NowState. Focus running uses `.periodic(from:by: 1)` for the NowBlock only.

---

## 4. Maple tree hero

### 4.1 The growth model

The tree has two independent axes. Copy and VoiceOver state both: "grown over 41 days" and "23 of 155 leaves".

1. **Structure = tended days.**
   - A tended day is a local calendar day on which any category counter increased, excluding First steps and Community challenges.
   - `g = min(1, (tendedDays / 540)^0.6)`.
   - g is non-decreasing and grows visibly from day 1. Examples: day 1 = 0.023, day 30 = 0.18, day 90 = 0.34, day 180 = 0.52, day 365 = 0.79, day 540 = 1.0.
2. **Foliage = the collection.** Every earned species is on the tree as rosettes of its own real leaf. The stage *name* comes from species count:

| Stage | Species |
|---|---|
| Seedling | 0–4 |
| Sapling | 5–19 |
| Young maple | 20–49 |
| Spreading maple | 50–99 |
| Old maple | 100–154 |
| Grand maple | 155 |

### 4.2 Silhouette and construction

- **Habit:** an open-grown sugar maple. A short, stout trunk with a gentle S-curve forks low (at 0.28 × tree height) into 2–3 leaders (3 with probability 0.6, seeded). These form a broad, slightly asymmetric dome crown about 1.3 : 1 wide to tall when mature. Two small root flares sink into the ground.
- **Seed:** SplitMix64 seeded from the profile UUID. The silhouette is personal and stable across launches and devices.
- **Recursion:** split angles 22–38° (seeded jitter), child length × 0.74, width taper × 0.68, a +4° upward bend per segment, 12% seeded pruning, maximum depth 8.
- **Continuous emergence:** depths 1–3 exist at g = 0. Each later depth appears at a threshold and grows from length 0 to full over Δg = 0.10 with smoothstep:

| Depth | Appears at g |
|---|---|
| 4 | 0.05 |
| 5 | 0.18 |
| 6 | 0.34 |
| 7 | 0.52 |
| 8 | 0.72 |

- **Tips:** a segment endpoint becomes a tip once the segment is at least 50% grown. Existing segments only lengthen and thicken; their topology never changes. That is why slot assignments are permanent.
- **Bark:** horizontal gradient `bark` (`#2A3348` on the moonlit left to `#121826`). Thin tips lighten toward `#3A4663`. A 0.75pt `barkRim` (`#A9BEE3` at 25%) runs along the moon-facing edge of the trunk and depth 1–3 limbs. No outlines.
- **Fallback:** if the procedural skeleton fails visual review at any stage, ship hand-authored skeletons for the six stages, with the same slot and rosette system on top. Home does not ship until the tree beats a still render.

### 4.3 Size and placement (402 × 874)

| Property | Value |
|---|---|
| Trunk base | (201, 470), on the ground crest |
| Tree height H | lerp(140, 350, g); the crown top never goes above y 120 |
| Crown width W | lerp(110, 340, g); may bleed 8pt past the margins at g = 1 |
| Trunk base width | lerp(4, 22, g) |
| Crown centroid | about (201, 470 − 0.55H) |

The tree is never inside a container. The scene layer runs full-bleed from y 0 to 560 and dissolves into `#05070D` from y 460 to 540.

### 4.4 Lighting, bloom, sky and ground

Draw order: sky → stars → moon and moonlight → canopy bloom → ground and light pool → contact shadow → branches → rosettes → buds and halos → particles.

| Phase | Sky gradient | Light | Stars |
|---|---|---|---|
| Morning | `#0B1426` → `#111D35` at 55% → `#05070D` at y 560. Warm horizon wash `#3B2F3F` at 10% over y 380–480. | Pool `#F2E6D8` at 5% from the upper left. No moon. | 12 of 48, at 10% |
| Day | `#0B1426` → `#111D35` at 50% → `#05070D` | Cool pool `moonlight` at 6%, top centre | None |
| Evening | `#05070D` → `#0B1426` at 55% → `#05070D` | Crescent moon 12pt `#E9EEF7` at 55% at (322, 128), with a 60pt halo at 6%. Moonlight pool `#AFC3E8` at 7%, an ellipse from the moon toward the crown. | All 48, at 15–50% |
| Wind-down | As evening | As evening; tree brightness × 0.9 | As evening |
| Night | `#05070D` → `#080D19` | Moon as evening; pool at 5%; tree brightness × 0.75 | All 48 at 45%; 2 twinkle |

No other sky hues (no violet haze, no dawn rose beyond the 10% wash above).

- **Canopy bloom:**
  - A radial gradient centred on the crown centroid, radius 0.75 × W, blend `.plusLighter`.
  - Colour: the instance-count-weighted average of the visible leaf colours, with saturation clamped to 0.45.
  - Base opacity by phase: Morning 14%, Day 12%, Evening 14%, Wind-down 12%, Night 8%. Multiplied by vitality v (§4.8).
  - Hard maximum 18%.
- **Ground:**
  - A mound ellipse centred at (201, 560), 620 × 180, fill `ground` `#070B14`.
  - A 1pt rim along its crest: `#9DB4E6` at 14% in the centre, fading to 0 at the sides.
  - A light pool on the ground under the crown: a 260 × 40 ellipse in the bloom colour at 8%.
- **Contact shadow:** a 120 × 14 ellipse at (201, 472), black at 55%, blur 8.
- **Trophy:** at 155 of 155 (Grand maple), a faint ring of `moonlight` at 8%, radius W × 0.62, sits behind the crown.

### 4.5 The collection as foliage

**Instance budget.** Total leaves T never decreases, and each species always shows at least 3 copies:

```
T_species  = n ≤ 10 ? 24·n : max(240, 3·n)
T_capacity = round(24 + 456·g)
T          = max(3·n, min(T_species, T_capacity))
```

Instances are distributed `floor(T / n)` per species, with the remainder going to the earliest-earned species. The hard cap is 480.

**Rosettes**
- Instances are grouped into rosettes of 3–6 leaves, fanned within an 18pt radius, with petioles pointing back to the twig and seeded rotation of ±40° around the species' resting tilt.
- 70% of rosettes sit on the outer shell of the crown so it reads as a dome. Inner rosettes are darkened by 15%.
- Leaf size is lerp(18, 11, g) pt ± 15% (seeded).
- Below 14pt use `LeafView.Detail.fillOnly` (no outline or veins). From 14pt up use `.automatic`.

**Slots**
- At unlock, each species gets one **primary tip**, chosen in unlock order from the crown outward, alternating left and right. The primary tip never changes.
- Additional rosettes go to the nearest free tips (satellites). Satellites may be redistributed when n changes, but the total count never drops.
- If tips < n + 3, up to 3 species share a tip. The earliest keeps the twig end; later species attach 8–12pt back along the twig.
- The featured leaf takes the crown's top tip as an extra rosette.

**Buds:** the next 3 leaves (§3.5) hang at free tips as closed teardrop buds.
- Size 6 × 9pt, scaled 0.4 → 1.0 with progress.
- Colour `budNeutral` (`#C9D3E3` at 45%), with a 0.5pt rim at white 20%.
- The Home next leaf is the largest bud and has a faint season-tint halo (r 10, 12%).

**Waiting bud:** an earned-but-unopened leaf.
- Its bud sits at the species' future primary tip.
- `reward` core at 60% with a halo of r 18 at 25%, breathing ±15% over 4s (static at 60% under Reduce Motion).
- 44pt hit area. Opens the reveal.

**New-leaf halo:** after placement, the species' primary rosette carries a `reward` halo (r 16, 30%) that fades linearly to 0 over 24h.

What the tree looks like at each collection size (typical tended days in brackets):

| Species n (days) | g | Stage | Tree H × W | Leaves | Per species | Look |
|---|---|---|---|---|---|---|
| 0 (onboarding only) | 0 | Seed | 44pt sprout | 0 | — | Two neutral cotyledons (`#6E8F6A` at 70%) and one closed neutral bud. Seen only during onboarding, before the first reveal. |
| 1 (day 0) | 0.00 | Seedling | 140 × 110 | 24 | 24 | A small sapling dressed in one species, in 5 rosettes of 18pt leaves, with 3 buds. Reads as intentional, not bare. |
| 10 (~day 8) | 0.08 | Sapling | 159 × 128 | 60 | 6 | A young, varied sapling. Each species is one or two rosettes, with leaves about 17pt. |
| 50 (~day 150) | 0.46 | Spreading maple | 237 × 216 | 236 | 4–5 | A full dome of mixed shapes. Autumn shows a variegated crimson, scarlet, orange and gold crown. Leaves about 15pt. |
| 155 (~day 600) | 1.00 | Grand maple | 350 × 340 | 465 | 3 | A dense, calm crown of 155 species at 11pt (fill only), plus the moon-ring trophy. |

### 4.6 How daily healthy behaviour shows

Something on the tree changes on every good day, even when no leaf drops:
1. **Structure** grows with each tended day. The change is re-rendered when Home next appears and eases in over `graft` (1.6s).
2. **Buds** swell with progress toward their leaves.
3. **Vitality** (light and motion) responds to the last 7 nights (§4.8).

On a day when the tree grew but no leaf dropped, VoiceOver's value includes "Grew today."

### 4.7 Seasons

The season comes from the real date and the user's hemisphere (existing `Season(for:hemisphere:)`). All on-tree colours are desaturated 10% and multiplied by the phase brightness.

| Season | Deciduous leaves | Evergreens (24) | Extras | Particle system (one at a time) |
|---|---|---|---|---|
| Spring | Species summer green mixed 25% toward `#D8E8B0` | Own green | First 21 days: 2pt `#B3312B` flower dots at 70% on 20% of tips (seeded) | 6 pollen motes `#E8F0C0` at 12%, drifting up over 20s |
| Summer | Species summer green, display lift +6% lightness | Own green | — | Evening and night only: 4 fireflies `#D9E6A8` at 35%, 2pt, blur 2, 3s fades |
| Autumn | Each species turns from summer green to its autumn code (R `#B3312B`, S `#D2462A`, O `#D9782B`, Y `#D1A020`) on its own seeded day within the first 21 days of autumn | G `#3F6D3B` +6% lift | — | One samara (6pt winged seed, `#B89A72` at 55%) every 30–45s, spinning 360° per 0.8s, falling 14s and fading at the ground |
| Winter | Autumn colour mixed 60% toward `#C9DCE8`, with a 0.75pt white rim at 40% when the leaf is 14pt or larger. Phased in on seeded days over the first 10 days. Leaves never fall. | Deep own green with a 0.75pt white rim at 25%. Evergreens visibly stand out. | 1pt white line at 35% along the top of depth 1–3 limbs (snow) | 14 snow motes, 1–2pt, white at 35%, falling over 18s |

### 4.8 Quiet state after bad nights

Vitality is computed once a day from the last 7 nights:

```
score = 0.5·onTimeShare + 0.25·fullNightShare + 0.25·scrollFreeShare
v     = 0.4 + 0.6·score              (v ∈ [0.4, 1.0])
```

If a category is unavailable, its weight is redistributed proportionally across the others.

| Property | Mapping |
|---|---|
| Bloom opacity | × v |
| Sway amplitude | × v |
| Leaf saturation | × (0.8 + 0.2·(v − 0.4)/0.6) |
| Leaf scale | 0.94 → 1.00 across v |
| Particles | Only when v ≥ 0.6 |
| Star twinkle | Only when v ≥ 0.6 |

- Changes interpolate over `drift` (3.2s) the next time Home appears.
- **Quiet** means v < 0.55. No Home copy changes; VoiceOver adds "Resting."
- Nothing is removed, drooped, browned or greyed.

### 4.9 Idle motion, performance and Reduce Motion

**Motion**
- **Sway:** an 8s sine loop (10s in the Night phase), rotated about the trunk base with layered amplitudes:
  - trunk and depth 1–3: ±0.6°;
  - depth 4–6: ±1.0° with a 0.8s phase lag;
  - rosette layer: ±1.4° with a 1.2s lag.
- **Flutter:** ±3° on seeded 5–7s periods, for at most the 40 rosettes nearest the crown front. Off when there are more than 60 rosettes.
- **Bloom:** breathes ±15% of its opacity over 10s.
- **Stars:** twinkle on 6–12s periods (evening and night).

**Rendering**
- When data changes (g, species set, season, featured leaf, vitality, phase), build a `TreeSkeleton` and rasterise three layers with `ImageRenderer` at screen scale:
  - L0: trunk and depth 1–3;
  - L1: depth 4–8;
  - L2: rosettes.
- Each frame, compose the layers with rotation about the trunk base. Flutter rosettes and particles draw in a small `Canvas` overlay. The bloom is a `RadialGradient` view.
- `TimelineView(.animation(minimumInterval: 1/30, paused: …))` is paused when the stage is off-screen (`onScrollVisibilityChange`), when the scene phase is not active, under Low Power Mode, or under Reduce Motion.
- Night phase: after 60s without interaction the tree freezes to a still frame.
- Target under 4ms per frame on iPhone 15-class hardware, measured in Instruments before the Home ship gate.

**Reduce Motion:** one still frame at sway phase 0, with no flutter, twinkle or particles and a static bloom at its mean. Data changes, such as a new rosette or growth, crossfade over 0.6s.

### 4.10 Interaction

- **Tap the tree** (anywhere outside the waiting bud): Tree view (§8.4), a full-screen cover with a zoom transition, where each rosette is tappable.
- **Tap the waiting bud:** the reveal.
- Rosettes are not individually tappable on Home. They are too small for reliable 44pt targets.

### 4.11 VoiceOver

The tree is one element (`accessibilityElement(children: .ignore)`, trait `.isButton`).
- **Label:** "Your maple. Young maple, 23 of 155 leaves, grown over 41 days."
- **Value:** "Newest: Red maple. Next leaf: Paperbark maple, 9 of 14 on-time bedtimes." It also adds, when they apply, "A new leaf is waiting.", "Grew today." and "Resting."
- **Hint:** "Opens your maple full screen."
- **Custom actions:** "Open new leaf" (when one is waiting), "Show newest leaf", "Show next leaf", "Open herbarium".
- Dynamic Type scales the labels around the tree, never the drawing.

---

## 5. Leaf collection

### 5.1 The reward model as the UI presents it

Every one of the 155 species is a permanent reward on exactly one (category, threshold) rung, taken from the rewards architect's table: 18 categories. A leaf unlocks once and is never lost.

`rewards.json` (next to `species.json`) holds:
- **Per leaf:** `speciesID`, `category`, `threshold`, `tier`.
- **Per category:** `name`, `unit`, `ruleTemplate`, `shortTemplate`, `earnedTemplate`, `definition`, `availableFrom`, `requires`, `timeOfDay`, `designPace`, `action`.

The UI never hard-codes rule copy; it reads these fields. Milestone codes (`availableFrom`) exist only in data and are never displayed.

The initial category copy is below. Canonical order is top to bottom; Herbarium sections follow it.

| Category | Ladder | Locked rule (`{n}`) | Tile short rule | Definition (shown in detail; the engine must match it) | Requires | Detail action |
|---|---|---|---|---|---|---|
| First steps | 1 | Plant your maple | Setup | Finish setting up Maple. | — | — |
| Nights tracked | 1…540 | Track {n} nights | {n} nights | A night counts when Maple knows your bedtime and wake time, from Apple Health or your Goodnight tap. | — | — |
| On-time bedtimes | 1…470 | Be in bed on time {n} nights | {n} on time | On time means in bed no later than 15 minutes after your bedtime, from your Goodnight tap or Apple Health. | — | Start wind-down |
| Bedtime runs | 3…60 | Keep bedtime {n} nights in a row | {n}-night run | Your best run counts. One missed night in any 7 doesn't break a run. | — | Start wind-down |
| Full nights | 7…360 | Sleep a full night {n} times | {n} full nights | Asleep for at least your sleep goal (7h unless you change it), from Apple Health. | Apple Health | — |
| Steady weeks | 1…72 | Have {n} steady weeks | {n} weeks | A steady week, Monday to Sunday, has 5 or more on-time nights. | — | — |
| Seasons in rhythm | 1…6 | Stay in rhythm through {n} seasons | {n} seasons | A season counts when 8 of its 13 weeks are steady weeks. | — | — |
| Steady mornings | 5…400 | Wake on time {n} mornings | {n} mornings | Awake within 30 minutes of your wake time, from Apple Health. | Apple Health | — |
| Focus hours | 2…320 | Focus for {n} hours in total | {n}h focus | Every minute in a focus session counts, even if you end it early. | — | Start focus |
| Focus days | 1…300 | Focus on {n} days | {n} days | A focus day has at least 25 minutes of focus. | — | Start focus |
| Sound nights | 3…190 | Fall asleep to sounds {n} nights | {n} nights | A sleep sound plays for at least 10 minutes after your Goodnight. | — | Sleep sounds |
| Wind-down rituals | 5…220 | Finish {n} wind-down rituals | {n} rituals | Every step of your ritual is done before bedtime. | — | Start wind-down |
| Scroll-free wind-downs | 3…340 | Wind down without scrolling {n} times | {n} calm evenings | Under 5 minutes in your wind-down apps between wind-down and bedtime. | Screen Time | Start wind-down |
| Shield nights | 7…290 | Keep the night shield up {n} nights | {n} shield nights | Your wind-down apps stay shielded from wind-down to wake, with no unblocks. | Screen Time | — |
| Phone-free mornings | 5…260 | Have {n} phone-free mornings | {n} mornings | Under 2 minutes on your phone in the first 30 minutes after your wake time. | Screen Time | — |
| Mood check-ins | 10…260 | Check in on {n} days | {n} check-ins | A check-in is the two-tap morning note on mood and energy. | — | Check in |
| Caffeine curfew | 10…180 | Keep your caffeine curfew {n} days | {n} days | No caffeine logged after your curfew (8 hours before bedtime unless you change it). | — | — |
| Community challenges | 1…12 | Finish {n} community challenges | {n} challenges | A challenge counts when you finish your part before it ends. | — | — |

**Earned line template:** "For {n} on-time bedtimes", "For a {n}-night run", "For planting your maple", and so on.

**Tiers** (design rarity from the rewards table) are First steps, Common, Uncommon, Rare and Legendary. They are shown as a neutral chip, never coloured and never ranked against other people.

### 5.2 Leaf states and labelling

| State | Meaning | Visual (tile) |
|---|---|---|
| Earned | Unlocked and revealed | Level-1 tile, own-colour bloom, specimen in the pressed colourway |
| Waiting | Unlocked, not yet revealed | 48pt `BudGlyph` with amber glow; meta "Waiting"; tap opens the reveal (at night: "Opens in the morning") |
| Next | The next 3 locked rungs of an available category | No fill; skeleton in season tint with petiole-up progress fill; amount and bar |
| Locked | Further rungs of an available category | No fill; neutral skeleton; short rule |
| Needs permission | Category shipped but Apple Health or Screen Time not granted | Neutral skeleton at 50% opacity; meta "Needs Screen Time" / "Needs Apple Health" |
| Dormant | Category not shipped yet | Neutral skeleton at 35% opacity; meta "Not earnable yet" |

**Approximate labelling** applies identically everywhere for confidence `i` and `u`:

| Surface | Confidence i | Confidence u |
|---|---|---|
| Tiles, next-leaf row, Almost-there cards | "≈" mark | "≈" mark |
| Detail, reveal, share card chip | "≈ Approximate drawing" | "≈ Uncharted" |
| Detail Accuracy row | "Approximate. Drawn from the typical leaf of its series; this species is little studied." | "Uncharted. Only its native range is confirmed; this drawing is a placeholder." |
| VoiceOver | "Approximate drawing." | "Uncharted, placeholder drawing." |

**Pressed colourway** is the season the leaf was earned in, and it is permanent:

| Season earned | Pressed colourway |
|---|---|
| Spring | Spring green |
| Summer | Summer green |
| Autumn | Autumn colour |
| Winter | Frost (deciduous only) |

Evergreens are always pressed in their green. On the tree, leaves always follow the *current* season (§4.7).

**One count rule:** "N of 155" counts opened (placed) leaves only, on every surface (Home's caption, Tree view, the Herbarium's count, owned bar, "Earned" chip and section counts, Profile, VoiceOver); waiting leaves show as buds and may be mentioned apart ("1 waiting") but never add to N (`LeafCount` in MapleCore).

### 5.3 Herbarium layout

Background `#05070D` with a season-tint bloom at 6% (r 300, centred at (201, 40)). Nav bar hidden; margins 16.

```
y=0   +----------------------------------------------------+
y=62  | Herbarium                          (srch) (fltr)   |  28pt title; 36pt glass circles, 8pt apart
y=114 | 23 of 155                                          |  34pt '23' + 17pt ' of 155'
y=164 | ==========---------------------------------------  |  3pt owned bar: amber on white 8%
y=176 | Your rarest: Amami maple . Under 1%                |  13pt; only in the value state
y=212 | Almost there                                       |  20pt section title
y=244 | [ skel ] [ skel ] [ skel ] [ sk                    |  136x170 cards, 12pt apart, h-scroll
      | Red map. Paperb.  Trident  Nor                     |  13pt name
      | 3 nights 2h 10m   4 nights 6 m                     |  12pt remainder + 2pt tint bar
y=438 | (All 155)(Earned 23)(Locked 132)        (Group v)  |  32pt chips + glass menu
y=486 | On-time bedtimes                          6 of 15  |  pinned header: 20pt + 15pt count
      | In bed within 15 minutes of your bedtime.          |  13pt definition
      | .--------. .--------. .--------.                   |  3 cols, 10pt gutters
      | | (leaf) | | (leaf) | | (leaf) |                   |  earned: L1 tile + own-colour bloom
      | |Sugar m.| |Red map.| |Field m.|                   |
      | |38% hav.| |22% hav.| | 4 Oct  |                   |
      | '--------' '--------' '--------'                   |
      |   (skel)     (skel)     (skel)                     |  next 3: no fill, tint skeleton
      | Paperbark   Trident    Norway                      |    filling from the petiole
      | 9 of 14 ==  3 of 30 =  0 of 45                     |  amount + 2pt bar
      |                    Show 9 more                     |  44pt text row
y=874 +----------------------------------------------------+
```

1. **Header (y 62–106):**
   - "Herbarium" in `screenTitle`.
   - On the right, `IconCircle`s `magnifyingglass` (search sheet) and `line.3.horizontal.decrease` (filter sheet). The filter circle shows the active filter count as a 16pt `surface2` badge.
2. **Count:**
   - "23" in `StatNumber(.stat)` (34pt) plus " of 155" in 17 `textSecondary`.
   - A 3pt full-width bar: `reward` fill on a white 8% track.
   - "Your rarest: {name} · {formatted}" in `footnote` secondary. Shown only when at least one earned leaf has a value-state share.
3. **Almost there:**
   - Up to 6 `AlmostThereCard`s sorted by estimate (§3.5). Hidden if fewer than 2 candidates.
   - Each card is 136 × 170, Level 1, radius 20, with a season-tint top spotlight (radial, 8%, r 120, clipped). It holds:
     - a 72pt skeleton with a petiole-up progress fill (pressed colourway at 40%);
     - the name, 13 SF Rounded semibold (New York italic if scientific), with "≈" for i/u;
     - a 2pt tint bar, inset 14;
     - the remainder, e.g. "3 nights to go", 12pt secondary.
   - Tap pushes detail with zoom.
4. **Controls:**
   - `Chip`s: "All 155", "Earned 23", "Locked 132".
   - A `GlassCapsule` menu "Group" holding:
     - Group by: Category (default), Region, Autumn colour, Leaf form, Tier.
     - Sort: Next to earn (default), Rarest first, Newest first, A–Z.
5. **Sections:**
   - **Pinned headers:** `#05070D` at 92% with `ultraThinMaterial` and a white 6% hairline below. They show the name in `sectionTitle`, "6 of 15" in 15 secondary on the right, and the category definition in `footnote` secondary.
   - **Permission:** if the category needs a permission that is missing, the header adds "Needs Screen Time" (13 secondary) and a 32pt `GlassCapsule` "Turn on", which opens the permission primer.
   - **Collapsing:** each section shows its earned and waiting leaves, then its next 3 locked rungs, then a "Show 9 more" text row (15 medium secondary, 44pt). Expansion is remembered for the session. Filters, search and the Locked chip show everything.
   - **Dormant section:** all unshipped categories collapse into one final section titled "Dormant", with "12 leaves" on the right and "These can't be earned in Maple yet." as the definition. It shows the first 6, then "Show all".
   - **Order within a section:** rung order. Earned rungs are always the lowest, so earned leaves come first.
6. **Grid:** 3 columns, 10pt gutters, cells about 116.7 × 156. 24pt between sections; 12pt from a header to its grid.

### 5.4 Grouping, sorting, filters, search

- **Group by Region:** EA East Asia, HM Himalaya, SEA Southeast Asia, WA West & Central Asia, EU Europe, AF North Africa, NA North America, CA Mexico & Central America. A species appears under each of its regions. Headers show "4 of 13".
- **Group by Autumn colour:** Crimson, Scarlet, Orange, Gold, Stays green. Each header has a 10pt colour dot.
- **Group by Leaf form:** Palmate, Unlobed, Three leaflets, Pinnate, Palmately compound.
- **Group by Tier:** First steps → Legendary.
- **Sort "Rarest first":** uses value-state shares only. Every tile's meta shows the share; tiles without one sort last with "No rarity yet".
- **Filter sheet** (`.medium`):
  - region chips;
  - autumn-colour dots;
  - leaf-form chips;
  - toggles "Evergreen only", "Approximate drawings only", "Earnable now only".
  - A "Reset" text button.
- **Search sheet** (its own `NavigationStack` with `.searchable`): matches common name, scientific name, series and range words. Results appear as tiles in the same grid.

### 5.5 Cell (LeafCell)

- Leaf well 116 × 100, with the leaf at 64pt. Name at y 104; meta at y 124.
- **Name:** 13 SF Rounded semibold `textPrimary`, one line, `minimumScaleFactor(0.85)`. Unnamed species use 13 New York italic. Locked cells use `textSecondary`.
- **Meta:** 12pt `tileMeta` `textSecondary`, monospacedDigit.
- **Corners:** "≈" at 11pt in the top-left (inset 10) for i/u. A 6pt `reward` dot in the top-right (inset 10) for earned leaves not yet seen.

| Variant | Container | Leaf | Meta |
|---|---|---|---|
| Earned | Level 1 (`surface1`, radius 20, top-lit hairline) with a clipped radial bloom of the pressed colour at 18%, r 70 | `SpecimenView` 64pt, pressed colourway, contact shadow 40 × 5 | "38% have it" (value state) or the pressed date "4 Oct" |
| Waiting | Level 1 | `BudGlyph` 48pt with amber glow | "Waiting" |
| Next | None | Skeleton: outline 1pt season tint at 60%, veins 0.75pt white 15%, progress fill at 40% | "9 of 14" plus a 2pt × 56pt tint bar |
| Locked | None | Skeleton: outline 1pt `skeletonStroke`, veins `skeletonVein` | Short rule, "60 on time" |
| Needs permission | None | Locked skeleton at 50% opacity | "Needs Screen Time" / "Needs Apple Health" |
| Dormant | None | Locked skeleton at 35% opacity | "Not earnable yet" |

- Press feedback: scale 0.98 and opacity 0.9 over `press`.
- Detail pushes with `.matchedTransitionSource(id: species.id, in: ns)`.

### 5.6 Leaf detail (`LeafDetailView`)

Pushed with `.navigationTransition(.zoom(sourceID:in:))`, which becomes an opacity transition under Reduce Motion. Background `#05070D`. Scrolls.

```
y=62  | (<)                                       (share)  |  IconCircles; share for earned leaves only
y=106 |                       bloom                        |  SpecimenStage 300pt
      |                     LEAF 200pt                     |  resting tilt; slow sway
      |                   contact shadow                   |
y=414 |           ( Pressed | Summer | Autumn )            |  32pt SegmentedCapsule (earned only)
      |                 Pressed in autumn                  |  13pt secondary
y=476 |                     Red maple                      |  28pt SF Rounded semibold
      |                    Acer rubrum                     |  17pt New York italic, secondary
      |                      (Common)                      |  tier chip (+ approximate chip if i/u)
y=574 |                        22%                         |  MemberShareLabel .detail
      |            of members have this leaf (i)           |
y=648 | .------------------------------------------------. |  StatusTile, L1, radius 28, padding 20
      | | Pressed Saturday 4 October 2026                | |
      | | For 14 on-time bedtimes . in autumn            | |
      | | Show on my maple >                             | |
      | '------------------------------------------------' |
      | Native range       Eastern North America           |  SpecimenLabel, L1, radius 28, 48pt rows
      | Leaf               Palmate . 3 lobes . toothed     |
      | Autumn colour      * Scarlet                       |
      | Series             Rubra                           |
```

1. **Specimen stage (300pt):**
   - The leaf at 200pt and its resting tilt.
   - A bloom in the leaf colour at 22%, r 180.
   - A contact shadow 120 × 10, black at 45%, blur 10.
   - Earned leaves sway ±1.5° over 8s (static under Reduce Motion).
   - Locked leaves show the skeleton: outline 1.25pt `#8A96AD` at 55%, veins 0.75pt at 35%, and a progress fill if the leaf is a next rung.
2. **Colourway control** (earned only): `SegmentedCapsule` with Pressed, Summer and Autumn. The caption below reads "Pressed in {season}". Evergreens show a static "Evergreen · stays green" label instead.
3. **Names:**
   - Common name in `leafTitle` (28 SF Rounded semibold); the scientific name in 17 New York italic `textSecondary`.
   - Without a common name, the scientific name becomes the title (28 New York italic semibold) and the second line is "Series Macrantha" in 15 secondary.
4. **Chips** (8pt apart, centred): the tier chip, plus the approximate chip for i/u.
5. **Member share:** `MemberShareLabel(.detail)` (§5.7), with a 20pt `info.circle` that opens the explainer sheet.
6. **Status tile** (Level 1, radius 28, padding 20):
   - **Earned:**
     - "Pressed Saturday 4 October 2026" in 17 SF Rounded semibold;
     - the earned line plus " · in autumn" in 15 secondary;
     - `TextLink` "Show on my maple", which opens Tree view centred on the primary rosette and pulses its halo twice over 2s.
   - **Locked and available:**
     - "How to earn" in 13 secondary;
     - the rule in 20 SF Rounded semibold ("Be in bed on time 14 nights");
     - a 4pt `ProgressHairline`;
     - "9 of 14 · about 5 nights at your pace" in 15 secondary monospacedDigit (the estimate is omitted when rate = 0);
     - the definition line in 13 secondary;
     - the category's action as a `GlassCapsule`, shown only when it makes sense in the current phase;
     - `TextLink` "Pin as next leaf" / "Unpin".
   - **Needs permission:** the rule, "Needs Screen Time" in 15 secondary, and `GlassCapsule` "Turn on Screen Time".
   - **Dormant:** the rule and "Not earnable yet".
   - **Waiting:** "A new leaf is waiting" and the `GlassCapsule` "Open", or "Opens in the morning" in Wind-down and Night.
7. **Specimen label** (Level 1, radius 28; 48pt rows; dividers 0.5pt white 6%): Native range, Regions (as chips), Leaf ("Palmate · 3 lobes · toothed"), Autumn colour (10pt dot plus name), Series, Evergreen (only when true), Note (multi-line, 15 New York italic secondary), Accuracy (i/u only).
8. **Source:** "Species list: Plants of the World Online, Royal Botanic Gardens, Kew." in 12 secondary.
9. **Earned only:** a `GlassCapsule` "Feature on your maple", which sets the crown rosette and the avatar.

### 5.7 Members who have this leaf (rarity)

**What the number means.** The share of active Maple members who hold the species. Active members are installs that opted in and had tracked activity in the last 28 days. The denominator is the number of reports for the latest complete ISO week. It appears on locked and earned leaves.

**States** (`enum MemberShare`), computed by `LeafShareStore.share(for:)`:

| State | When | Detail copy | Tile meta (earned, or Rarest-first sort) | Reveal | Share card |
|---|---|---|---|---|---|
| `.loading` | No cache, request in flight | A 44 × 12 placeholder capsule (white 8%) pulsing 0.35↔0.6 over 1.6s (static 0.45 under Reduce Motion). VoiceOver: "Loading rarity". | Pressed date | Placeholder | Line omitted |
| `.value(display, asOf)` | Fresh: last successful fetch under 48h | "22%" (22pt) / "of members have this leaf" | "22% have it" | "22% of members have this" | "22% of Maple members have it" |
| `.stale(display, asOf)` | A cache exists but the last successful fetch is over 48h old | Same value in `textSecondary`, plus "As of 3 Oct" in 13 secondary | Value, no date | Value plus "as of 3 Oct" | Line omitted |
| `.notEnoughMembers(soFar)` | The week has fewer than 1,000 reports | "Rarity appears once 1,000 members take part" plus " · 640 so far" when published | Pressed date | Same as detail | Line omitted |
| `.neverFetched` | Offline and no cache | "Rarity shows when you're online" | Pressed date | Same as detail | Line omitted |
| `.newSpecies` | Species added in a catalogue update | "New · rarity next week" | Pressed date | Same as detail | Line omitted |
| `.notEarnableYet` | Category not shipped | "Not earnable yet" | "Not earnable yet" | — | — |

Opting out never changes what the user sees; they are simply not counted.

**Formatter** (`MemberShareFormatter`, pure). Input: estimate `p`, 95% bounds `lo` and `hi`, all in percent.

1. If `hi < 0.1` → "Under 0.1%". If `lo > 99` → "Over 99%".
2. `half = (hi − lo) / 2`. The value is *precise* if `half ≤ 0.4 × p`.
3. If precise:
   - `p ≥ 2` → whole percent, clamped to 1…99 ("38%");
   - `0.1 ≤ p < 2` → one decimal ("0.4%").
4. If not precise:
   - `p < 50` → "Under {stepUp(hi)}%";
   - otherwise → "Over {stepDown(lo)}%".
   - Steps: 0.1, 0.2, 0.5, 1, 2, 3, 5, 10, 15, 20, 25, 30, 40, 50, 60, 70, 80, 90, 95, 99.
5. Never "0%" and never "100%".
6. Unit tests cover p = 0.09, 0.1, 0.99, 1.0, 1.99, 2.0, 9.95, 49.9, 50, 99.4 and 99.6, each with wide and narrow bounds.

**Explainer sheet:**
> "Out of 12,400 members who shared their leaves in the week of 29 Sep. Each phone randomly flips some of its answers before sending, so these are estimates; Maple shows a bound like 'Under 1%' when it can't be sure. Only which leaves you hold is ever shared, never sleep, health or screen data."

It ends with a `TextLink` "Privacy settings". The member count is rounded down to the nearest 100.

**Consent:** asked once, as a `.medium` sheet at the end of the first morning reveal.
- **Title:** "Help show how rare each leaf is?"
- **Body:** "Once a week, Maple can send a scrambled list of which leaves you hold. No account, no device ID, no health data."
- **Buttons:** primary "Include my leaves"; `TextLink` "Not now".
- **Settings › Privacy toggle:** "Include my leaves in rarity stats". It is off until the user consents.
- **Privacy copy** changes from "Never leaves your iPhone" to "Your sleep, focus and screen data never leave your iPhone."

**Pipeline** (D14; details in the rewards architect's draft):
- **Client report:** once per ISO week (BGAppRefreshTask or the next foreground), each opted-in client sends:
  - the catalogue version;
  - the ISO week;
  - a 155-bit vector, randomized-response noised on device with f = 0.1.
- **Transport:** through an Oblivious HTTP relay, with an App Attest assertion, and DeviceCheck bits enforcing one report per week.
- **Server:** a Worker adds each report into the week's Durable Object counters and discards the payload.
- **Publishing:** a nightly Cron Trigger computes `p̂ = (observed − f) / (1 − 2f)` with its CI. It falls back to the mean of the last 4 weeks when an interval is too wide. It writes `rarity.json` (catalogue version, week, member count floored to 100, `reports` floored to 10 when below threshold, per species `{pct, lo, hi}`) to R2 behind the CDN.
- **Client fetch:** on foreground, at most once per 24h, with ETag. Cached in the App Group with its fetch time.
- **Before the endpoint is live:** production uses `UnconfiguredLeafShareProvider`, which always yields `.notEnoughMembers(nil)`. `PreviewLeafShareProvider` exists only under `#if DEBUG`.

### 5.8 Unlock celebration (`RevealView`)

**When**
- Pending reveals open from:
  - the Home CTA;
  - the waiting bud;
  - a waiting tile;
  - the focus-session summary ("A new leaf opened" with a `GlassCapsule` "Open", in Morning and Day only).
- Leaves earned from Evening onward are held. The focus summary then says "A new leaf will be waiting in the morning."
- Never presented in Wind-down or Night. The only exception is the First-steps leaf at the end of onboarding (D12).

**Cover**
- Full-screen, pure `#05070D`, with a season-tint bloom at 6% behind the centre. Fades in over `gentle`.
- **Header** at the top inset + 24: "A new leaf" (15 SF Rounded semibold `textSecondary`) with " · 1 of 3" when queued. Under it the category name (13 secondary), e.g. "On-time bedtimes". The species stays hidden until it opens.
- **Bud** at 40% of the height: a 96pt `BudShape` (two overlapping scales, bark gradient, 0.75pt `barkRim`) with a `reward` core glow at 35% (r 60), breathing ±15% over 4s.
- **Prompt:** "Tap to open" (13 secondary) 48pt above the bottom safe area. VoiceOver exposes the bud as the button "Open new leaf".

**Full ritual.** Used for the first 3 reveals ever, and always for uncommon, rare and legendary tiers. Timeline from the tap:

| Time | Event |
|---|---|
| 0s | One haptic: `.impact(flexibility: .soft, intensity: 0.5)`. This is the only haptic in the ritual. |
| 0–0.6s | Bud scales rotate ±35° apart and fade (easeOut) |
| 0.2–1.6s | Leaf scales 0.2 → 1.0 and rotates from −25° to its resting tilt, unfurling behind a mask that sweeps from petiole to tip (`reveal` curve) |
| 0.4–1.6s | Veins draw in with trim 0 → 1 |
| 1.0–1.8s | Fill fades 0 → 1 |
| 0–1.6s | `reward` bloom grows 0 → 30% at r 200 |
| 1.6–2.4s | Bloom crossfades to the leaf's own colour at 22% |
| 1.8–2.8s | Leaf drifts 12pt down and settles (easeInOut; no overshoot) |
| 2.0–2.6s | Text fades in with 8pt upward drift |

Text, top to bottom:
- the name in 28 SF Rounded semibold (or 28 New York italic semibold if unnamed);
- the scientific name in 17 New York italic secondary;
- chips: tier, plus the approximate or Uncharted chip;
- the earned line ("For 14 on-time bedtimes") in 15 secondary;
- `MemberShareLabel(.inline)`.

At 2.6s the footer appears:
- **More queued:** primary "Next leaf", plus `TextLink` "Open all 3".
- **Last one:** primary "Place on your maple".
- A 36pt share `IconCircle` fades in at the top right.

**Short ritual.** Used for First-steps and Common tiers from the 4th reveal onward, lasting 1.2s:
- the bud fades over 0.3s;
- the leaf scales 0.6 → 1.0 while its fill appears over 0.8s;
- the bloom goes amber → leaf colour over 1.0s;
- text appears at 0.6s;
- the same single haptic.

**Open all:** the remaining buds appear in a centred row (56pt each, up to 6 per row) and open one after another every 0.35s with the short ritual. Then a vertical list of the opened leaves follows: 64pt specimen, name and earned line per row. The footer is the primary "Place on your maple".

**Placement:** the cover fades out over `gentle`. On Home, each new primary rosette (and its satellites) fades in 0 → 1 over `graft` (1.6s) at its slot with the amber halo. TreeCaption's count rolls. There is no second haptic, no confetti and no sound by default. A "Reveal sound" toggle in Settings is off by default and uses the ambient session, so it respects the silent switch.

**Reduce Motion:** the bud crossfades to the complete leaf and text over 0.6s. "Open all" goes straight to the list. The haptic is kept.

**After placement:** `AccessibilityNotification.Announcement` "Red maple placed on your maple." If this was the first morning reveal, the consent sheet follows (§5.7).

### 5.9 Share card (`ShareCardView`)

- Rendered with `ImageRenderer` from a 360 × 450pt view at scale 3 (1080 × 1350). Shared through `ShareLink` with a Transferable PNG.
- **Background:** `#05070D`.
- **Frame:** a Level-2 frame inset 24, radius 40. 1pt border from `borderHighlight` (white 22%) to `borderSoft` (`#9DB4E6` at 10%), with a glow `#7F9FE0` at 8%, r 24, inside the canvas margin.
- **Contents, top to bottom:**
  - the specimen at 200pt in the pressed colourway, with bloom and contact shadow;
  - the name in 26 SF Rounded semibold;
  - the scientific name in 15 New York italic;
  - "Pressed 4 Oct 2026 · for 14 on-time bedtimes" in 13 secondary;
  - the approximate or Uncharted chip for i/u;
  - "22% of Maple members have it" in 13 season tint, **only in `.value`**;
  - a "maple" wordmark in 13 SF Rounded semibold, white at 60%.

---

## 6. Design tokens (replacement values for `Tokens.swift`)

### 6.1 Colours

| Token | Value | Use |
|---|---|---|
| `background` | `#05070D` | Every screen |
| `surface1` | `#0C1527` | Level-1 tiles |
| `surface2` | `#111D35` | Sheets, selected chip and segment thumb, avatar disc, pressed Level 1, Reduce Transparency fallback for glass |
| `textPrimary` | `#F2F5FA` | Primary text |
| `textSecondary` | `#8A96AD` (6.7:1 on background) | Secondary text |
| `textTertiary` | `#5A6680` (3.5:1) | Decorative strokes and ticks only. **Never text.** |
| `hairlineTop` | white 8% → 0% at 40% of the height | Level-1 top-lit inner stroke |
| `divider` | white 6% | Row separators |
| `track` | white 8% | Progress tracks |
| `skeletonStroke` / `skeletonVein` | `#8A96AD` 35% / white 10% | Locked leaves |
| `borderHighlight` / `borderSoft` | white 22% / `#9DB4E6` 10% | Level 2, glass borders |
| `glowLevel2` | `#7F9FE0` 8%, r 24, y 0 | Share card only |
| `reward` | `#E8A35C` | Amber whitelist only (§1.3) |
| `rewardHalo` | `#E8A35C` 30% | New-leaf halo |
| `primaryFillTop` / `primaryFillBottom` | `#E2E8F2` / `#B4C0D6` | Primary capsule |
| `primaryFillTopDim` / `primaryFillBottomDim` | `#CBD3E2` / `#A2AEC6` | Primary capsule in evening and wind-down |
| `primaryLabel` | `#05070D` (11:1 on the fill) | Primary capsule label |
| `primaryBorderTop` / `primaryBorderBottom` | white 45% / `#9DB4E6` 20% | Primary capsule border |
| `primaryGlow` | `#9DB4E6` 10%, r 20 | Primary capsule glow |
| `primaryDisabledFill` | white 12% (label `textSecondary`) | Disabled primary |
| `glassTint` | `#0B1426` 30% | `GlassCapsule`, `IconCircle` |
| `chipFill` | white 5% | Unselected chips |
| `chipSmallFill` | white 6% | Tier and other small chips |
| `seasonTint.spring` | `#BFD8A6` | Season tint |
| `seasonTint.summer` | `#9CC3A4` | Season tint |
| `seasonTint.autumn` | `#E3A49E` (9.6:1); hue about 5°, 26° from amber | Season tint. Verify against `#E8A35C` and `#D1A020` on device and in protan, deutan and tritan simulators before ship. Meaning never depends on colour alone. |
| `seasonTint.winter` | `#C9DDEE` | Season tint |
| `budNeutral` | `#C9D3E3` 45% | Locked buds |

**Scene**

| Token | Value |
|---|---|
| `skyNight` | `#05070D` |
| `skyNavy` | `#0B1426` |
| `skyDay` | `#111D35` |
| `skyDeep` | `#080D19` |
| `dawnWash` | `#3B2F3F` 10% |
| `dawnPool` | `#F2E6D8` 5% |
| `moonlight` | `#AFC3E8` (pools 5–7%) |
| `moonDisc` | `#E9EEF7` 55% |
| `ground` | `#070B14` |
| `groundRim` | `#9DB4E6` 14% |
| `bark` | `#2A3348` → `#121826` |
| `barkTip` | `#3A4663` |
| `barkRim` | `#A9BEE3` 25% |
| `contactShadow` | black 55% |
| `samara` | `#B89A72` 55% |
| `firefly` | `#D9E6A8` 35% |
| `pollen` | `#E8F0C0` 12% |

**Leaf colourways** (`LeafColourway` in MapleCore, computed from `LeafSpecies`):

| Colourway | Computation |
|---|---|
| `summer` | `summerColor` + 0.06 lightness |
| `spring` | `summerColor` mixed 25% toward `#D8E8B0` |
| `autumn` | `autumnColor` (G + 0.06 lightness) |
| `frost` | `autumnColor` mixed 60% toward `#C9DCE8`, plus a white 40% rim at 14pt and above. Deciduous only. |

On the tree: −10% saturation, × phase brightness (Wind-down 0.9, Night 0.75).

**Remove:** `backgroundRaised`, `surface`, `surfaceRaised` (`#18264A`), `glow`, and the entire `LeafPalette` (including `autumnGold`, which equalled `reward`).

**Increase Contrast overrides:**

| Token | Override |
|---|---|
| `textSecondary` | `#A3AEC2` |
| `hairlineTop` | 24% |
| `divider` | 16% |
| `track` | 16% |
| `skeletonStroke` | 55% |
| Glass borders | 40% / 25% |

### 6.2 Typography

All styles use Dynamic Type text styles (`Font.system(_:design:weight:)`) or `@ScaledMetric(relativeTo:)`. Numerals always use `.monospacedDigit()`.

| Token | Spec | Relative to |
|---|---|---|
| `heroNumeral` | 64 SF Rounded semibold, tracking −1.5, max 88. Units 32 SF Rounded medium `textSecondary`. | `.largeTitle` |
| `scoreNumeral` | 48 SF Rounded semibold | `.largeTitle` |
| `statNumeral` | 34 SF Rounded semibold (Profile totals use 28) | `.title` |
| `screenTitle` / `leafTitle` | 28 SF Rounded semibold, tracking −0.3 | `.title` |
| `sectionTitle` | 20 SF Rounded semibold | `.title3` |
| `headline` / `buttonLabel` | 17 SF Rounded semibold | `.headline` |
| `body` | 17 SF Pro regular | `.body` |
| `contextEmphasis` | 15 SF Rounded semibold | `.subheadline` |
| `callout` | 15 SF Pro regular | `.subheadline` |
| `footnote` | 13 SF Pro regular | `.footnote` |
| `tileName` | 13 SF Rounded semibold | `.footnote` |
| `tileMeta` | 12 SF Pro regular, monospacedDigit | `.caption` |
| `micro` | 11 SF Rounded medium (minimum size; chips and ≈ only) | `.caption2` |
| `scientific(_ style)` | New York italic: `.system(style, design: .serif).italic()` at 28 (title), 17, 15, 13 | the given style |

Rules:
- Sentence case everywhere. No tracked uppercase anywhere.
- `SectionLabel` (tracked caps) is removed from shipping UI.
- The serif is used only for scientific names, and for species notes.

### 6.3 Spacing

| Token | Value |
|---|---|
| `xxs` | 4 |
| `xs` | 8 |
| `sm` | 12 |
| `md` | 16 |
| `lg` | 24 |
| `xl` | 32 |
| `xxl` | 40 (changed from 48) |
| `xxxl` | 48 |
| `hero` | 56 |

| Context | Value |
|---|---|
| Home margin | 24 |
| Herbarium margin | 16 |
| List and sheet margin | 20 |
| Row height | 56 |
| Specimen-label row | 48 |
| Grid gutter | 10 |
| Rows within a group | 12 apart |
| Between groups | 32 |
| Herbarium section gap | 24 |
| Minimum hit target | 44 × 44 |

### 6.4 Radii

| Token | Value |
|---|---|
| `tile` | 20 |
| `largeTile` | 28 |
| `shareCard` | 40 |
| Buttons and chips | `Capsule(style: .continuous)` |
| Icon buttons and avatar | `Circle` |
| Sheets | System |

All rounded rectangles use `style: .continuous`. Remove `card` 24, `control` 16 and `chip` 12.

### 6.5 Elevation, glow, shadow

| Level | Fill | Edge | Glow / shadow | Used by |
|---|---|---|---|---|
| Level 0 | None | None | None | Default: the whole Home first screen, below-the-fold blocks, section headers, specimen rows on black |
| Level 1 | `surface1` | 1pt inner `hairlineTop` gradient | None | Herbarium earned and waiting tiles, Almost-there cards, detail tiles, list rows |
| Level 2 | `surface1` | 1pt `borderHighlight` → `borderSoft` | `glowLevel2` | Share card frame only |

Content glow caps:

| Source | Maximum |
|---|---|
| Tree bloom | 18% |
| Leaf bloom in tiles | 18% |
| Leaf bloom in detail and reveal | 22% |
| Reveal amber bloom | 30% |
| Waiting-bud core | 60% |
| Primary glow | 10% |

Contact shadow is the only shadow type: an ellipse, black 45–55%, blur 6–10. No `.shadow` on any container.

### 6.6 Motion

| Token | Value | Use |
|---|---|---|
| `press` | 0.2s easeOut | Press feedback (the only fast motion) |
| `gentle` | 0.6s easeInOut | Selection, numericText, crossfades, Reduce Motion substitutes |
| `calm` | 1.0s easeInOut | Sections appearing, sheet content |
| `drift` | 3.2s easeInOut | Sky and vitality interpolation |
| `reveal` | 1.6s `timingCurve(0.2, 0, 0, 1)` | Bud opening, unfurl |
| `revealShort` | 1.2s total | Short ritual |
| `graft` | 1.6s easeInOut | New rosette and growth easing on the tree |
| `sway` | 8s sine (Night 10s) | ±0.6 / 1.0 / 1.4° |
| `flutter` | 5–7s seeded sine | ±3° |
| `breathe` | 10s | Bloom ±15% |
| `budPulse` | 4s | Waiting bud ±15% |
| `twinkle` | 6–12s | Stars |
| `particles` | samara 14s, snow 18s, pollen 20s, firefly 3s fades | Season particles |
| `loadingPulse` | 1.6s, opacity 0.35 ↔ 0.6 | Never a shimmer sweep |

- Ambient rendering runs at 30fps maximum and pauses off-screen, when inactive, in Low Power Mode (still frame) and after 60s idle at Night.
- No spring overshoot (`dampingFraction` 1.0 when a spring is used).
- All motion goes through `mapleAnimation(_:value:)`.

### 6.7 Haptics

| Moment | Haptic |
|---|---|
| Reveal opens | `.impact(flexibility: .soft, intensity: 0.5)` |
| Segmented and chip changes | `.selection` |
| Everything else | None |

Haptics are kept under Reduce Motion.

### 6.8 Symbols

- **Custom template symbols** (asset catalogue; 1.5pt rounded stroke drawn to SF Symbols Regular): `maple.tree`, `maple.herbarium`.
- **SF Symbols allowed** only inside controls, at 13–17pt regular or semibold, monochrome: `moon` (tab), `moon.fill` (streak), `chevron.left`, `chevron.right`, `xmark`, `magnifyingglass`, `line.3.horizontal.decrease`, `square.and.arrow.up`, `info.circle`, `plus`, `minus`, `play.fill`, `pause.fill`.
- Leaves and buds are always drawn, never symbols.

### 6.9 Shape of the new `Tokens.swift`

```swift
public struct Theme: Sendable {
  public var colors: Colors          // flat tokens above + seasonTint(_ season:) + scene: SceneColors
  public var spacing: Spacing        // xxs…hero, homeMargin 24, gridMargin 16, listMargin 20, row 56, labelRow 48, gutter 10
  public var radius: Radius          // tile 20, largeTile 28, shareCard 40
  public var elevation: Elevation    // level1/level2 specs (fill, edge gradient, glow)
  public var motion: Motion          // press, gentle, calm, drift, reveal, revealShort, graft + loop periods
}
public enum MapleFont { heroNumeral(size:), scoreNumeral, statNumeral, screenTitle, leafTitle, sectionTitle,
                        headline, body, contextEmphasis, callout, footnote, tileName, tileMeta, micro, scientific(_:) }
public enum SceneColors { static func sky(for phase: NowPhase) -> SkyPalette }   // §4.4 table, data only
```

---

## 7. Components

### 7.1 Delete

- `App/Features/Shared/PlaceholderCard.swift`.
- `App/Features/Today`, `Sleep`, `Focus`, `Grove` and `Insights` as tab roots.
- `GlowCard` and `glowSurface(cornerRadius:fill:)`.
- `MapleLeafShape` and `LeafGlyph`.
- `MapleButtonStyle` (both kinds).
- `mapleBackground()` (the full-screen navy gradient).
- `Theme.LeafPalette`.
- Every "Arrives in Mx" string, including Settings' export and delete line.
- `SectionLabel` is removed from all shipping screens. It may remain only inside the DEBUG Design System screen.

### 7.2 Keep and update

| Component | Change |
|---|---|
| `LeafView`, `LeafGeometry`, `LeafRenderer` (MapleDesign/Leaves) | Keep as the only leaf renderer. Add `Fill.colourway(LeafColourway)`, a `Style.skeleton(stroke:vein:)` mode (outline and veins, no fill), and `progressFill(fraction:colour:opacity:)`, a mask rising from the petiole. Add `LeafPathCache`: lazy, lock-protected, keyed by species id. |
| `StatNumber` | Sizes become `.hero` (64, units at half size in secondary), `.score` (48), `.stat` (34), `.inline` (17). Keeps `@ScaledMetric`, combined accessibility and `numericText`. |
| `mapleAnimation(_:value:)` | Unchanged; all motion goes through it. |
| `DesignSystemView` | Rebuilt (§8.10). |

### 7.3 Build

| Component | Module | Purpose | Visual spec |
|---|---|---|---|
| `.surface(_ level:, radius:)` | MapleDesign | Replaces GlowCard | §6.5 |
| `MoonlightButtonStyle(dimmed:)` | MapleDesign | The one primary action | 52pt minimum capsule; vertical gradient `primaryFillTop` → `primaryFillBottom` (dim variant in evening and wind-down); 1pt border `primaryBorderTop` → `primaryBorderBottom`; glow `primaryGlow`; label `buttonLabel` `primaryLabel`, up to 2 lines at accessibility sizes. Pressed: scale 0.98 and 6% darker over `press`. Disabled: `primaryDisabledFill`. |
| `GlassCapsuleStyle` | MapleDesign | Secondary actions | 44pt capsule, `.glassEffect(.regular.tint(glassTint))`, 1pt border `borderHighlight` → `borderSoft`, no glow; label 15 SF Rounded semibold `textPrimary`. Reduce Transparency: `surface2` fill. |
| `IconCircleStyle` | MapleDesign | Back, close, share, search, filter, info, plus, minus, play | 36pt visual, 44pt hit area, glass as above, symbol 15 semibold at 90% |
| `TextLink` | MapleDesign | "All insights ›" and similar | 15 SF Rounded medium `textSecondary` + `chevron.right` at 11 semibold |
| `Chip` | MapleDesign | Filters | 32pt capsule, `tileName`; `chipFill` / selected `surface2` + white 14% top hairline |
| `SmallChip` | MapleDesign | Tier, approximate, region | 22pt capsule, `micro`, `chipSmallFill`. The approximate variant has no fill and a 1pt dashed border, white 30%, dash (3, 2). |
| `SegmentedCapsule` | MapleDesign | Colourway, Sleep/Focus | 32–36pt; track white 6%; thumb `surface2` + top hairline slides with `gentle`; labels 13–15 SF Rounded semibold |
| `ProgressHairline(fraction:, height:)` | MapleDesign | All progress | 2 / 3 / 4pt capsule; track `track`; flat fill in season tint (amber only for the Herbarium owned bar); never a gradient, never a label inside |
| `SpecimenView(species:, colourway:, size:, state:)` | MapleDesign | The specimen grammar | Bloom (own colour) + `LeafView` at its resting tilt + contact shadow. `state`: earned, next(progress), locked, waiting. |
| `BudShape` / `BudGlyph(waiting:)` | MapleDesign | Buds | Two overlapping teardrop scales, bark gradient, rim. The waiting variant adds a `reward` core glow (breathing or static). |
| `MemberShareLabel(share:, layout: .detail / .tile / .inline)` | MapleDesign | Rarity in every state | §5.7 |
| `MemberShareFormatter` | MapleCore | CI-aware formatting | §5.7 |
| `NowState` / `NowPhase` resolver | MapleCore | Home state | §3.3–3.4 |
| `NextLeafPicker` | MapleCore | Next, buds, Almost there | §3.5 |
| `TreeGrowth(tendedDays:)` → g; `TreeStageName(speciesCount:)` | MapleCore | Two axes | §4.1 |
| `TreeLayout.generate(seed:g:species:buds:featured:)` → `TreeSkeleton { segments, tips, slots, budSlots }` | MapleCore | Deterministic layout | §4.2–4.5 |
| `Vitality(last7Nights:)` → v | MapleCore | Quiet state | §4.8 |
| `LeafColourway` | MapleCore | Colour maths | §6.1 |
| `HomeView`, `HomeHeader`, `TreeCaption`, `NowBlock`, `NextLeafRow`, `PrimaryAction`, `ScoreBlock`, `WeekBlock` | App/Features/Home | Home | §3 |
| `TreeStage`, `SkyBackdrop`, `TreeRenderer` (3 raster layers), `ParticleLayer`, `TreeView` | App/Features/Tree | The hero | §4, §8.4 |
| `HerbariumView`, `HerbariumModel` (@Observable, derived sections), `AlmostThereCard`, `LeafCell`, `CategorySectionHeader`, `HerbariumFilterSheet`, `HerbariumSearchSheet`, `LeafDetailView`, `StatusTile`, `SpecimenLabel`, `ShareCardView` | App/Features/Herbarium | Collection | §5 |
| `RevealView`, `RevealCoordinator` (@Observable queue; held vs pending) | App/Features/Reveal | Ritual | §5.8 |
| `RestView`, `SleepDial`, `FocusTimer`, `WindDownMode`, `FocusSessionView`, `SoundsSheet` | App/Features/Rest | Tools | §8.1 |
| `StreakSheet`, `ProfileSheet`, `ScoreSheet`, `InsightsView` | App/Features/… | Secondary screens | §8 |
| `LeafShareProvider` protocol, `LeafShareStore` (@Observable, @MainActor, App Group cache), `UnconfiguredLeafShareProvider`, `RarityReporter` (randomized response + OHTTP) | MapleServices | Rarity | §5.7 |

### 7.4 Data the views read

```swift
struct LeafProgress: Sendable, Identifiable {
  let speciesID: String; let category: CategoryID; let threshold: Double; let tier: Tier
  let current: Double                  // category counter, clamped to threshold
  let availability: Availability       // .available, .needsScreenTime, .needsAppleHealth, .dormant
  let state: State                     // .earned(Date, pressed: LeafColourway), .waiting(Date), .locked
  let estimatedDays: Double?           // nil when unavailable or earned
}
```

`LeafEngine` produces `Unlock` records keyed by species id (deterministic, so duplicates are impossible) with date and season. The UI never computes unlocks itself.

---

## 8. Other tabs and screens

Rule for all of them: each screen is built around its own object or real data. A tool that has not shipped is absent. An empty state is drawn (a sapling, a bud, a skeleton), never an icon plus a sentence.

### 8.1 Rest tab

- **Header:** a custom 44pt row with "Rest" in `screenTitle`.
- **Mode switch:** a 36pt `SegmentedCapsule` with Sleep and Focus, shown only once Focus ships. Until then Rest is Sleep only.
- **Sleep:**
  - **The hero object:** `SleepDial`, 280pt. A 24h ring (2pt track, white 8%). The bed-to-wake arc is 3pt in season tint; the wind-down arc is the same tint at 40%. A 10pt moon marker sits at the current time.
  - **Below the dial:**
    - "23:00 → 07:00" in `statNumeral`: tonight's times. The dial and this pair always show tonight, the night that wakes into tomorrow; a night is a weekend night when it wakes into the calendar's weekend (Friday and Saturday nights for a Saturday–Sunday weekend), so it follows the member's region;
    - "8h in bed" in 15 secondary;
    - only when weekend nights differ, one quiet line naming the other nights: "Weekends 00:30 → 09:00" on a weekday night, "Weekdays 23:00 → 07:00" on a weekend night (13 secondary, monospaced digits);
    - `TextLink` "Edit schedule".
  - **Schedule editor** (sheet, `.medium`, `.large` while a wheel is open):
    - "Sleep schedule" (`sectionTitle`) and a close `IconCircle`.
    - A full-width 36pt `SegmentedCapsule` "Every day · Weekdays · Weekends", with one 13 secondary line under it that names the nights from the calendar ("Sunday to Thursday nights", "Friday and Saturday nights"), "The same every night" on Every day, or "Weekends will use these times too" when Every day would fold a separate weekend back in.
    - Why one three-way control: it is both the switch (one schedule, or a separate weekend) and the tab for the weekend times, so the sheet stays a single decision with no extra toggle row, and the words say exactly which nights the times below are for. It opens on Every day for one schedule, otherwise on tonight's nights. The first visit to Weekends starts from the weekday times; saving on Every day saves one schedule for every night.
    - Below it the two times side by side (tapping one opens its wheel), the wind-down length (30m, 45m, 1h), a one-line summary and "Save". Edits apply from the next night for the ledger.
  - **Level-1 rows** (56pt, 12pt apart), each present only once its feature ships: "Sleep sounds · Rain" (opens the Sounds sheet), "Wind-down apps · 4 apps", "Caffeine curfew · 15:00", "Alarm · 07:00".
  - **Primary:** "Start wind-down" (dimmed variant) in Evening and Wind-down; none otherwise.
- **Wind-down mode** (full-screen cover):
  - A dim bedside screen: the time in `heroNumeral` at 70% opacity, then "38m until bed" (15 secondary).
  - Ritual steps once they ship. A sounds `GlassCapsule`.
  - Primary "Goodnight", which records phone-down time and dims to black after 10s.
  - No tree and no leaves, so there is nothing to browse at night.
- **Focus:**
  - **The hero object:** `FocusTimer`, a 240pt ring (2pt track, white 10%) whose progress arc (3pt, season tint) ends in a 14pt leaf of the next focus-category species. "25:00" in `heroNumeral` sits inside.
  - **Below it:**
    - a stepper: `IconCircle` minus and plus around a 120 × 44 glass capsule "25m" (22 SF Rounded medium monospacedDigit);
    - the line "Counts toward Trident maple · 6h of 8h" (13 secondary);
    - primary "Start focus".
  - **Running:** the arc fills and the numeral counts down. "End early" is a `TextLink`.
  - **Finished:** a summary sheet with minutes, today's total and the leaf progress line, plus "A new leaf opened · Open" or "A new leaf will be waiting in the morning" when one was earned.

### 8.2 Insights (pushed from Home or Profile)

- "Insights" in `screenTitle`.
- One week chart: 7 sleep-duration bars, 12pt wide, max 56pt, white 70%, with a dashed goal hairline at white 18% and 4pt season-tint dots on on-time nights.
- Under the chart, plain-language rule rows (Level 0, 56pt): "In bed by 23:00 · 5 of 7 nights", "Asleep 7h or more · 4 of 7".
- Sections appear only for data that exists. At first ship it is sleep only.
- No placeholder rows.

### 8.3 Profile sheet (`.large`, from the avatar)

- The featured leaf as `SpecimenView` at 96pt.
- "Young maple · 23 leaves · 41 days" in 15 secondary.
- A totals row of up to 4 `StatNumber(.stat)` at 28pt with 13pt captions (nights on time, focus hours, wind-downs, mornings), each shown only once its category exists.
- Level-1 rows: Settings, Privacy, Challenges (once shipped), Export and delete (once shipped), About, and Design System (DEBUG only).

### 8.4 Tree view (full-screen cover, zoom from the stage)

- The same scene and phase as Home, with the tree fitted to the width minus 32.
- Pinch to zoom 1–3× and pan.
- Tapping a rosette (22pt hit radius in screen space) pushes that leaf's detail. Tapping the waiting bud opens the reveal.
- **Top bar:**
  - close `IconCircle`;
  - centred title "Your maple" (17 SF Rounded semibold) with "Young maple · 23 of 155 · 41 days" (13 secondary) under it.
- **Bottom:** `GlassCapsule` "See all leaves", which switches to the Herbarium filtered to Earned.
- **VoiceOver:** each primary rosette is an element, ordered left to right and top to bottom, labelled "Red maple, pressed 4 October". The "See all leaves" list is the full alternative.
- Reduce Motion: no sway.

### 8.5 Score sheet (once the wellbeing score ships)

- Title "How your score works".
- One section per sub-score.
- **Each row:** the rule in plain words with your week, e.g. "In bed by 23:00 · 5 of 7 nights" (17 SF Rounded semibold over 13 secondary), and a 4pt bar.
- **Each section ends with one improvement line**, e.g. "Two more on-time nights would lift Sleep to 86."
- The window is always stated: "Last 7 days, updated 07:10".

### 8.6 Streak sheet (`.medium`)

- A `moon.fill` glyph at 40pt and the numeral "12" in `heroNumeral`, both `reward`.
- "night run" in 15 secondary and "Best run: 21 nights" in 13 secondary.
- A 14-night row of 20pt circles:
  - nights in the current run: filled `reward`;
  - a forgiven miss: hollow `reward` ring;
  - other nights: white 8% ring.
- "One missed night in any 7 doesn't break a run." in 13 secondary.
- The next Bedtime-runs leaf as a `NextLeafRow`.

### 8.7 Settings and Privacy

- Level-1 grouped rows; `screenTitle` header; no large titles; no milestone strings.
- **Privacy rows:**
  - "Include my leaves in rarity stats" (toggle), with the explainer link;
  - "Your sleep, focus and screen data never leave your iPhone." (13 secondary);
  - Apple Health and Screen Time status rows with "Turn on" where they are missing.
- **Settings:** hemisphere, sleep goal, "Reveal sound" (off by default).

### 8.8 Onboarding (the only place the Seed stage is seen)

**Setup.** One question per screen, then the schedule they propose, then the permission primers. Every screen has the same frame: a top bar with a back `IconCircle` (questions and the schedule step only) and a 2pt `ProgressHairline` (season tint on `track`, the step's share of 7), the question in `screenTitle` with a 15 secondary line under it, the answer centred in the space below, and a `MoonlightButton` at the bottom. No emoji; sentence case; everything scales with Dynamic Type (side-by-side pairs stack, and the page scrolls, at accessibility sizes). Screens cross-fade; with Reduce Motion the in-screen number and layout animations are off. Every answer is saved as it changes (`onboarding.json`), so a relaunch reopens the same screen with the same answers.

1. **"When do you need to be up on weekdays?"** · "Your bedtime is worked back from it." A wheel time picker (07:00). "Continue".
2. **"And on weekends?"** · the calendar's weekend mornings ("Saturday and Sunday mornings"). A 36pt `SegmentedCapsule` "Same time · Later" (at most 320pt wide). Same time shows "Up at 07:00, as on weekdays"; Later shows a wheel (weekday + 1h to start). The answer area keeps the wheel's height either way, so nothing jumps.
3. **"How much sleep feels best?"** · "Most people feel best with 7 to 9 hours." The need in `heroNumeral` ("7h 30m") between minus and plus `IconCircle`s, 7h to 9h in 15-minute steps (7h 30m to start), a row of choice dots and "Bed about 23:15" under it. VoiceOver: one adjustable element. The answer becomes Settings' sleep goal.
4. **"How long do you like to wind down?"** · "A quiet stretch before bed, with the phone put away." The start time in `heroNumeral` with "Your wind-down starts" (", on weekdays" when weekends differ), and a capsule "30m · 45m · 1h" (45m to start).
5. **"Your sleep schedule"** · "Proposed from your answers. Saving it plants your maple." (it reads "Adjusted from your answers." once changed). The schedule the answers propose: for each night type, bedtime = wake − sleep need − 15 minutes to fall asleep, with the chosen wind-down. When weekends differ, a "Weekdays · Weekends" capsule above the times, with the nights it covers under it. Bedtime → wake-up as two tappable `statNumeral` times (the selected one on a lifted tile), "8h in bed", one wheel for the selected time, and the wind-down capsule with "From 22:15". Primary "Save schedule" saves it (one call), sets the sleep goal, and earns the First-steps leaf. Back from here returns to the questions; the adjusted times are kept unless an answer then changes.
6. **Apple Health primer**: `HealthPrimerView` full screen (one 112pt leaf, two sentences, "Continue", "Not now"); Continue shows Apple's prompt. Skipped when Apple Health is already connected. Either answer moves on; there is no back from here, since the schedule is saved.
7. **Notifications primer**: owned by the reminders work; until it lands the step continues at once.

**End.**

1. The scene with the 44pt sprout and its neutral bud on the hill. The bud turns amber.
2. "Your maple" (`screenTitle`) and "Tap to open your first leaf" (13 secondary).
3. The full reveal of the First-steps leaf ("For planting your maple").
4. "Place on your maple" grafts it, and Home appears.

### 8.9 Herbarium empty and early states

The grid always shows all 155 skeletons, so the scale and variety of shapes are visible from day one. "Almost there" shows the reachable first rungs. There is no "nothing here yet" illustration.

### 8.10 Design System screen (DEBUG only)

Sections are separated by 0.5pt hairlines, not boxed. It shows:
- every colour swatch with its hex value and role ("reward only", "decorative only");
- Levels 0, 1 and 2 side by side;
- the numeral scale (64 / 48 / 34 / 17) and the full type ramp, including the New York italic;
- the primary capsule (normal, dimmed, disabled), glass capsule, icon circle, chips and segmented control, all on real backgrounds;
- every `MemberShareLabel` state;
- every `LeafCell` variant;
- the tree at 0, 1, 5, 15, 40, 90 and 155 species, in each of the 4 seasons and 5 phases, plus quiet;
- all 155 species in summer, autumn, spring and frost, with i and u flagged.

---

## 9. Accessibility requirements

**VoiceOver**
- Every element has a spoken label with full units, e.g. "7 hours 12 minutes asleep last night", "23 of 155 leaves".
- The tree is one element with custom actions (§4.11). Per-leaf access is through the Herbarium and Tree view.
- **Tiles are combined button elements:**
  - Earned: "Red maple, Acer rubrum. Pressed 4 October. 22 percent of members have it."
  - Locked: "Paperbark maple, locked. Be in bed on time 14 nights. 9 of 14."
  - Approximate leaves add "Approximate drawing." or "Uncharted, placeholder drawing."
- **Headings:** Herbarium section headers, "Almost there", "This week", and detail-tile titles all carry the header trait.
- **Custom rotor** in the Herbarium: "Earned leaves", "Almost there".
- **The reveal:**
  - the bud is a button, "Open new leaf";
  - a visible "Open" text button sits below the caption for Switch Control;
  - an announcement is posted after placement.
- Scientific names use a Latin language hint for speech (`.accessibilitySpeechLanguage("la")`) so they are read sensibly.

**Dynamic Type**
- All text scales.
- `heroNumeral` is capped at 88 and `scoreNumeral` at 72. Numerals use `minimumScaleFactor(0.6)`.
- At accessibility sizes:
  - Home's stage (and Rest's dial) yield height, down to 150pt, so the first screen's action stays above the tab bar; at the two largest sizes the capsule is pinned just above the tab bar and the rest scrolls under it (`HeroFit`, §3.1);
  - the NowBlock caption may wrap to 3 lines; the tree caption drops the stage name rather than truncate;
  - the primary label may wrap to 2 lines and the capsule grows; a `GlassCapsule` label does the same;
  - the Tree view's subtitle drops the stage name, then the days, rather than cut off the count, and the tree is fitted below the top bar as it is drawn;
  - the score capsules become 3 left-aligned rows (label left, value right) through `ViewThatFits`, and the twigs are hidden.
- **Herbarium columns:** 3 up to `.xLarge`; 2 up to `.xxxLarge`; at accessibility sizes, a 1-column list of 72pt rows with a 48pt leaf on the left. The Almost-there rail becomes a vertical stack.
- Drawings (tree, leaves) never scale with text.

**Reduce Motion**
- Every screen renders a complete still frame:
  - no sway, flutter, twinkle, particles, parallax or loading pulse;
  - zoom transitions become opacity;
  - numbers change without rolling;
  - the reveal becomes a 0.6s crossfade.
- Haptics are kept.

**Reduce Transparency:** all glass (tab bar, capsules, circles, pinned headers) becomes solid `surface2` with the same border.

**Increase Contrast:** apply the §6.1 overrides; text never drops below `textSecondary` on `background`.

**Contrast**
- All required text meets 4.5:1. `textSecondary` is 6.7:1, season tints are 9:1 or more, and the primary label is 11:1.
- `textTertiary` (3.5:1) is never used for text.
- The stage caption sits on the dark ground fill, not on the bloom.

**Colour independence**
- Rarity, progress, tier and state are always also carried by text or shape: skeleton vs filled, "≈", the meta copy.
- Autumn colour names appear in detail next to their dot.
- Crimson and scarlet are distinguished by name, never by colour alone.

**Targets:** 44 × 44pt minimum everywhere, including the 32pt avatar, the 36pt circles, the waiting bud and the tree caption.

**Haptics:** only the reveal haptic and `.selection`. Nothing conveys information by haptic alone.

**Verification before ship**
- **Snapshot matrix:**
  - Home in each of new user, morning (Health / no Health / no data), day (before and after focus ships), focus running, evening, wind-down, night, pending (1 and 3), quiet;
  - in 4 seasons, at Large and AX3, with Reduce Motion on.
- **Tree:** 0, 1, 5, 15, 40, 90 and 155 species × 4 seasons × 5 phases, with a fixed seed.
- **Rarity:** every `MemberShareLabel` state.
- **Herbarium:** every `LeafCell` variant, plus detail for k, i and u.
- **Unit tests:**
  - `RewardLadderTests`: every species exactly once and thresholds strictly increasing per category;
  - `MemberShareFormatter` edges;
  - `NextLeafPicker`, including the new-user first rungs and exclusion of unavailable categories;
  - growth monotonicity in g and in total leaf count;
  - `TreeLayout` determinism, with capacity `tips × 3 ≥ n + 3` at every point of the pacing simulation;
  - LeafEngine idempotence.
- **Pacing simulation:** 365 days for typical, light and no-Screen-Time users.
- **Manual passes:**
  - a VoiceOver rotor pass through Home → Tree view → Herbarium → Detail → Reveal;
  - a Switch Control pass through the reveal;
  - an Instruments pass on the tree (under 4ms per frame);
  - autumn tint vs amber vs gold checked on device and in colour-blind simulators.