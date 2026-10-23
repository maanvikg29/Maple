import Foundation
import Testing
@testable import MapleCore

@Suite("Hours credit")
struct HoursCreditTests {
    private func one(_ day: FocusDay, now: Date? = nil) throws -> SessionCredit {
        try #require(day.credits(now: now).first)
    }

    @Test("A session proven to its planned end credits exactly its length, however long the phone slept in between")
    func exact() throws {
        let day = FocusDay(at(2026, 10, 23, 14))
        day.session(minutes: 50)
        let credit = try one(day)
        #expect(credit.seconds == 3000)
        #expect(credit.awakeSeconds == 3000)
        #expect(credit.day == LocalDay(year: 2026, month: 10, day: 23))
        #expect(credit.stretches.allSatisfy { $0.counted })
    }

    @Test("3,600 seconds is an hour; 3,599 isn't")
    func hourBoundary() throws {
        let full = FocusDay(at(2026, 10, 23, 9))
        full.session(minutes: 60)
        #expect(try one(full).seconds == 3600)
        let short = FocusDay(at(2026, 10, 23, 9))
        let id = short.session(minutes: 0, planned: 60, reason: nil)
        short.time.advance(3599)
        short.write(.sessionEnded(.endedEarly, verified: true), session: id)
        #expect(try one(short).seconds == 3599)
    }

    @Test("Overlapping sessions count once")
    func overlap() throws {
        let day = FocusDay(at(2026, 10, 23, 14))
        let a = UUID(), b = UUID()
        day.write(.sessionStarted(FocusFixtures.plan()), session: a)
        day.write(.shieldApplied, session: a)                                  // 14:00
        day.at(at(2026, 10, 23, 14, 10))
        day.write(.sessionStarted(FocusFixtures.plan()), session: b)
        day.write(.shieldApplied, session: b)                                  // 14:10
        day.at(at(2026, 10, 23, 14, 50))
        day.write(.sessionEnded(.completed, verified: true), session: a)
        day.at(at(2026, 10, 23, 15))
        day.write(.sessionEnded(.completed, verified: true), session: b)
        let credits = day.credits()
        #expect(credits.map(\.seconds) == [3000, 600])
        #expect(credits[1].stretches.contains { $0.rule == .overlap && $0.interval.duration == 2400 })
    }

    @Test("A 23:40–00:30 session with bed at 01:00 counts whole, on one Maple day")
    func acrossMidnight() throws {
        let window = AwakeWindow(start: at(2026, 10, 23, 8), end: at(2026, 10, 24, 1), windDown: at(2026, 10, 24, 0, 15))
        let day = FocusDay(at(2026, 10, 23, 23, 40))
        day.session(minutes: 50, plan: FocusFixtures.plan(window: window))
        let credit = try one(day)
        #expect(credit.seconds == 3000)
        #expect(credit.day == LocalDay(year: 2026, month: 10, day: 23))
    }

    @Test("A session across the autumn clock change credits its real length")
    func clockChangeDay() throws {
        var london = Calendar(identifier: .gregorian)
        london.timeZone = TimeZone(identifier: "Europe/London")!
        let window = AwakeWindow(start: at(2026, 10, 24, 6, in: london), end: at(2026, 10, 25, 4, in: london),
                                 windDown: at(2026, 10, 25, 3, in: london))
        let day = FocusDay(at(2026, 10, 25, 0, 40, in: london))
        day.session(minutes: 90, plan: FocusFixtures.plan(minutes: 90, day: "2026-10-24", window: window))
        #expect(try one(day).seconds == 5400)
    }

    @Test("A flight mid-session changes nothing: the day and zone are the plan's")
    func flight() throws {
        let day = FocusDay(at(2026, 10, 23, 14))
        let id = day.session(minutes: 25, planned: 50, reason: nil)
        day.time.setZone("America/New_York")
        day.time.advance(25 * 60)
        day.write(.sessionEnded(.completed, verified: true), session: id)
        let credit = try one(day)
        #expect(credit.seconds == 3000)
        #expect(credit.zone == "UTC")
    }

