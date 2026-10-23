import Foundation
import Testing
@testable import MapleCore

@Suite("Dial layout")
struct DialLayoutTests {
    @Test("One mark a minute to an hour, then one per 2 and per 3 minutes; never more than 60")
    func marks() {
        #expect(DialLayout(plannedMinutes: 50).markCount == 50)
        #expect(DialLayout(plannedMinutes: 60).minutesPerMark == 1)
        #expect(DialLayout(plannedMinutes: 90).minutesPerMark == 2)
        #expect(DialLayout(plannedMinutes: 90).markCount == 45)
        #expect(DialLayout(plannedMinutes: 65).markCount == 33)
        #expect(DialLayout(plannedMinutes: 180).markCount == 60)
        #expect([20, 120, 125].map { DialLayout(plannedMinutes: $0).markCount } == [20, 60, 42])
        #expect((20...180).allSatisfy { DialLayout(plannedMinutes: $0).markCount <= 60 })
    }

    @Test("Marks go clockwise from 12 o'clock; every 5th is long")
    func placement() {
        let dial = DialLayout(plannedMinutes: 50)
        #expect(dial.angle(ofMark: 0) == 0)
        #expect(abs(dial.angle(ofMark: 25) - .pi) < 1e-9)
        #expect(dial.isLong(0) && dial.isLong(5) && !dial.isLong(6))
        #expect(dial.mark(atElapsed: 0) == 0)
        #expect(dial.mark(atElapsed: 59.9) == 0)
        #expect(dial.mark(atElapsed: 60) == 1)
        #expect(dial.mark(atElapsed: 50 * 60) == 49)
        #expect(DialLayout(plannedMinutes: 90).mark(atElapsed: 3 * 60) == 1)
        #expect(abs(dial.angle(atMinute: 35) - 2 * .pi * 35 / 50) < 1e-9)
    }

    @Test("The leaf dot sits on the marks when the length isn't a multiple of minutes per mark")
    func dotOnMarks() {
        let sixtyFive = DialLayout(plannedMinutes: 65)
        #expect(abs(sixtyFive.angle(atMinute: 64) - sixtyFive.angle(ofMark: 32)) < 1e-9)
        let oneTwentyFive = DialLayout(plannedMinutes: 125)
        #expect(abs(oneTwentyFive.angle(atMinute: 123) - oneTwentyFive.angle(ofMark: 41)) < 1e-9)
    }

    @Test("A 30° turn is 5 minutes, between 20 minutes and 3 hours")
    func turning() {
        #expect(DialLayout.length(turning: 30, from: 50) == 55)
        #expect(DialLayout.length(turning: 359, from: 50) == 105)
        #expect(DialLayout.length(turning: -29, from: 50) == 50)
        #expect(DialLayout.length(turning: -360, from: 50) == 20)
        #expect(DialLayout.length(turning: 3600, from: 50) == 180)
        #expect(DialLayout.stepped(50, by: -1) == 45)
        #expect(DialLayout.stepped(20, by: -1) == 20)
    }
}

@Suite("Focus time text")
struct FocusTimeTextTests {
    @Test("Whole minutes rounded up; seconds only in the last minute; 60 seconds reads 1m")
    func remaining() {
        #expect(FocusTimeText.remaining(32 * 60) == "32m")
        #expect(FocusTimeText.remaining(31 * 60 + 1) == "32m")
        #expect(FocusTimeText.remaining(90 * 60) == "1h 30m")
        #expect(FocusTimeText.remaining(60) == "1m")
        #expect(FocusTimeText.remaining(59.5) == "1m")
        #expect(FocusTimeText.remaining(59) == "0:59")
        #expect(FocusTimeText.remaining(4.2) == "0:05")
        #expect(FocusTimeText.remaining(0) == "0:00")
        #expect(FocusTimeText.remaining(-3) == "0:00")
    }

    @Test("Lengths and spoken forms")
    func lengths() {
        #expect(FocusTimeText.length(minutes: 50) == "50m")
        #expect(FocusTimeText.length(minutes: 60) == "1h")
        #expect(FocusTimeText.length(minutes: 90) == "1h 30m")
        #expect(FocusTimeText.spokenRemaining(32 * 60, locale: enGB) == "32 minutes left")
        #expect(FocusTimeText.spokenRemaining(45, locale: enGB) == "45 seconds left")
        #expect(FocusTimeText.spokenRemaining(1, locale: enGB) == "1 second left")
        #expect(FocusTimeText.spokenLength(minutes: 90, locale: enGB).contains("1 hour"))
    }
}

