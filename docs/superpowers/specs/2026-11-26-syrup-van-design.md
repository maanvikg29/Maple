# The syrup van: design

Status: **approved by the owner on 2026-11-26** ("yes to all, drop the tab bar"). Nothing in this document is built yet. The build plans are in `docs/superpowers/plans/`.

Every rule below carries one of two marks:
- **Decided**: the owner chose it in the 2026-11-26 design conversation.
- **Proposed**: Claude's suggestion. The owner approved all of them together on 2026-11-26, so they are binding too. The mark is kept so it stays clear which rules the owner shaped and which they accepted as written.

**How it relates to the other specs.** This is a new look and a new reward layer for Maple. It sits on top of the focus logic that already exists and does not change it:
- `2026-10-11-focus-hours-saved-design.md` and `2026-10-23-f1-focus-design.md` still decide what a session is, what blocking does, what counts as time saved, the streak, and the Lock Screen.
- This document replaces how those things look, what the member does between sessions, and what they earn.
- Where this document and `docs/design/spec.md` disagree about style ("calm, dark, nothing gamified"), this one wins once the owner approves it. `CLAUDE.md` is updated at that point, not before.

**Concept images** (in `docs/design/concepts/2026-11-26-syrup-workshop/`). They are pictures of the target, not finished art:
- `syrup-van.jpg`: the home screen's scene. The owner chose this one.
- `van-night-preview.png`: the same scene at night (small preview).
- `pip-from-van.jpg`: the mascot, cut from the van image. This is the reference for Pip.
- `pip-mascot.png`: Pip alone (small preview).
- `maple-works-factory.jpg`: the factory setting. Kept as an idea, not chosen.
- `opening-screen-preview.png` and `pip-outfit-preview.png`: two renders that missed what was asked. Kept only for the record.

---

## 1. What changes and what stays

| | Today | With the syrup van |
|---|---|---|
| Home | A maple tree that grows leaves | The van under the maple tree |
| Reward for focusing | One of 155 leaves at rare milestones | Plain leaves every few minutes, plus the 155 as special leaves |
| Between sessions | Look at the tree and the Herbarium | Cook syrup, upgrade the workshop, decorate, dress Pip |
| The timer | A dial on a dark page | A gauge in the workshop, then the tree |
| Style | Dark, restrained, amber for rewards only | Warm, hand-drawn, thick outlines, busy with detail |

What stays as it is: how a session starts and runs (without presets or breaks, §6.3); app blocking and the strictness levels; the counting rules for time saved; the streak; subjects and History; sleep and the schedule; Apple Health.

---

## 2. The loop

1. **Focusing earns leaves.** **Decided.**
2. **A leaf is either cooked into syrup or spent on an upgrade.** **Decided.**
3. **Cooking happens when the member taps the pot.** It is never automatic. **Decided.**
4. **Upgrades make each leaf give more syrup.** **Decided.**
5. **Syrup buys decorations.** **Decided.**
6. **Nothing is ever bought with money.** Leaves and syrup come only from focusing. **Decided** (it is also an existing rule in `docs/decisions.md`).

**The numbers:**
- **0.9 leaves for every minute focused,** which is 54 an hour. A 50-minute session gives 45 leaves. **Decided** (owner, 2026-11-26; first 1 per 5 minutes, then 0.8 a minute, then this).
- **A session's leaves are rounded up when it ends.** **Decided** (owner, 2026-11-26).
- **Every session earns the same way, from its time focused,** whether it blocks apps or is a plain timer. Time saved, with its daily limit, still decides the special leaves. **Decided** (owner, 2026-11-26: the pace is per minute, with no difference between kinds of session).
- **A session ended before its timer runs out earns nothing.** Every leaf of that session is lost, however long it ran, and Pip falls out of the tree (§6.6). The session is still in History, marked as ended early. **Decided** (owner, 2026-11-26). It holds for every way out before the end: End early, Locked's emergency release, and Release all apps. Time saved toward the special leaves keeps today's rule (an early end keeps its counted minutes) until the owner says otherwise.
- One leaf cooks into one bottle of syrup before any upgrade. **Proposed**, to be tuned in its own pass (§14).

---

## 3. The 155 special leaves

- **The 155 species stay.** **Decided.**
- **Each one makes its own special syrup.** **Decided.**
- **Special syrup buys special decorations and clothes for Pip.** **Decided.**
- **Cooking a special leaf does not use it up.** The leaf stays in the Herbarium. It makes its special syrup once. **Decided.**
- **Pip's belly leaf can be changed to any species the member has collected.** **Decided.**
- **How a special leaf is earned does not change.** They still come from the milestones in the reward table (`Scripts/generate-rewards.py`) and from sleep. **Proposed.**
- **The rarer the leaf, the bigger what it unlocks.** **Proposed.**

