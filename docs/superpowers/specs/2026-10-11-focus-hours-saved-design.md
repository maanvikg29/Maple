# Focus tab and hours saved: design

Status: draft for the owner's review (2026-10-11). Once approved it is binding for everything it covers, and it wins over `docs/design/spec.md` and `docs/design/rewards.md` where they disagree (§12 lists every override).

Sources: 15 research agents (run `wf_14378e2b-21f`, 2026-10-11). They covered:
- Opal in depth, plus 22 study-timer and blocker apps;
- about 17,800 mined App Store reviews;
- Apple's Screen Time, ActivityKit and App Intents docs, checked against the iOS 27 SDK on this Mac;
- a red team of approach A, and reward economics with a Monte Carlo pacing model;
- learning science, social study, ambient sound and session UX.

## 1. What we're building and why

**What the owner said.**
- Maple is a focus app. Leaves come mostly from *hours saved*: awake time during which the apps you chose were really blocked. Sleep is secondary.
- There is a new tab for studying, with a dedicated timer that blocks selected apps.
- Maple must be better than its competitors.
- Blocking is built for real now, and works once the account joins the paid Developer Program.

**What success looks like.**
- A student starts a blocked study session in one tap and is never failed by accident.
- The hours number is one they can check.
- The collection keeps meaning something after a year.

**Assumptions** (from the research, accepted by the owner in the decisions below):
- v1 is for ages 13 and up.
- Approach A+ is the counting model.
- The tab is called Focus.

## 2. Owner decisions (2026-10-11)

| # | Question | Decision |
|---|---|---|
| O1 | Counting model | **A+** (§3): hours saved = time your chosen apps stayed locked while you were awake. Caps: 6h a day, 2h a day from blocks that start on their own, and 15 min–3h per session. The label stays "Hours saved". |
| O2 | Tab name | **Focus**. "Study" is the default session type ("Start study · 50m"). |
| O3 | Pricing | **Decide later.** This build has no paywall code, and everything in it is free. Apple Guideline 4.10 bars charging for Screen Time features in any case. |
| O4 | Sync | **Yes.** Maple's own session ledger and its leaf list sync to the member's private iCloud (§9.5). Screen Time usage data and health data never sync. |
| O5 | Breaks | **Locked breaks by default.** Short breaks keep apps locked and count. An opt-in Phone break unlocks apps and earns nothing. |
| O6 | Audience | **13+ students and adults.** Productivity category, 9+ rating, no social features in v1, no under-13 support. |

## 3. Hours saved (approach A+)

### 3.1 Why A, and why the plus
- **Measuring a real drop in screen time is impossible** outside the EU. Apple's usage export (`approvedWithDataAccess`, `DeviceActivityData.activityData`, iOS 26.4) is EU-only and limited to one app per device. Outside it, usage never leaves the DeviceActivityReport sandbox.
- **Usage thresholds are unreliable.** On iOS 26–27, `eventDidReachThreshold` fires early or with zero use (FB18061981, FB21450954).
- **So Maple counts the only records it controls:** when its own stores locked and unlocked apps.
- **The plus closes three holes found by the red team:**
  - callback timestamps that arrive late;
  - passive schedules that farm the ladder;
  - clock and permission tricks.

### 3.2 Rules
- **R1. Definition.** Hours saved for a local day =
  1. the union of verified locked intervals,
  2. intersected with that day's awake window,
  3. minus override and Phone-break windows,
  4. then capped (R8, R9).

  Overlapping sessions or blocks count once. Two iPhones on one iCloud account merge into one timeline.
- **R2. Start of an interval.** A verified locked interval starts at a ledger `shieldApplied` event. That event must be written by the process that applied the shield (the app for sessions, the monitor extension for schedules), while authorization is `.approved` and the selection qualifies (R3). No start event, no credit.
- **R3. Qualifying selection.** At least one app category, or 3 or more apps or sites, or "Only these apps" mode. The selection is frozen when a session starts; edits apply to the next session.
- **R4. End of an interval.** The earliest of:
  - the planned end;
  - an End tap;
  - "End session" on the shield;
  - an emergency release;
  - the start of an override or Phone break;
  - the last provable checkpoint before access was revoked, Maple was deleted, or a token expired.

  A checkpoint is the app in the foreground, a monitor callback, or a shield-action event. DeviceActivity callback timestamps are never boundaries.
- **R5. Timing.**
  - Every event records the wall clock, the continuous clock and the boot session.
  - Credit for a segment = min(planned length, wall-clock elapsed, continuous elapsed within one boot).
  - After a restart, only uptime counts.
  - A clock change can only lower credit.
- **R6. Awake window.**
  - Nothing between the scheduled bedtime and the wake time counts.
  - Bedtime blocks count only their wind-down.
  - A session started after bedtime still blocks, but earns 0, with a gentle note.
  - Apple Health sleep never subtracts credit.
