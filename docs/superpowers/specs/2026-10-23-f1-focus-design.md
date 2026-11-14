# F1 Focus core: design

Status: approved by the owner section by section (2026-10-12 to 2026-10-23). Revised on 2026-10-23 after a 10-agent review of the F1a and F1b scopes. The owner delegated the fixes, so the decisions that review forced (F1-11 to F1-26 in §2.2) were made by Claude on the owner's behalf. They are flagged for review, and §12 lists the questions still open.

**How it relates to the focus spec.** This is the detailed design for build step 2 (F1) of `2026-10-11-focus-hours-saved-design.md`, called "the focus spec" below. The focus spec was amended in place, so the two documents agree (§10 lists every edit). Detail that exists only here is binding for F1.

**Sources.**
- **A 7-agent review of the focus spec** (2026-10-12):
  - five loophole hunts, covering credit, the iOS platform, UI, architecture, and wellbeing with App Review;
  - two competitor studies.

  The research page is private to the owner.
- **A 10-agent review of this design** (2026-10-23). Five reviewers covered F1a (credit, data, architecture, code fit and improvements), and five covered F1b (UX, accessibility, system integration, code fit and improvements).
- **Interactive mockups**, kept as standalone pages:
  - `docs/design/mockups/f1-timer.html`: the minute-marks timer and its finish;
  - `docs/design/mockups/f1-focus-screens.html`: the F1 screens. §5.13 to §5.17 have no mockup, and the owner reviews them in the simulator.

## 1. Scope

### 1.1 F1: built now and checked in the simulator against the preview blocker
- **Tabs:** Home · Focus · Herbarium.
  - The Rest tab is retired.
  - The sleep schedule becomes a Settings row ("Sleep schedule · 23:00 → 07:00") that opens the existing `ScheduleEditor`. It has to stay editable because it feeds the awake window (R6).
  - Wind-down mode still opens from Home's evening action.
- **Focus tab** (§5):
  - start screen with the minute-marks dial (§4), preset chips, intention line and Blocking line;
  - presets with strictness (Gentle, Steady, Locked), and their editor;
  - the Blocking sheet, with a DEBUG fake picker;
  - running session and locked break;
  - end early and emergency release;
  - receipt as the session's final frame;
  - Saved today and the streak sheet;
  - Needs Screen Time with a plain timer.
- **First session:** preselects Quick (25m), so the first finished-session leaf comes quickly.
- **Home** (§5.10):
  - hours saved today;
  - a running session's time left with "Return to session", in every phase;
  - the Focus streak in the header, with its sheet;
  - Start, which is a hold for Locked and opens the Focus tab when the start screen has something to say.
- **Live Activity and Dynamic Island:** display only, with no buttons. This keeps App Intents out of F1.
- **Notifications** (§6): session end, plus the opt-in daily study reminder.
- **Logic:**
  - the session ledger;
  - per-day credit;
  - the counters for `hours_saved`, `sessions_finished` and `focus_streak`;
  - the pure cores that the F1-paid extensions will wrap.
- **Free builds:**
  - Home stays on Rested nights.
  - Focus offers only the plain timer, which counts toward nothing (R12). Once chosen it is remembered, and the Focus tab goes straight to it (F1-29).
  - The copy is in §5.3.

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
4. **Storage for extensions:**
   - `ShieldActionCore` and `MonitorCore`, the pure cores the extensions wrap;
   - a small `active-session.json` the extensions read;
   - the rule that extensions never fall back to a private folder;
   - a one-time move of data out of today's fallback folder.
5. **Other features:**
   - onboarding's "What pulls you in" step;
   - the Control Center start, which pulls `StartFocusSession` forward from F2;
   - Time Sensitive end alerts (paid accounts only).
6. **App Store housekeeping:**
   - the Productivity category (`Config/Maple.xcconfig` says `healthcare-fitness` today);
   - a privacy manifest;
   - the privacy-policy link;
   - the age rating.

### 1.3 Moved to F2
- the Flow (count-up) timer, Cycles and Phone breaks;
- History and deleting sessions;
- `requireAutomaticDateAndTime` in Locked;
- the "This week" strip below the start screen;
- a one-night schedule override ("Tonight I'm up until 00:30");
- a "Rest 10m" suggestion after about 2 hours of back-to-back sessions.

Schedules, subjects and exams, sounds, iCloud sync and widgets were already F2.

## 2. Decisions

### 2.1 Owner decisions (2026-10-12 to 2026-10-23)
| # | Question | Decision |
|---|---|---|
| F1-1 | Locked's way out | **Always there, but slow.** The emergency release is a 10-second hold, then one slow breath. It ends the session, keeps its minutes and never counts as finished. It replaces "one per 7 days", because a teen must never be trapped. |
| F1-2 | Flow timer | **F2.** It is the weakest shape for integrity. |
| F1-3 | Sleep schedule once Rest is retired | **A Settings row.** |
| F1-4 | Daily study reminder | **Opt-in, off by default.** It never mentions leaves, streaks or missed days. |
| F1-5 | Running time | **Calm minutes:** "31m", with seconds only in the last minute. |
| F1-6 | Timer look | **C, minute marks** (§4), with the gold finish. Chosen over the growing leaf and the night-sky arc. |
| F1-7 | Finished session | **At least 20 locked awake minutes, making up at least ¾ of the planned focus time; at most 3 count a day** (was 4). |
| F1-8 | Rest days | **2 a week, automatic, and they count toward the run's length.** F1-13 says how. |
| F1-9 | Paid program | **Joined once F1's screens and features are done.** F1-paid follows. |
| F1-10 | Plans | **F1 is two implementation plans:** F1a (logic) and F1b (screens) (§9). |

### 2.2 Decided on the owner's behalf after the review (2026-10-23)
F1-27 to F1-31 are the owner's own, from 2026-10-29, answering questions the F1b final review raised. F1-32 to F1-36 are the owner's too, from 2026-11-14, after using the build in the simulator.