    @Test("Time after the last checkpoint is unconfirmed while running, and never counted")
    func provisional() throws {
        let day = FocusDay(at(2026, 10, 23, 14))
        let id = day.session(minutes: 20, planned: 50, reason: nil)
        day.write(.shieldVerified, session: id)                                // 14:20:05
        day.time.advance(10 * 60)
        let credit = try one(day)
        #expect(credit.seconds == 1200)
        #expect(credit.stretches.last?.rule == .unconfirmed)
        #expect(credit.stretches.last?.interval.duration == 600)
        let session = try #require(day.ledger.sessions().first)
        #expect(HoursCredit.provisionalSeconds(for: session, now: day.time.now, roomLeftToday: 21_600 - 1200) == 600)
        #expect(HoursCredit.provisionalSeconds(for: session, now: day.time.now, roomLeftToday: 100) == 100)
    }

    @Test("Revoked access earns credit up to the last checkpoint")
    func revoked() throws {
        let day = FocusDay(at(2026, 10, 23, 14))
        let id = day.session(minutes: 10, planned: 50, reason: nil)
        day.write(.shieldVerified, session: id)
        day.time.advance(60)
        day.write(.shieldLost, session: id)
        day.time.advance(39 * 60)
        day.write(.sessionEnded(.completed, verified: false), session: id)
        let credit = try one(day)
        #expect(credit.seconds == 600)
        #expect(!credit.finished)
    }

