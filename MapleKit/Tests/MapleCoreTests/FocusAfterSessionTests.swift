import Foundation
import Testing
@testable import MapleCore

@Suite("Credit words")
struct CreditWordsTests {
    @Test("Every rule has its words, and Couldn't confirm the block replaces Protection was off")
    func reasons() {
        #expect(CreditWords.reason(.override) == "Unlocked")
        #expect(CreditWords.reason(.unconfirmed) == "Couldn't confirm the block")
        #expect(CreditWords.reason(.afterBedtime) == "After bedtime")
        #expect(CreditWords.reason(.beforeMorning) == "After bedtime")
        #expect(CreditWords.reason(.dailyCap) == "Over today's 6h")
        #expect(CreditWords.reason(.overlap) == "Counted in another session")
        #expect(CreditWords.reason(.plainTimer) == "Plain timer")
        #expect(CreditWords.reason(.notQualifying) == "Selection didn't count")
        #expect(CreditRule.allCases.allSatisfy { !CreditWords.reason($0).lowercased().contains("protection") })
    }

    @Test("Saved today's greyed lines: an unlock says how long, other reasons stand alone")
    func lines() {
        #expect(CreditWords.line(.override, seconds: 300) == "Unlocked 5 min")
        #expect(CreditWords.line(.override, seconds: 20) == "Unlocked 1 min")
        #expect(CreditWords.line(.afterBedtime, seconds: 600) == "After bedtime")
        #expect(CreditWords.line(.dailyCap, seconds: 3000) == "Over today's 6h")
        #expect(CreditWords.line(.unconfirmed, seconds: 2400) == "Couldn't confirm the block")
    }

    @Test("Spoken, a greyed line says its length in words: never a bare min or h")
    func spokenLines() {
        #expect(CreditWords.spokenLine(.override, seconds: 300, locale: enGB) == "Unlocked 5 minutes")
        #expect(CreditWords.spokenLine(.override, seconds: 20, locale: enGB) == "Unlocked 1 minute")
        #expect(CreditWords.spokenLine(.dailyCap, seconds: 3000, locale: enGB)
            == "Over today's \(HomeFormat.spokenDuration(minutes: 360, locale: enGB))")
        #expect(CreditWords.spokenLine(.afterBedtime, seconds: 600, locale: enGB) == "After bedtime")
        #expect(CreditWords.spokenLine(.unconfirmed, seconds: 2400, locale: enGB) == "Couldn't confirm the block")
    }
}

@Suite("Receipt marks")
struct ReceiptMarksTests {
    private let start = at(2026, 10, 23, 14)

    private func stretch(_ from: Double, _ to: Double, _ rule: CreditRule? = nil) -> CreditStretch {
        CreditStretch(DateInterval(start: start.addingTimeInterval(from * 60), end: start.addingTimeInterval(to * 60)), rule)
    }

    @Test("A break counts, so its minutes light like any others")
    func breakCounts() throws {
        let script = SessionScript(start: start, plan: FocusFixtures.plan(breakMinutes: 5))
        script.write(.shieldApplied)
        script.after(30 * 60, .breakStarted(seconds: 300))
        script.after(5 * 60, .breakEnded)
        script.after(15 * 60, .sessionEnded(.completed, verified: true))
        let session = try #require(script.record)
        let credit = try #require(HoursCredit.credit([session], crediting: [.live], now: script.time.now).first)
        let marks = ReceiptMarks.marks(layout: DialLayout(plannedMinutes: 50), countdownStart: session.countdownStart,
                                       stretches: credit.stretches)
        #expect(marks == Array(repeating: .lit, count: 50))
    }

    @Test("An unlock leaves gaps, and a mark the unlock only touched is a gap too")
    func override() {
        let marks = ReceiptMarks.marks(layout: DialLayout(plannedMinutes: 50), countdownStart: start,
                                       stretches: [stretch(0, 20.5), stretch(20.5, 25.5, .override), stretch(25.5, 50)])
        #expect(marks == Array(repeating: .lit, count: 20) + Array(repeating: .gap, count: 6) + Array(repeating: .lit, count: 24))
    }

    @Test("Time after the last confirmed block is a gap")
    func unconfirmedTail() {
        let marks = ReceiptMarks.marks(layout: DialLayout(plannedMinutes: 50), countdownStart: start,
                                       stretches: [stretch(0, 38), stretch(38, 50, .unconfirmed)])
        #expect(marks == Array(repeating: .lit, count: 38) + Array(repeating: .gap, count: 12))
    }

    @Test("65 minutes: 33 marks of 2 minutes, and the last mark covers only the final minute")
    func sixtyFive() {
        let layout = DialLayout(plannedMinutes: 65)
        #expect(layout.markCount == 33)
        #expect(layout.minutesPerMark == 2)
        // The whole plan counted: the short last mark is lit, though a 2-minute span would run past the end.
        #expect(ReceiptMarks.marks(layout: layout, countdownStart: start, stretches: [stretch(0, 65)]) == Array(repeating: .lit, count: 33))
        let tail = ReceiptMarks.marks(layout: layout, countdownStart: start, stretches: [stretch(0, 64.5), stretch(64.5, 65, .unconfirmed)])
        #expect(tail == Array(repeating: .lit, count: 32) + [.gap])
        let capped = ReceiptMarks.marks(layout: layout, countdownStart: start, stretches: [stretch(0, 61), stretch(61, 65, .dailyCap)])
        #expect(capped == Array(repeating: .lit, count: 30) + [.gap, .gap, .gap])
    }

    @Test("Nothing counted lights nothing; overlapping stretches can't light a mark they only partly cover")
    func edges() {
        #expect(ReceiptMarks.marks(layout: DialLayout(plannedMinutes: 20), countdownStart: start, stretches: [])
            == Array(repeating: .gap, count: 20))
        let overlapping = ReceiptMarks.marks(layout: DialLayout(plannedMinutes: 20), countdownStart: start,
                                             stretches: [stretch(0, 40.0 / 60), stretch(10.0 / 60, 50.0 / 60)])
        #expect(overlapping.first == .gap)
    }
}

@Suite("Receipt")
struct ReceiptModelTests {
    typealias Ended = (session: SessionRecord, credit: SessionCredit)

    /// Field maple, the 3h rung, with 1h 10m to go.
    static let fieldMaple = progressRow("campestre", .hoursSaved, threshold: 3, current: Double(3 * 3600 - 70 * 60) / 3600, estimate: nil)