| Rarity | Unlocks | Example |
|---|---|---|
| Common | A small item | A mug, a sticker for the van |
| Uncommon | Clothing for Pip | A scarf, a hat, a vest |
| Rare | A decoration that moves | A wind chime, a companion animal |
| Legendary | A makeover | A paint job for the van, northern lights at night |

- **The tasting shelf.** Each special syrup has its own bottle on a rack in the workshop. The rack starts as 155 empty outlines. **Proposed.**

The owner has said the detail of this section comes later. §14 lists it.

---

## 4. Pip

- **The mascot is a squirrel with a maple leaf on its belly.** **Decided.**
- **It is the squirrel in the van image, exactly** (`pip-from-van.jpg`). **Decided.**
  - Chubby red-brown body with a thick dark brown outline.
  - A big tail curled into a swirl, with a peach stripe inside.
  - Peach face mask, muzzle and belly. Black dot eyes, a small black nose, a tiny smile.
  - One red maple leaf in the middle of the belly.
- **The name is Pip.** The owner is keeping it and may change it. **Decided.**
- **Clothes never cover the belly leaf.** Tops are open at the front: aprons with a cut-out, vests, scarves. **Proposed.**
- **Clothing slots:** hat, neck, body, back, ladle, tail. **Proposed.**

---

## 5. One scene, three cameras

The whole app is one place: the van parked under the maple tree. The camera has three positions. **Proposed as a way to describe what the owner decided below.**

| Camera | What it is for | How the member gets there |
|---|---|---|
| The whole scene | Home, and decorating | Opening the app; tapping "decorate" |
| Inside the van, straight-on side view | The workshop: the timer, cooking, the shelf | Tapping the enter button on home |
| Up in the tree | A session that is running | Starting the timer |

### 5.1 Home

- **Home is the van image:** the van seen from above and behind, under the tree. **Decided.**
- **The van's side is cut away, so the inside shows.** **Decided** ("the cut is the good part").
- **Home says welcome and shows the time.** **Decided.**
  - A greeting by time of day ("Good evening") with the clock time large under it. **Proposed.**
  - One line about what is waiting: "Pip is out of leaves", "3 leaves waiting to cook". **Proposed.**
- **One enter button.** Tapping it zooms into the workshop. **Decided.**
- **Counters** for leaves and syrup at the top. **Proposed.**
- A session that is running, or that ended while the member was away, skips home and opens on that session, as the app does today. **Proposed.**

### 5.2 The workshop

- **A proper side view of the inside of the van.** **Decided.**
- **What is in it** (**Proposed**):
  - the boiler with its round gauge, which is the timer (§6);
  - the stove and the pot, which the member taps to cook;
  - the leaf basket, holding leaves not yet cooked;
  - the tasting shelf (§3);
  - a logbook on the counter, which opens History and subjects;
  - a way back out to home.

### 5.3 Entering

**Proposed**, about 1.2 seconds in all:
1. The enter button fades and a latch clicks, with a light tap from the phone.
2. The camera pushes in toward the van.
3. The view turns to the straight-on side view and warm light fills it.
4. Pip hops in ahead.
5. The gauge and the pot settle into place.

The full entrance plays once a day. After that it takes under half a second. With Reduce Motion on, it is a cross-fade.

### 5.4 Decorating

- **Tapping the decoration button goes back to the home view, where the van can be edited.** **Decided.**
- In edit mode the member taps a place on the van, the roof or the grass and picks what goes there. **Proposed.**
- Every indoor decoration is drawn twice: once at home's angle and once for the workshop's side view. The owner accepted this cost. **Decided.**

---

## 6. The timer

Everything about when a session counts is unchanged (F1 design §3). This section is about what the member sees and does.

### 6.1 The gauge is the Focus button

- **The timer is the Focus button.** **Decided.**
- In the workshop it is the round brass gauge on the boiler. Its face shows the length that would start now ("50m") and the word "focus". **Proposed.**
- **Tapping it zooms in and shows the timer's options.** **Decided.**

### 6.2 Choosing how long

**Decided (owner, 2026-11-26):** the gauge grows until it fills the width of the screen and becomes **a drawn analog clock with depth**: a thick rim, a face set back inside it, hands that cast a little shadow. **The time shows as digits in the centre of the clock, in the hub the hands start from.**