| # | Question | Decision |
|---|---|---|
| F1-11 | Breaks | **Inside the planned length.** The countdown keeps running and the end never moves, so the notification, the Live Activity and F1-paid's monitor all stay fixed. A break that would pass the end is cut short at the end. |
| F1-12 | When leaves open | **Held until morning only when the unlock happens in wind-down or at night.** Evening unlocks open at once. `RevealSchedule` changes, and so do `docs/design/spec.md` and `docs/core-api.md`. This applies to sleep leaves too. |
| F1-13 | Rest days | **They only bridge gaps.** A missed day becomes a rest day once a later finished day follows it. A run has at most 2 rest days in any 7 days in a row. Misses since the last finished day neither count nor break the run while the allowance still covers them. One session can't earn a 3-day leaf. |
| F1-14 | Qualifying selection (R3) | **Any non-empty "Block these" qualifies** (was a category or 3 apps). "Only these" keeps its limits, and the 50-token cap stays. A member who blocks the one app that pulls them in is doing exactly what Maple asks. |
| F1-15 | Shortest session | **20 minutes** (was 15). A finished session needs 20 locked minutes, so a 15-minute plan could never finish. |
| F1-16 | End notification | **"Session done · Study, 50 minutes",** never "saved", because its words are fixed before the result is known. A plain timer reads "Timer done · 50 minutes". |
| F1-17 | Free builds | **The copy reads "This version of Maple can't lock apps. The timer still runs, but it won't count."** Screen Time leaves read "Not available in this build", with no button. |
| F1-18 | Gold during a session | **Recorded as an override in `docs/design/spec.md`,** because amber is otherwise for earned rewards only. Gold appears only over counted marks. A session that counted nothing finishes in white. |
| F1-19 | Private text | **Intentions live in `session-notes.json`,** which the member can edit and erase. The ledger never holds free text, and logs never hold content. |
| F1-20 | Home's Start | **No long-press preset menu.** Start begins the last-used preset in one tap (a hold for Locked) only when the start screen has nothing to warn about. Otherwise it opens the Focus tab with that preset selected. |
| F1-21 | Locked's promise | **"Hold to start. Locked ends early only by emergency release."** The honest explanation sits in the strictness chooser (§5.13). Steady's and Locked's timings are unchanged. |
| F1-22 | Holds and accessibility | **Every hold has a named accessibility action.** It starts a visible countdown of the same length that can be cancelled. |
| F1-23 | Notification permission | **Asked once, at the first session start,** if iOS hasn't asked yet. Settings gets a "Session end" switch, on by default. |
| F1-24 | Undesigned screens | **Designed in §5.13 to §5.17 without mockups:** the preset editor, the Blocking sheet, the streak sheet, intention entry and large text. The ended-away receipt is in §5.8. |
| F1-25 | Home before the day's first session | **The lifetime total, "41h", captioned "saved in all · none yet today",** instead of a large "0m". |
| F1-26 | Launches | **Live, demo and sandbox** (§7.6). Demo launches keep everything in memory. The DEBUG sandbox keeps its own files and credits preview events, so a whole session can be tried end to end. |
| F1-27 | The Live Activity during a break | **"Study · break until 14:28"** on the Lock Screen and in the expanded view, read aloud as "Study, break until 14:28", in the app's clock format ("2:28 PM" in en_US). With Maple suspended nothing updates the activity when the break ends, so "break until" stays true afterwards, where "Break · back at 14:28" didn't. The app's own break screen is unchanged (§5.11). Owner, 2026-10-29. |
| F1-28 | An intention typed and then swiped away | **Saved, exactly as Return saves it:** trimmed, at most 60 characters, and a blank field means no intention. A field that was cleared still removes the intention at once (§5.16). Owner, 2026-10-29. |
| F1-29 | The plain timer in a build that can't block | **Remembered.** In a build that can never block, the member's first "Use a plain timer · it won't count" is saved in Settings, and from then on the Focus tab goes straight to the plain timer's start screen, which keeps its "Plain timer · apps aren't locked" line. A build that can block still asks again after each start, because Screen Time may be turned on (§1.1, §5.3). Owner, 2026-10-29. |
| F1-30 | A plain timer's strictness | **Gentle, whatever its preset.** A plain timer locks nothing, so Locked's and Steady's exit costs mean nothing for it: it starts with one tap and no hold, the start screen shows no Locked line, and End early is Gentle's, with no emergency release and no 15-second countdown. Sessions that lock apps are unchanged (§5.2, §5.6, §5.7, §5.12, §5.13). Owner, 2026-10-29. |
| F1-31 | A receipt shown the next day | **"saved · 2h 10m that day"**, with that day's total, only when the session's Maple day is earlier than the shown day and the shown day's window has opened (wake − 60). Between bedtime and that moment it still says "today". Today's receipts keep "today" (§5.8). Its numeral then opens "Saved that day", with that day's sessions (§5.9). Owner, 2026-10-29 and 2026-11-12. |
| F1-32 | End early asks twice | **The sheet's way out leads to a breath, then a second question; only "End session" there ends the session** (§5.6). The breath takes the session's place: one slow breath for Gentle, two for Steady. The 5-second ring and the 15-second "Ending in 15s" countdown are gone. Owner, 2026-11-14: the ring "doesn't seem very significant", and "after breathing part is done ask again". |
| F1-33 | Turning the dial | **The marks follow the finger between lengths, and a step is taken at its halfway point** (§4.5), so the dial settles on the nearer length. The length still moves in 5-minute steps. Owner, 2026-11-14: "make turning the dial more smoother". |
| F1-34 | The Focus tab's backdrop | **Still stars and a low glow in the season's tint** behind every Focus screen (§5.4). One still frame: nothing redraws through a session. Owner, 2026-11-14: "a lot of blank space when the timer is on". |
| F1-35 | Session buttons | **"End early" is a glass capsule beside "Take a break"** (§5.4), and End early's sheet is only as tall as what it says, in the session screen's own dark (§5.6). Owner, 2026-11-14. |
| F1-36 | Strictness in a free build | **The strictness chooser stays in the preset editor** in a build without Family Controls, where sessions run as plain timers. Owner, 2026-11-14: "dont hide it". |

## 3. Counting rules
The focus spec's R1 to R14 stand, with the changes below made in place there. F1a implements §3.1 to §3.5 exactly.