    private func replay(_ script: SessionScript) throws -> Ended {
        let session = try #require(script.record)
        let credit = try #require(HoursCredit.credit([session], crediting: [.live], now: script.time.now).first)
        return (session: session, credit: credit)
    }

    /// A 50-minute session from `start`, its block confirmed at once unless `applied` is false, then `body`.
    private func session(
        at start: Date = at(2026, 10, 23, 14), plan: FocusPlan = FocusFixtures.plan(), applied: Bool = true,
        _ body: (SessionScript) -> Void
    ) throws -> Ended {
        let script = SessionScript(start: start, plan: plan)
        if applied { script.write(.shieldApplied) }
        body(script)
        return try replay(script)
    }

    /// 14:00–14:50, a 5-minute break at minute 30, every read-back confirmed.
    private func clean() throws -> Ended {
        try session(plan: FocusFixtures.plan(breakMinutes: 5)) {
            $0.after(30 * 60, .breakStarted(seconds: 300))
            $0.after(5 * 60, .breakEnded)
            $0.after(15 * 60, .sessionEnded(.completed, verified: true))
        }
    }

    /// - Parameter shownOn: The Maple day the receipt is shown on; nil is the session's own.
    private func receipt(
        _ ended: Ended, unlocks: [LeafUnlock] = [], held: Bool = false, next: LeafProgress? = ReceiptModelTests.fieldMaple,
        today: Int = 130 * 60, shownOn: LocalDay? = nil, reflection: Reflection? = nil, now: Date? = nil
    ) -> ReceiptModel {
        ReceiptModel(
            session: ended.session, credit: ended.credit, unlocks: unlocks, heldUntilMorning: held, next: next, todaySeconds: today,
            today: shownOn ?? ended.session.plan.day, reflection: reflection,
            now: now ?? ended.session.endedAt ?? ended.session.plannedEnd, locale: enGB, calendar: utc
        )
    }

    private func leaf(_ id: String) -> LeafUnlock {
        LeafUnlock(speciesID: id, date: at(2026, 10, 23, 14, 50), season: .autumn, colourway: .autumn)
    }

    @Test("On time: counted minutes, today's total, the next leaf, the breakdown, the reflection and the buttons")
    func onTime() throws {
        let model = receipt(try clean())
        #expect(model.ending == .onTime)
        #expect(model.playsFinish)
        #expect(model.isGold)
        #expect(model.countedSeconds == 3000)
        #expect(model.subtitle == "Apps open again")
        #expect(model.numeral == "50m")
        #expect(model.numeralParts == [.value("50"), .unit("m")])
        #expect(model.caption == "saved · 2h 10m today")
        #expect(model.note == nil)
        #expect(model.leafLine == "Field maple · 1h 10m to go")
        #expect(!model.leafOpened)
        #expect(model.breakdown == "Locked the whole time · 1 break")
        #expect(model.endedLine == nil)
        #expect(model.layout == DialLayout(plannedMinutes: 50))
        #expect(model.marks == Array(repeating: .lit, count: 50))
        #expect(model.dialLabel == "50 minutes saved. \(HomeFormat.spokenDuration(minutes: 130, locale: enGB)) today.")
        #expect(model.dialLabel.hasPrefix("50 minutes saved. 2 hours"))
        #expect(model.reflectionPrompt == "How did it go?")
        #expect(model.choices.map(\.title) == ["All done", "Partly", "Not yet"])
        #expect(model.choices.allSatisfy { !$0.isSelected })
        #expect(model.again == "Again · 50m")
        #expect(FocusCopy.done == "Done")
    }

    @Test("Shown on a later Maple day, the caption says that day, with that day's total: as shown, read aloud and at large sizes")
    func thatDay() throws {
        let done = try clean()
        let nextDay = LocalDay(year: 2026, month: 10, day: 24)
        let model = receipt(done, shownOn: nextDay, now: at(2026, 10, 24, 8, 30))
        #expect(model.caption == "saved · 2h 10m that day")
        #expect(model.timeLine == "50m saved · 2h 10m that day")
        #expect(model.dialLabel == "50 minutes saved. \(HomeFormat.spokenDuration(minutes: 130, locale: enGB)) that day.")
        #expect(model.dialLabel.hasPrefix("50 minutes saved. 2 hours"))
        #expect(!model.dialLabel.contains("today"))
        // Under a minute saved that day.
        let none = receipt(done, today: 30, shownOn: nextDay)
        #expect(none.caption == "saved · none that day")
        #expect(none.timeLine == "50m saved · none that day")
        #expect(none.dialLabel == "50 minutes saved. None that day.")
        // Today's receipts keep "today".
        #expect(receipt(done).caption == "saved · 2h 10m today")
        #expect(receipt(done, shownOn: LocalDay(year: 2026, month: 10, day: 23)).timeLine == "50m saved · 2h 10m today")
        #expect(receipt(done, today: 30).caption == "saved · none yet today")
    }

    @Test("Without a break the breakdown is Locked the whole time; a chosen reflection is marked")
    func noBreak() throws {
        let ended = try session { $0.after(50 * 60, .sessionEnded(.completed, verified: true)) }
        let model = receipt(ended, reflection: .partly)
        #expect(model.breakdown == "Locked the whole time")
        #expect(model.choices.map(\.reflection) == [.allDone, .partly, .notYet])
        #expect(model.choices.map(\.isSelected) == [false, true, false])
    }

    @Test("Leaf lines: one leaf now or in the morning, several, and a leaf that isn't the dial's")
    func leafLines() throws {
        let done = try clean()
        let one = receipt(done, unlocks: [leaf("campestre")])
        #expect(one.leafLine == "Field maple is yours · it opens after this session")
        #expect(one.leafOpened)
        #expect(receipt(done, unlocks: [leaf("campestre")], held: true).leafLine == "Field maple is yours · it opens in the morning")
        let two = receipt(done, unlocks: [leaf("campestre"), leaf("buergerianum")])
        #expect(two.leafLine == "2 new leaves are yours")
        #expect(two.leafOpened)
        let sessionLeaf = receipt(done, unlocks: [leaf("buergerianum")])
        #expect(sessionLeaf.leafLine == "Trident maple is yours · it opens after this session")
        #expect(!sessionLeaf.leafOpened)
        #expect(receipt(done, next: nil).leafLine == nil)
    }

