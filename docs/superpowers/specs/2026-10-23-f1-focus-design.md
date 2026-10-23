# F1 Focus core: design

Status: approved by the owner section by section (2026-10-12 to 2026-10-23). This written version is waiting for the owner's review.

**How it relates to the focus spec.** This is the detailed design for build step 2 (F1) of `2026-10-11-focus-hours-saved-design.md`, called "the focus spec" below. The focus spec was amended in place on the same day, so the two documents agree (§10 lists every edit). Detail that exists only here is binding for F1.

**Sources.**
- **A 7-agent review of the focus spec** (2026-10-12):
  - five loophole hunts, covering credit, the iOS platform, UI, architecture, and wellbeing with App Review;
  - two competitor studies.

  The research page is private to the owner.
- **Interactive mockups**, kept as standalone pages:
  - `docs/design/mockups/f1-timer.html`: the minute-marks timer and its finish;
  - `docs/design/mockups/f1-focus-screens.html`: every F1 screen.

## 1. Scope

### 1.1 F1: built now and checked in the simulator against the preview blocker
- **Tabs:** Home · Focus · Herbarium.
  - The Rest tab is retired.
  - The sleep schedule becomes a Settings row ("Sleep schedule · 23:00 → 07:00") that opens the existing `ScheduleEditor`. It has to stay editable because it feeds the awake window (R6).
  - Wind-down mode still opens from Home's evening action.
- **Focus tab** (§5):
  - start screen with the minute-marks dial (§4), preset chips, intention line and Blocking line;
  - presets with strictness (Gentle, Steady, Locked);
  - running session and locked break;
  - end early and emergency release;
  - receipt as the session's final frame;
  - Saved today;
  - Needs Screen Time with a plain timer.
- **First session:** preselects Quick (25m), so the first finished-session leaf comes quickly.
- **Home** (§5.10): hours saved today, a running session's time left with "Return to session", the Focus streak in the header with its sheet, and Start (hold-to-start for Locked).
- **Live Activity and Dynamic Island:** display only, with no buttons. This keeps App Intents out of F1.
- **Notifications** (§6): session end, plus the opt-in daily study reminder.
- **Logic:**
  - the session ledger;
  - per-day credit;
  - the counters for `hours_saved`, `sessions_finished` and `focus_streak`;
  - the pure cores that the F1-paid extensions will wrap.
- **Free builds:** Home stays on Rested nights, and Focus offers only the plain timer, which counts toward nothing (R12).

### 1.2 F1-paid: a short step after the account joins the paid program
1. **On-device tests first** (§8.3). Extension writes to the App Group come before anything that depends on them.
2. **`ScreenTimeBlockingService`:**
   - Apple's picker;
   - real shields with read-back;
   - the 50-token cap;
   - handling first-run `tokensDidExpire` (about 30% of first selections hit it).
3. **Extensions:**
   - `MapleMonitor`, which ends sessions and re-locks after unlocks while Maple is closed;
   - `MapleShield`, the look of the blocked-app screen;
   - `MapleShieldAction`, its "Need it?" buttons.
4. **Other features:**
   - onboarding's "What pulls you in" step;
   - the Control Center start, which pulls `StartFocusSession` forward from F2;
   - Time Sensitive end alerts (paid accounts only).
5. **App Store housekeeping:**
   - the Productivity category (`Config/Maple.xcconfig` says `healthcare-fitness` today);
   - a privacy manifest;
   - the privacy-policy link;
   - the age rating.

### 1.3 Moved to F2
- the Flow (count-up) timer, Cycles and Phone breaks;
- History and deleting sessions;
- `requireAutomaticDateAndTime` in Locked;
- the "This week" strip below the start screen.

Schedules, subjects and exams, sounds, iCloud sync and widgets were already F2.

## 2. Owner decisions (2026-10-12 to 2026-10-23)

