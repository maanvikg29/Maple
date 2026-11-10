# Step 1A: merge the parked M1 branches — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** bring the three parked M1 branches into one working branch, adapted to the focus design.
- `m1-schedule-onboarding`: weekday and weekend schedules, the onboarding questions.
- `m1-health-import`: sleep from Apple Health.
- `m1-notifications`: reminders.

The adaptations: no morning notification, and the real reminders primer in onboarding.

**Architecture:** three `--no-ff` merges, in this order, onto `maanvik/focus-step1`. Each merge commit includes the fixes its semantic conflicts need, so every commit builds and passes. Two follow-up commits then adapt the result to the spec: one removes the morning-leaf reminder, one wires the reminders primer into onboarding. A final commit updates the docs.

A trial merge on 2026-10-11 found exactly these conflicts:
- **Text:** 2 doc files in the health merge, and `MapleApp.swift` in the notifications merge.
- **Compile:** the health seeder and the reminders' night list still use the single-schedule API.

With the fixes below, the trial built and passed 507 tests.

**Tech stack:** Swift 6.4 (language mode 6), SwiftUI, iOS 27 SDK, Xcode 27, Swift Testing. HealthKit and UserNotifications come in through the merged branches.

**Spec:** `docs/superpowers/specs/2026-10-11-focus-hours-saved-design.md`. This plan covers the first half of §11 step 1, plus §8 (notifications) and the parts of §7 (onboarding) that exist before F1. The reward re-cut (§4) is plan 1B: `docs/superpowers/plans/2026-10-11-step1b-reward-recut.md`.

## Global constraints
- iPhone only (`TARGETED_DEVICE_FAMILY = 1`), iOS 27 minimum, Swift 6 language mode with strict concurrency, zero compiler warnings in Debug and Release.
- Tests use Swift Testing (`@Test`, `#expect`, `#require`). Write the test before the change it checks.
- Demo and mock code compiles only under `#if DEBUG`.
- Sleep leaves come only from Apple Health (spec D9). A Goodnight tap never earns a leaf.
- Notifications (spec §8):
  - Allowed: session end (F1), opt-in block heads-ups (F2), an opt-in wind-down reminder, and the shield fallback (F1).
  - Never sent: morning notifications, streak nagging, "come back" pushes.
- Copy is calm and in sentence case, with no exclamation marks and no emoji.
- Build output goes to `~/Library/Developer/Xcode/DerivedData/Maple-<hash>` (the scripts handle this). Never build inside the repo; it lives in iCloud Drive.
- Every commit message ends with a blank line, then `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Never push, and never merge into `main`. The owner reviews and pushes (CLAUDE.md, "Ask before pushing").

All commands run from the repo root, `/Users/maanvikgupta/Documents/Claude proj w guds/Maple`. The test command is:

```bash
SIMULATOR="iPhone 17" Scripts/test.sh 2>&1 | tail -n 25
```

It passes when the output ends with `** TEST SUCCEEDED **` and three `✔ Test run with N tests … passed` lines.

## Review focus
Conditions the spec implies but the merged branches' own tests never exercised. Each has a test in the task named.
1. **A weekend schedule that differs from weekdays.** Reminders must use each night's own wind-down (Friday night → the weekend schedule), and the Health seeder must plant weekend nights around the weekend bedtime. Tests: Task 2 `weekendSeeding`, Task 3 `weekendNights`.
2. **A settings file written by a build that had the morning-leaf switch.** It must still load, keep the wind-down switch, and drop the old key on the next save. Test: Task 4 `olderFileWithMorningSwitch`.
3. **A morning reminder already pending on a phone from an earlier build.** It must be removed at the next reschedule, never delivered. Test: Task 4 `leftoverMorningReminderRemoved`.
4. **Onboarding when iOS has already been asked about notifications** (a reinstall). The notifications step must continue at once instead of showing a primer that can't ask anything. Checked in the simulator in Task 5, step 6.
5. **No reminder ever fires between bedtime and the morning start**, on any schedule, now that only wind-down exists. Test: Task 4 keeps and adapts `nothingAtNight`.

---

### Task 1: Branch and merge `m1-schedule-onboarding`

This merge has no conflicts.

**Files:** none edited by hand. The merge brings 41 files: `WeeklySleepSchedule`, `PhaseWindows(weekly:)`, `OnboardingProgress`, `OnboardingStore`, `OnboardingQuestions.swift` and their tests.

**Interfaces produced** (later tasks rely on these exact names):
- `WeeklySleepSchedule` (MapleCore). It provides:
  - `.standard` and `.everyNight(_:)`;
  - `weekday` and `weekend`;
  - `schedule(forNight:calendar:)`;
  - `times(forNight:calendar:) -> NightTimes`;
  - `currentNight(at:calendar:) -> LocalDay`;
  - `static variant(forNight:calendar:) -> Variant`.
- `NightTimes`: `night`, `variant`, `schedule`, `windDownStart`, `bedtime`, `wake`, `morningStart`.
- `ScheduleStore.weekly: WeeklySleepSchedule`. `ScheduleStore.schedule: SleepSchedule` is tonight's schedule.
- `CollectionStore.schedule` and `CollectionContext.schedule` are now `WeeklySleepSchedule`.
- `RevealSchedule.releaseDate(for:schedule:calendar:)` takes a `WeeklySleepSchedule`.
- `OnboardingStep` gains a `.notifications` case. `PlantYourMapleView` shows `OnboardingNotificationsStep { answered(.notifications) }` for it.

- [ ] **Step 1: Make the working branch**

```bash
git switch maanvik/focus-design
git switch -c maanvik/focus-step1
```

- [ ] **Step 2: Merge**

```bash
git merge --no-ff m1-schedule-onboarding -m "Merge m1-schedule-onboarding: weekday and weekend schedules, onboarding questions" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Expected: `Merge made by the 'ort' strategy.` and no conflicts.

- [ ] **Step 3: Run the tests**

Run the test command. Expected: `** TEST SUCCEEDED **`. If anything fails, stop and report: this branch passed 429 tests on its own.

---

### Task 2: Merge `m1-health-import`

**Files:**
- Resolve: `docs/core-api.md` (1 conflict), `docs/debug-launch-arguments.md` (2 conflicts).
- Modify: `MapleKit/Sources/MapleServices/Demo/HealthSleepSeeder.swift`. It takes a `WeeklySleepSchedule` from now on; its callers already pass `collection.schedule`, which is one after Task 1.
- Modify: `MapleKit/Tests/MapleServicesTests/HealthSleepImporterTests.swift`.

**Interfaces:**
- Consumes: from Task 1, `WeeklySleepSchedule.schedule(forNight:calendar:)` and `WeeklySleepSchedule.variant(forNight:calendar:)`.
- Produces:
  - `HealthSleepSeeder.plan(nights:source:schedule: WeeklySleepSchedule, now:calendar:notBefore:)`, with the same `schedule: WeeklySleepSchedule` parameter on `samples(…)` and `seed(…)`;
  - `HealthSleepImporter` (MapleServices, injected as `sleep` in `MapleApp`).

- [ ] **Step 1: Start the merge**

```bash
git merge --no-ff m1-health-import
```

Expected: `CONFLICT (content): Merge conflict in docs/core-api.md` and `… in docs/debug-launch-arguments.md`. Automatic merge failed.

- [ ] **Step 2: Resolve `docs/core-api.md`**

There is one conflict block, between `<<<<<<< HEAD` and `>>>>>>> m1-health-import`. It sits in the Home section, just before `## Leaves: progress, next leaf, buds, Almost there`. Replace the whole block, markers included, with these two lines:

```markdown
- Inputs that don't exist yet are optional and default to the documented fallbacks: `nowState(at:lastNight:goodnightAt:focus:windDownActive:checkInDue:)`. Home passes `sleep.lastNightSleep(at: now)` as `lastNight` ("7h 12m" · "asleep 23:08 · up 06:20"; for iPhone's in-bed estimate the time in bed). A morning with neither last night's sleep nor a Goodnight shows tonight's wind-down start as a clock time ("22:15" · "wind-down tonight · bed 23:00"), never a countdown; the day shows the countdown to wind-down until focus ships.
- Lower level: `NowPhase.resolve(date:weekly:calendar:)` (or `schedule:` for one schedule every night), `PhaseWindows(weekly:)` (`day(containing:calendar:)` for a day's phase starts, `sampleDate(in:onDayOf:calendar:)` for previews), `HomeFormat` (durations "1h 20m", locale clock times).
```