    @Test("The leaf line's two tones: the name, then the rest; a line that says a leaf is yours is one run, with the bud")
    func leafLineParts() throws {
        let done = try clean()
        let model = receipt(done)
        #expect(model.leafLineParts == RunningSessionModel.Line(lead: "Field maple", trail: "· 1h 10m to go"))
        #expect(model.leafLineParts?.text == model.leafLine)
        #expect(!model.leafLineOpened)
        let one = receipt(done, unlocks: [leaf("campestre")])
        #expect(one.leafLineParts == RunningSessionModel.Line(lead: "Field maple is yours · it opens after this session"))
        #expect(one.leafLineOpened)
        let two = receipt(done, unlocks: [leaf("campestre"), leaf("buergerianum")])
        #expect(two.leafLineParts == RunningSessionModel.Line(lead: "2 new leaves are yours"))
        #expect(two.leafLineOpened)
        // A leaf that isn't the dial's (not an hours leaf) is still yours: the bud, but no grown centre.
        let other = receipt(done, unlocks: [leaf("buergerianum")])
        #expect(other.leafLineOpened)
        #expect(!other.leafOpened)
        #expect(receipt(done, next: nil).leafLineParts == nil)
        #expect(!receipt(done, next: nil).leafLineOpened)
    }

    @Test("Spoken forms: the leaf line, Ended at, the breakdown and Again say their times in words, never a bare m or h")
    func spoken() throws {
        let model = receipt(try clean())
        #expect(model.leafSpoken == "Field maple, \(HomeFormat.spokenDuration(minutes: 70, locale: enGB)) to go")
        #expect(model.leafSpoken?.hasPrefix("Field maple, 1 hour") == true)
        #expect(model.breakdownSpoken == "Locked the whole time, 1 break")
        #expect(model.againSpoken == "Again, 50 minutes")
        #expect(model.noteSpoken == nil)

        let early = receipt(try session { $0.after(18 * 60 + 20, .sessionEnded(.endedEarly, verified: true)) })
        #expect(early.noteSpoken == "Ended at 18 of 50 minutes")
        #expect(early.breakdownSpoken == "Locked the whole time")

        let unlocked = receipt(try session {
            $0.after(20 * 60, .overrideStarted(seconds: 300))
            $0.after(5 * 60, .overrideEnded)
            $0.after(25 * 60, .sessionEnded(.completed, verified: true))
        })
        #expect(unlocked.breakdownSpoken == "45 minutes locked, 5 minutes unlocked, not counted")

        let crossing = receipt(try session(at: at(2026, 10, 23, 22, 30)) { $0.after(50 * 60, .sessionEnded(.completed, verified: true)) })
        #expect(crossing.breakdownSpoken == "30 minutes counted, 20 minutes after bedtime")

        // A line that says a leaf is yours has no time in it, and reads as it is (as on the running screen).
        let one = receipt(try clean(), unlocks: [leaf("campestre")])
        #expect(one.leafSpoken == "Field maple is yours · it opens after this session")

        let released = try session(plan: FocusFixtures.plan(strictness: .locked)) {
            $0.after(18 * 60, .sessionEnded(.emergencyRelease, verified: true))
        }
        let emergency = receipt(released)
        #expect(emergency.againSpoken == nil && emergency.breakdownSpoken == nil && emergency.leafSpoken == nil)

        let long = try session(plan: FocusFixtures.plan(minutes: 90)) { $0.after(65 * 60, .sessionEnded(.endedEarly, verified: true)) }
        #expect(receipt(long).noteSpoken == "Ended at \(HomeFormat.spokenDuration(minutes: 65, locale: enGB)) of \(HomeFormat.spokenDuration(minutes: 90, locale: enGB))")
        #expect(receipt(long).againSpoken == "Again, \(HomeFormat.spokenDuration(minutes: 90, locale: enGB))")

        for model in [model, early, unlocked, crossing, one, receipt(long)] {
            for line in [model.leafSpoken, model.noteSpoken, model.breakdownSpoken, model.againSpoken].compactMap({ $0 }) {
                #expect(line.range(of: #"\d\s?[mh]\b"#, options: .regularExpression) == nil, "\(line)")
            }
        }
    }

    @Test("Ended while away: the finish plays only within 10 minutes of the end")
    func endedAway() throws {
        let late = try session { $0.after(2 * 3600 + 50 * 60, .sessionEnded(.completed, verified: true)) }
        let model = receipt(late, now: at(2026, 10, 23, 16, 50))
        #expect(model.ending == .endedAway(playsFinish: false))
        #expect(!model.playsFinish)
        #expect(model.isGold)
        #expect(model.numeral == "50m")
        let soon = try session { $0.after(55 * 60, .sessionEnded(.completed, verified: true)) }
        let fresh = receipt(soon, now: at(2026, 10, 23, 14, 55))
        #expect(fresh.ending == .endedAway(playsFinish: true))
        #expect(fresh.playsFinish)
        // On time, but seen 40 minutes later: the final frame shows still.
        let done = try clean()
        #expect(receipt(done, now: at(2026, 10, 23, 15, 30)).ending == .onTime)
        #expect(!receipt(done, now: at(2026, 10, 23, 15, 30)).playsFinish)
    }

    @Test("Ended early: no gold, and Ended at 18 of 50m over the counted time")
    func endedEarly() throws {
        let early = try session { $0.after(18 * 60 + 20, .sessionEnded(.endedEarly, verified: true)) }
        let model = receipt(early)
        #expect(model.ending == .endedEarly)
        #expect(!model.isGold)
        #expect(model.playsFinish)
        #expect(model.note == "Ended at 18 of 50m")
        #expect(model.numeral == "18m")
        #expect(model.caption == "saved · 2h 10m today")
        #expect(model.breakdown == "Locked the whole time")
        #expect(model.marks == Array(repeating: .lit, count: 18) + Array(repeating: .gap, count: 32))
        let released = try session { $0.after(18 * 60, .sessionEnded(.releaseAll, verified: true)) }
        #expect(receipt(released).ending == .endedEarly)
    }