| # | Question | Decision |
|---|---|---|
| F1-1 | Locked's way out | **Always there, but slow.** The emergency release is a 10-second hold, then one slow breath. It ends the session, keeps its minutes and never counts as finished. It replaces "one per 7 days", because a teen must never be trapped. |
| F1-2 | Flow timer | **F2.** It is the weakest shape for integrity. |
| F1-3 | Sleep schedule once Rest is retired | **A Settings row.** |
| F1-4 | Daily study reminder | **Opt-in, off by default.** It never mentions leaves, streaks or missed days. |
| F1-5 | Running time | **Calm minutes:** "31m", with seconds only in the last minute. |
| F1-6 | Timer look | **C, minute marks** (§4), with the gold finish. Chosen over the growing leaf and the night-sky arc. |
| F1-7 | Finished session | **At least 20 locked awake minutes, making up at least ¾ of the planned focus time; at most 3 count a day** (was 4). |
| F1-8 | Rest days | **2 a week, automatic, and they count toward the run's length.** |
| F1-9 | Paid program | **Joined once F1's screens and features are done.** F1-paid follows. |
| F1-10 | Plans | **F1 is two implementation plans:** F1a (logic) and F1b (screens) (§9). |

## 3. Counting-rule changes
These are made in place in focus spec §3. In short:
- **Only confirmed blocks count (R2).** Time starts at a `shieldApplied` event written after Maple reads its own block back. Any Maple process may write it. Preview events never count.
- **Qualifying selections (R3).**
  - "Block these" needs at least one category, or 3 or more apps or sites.
  - "Only these" needs no allowed categories and at most 20 apps or sites.
  - Across every active store, Maple never shields more than 50 app or 50 web tokens. Above that, iOS silently blocks nothing.
- **Credit stops at the last proven checkpoint (R4).**
  - The receipt says "Couldn't confirm the block after 14:10" instead of guessing.
  - "Release all apps" ends credit.
- **The clock keeps running while the phone sleeps (R5).** Sessions are timed with `ContinuousClock` plus the boot id from `kern.bootsessionuuid`. Time after the last event is provisional: it shows on the dial but never reaches the counters.
- **Days and the sleep window (R6, R10).**
  - Each session lands on the day it really happened: the last trusted time plus the continuous time elapsed since.
  - A Maple day (the existing `PhaseWindows.Day`) turns over inside the sleep window, not at midnight.
  - Each session freezes its awake window and time zone when it starts.
  - Bedtime edits made after 18:00 apply from the next night.
  - The sleep window used for credit is at least 6 hours.
  - Sessions the member starts count from 60 minutes before wake.
- **Totals never go down (R11).**
  - Each Maple day's credit is stored on its own.
  - A day can be recounted upward for 3 days, then it is frozen.
  - Counters are the sum of the days.
- **Finished sessions and the streak (R13).**
  - The new finished-session bar: F1-7.
  - The rest days: F1-8.
  - Days before a run starts never use the rest-day allowance.
  - Today stays pending until it ends.
  - Progress shows the current run, and the leaf uses the best run.
  - A broken run reads "Best: 21 days", never "streak lost".
  - Neither an emergency release nor "Release all apps" ever counts as finished.
- **When leaves open.** A leaf carries the moment its session ended. It is held until morning only if that session ended during wind-down or at night.
- **Wording.**
  - Landmark rungs lose their figurative lines: "Save 24 hours", not "Save 24 hours · A day back".
  - No week-against-week comparisons.

## 4. The minute-marks dial (`MinuteDial`)
One component serves the start screen, the running session, breaks, holds and the receipt. The whole Focus tab reads as one object.