- [ ] **Step 3: Resolve `docs/debug-launch-arguments.md`**

There are two conflict blocks.

**Block 1** is in the table, after the `-MapleDemoReduceMotion` row. Keep HEAD's two rows (`-MapleDemoFirstRunAutoplay`, `-MapleDemoOnboardingStep`) exactly as they are. Drop the health side's two older versions of those rows. Keep the health side's three new rows (`-MapleDemoSeedHealth`, `-MapleDemoSeedSource`, `-MapleDemoSeedStore`) exactly as they are, placed after HEAD's two. Delete the markers.

**Block 2** is after the "Rest example" line. Replace the whole block, markers included, with:

```markdown
Weekend examples: `-MapleDemoSpecies 23 -MapleDemoWeekendSchedule 00:30-09:00/60 -MapleDemoDay friday -MapleDemoPhase evening` is Home on a weekend night's evening (add `-MapleDemoTab rest` for the dial, with "Weekdays 23:00 → 07:00" under it); `-MapleDemoDay wednesday` is a weekday night ("Weekends 00:30 → 09:00").

The Reveal and Onboarding arguments act only on a demo launch (with at least one Core argument), so they never touch the member's files. Three exceptions act on a live launch on purpose, as a tap would: `-MapleDemoFirstRunAutoplay`, `-MapleDemoHealthContinue` and `-MapleDemoSeedHealth` (whose samples go into the simulator's Apple Health; the seed arguments never make a launch a demo).

Apple Health end to end (iPhone 17e): a real install and first run (`-MapleDemoFirstRunAutoplay 2`, below), then after midnight `xcrun simctl launch <udid> com.maanvikgupta.maple -MapleDemoPhase morning -MapleDemoPermissions health -MapleDemoSeedHealth 10 -MapleDemoSeedStore memory` shows Home's morning numeral from last night's seeded Watch sleep and the leaves the install night earned waiting; add `-MapleDemoTab herbarium` for the Herbarium, or `-MapleDemoPresent reveal` to open them. Without `-MapleDemoSeedStore memory` (and without Core arguments) the seeder writes into the simulator's Apple Health and the member's own files are used, which needs one tap on Apple's sheet.
```

Check that no markers are left:

```bash
grep -n '<<<<<<<\|>>>>>>>\|^=======$' docs/core-api.md docs/debug-launch-arguments.md
```

Expected: no output.

- [ ] **Step 4: Write the failing weekend test**

In `MapleKit/Tests/MapleServicesTests/HealthSleepImporterTests.swift`, find the suite that holds the test whose display name begins `"Seeded iPhone and other-app nights take their own rungs"`. That suite declares `private let schedule = SleepSchedule.standard`.
1. Change that declaration to `private let schedule = WeeklySleepSchedule.standard`.
2. In the test that computes `bedtimeOffsets`, change `NightLedger.date(schedule.bedtime, on:` to `NightLedger.date(schedule.weekday.bedtime, on:`.
3. Add this test to the same suite:

```swift
    @Test("Seeded nights follow the weekend schedule on weekend nights")
    func weekendSeeding() throws {
        // A weekend three hours later than weekdays, so a night seeded on the wrong schedule can't pass.
        let weekend = SleepSchedule(bedtime: ClockTime(hour: 2), wake: ClockTime(hour: 10), windDownMinutes: 45)
        let weekly = WeeklySleepSchedule(weekday: .standard, weekend: weekend)
        let now = at(2026, 10, 12, 12)
        let nights = SleepNightBuilder(calendar: utc).nights(
            from: HealthSleepSeeder.samples(nights: 7, source: .otherApp, schedule: weekly, now: now, calendar: utc)
        )
        #expect(nights.count == 7)
        #expect(nights.contains { WeeklySleepSchedule.variant(forNight: $0.night, calendar: utc) == .weekend })
        for night in nights {
            let bedtime = NightLedger.date(weekly.schedule(forNight: night.night, calendar: utc).bedtime, on: night.night, calendar: utc)
            let offset = night.onset.timeIntervalSince(bedtime)
            // The seeder moves sleep onset from 45 minutes early to 100 minutes late around that night's bedtime.
            #expect(offset >= -46 * 60 && offset <= 101 * 60, "\(night.night): \(offset / 60) min")
        }
    }
```

- [ ] **Step 5: Build the tests and confirm they fail**

Run the test command. Expected: the build fails in `HealthSleepSeeder.swift` and its callers, with errors such as `cannot convert value of type 'WeeklySleepSchedule' to expected argument type 'SleepSchedule'`.

- [ ] **Step 6: Port the seeder to the weekly schedule**

In `MapleKit/Sources/MapleServices/Demo/HealthSleepSeeder.swift`:
1. In all four signatures (`plan(…)`, `samples(…)`, the private `night(…)` and `seed(…)`), replace `schedule: SleepSchedule` with `schedule: WeeklySleepSchedule`.
2. In the private `night(_:schedule:calendar:notBefore:)`, replace the two lines that read `schedule.bedtime` and `schedule.wake` with:

```swift
        let tonight = schedule.schedule(forNight: evening, calendar: calendar)
        let bedtime = NightLedger.date(tonight.bedtime, on: evening, calendar: calendar)
        let wakeTime = NightLedger.date(tonight.wake, on: evening, calendar: calendar)
```

Nothing else changes. `HealthDemoSeeding.swift` and `HealthSleepImporter.launch` already pass `collection.schedule`, which is a `WeeklySleepSchedule`.

- [ ] **Step 7: Run the tests and confirm they pass**

Run the test command. Expected: `** TEST SUCCEEDED **`, including `Seeded nights follow the weekend schedule on weekend nights`.

- [ ] **Step 8: Commit the merge**

```bash
git add -A
git commit -m "Merge m1-health-import: sleep from Apple Health" -m "The demo seeder now plans each night on its own schedule (weekday or weekend)." -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Merge `m1-notifications`

**Files:**
- Resolve: `App/MapleApp.swift`.
- Modify:
  - `MapleKit/Sources/MapleCore/Notifications/UpcomingNight.swift`: nights from the weekly schedule;
  - `App/Features/Notifications/ReminderInputs.swift`;
  - `App/Features/Notifications/ReminderDemo.swift`;
  - `App/Features/Notifications/ReminderUpkeep.swift`.
- Test: `MapleKit/Tests/MapleCoreTests/ReminderPlanTests.swift`.

**Interfaces:**
- Consumes: `WeeklySleepSchedule.currentNight(at:calendar:)`, `WeeklySleepSchedule.times(forNight:calendar:)` and `ScheduleStore.weekly` (Task 1).
- Produces: `UpcomingNight.nights(for: WeeklySleepSchedule, around: Date, count: Int = ReminderPlan.horizonDays, calendar: Calendar) -> [UpcomingNight]`. It returns `count + 1` nights: last night, whose morning has started, then the next `count`.

- [ ] **Step 1: Start the merge**

```bash
git merge --no-ff m1-notifications
```

Expected: `CONFLICT (content): Merge conflict in App/MapleApp.swift`.

- [ ] **Step 2: Resolve `App/MapleApp.swift` by keeping both sides**

**Conflict 1** is among the `@State` properties. The result must contain both:

```swift
    /// Apple Health's sleep, read into the collection: the sleep leaves' only source (spec D9).
    @State private var sleep: HealthSleepImporter
    /// The wind-down reminder, kept scheduled by `ReminderUpkeep`.
    @State private var reminders = NotificationScheduler.launch()
```

**Conflict 2** is in the `.environment` chain. The result must contain both:

```swift
                .environment(sleep)
                .environment(reminders)
```

Delete all markers. (`reminders`' comment is already the one-reminder wording, so Task 4 doesn't have to revisit it.)

- [ ] **Step 3: Write the failing weekend test**

In `MapleKit/Tests/MapleCoreTests/ReminderPlanTests.swift`, in `struct UpcomingNightTests`, add after `midnightWrap()`:

```swift
    @Test("Weekend nights use the weekend schedule")
    func weekendNights() throws {
        let weekend = SleepSchedule(bedtime: ClockTime(hour: 0, minute: 30), wake: ClockTime(hour: 9), windDownMinutes: 60)
        let weekly = WeeklySleepSchedule(weekday: .standard, weekend: weekend)
        let nights = UpcomingNight.nights(for: weekly, around: at(2026, 10, 12, 12), calendar: utc)
        #expect(nights.count == 8)
        #expect(nights.contains { WeeklySleepSchedule.variant(forNight: $0.name(in: utc), calendar: utc) == .weekend })
        for night in nights {
            let expected = weekly.times(forNight: night.name(in: utc), calendar: utc)
            #expect(night.windDownStart == expected.windDownStart)
            #expect(night.bedtime == expected.bedtime)
            #expect(night.wake == expected.wake)
            #expect(night.morningStart == expected.morningStart)
        }
    }