    @Test("Emergency release: §5.7's ended state, with Done only")
    func emergency() throws {
        let released = try session(plan: FocusFixtures.plan(strictness: .locked)) {
            $0.after(18 * 60, .sessionEnded(.emergencyRelease, verified: true))
        }
        let model = receipt(released)
        #expect(model.ending == .emergency)
        #expect(!model.playsFinish)
        #expect(!model.isGold)
        #expect(model.numeral == "18m")
        #expect(model.caption == "saved · they stay yours")
        #expect(model.endedLine == "Session ended. It won't count as finished.")
        #expect(model.breakdown == nil)
        #expect(model.leafLine == nil)
        #expect(model.again == nil)
        #expect(model.reflectionPrompt == nil)
        #expect(model.choices.isEmpty)
        #expect(receipt(released, unlocks: [leaf("campestre")]).leafLine == "Field maple is yours · it opens after this session")
    }

    @Test("After bedtime: a white finish, 0m, and why")
    func afterBedtime() throws {
        let late = try session(at: at(2026, 10, 23, 23, 10), plan: FocusFixtures.plan(day: "2026-10-24", window: FocusFixtures.window(24))) {
            $0.after(50 * 60, .sessionEnded(.completed, verified: true))
        }
        let model = receipt(late, today: 0)
        #expect(model.ending == .countedNothing)
        #expect(model.playsFinish)
        #expect(!model.isGold)
        #expect(model.numeral == "0m")
        #expect(model.caption == "saved · none yet today")
        #expect(model.breakdown == "After bedtime · this didn't count")
        #expect(model.marks == Array(repeating: .gap, count: 50))
        #expect(model.leafLine == "Field maple · 1h 10m to go")
        #expect(model.dialLabel == "\(HomeFormat.spokenDuration(minutes: 0, locale: enGB)) saved. None yet today.")
    }

    @Test("Crossing bedtime: what counted, and the minutes after bed")
    func crossingBedtime() throws {
        let crossing = try session(at: at(2026, 10, 23, 22, 30)) { $0.after(50 * 60, .sessionEnded(.completed, verified: true)) }
        let model = receipt(crossing)
        #expect(model.ending == .onTime)
        #expect(model.numeral == "30m")
        #expect(model.breakdown == "30m counted · 20m after bedtime")
        #expect(model.marks == Array(repeating: .lit, count: 30) + Array(repeating: .gap, count: 20))
    }

    @Test("Unlocked minutes are gaps: 45m locked · 5m unlocked, not counted")
    func unlocked() throws {
        let unlocked = try session {
            $0.after(20 * 60, .overrideStarted(seconds: 300))
            $0.after(5 * 60, .overrideEnded)
            $0.after(25 * 60, .sessionEnded(.completed, verified: true))
        }
        let model = receipt(unlocked)
        #expect(model.numeral == "45m")
        #expect(model.breakdown == "45m locked · 5m unlocked, not counted")
        #expect(model.isGold)
        #expect(model.marks == Array(repeating: .lit, count: 20) + Array(repeating: .gap, count: 5) + Array(repeating: .lit, count: 25))
    }

    @Test("Plain timer: lit marks and 50m focused · not counted toward leaves")
    func plainTimer() throws {
        let plain = try session(plan: FocusFixtures.plan(kind: .plainTimer, selection: nil), applied: false) {
            $0.after(50 * 60, .sessionEnded(.completed, verified: false))
        }
        let model = receipt(plain)
        #expect(model.ending == .countedNothing)
        #expect(!model.isGold)
        #expect(model.subtitle == "Plain timer")
        #expect(model.numeral == "50m")
        #expect(model.caption == "focused · not counted toward leaves")
        #expect(model.breakdown == nil)
        #expect(model.leafLine == nil)
        #expect(model.marks == Array(repeating: .lit, count: 50))
        #expect(model.dialLabel == "50 minutes focused. Not counted toward leaves.")
        #expect(model.again == "Again · 50m")
    }

    @Test("Lost confirmation: Couldn't confirm the block after 14:10, in the locale's clock")
    func lostConfirmation() throws {
        let revoked = try session {
            $0.after(10 * 60, .shieldVerified)
            $0.after(30, .shieldLost)
            $0.after(39 * 60 + 30, .sessionEnded(.completed, verified: false))
        }
        let model = receipt(revoked)
        #expect(model.breakdown == "Couldn't confirm the block after 14:10")
        #expect(model.breakdownSpoken == "Couldn't confirm the block after 14:10")
        #expect(model.numeral == "10m")
        #expect(model.isGold)
        #expect(model.marks == Array(repeating: .lit, count: 10) + Array(repeating: .gap, count: 40))
        let twelveHour = ReceiptModel(
            session: revoked.session, credit: revoked.credit, unlocks: [], heldUntilMorning: false, next: nil, todaySeconds: 600,
            today: revoked.session.plan.day, reflection: nil, now: at(2026, 10, 23, 14, 50), locale: enUS, calendar: utc
        )
        #expect(twelveHour.breakdown == "Couldn't confirm the block after 2:10 PM")
    }