### 4.1 Geometry
- **Size:** about 75% of the screen width (≈300pt on a 393pt screen). It shrinks with HeroFit, down to 220pt.
- **Marks:** one per minute up to 1 hour, one per 2 minutes up to 2 hours, and one per 3 minutes up to 3 hours. A dial never has more than 60 marks.
- **Placement:**
  - Mark *i* of *n* sits at *i*/*n* of a full turn, clockwise from 12 o'clock.
  - Every 5th mark is long.
  - Proportions on a 200-unit box: long marks run from radius 80 to 92, short marks from 84 to 92. The stroke is 1.6 (2.2 for the current mark), with round caps.
- **Leaf dot:** radius 2.6 at radius 99, placed at the minute where the next hours leaf opens, if that falls within the session.
  - It is season tint until it is reached, then amber.
  - It is hidden on the receipt.

### 4.2 Mark states
| State | Used for | Colour |
|---|---|---|
| plan | start-screen preview | `textPrimary` 42% |
| ahead | time still to come | `textPrimary` 16% |
| lit | passed minutes | `textPrimary` 88% |
| current | the minute in progress | season tint, brightening from 35% to 100% through its minute |
| rest | break time left | `budNeutral` (#C9D3E3) 78% |
| gap | minutes that didn't count (receipt) | `textPrimary` 9% |
| hold | press-and-hold progress | `textPrimary` 100% |
| off | Needs Screen Time | `textPrimary` 10% |

### 4.3 Centre
- **The next hours leaf**, drawn with `LeafView`'s skeleton style and `progressFill`. F1b extends `progressFill` to draw two tones and an edge. The fill is progress toward that leaf within its rung:
  - softer gold for the part saved before this session;
  - brighter gold for this session;
  - a light edge at the fill line.
- **When the leaf opens mid-session:**
  - it turns fully gold, with dark veins and a soft glow;
  - the bloom behind the dial cross-fades from season tint to gold;
  - the leaf line reads "Field maple is ready · yours at the end", with the amber bud.
- **The numeral** is the hero (SF Rounded semibold), with its unit in secondary. A caption sits under it.
- **On the receipt** the leaf grows to fill the centre. The numeral shrinks to about 72% beneath it.

### 4.4 Time text (`FocusTimeText`)
| Situation | Text |
|---|---|
| 60 s or more left | Whole minutes, rounded up: "32m" |
| Under 60 s left | "0:SS", seconds rounded up. 60 seconds always reads "1m", never "0:60". |
| Lengths on the start screen | "50m", "1h", "1h 30m" |
| Receipt | "50m", captioned "saved · 2h 10m today" |
| Lock Screen / Dynamic Island | "32m left" / "32m" |

### 4.5 Setting the length
- **Turning the dial:** 30° of turn changes the length by 5 minutes, so one full turn is an hour.
  - The range is 15 minutes to 3 hours.
  - Each step plays a `.selection` haptic, and the marks re-lay out.
  - Turning changes only this session. Holding a chip edits its preset.
- **Chips** set their preset's length.
- **Hint:** the caption reads "turn to set the length" until the member has turned the dial once. After that it shows the preset name.
- **VoiceOver:** an adjustable element ("Session length, 50 minutes"), where swiping up or down changes the length by 5 minutes.

### 4.6 Motion
- **All motion uses only transform and opacity.** Nothing animates layout, font size or filters. This rule came from the timer prototype, where animating those stuttered.
- **During a session:**
  - lit marks fade in over 0.3s;
  - the current mark brightens continuously;
  - when the leaf opens, the leaf, glow, dot and bud ease over 0.6s.
- **Finish:** it plays once, when the session ends.
  - The marks sweep gold one after another (14ms apart, 0.9s each).
  - The leaf grows into the centre with a slight overshoot (0.8s).
  - The glow pulses once, and a gold ring ripples out (1.5s).
  - The leaf line, then Done and Again, rise in (0.4s and 0.6s delays).
  - A soft impact haptic plays.
- **Reduce Motion:**
  - no sweep, ripple or overshoot;
  - states cross-fade;
  - the marks step once a minute.
- **Dimming:** the running screen dims to 50% after 30 seconds (focus spec §5.4).

### 4.7 Other surfaces
- **Live Activity and Dynamic Island:** these can't draw the marks.
  - They use the system `ProgressView(timerInterval:)` ring.
  - The text is `.timer(countingDownIn:maxPrecision: .seconds(60))`.
- **Holds show their progress on the dial:** marks in the hold state fill clockwise while the button is pressed.

## 5. Screens
Every screen has a DEBUG launch argument (§8.2). The mockup page shows each one.

### 5.1 Focus start (Steady)
- **Layout, top to bottom:**
  - the title "Focus";
  - the dial: plan marks, the leaf dot, the next leaf in the centre as it is now, "50m", and the caption (§4.5);
  - the chips: Study 50m · Quick 25m · Deep 90m · Read 30m · +;
  - "What's this for?", an optional intention, offering the last 3 as chips;
  - "Blocking 6 apps · Steady ›", with up to 4 app icons, which opens the Blocking sheet;
  - the counts line, "Your Field maple opens at minute 35". If the session won't reach the leaf, it reads "Counts toward Field maple · 35m to go".
  - The primary capsule, "Start study · 50m". The verbs are: study, a quick session, a deep session, reading.
- **Nothing scrolls** at default text sizes.
- **States:**

| State | What changes |
|---|---|
| No app set | The line reads "Choose apps to block ›", and the capsule "Choose apps". |
| Selection doesn't qualify (R3) | "Blocking 2 apps · add 1 to count ›", with the counts line hidden. |
| Expired tokens | "Some apps need choosing again ›" |
| First ever | The counts line shows the definition from focus spec §3.3. |
| Evening, wind-down | The capsule is dimmed. |
| Crosses bedtime | "Counts until bed at 23:00" |
| After bedtime | "After bedtime · this won't count" |
| Today's cap reached | "6h counted today · more won't add" |
| Session running, minimised | The dial is live and can't be turned, the chips and lines are hidden, and the capsule reads "Return to session". |
| Shields couldn't be applied | "Couldn't lock your apps · Start as a plain timer?" |

### 5.2 Focus start (Locked)
- The Blocking line reads "· (lock) Locked ›".
- The capsule reads "Hold to start · 50m". It needs a 1.5-second hold:
  - the marks fill around the dial while it is held;
  - they drain back if it is let go early.
- A plain tap shows "Hold to start. Locked can't end early." for 4 seconds.
- Locked never starts with one tap anywhere, including Home's Start and the receipt's "Again".

### 5.3 Needs Screen Time
- **When it shows:** whenever blocking isn't available. The plain timer is offered instead.
- **Layout:**
  - the dial with its marks off;
  - a card: "Lock apps with Screen Time", then "Maple keeps your chosen apps resting while you focus. It never sees which apps you use.";
  - the primary, "Turn on Screen Time";
  - a link, "Use a plain timer · it won't count".
- **Free builds can't request Screen Time.** There the card reads "Blocking arrives in a later version", and only the plain timer is offered.

### 5.4 Running session
- **Header:** "Study · Chemistry ch. 4" (preset · intention), with "6 apps resting" under it.
- **Dial:** passed minutes lit, the current mark tinted, and the leaf dot. The centre shows the leaf, "32m" and "left of 50m".
- **Leaf line:** "Field maple · 17m to go".
- **Buttons:**
  - "Take a break", when the preset has one;
  - "End early" (Gentle and Steady) or "Emergency release" (Locked).
- **Other behaviour:**
  - ⌄ minimises the session, which keeps running;
  - the screen dims after 30 seconds;
  - a season-tint bloom sits behind the dial, turning gold once the leaf opens.

### 5.5 Break
- **Rules:**
  - Apps stay locked and the break counts (O5).
  - A preset can include one 5-minute locked break. Study and Deep include one by default; Quick and Read don't.
- **Header:** "Break · apps stay locked".
- **Dial:** it switches to the break, with one rest-colour mark per 10 seconds, going out one by one. The centre shows "4m" and "left of your break".
- **Below the dial:**
  - one suggestion for something to do away from the phone, rotating between standing up, looking out of a window and getting water;
  - "The break counts. Your session picks up at 18m."
- **Ending:** "Back to studying" ends the break early. When the break runs out, a soft tap plays and the session resumes.

### 5.6 End early (Gentle, Steady)
- **A sheet over the session:**
  - "End this session?";
  - "18 minutes saved so far. They stay yours either way.";
  - the primary, "Keep going".
- **Steady:**
  - "Hold to end" needs 3 seconds;
  - then a quiet 15-second countdown, "Ending in 15s", which "Keep going" still cancels;
  - "Take a 5-minute break instead" is offered while the break is unused.
- **Gentle:** a 5-second breathing ring, then the session ends.

### 5.7 Emergency release (Locked)
- **A full screen:** "Emergency release", with "Study · Locked" under it.
  - The dial is in the hold state, with "10s" and "hold to release" in the centre, changing to "keep holding" while pressed.
  - The copy reads "Ends this session now. Your 18 minutes stay yours, but it won't count as finished."
- **"Hold to release" needs 10 seconds.** Letting go early drains the progress.
- **Then the breath:**
  - "Breathe in" for 4 seconds, then "and out" for 4 seconds, while the bloom slowly swells;
  - then the ended state: "18m", "saved · they stay yours", "Session ended. It won't count as finished." and "Done".
- **No limit:** it is always available, with no weekly allowance. Each use is logged as `sessionEnded(emergencyRelease)`.

### 5.8 Receipt (the session's final frame)
- **The finish (§4.6),** then:
  - "50m", captioned "saved · 2h 10m today";
  - the leaf line, "A new leaf is waiting · Open". A held leaf reads "A new leaf will open in the morning".
  - the breakdown, "Locked the whole time · 1 break";
  - an optional one-tap "How did it go?" (Done · Partly · Not yet);
  - "Done", and "Again · 50m" (a hold for Locked).
- **Tapping the numeral** opens Saved today.
- **Variants:**
  - **Unlocked minutes:** shown as gap marks, with "45m locked · 5m unlocked, not counted".
  - **Plain timer:** all marks in the gap state, with "Not counted · apps weren't locked".
  - **Lost confirmation:** "Couldn't confirm the block after 14:10".
  - **After bedtime:** "After bedtime · this didn't count".
  - **Over the cap:** "Over today's 6h · this didn't add".

### 5.9 Saved today
As in focus spec §3.3. Its reasons include "Couldn't confirm the block" in place of "Protection was off".

### 5.10 Home
As in focus spec §6, with these details:
- **Day:** "1h 20m", captioned "saved today · 41h in all". Start is a hold for Locked.
- **Next-leaf row:** the skeleton leaf, the name, "35m to go" and the hairline.
- **Header streak:** a drawn amber leaf with the current run, hidden under 2. It opens the streak sheet: the current run, the best run, and the rest days used this week.
- **Session running:** "18m", captioned "left in this session", with "Return to session".
- **The mini bar** shows only on Herbarium, because Home already shows the session.

### 5.11 Lock Screen and Dynamic Island
- **Lock Screen:** the leaf, "32m left", "Study · 6 apps resting" and the ring.
- **Compact:** the leaf, "32m" and the ring.
- **Expanded:** the leaf, "32m left", the intention and the ring.
- **No buttons.** Once `staleDate` passes, it shows "Session complete".

### 5.12 Settings
- "Sleep schedule ›".
- "Daily study reminder", with an on/off switch and a time.
- "Release all apps", for stuck shields only. During a session it goes through that strictness level's own end path, so in Locked it is the emergency release. On F1 builds it clears the preview stores.

## 6. Notifications
- **Session end:**
  - a new `ReminderKind.sessionEnd`, scheduled at start for the planned end;
  - exempt from ReminderPlan's night rule;
  - cancelled by an early end or an emergency release;
  - kept by `ReminderUpkeep`;
  - copy: "Session done · 50 minutes saved", with a soft chime;
  - Time Sensitive in F1-paid.
- **Daily study reminder:**
  - a new `ReminderKind.studyReminder`, off by default;
  - the member picks the time when turning it on (16:00 suggested), and it must fall before wind-down;
  - once a day, and skipped on days a session has already started;
  - copy: "Ready to study? Your apps can rest for a while." It never mentions leaves, streaks or missed days.
- **Still never sent:** morning notifications, streak nagging and "come back" pushes.

## 7. Architecture

### 7.1 MapleCore/Focus (pure, `Sendable`, nonisolated)
- **`FocusEvent`:**
  - the focus spec's kinds, plus `shieldCleared(reason)` and `.unknown`, so older builds skip newer events;
  - a stamp: wall date, continuous nanoseconds, boot id and zone id;
  - a `source` (`app`, `monitor`, `shieldAction` or `preview`);
  - the session id and the device id.
- **`FocusPlan`:** the focus spec's fields, plus:
  - the frozen awake window (bedtime, wake and wind-down instants) and zone;
  - `SelectionSummary.qualifies`, which applies R3.
- **`FocusLedger`:**
  - merges by event id, order-free and idempotent;
  - orders by boot, then continuous time, then id;
  - replays sessions, crediting only between events of the same boot.
- **`HoursCredit`:** applies R1–R10 to give a `DayCredit` per Maple day, plus labelled counted and uncounted stretches, in integer seconds.
- **`FocusBook`:** a new field of `CollectionSnapshot` beside `nights`, saved atomically with the counters. It holds one `DayCredit` per Maple day:
  - seconds and auto-started seconds;
  - finished sessions and streak status;
  - the schedule used and the rules version.

  Open days are recounted upward until 3 days after they end, then frozen.
- **`FocusCounters`:**
  - returns dated marks (instant, day, values) in time order;
  - returns both the current and the best streak.

  `CollectionSnapshot.applyFocus(marks:)` applies each mark with `at: mark.instant`, so unlock dates, tended days and the reveal hold follow when credit was earned. `LeafEngine` is unchanged.
- **Pure cores:** `ShieldReconciler`, `ShieldActionCore` and `MonitorCore`.
  - They take no action on an unknown state.
  - They are idempotent.
  - F1-paid's extensions are thin adapters around them.
- **Dial logic:** `DialLayout` (mark count and the leaf dot) and `FocusTimeText` (§4.4).
- **`FocusTimeSource`:** injected.
  - Live: `ContinuousClock` plus the boot id.
  - Scripted: a shifted clock that keeps running, for tests and demos. `MapleClock.fixed` would freeze a session.
- **Edits to existing code:**
  - `NowState` gains the preset, saved time (today, yesterday and in all), the current streak and `BlockingCapability`;
  - `NextLeafPicker`;
  - `ReminderPlan` gains `.sessionEnd` and `.studyReminder`;
  - `ShippedFeatures`, whose F1 flag is flipped last;
  - the reward generator drops the landmark lines.

### 7.2 MapleStorage (new target, nonisolated)
- **`MapleContainer`,** moved from MapleServices:
  - The App Group key is read from each target's own Info.plist.
  - Extensions get no silent fallback.
  - A one-time migration moves data out of today's fallback folder.
- **`JSONLinesFile`:**
  - before each append, it makes sure the file ends in a newline;
  - reading tolerates damage: bad lines are skipped and logged, and the file is never set aside;
  - files use `.completeUntilFirstUserAuthentication` protection.
- **`LedgerDirectory`:**
  - one file per process: `ledger-app`, `ledger-monitor`, `ledger-shieldaction`;
  - preview data lives under `Demo/`.

### 7.3 MapleActivity (new small target)
`FocusActivityAttributes`, shared by the app and the widget extension.

### 7.4 MapleServices/Focus (MainActor)
- **`FocusSessionStore`:**
  - turns commands into events, replays them and calls `applyFocus`;
  - drives blocking, the Live Activity and the end notification;
  - if the ledger can't be read, it holds an unknown state and neither writes nor clears.
- **`BlockingService`:**
  - **The protocol boundary:** no FamilyControls or ManagedSettings types cross it. A selection is opaque `Data` plus a `SelectionSummary`.
  - **Methods:** `perform([ShieldOp])` returns verified results, plus `probe()`, `armEndGuard`, `armReshield`, `releaseAll()` and an `AsyncStream` of signals.
  - **`MapleBuild`:** reads the tier from a `MapleTier` Info.plist key, as `MapleHealthBackgroundDelivery` does today.
  - **`BlockingCapability`:** keeps what the build can do (`unavailableInBuild`, `preview`, `screenTime`) separate from whether permission was granted. Permission is probed, not read from `authorizationStatus`.
  - **`PreviewBlockingService` (DEBUG):**
    - runs only on demo stores, in a sandbox folder;
    - its events carry `source: preview`, which live replay never credits;
    - it injects the real failure modes: 51 tokens reading back nil, revocation with a stale status, late callbacks, failed writes and expired tokens.
  - **`UnavailableBlockingService`:** free Release builds.
  - **`ScreenTimeBlockingService`:** F1-paid.
- **Other stores:** `PresetStore`, `AppSetStore`, and `LiveActivityController` (a protocol plus a fake).

### 7.5 MapleDesign
`MinuteDial` (§4) and `HoldButton`. The leaf reuses `LeafView`'s skeleton and `progressFill`.

### 7.6 App
- **`App/Features/Focus`:** every screen in §5, plus a DEBUG fake picker.
- **Elsewhere in the app:** Home's changes, the Settings rows, and the tab change in `RootView`.
- **New target:** `MapleWidgets` (the Live Activity only), plus `NSSupportsLiveActivities` on the app.

### 7.7 F1-paid additions
- **Extension targets:** thin adapters over the pure cores.
- **Monitor activities:**
  - one-off activities per session: `s.<id>`, from start to the planned end, with `repeats: false`;
  - per re-lock: `r.<id>`, at least 15 minutes long.
  - Unique names keep a late callback from clearing another session.
- **Writing:**
  - `shieldApplied` is written only after the read-back succeeds;
  - processes write before acting: an event is logged before a shield is cleared, and a failed write means nothing is cleared.
- **Token cap:** 50 tokens across all stores, enforced when a selection is saved and again in the reconciler.
- **Credit depends only on the app's own writes** until the App Group write test passes on a device.

## 8. Testing

### 8.1 Logic (Swift Testing, tests written first)
- **Ledger files:**
  - merging is order-free and idempotent;
  - a torn tail is skipped, and the next append still decodes;
  - unknown kinds round-trip;
  - an unreadable ledger leaves the store in the unknown state.
- **Credit:**
  - 3,600 seconds unlocks the 1h leaf; 3,599 seconds doesn't;
  - overlapping sessions count once;
  - a 23:40–00:30 session falls on one Maple day;
  - daylight-saving days (23h and 25h);
  - a flight mid-session;
  - setting the clock forward or back, and a UTC+14 round trip;
  - 50 minutes of simulated sleep earn full credit;
  - after a reboot, only uptime with a read-back counts;
  - a killed app reopened after the end;
  - credit with no later event is provisional only;
  - revocation earns credit up to the last checkpoint;
  - a plain timer, and preview events in live stores, earn 0.
- **The awake window:**
  - a bedtime edit after 18:00 leaves today unchanged;
  - a sleep window under 6h is widened to 6h;
  - wake − 60 min;
  - after bedtime counts 0.
- **Caps and overrides:**
  - the 6h cap;
  - an override removes its whole window;
  - a locked break counts.
- **`FocusBook`:**
  - counters never fall after a delete, a rules change, a lost ledger or an older build;
  - a late subtraction doesn't stall later days;
  - closed days are frozen after 3 days.
- **Dating:**
  - a Day session applied in the Evening isn't held;
  - a leaf earned at 20:30 opens and one earned at 22:30 is held (bedtime 23:00, wind-down from 22:15);
  - nothing unlocks before the session's closing checkpoint.
- **Finished sessions:**
  - Gentle with four overrides in 20 minutes: not finished;
  - access revoked at minute 1: not finished;
  - after bedtime: not finished;
  - over the daily cap: finished;
  - at most 3 count a day;
  - an emergency release and "Release all apps": never finished.
- **The streak:**
  - five sessions a week keep the run going, and a third miss in a week breaks it;
  - locale weeks starting on Sunday and on Monday;
  - best run 14 with current run 2 shows "2 of 30".
- **R3:**
  - 2 apps don't qualify; 3 apps or 1 category do;
  - "Only these" with an allowed category doesn't qualify;
  - 51 tokens are refused.
- **The reconciler:** takes no action on an unknown state, clears expired sessions and is idempotent.
- **Dial and text:**
  - mark counts at 15, 50, 60, 65, 120, 125 and 180 minutes;
  - the leaf dot's angle;
  - "1m" versus "0:59";
  - the "1h 30m" format.
- **System:**
  - on a free build, Rested nights is the next leaf, there is no Screen Time prompt, and Day shows the wind-down countdown;
  - a `-MapleDemo*` launch writes nothing to the live files;
  - the end notification survives `ReminderUpkeep`;
  - replaying 3 synthetic years stays within budget.

### 8.2 UI
- **DEBUG launch arguments** (documented in `docs/debug-launch-arguments.md`):
  - `-MapleDemoTab focus`, which replaces `rest`;
  - `-MapleDemoFocus idle|noSet|smallSet|expired|running|dimmed|break|minimised|ended|endedAway|endEarly|emergency`;
  - `-MapleDemoFocusAt <min>`;
  - `-MapleDemoStrictness gentle|steady|locked`;
  - `-MapleDemoScreenTime approved|notDetermined|declined|restricted|unavailable|revoked|plain|failStart`;
  - `-MapleDemoReceipt clean|unlocked|early|plain|revoked|bedtime|capped|leaf|leafNight`;
  - `-MapleDemoSaved typical|capped|empty`;
  - `-MapleDemoLiveActivity running|ended`;
  - `-MapleDemoNotify sessionEnd`;
  - `-MapleDemoPresent blocking|preset|endEarly|saved|streak`.
- **Screenshots:** each state is checked in the simulator.
- **Accessibility:**
  - VoiceOver: the dial is adjustable, and every hold has a VoiceOver alternative (a double-tap and hold);
  - Reduce Motion (§4.6);
  - Dynamic Type for the numeral and the lines, with nothing scrolling at default sizes.

### 8.3 F1-paid on-device checklist
- **First:** App Group writes from the monitor and shield-action extensions.
- **The focus spec's list:**
  - the monitor's memory headroom;
  - `openParentalControlsApp` under individual authorization;
  - applying shields from background intents;
  - stuck-shield recovery with the app killed and the phone off Xcode.
- **Added by the review:**
  - whether revoking access wipes the store;
  - `isActive` across processes;
  - `startMonitoring` from the shield-action extension;
  - one-off schedules that cross midnight;
  - Apple's picker inside a sheet;
  - installing a free build that contains the extensions;
  - individual authorization on a teen's child account;
  - session timing with the phone asleep.

### 8.4 Gates
- zero warnings;
- Swift 6 strict concurrency;
- the whole suite green;
- a Release build containing no Preview or Demo symbols.

## 9. Implementation plans
Each plan has its own branch and pull request.

1. **F1a, logic.**
   - **Contents:**
     - MapleStorage and MapleCore/Focus (§7.1–7.2);
     - `FocusBook` and `applyFocus(marks:)`;
     - the `ReminderPlan` kinds;
     - the MapleServices stores with preview blocking;
     - the landmark-line change in `Scripts/generate-rewards.py`, `rewards.json` and its test;
     - all §8.1 tests.
   - **No UI.**
   - **Branch:** `maanvik/f1a-focus-logic`.
2. **F1b, screens.**
   - **Contents:**
     - `MinuteDial` and `HoldButton`;
     - every §5 screen;
     - Home and the Settings rows;
     - the tab change (Rest retired);
     - MapleActivity and the Live Activity widget;
     - wiring the notifications;
     - the DEBUG arguments and their doc;
     - flipping `ShippedFeatures` for F1 last.
   - **Branch:** `maanvik/f1b-focus-screens`.
3. **F1-paid:** its own plan once the account joins the paid program. It starts with the on-device App Group write test.

## 10. Edits made to the focus spec with this document
- **Header:** status and a pointer here.
- **O5:** the Phone break is F2.
- **§3.2 rules:**
  - R2 (read-back, any process, preview never counts);
  - R3 (the "Only these" limits and the 50-token cap);
  - R4 (Release all apps, proven checkpoints);
  - R5 (`ContinuousClock`, provisional credit, day placement);
  - R6 (the Maple day, frozen windows, 18:00 edits, 6h minimum, wake − 60);
  - R10 (the Maple day boundary);
  - R11 (`FocusBook`);
  - R13 (finished sessions, rest days, best and current run).
- **§3.3:** the week line has no comparison, Home's running time reads "18m", and "Couldn't confirm the block" replaces "Protection was off".
- **§4.2:** landmark lines removed.
- **§5:**
  - §5.1: the dial replaces the ring, and the "This week" strip moves to F2;
  - §5.3: Flow, Cycles and the Phone break move to F2, and Locked's emergency release changes;
  - §5.4: the dial and calm minutes, and the mini bar on Herbarium only;
  - §5.7: the receipt is the final frame;
  - §5.10: "Couldn't confirm" wording;
  - §5.11: no Live Activity buttons in F1.
- **§6:** the drawn streak leaf, calm minutes, and hold-to-start for Locked.
- **§7:** F1 keeps today's onboarding, and "What pulls you in" comes with F1-paid.
- **§8:** the session-end and daily study reminder kinds.
- **§9:** MapleStorage, `FocusBook`, `BlockingCapability`, the preview sandbox, `shieldCleared`, `source`, the extensions in F1-paid, and end paths that don't include the Live Activity.
- **§10:** points here for F1's tests.
- **§11:** step 2 is split into F1a, F1b and F1-paid.
- **§14:** Opal's recovery.

## 11. Research corrections
- **Opal has largely recovered** (4.72★ overall), so the focus spec's risk line about its weak moment is out of date and has been updated.
- **Forest's reviews have averaged about 2.05★ since its September 2026 redesign,** and Focus Friend is rising. A calm, honest timer that never punishes is the opening.