- **The long hand is minutes.** Dragging it round sets the length; one turn is an hour, and passing the top adds or takes away an hour. **Proposed.**
- **The short hand is hours.** It follows by itself, as on any clock. **Proposed.**
- **The limits stay as they are today:** from 20 minutes to 3 hours, in 5-minute steps (`DialLayout`), with a small tick from the phone at each step. **Proposed.**
- **The hub reads "0:50", "1:30".** The start button below still reads "Start study · 50m". **Proposed.**
- **The face fills with syrup colour** from the top to the long hand, and three drops on the face fill as each whole hour is passed, so the length reads at a glance without the digits. **Proposed.**
- A first interactive mock-up was shown to the owner on 2026-11-26 (in the conversation, not saved in the repo).
- **The timer never shows a leaf count or a rate.** No "about 45 leaves", no "0.9 a minute". **Decided** (owner, 2026-11-26).
- **There are no presets.** No Study, Quick, Deep or Read, and no recipe cards. The clock sets the length, and that is all there is to choose about time. **Decided** (owner, 2026-11-26).
- **A bucket beside the clock grows with the length:** a small pail under 50 minutes, a bucket from 50 minutes, a big basket from 90. It is a picture, never a number. **Proposed.**
- **Minus and plus buttons** either side of the clock move 5 minutes, for anyone who would rather not turn. VoiceOver adjusts the length the same way. **Proposed.**

### 6.3 The other options

- **One block mode.** **Decided** (owner, 2026-11-26: "just a block mode"). Under the clock, one control for blocking: which apps are blocked, opened from a line such as "Blocking 6 apps ›". **Decided** (owner, 2026-11-26, "yes to all"):
  - **Block mode can be switched off** with one switch, and the session then runs as a plain timer. It earns the same leaves.
  - **The three strictness levels stay,** chosen inside the block mode sheet: Gentle, Steady, Locked. They set how hard it is to end a blocking session early (F1 design §5.6, §5.7). A plain timer is always Gentle (F1-30).
  - **Breaks are dropped for now.** They belonged to the presets. Steady's "Take a 5-minute break instead" goes with them.
- **Subject:** "Maths ›" (from the Study record). **Decided** (owner, 2026-11-26).
- **No "What's this for?" note.** **Decided** (owner, 2026-11-26).

### 6.4 Starting

**Proposed.**
- One button: "Start · 50m".
- On start, Pip picks up the bucket and hops out, and the camera rises into the tree.
- In a free-tier build without Apple's Family Controls permission, the session starts as a plain timer, as today (see §13, question 1).

### 6.5 While it runs

- **The view is the maple tree, and leaves fall as the animation.** The syrup bottle is not the timer. **Decided.**
- **The falling leaves are only an animation.** They fall at random and don't match the leaves the session earns. **Decided** (owner, 2026-11-26).
- **No leaf count while it runs.** The count appears when the session ends, as Pip tips the bucket into the basket (§6.7). **Proposed**, following the two rules above.
- **Proposed** detail:
  - The time left is on a wooden sign on the trunk, in large numerals.
  - The screen dims after 30 seconds, as today.
  - A way to minimise returns to home, where the gauge shows the time left.
- **Away from the app:** the Lock Screen and the session-end notification work as today.

### 6.6 Breaks and ending early

- **Breaks are dropped for now** (§6.3), so there is no break view.
- **End early: the session's leaves are lost.** **Decided** (owner, 2026-11-26). Pip falls out of the tree, the bucket tips and the leaves scatter. The session is saved in History as ended early, with its time focused.
- The way out keeps today's two steps (the sheet, then the breath, then "Still want to end?"), and the second question says plainly that this session's leaves will be lost. **Proposed.**
- The fall is a soft tumble into a leaf pile, and Pip gets up again. The words never say "fail" or "quit". **Proposed.**

### 6.7 When it ends

- **An animation of Pip walking back to the van with a bucket of maple leaves.** **Decided.**
- **Proposed** detail:
  1. The last leaf drops and Pip climbs down.
  2. The camera pulls back to the home view.
  3. Pip walks across the grass to the van with the bucket.
  4. Pip tips the bucket into the leaf basket and the leaf count goes up.
  5. The summary shows: time focused, time saved, leaves earned, and a special leaf if one was reached.
- The bucket is as full as the session was long.
- A special leaf sits on top of the bucket and glows.
- If the session ended while the phone was locked, the walk plays when the member next opens the app.
- It lasts about 3 seconds. A tap skips to the summary. With Reduce Motion on, it is a single still frame.

---

## 7. The shop