    @Test("Over the cap: Over today's 6h · this didn't add, or the part that did")
    func overCap() throws {
        let day = FocusDay(at(2026, 10, 23, 8))
        day.session(minutes: 180)
        day.at(at(2026, 10, 23, 11, 30))
        day.session(minutes: 180)
        day.at(at(2026, 10, 23, 15))
        let third = day.session(minutes: 50)
        let thirdSession = try #require(day.ledger.sessions().first { $0.id == third })
        let thirdCredit = try #require(day.credits().first { $0.id == third })
        let model = receipt((session: thirdSession, credit: thirdCredit), today: HoursCredit.dailyCap)
        #expect(model.ending == .countedNothing)
        #expect(!model.isGold)
        #expect(model.numeral == "0m")
        #expect(model.caption == "saved · 6h today")
        #expect(model.breakdown == "Over today's 6h · this didn't add")
        #expect(model.breakdownSpoken == "Over today's \(HomeFormat.spokenDuration(minutes: 360, locale: enGB)), this didn't add")

        let partial = FocusDay(at(2026, 10, 23, 8))
        partial.session(minutes: 180)
        partial.at(at(2026, 10, 23, 11, 30))
        partial.session(minutes: 170)
        partial.at(at(2026, 10, 23, 15))
        let last = partial.session(minutes: 50)
        let lastSession = try #require(partial.ledger.sessions().first { $0.id == last })
        let lastCredit = try #require(partial.credits().first { $0.id == last })
        let capped = receipt((session: lastSession, credit: lastCredit), today: HoursCredit.dailyCap)
        #expect(capped.numeral == "10m")
        #expect(capped.breakdown == "10m counted · 40m over today's 6h")
        #expect(capped.breakdownSpoken
            == "10 minutes counted, 40 minutes over today's \(HomeFormat.spokenDuration(minutes: 360, locale: enGB))")
        #expect(capped.isGold)
        #expect(capped.marks == Array(repeating: .lit, count: 10) + Array(repeating: .gap, count: 40))
    }

    @Test("Gold only over counted marks: a session that counted under one mark finishes in white")
    func goldNeedsALitMark() throws {
        // Two sessions use all but 30 seconds of the day's 6h, so the third counts 30 seconds and then hits the cap.
        let day = FocusDay(at(2026, 10, 23, 8))
        day.session(minutes: 180)
        day.at(at(2026, 10, 23, 11, 30))
        day.session(minutes: 180, overrides: [(minute: 10, seconds: 30)])
        day.at(at(2026, 10, 23, 15))
        let third = day.session(minutes: 50)
        let thirdSession = try #require(day.ledger.sessions().first { $0.id == third })
        let thirdCredit = try #require(day.credits().first { $0.id == third })
        #expect(thirdCredit.seconds == 30)
        let model = receipt((session: thirdSession, credit: thirdCredit), today: HoursCredit.dailyCap)
        #expect(model.ending == .onTime)
        #expect(model.countedSeconds == 30)
        #expect(model.numeral == "0m")
        #expect(model.marks == Array(repeating: .gap, count: 50))
        #expect(!model.isGold)
        // An ordinary on-time session still finishes in gold.
        #expect(receipt(try clean()).isGold)
    }

    @Test("A selection that doesn't qualify: Not counted · add an app to count")
    func notQualifying() throws {
        let allowList = SelectionSummary(mode: .onlyThese, apps: 24, sites: 0, categories: 0)
        let ended = try session(plan: FocusFixtures.plan(selection: allowList)) {
            $0.after(50 * 60, .sessionEnded(.completed, verified: true))
        }
        let model = receipt(ended)
        #expect(model.ending == .notQualifying)
        #expect(!model.isGold)
        #expect(model.numeral == "50m")
        #expect(model.caption == "Not counted · add an app to count")
        #expect(model.breakdown == nil)
        #expect(model.leafLine == nil)
        #expect(model.marks == Array(repeating: .gap, count: 50))
        #expect(model.subtitle == "Apps open again")
    }

    @Test("At accessibility sizes the time repeats under the dial: the numeral and its caption, as the dial shows them (§5.17)")
    func timeLine() throws {
        #expect(receipt(try clean()).timeLine == "50m saved · 2h 10m today")
        #expect(receipt(try clean(), today: 0).timeLine == "50m saved · none yet today")
        let plain = try session(plan: FocusFixtures.plan(kind: .plainTimer, selection: nil), applied: false) {
            $0.after(50 * 60, .sessionEnded(.completed, verified: false))
        }
        #expect(receipt(plain).timeLine == "50m focused · not counted toward leaves")
        // A caption that starts its own sentence follows a dot.
        let allowList = SelectionSummary(mode: .onlyThese, apps: 24, sites: 0, categories: 0)
        let notCounted = try session(plan: FocusFixtures.plan(selection: allowList)) {
            $0.after(50 * 60, .sessionEnded(.completed, verified: true))
        }
        #expect(receipt(notCounted).timeLine == "50m · Not counted · add an app to count")
    }

    @Test("No receipt line shouts, fails, quits or talks about a streak")
    func voice() throws {
        let early = try session { $0.after(18 * 60, .sessionEnded(.endedEarly, verified: true)) }
        let revoked = try session {
            $0.after(10 * 60, .shieldVerified)
            $0.after(30, .shieldLost)
            $0.after(39 * 60 + 30, .sessionEnded(.completed, verified: false))
        }
        let models = [receipt(try clean()), receipt(early), receipt(revoked), receipt(try clean(), unlocks: [leaf("campestre")])]
        for model in models {
            let lines = [model.subtitle, model.numeral, model.caption, model.leafLine, model.breakdown, model.note, model.endedLine,
                         model.dialLabel, model.again].compactMap { $0 }
            for line in lines {
                let lower = line.lowercased()
                #expect(!line.contains("!"), "\(line)")
                #expect(!["fail", "quit", "streak", "lost"].contains { lower.contains($0) }, "\(line)")
            }
        }
    }
}

/// When a receipt says "that day" (F1-31): only once the session's Maple day is earlier than the day the member is
/// still living in, which moves on when the next window opens (wake − 60), never at bedtime. On the standard schedule
/// bedtime is 23:00 and wake 07:00, so a window opens at 06:00.
@Suite("A receipt's day")
struct ReceiptDayTests {
    private let context = CollectionContext(schedule: .standard, permissions: [.appleHealth], calendar: utc, hemisphere: .northern)
    private let snapshot = CollectionSnapshot.empty(profileID: UUID(), createdAt: at(2026, 10, 1))

    /// A session on `plan`'s frozen day and window, as `FocusSessionStore.start` freezes them at `start`, that ran `minutes`.
    private func ended(from start: Date, minutes: Int) throws -> (session: SessionRecord, credit: SessionCredit) {
        let frozen = snapshot.focusWindow(at: start, context: context)
        let plan = FocusFixtures.plan(minutes: minutes, day: frozen.day.description, window: frozen.window)
        let script = SessionScript(start: start, plan: plan)
        script.write(.shieldApplied)
        script.after(TimeInterval(minutes * 60), .sessionEnded(.completed, verified: true))
        let session = try #require(script.record)
        let credit = try #require(HoursCredit.credit([session], crediting: [.live], now: script.time.now).first)
        return (session: session, credit: credit)
    }

    /// The receipt as `ReceiptView` builds it: `today` is the day the member is living in at `shown`.
    private func receipt(_ ended: (session: SessionRecord, credit: SessionCredit), shown: Date, todaySeconds: Int? = nil) -> ReceiptModel {
        ReceiptModel(
            session: ended.session, credit: ended.credit, unlocks: [], heldUntilMorning: false, next: nil,
            todaySeconds: todaySeconds ?? ended.credit.seconds, today: snapshot.livingDay(at: shown, context: context),
            reflection: nil, now: shown, locale: enGB, calendar: utc
        )
    }

    /// 22:20 to 23:10 on the 23rd: its last 10 minutes are past bedtime, so it counts 40.
    private func eveningSession() throws -> (session: SessionRecord, credit: SessionCredit) {
        try ended(from: at(2026, 10, 23, 22, 20), minutes: 50)
    }