- **R7. Breaks and overrides.**
  - A short break with shields up counts.
  - A Phone break counts nothing.
  - Each "1 minute" or "5 minutes" override removes its whole granted window, from the tap until the re-shield or the session end.
  - Limits per session: Steady 2, Gentle unlimited (each one logged and removed), Locked none.
- **R8. Session limits.** User-started sessions are planned at 15 min–3h (15 min is the DeviceActivity minimum). Flow (count-up) sessions also cap at 3h, with a check-in at 90 min. No session credits more than its planned length.
- **R9. Daily caps.**
  - At most 6h per local day counts.
  - At most 2h of that can come from blocks that started on their own (Morning, wind-down, unconfirmed Study blocks).
  - Tapping Start on a Study block within its first 10 minutes makes it user-started.
  - Time over a cap stays in History, greyed, with its reason.
- **R10. Days and travel.**
  - Events store UTC instants plus the time zone.
  - Minutes count toward the local day they happened in, split at local midnight.
  - Scheduled blocks are clamped to their nominal length across daylight-saving and time-zone changes.
- **R11. Totals never go down.**
  - The ledger is append-only and replayed deterministically.
  - Deleting a session hides it but never removes an earned leaf.
  - Each day stores the rules version it was counted under, and rule changes apply only to future days.