@Suite("Session forecast")
struct SessionForecastTests {
    private let window = AwakeWindow(start: at(2026, 10, 23, 6), end: at(2026, 10, 23, 23), windDown: at(2026, 10, 23, 22, 15))

    private func forecast(
        start: Date = at(2026, 10, 23, 14), minutes: Int = 50, now: Date? = nil, canCount: Bool = true, toLeaf: Int? = 35 * 60,
        room: Int = 21_600, firstEver: Bool = false
    ) -> SessionForecast {
        SessionForecast(start: start, plannedSeconds: minutes * 60, window: window, now: now ?? start, canCount: canCount,
                        secondsToLeaf: toLeaf, leafName: "Field maple", roomLeftToday: room, firstEver: firstEver)
    }

    private func line(_ forecast: SessionForecast) -> String? {
        forecast.countsLine.text(locale: enGB, calendar: utc)
    }

    @Test("A leaf in reach: the minute it opens")
    func reaches() {
        let result = forecast()
        #expect(result.leafMinute == 35)
        #expect(line(result) == "You'll reach Field maple at minute 35")
        #expect(forecast(start: at(2026, 10, 23, 14), now: at(2026, 10, 23, 14, 20), toLeaf: 15 * 60).leafMinute == 35)
    }

    @Test("Out of reach: no dot, and how far there is to go")
    func toward() {
        let far = forecast(toLeaf: 80 * 60)
        #expect(far.leafMinute == nil)
        #expect(line(far) == "Counts toward Field maple · 1h 20m to go")
        #expect(forecast(room: 20 * 60).leafMinute == nil)
    }

    @Test("Bedtime, the cap, a plain timer and the first session change the line")
    func states() {
        let crossing = forecast(start: at(2026, 10, 23, 22, 30), toLeaf: 10 * 60)
        #expect(crossing.leafMinute == 10)
        #expect(line(crossing) == "Counts until bed at 23:00")
        let late = forecast(start: at(2026, 10, 23, 23, 10))
        #expect(late.leafMinute == nil)
        #expect(line(late) == "After bedtime · this won't count")
        #expect(line(forecast(room: 0)) == "6h counted today · more won't add")
        #expect(line(forecast(canCount: false)) == nil)
        #expect(forecast(canCount: false).leafMinute == nil)
        #expect(line(forecast(firstEver: true)) == "Time your chosen apps stayed locked while you were awake.")
        #expect(forecast(start: at(2026, 10, 23, 5, 30), toLeaf: 10 * 60).leafMinute == 40)
    }

    @Test("Leaf lines")
    func leafLines() {
        #expect(SessionForecast.leafLine(leaf: "Field maple", secondsToGo: 17 * 60 - 20) == "Field maple · 17m to go")
        #expect(SessionForecast.openedLine(leaf: "Field maple", heldUntilMorning: false) == "Field maple is yours · it opens after this session")
        #expect(SessionForecast.openedLine(leaf: "Field maple", heldUntilMorning: true) == "Field maple is yours · it opens in the morning")
        #expect(SessionForecast.openedLine(count: 2) == "2 new leaves are yours")
    }
}

@Suite("Start readiness")
struct StartReadinessTests {
    private let reaches = SessionForecast.CountsLine.reaches(leaf: "Field maple", minute: 35)

    private func check(
        strictness: Strictness = .steady, allowed: Bool = true, selection: SelectionSummary? = FocusFixtures.blockSix,
        expired: Bool = false, first: Bool = false, phase: NowPhase = .day, line: SessionForecast.CountsLine? = nil
    ) -> StartReadiness {
        StartReadiness.check(strictness: strictness, blockingAllowed: allowed, selection: selection, expiredTokens: expired,
                             isFirstSession: first, phase: phase, countsLine: line ?? reaches)
    }

    @Test("Nothing to warn about: one tap, or a hold for Locked")
    func ready() {
        #expect(check() == .ready(needsHold: false))
        #expect(check(strictness: .locked) == .ready(needsHold: true))
    }