    @Test("Its finish, past bedtime on its own evening, says today, as read aloud and at large sizes")
    func justAfterBedtime() throws {
        let evening = try eveningSession()
        #expect(evening.session.plan.day == LocalDay(year: 2026, month: 10, day: 23))
        let model = receipt(evening, shown: at(2026, 10, 23, 23, 10))
        #expect(model.playsFinish)
        #expect(model.numeral == "40m")
        #expect(model.caption == "saved · 40m today")
        #expect(model.timeLine == "40m saved · 40m today")
        #expect(model.dialLabel == "40 minutes saved. 40 minutes today.")
    }

    @Test("Opened in the small hours, before the next window opens, it still says today")
    func smallHours() throws {
        let model = receipt(try eveningSession(), shown: at(2026, 10, 24, 0, 30))
        #expect(model.caption == "saved · 40m today")
        #expect(model.timeLine == "40m saved · 40m today")
        #expect(model.dialLabel == "40 minutes saved. 40 minutes today.")
    }

    @Test("One second before the next window opens it says today; at that moment it says that day")
    func theWindowOpening() throws {
        let evening = try eveningSession()
        let opens = snapshot.focusWindow(at: at(2026, 10, 24, 12), context: context).window.start
        #expect(opens == at(2026, 10, 24, 6))
        #expect(receipt(evening, shown: opens.addingTimeInterval(-1)).caption == "saved · 40m today")
        let atOpening = receipt(evening, shown: opens)
        #expect(atOpening.caption == "saved · 40m that day")
        #expect(atOpening.timeLine == "40m saved · 40m that day")
        #expect(atOpening.dialLabel == "40 minutes saved. 40 minutes that day.")
    }

    @Test("Mid-morning the next day it says that day")
    func midMorning() throws {
        let model = receipt(try eveningSession(), shown: at(2026, 10, 24, 10, 30))
        #expect(model.caption == "saved · 40m that day")
        #expect(model.timeLine == "40m saved · 40m that day")
        #expect(model.dialLabel == "40 minutes saved. 40 minutes that day.")
    }

    @Test("A session started inside the sleep window belongs to the next day, so it says today that night and that morning")
    func startedAfterBedtime() throws {
        let late = try ended(from: at(2026, 10, 23, 23, 20), minutes: 25)
        #expect(late.session.plan.day == LocalDay(year: 2026, month: 10, day: 24))
        #expect(late.credit.seconds == 0)
        #expect(receipt(late, shown: at(2026, 10, 23, 23, 55)).caption == "saved · none yet today")
        #expect(receipt(late, shown: at(2026, 10, 24, 7)).caption == "saved · none yet today")
        #expect(receipt(late, shown: at(2026, 10, 24, 7), todaySeconds: 3600).caption == "saved · 1h today")
    }

    @Test("The none caption follows the same rule")
    func noneCaption() throws {
        let evening = try eveningSession()
        for shown in [at(2026, 10, 23, 23, 10), at(2026, 10, 24, 0, 30), at(2026, 10, 24, 5, 59, 59)] {
            let model = receipt(evening, shown: shown, todaySeconds: 30)
            #expect(model.caption == "saved · none yet today")
            #expect(model.timeLine == "40m saved · none yet today")
            #expect(model.dialLabel == "40 minutes saved. None yet today.")
        }
        for shown in [at(2026, 10, 24, 6), at(2026, 10, 24, 10, 30)] {
            let model = receipt(evening, shown: shown, todaySeconds: 30)
            #expect(model.caption == "saved · none that day")
            #expect(model.timeLine == "40m saved · none that day")
            #expect(model.dialLabel == "40 minutes saved. None that day.")
        }
    }

    @Test("The day being lived in moves on when the next window opens: an hour before wake, or later after a short night")
    func livingDay() {
        let friday = LocalDay(year: 2026, month: 10, day: 23), saturday = LocalDay(year: 2026, month: 10, day: 24)
        func day(_ date: Date, bedtime: ClockTime = SleepSchedule.standard.bedtime, wake: ClockTime = SleepSchedule.standard.wake) -> LocalDay {
            let schedule = SleepSchedule(bedtime: bedtime, wake: wake, windDownMinutes: 45)
            let context = CollectionContext(schedule: .everyNight(schedule), permissions: [], calendar: utc, hemisphere: .northern)
            return snapshot.livingDay(at: date, context: context)
        }
        // 23:00 to 07:00: the window opens at 06:00.
        #expect(day(at(2026, 10, 23, 6)) == friday)
        #expect(day(at(2026, 10, 23, 22, 59)) == friday)
        #expect(day(at(2026, 10, 23, 23)) == friday)
        #expect(day(at(2026, 10, 24, 5, 59, 59)) == friday)
        #expect(day(at(2026, 10, 24, 6)) == saturday)
        // Bed after midnight, 00:30 to 08:30: the same evening's window runs past midnight, and the next opens at 07:30.
        let lateBed = ClockTime(hour: 0, minute: 30), lateWake = ClockTime(hour: 8, minute: 30)
        #expect(day(at(2026, 10, 24, 0, 15), bedtime: lateBed, wake: lateWake) == friday)
        #expect(day(at(2026, 10, 24, 0, 45), bedtime: lateBed, wake: lateWake) == friday)
        #expect(day(at(2026, 10, 24, 7, 29, 59), bedtime: lateBed, wake: lateWake) == friday)
        #expect(day(at(2026, 10, 24, 7, 30), bedtime: lateBed, wake: lateWake) == saturday)
        // A night under 6 hours, 03:00 to 07:00: wake moves to 09:00, so the window opens at 08:00.
        let shortBed = ClockTime(hour: 3), shortWake = ClockTime(hour: 7)
        #expect(day(at(2026, 10, 24, 7, 30), bedtime: shortBed, wake: shortWake) == friday)
        #expect(day(at(2026, 10, 24, 8), bedtime: shortBed, wake: shortWake) == saturday)
    }
}

@Suite("Saved today")
struct SavedTodayModelTests {
    private let today = LocalDay(year: 2026, month: 10, day: 23)

    private func model(_ credits: [SessionCredit], _ sessions: [SessionRecord], now: Date, locale: Locale = enGB) -> SavedTodayModel {
        SavedTodayModel(credits: credits, sessions: sessions, day: today, now: now, calendar: utc, locale: locale)
    }