**Proposed.**
- Three shelves: decorations, machine upgrades, and clothes for Pip.
- Empty places in the van are visible on home in edit mode, so there is always something next.
- Sets: finishing a themed group of items gives a bonus.
- Some items do something: a cat bed brings a cat, a lantern lights the van in the evening.
- Machine upgrades change how the machine looks, not only a number.
- Later rooms: a trailer for stored syrup, then new places to park.

---

## 8. Night

- **There is a night version.** **Decided.**
- **Proposed** detail:
  - It follows the member's own schedule, which Maple already has: evening turns the scene to dusk, and wind-down turns it to night.
  - Light comes from the lantern, the string lights and the windows.
  - After bedtime the van is shut and Pip is asleep: "Pip's asleep. See you in the morning." Sessions started after bedtime already count nothing, so this matches the rule.
  - Some decorations exist only at night.

---

## 9. What happens to today's screens

**All proposed.**

| Today | Becomes |
|---|---|
| Home (the tree) | The home view (§5.1). The tree is still there, beside the van. |
| Focus tab: start screen | The zoomed gauge (§6.2 to §6.4) |
| Focus tab: running, break, end early | The tree view (§6.5, §6.6) |
| Receipt | The walk back and the summary (§6.7) |
| Herbarium | Stays. It also shows each leaf's special syrup and what it unlocked. |
| History and subjects | Stay, opened from the logbook in the workshop |
| Saved today, the streak | Stay, shown on home |
| Profile and Settings | Stay, opened from home |
| Sleep, wind-down, Apple Health | Stay. A leaf earned from sleep is waiting on the van's step in the morning. |

**The tab bar is dropped.** The scene is the navigation: enter, decorate, the shop, and the Herbarium as a leaf-press book. **Decided.**

---

## 10. The art

- **The look:** a dense, cosy cut-away scene with thick dark outlines, flat warm colours and many small objects, as in `syrup-van.jpg`. **Decided** ("this is better").
- **It takes the format of cosy room games as inspiration and copies no other app's character or room.** **Decided.**
- **The concept images are not the app's art.** They are single pictures. **Proposed** for the real thing:
  - every object is its own piece, so it can be placed, bought, animated and swapped;
  - indoor objects have two drawings (§5.4);
  - Pip has a set of poses: standing, stirring, carrying the bucket, climbing, sitting, asleep;
  - everything has a night version, or is lit by the scene.
- Who draws it: Claude, for now (§13, question 5).

---

## 11. Accessibility

**Proposed.** The rules Maple already follows carry over:
- every action has a VoiceOver label and can be done without a gesture that needs dragging;
- text grows with the system text size, and the time left is always shown as text, never only as a picture;
- Reduce Motion replaces each camera move and walk with a cross-fade or a still frame;
- no meaning is carried by colour alone.

---

## 12. Order of building

**Proposed.** Each step ends with something that runs in the simulator.

1. **The art list.** Every object, pose and angle needed for steps 2 to 4, and a decision on who draws it.
2. **The economy, in logic only.** Leaves, syrup, cooking, upgrades, with tests. No screens.
3. **The scene shell.** The home view, the entrance and the workshop, with the gauge driving the timer that exists today.
4. **The session.** The tree view, the falling leaves, the walk back and the summary.
5. **The shop and decorating.**
6. **Special syrups, the tasting shelf and Pip's clothes.**
7. **Night.**

The Study record (branch `maanvik/f2-study-record`) is finished and independent of all this. It can merge before or after.

---

## 13. Questions, and the owner's answers (2026-11-26)

1. **Plain timers.** In a free-tier build without Apple's Family Controls permission, sessions are plain timers and count nothing as time saved. **They earn plain leaves from time focused,** so the whole game works in that build. Special leaves still need counted time.
2. **The pace.** First answered as one leaf per 5 minutes; **changed by the owner the same day to 0.8 and then 0.9 leaves a minute, rounded up when the session ends, and nothing for a session ended early** (§2).
3. **The tab bar.** **Dropped** (§9).
4. **How special leaves are earned.** **Unchanged from today** (§3).
5. **Who draws the art.** **Claude draws it for now** (owner, 2026-11-26: "u draw the art for now"). The pieces are drawn in code as separate objects, with the concept images as the reference. Whether a person or an image tool redraws them later is left open.
6. **The entrance.** **About 1.2 seconds, in full once a day** (§5.3).

---

## 14. Left for later, on purpose

- The full list of special syrups, decorations and clothes, and what each of the 155 leaves unlocks.
- Prices, upgrade steps and the pace of the economy.
- The factory setting and the tree cut-away, which are kept as ideas.
- Sounds.
- Sharing or visiting other members' vans.