- **R12. No Screen Time, no credit.** Without Screen Time permission, and on free-tier builds, hours saved stays 0 and no ladder counts unblocked sessions. The tab shows its "Needs Screen Time" state (§5.10).
- **R13. Secondary ladders.**
  - A *finished session* must meet all of these: user-started, planned at 20 min or more, reached its planned end (overrides allowed but subtracted). At most 4 count per day.
  - A *Focus streak day* has at least one finished session.
  - Any 2 days per calendar week (the locale's week) count as rest days automatically, and Away (F2) pauses the streak. Away is set for today or later, never back-dated.
  - Streak leaves use the best run.
  - A *Phone-free morning* or a *Bedtime kept* means that block ran to its end with no override, early end or Phone break.
- **R14. Never a source of credit:** usage thresholds, DeviceActivityReport numbers and the EU data-access API. These may only drive gentle hints, and only after device testing.

### 3.3 What members see
| Where | Copy |
|---|---|
| Definition (first use, then behind an info button) | "Time your chosen apps stayed locked while you were awake." |
| Home, day | Hero "2h 15m", caption "saved today · 41h in all" |
| Home, session running | Hero "18 min", caption "left in this session" |
| Next leaf | "Trident maple · 3h 20m to go" |
| Receipt | "50m saved · apps locked the whole time", or "45m saved · 5m unlocked, not counted" |
| Saved today sheet | Counted stretches ("Study · 14:00–15:10 · 1h 05m") plus greyed time with its reason ("Unlocked 5 min", "After bedtime", "Over today's 6h", "Protection was off") |
| How we count (5 lines) | "Counts only while your chosen apps are locked. Sleep doesn't count. Unlocks and phone breaks don't count. Overlaps count once. Up to 6 hours count each day." |
| Week / lifetime | "9h 40m saved this week · 1h more than last" / "412 hours saved" |
| Feedback only | "Back to studying 3 times" (receipt and weekly recap; never currency) |

Never shown:
- conversions ("= 3 books");
- "you would have wasted";
- goal percentages or composite scores;
- any claim that the number is a measured drop in screen time.

## 4. Reward table

### 4.1 Categories (replaces all 19)
155 leaves = 114 hours saved + 40 secondary + 1 first leaf.

| Category id | Name | Unit | Rungs | Needs | Release |
|---|---|---|---|---|---|
| `first_leaf` | First leaf | step | 1 | — | Now (step 1) |
| `hours_saved` | Hours saved | hours | 114 (§4.2) | Screen Time | F1 |
| `sessions_finished` | Sessions finished | sessions | 1, 10, 25, 50, 100, 250, 500, 1000 | Screen Time | F1 |
| `focus_streak` | Focus streak | days (best run) | 3, 7, 14, 30, 50, 75, 100, 150, 250, 365 | Screen Time | F1 |
| `phone_free_mornings` | Phone-free mornings | mornings | 1, 7, 25, 50, 100, 200, 365 | Screen Time | F2 |
| `bedtime_kept` | Bedtime kept | nights | 1, 7, 25, 50, 100, 200, 365 | Screen Time | F2 |
| `rested_nights` | Rested nights | nights | 3, 14, 30, 60, 100, 175, 250, 365 | Apple Health | Sleep import |

- **`first_leaf`:** Sugar maple, "Plant your maple". Earned at the end of onboarding at any hour (D12 unchanged). It ships now, because onboarding reveals it. Until F1 restructures onboarding it is still awarded when onboarding saves the schedule, the step just before the sprout. From F1 on it no longer depends on the schedule.
- **`rested_nights`:** counts nights the NightLedger settles as `.onTime` (asleep by the target bedtime, from Apple Health only, D9). Its leaves follow the existing reveal schedule (held overnight, opened in the morning). It is never Home's automatic next leaf.

### 4.2 Hours-saved thresholds
1, 2, 3, 5, 7, 10, 13, 16, 20, 24, 28, 32, 36, 40, 45, 50, 55, 60, 65, 70, 75, 80, 85, 90, 95, 100, 110, 120, 130, 140, 150, 160, 168, 180, 190, 200, 210, 220, 230, 240, 250, 265, 280, 295, 310, 325, 340, 355, 370, 385, 400, 420, 440, 460, 480, 500, 520, 540, 560, 580, 600, 620, 640, 660, 680, 700, 720, 740, 760, 780, 800, 825, 850, 875, 900, 925, 950, 975, 1000, 1025, 1050, 1075, 1100, 1125, 1150, 1175, 1200, 1225, 1250, 1275, 1300, 1325, 1350, 1375, 1400, 1425, 1450, 1475, 1500, 1530, 1560, 1590, 1620, 1650, 1680, 1710, 1740, 1770, 1800, 1840, 1880, 1920, 1960, 2000.

That is 114 unique, ascending thresholds, roughly h_k ≈ k + 0.145k². Landmark rungs carry a line:
- 24h "A day back"
- 168h "A week back"
- 720h "A month back"
- 2,000h "A working year back"

### 4.3 Placement of the 155 species
- **Early and landmark rungs:** famous garden species (red, Japanese, Fullmoon, Norway, paperbark, trident and similar).
- **Top rungs:** the top 10 hours rungs and the top rung of each secondary ladder go to the catalog's most threatened maples on the IUCN Red List (CR first, then EN, then VU). Each is recorded in `species.json` with its category, assessment year and source URL. Leaf detail adds one dated, sourced line (for example "Fewer than 500 grow in the wild").
- **u-confidence species:** the 11 stay on late rungs and keep their Uncharted presentation (D3).
- **Families:** each ladder keeps a family where possible, as in `rewards.md`, and evergreens sit on consistency ladders (streak, mornings, bedtime).
- **The mapping itself** is generated as data in the implementation plan. Tests check that:
  - all 155 species are used exactly once;
  - no two leaves share a rung;
  - the threatened-species rule holds.

### 4.4 Tiers, pacing and rarity
- **Tiers** stay journey labels, derived by the existing rule (median unlock day for a committed member). They are recomputed with the new pacing model (`scratchpad/econ/sim3.py`, copied into `docs/design/` with the plan).
- **Modelled pacing** for a typical member (~1.9h a day credited):
  - about 14 leaves by day 7, 95 by year 1 and 129 by year 2;
  - 2,000h at about 2.9 years.

  Nobody reaches 2,000h before about 334 days.
- **Reveals:** at most 3 per session (the rest wait in the tray), and none at night.
- **Thresholds are frozen** before the "% of members" statistic goes live, after real daily credit has been checked in TestFlight. After that they can only be lowered.
- **The 6h cap** is the setting to revisit if testers studying in exam season object. 8h is the fallback.

### 4.5 Next leaf
- Home's automatic next leaf is the next `hours_saved` rung, unless the member has pinned another leaf.
- Secondary rungs show in Almost there and in leaf detail.
- §3.5's phase preference no longer applies to Home's pick.

## 5. Focus tab

**Tabs:** Home · Focus · Herbarium. Focus uses SF `timer` (outline, regular) as its symbol. The Rest tab is retired:
- the sleep schedule moves into Focus as the Bedtime block (§5.8);
- wind-down mode stays a full-screen cover, opened from Home's evening action or the Bedtime tile.

All screens follow spec §1: one hero per screen, calm dark design, amber only for rewards, sentence case, no red, and never the words "fail" or "quit".

### 5.1 Idle root
- **Header:** 44pt, "Focus" in `screenTitle`, with "History ›" as a `TextLink` (F2).
- **Hero ring:** 240–280pt.
  - A 2pt track and a 3pt season-tint arc ending in a 14pt silhouette of the next hours leaf.
  - Inside: the preset name and "50:00" in the hero numeral.
  - Dragging the leaf handle sets 15–180 min in 5-minute steps. A −/+ stepper is the accessible alternative.
- **Preset chips:** Study 50m · Quick 25m · Deep 90m · Read 30m · +, with the last-used one selected.
- **Lines under the chips:**
  - "Blocking 6 apps ›", with up to 5 app icons; opens the Blocking sheet;
  - "Counts toward Trident maple · 6h 40m of 8h" (13pt secondary);
  - an optional nearest exam, "Biology · 12 days" (F2).
- **Primary capsule:** "Start study · 50m". In Locked, it is hold-to-start.
- **Below the fold:**
  - the Schedules grid (§5.8, F2);
  - a "This week" strip, "4h 10m saved this week".
- **Time of day:** the tab adapts.
  - In the evening, the Bedtime tile moves first.
  - During wind-down and at night, the hero becomes the Bedtime status ("Wind-down · 38m until bed"). Starting a long session becomes a quiet link that suggests a short review instead.

### 5.2 Blocking sheet (`.large`)
- **Mode:** a segmented capsule with two choices.
  - "Block these": a block list.
  - "Only these": an allow list via `.all(except:)` for apps and web domains.
- **Named sets** are reused by presets and schedules: Distractions, Study apps and Bedtime to start.
- **Apple's picker** uses the iOS 26.2 title, header and footer overload, with the line "Maple never sees which apps you pick".
- **Token limit:** a counter, plus a nudge toward categories near the 50-token shield limit.
- **Footer:** apps on iOS's Always Allowed list and phone calls always stay open. "Only these" setup suggests adding essentials (Messages, Maps, banking).
- **Expired tokens** (`tokensDidExpire`) show "Some apps need choosing again". Maple never writes an empty set over a non-empty one.

### 5.3 Presets (`.large` editor)
- A preset holds:
  - **shape:**
    - Countdown;
    - Cycles: 25/5 ×4 with a 15-minute long break, or 50/10;
    - Flow: count-up with a 3h cap, suggesting a 5, 8 or 10-minute break depending on how long you've focused;
  - length and break plan, with "Breaks off your phone" (default) or "Phone break";
  - app set;
  - strictness;
  - sound (F2);
  - optional subject (F2).
- At most 6 presets, reordered by drag.
- **Strictness levels** (all free):
  - **Gentle:** unlimited overrides (each one subtracted). End early after a 5-second breathing ring.
  - **Steady (default):** 2 overrides per session, and from the second one a 10-second breath in Maple. End early is hold 3s, then a 15-second quiet countdown, with "Take a 5-minute break instead" offered when break time remains.
  - **Locked:** no overrides and no ending. One Emergency release per 7 days: hold to confirm; it ends this session only and keeps the minutes. The copy says honestly that Screen Time access can always be withdrawn in Settings.
- **Changing strictness:** tighter applies now, looser from the next day ("Steady starts tomorrow"). Nothing changes during a running session.

### 5.4 Running session (full-screen cover)
- **Background:** scene black with a faint season-tint bloom. A `chevron.down` button minimises the view while the session keeps running.
- **Header:** "Study · Chemistry ch. 4", plus the status row "Blocking 6 apps · Protection on".
- **Ring:** 280pt; the arc advances, showing "18:42" and "of 50m". The leaf rides the arc end, and "Trident maple · 6h 40m of 8h" ticks up each minute.
- **Cycles:** "Round 2 of 4". A break shows its own countdown ring with one off-phone suggestion (stand, look outside, water).
- **Bottom row:** a "Break" capsule when the plan allows, a sound button (F2) and an "End early" `TextLink`.
- **Display:**
  - dims to 50% after 30s;
  - under Reduce Motion the arc steps once a minute;
  - StandBy desk mode (F2).
- **Mini bar:** while a session runs, a `tabViewBottomAccessory` mini bar shows on Home and Herbarium.

### 5.5 Shield (system block screen)
- **Look:** background `#05070D`, with the next leaf's PNG (pre-rendered into the App Group) as the icon and no amber.
- **Title:** "{App} is resting".
- **Subtitle:** the member's intention ("Study · Chemistry ch. 4"), never a countdown.
- **Primary button:** "Back to studying" (`.close`).
- **Secondary button:** "Need it?" opens a submenu (iOS 26.4) with "1 minute", "5 minutes" and "End session".
- **Steady:** from the second override, the member is routed through Maple's 10-second breath (`openParentalControlsApp`, iOS 26.5), with a notification as the fallback.
- **Locked:** no secondary button.
- **Variants:** Morning, Bedtime and Study each have their own copy.
- **Logging:** every choice is written to the ledger.

### 5.6 End early (`.medium` sheet)
- **Copy:** "End this session?" and "32 minutes saved so far. They stay yours either way."
- **Friction** follows the strictness level (§5.3).
- **History** marks an early end with a neutral half ring.

### 5.7 Receipt (`.medium` sheet at session end)
- **Hero:** "50m", captioned "saved · 2h 10m today".
- **Breakdown:** "50m locked · 5m unlocked, not counted · 2 breaks" and "Back to studying 3 times".
- **Leaf:** the next-leaf hairline animates. If a leaf opened, a capsule shows "A new leaf opened · Open" by day, or "waiting in the morning" otherwise.
- **Reflection:** an optional one-tap "How did it go?" (Done, Partly, Not yet) and a "Next time, start with…" note that pre-fills the next intention.
- **Buttons:** primary "Done". Secondary "Again · 50m" or "Start break".

### 5.8 Schedules (F2)
- **Layout:** a 2-column grid of tiles below the ring. Each tile shows:
  - name, time range and days;
  - a status chip ("On now", "in 2h");
  - up to 4 app icons and its strictness.

  Inactive tiles show at 40%.
- **Morning:**
  - starts at the wake time for a chosen length (default 60 min);
  - counts within the 2h allowance;
  - running to its end with no override, early end or Phone break earns a Phone-free morning.
- **Bedtime:**
  - The wind-down (default 45–60 min before bed) is the counted part. It opens wind-down mode and earns Bedtime kept.
  - From bed to wake, apps stay locked but nothing counts.
  - The editor holds bedtime, wake time and wind-down length, so it is now the sleep schedule's home.
- **Study blocks:**
  - up to 6 weekday windows ("Mon–Thu 19:00–21:00 · Biology");
  - a 5-minute heads-up (opt-in) and a scheduled Live Activity;
  - tapping Start within the first 10 minutes gives full credit; otherwise the block shares the 2h allowance.
- **How blocks run:**
  - one repeating `DeviceActivitySchedule` per block, whose monitor checks the weekday, which keeps Maple under the 20-activity limit;
  - a scheduled Live Activity (`request(...start:)`) mirrors each block.
- **Missed starts:** show "Morning didn't start · Start now?" and count nothing for the missed part. Missing data is neutral.
- **Edits:** tighter now, looser from the next day, nothing during a running block.

### 5.9 History and Saved today
- **Saved today sheet (F1):** opened from Home's numeral or the receipt; §3.3 has its content.
- **History (F2):**
  - a Week/Month segmented control with one hero numeral;
  - 7 bars (white 70%) with season-tint dots on days with a finished session;
  - "By subject" rows;
  - sessions grouped by day with neutral full or half rings.
- **Session detail (F2):**
  - a timeline of locked time, breaks and unlocks;
  - credited minutes with their reasons;
  - the reflection, and retagging.
- **No league tables.**

### 5.10 Needs Screen Time
- **When it shows:** whenever authorization isn't `.approved`, and always on free-tier builds.
- **Content:** a designed primer explaining what blocking does and that Maple never sees which apps are chosen, with a "Turn on Screen Time" primary.
- **Plain timer:** a `TextLink` "Use as a plain timer" runs a session with no shields. The ring and receipt still work, but the receipt reads "Not counted · apps weren't locked", and nothing counts toward any ladder (R12).
- **Revoked access:** if access is revoked mid-session, the session continues as a plain timer, and the receipt shows "Protection was off from 14:32".

### 5.11 Outside the app
- **Live Activity and Dynamic Island (F1):**
  - the leaf, a minute-precision countdown (`.timer`), the ring and "6 apps resting";
  - a Break button and no End button;
  - `staleDate` shows "Session complete".
- **End-of-session notification (F1):** a local notification with a soft chime. It becomes Time Sensitive on the paid tier.
- **One App Intent (F2), `StartFocusSession`:** a `LiveActivityIntent` pinned to the main app. It powers:
  - a Control for Control Center, the Lock Screen and the Action Button (starts the default preset);
  - a small interactive widget with 2 preset buttons;
  - Lock Screen accessories for next-leaf progress;
  - App Shortcuts: "Start a {length} study session in Maple" and "How long is left in Maple".

  Starts are donated, so Siri Suggestions can learn the member's rhythm.

### 5.12 Subjects, exams and sounds (F2)
- **Subjects:** up to 8, each shown with a leaf from the member's own Herbarium (no colour coding). They can be renamed Projects.
- **Intention:** an optional one-line intention per session, shown on the running screen and the shield.
- **Exam countdowns:** up to 5, shown in days. They disappear after the date and never ask for a grade.
- **Sounds:** generated in code. Silence is the default, then Rain on leaves, Deep (brown), Soft (pink) and Brook.
  - They fade in at the start, crossfade at breaks and fade out at the end.
  - They pause when headphones disconnect.
  - "Under my music" mixes them under the member's own music.
  - Copy talks about masking and preference only, never brain claims.

## 6. Home changes
Only the NowBlock, the next-leaf row, the header streak and the actions change. The tree and caption are untouched.

**NowBlock and actions:**

| State | Numeral | Caption | Action |
|---|---|---|---|
| Morning block running | Time left, "38m" | "left of your phone-free morning" | None |
| Morning, with Apple Health | Last night's sleep (unchanged) | unchanged | unchanged |
| Morning, no sleep data | Saved yesterday, "1h 50m" | "saved yesterday · 41h in all" | None |
| Day | Saved today, "2h 15m" (or "0m") | "saved today · 41h in all" | "Start study · 50m" (the last-used preset). It starts at once; a long-press lists the other presets. |
| Session running (any phase except night) | Time left, "18 min" | "left in this session" | "Return to session" |
| Evening, wind-down, night | Unchanged | Unchanged | "Start wind-down" opens wind-down mode, as now |

- **Without Screen Time**, the day numeral is the countdown to wind-down (today's "Day, before focus ships" row), and the action reads "Turn on blocking".
- **Header streak:** shows the Focus streak (SF `leaf.fill`, amber, hidden under 2) instead of the bedtime run. The Streak sheet shows the Focus streak with its rest days.
- **WeekBlock:** markers show days with a finished session (filled season tint) instead of on-time nights.
- **The ScoreBlock** stays out of scope.

## 7. Onboarding
The order moves to phone habits first. The parked `m1-schedule-onboarding` steps are reused.

1. **Welcome:** one line on hours saved.
2. **What pulls you in:** pick the apps to block (FamilyActivityPicker into the Distractions set). On free-tier builds this step shows the Needs Screen Time primer and continues.
3. **Your days:** wake time, bedtime and sleep need, giving the proposed schedule. It feeds the awake window (R6) and the Bedtime block.
4. **Apple Health primer:** optional, for Rested nights.
5. **Notifications primer:** optional, for session ends and block heads-ups.
6. **Plant your maple:** the first leaf is revealed (D12).

There is no questionnaire before the first timer.

## 8. Notifications
- **Allowed:**
  - session end;
  - an opt-in 5-minute heads-up per scheduled block;
  - an opt-in wind-down reminder;
  - the shield fallback for the 10-second breath.
- **Never sent:**
  - morning notifications (rewards.md's rule stands, which settles the conflict on `m1-notifications`);
  - streak nagging;
  - "come back" pushes.

## 9. Architecture

### 9.1 MapleCore (pure, `Sendable`, no SwiftUI)
- **`FocusEvent`:** an append-only ledger event. It carries:
  - an id;
  - kind, one of `sessionStarted`, `shieldApplied`, `checkpoint`, `breakStarted`, `breakEnded`, `phoneBreakStarted`, `phoneBreakEnded`, `overrideGranted`, `overrideEnded`, `backToStudy`, `sessionEnded(reason)`, `authorizationLost`, `tokensExpired`, `blockStarted`, `blockEnded`;
  - a session or block id;
  - the wall date, continuous uptime, boot session id and time zone identifier;
  - the source process.
- **`FocusPlan`:** shape, planned length, break plan, strictness, selection summary (category count, app and site count, mode) and kind (`userStarted` or `scheduled`). It is frozen into `sessionStarted`.
- **`FocusLedger`:** replays events into sessions with their segments. It is deterministic and idempotent: merging two copies of the ledger and replaying gives the same result.
- **`HoursCredit`:** applies R1–R10 to the replayed sessions, the awake windows (from the sleep schedule) and the calendar. It produces per-local-day credit with labelled counted and uncounted stretches (for Saved today and History) and the rules version.
- **`FocusCounters`:** produces the counter values for `hours_saved`, `sessions_finished`, `focus_streak` (best run), `phone_free_mornings` and `bedtime_kept`. These feed the existing `CollectionSnapshot.raise(_:to:)` high-water marks, so `LeafEngine` stays unchanged.
- **`ShieldReconciler`:** given the time, the running session, scheduled blocks and the current store states, it returns the actions to apply or clear for each named store. It is pure and unit-tested. Every process that can act runs it.
- **`RewardCategoryID` / `RewardCategoryInfo` / `rewards.json`:** re-cut to the 7 categories in §4.1. `ShippedFeatures` gains F1 and F2 (replacing the old M2/M3 focus and Screen Time gates).

The NightLedger is kept. Its settled nights now raise only `rested_nights`, and vitality (§4.8) still reads them.

### 9.2 MapleServices (MainActor)
- **`FocusSessionStore`** (`@Observable`): start, break, Phone break, override bookkeeping and end. It writes the ledger, drives `BlockingService` and the Live Activity, and recounts credit on every change.
- **`BlockingService` (protocol):**
  - `ScreenTimeBlockingService` (paid tier): FamilyControls authorization, `ManagedSettingsStore` with one named store per purpose (`session`, `morning`, `bedtime`, `study-<id>`), cleanup via `deleteStores`, and token refresh on `tokensDidExpire`.
  - `UnavailableBlockingService` (free tier, Release): always reports not authorized.
  - `PreviewBlockingService` (DEBUG): drives every shield state, including revocation and expired tokens, for the simulator and tests.
- **`AppSetStore`:** named app sets (opaque `FamilyActivitySelection` data, encoded in the App Group) plus their qualifying summary.
- **`PresetStore`:** presets, the last-used one, and strictness-change scheduling.
- **`FocusScheduleStore` (F2):** Morning, Bedtime and Study blocks, registered with `DeviceActivityCenter`.

### 9.3 Extensions (paid tier: real entitlements; free tier: built without Family Controls, inert)
| Target | Bundle suffix | Job |
|---|---|---|
| `MapleMonitor` | `.monitor` | `DeviceActivityMonitor`: applies or clears block shields, writes `blockStarted`, `shieldApplied`, `checkpoint` and `blockEnded`, and runs the reconciler. No SwiftUI or SwiftData (~6 MB memory ceiling). |
| `MapleShield` | `.shield` | `ShieldConfigurationDataSource`: reads the session's intention and the leaf PNG from the App Group. |
| `MapleShieldAction` | `.shieldaction` | `ShieldActionDelegate`: back to studying, the 1- and 5-minute overrides, End session and the breath hand-off. Writes events and runs the reconciler. |
| `MapleWidgets` | `.widgets` | Live Activity (F1); Control, widget and accessories (F2). Free tier works. |
| `MapleReport` | `.report` | Later: the display-only trend card. Requested with the others so approval covers it. |

- **One file per process:** each process appends events to its own small JSON-lines file in the App Group (`ledger-app`, `ledger-monitor`, `ledger-shieldaction`). The app merges them by event id. No two processes ever write the same file.
- **Signing:** free-tier builds must still sign on a free account, so no embedded target carries a Family Controls entitlement in the free tier (the existing `Maple-$(MAPLE_TIER).entitlements` pattern, extended per target).

### 9.4 Reliability layer (F1)
- Sessions apply shields from the app itself. Schedules use the monitor, with the reconciler as a backstop.
- **The reconciler runs** on every foreground, every extension callback and every intent.
- **Every session has redundant end paths:** the DeviceActivity interval end, the reconciler and the Live Activity's end date.
- **Status and escape hatch:** a "Protection on" status row, and an always-available "Release all apps" in the running screen and in Settings.
- **Authorization** is checked on every launch and in every extension callback. Losing it writes `authorizationLost` at the last checkpoint.
- **Missed scheduled starts** produce the "Start now?" prompt, never a penalty.

### 9.5 iCloud sync (paid tier; ships with F2)
- **Container:** the CloudKit private database, one zone.
- **What syncs:** ledger events and `LeafUnlock` records (species id, date, season, colourway, revealed, seen), with encrypted fields. Never Screen Time usage, app tokens or health data.
- **Merge:** by event id and species id. Replay keeps totals monotonic. Reveal state merges with "revealed wins".
- **Quota or network failures** leave the local ledger as the source of truth, and the write is retried. The Privacy screen discloses what syncs.
- **Free tier:** device only.

## 10. Testing
- **Logic first, with Swift Testing.** `FocusLedger`, `HoursCredit`, `FocusCounters` and `ShieldReconciler` get deterministic replay tests. Cases include:
  - overlaps and union;
  - midnight splits and daylight-saving days;
  - time-zone travel;
  - both caps, including the start-tap conversion;
  - overrides (whole window removed) and Phone breaks;
  - missed callbacks;
  - revocation, deletion and token expiry;
  - clock changes;
  - reboots;
  - Flow cap and check-in;
  - finished-session and streak rules (rest days, best run);
  - merge idempotence.
- **Reward table tests:** 155 species used once, unique rungs, the threatened-species placement rule, ladder totals, and ascending thresholds.
- **UI:** new DEBUG launch arguments for every Focus state (idle, running, break, receipt, needs Screen Time, revoked, shield preview, each strictness), checked in the simulator with screenshots and documented in `docs/debug-launch-arguments.md`.
- **On-device checklist (paid tier):**
  - App Group writes from the monitor and shield-action extensions (the riskiest assumption, so test it first);
  - the monitor's memory headroom;
  - `openParentalControlsApp` under individual authorization;
  - applying shields from background intents;
  - stuck-shield recovery with the app killed and the phone off Xcode;
  - `requireAutomaticDateAndTime` in Locked.
- **Gates:** zero warnings, Swift 6 strict concurrency, and the whole suite green.

## 11. Build order
Each step gets its own implementation plan.

1. **Reward re-cut and parked M1 merge.**
   - Re-cut `rewards.json` and the category code to §4.
   - Merge `m1-schedule-onboarding`, `m1-health-import` and `m1-notifications`, adapted to §7 and §8: Rested nights from Apple Health; no morning notification.
2. **F1 Focus core.**
   - The MapleCore ledger, credit and reconciler.
   - The Focus tab: idle root, Blocking sheet, presets, strictness, running session, end early, receipt, Saved today and Needs Screen Time.
   - Shield and shield-action extensions, Live Activity, end notification and Home changes.
   - Ladders: `first_leaf`, `hours_saved`, `sessions_finished` and `focus_streak`.
   - On the free tier everything runs against `PreviewBlockingService` in DEBUG.
3. **F2 Focus schedules and surfaces.**
   - Morning, Bedtime and Study blocks with the monitor extension.
   - Ladders: `phone_free_mornings` and `bedtime_kept`.
   - Subjects, exams, Away, sounds, History and session detail.
   - The Control, widget and App Shortcuts, StandBy and iCloud sync.
4. **Later, each behind a flag:**
   - SharePlay "Study together now";
   - Study Circles;
   - a Focus filter;
   - spaced review reminders;
   - "Due soon" from Reminders and Calendar;
   - a weekly look-back and a learned allow list;
   - the Screen Time trend card;
   - "What works for you" insights and CSV export;
   - a Study key (NFC or QR);
   - an AlarmKit "Ring when done";
   - recorded ambient places;
   - class timetable blocks (no credit);
   - the anonymous Library line;
   - a term recap card.

**Paid program:** file Family Controls Distribution requests for all 5 bundle IDs (app, `.monitor`, `.report`, `.shield`, `.shieldaction`) on day one. Approval takes weeks.

## 12. Changes to existing documents (made during step 1)
- **`docs/design/spec.md`.** Add an Overrides entry pointing here. Then:
  - D10 becomes Home · Focus · Herbarium;
  - §2.2 is re-homed (Rest rows move to Focus);
  - §3.4 follows §6, and §3.5 follows §4.5;
  - §8.1 Rest is retired in favour of §5;
  - D12's first leaf no longer needs a saved sleep schedule.
- **`docs/design/rewards.md`.** Replace the model, categories and pacing with §3–§4:
  - the 3h/day and 10h/week focus caps and the 10-minute minimum become R8–R9;
  - "Health- and Screen Time-derived unlocks stay on device" becomes §9.5's private sync of Maple's own records;
  - the 7-day delay for selection changes becomes R3's freeze at session start.
- **`docs/architecture.md`.** Replace the milestones with §11's order. The remaining later items stay as they are, with M9 Social becoming the Study Circles item.
- **`CLAUDE.md`.** Point "Product direction" at this spec instead of saying the tab is still being designed.

## 13. Not doing
- **Leaderboards, rankings, hour percentiles or live grids.** They lower intrinsic motivation, drive padding and cheating, and are flagged for teens.
- **Withering, dying or sad companions; failure copy; red.**
- **Coins, shops, paid streak repair or resets, buying leaves, seasonal leaves.**
- **Ads, weekly plans, or paywalled blocking, strictness, allow lists or session length** (Guideline 4.10).
- **Camera rooms, matching with strangers, free-text chat or feeds** (Guideline 1.2, teen safety, and they would push Maple into iOS 27's Social Media allowance).
- **Flashcards, to-do or planner systems, an in-app AI tutor.** Maple allows Anki, Quizlet and ChatGPT instead of copying them.
- **Approach B or C** as a source of credit, and the app-and-website-usage capability.
- **`denyAppRemoval` by default, Shortcuts redirects, or hiding apps.**
- **Binaural beats, "40 Hz", focus-boost or ADHD claims, licensed lo-fi.**
- **A push server for the timer, `LongRunningIntent`, or silent-audio keep-alive** (Guideline 2.5.4).
- **Teacher or school dashboards** (DPLA 3.3.3(P)).
- **Composite scores, motion-sensor inference, self-reported baselines or manual time entry.**
- **AI-generated art.**

## 14. Risks
- **Extension writes:** monitor and shield-action writes to the App Group are undocumented by Apple. They are tested first on the paid tier, and the ledger design depends on them.
- **DeviceActivity reliability** on iOS 26–27 (missed or early callbacks, dormant extensions). Mitigated by app-applied session shields, the reconciler, "Start now?" and neutral missing data.
- **Stuck shields** would make the phone partly unusable. Mitigated by redundant end paths and "Release all apps".
- **The label can still be challenged.** Mitigated by the strict definition, receipts and the no-conversion rule, and by never marketing the number as a measured reduction.
- **The paid program gates** 146 of the 155 leaves (everything except Rested nights and the first leaf) and all device testing. The Needs Screen Time primer has to convert well.
- **The pacing model** rests on assumed usage profiles. Validate it in TestFlight and freeze thresholds before rarity goes live.
- **Scope:** the F1 and F2 split, and flags for everything later.
- **Opal is recovering** (October review average 3.47), so its weak moment may not last.