### 3.1 Events
- **What each event carries:**
  - an id;
  - a schema version `v`;
  - a kind and its fields;
  - the session id and the device id (a random UUID made once and kept in the container);
  - the writer (`app`, `monitor` or `shieldAction`) and that writer's sequence number `seq`, which only ever goes up;
  - the source (`live` or `preview`);
  - `affectsCredit`;
  - a stamp: the wall instant, the continuous time in nanoseconds (`ContinuousClock`'s base, which keeps running while the phone sleeps), a hashed boot id from `kern.bootsessionuuid`, and the time zone id.
- **Kinds in F1:**
  - `sessionStarted(plan)`;
  - `shieldApplied`, written only after Maple reads its own block back;
  - `shieldVerified`, a later read-back that succeeded;
  - `shieldLost`, a read-back that failed;
  - `breakStarted(seconds)` and `breakEnded`;
  - `overrideStarted(seconds)` and `overrideEnded`, from F1-paid's shield action, which the preview blocker can inject;
  - `sessionEnded(reason, verified)`, where the reason is `completed`, `endedEarly`, `emergencyRelease` or `releaseAll`;
  - `shieldCleared(reason)`;
  - `reflected(answer)`, with `allDone`, `partly` or `notYet`;
  - `sessionHidden`, reserved for F2.

  An older build keeps a kind it doesn't know as `unknown`. If that event affects credit, the session's credit stops at the last checkpoint before it.
- **Ids.** Events the app writes get a random UUID. Events that two processes might both derive (an end at the planned time, a clear) get a deterministic id built from the session id and the kind, so writing one twice is harmless. A second terminal event for a session is ignored.

### 3.2 Order and placement
- **Order.** Events sort by boot, then continuous time, then writer, then `seq`, then id. Boots are ordered by when they first appear in the app writer's own `seq`, which carries on across device ids on one install, or else by their first event's wall time; the device id only breaks ties.
- **Placement (trusted time).** Within one boot, every event is placed at the boot's anchor plus the continuous time elapsed since it. The anchor is the boot's first event's wall time. So changing the clock inside a boot moves nothing.
- **Across boots,** a boot's anchor is never earlier than the last placed event of the boot before it on the same device. So setting the clock back can't move a session onto an earlier day.

### 3.3 One session's credit
1. **Start.** Credit starts at `shieldApplied`, which is only ever written after a read-back of a qualifying selection (R2, R3). The countdown also runs from `shieldApplied`, not from the tap.
2. **Checkpoints.** A checkpoint is any later event of the session written right after a successful read-back: `shieldVerified`, `breakStarted`, `breakEnded`, and a `sessionEnded` marked `verified`. Credit runs to the last checkpoint.
3. **Boots.** Credit never crosses a boot. After a restart, it starts again at the first read-back in the new boot.
4. **The planned end** is `shieldApplied` plus the planned length. In the same boot this uses continuous time; in a later boot it uses placed time. A session proven all the way to its planned end credits exactly its planned length.
5. **Removed windows.** An override removes its whole window. Nothing after a `shieldLost`, or after an `unknown` event that affects credit, counts.
6. **The awake window** (R6) is frozen into the plan at start:
   - It runs from 60 minutes before last night's wake to tonight's bedtime: `PhaseWindows.Day.morning` to `.night`.
   - The schedule for each night is the one in force at 18:00 that evening (`NightLedger.schedule(for:current:)`), so edits after 18:00 apply from the next night.
   - A sleep window shorter than 6 hours is widened to 6 hours by moving that night's wake later.
   - A session that starts inside a sleep window takes the next day's window, so its minutes from 60 minutes before wake onward count.
7. **The day.** All of a session's credit belongs to the Maple day of its frozen window. Credit that overlaps another session's counts once. At most 6 hours count a day, and earlier time counts first.
8. **Whole seconds.** Credit is kept in whole seconds. The hours counter is `Double(totalSeconds) / 3600`, and it only ever moves through `raise`.
9. **Provisional time.** Time after the last checkpoint shows on the dial but never reaches the counters.
10. **Labels.** Every uncounted stretch carries a stable rule id, which Saved today and the receipt turn into words: `afterBedtime`, `beforeMorning`, `dailyCap`, `override`, `unconfirmed`, `plainTimer`, `notQualifying`, `overlap`.
11. **Sources.** Live launches credit only `live` events. The DEBUG sandbox also credits `preview` events, and only inside its own files.

### 3.4 Finished sessions and the streak
- **A finished session** meets all of these:
  - the member started it;
  - its selection qualified;
  - it ended `completed`, at its planned end (an early end, an emergency release or "Release all apps" never finishes);
  - it has at least 1,200 counted seconds before the daily cap;
  - those make up at least ¾ of its planned length.

  At most 3 count per Maple day, in the order they ended. A finished session belongs to the Maple day of its frozen window.
- **A focus day** has at least one finished session.
- **A run** is a sequence of Maple days that starts and ends on a focus day, where every day between focus days is a rest day. There are at most 2 rest days in any 7 days in a row.
- **The current run** is the run ending at the latest focus day. It stays alive while the misses since then, with today left out, would still fit the rest-day allowance. Once they can't, the current run is 0.
- **Today stays pending** until it ends.
- **The best run** is a high-water mark kept in `FocusBook`. Streak leaves use it; progress shows the current run. A broken run reads "Best: 21 days", never "streak lost".
- **Travel.** A gap of one day across a time-zone change is neutral: neither a miss nor a rest day.

### 3.5 Totals never go down (R11)
- **`FocusBook`,** a field of `CollectionSnapshot`, keeps one `DayCredit` per Maple day, keyed by the day label and the time zone:
  - each session's counted seconds and whether it finished, each kept as the higher of the old and new values;
  - the day's seconds (the sum, capped at 6 hours) and its finished count (at most 3);
  - when credit first appeared, the rules version, and when the day freezes.
- **Freezing.** A day can be recounted upward until 3 days after the later of its end and its first credit. Then it is frozen, and only its totals are kept.
- **Facts only.** The book stores facts, never a streak status. It also keeps the best run as a high-water mark, and a `baseline` for totals it can't recount.
- **Baseline.** When the book is missing or was dropped by an older build while the counters are above zero, the baseline becomes the counters minus what the replay recounts. New credit then adds on top instead of stalling.
- **Version 2.** `CollectionSnapshot` becomes version 2 and decodes field by field, tolerantly. A build never saves over a file whose version is newer than its own.
- **Counters** are the baseline plus the sum of the days, applied as dated marks (§7.2).

### 3.6 Other counting changes
- **R3:** any non-empty "Block these" qualifies (F1-14). "Only these" needs no allowed categories and at most 20 apps or sites. Across every active store, Maple never shields more than 50 app or 50 web tokens. Above that, iOS silently blocks nothing.
- **R4:** the receipt says "Couldn't confirm the block after 14:10" instead of guessing, and "Release all apps" ends credit.
- **R8:** sessions are planned at 20 minutes to 3 hours (F1-15).
- **When leaves open** (F1-12). A leaf carries the moment its credit was earned. It is held until morning only if that moment falls in wind-down or at night.
- **Leaf remainders** for hours round up to the next minute, so "1m to go" never shows for a leaf that is already earned.
- **Wording.**
  - Landmark rungs lose their figurative lines: "Save 24 hours", not "Save 24 hours · A day back".
  - The `sessions_finished` and `focus_streak` metrics, and the Herbarium definitions, follow §3.4.
  - No week-against-week comparisons.

## 4. The minute-marks dial (`MinuteDial`)
One component serves the start screen, the running session, breaks, holds and the receipt. The whole Focus tab reads as one object.

### 4.1 Geometry
- **Size:** about 75% of the screen width (≈300pt on a 393pt screen). It shrinks with HeroFit, down to 220pt.
- **Marks:** one per minute up to 1 hour, one per 2 minutes up to 2 hours, and one per 3 minutes up to 3 hours. A dial never has more than 60 marks.
- **Placement:**
  - Mark *i* of *n* sits at *i*/*n* of a full turn, clockwise from 12 o'clock.
  - Every 5th mark is long.
  - Proportions on a 200-unit box: long marks run from radius 80 to 92, and short marks from 84 to 92. Gap marks are shorter, from 86 to 92. The stroke is 1.6 (2.2 for the current mark), with round caps.
- **Leaf dot:** radius 2.6 at radius 99, placed at the minute where the next hours leaf would open.
  - `SessionForecast` (§7.2) decides that minute from what can still count: today's remaining cap, the frozen awake window and the overrides so far. The dot is hidden when the leaf is out of this session's reach.
  - It is season tint until it is reached, then amber.
  - It is hidden on the receipt.

### 4.2 Mark states
Colours are `MinuteDial` tokens in `Tokens.swift`, each with an Increase Contrast value.

| State | Used for | Colour | Increase Contrast |
|---|---|---|---|
| plan | start-screen preview | `textPrimary` 42% | 60% |
| ahead | time still to come | `textPrimary` 16% | 30% |
| lit | passed minutes | `textPrimary` 88% | 100% |
| current | the minute in progress | season tint, brightening from 55% to 100% through its minute | 100% |
| rest | break time left | `#C9D3E3` at 78% (the raw value, not a token) | 100% |
| gap | minutes that didn't count (receipt) | `textPrimary` 9%, drawn shorter | 22% |
| hold | press-and-hold progress | `textPrimary` 100% | 100% |
| off | Needs Screen Time | `textPrimary` 10% | 22% |

### 4.3 Centre
- **The next hours leaf**, drawn with `LeafView`'s skeleton style and `progressFill`. F1b extends `progressFill` to draw two tones and an edge.
  - The fill is progress within the leaf's rung: from the rung below (`LeafProgress.floor`) to its threshold, which is `LeafProgress.rungFraction`. Every other surface keeps using `fraction` (§12, question 7).
  - softer gold for the part saved before this session;
  - brighter gold for this session, counted time only;
  - a light edge at the fill line.
- **During a session,** the dial and Home's next-leaf row both read the store's display credit (counted plus provisional), so they agree. Only the counters unlock leaves.
- **When the leaf opens mid-session** (only after a checkpoint confirms the crossing):
  - it turns fully gold, with dark veins and a soft glow;
  - the bloom behind the dial cross-fades from season tint to gold;
  - the leaf line reads "Field maple is yours · it opens after this session" (or "… opens in the morning" when it will be held), with the amber bud.
- **The numeral** is the hero (SF Rounded semibold), with its unit in secondary. A caption sits under it.
- **On the receipt:**
  - When a leaf opened, it grows to fill the centre and the numeral shrinks to about 72% beneath it.
  - When none did, the leaf stays a skeleton showing this session's share, and doesn't grow.

### 4.4 Time text (`FocusTimeText`)
| Situation | Text |
|---|---|
| 60 s or more left | Whole minutes, rounded up: "32m" |
| Under 60 s left | "0:SS", seconds rounded up. 60 seconds always reads "1m", never "0:60". |
| Lengths on the start screen | "50m", "1h", "1h 30m" |
| Receipt | "50m", captioned "saved · 2h 10m today" |
| Lock Screen and Dynamic Island | The system's own timer text, plus a static "until 14:52" (§5.11) |
| Spoken | "32 minutes left", "45 seconds left", "1 hour 30 minutes" |

### 4.5 Setting the length
- **Turning the dial:** 30° of turn changes the length by 5 minutes, so one full turn is an hour.
  - The range is 20 minutes to 3 hours.
  - A step is taken at its halfway point (15°), so the dial settles on the nearer length when the finger lifts (F1-33).
  - Each step plays a `.selection` haptic.
  - The marks follow the finger between lengths: the ring is spaced for a number of marks that moves continuously with the turn, a mark fading in or out at 12 o'clock, and the leaf dot keeps its minute. When the finger lifts, or a chip is tapped, the ring glides to the length. Under Reduce Motion the marks step from one length's ring to the next.
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
- **Finish:** it plays once, when the session ends, and only if the member sees it within 10 minutes of the end.
  - The counted marks sweep gold one after another (14ms apart, 0.9s each). Marks that didn't count stay as gaps. A session that counted nothing sweeps white.
  - When a leaf opened, it grows into the centre with an ease-out, with no overshoot (0.8s).
  - The glow pulses once, and a gold ring ripples out (1.5s).
  - The leaf line, then Done and Again, fade in (0.4s and 0.6s delays, each at least 0.6s long).
  - A soft impact haptic plays.
- **Reduce Motion:**
  - no sweep or ripple;
  - states cross-fade;
  - the marks step once a minute.
- **Dimming** (§5.4):
  - After 30 seconds, only the bloom and the marks dim, to 50%.
  - There is no dimming under VoiceOver or Increase Contrast.
  - The first touch only wakes the screen.
  - Auto-Lock is left alone, so the phone can sleep as usual.

### 4.7 Other surfaces
- **Live Activity and Dynamic Island:** these can't draw the marks.
  - They use the system `ProgressView(timerInterval:)` ring.
  - The text is the system timer text, plus "until 14:52".
- **Holds:** while a hold-to-start or hold-to-release is pressed, its progress fills the dial's marks clockwise. When the dial is busy showing a lit session, the progress shows in the button instead.

### 4.8 Rendering
- **The dial is drawn** with `Canvas` from a value type, `DialFrame`. It holds the mark states, the current mark's brightness, the dot and the fill, so the drawing can be tested without a view.
- **Sampling.**
  - A running dial samples once a second.
  - The finish runs at 30fps for its 1.5 seconds.
  - Drawing pauses when the view is off screen or the app isn't active.

### 4.9 Accessibility
| Element | Read as | Actions |
|---|---|---|
| Start dial | "Session length, 50 minutes" | adjustable ±5 minutes |
| Running dial | "32 minutes left of 50. Field maple at minute 35." | Magic Tap returns to the session controls |
| Break dial | "4 minutes of break left. Back to studying at 14:28." | none |
| Receipt dial | "50 minutes saved. 2 hours 10 minutes today." | none |
| Hold buttons | "Hold to start, Locked 50 minutes" | a named action that starts a visible countdown (F1-22) |

Announcements come only at milestones: the leaf opening, the break ending and the session ending. They never come each minute.

## 5. Screens
Every screen has a DEBUG launch argument (§8.2). The mockup page shows §5.1 to §5.12.

### 5.1 Focus start (Steady)
- **Layout, top to bottom:**
  - the title "Focus";
  - the dial: plan marks, the leaf dot, the next leaf in the centre as it is now, "50m", and the caption (§4.5);
  - the chips: Study 50m · Quick 25m · Deep 90m · Read 30m · +;
  - "What's this for?", an optional intention (§5.16);
  - "Blocking 6 apps · Steady ›", with up to 4 app icons, which opens the Blocking sheet;
  - the counts line, "You'll reach Field maple at minute 35". If the session won't reach the leaf, it reads "Counts toward Field maple · 35m to go".
  - The primary capsule, "Start study · 50m". The verbs are: study, a quick session, a deep session, reading.
- **Nothing scrolls** at default text sizes. With more than 5 presets, the chip row scrolls sideways.
- **The Blocking line** names what the selection holds:

| Selection | Line |
|---|---|
| Block list of apps | "Blocking 6 apps" |
| Block list with categories | "Blocking 1 category and 2 apps" |
| Allow list | "Allowing 6 apps" |
| Allow list over 20 | "Allowing 24 apps · 20 or fewer count ›" |

- **States:**

| State | What changes |
|---|---|
| No app set | The line reads "Choose apps to block ›", and the capsule "Choose apps". |
| Selection doesn't qualify (R3) | "Allowing 24 apps · 20 or fewer count ›", with the counts line hidden. |
| Expired tokens | "Some apps need choosing again ›" |
| First ever | The counts line shows the definition from focus spec §3.3. |
| Wind-down | The capsule is dimmed but still works. |
| Crosses bedtime | "Counts until bed at 23:00" |
| After bedtime | "After bedtime · this won't count" |
| Today's cap reached | "6h counted today · more won't add" |
| Session running, minimised | The dial is live and can't be turned, the chips and lines are hidden, and the capsule reads "Return to session". |
| Locking | After Start, the capsule reads "Locking 6 apps…" until the read-back confirms the block. Then the header settles to "6 apps resting", with a soft haptic. |
| Shields couldn't be applied | "Couldn't lock your apps · Start as a plain timer?" |

- **Start readiness.** `StartReadiness` (§7.2) says whether a start can go straight ahead, or which of the states above needs the start screen. Home's Start and the receipt's Again use it (F1-20).

### 5.2 Focus start (Locked)
- The Blocking line reads "· (lock) Locked ›".
- The capsule reads "Hold to start · 50m". It needs a 1.5-second hold:
  - the marks fill around the dial while it is held;
  - they drain back if it is let go early.
- A plain tap shows "Hold to start. Locked ends early only by emergency release." for 4 seconds.
- A session that locks apps never starts Locked with one tap anywhere, including Home's Start and the receipt's Again.
- **A plain timer is never Locked** (F1-30). It locks nothing, so it is Gentle whatever its preset: from a Locked preset it starts with one tap, with no hold and no "Hold to start…" line, and it ends through Gentle's End early (§5.6). That includes "Start as a plain timer" after a lock that failed. One rule decides the strictness that applies (`Strictness.applying(to:)`), for the start screen, Home's Start, the receipt's Again and every way out.

### 5.3 Needs Screen Time
- **When it shows:** whenever blocking isn't available. The plain timer is offered instead.
- **Choosing the plain timer** (F1-29):
  - In a build that can never block, the first "Use a plain timer · it won't count" is remembered in Settings, across launches. From then on the Focus tab goes straight to the plain timer's start screen, which keeps its "Plain timer · apps aren't locked" line, so it stays honest; the free build's card no longer comes before every session. Existing members' settings read as not chosen.
  - In a build that can block, the choice lasts until the next start, because Screen Time may be turned on. Once Screen Time allows Maple, the start screen blocks again.
- **Every "Turn on Screen Time" in the app** (Home's needs-permission row, the Herbarium) opens this screen. Maple's page in iOS Settings has no Screen Time switch.
- **Layout:**
  - the dial with its marks off;
  - a card;
  - the primary, when there is one;
  - a link, "Use a plain timer · it won't count".
- **Card copy by state:**

| State | Card | Primary |
|---|---|---|
| Not asked yet | "Lock apps with Screen Time" · "Maple keeps your chosen apps resting while you focus. It never sees which apps you use." | "Turn on Screen Time" |
| Declined | "Screen Time is off for Maple" · "Turn it on to count your focus time." | "Turn on Screen Time" |
| Restricted (a parent manages Screen Time) | "Screen Time is managed on this iPhone" · "A parent can allow Maple in Screen Time settings." | none |
| No passcode | "Set a passcode to use Screen Time" | none |
| Free build | "This version of Maple can't lock apps" · "The timer still runs, but it won't count." | none |
| Revoked mid-session | The session continues as a plain timer, and the receipt shows "Couldn't confirm the block after 14:10". | none |

### 5.4 Running session
- **Header:** "Study · Chemistry ch. 4" (preset · intention), with "6 apps resting" under it. An allow list or a selection with categories reads "Apps resting". A plain timer reads "Plain timer · apps aren't locked".
- **Dial:** passed minutes lit, the current mark tinted, and the leaf dot. The centre shows the leaf, "32m" and "left of 50m".
- **Leaf line:** "Field maple · 17m to go".
- **First session only:** one line under the dial, "You can lock your phone. Maple keeps time."
- **Buttons:**
  - "Take a break", when the preset has one;
  - "End early" (Gentle and Steady) or "Emergency release" (Locked);
  - both are glass capsules, side by side, and stacked where they don't fit (F1-35).
- **Backdrop** (F1-34): behind every Focus screen, still stars over the background and a low glow in the season's tint rising from the foot of the screen. It is one still frame, so it costs a long session nothing.
- **Other behaviour:**
  - ⌄ minimises the session, which keeps running;
  - the screen dims after 30 seconds (§4.6);
  - a season-tint bloom sits behind the dial, turning gold once the leaf opens.
- **Relaunching** while a session runs, or opening the Focus tab, shows this screen. It is drawn from the store, so a killed app comes back to the same session.

### 5.5 Break
- **Rules:**
  - Apps stay locked and the break counts (O5).
  - A preset can include one 5-minute locked break. Study and Deep include one by default; Quick and Read don't.
  - The break sits inside the planned length (F1-11), so the session still ends at its planned end. A break that would pass the end stops at the end.
- **Header:** "Break · apps stay locked".
- **Dial:** it switches to the break, with one rest-colour mark per 10 seconds, going out one by one. The centre shows "4m" and "left of your break".
- **Below the dial:**
  - one suggestion for something to do away from the phone, rotating between standing up, looking out of a window and getting water;
  - "The break counts. Back to studying at 14:28."
- **Ending:** "Back to studying" ends the break early. When the break runs out, the session screen returns, and a soft haptic plays if the app is open. Nothing is sent while the phone is locked.

### 5.6 End early (Gentle, Steady)
- **A small sheet over the session,** only as tall as what it says, in the session screen's own dark (F1-35):
  - "End this session?";
  - "18 minutes saved so far. They stay yours either way." The minutes are counted seconds. At zero it reads "This session isn't counting toward leaves.";
  - the primary, "Keep going".
- **The sheet's way out:**
  - Gentle: "End session";
  - Steady: "Hold to end", which needs 3 seconds, and "Take a 5-minute break instead" while the break is unused (cut short at the planned end).
- **The breath** (F1-32) takes the session's place once the sheet has gone, with the tab bar tucked away:
  - "Breathe in" for 4 seconds and "and out" for 4, inside the session's own dial: once for Gentle, twice for Steady;
  - a soft disc fills the dial as the breath comes in and empties as it goes out, and the cool bloom swells with it (a transform and an opacity; under Reduce Motion only the opacity);
  - under the dial: "One slow breath before you decide." ("Two slow breaths…" for Steady);
  - "Keep going" is there from the first moment.
- **The second question,** when the breath is over:
  - the dial shows "18m" over "saved so far" ("19m" over "focused" when the session can't count);
  - "Still want to end?", with the line that says the minutes stay;
  - "Keep going", and "End session", which fades in where it has been waiting. The session ends only on that tap.
- **Leaving the foreground** during the breath or the question goes back to the session, as it cancels a hold.
- **A plain timer** always ends this way, as Gentle, whatever its preset's strictness (F1-30): no hold, one breath, and no emergency release.

### 5.7 Emergency release (Locked)
- **A full screen:** "Emergency release", with "Study · Locked" under it.
  - The dial is in the hold state, with "10s" and "hold to release" in the centre, changing to "keep holding" while pressed.
  - The copy reads "Ends this session now. Your 18 minutes stay yours, but it won't count as finished." With nothing counted, the middle sentence is left out.
- **"Hold to release" needs 10 seconds.** Letting go early drains the progress.
- **The release happens when the hold completes,** so the breath can't trap anyone.
- **Then the breath:**
  - "Breathe in" for 4 seconds, then "and out" for 4 seconds, while the bloom slowly swells;
  - then the ended state: "18m", "saved · they stay yours", "Session ended. It won't count as finished." and "Done".
- **No limit:** it is always available, with no weekly allowance. Each use is logged as `sessionEnded(emergencyRelease)`.
- **Never for a plain timer,** which locks nothing and ends through Gentle's End early whatever its preset (F1-30).
- **Holds cancel** when the app leaves the foreground.

### 5.8 Receipt (the session's final frame)
- **Header:** "Study · Chemistry ch. 4" over "Apps open again". There is no ⌄ on the receipt.
- **The finish (§4.6),** then:
  - "50m", captioned "saved · 2h 10m today". When the session's Maple day is earlier than the shown day and the shown day's window has opened (wake − 60), it reads "saved · 2h 10m that day", with that day's total (F1-31); VoiceOver reads "2 hours, 10 minutes that day", and the large-text line under the dial matches. Between bedtime and that moment it still says "today", so a finish past bedtime or a receipt opened in the small hours keeps it;
  - the leaf line (below);
  - the breakdown, "Locked the whole time · 1 break";
  - an optional one-tap "How did it go?" (All done · Partly · Not yet);
  - "Done", and "Again · 50m" (a hold for Locked; it uses start readiness).
- **Leaf line:**
  - no leaf: "Field maple · 1h 10m to go";
  - one leaf: "Field maple is yours · it opens after this session", or "… opens in the morning" when it is held;
  - more: "2 new leaves are yours".
- **Tapping the numeral** opens Saved today on the day of the total it shows ("Saved that day" when the caption says "that day", §5.9).
- **Endings:**

| Ending | Receipt |
|---|---|
| On time | As above. |
| Ended while away | Shown once, when the member next opens Maple. The finish plays only if the session ended within the last 10 minutes; otherwise the final frame shows still. |
| Ended early | No gold. "Ended at 18 of 50m" over the counted time. |
| Emergency release | The ended state of §5.7. |
| Counted nothing | A neutral white finish with no gold. |
| Didn't qualify | "Not counted · add an app to count" |

- **Variants:**
  - **Unlocked minutes:** shown as gap marks, with "45m locked · 5m unlocked, not counted".
  - **Plain timer:** lit marks and "50m focused · not counted toward leaves".
  - **Lost confirmation:** "Couldn't confirm the block after 14:10".
  - **After bedtime:** "After bedtime · this didn't count".
  - **Over the cap:** "Over today's 6h · this didn't add" ("Over that day's 6h · this didn't add" when the caption says "that day", F1-31).
- **The end notification** opens this receipt when tapped.
- **The reflection carries forward.** "Partly" or "Not yet" puts that intention first among the next start's chips, and "All done" drops it.

### 5.9 Saved today
As in focus spec §3.3. Its reasons come from the rule ids in §3.3, with "Couldn't confirm the block" in place of "Protection was off". A receipt opens it on the day of the total it showed (F1-31). From one saying "that day" the sheet is titled "Saved that day", its cap reason reads "Over that day's 6h", and a day with nothing reads "Nothing saved that day."; VoiceOver's hint on that receipt's numeral is "Opens Saved that day". From Home it opens on today.

### 5.10 Home
As in focus spec §6, with these details:
- **Day:** "1h 20m", captioned "saved today · 41h in all".
- **Before the day's first session:** "41h", captioned "saved in all · none yet today" (F1-25). With nothing saved ever, the day keeps the wind-down countdown.
- **Morning with no sleep data:** "1h 50m", captioned "saved yesterday · 41h in all", when something was saved yesterday. Otherwise it keeps today's "wind-down tonight".
- **Start:** "Start study · 50m", or "Hold to start · Locked 50m".
  - It starts at once only when start readiness says so. Otherwise it opens the Focus tab with that preset selected.
  - Without Screen Time, the day numeral is the countdown to wind-down and the action reads "Turn on blocking", which opens Needs Screen Time. Free builds have no action there.
  - There is no long-press preset menu.
- **Next-leaf row:** the skeleton leaf, the name, "35m to go" and the hairline.
- **Header streak:** a drawn amber leaf with the current run, hidden under 2. It opens the streak sheet (§5.15).
- **Session running,** in every phase, night included: "18m", captioned "left in this session", with "Return to session".
- **The mini bar** shows only on Herbarium, because Home already shows the session.

### 5.11 Lock Screen and Dynamic Island
- **Lock Screen:**
  - the leaf as a skeleton in season tint (never gold);
  - the system timer text and "until 14:52";
  - "Study" (the preset name only; the intention stays private on the Lock Screen);
  - the ring.
- **Compact:** the leaf and the system timer text.
- **Minimal:** the ring.
- **Expanded:** the leaf, the timer text, "Study · Chemistry ch. 4" (the intention capped at 40 characters) and the ring.
- **During a break:** "Study · break until 14:28" on the Lock Screen and in the expanded view: the preset name (never the intention), then "break until" and the break's end, in the app's clock format. VoiceOver reads "Study, break until 14:28" (F1-27). With Maple suspended nothing updates the activity when the break ends, and "break until" stays true afterwards. The app's own break screen (§5.5) is unchanged.
- **Plain timer:** "Plain timer", with no leaf.
- **No buttons.** Once `staleDate` passes, it shows "Session complete".
- **Upkeep:**
  - On launch and on every return to the foreground, the app reconnects to its running Live Activity, or ends any it doesn't recognise.
  - Demo Live Activities use real dates.

### 5.12 Settings
- "Sleep schedule ›".
- "Session end", a switch, on by default.
- "Daily study reminder", with an on/off switch and a time.
- "Release all apps", for stuck shields only.
  - It asks first: "Release all apps? Every app Maple is resting opens again now."
  - During a session it goes through that strictness level's own end path, so in Locked it is the emergency release. During a plain timer it is Gentle's End early, whatever the preset (F1-30).
  - On F1 builds it clears the preview stores.

### 5.13 Preset editor
- **Opens from:** holding a chip, or the "+" chip ("New preset").
- **Fields:**
  - name, up to 24 characters;
  - verb (study, a quick session, a deep session, reading, focus);
  - length (the dial's range);
  - break: none or one 5-minute locked break;
  - app set;
  - strictness.
- **Strictness chooser:** three rows, each with one honest line.
  - Gentle: "Unlock an app when you need it. Unlocked time doesn't count."
  - Steady: "Two unlocks a session. Ending early takes a hold and 15 seconds."
  - Locked: "No unlocks. Ending early takes a 10-second hold and a breath. Calls and Always Allowed apps keep working, and you can turn off Screen Time for Maple in Settings."
- **Changing strictness:** a tighter level applies now. A looser one applies from the next day, with the line "Steady starts tomorrow".
- **What it applies to:** sessions that lock apps. A plain timer is Gentle whatever its preset's level (F1-30).
- **Limits:** at most 6 presets. "+" hides at 6. Deleting is a destructive row at the bottom, and the last preset can't be deleted.

### 5.14 Blocking sheet
- **Mode:** a segmented capsule, "Block these" or "Only these".
- **Named sets:** Distractions, Study apps and Bedtime to start.
- **The picker:**
  - F1 uses a DEBUG fake picker: a list of sample apps, sites and categories with checkboxes.
  - F1-paid swaps in Apple's picker.
- **Counter:** "6 apps · 1 site", plus "Up to 50 apps can rest at once" near the limit.
- **Footer:** "Calls and apps on iOS's Always Allowed list stay open."
- **Never empty over full:** an empty selection is never saved over a non-empty one.

### 5.15 Streak sheet
- **Title:** the current run, "12 days".
- **Lines:** "Best: 21 days" and "2 rest days a week are built in".
- **Week:** this week as 7 dots. Finished days are season tint, rest days and misses are neutral, and today is pending. It never says "0 rest days left".

### 5.16 Intention entry
- "What's this for?" opens a single-line field (at most 60 characters) above the keyboard.
- The last 3 distinct intentions show as chips above it, with carried-forward ones first (§5.8).
- Return saves it. Closing the entry without Return (a swipe down, or a tap outside) saves it the same way: trimmed, at most 60 characters, and a blank field means no intention (F1-28).
- Clearing the field removes it at once.

### 5.17 Large text
- **The dial** uses a fitted size, never `scaleEffect`.
- **The centre numeral** caps at xxLarge. At accessibility sizes, the time is repeated as a line under the dial.
- **Layout:**
  - At accessibility sizes the start screen becomes a `ScrollView`, with the primary pinned at the bottom (HeroFit).
  - Chips show names only, and wrap with `ChipFlow`.
  - "+" is at least 44pt wide and reads "New preset".

## 6. Notifications
- **Session end:**
  - a new `ReminderKind.sessionEnd`, scheduled at start for the planned end, with an absolute trigger;
  - built from `ReminderPlan.Input.runningSession`;
  - exempt from ReminderPlan's night rule;
  - cancelled by an early end, an emergency release or "Release all apps";
  - kept by `ReminderUpkeep`;
  - copy: "Session done · Study, 50 minutes", or "Timer done · 50 minutes" for a plain timer, with the default sound (a rendered soft chime can replace it later);
  - Time Sensitive in F1-paid;
  - tapping it opens the receipt.
- **Daily study reminder:**
  - a new `ReminderKind.studyReminder`, off by default;
  - the member picks the time when turning it on (16:00 suggested), and it must fall in the Day phase;
  - once a day, and skipped on days a session has already started;
  - copy: "Ready to study? Your apps can rest for a while." It never mentions leaves, streaks or missed days.
- **Permission:**
  - The notifications primer reads "When a session ends, and when it's time to wind down. Nothing else."
  - If iOS hasn't asked yet, Maple asks once, at the first session start (F1-23).
- **Moving code:** `ReminderInputs` moves from the app into MapleServices, so it can be tested.
- **Still never sent:** morning notifications, streak nagging and "come back" pushes.

## 7. Architecture

### 7.1 MapleFocusCore (new target: pure, `Sendable`, nonisolated, no resources)
The types the F1-paid extensions need, kept apart so the monitor (about 6 MB of memory) never loads MapleCore's resources. MapleCore re-exports it, so app code imports only MapleCore.
- **`LocalDay`,** moved here from MapleCore unchanged.
- **The event model:**
  - `FocusEvent` and `FocusEventKind` (§3.1);
  - `EventStamp`;
  - `FocusWriter`;
  - `FocusSource`;
  - `EndReason`;
  - `Reflection`.
- **`FocusPlan`,** frozen into `sessionStarted`:
  - `presetID`, `presetName` and `verb`;
  - planned seconds, break seconds and strictness;
  - `appSetID` and a `SelectionSummary`;
  - the kind (`blocking` or `plainTimer`);
  - `startedFrom` (Focus tab, Home or Again);
  - `mapleDay` and the frozen `AwakeWindow` (start, end, wind-down);
  - the time zone, the app build and the rules version.

  There is no free text beyond the preset name.
- **`SelectionSummary`:** mode, app, site and category counts, and `qualifies` (R3).
- **`FocusTimeSource`:**
  - live: the wall clock, `clock_gettime_nsec_np(CLOCK_MONOTONIC)` (the continuous clock, which counts sleep) and the hashed boot id;
  - manual: for tests;
  - shifted: real continuous time with a wall offset, for demos.
- **`FocusLedger`:** merges events by id (order-free and idempotent), orders and places them (§3.2), and replays them into `SessionRecord`s with their checkpoints and state.
- **`ShieldOp`** and the pure `ShieldReconciler`:
  - it takes no action on an unknown state;
  - it clears sessions that have expired;
  - it is idempotent.
- **`MapleTier`** and **`BlockingCapability`:** what the build can do (`unavailableInBuild`, `preview`, `screenTime`), kept separate from whether permission was granted.

### 7.2 MapleCore/Focus (pure)
- **`AwakeWindow`:** builds the frozen window (§3.3 step 6) from the schedule and `NightLedger`'s past schedules.
- **`HoursCredit`:** turns replayed sessions into `SessionCredit` (counted seconds, finished, labelled stretches) and per-day totals (§3.3, §3.4).
- **`FocusBook`** and **`DayCredit`** (§3.5).
- **`FocusCounters`:**
  - returns dated marks (instant, day, values) in time order;
  - returns the current and best runs.

  `CollectionSnapshot.applyFocus(marks:)` applies each mark with `at: mark.instant` through `raise`. So unlock dates, tended days and the reveal hold follow when credit was earned. `LeafEngine` is unchanged, and `RevealSchedule` changes as F1-12 says.
- **`SessionForecast`:**
  - the minute the next hours leaf would open, or nil;
  - the counts line's state;
  - the leaf line.
- **`StartReadiness`:** whether a start can go straight ahead, or why the start screen is needed.
- **`DialLayout`:** mark count, minutes per mark, angles and the leaf dot.
- **`FocusTimeText`** (§4.4).
- **`RecentIntentions`:** the last 3 distinct intentions, with carried-forward ones first.
- **Capability types:** `LeafAvailability` gains `.notInThisBuild`. Home's pick treats it like `.dormant`, and it offers no button.
- **`LeafProgress.floor` and `rungFraction`:** the rung below and the progress within the rung, for the dial (§4.3).
- **Edits to existing code:**
  - `NowState`: calm minutes, the running session in every phase, saved today and in all, the lifetime total before the first session, Start with readiness, and no long-press;
  - `NextLeafPicker`: free builds keep Rested nights;
  - `ReminderPlan` gains `.sessionEnd` and `.studyReminder`;
  - `ShippedFeatures`, whose F1 flag is flipped last, in F1b;
  - `MapleClock.shifted(by:)`;
  - `LeafRemainder` rounds hours up;
  - the reward generator drops the landmark lines and updates the two metrics.

### 7.3 MapleStorage (new target, nonisolated, depends on MapleFocusCore)
- **`MapleContainer`,** moved from MapleServices unchanged.
- **`JSONLinesFile`:**
  - before each append, it makes sure the file ends in a newline;
  - reading tolerates damage: bad lines are skipped and counted, and the file is never set aside;
  - files use `.completeUntilFirstUserAuthentication` protection.
- **`FocusLedgerStore`,** a protocol with two implementations:
  - `FileLedgerStore`: one file per writer per month (`ledger-app-2026-10.jsonl`), so files stay small and a replay of the open days reads only the recent months' files, decoding only what was appended since its last read;
  - `MemoryLedgerStore`: for demos and tests.

### 7.4 MapleServices/Focus (MainActor)
- **`FocusSessionStore`:**
  - turns commands into events, replays them and applies credit through `CollectionStore.applyFocus`;
  - runs its effects one at a time: blocking, the Live Activity and the end notification;
  - only temporary clears (an override) must be written before they are acted on, and final clears always run;
  - if the ledger can't be read, it holds an unknown state and neither writes nor clears;
  - exposes display credit (counted plus provisional) for the dial and Home;
  - grants `.screenTime` in the collection's permissions while blocking is available and allowed, as `HealthPermission.apply(to:)` does for Apple Health;
  - can be seeded with a demo scenario (a ledger and a clock offset), so every `-MapleDemoFocus` state is reachable without taps.
- **`BlockingService`:**
  - **The protocol boundary:** no FamilyControls or ManagedSettings types cross it. A selection is opaque `Data` plus a `SelectionSummary`.
  - **Methods:** `probe()`, `requestAuthorization()`, `perform(ShieldOp)` (which returns a verified result) and `releaseAll()`.
  - **`MapleBuild`:** reads the tier from a `MapleTier` Info.plist key, as `MapleHealthBackgroundDelivery` does today.
  - **`PreviewBlockingService` (DEBUG):**
    - keeps its "store" in memory;
    - its events carry `source: preview`, which only the sandbox credits;
    - it injects the real failure modes: 51 tokens reading back nil, revocation with a stale status, a failed apply, a failed write and expired tokens.
  - **`UnavailableBlockingService`:** free Release builds.
  - **`ScreenTimeBlockingService`:** F1-paid.
- **Other stores:**
  - `PresetStore` (`presets.json`);
  - `AppSetStore` (`app-sets.json`);
  - `SessionNotesStore` (`session-notes.json`: intentions by session id);
  - `LiveActivityController`, a protocol plus a fake, over a MapleCore display value;
  - `ReminderInputs`, moved from the app;
  - `AppSettings` gains the session-end switch and the study reminder's switch and time, decoded tolerantly.

### 7.5 MapleDesign
`MinuteDial` (§4), `DialFrame`, `HoldButton` and the dial tokens. The leaf reuses `LeafView`'s skeleton and `progressFill`.

### 7.6 Launches
| Mode | Ledger | Credits | Used by |
|---|---|---|---|
| Live | files in the container | `live` events | Release and ordinary DEBUG runs; a DEBUG live run behaves like its tier |
| Demo | memory only, seeded per `-MapleDemoFocus` | nothing new | every `-MapleDemo…` launch; nothing touches the live files |
| Sandbox (DEBUG) | its own folder, `Sandbox/` | `live` and `preview` events | `-MapleDemoSandbox YES`; a complete parallel container, so sessions can run end to end |

- `DemoLaunchOptions` gains the Focus arguments as typed fields, so `isActive` covers them.
- **The demo clock keeps running** whenever a Focus argument is present. `MapleClock.shifted(by:)` puts "now" inside the asked-for phase and lets it tick, and the demo `FocusTimeSource` shares that offset, so Home and the dial agree.
- **Features in demos.** Focus demos run with exactly `[.m1, .f1]`, never `.all`, so F2's surfaces stay hidden.
- `-MapleDemoSessionSeconds 90` makes sandbox sessions short, in real time.

### 7.7 App
- **`App/Features/Focus`:** every screen in §5, plus the DEBUG fake picker and a DEBUG ledger inspector.
- **Elsewhere in the app:**
  - Home's changes;
  - the Settings rows;
  - the tab change in `RootView`.
- **New target:** `MapleWidgets`, for the Live Activity only.
  - Its bundle id is `$(MAPLE_BUNDLE_ID).widgets`, with its own xcconfig and no entitlements.
  - It links MapleActivity but not MapleStorage.
  - The app gets `NSSupportsLiveActivities`.
  - `docs/entitlements.md` is updated.
- **MapleActivity:** a small nonisolated library holding `FocusActivityAttributes`, shared by the app and the widget extension.

### 7.8 Privacy
- The ledger holds no free text. Intentions live in `session-notes.json`, and the Lock Screen shows the preset name only.
- **Ids.** The device id is a random UUID kept in the container. The boot id is hashed with it, so it can't be matched across installs.
- **Stamps.** The continuous time and the boot id mean something only on this device. The wall time and the time zone are the parts that could sync in F2.
- **Logs** carry ids and counts, never content.
- **The privacy manifest** (F1-paid) lists the required-reason APIs: the boot time read through `sysctl`, file timestamps, and `UserDefaults`.

### 7.9 F1-paid additions
- **Extension targets:** thin adapters over the pure cores.
- **Monitor activities:**
  - one-off activities per session: `s.<id>`, from start to the planned end, with `repeats: false`;
  - per re-lock: `r.<id>`, at least 15 minutes long.
  - Unique names keep a late callback from clearing another session.
- **Writing:** `shieldApplied` is written only after the read-back succeeds.
- **Token cap:** 50 tokens across all stores, enforced when a selection is saved and again in the reconciler.
- **Credit depends only on the app's own writes** until the App Group write test passes on a device.

## 8. Testing

### 8.1 Logic (Swift Testing, tests written first)
- **Ledger files:**
  - merging is order-free and idempotent, checked with seeded random orders;
  - a torn tail is skipped, and the next append still decodes;
  - unknown kinds round-trip, and one that affects credit stops credit at the checkpoint before it;
  - a second terminal event changes nothing;
  - an unreadable ledger leaves the store in the unknown state;
  - golden fixtures: a few ledgers written as JSON lines, with their exact expected credit.
- **Order and placement:**
  - setting the clock back or forward inside a boot moves nothing;
  - a new boot is never placed before the previous boot's last event;
  - boots are ordered by the app's own `seq`.
- **Credit:**
  - 3,600 seconds unlocks the 1h leaf; 3,599 seconds doesn't;
  - a session proven to its planned end credits exactly its length;
  - the countdown and credit start at `shieldApplied`, not the tap;
  - overlapping sessions count once;
  - a 23:40–00:30 session with bed at 01:00 falls on one Maple day;
  - daylight-saving days (23h and 25h);
  - a flight mid-session;
  - 50 minutes of simulated sleep earn full credit;
  - after a reboot, only uptime with a read-back counts;
  - a killed app reopened after the end credits to the planned end;
  - credit with no later checkpoint is provisional only;
  - revocation earns credit up to the last checkpoint;
  - a plain timer earns 0, and preview events earn 0 in live launches;
  - a 50m Study with a 5m break at minute 30 credits 50m and ends at start + 50m;
  - "Take a 5-minute break instead" at minute 47 of 50 stops at 50.
- **The awake window:**
  - a bedtime edit after 18:00 leaves today unchanged;
  - a sleep window under 6h is widened to 6h at the wake end;
  - a session started at 05:30 with wake at 07:00 counts from 06:00;
  - after bedtime counts 0;
  - a session crossing bedtime counts until bed.
- **Caps and overrides:**
  - the 6h cap, with earlier time counted first;
  - an override removes its whole window;
  - a locked break counts.
- **`FocusBook`:**
  - counters never fall after a deleted ledger, a rules change or an older build dropping the book;
  - a late subtraction in one session doesn't stall a later session on the same day;
  - days freeze 3 days after the later of their end and their first credit;
  - a book dropped by an older build rebuilds its baseline from the counters;
  - a file with a newer version is never saved over.
- **Dating:**
  - a leaf earned at 20:30 opens at once, and one earned at 22:30 is held (bedtime 23:00, wind-down from 22:15);
  - a Day session applied in the evening isn't held;
  - nothing unlocks before the session's closing checkpoint.
- **Finished sessions:**
  - Gentle with four overrides in 20 minutes: not finished;
  - access revoked at minute 1: not finished;
  - after bedtime: not finished;
  - over the daily cap: finished;
  - at most 3 count a day;
  - an early end, an emergency release and "Release all apps": never finished;
  - a selection that doesn't qualify, run to its end: 0 hours, not finished, not a focus day.
- **The streak:**
  - Monday-to-Friday sessions keep the run going, and a third miss in 7 days breaks it;
  - one session followed by misses never makes a run longer than 1;
  - the current run stays alive through 2 trailing misses, and shows the bridged length once a session follows;
  - a one-day gap across a time-zone change is neutral;
  - best run 14 with current run 2 shows "2 of 30".
- **R3:**
  - one app qualifies in "Block these", and an empty selection doesn't;
  - "Only these" with an allowed category, or with 21 apps, doesn't qualify;
  - 51 tokens are refused.
- **The reconciler:** takes no action on an unknown state, clears expired sessions and is idempotent.
- **Dial and text:**
  - mark counts at 20, 50, 60, 65, 120, 125 and 180 minutes;
  - the leaf dot's angle, and no dot when the cap, the awake window or overrides put the leaf out of reach;
  - "1m" versus "0:59";
  - the "1h 30m" format and the spoken forms.
- **Home (`NowState`):**
  - a running session shows at night;
  - Start opens the Focus tab when readiness says so;
  - the lifetime total before the first session;
  - calm minutes.
- **System:**
  - on a free build, Rested nights is the next leaf, there is no Screen Time prompt, Screen Time leaves are "not in this build", and Day shows the wind-down countdown;
  - a `-MapleDemo*` launch writes nothing to the live files;
  - the end notification survives `ReminderUpkeep`, and the study reminder is skipped on a day with a session;
  - replaying the open days takes under 50 ms, and rebuilding 3 synthetic years takes under 1 s in the Debug simulator.

### 8.2 UI
- **DEBUG launch arguments** (documented in `docs/debug-launch-arguments.md`):
  - `-MapleDemoShip f1`, which ships F1 in demo stores, so every F1b screen can be checked before the final flip;
  - `-MapleDemoTab focus`, which replaces `rest`;
  - `-MapleDemoFocus idle|noSet|smallSet|expired|running|dimmed|break|minimised|ended|endedAway|endEarly|emergency`;
  - `-MapleDemoFocusAt <min>`;
  - `-MapleDemoStrictness gentle|steady|locked`;
  - `-MapleDemoScreenTime approved|notDetermined|declined|restricted|noPasscode|unavailable|revoked|plain|failStart`;
  - `-MapleDemoReceipt clean|unlocked|early|plain|revoked|bedtime|capped|leaf|leafNight|notQualifying`;
  - `-MapleDemoSaved typical|capped|empty`;
  - `-MapleDemoLiveActivity running|break|plain|ended`;
  - `-MapleDemoNotify sessionEnd`;
  - `-MapleDemoPresent blocking|preset|endEarly|saved|streak|intention`;
  - `-MapleDemoSandbox YES` and `-MapleDemoSessionSeconds <n>` (§7.6);
  - `-MapleDemoFocus first`, `-MapleDemoPreset study|quick|deep|read` and `-MapleDemoIntention <text>`;
  - frozen frames, following `-MapleDemoRevealAt`: `-MapleDemoHoldAt 0…1`, `-MapleDemoEndCountdown <s>` and `-MapleDemoFinishAt <s>`;
  - `-MapleDemoReduceMotion YES` extended to Focus.
- **Ownership.** Every Focus argument is a Core argument in `DemoLaunchOptions`, so any of them keeps the launch in demo stores. `-MapleDemoPresent endEarly` is dropped in favour of `-MapleDemoFocus endEarly`. `endedAway` is a session that ended 2 hours before launch.
- **Snapshots.** `Scripts/snapshot/FocusScenes.swift` renders every mark state, the leaf tones, Dynamic Type and the Live Activity layouts, replacing `RestScenes`.
- **Screenshots:** each state is checked in the simulator.
- **Accessibility:**
  - VoiceOver follows §4.9;
  - every hold has its named action (F1-22);
  - Reduce Motion (§4.6);
  - Dynamic Type follows §5.17.

### 8.3 F1-paid on-device checklist
- **First:** App Group writes from the monitor and shield-action extensions.
- **The focus spec's list:**
  - the monitor's memory headroom;
  - `openParentalControlsApp` under individual authorization;
  - applying shields from background intents;
  - stuck-shield recovery with the app killed and the phone off Xcode.
- **Added by the reviews:**
  - whether revoking access wipes the store;
  - `isActive` across processes;
  - `startMonitoring` from the shield-action extension;
  - one-off schedules that cross midnight;
  - Apple's picker inside a sheet;
  - installing a free build that contains the extensions;
  - individual authorization on a teen's child account;
  - session timing with the phone asleep;
  - whether `CLOCK_MONOTONIC` and `kern.bootsessionuuid` read the same in the app and the extensions.

### 8.4 Gates
- zero warnings;
- Swift 6 strict concurrency;
- the whole suite green;
- a Release build containing no Preview or Demo symbols, checked by `Scripts/check-release.sh`.

## 9. Implementation plans
Each plan has its own branch and pull request. Both branch from `main`, and F1a doesn't change NightLedger, which another branch is simplifying.

1. **F1a, logic.**
   - **Contents:**
     - MapleFocusCore, MapleStorage and MapleCore/Focus (§7.1–7.3), with the package, scheme and project wiring;
     - `FocusBook`, `CollectionSnapshot` version 2 and `applyFocus(marks:)`;
     - the `RevealSchedule` change, with `docs/design/spec.md` and `docs/core-api.md`;
     - `LeafRemainder`, `LeafAvailability.notInThisBuild` and `NextLeafPicker`;
     - the `ReminderPlan` kinds, with `ReminderInputs` moved into MapleServices;
     - the MapleServices stores with preview blocking, and the launch modes;
     - `NowState`, with the smallest HomeView change that compiles;
     - the reward generator's text changes, `rewards.json`, `RewardCategoryInfo`, `rewards.md` and their tests;
     - `Scripts/check-release.sh`;
     - all §8.1 tests.
   - **No new screens.**
   - **Branch:** `maanvik/f1a-focus-logic`.
2. **F1b, screens.**
   - **Contents:**
     - `-MapleDemoShip f1` first;
     - `MinuteDial`, `DialFrame` and `HoldButton`;
     - every §5 screen;
     - Home and the Settings rows;
     - the tab change (Rest retired);
     - MapleActivity and the Live Activity widget;
     - wiring the notifications;
     - the design overrides in `docs/design/spec.md` (F1-18; the reveal easing without overshoot; haptic rows in §6.7; the `timer`, `chevron.down` and `lock.fill` symbols in §6.8);
     - the DEBUG arguments and their doc;
     - flipping `ShippedFeatures` for F1 last.
   - **Branch:** `maanvik/f1b-focus-screens`, from `main` once F1a has merged.
3. **F1-paid:** its own plan once the account joins the paid program. It starts with the on-device App Group write test.

## 10. Edits made to the focus spec with this document
- **Header:** status and a pointer here.
- **O5:** the Phone break is F2.
- **§3.2 rules:**
  - R2 (read-back, any process, preview never counts);
  - R3 (any non-empty "Block these"; the "Only these" limits and the 50-token cap);
  - R4 (Release all apps, proven checkpoints);
  - R5 (`ContinuousClock`, provisional credit, same-boot placement);
  - R6 (the Maple day, frozen windows, 18:00 edits, 6h minimum, wake − 60);
  - R7 (a break sits inside the planned length);
  - R8 (20 minutes to 3 hours);
  - R10 (the Maple day boundary);
  - R11 (`FocusBook`);
  - R13 (finished sessions, bridging rest days, best and current run).
- **§3.3:** the week line has no comparison, Home's running time reads "18m", and "Couldn't confirm the block" replaces "Protection was off".
- **§4.2:** landmark lines removed.
- **§5:**
  - §5.1: the dial replaces the ring, and the "This week" strip moves to F2;
  - §5.3: Flow, Cycles and the Phone break move to F2, and Locked's emergency release changes;
  - §5.4: the dial and calm minutes, and the mini bar on Herbarium only;
  - §5.7: the receipt is the final frame;
  - §5.10: "Couldn't confirm" wording, and "isn't approved, with or without data access";
  - §5.11: no Live Activity buttons in F1.
- **§6:** the drawn streak leaf, calm minutes, hold-to-start for Locked, Start with readiness and no long-press, and the running session in every phase.
- **§7:** F1 keeps today's onboarding, and "What pulls you in" comes with F1-paid.
- **§8:** the session-end and daily study reminder kinds.
- **§9:** MapleFocusCore, MapleStorage, `FocusBook`, `BlockingCapability`, the launch modes, `shieldCleared`, `source`, the extensions in F1-paid, and end paths that don't include the Live Activity.
- **§10:** points here for F1's tests.
- **§11:** step 2 is split into F1a, F1b and F1-paid.
- **§14:** Opal's recovery.

## 11. Research corrections
- **Opal has largely recovered** (4.72★ overall), so the focus spec's risk line about its weak moment is out of date and has been updated.
- **Forest's reviews have averaged about 2.05★ since its September 2026 redesign,** and Focus Friend is rising. A calm, honest timer that never punishes is the opening.

## 12. Questions still open for the owner
1. **Evening study.** Home offers Start only in the Day phase (wake + 3h to 2 hours before wind-down), so 20:15 to 22:15 shows "Start wind-down". F1 keeps that, and the Focus tab still starts sessions in the evening. Should Home offer Start in the evening too?
2. **Exit timings.** Steady's way out (a 3-second hold and 15 seconds) and Locked's (a 10-second hold and an 8-second breath) both take about 18 seconds. Should Steady be quicker?
3. **Rarity.** Should the hours ladder show "% of members" as other ladders do, given §13 of the focus spec rules out hour percentiles?
4. **Auto-Lock.** F1 leaves the idle timer alone, so the phone sleeps during a session. Is that right?
5. **The other branch.** A remote branch, `claude/project-thread-wghnsi`, adds a second `ReminderPlan` with morning reminders, which the focus spec rules out. It hasn't been touched.
6. **Pushing.** Local `main` is 21 commits ahead of `origin/main`, and nothing has been pushed.
7. **The leaf's fill.** The dial fills the leaf within its rung (§4.3), while Home's row, the Herbarium and the buds use progress from zero. Past about 10 hours they read differently: nearly full on Home, half full on the dial. Should the within-rung fill be used everywhere?
8. **Pull requests.** F1b is one plan, but it could land as 2 or 3 pull requests (the dial and Focus tab; Home, Settings and sheets; the widget, notifications and the flip). That would keep conflicts with the second developer small.