    /// Study 14:00–15:10 with a 5-minute unlock at minute 30, then Quick 16:00–16:25.
    private func typicalDay() -> FocusDay {
        let day = FocusDay(at(2026, 10, 23, 14))
        day.session(minutes: 70, overrides: [(minute: 30, seconds: 300)])
        day.at(at(2026, 10, 23, 16))
        var quick = FocusFixtures.plan(minutes: 25)
        quick.presetName = "Quick"
        day.session(minutes: 25, plan: quick)
        return day
    }

    @Test("Each session's counted stretch, its greyed time with the reason, and the day's total")
    func typical() {
        let day = typicalDay()
        let saved = model(day.credits(), day.ledger.sessions(), now: at(2026, 10, 23, 17))
        #expect(SavedTodayModel.title == "Saved today")
        #expect(saved.rows.map(\.title) == ["Study · 14:00–15:10 · 1h 5m", "Quick · 16:00–16:25 · 25m"])
        #expect(saved.rows.map(\.reasons) == [["Unlocked 5 min"], []])
        #expect(saved.rows.map(\.countedSeconds) == [3900, 1500])
        #expect(saved.rows.allSatisfy { !$0.isRunning })
        #expect(saved.totalSeconds == 5400)
        #expect(saved.total == "1h 30m")
        #expect(saved.emptyLine == nil)
        let twelveHour = model(day.credits(), day.ledger.sessions(), now: at(2026, 10, 23, 17), locale: enUS)
        #expect(twelveHour.rows.first?.title == "Study · 2:00 PM–3:10 PM · 1h 5m")
    }

    @Test("Spoken, each row and the total say their lengths in words: never a bare m or h")
    func spoken() {
        let day = typicalDay()
        let saved = model(day.credits(), day.ledger.sessions(), now: at(2026, 10, 23, 17))
        #expect(saved.rows.map(\.spoken) == [
            "Study, 14:00 to 15:10, \(HomeFormat.spokenDuration(minutes: 65, locale: enGB)). Unlocked 5 minutes",
            "Quick, 16:00 to 16:25, 25 minutes",
        ])
        #expect(saved.totalSpoken == HomeFormat.spokenDuration(minutes: 90, locale: enGB))
        #expect(saved.totalSpoken.hasPrefix("1 hour"))
        let twelveHour = model(day.credits(), day.ledger.sessions(), now: at(2026, 10, 23, 17), locale: enUS)
        #expect(twelveHour.rows.last?.spoken == "Quick, 4:00 PM to 4:25 PM, 25 minutes")

        let capped = FocusDay(at(2026, 10, 23, 8))
        capped.session(minutes: 180)
        capped.at(at(2026, 10, 23, 11, 30))
        capped.session(minutes: 180)
        capped.at(at(2026, 10, 23, 15))
        capped.session(minutes: 50)
        let full = model(capped.credits(), capped.ledger.sessions(), now: at(2026, 10, 23, 16))
        #expect(full.rows.last?.spoken == "Study, 15:00 to 15:50. Over today's \(HomeFormat.spokenDuration(minutes: 360, locale: enGB))")
        #expect(full.totalSpoken == HomeFormat.spokenDuration(minutes: 360, locale: enGB))

        for line in saved.rows.map(\.spoken) + full.rows.map(\.spoken) + [saved.totalSpoken, full.totalSpoken] {
            #expect(line.range(of: #"\d\s?(m|h|min)\b"#, options: .regularExpression) == nil, "\(line)")
        }
    }

    @Test("Over the cap: the greyed reason is Over today's 6h, and the total stops at 6h")
    func capped() {
        let day = FocusDay(at(2026, 10, 23, 8))
        day.session(minutes: 180)
        day.at(at(2026, 10, 23, 11, 30))
        day.session(minutes: 180)
        day.at(at(2026, 10, 23, 15))
        day.session(minutes: 50)
        let saved = model(day.credits(), day.ledger.sessions(), now: at(2026, 10, 23, 16))
        #expect(saved.rows.map(\.title) == ["Study · 08:00–11:00 · 3h", "Study · 11:30–14:30 · 3h", "Study · 15:00–15:50"])
        #expect(saved.rows.map(\.reasons) == [[], [], ["Over today's 6h"]])
        #expect(saved.total == "6h")
    }

    @Test("A running session's time since its last checkpoint counts as display credit, not as a reason")
    func running() throws {
        let script = SessionScript(start: at(2026, 10, 23, 14))
        script.write(.shieldApplied)
        script.after(30 * 60, .shieldVerified)
        let session = try #require(script.record)
        let now = at(2026, 10, 23, 14, 32)
        let saved = model(HoursCredit.credit([session], crediting: [.live], now: now), [session], now: now)
        #expect(saved.rows.map(\.title) == ["Study · 14:00–14:32 · 32m"])
        #expect(saved.rows.first?.reasons == [])
        #expect(saved.rows.first?.isRunning == true)
        #expect(saved.totalSeconds == 32 * 60)
        #expect(saved.total == "32m")
    }

    @Test("Lost confirmation and a plain timer each say why; a row that counted nothing drops its duration")
    func reasons() throws {
        let revoked = SessionScript(start: at(2026, 10, 23, 9))
        revoked.write(.shieldApplied)
        revoked.after(10 * 60, .shieldVerified)
        revoked.after(30, .shieldLost)
        revoked.after(39 * 60 + 30, .sessionEnded(.completed, verified: false))
        let plain = SessionScript(start: at(2026, 10, 23, 14), session: UUID(), plan: FocusFixtures.plan(kind: .plainTimer, selection: nil))
        plain.after(50 * 60, .sessionEnded(.completed, verified: false))
        let lost = try #require(revoked.record)
        let timer = try #require(plain.record)
        let credits = HoursCredit.credit([lost], crediting: [.live], now: revoked.time.now)
            + HoursCredit.credit([timer], crediting: [.live], now: plain.time.now)
        let saved = model(credits, [lost, timer], now: at(2026, 10, 23, 17))
        #expect(saved.rows.map(\.title) == ["Study · 09:00–09:50 · 10m", "Study · 14:00–14:50"])
        #expect(saved.rows.map(\.reasons) == [["Couldn't confirm the block"], ["Plain timer"]])
        #expect(saved.total == "10m")
    }

    @Test("Other days, hidden sessions and starts that never got going are left out")
    func leftOut() throws {
        let yesterday = SessionScript(start: at(2026, 10, 22, 14), session: UUID(),
                                      plan: FocusFixtures.plan(day: "2026-10-22", window: FocusFixtures.window(22)))
        yesterday.write(.shieldApplied)
        yesterday.after(50 * 60, .sessionEnded(.completed, verified: true))
        let hidden = SessionScript(start: at(2026, 10, 23, 9), session: UUID())
        hidden.write(.shieldApplied)
        hidden.after(50 * 60, .sessionEnded(.completed, verified: true))
        hidden.write(.sessionHidden)
        let ghost = SessionScript(start: at(2026, 10, 23, 11), session: UUID())
        ghost.after(1, .sessionEnded(.endedEarly, verified: false))
        let scripts = [yesterday, hidden, ghost]
        let records = try scripts.map { try #require($0.record) }
        let credits = zip(scripts, records).flatMap { HoursCredit.credit([$1], crediting: [.live], now: $0.time.now) }
        let saved = model(credits, records, now: at(2026, 10, 23, 17))
        #expect(saved.rows.isEmpty)
        #expect(saved.totalSeconds == 0)
        #expect(saved.total == "0m")
        #expect(saved.emptyLine == "Nothing saved yet today.")
    }

    @Test("How we count, in five lines, and the definition")
    func howWeCount() {
        #expect(SavedTodayModel.howWeCount == [
            "Counts only while your chosen apps are locked.", "Sleep doesn't count.", "Unlocks don't count.", "Overlaps count once.",
            "Up to 6 hours count each day.",
        ])
        #expect(SavedTodayModel.definition == "Time your chosen apps stayed locked while you were awake.")
    }
}