    @Test("A restart mid-session leaves its gap unconfirmed, so every second of the session carries a rule")
    func rebootGap() throws {
        let day = FocusDay(at(2026, 10, 23, 14))
        let id = day.session(minutes: 10, planned: 50, reason: nil)
        day.write(.shieldVerified, session: id)                                // 14:10:05, last proof before the restart
        day.time.reboot("b2", wall: at(2026, 10, 23, 14, 20, 5))
        day.write(.shieldVerified, session: id)                                // 14:20:05, first proof after it
        day.time.advance(30 * 60)
        day.write(.sessionEnded(.completed, verified: true), session: id)      // 14:50:05, the planned end
        let credit = try one(day)
        #expect(credit.seconds == 2400)
        #expect(credit.stretches.filter { $0.rule == .unconfirmed }.map(\.interval)
                == [DateInterval(start: at(2026, 10, 23, 14, 10, 5), end: at(2026, 10, 23, 14, 20, 5))])
        #expect(credit.stretches.reduce(0) { $0 + $1.interval.duration } == 3000)   // 14:00:05 to 14:50:05, none left out
    }

    @Test("A plain timer earns nothing, and preview events earn nothing in live launches")
    func nothingCounts() throws {
        let plain = FocusDay(at(2026, 10, 23, 14))
        plain.session(minutes: 50, plan: FocusFixtures.plan(kind: .plainTimer, selection: nil))
        let credit = try one(plain)
        #expect(credit.seconds == 0)
        #expect(credit.stretches.first?.rule == .plainTimer)

        let preview = FocusDay(at(2026, 10, 23, 14))
        preview.session(minutes: 50, source: .preview)
        #expect(preview.credits().isEmpty)
        #expect(preview.credits(sources: [.live, .preview]).first?.seconds == 3000)
    }

    @Test("A selection that doesn't qualify, run to its end, earns nothing and doesn't finish")
    func notQualifying() throws {
        let day = FocusDay(at(2026, 10, 23, 14))
        day.session(minutes: 50, plan: FocusFixtures.plan(selection: SelectionSummary(mode: .onlyThese, apps: 24, sites: 0, categories: 0)))
        let credit = try one(day)
        #expect(credit.seconds == 0)
        #expect(!credit.finished)
        #expect(credit.stretches.first?.rule == .notQualifying)
    }

    @Test("A 50-minute session with a break at minute 30 credits 50 minutes and ends on time")
    func breakCounts() throws {
        let day = FocusDay(at(2026, 10, 23, 14))
        let id = day.session(minutes: 30, planned: 50, reason: nil)
        day.write(.breakStarted(seconds: 300), session: id)
        day.time.advance(300)
        day.write(.breakEnded, session: id)
        day.time.advance(15 * 60)
        day.write(.sessionEnded(.completed, verified: true), session: id)
        let credit = try one(day)
        #expect(credit.seconds == 3000)
        #expect(credit.endedAt == at(2026, 10, 23, 14, 50, 5))
        #expect(credit.finished)
    }

    @Test("Before 60 minutes before wake and after bedtime don't count")
    func awakeWindow() throws {
        let evening = FocusDay(at(2026, 10, 23, 22, 30))
        evening.session(minutes: 50)
        let crossing = try one(evening)
        #expect(crossing.seconds == 1795)                                      // 22:30:05 to 23:00
        #expect(crossing.stretches.contains { $0.rule == .afterBedtime && $0.interval.duration == 1205 })

        let night = FocusDay(at(2026, 10, 23, 23, 10))
        night.session(minutes: 50)
        let after = try one(night)
        #expect(after.seconds == 0)
        #expect(!after.finished)

        let dawn = FocusDay(at(2026, 10, 23, 5, 30))
        dawn.session(minutes: 50)
        let early = try one(dawn)
        #expect(early.seconds == 1205)                                         // 06:00 to 06:20:05
        #expect(early.stretches.first?.rule == .beforeMorning)
    }

    @Test("At most 6 hours count a day, earlier time first")
    func dailyCap() throws {
        let day = FocusDay(at(2026, 10, 23, 7))
        for _ in 0..<7 { day.session(minutes: 60) }
        let credits = day.credits()
        #expect(credits.reduce(0) { $0 + $1.seconds } == 21_600)
        #expect(credits.last?.seconds == 0)
        #expect(credits.last?.stretches.first?.rule == .dailyCap)
    }

    @Test("An override removes its whole window")
    func override() throws {
        let day = FocusDay(at(2026, 10, 23, 14))
        day.session(minutes: 50, overrides: [(minute: 10, seconds: 120)])
        let credit = try one(day)
        #expect(credit.seconds == 2880)
        #expect(credit.stretches.contains { $0.rule == .override && $0.interval.duration == 120 })
    }

    @Test("Finished needs 20 counted minutes, ¾ of the plan and the planned end")
    func finished() throws {
        let gentle = FocusDay(at(2026, 10, 23, 14))
        gentle.session(minutes: 20, plan: FocusFixtures.plan(minutes: 20, strictness: .gentle),
                       overrides: [(minute: 2, seconds: 60), (minute: 6, seconds: 60), (minute: 10, seconds: 60), (minute: 14, seconds: 60)])
        #expect(try !one(gentle).finished)

        for reason in [EndReason.endedEarly, .emergencyRelease, .releaseAll] {
            let day = FocusDay(at(2026, 10, 23, 14))
            day.session(minutes: 50, reason: reason)
            #expect(try !one(day).finished, "\(reason)")
        }

        let quick = FocusDay(at(2026, 10, 23, 14))
        quick.session(minutes: 25)
        #expect(try one(quick).finished)
    }

    @Test("Over the daily cap still finishes")
    func overCapFinishes() throws {
        let day = FocusDay(at(2026, 10, 23, 7))
        day.session(minutes: 175, reason: .endedEarly)
        day.session(minutes: 175, reason: .endedEarly)
        day.session(minutes: 50)
        let last = try #require(day.credits().last)
        #expect(last.seconds == 600)
        #expect(last.finished)
    }

    @Test("At most 3 finished sessions count a day, in the order they ended")
    func threeADay() {
        let day = FocusDay(at(2026, 10, 23, 9))
        for _ in 0..<4 { day.session(minutes: 25) }
        #expect(day.credits().map(\.finished) == [true, true, true, false])
    }

    @Test("Subtracting a window splits and reports what it removed")
    func subtract() {
        let piece = DateInterval(start: at(2026, 10, 23, 14), duration: 3600)
        let (kept, removed) = HoursCredit.subtract([piece], DateInterval(start: at(2026, 10, 23, 14, 10), duration: 600))
        #expect(kept.map(\.duration) == [600, 2400])
        #expect(removed.map(\.duration) == [600])
    }

    /// Golden ledgers, written as the app writes them (one JSON object per line), with their exact credit. A change
    /// to the event format or the credit rules shows up here first.
    @Test("Golden ledgers credit exactly what they always have", arguments: [
        (#"""
{"id":"A1-1","v":1,"type":"sessionStarted","session":"00000000-0000-4000-8000-0000000000A1","device":"00000000-0000-4000-8000-0000000000D1","writer":"app","seq":1,"source":"live","credit":true,"at":{"wall":1792764000,"cont":1000000000000,"boot":"b1","zone":"UTC"},"plan":{"presetID":"00000000-0000-4000-8000-00000000F001","presetName":"Study","verb":"study","plannedSeconds":3000,"breakSeconds":0,"strictness":"steady","kind":"blocking","selection":{"mode":"blockThese","apps":6,"sites":0,"categories":0},"startedFrom":"focusTab","mapleDay":"2026-10-23","window":{"start":814428000,"end":814489200,"windDown":814486500},"zone":"UTC","appBuild":"1","rulesVersion":1}}
{"id":"A1-2","v":1,"type":"shieldApplied","session":"00000000-0000-4000-8000-0000000000A1","device":"00000000-0000-4000-8000-0000000000D1","writer":"app","seq":2,"source":"live","credit":true,"at":{"wall":1792764005,"cont":1005000000000,"boot":"b1","zone":"UTC"}}
{"id":"A1-3","v":1,"type":"shieldVerified","session":"00000000-0000-4000-8000-0000000000A1","device":"00000000-0000-4000-8000-0000000000D1","writer":"app","seq":3,"source":"live","credit":true,"at":{"wall":1792765205,"cont":2205000000000,"boot":"b1","zone":"UTC"}}
{"id":"A1-4","v":1,"type":"sessionEnded","session":"00000000-0000-4000-8000-0000000000A1","device":"00000000-0000-4000-8000-0000000000D1","writer":"app","seq":4,"source":"live","credit":true,"at":{"wall":1792767005,"cont":4005000000000,"boot":"b1","zone":"UTC"},"reason":"completed","verified":true}
"""#, 3000, true),
        (#"""
{"id":"A2-1","v":1,"type":"sessionStarted","session":"00000000-0000-4000-8000-0000000000A2","device":"00000000-0000-4000-8000-0000000000D1","writer":"app","seq":1,"source":"live","credit":true,"at":{"wall":1792764000,"cont":1000000000000,"boot":"b1","zone":"UTC"},"plan":{"presetID":"00000000-0000-4000-8000-00000000F001","presetName":"Study","verb":"study","plannedSeconds":3000,"breakSeconds":0,"strictness":"steady","kind":"blocking","selection":{"mode":"blockThese","apps":6,"sites":0,"categories":0},"startedFrom":"focusTab","mapleDay":"2026-10-23","window":{"start":814428000,"end":814489200,"windDown":814486500},"zone":"UTC","appBuild":"1","rulesVersion":1}}
{"id":"A2-2","v":1,"type":"shieldApplied","session":"00000000-0000-4000-8000-0000000000A2","device":"00000000-0000-4000-8000-0000000000D1","writer":"app","seq":2,"source":"live","credit":true,"at":{"wall":1792764005,"cont":1005000000000,"boot":"b1","zone":"UTC"}}
{"id":"A2-3","v":1,"type":"shieldVerified","session":"00000000-0000-4000-8000-0000000000A2","device":"00000000-0000-4000-8000-0000000000D1","writer":"app","seq":3,"source":"live","credit":true,"at":{"wall":1792764605,"cont":1605000000000,"boot":"b1","zone":"UTC"}}
{"id":"A2-4","v":1,"type":"shieldLost","session":"00000000-0000-4000-8000-0000000000A2","device":"00000000-0000-4000-8000-0000000000D1","writer":"app","seq":4,"source":"live","credit":true,"at":{"wall":1792765205,"cont":2205000000000,"boot":"b1","zone":"UTC"}}
{"id":"A2-5","v":1,"type":"sessionEnded","session":"00000000-0000-4000-8000-0000000000A2","device":"00000000-0000-4000-8000-0000000000D1","writer":"app","seq":5,"source":"live","credit":true,"at":{"wall":1792767005,"cont":4005000000000,"boot":"b1","zone":"UTC"},"reason":"completed","verified":false}
"""#, 600, false),
        (#"""
{"id":"A3-1","v":1,"type":"sessionStarted","session":"00000000-0000-4000-8000-0000000000A3","device":"00000000-0000-4000-8000-0000000000D1","writer":"app","seq":1,"source":"live","credit":true,"at":{"wall":1792764000,"cont":1000000000000,"boot":"b1","zone":"UTC"},"plan":{"presetID":"00000000-0000-4000-8000-00000000F001","presetName":"Study","verb":"study","plannedSeconds":3000,"breakSeconds":0,"strictness":"steady","kind":"blocking","selection":{"mode":"blockThese","apps":6,"sites":0,"categories":0},"startedFrom":"focusTab","mapleDay":"2026-10-23","window":{"start":814428000,"end":814489200,"windDown":814486500},"zone":"UTC","appBuild":"1","rulesVersion":1}}
{"id":"A3-2","v":1,"type":"shieldApplied","session":"00000000-0000-4000-8000-0000000000A3","device":"00000000-0000-4000-8000-0000000000D1","writer":"app","seq":2,"source":"live","credit":true,"at":{"wall":1792764005,"cont":1005000000000,"boot":"b1","zone":"UTC"}}
{"id":"A3-3","v":1,"type":"shieldVerified","session":"00000000-0000-4000-8000-0000000000A3","device":"00000000-0000-4000-8000-0000000000D1","writer":"app","seq":3,"source":"live","credit":true,"at":{"wall":1792764605,"cont":1605000000000,"boot":"b1","zone":"UTC"}}
{"id":"A3-4","v":1,"type":"focusWarp","session":"00000000-0000-4000-8000-0000000000A3","device":"00000000-0000-4000-8000-0000000000D1","writer":"app","seq":4,"source":"live","credit":true,"at":{"wall":1792765205,"cont":2205000000000,"boot":"b1","zone":"UTC"},"warp":2}
{"id":"A3-5","v":1,"type":"sessionEnded","session":"00000000-0000-4000-8000-0000000000A3","device":"00000000-0000-4000-8000-0000000000D1","writer":"app","seq":5,"source":"live","credit":true,"at":{"wall":1792767005,"cont":4005000000000,"boot":"b1","zone":"UTC"},"reason":"completed","verified":true}
{"id":"torn-6","v":1,"type":"shieldVer
"""#, 600, false),
    ])
    func golden(lines: String, seconds: Int, finished: Bool) throws {
        let events = lines.split(separator: "\n").compactMap { try? JSONDecoder().decode(FocusEvent.self, from: Data($0.utf8)) }
        let credit = try #require(HoursCredit.credit(FocusLedger(events).sessions(), crediting: [.live], now: at(2026, 10, 24)).first)
        #expect(credit.seconds == seconds)
        #expect(credit.finished == finished)
        #expect(credit.day == LocalDay(year: 2026, month: 10, day: 23))
    }
}