    @Test("Anything the start screen would warn about opens it instead")
    func warnings() {
        #expect(check(allowed: false) == .needsStartScreen(.blockingUnavailable))
        #expect(check(selection: nil) == .needsStartScreen(.noAppSet))
        #expect(check(selection: SelectionSummary(mode: .blockThese, apps: 0, sites: 0, categories: 0)) == .needsStartScreen(.noAppSet))
        #expect(check(selection: SelectionSummary(mode: .onlyThese, apps: 24, sites: 0, categories: 0)) == .needsStartScreen(.notQualifying))
        #expect(check(expired: true) == .needsStartScreen(.expiredTokens))
        #expect(check(first: true) == .needsStartScreen(.firstSession))
        #expect(check(phase: .windDown) == .needsStartScreen(.windDown))
        #expect(check(line: .afterBedtime) == .needsStartScreen(.afterBedtime))
        #expect(check(line: .capReached) == .needsStartScreen(.capReached))
        #expect(check(line: .untilBed(at(2026, 10, 23, 23))) == .needsStartScreen(.crossesBedtime))
    }
}

@Suite("Recent intentions")
struct RecentIntentionsTests {
    @Test("The last 3 distinct, carried-forward ones first, finished ones dropped")
    func chips() {
        let entries = [
            RecentIntentions.Entry(text: "Essay", reflection: .partly, at: at(2026, 10, 20, 9)),
            RecentIntentions.Entry(text: "Chemistry ch. 4", reflection: nil, at: at(2026, 10, 21, 9)),
            RecentIntentions.Entry(text: "Maths sheet", reflection: .allDone, at: at(2026, 10, 22, 9)),
            RecentIntentions.Entry(text: "chemistry ch. 4 ", reflection: nil, at: at(2026, 10, 22, 12)),
            RecentIntentions.Entry(text: "Spanish", reflection: .notYet, at: at(2026, 10, 23, 8)),
            RecentIntentions.Entry(text: "Reading", reflection: nil, at: at(2026, 10, 23, 9)),
        ]
        #expect(RecentIntentions.chips(entries) == ["Spanish", "Essay", "Reading"])
    }

    @Test("Intentions are trimmed and kept to 60 characters")
    func normalized() {
        #expect(RecentIntentions.normalized("  Essay  ") == "Essay")
        #expect(RecentIntentions.normalized("   ") == nil)
        #expect(RecentIntentions.normalized(String(repeating: "a", count: 80))?.count == 60)
    }
}

@Suite("Focus presets")
struct FocusPresetTests {
    @Test("Four presets to start: Study and Deep with a break")
    func defaults() {
        let presets = FocusPreset.defaults(appSetID: nil)
        #expect(presets.map(\.name) == ["Study", "Quick", "Deep", "Read"])
        #expect(presets.map(\.minutes) == [50, 25, 90, 30])
        #expect(presets.map(\.hasBreak) == [true, false, true, false])
        #expect(presets.map(\.verb) == [.study, .quick, .deep, .reading])
        #expect(presets.allSatisfy { $0.strictness == .steady })
    }

    @Test("Tighter strictness applies now; looser applies from the next day")
    func strictness() {
        let today = LocalDay(year: 2026, month: 10, day: 23)
        var preset = FocusPreset.defaults(appSetID: nil)[0]
        preset.changeStrictness(to: .locked, on: today, calendar: utc)
        #expect(preset.strictness(on: today) == .locked)
        preset.changeStrictness(to: .gentle, on: today, calendar: utc)
        #expect(preset.strictness(on: today) == .locked)
        #expect(preset.pendingStrictness == .gentle)
        let tomorrow = LocalDay(year: 2026, month: 10, day: 24)
        #expect(preset.strictness(on: tomorrow) == .gentle)
        preset.changeStrictness(to: .steady, on: tomorrow, calendar: utc)
        #expect(preset.strictness(on: tomorrow) == .steady)
        #expect(preset.pendingStrictness == nil)
    }

    @Test("Names are trimmed and kept to 24 characters; lengths stay in range")
    func limits() throws {
        #expect(FocusPreset.normalizedName("  Deep work  ") == "Deep work")
        #expect(FocusPreset.normalizedName("") == nil)
        #expect(FocusPreset.normalizedName(String(repeating: "x", count: 30))?.count == 24)
        var preset = FocusPreset.defaults(appSetID: nil)[0]
        preset.minutes = 500
        let data = try JSONEncoder().encode(preset)
        #expect(try JSONDecoder().decode(FocusPreset.self, from: data).minutes == 180)
    }
}