@Suite("Streak week")
struct StreakWeekTests {
    /// A Friday.
    private let today = LocalDay(year: 2026, month: 10, day: 23)

    private func days(_ list: [Int]) -> [(day: LocalDay, zone: String)] {
        list.map { (day: LocalDay(year: 2026, month: 10, day: $0), zone: "UTC") }
    }

    private func calendar(firstWeekday: Int) -> Calendar {
        var calendar = utc
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    @Test("The title is the current run, with the best run and the rest-day rule under it")
    func lines() {
        let week = StreakWeek(focusDays: [], today: today, calendar: utc, current: 12, best: 21)
        #expect(week.title == "12 days")
        #expect(week.lines == ["Best: 21 days", "2 rest days a week are built in"])
        let one = StreakWeek(focusDays: [], today: today, calendar: utc, current: 1, best: 1)
        #expect(one.title == "1 day")
        #expect(one.lines.first == "Best: 1 day")
    }

    @Test("A broken run reads its best: never lost, never rest days left")
    func broken() {
        let week = StreakWeek(focusDays: days([12, 13]), today: today, calendar: utc, current: 0, best: 21)
        #expect(week.title == "0 days")
        #expect(week.lines.first == "Best: 21 days")
        let words = ([week.title, week.weekLabel] + week.lines).joined(separator: " ").lowercased()
        #expect(!words.contains("lost"))
        #expect(!words.contains("left"))
        #expect(!words.contains("0 rest"))
    }

    @Test("Monday first: finished days tinted, a miss neutral, today pending, the days ahead neutral")
    func mondayFirst() {
        let week = StreakWeek(focusDays: days([19, 20, 22]), today: today, calendar: calendar(firstWeekday: 2), current: 4, best: 21)
        #expect(week.days.count == 7)
        #expect(week.days.first == LocalDay(year: 2026, month: 10, day: 19))
        #expect(week.days.last == LocalDay(year: 2026, month: 10, day: 25))
        #expect(week.dots == [.finished, .finished, .neutral, .finished, .pending, .neutral, .neutral])
        #expect(week.weekLabel == "3 finished days this week")
    }

    @Test("Sunday first: the same days, one place later in the row")
    func sundayFirst() {
        let week = StreakWeek(focusDays: days([19, 20, 22]), today: today, calendar: calendar(firstWeekday: 1), current: 4, best: 21)
        #expect(week.days.first == LocalDay(year: 2026, month: 10, day: 18))
        #expect(week.dots == [.neutral, .finished, .finished, .neutral, .finished, .pending, .neutral])
    }

    @Test("Today turns finished once a session finishes; a Monday is the first dot of a Monday week")
    func todayTurnsFinished() {
        let finished = StreakWeek(focusDays: days([22, 23]), today: today, calendar: calendar(firstWeekday: 2), current: 2, best: 2)
        #expect(finished.dots == [.neutral, .neutral, .neutral, .finished, .finished, .neutral, .neutral])
        #expect(!finished.dots.contains(.pending))
        let monday = StreakWeek(focusDays: days([25]), today: LocalDay(year: 2026, month: 10, day: 26),
                                calendar: calendar(firstWeekday: 2), current: 1, best: 21)
        #expect(monday.dots == [.pending, .neutral, .neutral, .neutral, .neutral, .neutral, .neutral])
        #expect(monday.weekLabel == "No finished days yet this week")
        #expect(StreakWeek(focusDays: days([23]), today: today, calendar: utc, current: 1, best: 1).weekLabel == "1 finished day this week")
    }
}

@Suite("Break dial")
struct BreakDialLayoutTests {
    @Test("One rest mark per 10 seconds; a break cut short at the planned end has fewer")
    func marks() {
        #expect(BreakDialLayout(breakSeconds: 300).markCount == 30)
        #expect(BreakDialLayout(breakSeconds: 180).markCount == 18)
        #expect(BreakDialLayout(breakSeconds: 95).markCount == 10)
        let layout = BreakDialLayout(breakSeconds: 300)
        #expect(abs(layout.angle(ofMark: 15) - .pi) < 1e-9)
    }

    @Test("Marks go out one by one, clockwise from 12 o'clock")
    func goingOut() {
        let layout = BreakDialLayout(breakSeconds: 300)
        #expect(layout.marks(left: 300) == Array(repeating: .rest, count: 30))
        #expect(layout.marks(left: 240) == Array(repeating: .off, count: 6) + Array(repeating: .rest, count: 24))
        #expect(layout.marks(left: 235) == Array(repeating: .off, count: 6) + Array(repeating: .rest, count: 24))
        #expect(layout.marks(left: 9.9) == Array(repeating: .off, count: 29) + [.rest])
        #expect(layout.marks(left: 0) == Array(repeating: .off, count: 30))
        #expect(layout.marks(left: 400) == Array(repeating: .rest, count: 30))
    }
}