```

In the same file, make the three call sites that pass a `SleepSchedule` pass a weekly one:
- In the file-level `plan(...)` helper: `UpcomingNight.nights(for: schedule, around: now, calendar: calendar)` becomes `UpcomingNight.nights(for: .everyNight(schedule), around: now, calendar: calendar)`.
- Both `UpcomingNight.nights(for: late, around:` calls (in `midnightWrap()` and in `skippedHour()`) become `UpcomingNight.nights(for: .everyNight(late), around:`.
- In the file-level `leaf(...)` helper: `RevealSchedule.releaseDate(for: unlock, schedule: schedule, calendar: calendar)` becomes `RevealSchedule.releaseDate(for: unlock, schedule: .everyNight(schedule), calendar: calendar)`.

The `.standard` call sites need no change: `.standard` resolves to `WeeklySleepSchedule.standard`. Don't add a `SleepSchedule` overload of `nights(for:)`. The trial merge showed it makes every `.standard` ambiguous.

- [ ] **Step 4: Run the tests and confirm they fail**

Run the test command. Expected: the build fails with `value of type 'PhaseWindows' has no member 'startMinute'` in `UpcomingNight.swift`.

- [ ] **Step 5: Port `UpcomingNight` to the weekly schedule**

In `MapleKit/Sources/MapleCore/Notifications/UpcomingNight.swift`, replace the whole `extension UpcomingNight { … }` (it holds `nights(for:around:count:calendar:)`, `night(endingAt:schedule:calendar:)` and `moments(of:around:days:calendar:)`) with:

```swift
extension UpcomingNight {
    /// The night whose morning started most recently (at or before `date`), then the next `count` nights, from the
    /// member's weekly schedule (`WeeklySleepSchedule.times(forNight:calendar:)`): weekend nights use the weekend
    /// schedule, and the times follow daylight-saving changes as the phases do.
    ///
    /// The first night gives `ReminderPlan` the last morning start; its own moments are in the past and schedule
    /// nothing.
    public static func nights(
        for weekly: WeeklySleepSchedule, around date: Date, count: Int = ReminderPlan.horizonDays, calendar: Calendar
    ) -> [UpcomingNight] {
        // Tonight is the night named by the day holding `date`; that day's morning was last night's morning start.
        let tonight = weekly.currentNight(at: date, calendar: calendar)
        return (-1..<max(0, count)).map { offset in
            let times = weekly.times(forNight: tonight.adding(days: offset, calendar: calendar), calendar: calendar)
            return UpcomingNight(
                windDownStart: times.windDownStart, bedtime: times.bedtime, wake: times.wake, morningStart: times.morningStart
            )
        }
    }
}
```

- [ ] **Step 6: Point the app's reminder wiring at the weekly schedule**

`App/Features/Notifications/ReminderInputs.swift`: in `upcomingNights(schedule:around:calendar:)`, delete the two `// TODO(integrator):` comment lines. Change the body to:

```swift
        UpcomingNight.nights(for: schedule.weekly, around: now, calendar: calendar)
```

`App/Features/Notifications/ReminderDemo.swift`: change `UpcomingNight.nights(for: schedule.schedule,` to `UpcomingNight.nights(for: schedule.weekly,`.

`App/Features/Notifications/ReminderUpkeep.swift`:
- In the computed `inputs`, change `schedule: schedule.schedule, savedAt:` to `schedule: schedule.weekly, savedAt:`.
- In `private struct ReminderInputsState`, change `var schedule: SleepSchedule` to `var schedule: WeeklySleepSchedule`, and `var nightSchedule: SleepSchedule` to `var nightSchedule: WeeklySleepSchedule`.

- [ ] **Step 7: Run the tests and confirm they pass**

Run the test command. Expected: `** TEST SUCCEEDED **`, including `Weekend nights use the weekend schedule`. The three `✔ Test run` lines should total 509 tests: the trial merge's 507, plus this test and Task 2's.

- [ ] **Step 8: Commit the merge**

```bash
git add -A
git commit -m "Merge m1-notifications: wind-down and morning-leaf reminders" -m "Reminders are planned from the weekly schedule, so weekend nights wind down on the weekend schedule." -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Remove the morning-leaf reminder (spec §8)

The spec allows no morning notifications, and rewards.md already says "no morning notification is sent". The wind-down reminder stays, with its switch on by default once iOS allows notifications.

This task also removes what only the morning reminder used:
- the `waiting` input to the plan, and `WaitingLeaf`;
- the tap routing (`ReminderRoute`, `pendingRoute`, `takeRoute()`, `handleTap`, the `maple.route` user-info key, and the reveal that `ReminderUpkeep` opened);
- the notification-center delegate. With no delegate, iOS shows nothing while Maple is open, which is what wind-down wanted anyway.

F1 adds back whatever its session-end notification needs.

**Files:**
- Rewrite: `MapleKit/Sources/MapleCore/Notifications/ReminderPlan.swift`.
- Modify:
  - `MapleKit/Sources/MapleServices/Notifications/NotificationScheduler.swift`;
  - `MapleKit/Sources/MapleServices/Settings/AppSettings.swift`;
  - `MapleKit/Sources/MapleDesign/Notifications/NotificationsPrimerView.swift`;
  - `App/Features/Notifications/ReminderUpkeep.swift`, `ReminderInputs.swift` and `ReminderDemo.swift`;
  - `App/Features/Settings/RemindersSettingsGroup.swift`.
- Test:
  - `MapleKit/Tests/MapleCoreTests/ReminderPlanTests.swift`;
  - `MapleKit/Tests/MapleServicesTests/NotificationSchedulerTests.swift`;
  - `MapleKit/Tests/MapleDesignTests/NotificationsPrimerTests.swift`.

**Interfaces produced:**
- `ReminderKind` has one case, `.windDown`. It no longer has `route` or `foregroundPresentation`.
- `ReminderSettings(windDown: Bool = true)`, with `.allOn` and `.allOff`.
- `ReminderPlan.Input(nights:settings:windDownOpenedAt:now:calendar:locale:)`: there is no `waiting`.
- `ReminderRequest` no longer has `route`.
- `AppSettings.reminders == ReminderSettings(windDown: windDownReminder)`. `AppSettings.morningLeafReminder` is gone.
- `NotificationsPrimerView.title == "A gentle reminder"` and `.message == "Only when it's time to wind down. Nothing else."`.

- [ ] **Step 1: Rewrite the reminder plan tests for wind-down only**

In `MapleKit/Tests/MapleCoreTests/ReminderPlanTests.swift`, keep the imports, `calendar(_:)`, `clock(_:_:)`, the `ReminderPlan.of(_:)` extension and the whole `UpcomingNightTests` suite (with Task 3's edits). Make these changes.

Replace the file-level `plan(...)` helper with:

```swift
/// A plan from one repeating schedule.
private func plan(
    _ schedule: SleepSchedule = .standard, now: Date, settings: ReminderSettings = .allOn,
    windDownOpenedAt: Date? = nil, calendar: Calendar = utc, locale: Locale = enGB
) -> ReminderPlan {
    ReminderPlan(.init(
        nights: UpcomingNight.nights(for: .everyNight(schedule), around: now, calendar: calendar), settings: settings,
        windDownOpenedAt: windDownOpenedAt, now: now, calendar: calendar, locale: locale
    ))
}
```

Delete the file-level `leaf(...)` helper.

In `struct ReminderPlanTests`:

**Leave unchanged:** `windDownEachNight()` (delete only its line `#expect(tonight.route == nil)`), `localeAwareTime()`, `windDownPassed()`, `windDownAlreadyOpened()`, `noWindDownWindow()`, `horizon()` and `skippedHour()`.

**Delete these tests:**
- `heldLeafMorning()`;
- `plural()`;
- `noLeafNoMorning()`;
- `pendingLeafOnce()`;
- `announcedThisMorning()`.

**Replace these tests, keeping each one's place in the file:**

```swift
    @Test("Nothing between bedtime and the morning start, ever: every reminder falls in wind-down")
    func nothingAtNight() {
        let schedules = [
            SleepSchedule.standard,
            SleepSchedule(bedtime: ClockTime(hour: 0, minute: 30), wake: ClockTime(hour: 8, minute: 30), windDownMinutes: 60),
            SleepSchedule(bedtime: ClockTime(hour: 21), wake: ClockTime(hour: 5), windDownMinutes: 30),
            SleepSchedule(bedtime: ClockTime(hour: 8), wake: ClockTime(hour: 16), windDownMinutes: 45),
        ]
        for schedule in schedules {
            for hour in stride(from: 0, to: 24, by: 3) {
                let now = at(2026, 10, 12, hour)
                for request in plan(schedule, now: now).requests {
                    let phase = NowPhase.resolve(date: request.fireDate, schedule: schedule, calendar: utc)
                    #expect(phase == .windDown, "\(request.id) at \(clock(request.fireDate))")
                }
            }
        }
    }

    @Test("Wind-down is the only reminder: nothing in the morning, ever")
    func onlyWindDown() {
        #expect(ReminderKind.allCases == [.windDown])
        for hour in stride(from: 0, to: 24, by: 2) {
            let result = plan(now: at(2026, 10, 12, hour))
            #expect(result.requests.allSatisfy { $0.kind == .windDown })
            #expect(result.requests.allSatisfy { clock($0.fireDate) == "22:15" })
        }
    }

    @Test("At most one wind-down reminder per night, even from overlapping nights")
    func onePerNight() {
        let now = at(2026, 10, 12, 21)
        let nights = UpcomingNight.nights(for: .standard, around: now, calendar: utc)
        let doubled = ReminderPlan(.init(nights: nights + nights, settings: .allOn, now: now, calendar: utc, locale: enGB))
        #expect(doubled.of(.windDown).count == 7)
        #expect(Set(doubled.requests.map(\.id)).count == doubled.requests.count)
        let days = doubled.of(.windDown).map { LocalDay($0.fireDate, calendar: utc) }
        #expect(Set(days).count == days.count)
    }

    @Test("Identifiers are deterministic, so rescheduling replaces instead of duplicating")
    func deterministic() {
        let first = plan(now: at(2026, 10, 12, 21))
        let again = plan(now: at(2026, 10, 12, 21))
        #expect(first == again)
        // An hour later the same nights keep the same identifiers.
        let later = plan(now: at(2026, 10, 12, 22))
        #expect(Set(later.requests.map(\.id)).isSubset(of: Set(first.requests.map(\.id))))
        #expect(first.requests.allSatisfy { $0.id.hasPrefix(ReminderKind.identifierPrefix) })
    }

    @Test("The switch turns the reminder off")
    func toggles() {
        let now = at(2026, 10, 12, 21)
        #expect(plan(now: now).of(.windDown).count == 7)
        #expect(plan(now: now, settings: ReminderSettings(windDown: false)).requests.isEmpty)
        #expect(plan(now: now, settings: .allOff).requests.isEmpty)
    }

    @Test("A bedtime after midnight: wind-down the evening before, named by that evening")
    func midnightWrap() throws {
        let late = SleepSchedule(bedtime: ClockTime(hour: 1), wake: ClockTime(hour: 9), windDownMinutes: 45)
        let windDown = try #require(plan(late, now: at(2026, 10, 12, 23)).of(.windDown).first)
        // Wind-down starts after midnight, at 00:15, and belongs to Monday night.
        #expect(windDown.fireDate == at(2026, 10, 13, 0, 15))
        #expect(windDown.id == "maple.reminder.windDown.2026-10-12")
        #expect(windDown.body == "Bed at 01:00.")
    }

    @Test("Across daylight-saving changes the reminders keep their local times")
    func daylightSaving() {
        let london = calendar("Europe/London")
        // Clocks go back on Sunday 25 October 2026 and forward on Sunday 29 March 2026.
        for start in [at(2026, 10, 22, 12, in: london), at(2026, 3, 26, 12, in: london)] {
            let windDowns = plan(now: start, calendar: london).of(.windDown)
            #expect(windDowns.count == 7)
            #expect(windDowns.allSatisfy { clock($0.fireDate, london) == "22:15" })
            #expect(windDowns.allSatisfy { $0.body == "Bed at 23:00." })
            #expect(Set(windDowns.map { LocalDay($0.fireDate, calendar: london) }).count == 7)
        }
    }

    @Test("A delivered wind-down reminder is cleared once it no longer holds")
    func staleDelivered() {
        // "Time to wind down" holds only during a wind-down the member hasn't started.
        #expect(!plan(now: at(2026, 10, 12, 22, 30)).staleDelivered.contains(.windDown))
        #expect(plan(now: at(2026, 10, 12, 22, 30), windDownOpenedAt: at(2026, 10, 12, 22, 20)).staleDelivered.contains(.windDown))
        #expect(plan(now: at(2026, 10, 12, 23, 30)).staleDelivered.contains(.windDown))
        #expect(plan(now: at(2026, 10, 12, 12)).staleDelivered.contains(.windDown))
    }

    @Test("Identifiers name their kind; anything else isn't Maple's")
    func kinds() {
        #expect(ReminderKind(identifier: "maple.reminder.windDown.2026-10-12") == .windDown)
        #expect(ReminderKind(identifier: "maple.reminder.morningLeaf.2026-10-12") == nil)
        #expect(ReminderKind(identifier: "maple.reminder.other") == nil)
        #expect(ReminderKind(identifier: "com.example.windDown") == nil)
    }

    @Test("Copy is calm: one short line each, no exclamation marks, no emoji")
    func copy() {
        let lines = [ReminderCopy.windDownTitle, ReminderCopy.windDownBody(bedtime: at(2026, 10, 12, 23), calendar: utc, locale: enGB)]
        for line in lines {
            #expect(!line.contains("!"))
            #expect(line.count <= 32)
            #expect(wordCount(line) <= 6)
            #expect(line.unicodeScalars.allSatisfy { !$0.properties.isEmojiPresentation })
            #expect(line.first?.isUppercase == true || line.first?.isNumber == true)
        }
    }
```

- [ ] **Step 2: Rewrite the scheduler and settings tests**

In `MapleKit/Tests/MapleServicesTests/NotificationSchedulerTests.swift`, leave `FakeNotificationCenter` (above `@Suite("Notification scheduler")`) unchanged. In `struct NotificationSchedulerTests`, replace the `plan(at:settings:waiting:)` helper and delete `heldLeaf()`:

```swift
    private func plan(at date: Date, settings: ReminderSettings = .allOn) -> ReminderPlan {
        ReminderPlan(.init(
            nights: UpcomingNight.nights(for: .standard, around: date, calendar: utc), settings: settings,
            now: date, calendar: utc, locale: Locale(identifier: "en_GB")
        ))
    }
```

**Leave unchanged:** `onlyMaple()`, `needsPermission()`, `horizon()`, `prompt()`, `demoLaunchesDontSchedule()` and `authorizationMapping()`.

**Delete:** `route()` and `foreground()`.

**Replace these tests, keeping each one's place:**

```swift
    @Test("Rescheduling leaves exactly the plan's requests pending, at their wall-clock times")
    func reschedule() async throws {
        let center = FakeNotificationCenter()
        let scheduler = NotificationScheduler(center: center, clock: .fixed(now))
        let plan = plan(at: now)
        await scheduler.reschedule(plan: plan)
        #expect(center.mapleIdentifiers == Set(plan.requests.map(\.id)))
        #expect(center.mapleIdentifiers.count == 7)
        #expect(scheduler.scheduled == plan.requests)
        let tonight = try #require(center.pending["maple.reminder.windDown.2026-10-12"])
        #expect(tonight.trigger == .date(DateComponents(year: 2026, month: 10, day: 12, hour: 22, minute: 15, second: 0)))
        #expect(tonight.request.interruption == .active)
    }

    @Test("Rescheduling again replaces rather than duplicates, and drops what the plan no longer has")
    func replaces() async {
        let center = FakeNotificationCenter()
        let scheduler = NotificationScheduler(center: center, clock: .fixed(now))
        await scheduler.reschedule(plan: plan(at: now))
        await scheduler.reschedule(plan: plan(at: now))
        #expect(center.mapleIdentifiers.count == 7)
        // Wind-down turned off: nothing is left.
        await scheduler.reschedule(plan: plan(at: now, settings: .allOff))
        #expect(center.mapleIdentifiers.isEmpty)
    }

    @Test("A morning reminder left pending by an earlier build is removed")
    func leftoverMorningReminderRemoved() async {
        let center = FakeNotificationCenter(pending: ["maple.reminder.morningLeaf.2026-10-12"])
        let scheduler = NotificationScheduler(center: center, clock: .fixed(now))
        await scheduler.reschedule(plan: plan(at: now))
        #expect(center.pending["maple.reminder.morningLeaf.2026-10-12"] == nil)
        #expect(center.mapleIdentifiers.count == 7)
    }

    @Test("Two reschedules at once never interleave: the later plan wins")
    func serialised() async {
        let center = FakeNotificationCenter()
        let scheduler = NotificationScheduler(center: center, clock: .fixed(now))
        let first = Task { await scheduler.reschedule(plan: plan(at: now)) }
        let second = Task { await scheduler.reschedule(plan: plan(at: now, settings: .allOff)) }
        await first.value
        await second.value
        #expect(center.mapleIdentifiers.isEmpty)
    }

    @Test("A delivered wind-down reminder that no longer holds leaves Notification Center")
    func clearsDelivered() async {
        let center = FakeNotificationCenter()
        center.delivered = ["maple.reminder.windDown.2026-10-11", "com.example.other"]
        let scheduler = NotificationScheduler(center: center, clock: .fixed(at(2026, 10, 12, 12)))
        // Midday: last night's wind-down reminder is out of date; the other app's stays.
        await scheduler.reschedule(plan: plan(at: at(2026, 10, 12, 12)))
        #expect(center.removedDelivered == ["maple.reminder.windDown.2026-10-11"])
        #expect(center.delivered == ["com.example.other"])
    }
```

Check `FakeNotificationCenter(pending:)` before relying on it. `onlyMaple()` already calls `FakeNotificationCenter(pending: ["com.example.other", "focus.session"])`, so the initializer takes identifiers. If it takes a different type, build the leftover the way `onlyMaple()` builds its own.

In `struct ReminderSettingsTests`, replace both tests with:

```swift
    @Test("The wind-down reminder is on by default, and its switch is saved")
    func persisted() throws {
        let url = try temporaryDirectory().appendingPathComponent(AppSettings.file)
        let settings = AppSettings(storage: JSONStorage(.file(url)), regionCode: "GB")
        #expect(settings.windDownReminder)
        #expect(settings.reminders == .allOn)
        settings.windDownReminder = false
        let reloaded = AppSettings(storage: JSONStorage(.file(url)), regionCode: "GB")
        #expect(!reloaded.windDownReminder)
        #expect(reloaded.reminders == .allOff)
    }

    @Test("A settings file from before the reminders existed turns wind-down on")
    func olderFile() throws {
        let old = #"{"version":1,"hemisphere":"southern","sleepGoalMinutes":480,"revealSound":true}"#
        let snapshot = try JSONDecoder().decode(SettingsSnapshot.self, from: Data(old.utf8))
        #expect(snapshot.windDownReminder)
        #expect(snapshot.hemisphere == .southern)
        let roundTrip = try JSONDecoder().decode(SettingsSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(roundTrip == snapshot)
    }

    @Test("A settings file with the old morning-leaf switch still loads, and the switch is dropped on save")
    func olderFileWithMorningSwitch() throws {
        let old = #"{"version":1,"hemisphere":"northern","sleepGoalMinutes":450,"revealSound":false,"windDownReminder":false,"morningLeafReminder":true}"#
        let snapshot = try JSONDecoder().decode(SettingsSnapshot.self, from: Data(old.utf8))
        #expect(!snapshot.windDownReminder)
        #expect(snapshot.sleepGoalMinutes == 450)
        let saved = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        #expect(!saved.contains("morningLeaf"))
    }
```

- [ ] **Step 3: Update the primer copy test**

In `MapleKit/Tests/MapleDesignTests/NotificationsPrimerTests.swift`, replace the `copy()` test with:

```swift
    @Test("The primer names the only reminder, in two calm sentences")
    func copy() {
        let message = NotificationsPrimerView.message
        #expect(message.split(separator: ".").count == 2)
        #expect(message.contains("wind down"))
        #expect(!message.contains("leaf") && !message.contains("morning"))
        #expect(message.hasSuffix("Nothing else."))
        #expect(NotificationsPrimerView.title == "A gentle reminder")
        for line in [NotificationsPrimerView.title, message, NotificationsPrimerView.allowTitle, NotificationsPrimerView.notNowTitle] {
            #expect(!line.contains("!"))
            #expect(line.first?.isUppercase == true)
        }
        #expect(NotificationsPrimerView.allowTitle == "Allow reminders")
        #expect(NotificationsPrimerView.notNowTitle == "Not now")
    }
```

- [ ] **Step 4: Run the tests and confirm they fail**

Run the test command. Expected: the tests still build, because the old `ReminderSettings` and `ReminderPlan.Input` initialisers default the morning parameters. These fail:
- `onlyWindDown()`: `ReminderKind.allCases` still holds `.morningLeaf`;
- `kinds()`: a morning-leaf identifier still parses;
- `persisted()`: `reminders` isn't `.allOff` while the morning switch is on;
- `olderFileWithMorningSwitch()`: the saved file still has `morningLeafReminder`;
- the primer's `copy()`.

- [ ] **Step 5: Rewrite `ReminderPlan.swift`**

Replace the whole of `MapleKit/Sources/MapleCore/Notifications/ReminderPlan.swift` with:

```swift
import Foundation

/// The one local notification Maple sends: "Time to wind down". There is no morning notification (rewards.md; focus
/// spec §8), so a waiting leaf is only ever shown in the app.
public enum ReminderKind: String, Sendable, Hashable, CaseIterable {
    /// "Time to wind down" at the start of wind-down. It never mentions leaves or progress (rewards.md).
    case windDown

    /// Every identifier Maple schedules starts with this, so rescheduling touches nothing else.
    public static let identifierPrefix = "maple.reminder."

    /// The prefix of this kind's identifiers ("maple.reminder.windDown.").
    public var identifierPrefix: String { Self.identifierPrefix + rawValue + "." }

    /// The notification thread, so iOS stacks each kind on its own.
    public var threadID: String { "maple." + rawValue }

    /// The kind a Maple identifier belongs to; nil for anything else.
    public init?(identifier: String) {
        guard let kind = Self.allCases.first(where: { identifier.hasPrefix($0.identifierPrefix) }) else { return nil }
        self = kind
    }
}

/// How a notification arrives (`UNNotificationInterruptionLevel`, without importing UserNotifications).
public enum ReminderInterruption: String, Sendable, Hashable {
    /// Silent: no sound, the screen stays dark; it waits on the Lock Screen and in Notification Center.
    case passive
    /// The usual alert, which Focus modes (Sleep included) may hold back.
    case active
}

/// One local notification to schedule.
public struct ReminderRequest: Sendable, Hashable, Identifiable {
    /// Deterministic: the kind and the night it belongs to ("maple.reminder.windDown.2026-10-12", named by the
    /// night's evening), so rescheduling replaces a request rather than adding a second one.
    public var id: String
    public var kind: ReminderKind
    public var fireDate: Date
    /// The fire date as a local wall-clock time (year to second, no time zone), so the reminder keeps its local
    /// time if the member's time zone changes before Maple reschedules.
    public var fireComponents: DateComponents
    public var title: String
    public var body: String
    public var threadID: String
    public var interruption: ReminderInterruption
    /// The default notification sound; false for a silent one.
    public var playsSound: Bool

    /// - Parameter calendar: The member's calendar, which turns `fireDate` into its local wall-clock time.
    public init(
        id: String, kind: ReminderKind, fireDate: Date, calendar: Calendar, title: String, body: String,
        threadID: String, interruption: ReminderInterruption, playsSound: Bool
    ) {
        self.id = id
        self.kind = kind
        self.fireDate = fireDate
        fireComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
        self.title = title
        self.body = body
        self.threadID = threadID
        self.interruption = interruption
        self.playsSound = playsSound
    }
}

/// Which reminders the member wants (Profile › Settings). On until they turn it off; nothing is sent until iOS
/// allows Maple's notifications.
public struct ReminderSettings: Sendable, Hashable {
    public var windDown: Bool

    public init(windDown: Bool = true) {
        self.windDown = windDown
    }

    public static let allOn = ReminderSettings()
    public static let allOff = ReminderSettings(windDown: false)

    public func allows(_ kind: ReminderKind) -> Bool {
        switch kind {
        case .windDown: windDown
        }
    }
}

/// The reminder's words (calm, sentence case, one short line each, no emoji or exclamation marks, never guilt).
public enum ReminderCopy {
    public static let windDownTitle = "Time to wind down"

    /// "Bed at 23:00." or "Bed at 11:00 PM.", in the member's clock style.
    public static func windDownBody(bedtime: Date, calendar: Calendar, locale: Locale) -> String {
        "Bed at \(HomeFormat.clock(HomeFormat.clockTime(of: bedtime, calendar: calendar), locale: locale))."
    }
}

/// The local notifications Maple should have scheduled right now. Pure: the app builds the input from its stores,
/// and `NotificationScheduler` replaces Maple's pending requests with `requests`.
///
/// Rules:
/// - **Wind-down** at each night's wind-down start: "Time to wind down" · "Bed at 23:00.". Not once that moment
///   has passed, not on a night with no wind-down (it starts at bedtime), and not on a night whose wind-down mode
///   the member has already opened (from 2 hours before wind-down until bedtime, the Evening and Wind-down
///   phases in which it can be opened).
/// - At most one per night, named by the night's evening; a second night with the same name (an overlap in the
///   input) adds nothing.
/// - Nothing ever fires between a bedtime and the next morning start, and nothing is sent in the morning.
/// - Only within the next 7 days (`horizonDays`), well under iOS's 64 pending requests.
/// - Turned off, it schedules nothing.
public struct ReminderPlan: Sendable, Equatable {
    /// Days ahead the plan covers.
    public static let horizonDays = 7
    /// How long before wind-down starts wind-down mode can be opened (the Evening phase, spec §3.3).
    public static let windDownLead: TimeInterval = 2 * 3600

    public struct Input: Sendable {
        /// Nights in order. Nights whose moments have passed are fine; they schedule nothing.
        public var nights: [UpcomingNight]
        public var settings: ReminderSettings
        /// When wind-down mode was last opened (the bedside log's start); nil if never.
        public var windDownOpenedAt: Date?
        public var now: Date
        /// The member's calendar, for naming nights and reading the bedtime's clock time.
        public var calendar: Calendar
        public var locale: Locale

        public init(
            nights: [UpcomingNight], settings: ReminderSettings, windDownOpenedAt: Date? = nil, now: Date,
            calendar: Calendar, locale: Locale
        ) {
            self.nights = nights
            self.settings = settings
            self.windDownOpenedAt = windDownOpenedAt
            self.now = now
            self.calendar = calendar
            self.locale = locale
        }
    }

    /// What to schedule, in fire order.
    public let requests: [ReminderRequest]
    /// Kinds whose delivered notifications no longer hold and should leave Notification Center: wind-down outside
    /// a wind-down the member hasn't started.
    public let staleDelivered: Set<ReminderKind>

    public init(requests: [ReminderRequest], staleDelivered: Set<ReminderKind> = []) {
        self.requests = requests
        self.staleDelivered = staleDelivered
    }

    /// Nothing scheduled, nothing cleared.
    public static let empty = ReminderPlan(requests: [])

    public init(_ input: Input) {
        let nights = input.nights.sorted { $0.morningStart < $1.morningStart }
        let horizon = input.now.addingTimeInterval(TimeInterval(Self.horizonDays) * 24 * 3600)
        var requests: [ReminderRequest] = []
        var named: Set<String> = []

        for night in nights {
            let name = night.name(in: input.calendar).description
            // A night that overlaps one already planned (the same evening) adds nothing.
            guard named.insert(name).inserted,
                  let request = Self.windDown(for: night, name: name, input: input),
                  request.fireDate > input.now, request.fireDate <= horizon,
                  !Self.isDuringSleep(request.fireDate, nights: nights)
            else { continue }
            requests.append(request)
        }

        self.requests = requests.sorted { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }
        self.staleDelivered = Self.stale(input: input, nights: nights)
    }

    // MARK: Rules

    private static func windDown(for night: UpcomingNight, name: String, input: Input) -> ReminderRequest? {
        guard input.settings.windDown, night.windDownStart < night.bedtime else { return nil }
        if let opened = input.windDownOpenedAt, openedWindDown(of: night, at: opened) { return nil }
        let kind = ReminderKind.windDown
        return ReminderRequest(
            id: kind.identifierPrefix + name, kind: kind, fireDate: night.windDownStart, calendar: input.calendar,
            title: ReminderCopy.windDownTitle,
            body: ReminderCopy.windDownBody(bedtime: night.bedtime, calendar: input.calendar, locale: input.locale),
            threadID: kind.threadID, interruption: .active, playsSound: true
        )
    }

    /// Wind-down mode opened in this night's Evening or Wind-down.
    private static func openedWindDown(of night: UpcomingNight, at opened: Date) -> Bool {
        opened >= night.windDownStart.addingTimeInterval(-windDownLead) && opened < night.bedtime
    }

    /// Strictly between some night's bedtime and its morning start.
    private static func isDuringSleep(_ date: Date, nights: [UpcomingNight]) -> Bool {
        nights.contains { date > $0.bedtime && date < $0.morningStart }
    }

    private static func stale(input: Input, nights: [UpcomingNight]) -> Set<ReminderKind> {
        let inWindDown = nights.contains { night in
            input.now >= night.windDownStart && input.now < night.bedtime
                && !(input.windDownOpenedAt.map { openedWindDown(of: night, at: $0) } ?? false)
        }
        return inWindDown ? [] : [.windDown]
    }
}
```

- [ ] **Step 6: Strip routing and the delegate from `NotificationScheduler.swift`**

In `MapleKit/Sources/MapleServices/Notifications/NotificationScheduler.swift`:
1. In `UserNotificationCenter`, delete the `routeKey` constant and its doc comment, and the line `if let route = request.route { content.userInfo = [Self.routeKey: route.rawValue] }`.
2. Replace the doc comment above `@Observable public final class NotificationScheduler` with:

```swift
/// Maple's local notification: "Time to wind down", nothing else (focus spec §8). One instance for the app,
/// created by `MapleApp` and injected with `.environment(_:)`.
///
/// ```swift
/// @Environment(NotificationScheduler.self) private var reminders
///
/// reminders.authorization                     // .notDetermined, .denied or .allowed
/// await reminders.requestAuthorization()      // iOS's prompt (alerts and sounds, no badge)
/// await reminders.reschedule(plan: plan)      // Maple's pending requests become exactly the plan's
/// ```
///
/// While Maple is open iOS shows nothing (there is no notification-center delegate); a tap just opens the app.
```

3. Delete the `pendingRoute` property and its doc comment, and the `delegate` property.
4. Replace `live()` and its doc comment with:

```swift
    /// The app's scheduler, on the system notification center.
    public static func live() -> NotificationScheduler {
        NotificationScheduler(center: UserNotificationCenter())
    }
```

5. Delete `takeRoute()`, `handleTap(identifier:)` and their doc comments.
6. Delete the whole `final class ReminderNotificationDelegate` (and its doc comment) at the end of the file.

- [ ] **Step 7: Drop the morning switch from `AppSettings.swift`**

In `MapleKit/Sources/MapleServices/Settings/AppSettings.swift`:
- In `SettingsSnapshot`, delete:
  - the `morningLeafReminder` property and its doc comment;
  - its initializer parameter `, morningLeafReminder: Bool = true` and the assignment `self.morningLeafReminder = morningLeafReminder`;
  - `, morningLeafReminder` from `CodingKeys`;
  - the decode line `morningLeafReminder = …`;
  - the encode line `try c.encode(morningLeafReminder, …)`.
- On `AppSettings`, delete the `morningLeafReminder` property and its doc comment.
- Replace `reminders` with:

```swift
    /// The reminder switch, as `ReminderPlan` reads it.
    public var reminders: ReminderSettings {
        ReminderSettings(windDown: windDownReminder)
    }
```

- In the doc comment above `AppSettings`, change "the reveal sound and the two reminders (spec §8.7)" to "the reveal sound and the wind-down reminder (spec §8.7)".

- [ ] **Step 8: Update the primer's words**

In `MapleKit/Sources/MapleDesign/Notifications/NotificationsPrimerView.swift`, replace:

```swift
    nonisolated public static let title = "Two gentle reminders"
    /// What Maple sends, and that it sends nothing more.
    nonisolated public static let message = "One when it's time to wind down, and one in the morning when a leaf is waiting. Nothing else."
```

with:

```swift
    nonisolated public static let title = "A gentle reminder"
    /// What Maple sends, and that it sends nothing more.
    nonisolated public static let message = "Only when it's time to wind down. Nothing else."
```

- [ ] **Step 9: Update the app's reminder wiring**

`App/Features/Notifications/ReminderInputs.swift`:
- Replace the doc comment on `enum ReminderInputs` with: `/// Builds `ReminderPlan`'s input from the app's stores: the coming nights of the member's weekly schedule, the reminder switch and whether wind-down mode has been opened. `ReminderUpkeep` reschedules with it whenever one of those changes.`
- Replace the body of `plan(collection:schedule:settings:bedside:now:locale:)` with:

```swift
        let calendar = collection.context.calendar
        return ReminderPlan(.init(
            nights: upcomingNights(schedule: schedule, around: now, calendar: calendar), settings: settings.reminders,
            windDownOpenedAt: bedside.session.startedAt, now: now, calendar: calendar, locale: locale
        ))
```

`App/Features/Notifications/ReminderUpkeep.swift`:
- Replace the type's doc comment with:

```swift
/// Keeps Maple's wind-down reminder in step with the member's day: reschedules
/// (`NotificationScheduler.reschedule(plan:)`) on every foreground and whenever the plan's inputs change (a schedule
/// save, the reminder switch, wind-down mode opening, iOS's permission answer, and a time-zone or clock change).
```

- Delete `@State private var showsReveal = false`.
- Delete the `.onChange(of: reminders.pendingRoute, initial: true) { … }` modifier and `.fullScreenCover(isPresented: $showsReveal) { RevealFlow() }`.
- Delete `private func open(_ route: ReminderRoute)`.
- In `inputs`, delete the argument `waiting: collection.waiting.map(\.speciesID),`.
- In `ReminderInputsState`, delete `var waiting: [String]`.
- Change the modifier's doc comment (`func reminderUpkeep()`) to "Keeps the reminder scheduled (`ReminderUpkeep`). Apply it once, at the root."

If the `collection` environment property is no longer read anywhere in `ReminderUpkeep`, delete it too (the DEBUG `ReminderDemo.postIfRequested` call still passes `collection:`, so it is probably still used).

`App/Features/Notifications/ReminderDemo.swift`:
- In the doc comment, change `-MapleDemoNotify windDown|morning` to `-MapleDemoNotify windDown`, and delete the clause "; the morning leaf shows as a banner over Maple too".
- In `requestedKind`, delete the line `case "morning", "morningleaf": .morningLeaf`.
- In `postIfRequested`, delete the whole `case .morningLeaf:` branch. The `switch kind` keeps only `case .windDown:`.

`App/Features/Settings/RemindersSettingsGroup.swift`:
- Delete the `ProfileSettingRow("Morning leaf", …) { … }` row (3 lines).
- Change the doc comment's first sentence to "Settings › the wind-down reminder (spec §8.7) as a Level-1 group, saved at once through `AppSettings` and rescheduled by `ReminderUpkeep`."

Then search for leftovers:

```bash
grep -rn 'morningLeaf\|ReminderRoute\|pendingRoute\|takeRoute\|handleTap\|WaitingLeaf\|ReminderNotificationDelegate\|foregroundPresentation' App MapleKit
```

Expected: the only matches are strings in tests:
- `NotificationSchedulerTests.swift`: the identifier in `leftoverMorningReminderRemoved()`, and the JSON and `"morningLeaf"` check in `olderFileWithMorningSwitch()`;
- `ReminderPlanTests.swift`: the identifier in `kinds()`.

If any other file matches, remove that use.

- [ ] **Step 10: Run the tests and confirm they pass**

Run the test command. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 11: Check for warnings**

```bash
SIMULATOR="iPhone 17" Scripts/build.sh 2>&1 | grep -E 'warning:' | grep -v 'appintentsmetadataprocessor' | sort -u
```

Expected: no output.

- [ ] **Step 12: Commit**

```bash
git add -A
git commit -m "Remove the morning-leaf reminder" -m "Maple sends no morning notification (rewards.md; focus spec §8). Wind-down is the only reminder; the tap routing and notification delegate only the morning reminder used are gone. A morning reminder left pending by an earlier build is removed at the next reschedule." -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: The reminders primer in onboarding

Onboarding's `.notifications` step is still a placeholder that continues at once. Make it show `NotificationsPrimerStep` when iOS hasn't been asked yet, and continue at once otherwise.

**Files:**
- Modify:
  - `App/Features/Onboarding/OnboardingPrimers.swift` (the `OnboardingNotificationsStep` view);
  - `App/Features/Onboarding/PlantYourMapleView.swift` (a TODO comment, the doc comment, autoplay).

**Interfaces:**
- Consumes:
  - `NotificationsPrimerStep(onContinue:)` and `NotificationsPrimerStep.isNeeded(_:)` (App, from `m1-notifications`);
  - `NotificationScheduler` from the environment (`MapleApp` injects it at the root, above onboarding).
- Produces: `OnboardingNotificationsStep(onDone:)`, unchanged in signature.

- [ ] **Step 1: Replace the placeholder view**

In `App/Features/Onboarding/OnboardingPrimers.swift`, replace the doc comment and the whole `struct OnboardingNotificationsStep` with:

```swift
/// The notifications step, between Apple Health and the sprout: the reminders primer (`NotificationsPrimerStep`,
/// "Allow reminders" or "Not now") while iOS hasn't been asked; once it has (a reinstall, or a member who answered
/// iOS elsewhere) there is nothing to ask, so the step continues at once and draws only the background.
/// `onDone` is called exactly once; `OnboardingStore` then saves the answer and the flow moves on to the sprout.
struct OnboardingNotificationsStep: View {
    var onDone: () -> Void

    @Environment(\.theme) private var theme
    @Environment(NotificationScheduler.self) private var reminders
    @State private var finished = false

    var body: some View {
        if NotificationsPrimerStep.isNeeded(reminders) {
            NotificationsPrimerStep(onContinue: finish)
        } else {
            theme.colors.background
                .ignoresSafeArea()
                .accessibilityHidden(true)
                .task { finish() }
        }
    }

    /// Answering "Allow reminders" changes iOS's answer, which also swaps the primer for the background; the guard
    /// keeps that from finishing twice.
    private func finish() {
        guard !finished else { return }
        finished = true
        onDone()
    }
}
```

The file already imports `MapleServices`, which declares `NotificationScheduler`.

- [ ] **Step 2: Remove the TODO and fix the doc comment in `PlantYourMapleView.swift`**

- In `case .notifications:`, delete the line `// TODO(integrator): the notifications primer goes here (see `OnboardingNotificationsStep`).`
- In the type's doc comment, step 3 reads "…then the notifications primer's place (`OnboardingStep .notifications`)". Change it to "…then the reminders primer (`OnboardingNotificationsStep`, skipped once iOS has been asked)".

- [ ] **Step 3: Make autoplay answer the primer**

In `PlantYourMapleView.swift`, inside the autoplay loop (the `while step == .setup, let current = setupStep, current != .sprout` switch), replace:

```swift
                case .notifications, .sprout:
                    // The notifications step moves on by itself.
                    try? await Task.sleep(for: .seconds(0.3))
```

with:

```swift
                case .notifications:
                    // "Not now" on the reminders primer (iOS's own prompt needs a real tap).
                    try? await Task.sleep(for: .seconds(pause))
                    if setupStep == .notifications { answered(.notifications) }
                case .sprout:
                    try? await Task.sleep(for: .seconds(0.3))
```

`answered(_:)` is the function the `.health` case already calls (`answered(.health)`). If the step continued at once because iOS had already been asked, `setupStep` has moved on, and the guard makes this a no-op.

- [ ] **Step 4: Build and run the tests**

Run the test command. Expected: `** TEST SUCCEEDED **` with no new failures. The onboarding logic tests in `OnboardingTests` and `OnboardingStoreTests` cover the step order and are unchanged.

- [ ] **Step 5: See the step in the simulator (iOS not asked yet)**

```bash
SIMULATOR="iPhone 17" Scripts/build.sh
xcrun simctl boot "iPhone 17" 2>/dev/null; xcrun simctl uninstall "iPhone 17" com.maanvikgupta.maple
APP=$(find "$HOME/Library/Developer/Xcode/DerivedData/Maple-$(pwd -P | shasum | cut -c1-8)/Build/Products/Debug-iphonesimulator" -maxdepth 1 -name 'Maple.app')
xcrun simctl install "iPhone 17" "$APP"
xcrun simctl launch "iPhone 17" com.maanvikgupta.maple -MapleDemoFresh YES -MapleDemoPresent onboarding -MapleDemoOnboardingStep notifications
sleep 4; xcrun simctl io "iPhone 17" screenshot /tmp/maple-notifications-step.png
```

Open the screenshot. Expected: the full-screen primer with a leaf, "A gentle reminder", "Only when it's time to wind down. Nothing else.", "Allow reminders" and "Not now", on the dark background.

- [ ] **Step 6: Check the already-asked case (Review focus 4)**

`-MapleDemoNotifyStatus allowed` makes the scheduler report that iOS has already answered:

```bash
xcrun simctl launch --terminate-running-process "iPhone 17" com.maanvikgupta.maple -MapleDemoFresh YES -MapleDemoPresent onboarding -MapleDemoOnboardingStep notifications -MapleDemoNotifyStatus allowed
sleep 4; xcrun simctl io "iPhone 17" screenshot /tmp/maple-notifications-asked.png
```

Expected: the screenshot shows the sprout (the neutral bud on the dark ground), not the primer and not a blank background.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Onboarding shows the reminders primer" -m "The notifications step shows NotificationsPrimerStep while iOS hasn't been asked and continues at once otherwise; first-run autoplay answers it with Not now." -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Docs and full check

**Files:**
- Modify: `docs/core-api.md` (the Reminders section), `docs/debug-launch-arguments.md` (3 rows), `docs/decisions.md` (a new entry).

- [ ] **Step 1: Rewrite the Reminders section of `docs/core-api.md`**

Replace everything from `## Reminders (local notifications)` up to, but not including, `## Recording behaviour` with:

````markdown
## Reminders (local notifications)

Maple sends one notification and nothing else: **"Time to wind down"** · "Bed at 23:00." at each night's wind-down start. There is no morning notification (rewards.md; focus spec §8). `App/Features/Notifications/ReminderUpkeep.swift` keeps it scheduled; screens only read the scheduler.

```swift
@Environment(NotificationScheduler.self) private var reminders   // MapleApp injects it
reminders.authorization                // .notDetermined, .denied or .allowed (read again on every foreground)
await reminders.requestAuthorization() // iOS's prompt: alerts and sounds, never badges
settings.windDownReminder              // AppSettings switch, on by default; sent only once iOS allows
```

- **The plan.** `ReminderPlan(.init(nights:settings:windDownOpenedAt:now:calendar:locale:))` (MapleCore, pure) gives `requests` (deterministic identifiers `maple.reminder.windDown.<night>`, fire dates as local wall-clock components, title, body, thread, interruption level) and `staleDelivered` (a delivered reminder that no longer holds, cleared from Notification Center). Nights are `UpcomingNight` values (wind-down start, bedtime, wake, morning start) from the member's weekly schedule: `UpcomingNight.nights(for: schedule.weekly, around:calendar:)`, so weekend nights wind down on the weekend schedule. Wind-down is skipped once wind-down mode has been opened that night (`BedsideLog`'s start). Nothing fires between bedtime and the morning start.
- **Scheduling.** `reminders.reschedule(plan:)` makes Maple's pending requests exactly the plan's (only `maple.reminder.` identifiers, so a morning reminder left by an earlier build is removed; at most the next 7 days; nothing while iOS doesn't allow it). `ReminderUpkeep` calls it on every foreground and whenever its inputs change: a schedule save, the switch, wind-down mode opening, iOS's answer, a time-zone or clock change. DEBUG demo launches never reschedule.
- **In the foreground.** Maple sets no notification-center delegate, so iOS shows nothing while Maple is open; a tap just opens the app.
- **Asking.** Settings shows the switch with a status line: "Allow reminders" opens `NotificationsPrimerSheet` (`NotificationsPrimerView` in MapleDesign: the member's featured leaf, "A gentle reminder", "Only when it's time to wind down. Nothing else.", "Allow reminders", "Not now") before iOS has been asked, and "Turn on in Settings" opens Maple's notification settings once the member has said no. In the first run, onboarding's notifications step (`OnboardingNotificationsStep`) shows `NotificationsPrimerStep(onContinue:)` full screen while iOS hasn't been asked, and continues at once once it has.

````

- [ ] **Step 2: Update `docs/debug-launch-arguments.md`**

In the `-MapleDemoFirstRunAutoplay` row, replace "the notifications step (a placeholder that moves on by itself)" with "\"Not now\" on the reminders primer (skipped when iOS has already been asked)".

In the `-MapleDemoOnboardingStep` row, replace "`notifications` (its placeholder, which continues at once)" with "`notifications` (the reminders primer; it continues at once when iOS has already been asked)".

Replace the whole `-MapleDemoNotify` row with:

```markdown
| `-MapleDemoNotify` | `windDown` | Notifications (`ReminderDemo`) | Posts the wind-down reminder with its real words ("Time to wind down" · "Bed at 23:00.") 5 seconds after launch, asking iOS first if Maple hasn't asked yet. While Maple is open iOS shows nothing, so bring another app forward (`xcrun simctl launch <udid> com.apple.Preferences`) to see its banner. It posts a real notification on the simulator, nothing else. The simulator can't allow notifications from the command line (`simctl privacy` has no notifications service, and `simctl push` is refused until the app is allowed), so tap "Allow" on iOS's prompt once; later launches post straight away. |
```

- [ ] **Step 3: Add a decision entry**

Append to `docs/decisions.md`:

```markdown
## 2026-10-11 — M1 branches merged; no morning notification
The three parked M1 branches (weekday and weekend schedules with the onboarding questions, the Apple Health importer, reminders) are merged into the focus work. Reminders and the Health demo seeder plan each night on its own (weekday or weekend) schedule. The morning-leaf reminder is removed: Maple sends no morning notification (rewards.md, focus spec §8), so wind-down is the only reminder until F1's session-end notification. Onboarding shows the reminders primer after Apple Health; the focus-first opening steps (what pulls you in, hours saved) arrive with F1, when blocking exists.
```

- [ ] **Step 4: Full verification**

```bash
SIMULATOR="iPhone 17" Scripts/test.sh 2>&1 | grep -E 'Test run with|TEST (SUCCEEDED|FAILED)'
SIMULATOR="iPhone 17" Scripts/build.sh 2>&1 | grep -E 'warning:|error:' | grep -v appintentsmetadataprocessor | sort -u
xcodebuild -project Maple.xcodeproj -scheme Maple -configuration Release -destination 'generic/platform=iOS Simulator' -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/Maple-$(pwd -P | shasum | cut -c1-8)" build 2>&1 | grep -E 'warning:|error:|BUILD (SUCCEEDED|FAILED)' | grep -v appintentsmetadataprocessor | sort -u
grep -rn 'TODO(integrator)' App MapleKit docs
```

Expected:
- three `✔ Test run with … passed` lines and `** TEST SUCCEEDED **`;
- no warnings or errors from either build, and `** BUILD SUCCEEDED **` for Release;
- no `TODO(integrator)` left.

- [ ] **Step 5: First run end to end in the simulator**

```bash
xcrun simctl uninstall "iPhone 17" com.maanvikgupta.maple
xcrun simctl install "iPhone 17" "$APP"
xcrun simctl launch "iPhone 17" com.maanvikgupta.maple -MapleDemoFirstRunAutoplay 2
```

(`$APP` is from Task 5, step 5. Set it again the same way if this is a new shell.)

Take a screenshot every few seconds until Home appears (`xcrun simctl io "iPhone 17" screenshot /tmp/firstrun-N.png`). Expected order:
1. the four questions;
2. the proposed schedule;
3. the Apple Health primer;
4. the reminders primer;
5. the sprout;
6. the Sugar maple's reveal;
7. Home.

Nothing should be stuck and no screen should be blank.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Docs for the merged M1 branches" -m "Reminders section, debug launch arguments and a decision entry for the single wind-down reminder." -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Then report to the owner. Don't push.
