import Foundation
import Testing
@testable import MapleCore
@testable import MapleFocusCore

/// A calendar whose week starts on Monday (en_GB), in UTC.
private let monday: Calendar = {
    var calendar = utc
    calendar.firstWeekday = 2
    return calendar
}()

/// Builds a few weeks of sessions the way the app writes them: on one clock, in start order, whatever order they
/// were added in.
private struct HistoryFixture {
    private struct Spec {
        let id: UUID
        let start: Date
        let plan: FocusPlan
        let seconds: Int
        let reason: EndReason?
        let hide: Bool
    }

    private var specs: [Spec] = []

    /// A session on `day` November 2026 at `hour`:00, `minutes` planned, ended after `ran` minutes (its whole length by
    /// default) or `ranSeconds`. Blocking sessions are confirmed and checkpointed half-way, so they count.
    @discardableResult
    mutating func add(
        day: Int, month: Int = 11, hour: Int = 10, minutes: Int = 50, ran: Int? = nil, ranSeconds: Int? = nil, plain: Bool = false,
        subject: UUID? = nil, preset: String = "Study", hide: Bool = false, ended: Bool = true
    ) -> UUID {
        let id = UUID(uuidString: "00000000-0000-4000-8000-\(String(format: "%012d", specs.count + 1))")!
        var plan = FocusFixtures.plan(
            minutes: minutes, kind: plain ? .plainTimer : .blocking, selection: plain ? nil : FocusFixtures.blockSix,
            day: String(format: "2026-%02d-%02d", month, day), window: FocusFixtures.window(day, month: month)
        )
        plan.subjectID = subject
        plan.presetName = preset
        let early = ran != nil || ranSeconds != nil
        specs.append(Spec(id: id, start: at(2026, month, day, hour), plan: plan, seconds: ranSeconds ?? (ran ?? minutes) * 60,
                          reason: ended ? (early ? .endedEarly : .completed) : nil, hide: hide))
        return id
    }

    var events: [FocusEvent] {
        let ordered = specs.sorted { $0.start < $1.start }
        guard let first = ordered.first else { return [] }
        let day = FocusDay(first.start)
        for spec in ordered {
            day.at(spec.start)
            day.write(.sessionStarted(spec.plan), session: spec.id)
            let length = TimeInterval(spec.seconds)
            if spec.plan.kind == .blocking {
                day.write(.shieldApplied, session: spec.id)
                day.time.advance(length / 2)
                day.write(.shieldVerified, session: spec.id)
                day.time.advance(length / 2)
            } else {
                day.time.advance(length)
            }
            if let reason = spec.reason {
                day.write(.sessionEnded(reason, verified: spec.plan.kind == .blocking), session: spec.id)
            }
            if spec.hide {
                day.time.advance(60)
                day.write(.sessionHidden, session: spec.id)
            }
        }
        return day.events
    }

    func sessions(running: UUID? = nil) -> [StudySession] {
        let records = FocusLedger(events).sessions()
        return StudyHistory.sessions(records, credits: HoursCredit.credit(records, crediting: [.live], now: at(2026, 12, 1)),
                                     running: running)
    }
}

private func subjects(_ names: String...) -> (list: SubjectList, ids: [UUID]) {
    var list = SubjectList()
    var ids: [UUID] = []
    for name in names {
        if case .added(let subject) = list.add(name) { ids.append(subject.id) }
    }
    return (list, ids)
}

@Suite("History's sessions")
struct StudyHistoryTests {
    @Test("An ended session is listed with its Maple day, its time focused, its time saved and how it ended")
    func listed() throws {
        var fixture = HistoryFixture()
        let full = fixture.add(day: 10, hour: 14)
        let early = fixture.add(day: 10, hour: 16, ran: 12)
        let sessions = fixture.sessions()
        #expect(sessions.map(\.id) == [full, early])
        let first = try #require(sessions.first)
        #expect(first.day == LocalDay(year: 2026, month: 11, day: 10))
        #expect(first.start == at(2026, 11, 10, 14))
        #expect(first.end == at(2026, 11, 10, 14, 50))
        #expect(first.focusedSeconds == 3000)
        #expect(first.savedSeconds == 3000)
        #expect(first.finished && first.ranToEnd)
        let second = try #require(sessions.last)
        #expect(second.focusedSeconds == 720)
        #expect(!second.finished && !second.ranToEnd)
    }

    @Test("A plain timer is listed with its time focused and nothing saved")
    func plainTimer() throws {
        var fixture = HistoryFixture()
        fixture.add(day: 10, plain: true)
        let session = try #require(fixture.sessions().first)
        #expect(session.focusedSeconds == 3000)
        #expect(session.savedSeconds == 0)
        #expect(!session.finished)
        #expect(session.ranToEnd)
    }

    @Test("Removed sessions, the running session and starts under a minute are left out")
    func leftOut() {
        var fixture = HistoryFixture()
        fixture.add(day: 10, hour: 9, hide: true)
        let kept = fixture.add(day: 10, hour: 11)
        fixture.add(day: 10, hour: 13, plain: true, ended: false)
        let running = fixture.add(day: 10, hour: 15, ended: false)
        fixture.add(day: 10, hour: 17, ranSeconds: 20, plain: true, preset: "Quick")
        #expect(fixture.sessions(running: running).map(\.id) == [kept])
    }

    @Test("A session cut off without an end is listed up to its last confirmed moment")
    func cutOff() throws {
        var fixture = HistoryFixture()
        let id = fixture.add(day: 10, ended: false)
        let session = try #require(fixture.sessions().first { $0.id == id })
        #expect(session.focusedSeconds == 1500)
        #expect(!session.ranToEnd)
    }

    @Test("A session after midnight belongs to the Maple day it was started in")
    func mapleDay() throws {
        let window = AwakeWindow(start: at(2026, 11, 10, 6), end: at(2026, 11, 11, 1), windDown: at(2026, 11, 11, 0, 15))
        let plan = FocusFixtures.plan(minutes: 25, kind: .plainTimer, selection: nil, day: "2026-11-10", window: window)
        let script = SessionScript(start: at(2026, 11, 11, 0, 10), plan: plan)
        script.after(25 * 60, .sessionEnded(.completed, verified: false))
        let session = try #require(StudyHistory.sessions(script.ledger.sessions(), credits: [], running: nil).first)
        #expect(session.day == LocalDay(year: 2026, month: 11, day: 10))
    }
}

@Suite("History's periods")
struct HistoryPeriodTests {
    private let today = LocalDay(year: 2026, month: 11, day: 12)

    @Test("A week runs from the calendar's first weekday for 7 days")
    func week() {
        let period = HistoryPeriod(.week, containing: today, calendar: monday)
        #expect(period.days.first == LocalDay(year: 2026, month: 11, day: 9))
        #expect(period.days.last == LocalDay(year: 2026, month: 11, day: 15))
        #expect(period.days.count == 7)

        var sunday = utc
        sunday.firstWeekday = 1
        #expect(HistoryPeriod(.week, containing: today, calendar: sunday).days.first == LocalDay(year: 2026, month: 11, day: 8))
    }

    @Test("A month is its calendar month, whatever its length")
    func month() {
        let november = HistoryPeriod(.month, containing: today, calendar: monday)
        #expect(november.days.first == LocalDay(year: 2026, month: 11, day: 1))
        #expect(november.days.count == 30)
        #expect(november.shifted(by: -9, calendar: monday).days.count == 28)
        #expect(november.shifted(by: 2, calendar: monday).days.first == LocalDay(year: 2027, month: 1, day: 1))
    }

    @Test("Stepping moves a whole period")
    func stepping() {
        let week = HistoryPeriod(.week, containing: today, calendar: monday)
        #expect(week.shifted(by: -1, calendar: monday).days.first == LocalDay(year: 2026, month: 11, day: 2))
        #expect(week.shifted(by: -1, calendar: monday).shifted(by: 1, calendar: monday) == week)
    }

    @Test("Titles: the period being lived in by name, others by their dates")
    func titles() {
        let week = HistoryPeriod(.week, containing: today, calendar: monday)
        #expect(week.title(today: today, calendar: monday, locale: enGB) == "This week")
        #expect(week.shifted(by: -1, calendar: monday).title(today: today, calendar: monday, locale: enGB) == "2–8 Nov")
        #expect(week.shifted(by: -2, calendar: monday).title(today: today, calendar: monday, locale: enGB) == "26 Oct – 1 Nov")
        let month = HistoryPeriod(.month, containing: today, calendar: monday)
        #expect(month.title(today: today, calendar: monday, locale: enGB) == "This month")
        #expect(month.shifted(by: -1, calendar: monday).title(today: today, calendar: monday, locale: enGB) == "October")
        #expect(month.shifted(by: -11, calendar: monday).title(today: today, calendar: monday, locale: enGB) == "December 2025")
    }
}

@Suite("History's page")
struct HistoryPageTests {
    private let today = LocalDay(year: 2026, month: 11, day: 12)

    private func page(
        _ fixture: HistoryFixture, _ span: HistoryPeriod.Span = .week, shift: Int = 0, subjects: SubjectList = SubjectList(),
        intentions: [UUID: String] = [:], filter: HistoryPage.SubjectKey? = nil
    ) -> HistoryPage {
        let period = HistoryPeriod(span, containing: today, calendar: monday).shifted(by: shift, calendar: monday)
        return HistoryPage(sessions: fixture.sessions(), period: period, today: today, subjects: subjects, intentions: intentions,
                           filter: filter, calendar: monday, locale: enGB)
    }

    @Test("The numeral is the period's time focused; the line under it is time saved and sessions finished")
    func totals() {
        var fixture = HistoryFixture()
        fixture.add(day: 9, minutes: 50)
        fixture.add(day: 10, minutes: 90)
        fixture.add(day: 10, hour: 15, minutes: 25, plain: true)
        fixture.add(day: 3, minutes: 50)                 // last week
        let page = page(fixture)
        #expect(page.title == "This week")
        #expect(page.numeral == "2h 45m")
        #expect(page.caption == "focused")
        #expect(page.savedLine == "2h 20m saved · 2 sessions finished")
        #expect(page.canGoBack)
        #expect(!page.canGoForward)

        let last = self.page(fixture, shift: -1)
        #expect(last.numeral == "50m")
        #expect(last.savedLine == "50m saved · 1 session finished")
        #expect(!last.canGoBack)
        #expect(last.canGoForward)
    }

    @Test("With nothing saved the second line is left out")
    func nothingSaved() {
        var fixture = HistoryFixture()
        fixture.add(day: 10, plain: true)
        #expect(page(fixture).savedLine == nil)
    }

    @Test("One bar a day: 7 in a week from its first weekday, one per date in a month, tinted when a session finished")
    func bars() {
        var fixture = HistoryFixture()
        fixture.add(day: 9, minutes: 50)
        fixture.add(day: 11, minutes: 25, plain: true)
        let week = page(fixture)
        #expect(week.bars.map(\.seconds) == [3000, 0, 1500, 0, 0, 0, 0])
        #expect(week.bars.map(\.hasFinished) == [true, false, false, false, false, false, false])
        #expect(week.bars.map(\.label) == ["M", "T", "W", "T", "F", "S", "S"])
        #expect(week.peakSeconds == 3000)
        #expect(week.bars[0].spoken == "Monday 9 November, 50 minutes")
        #expect(week.bars[1].spoken == "Tuesday 10 November, no sessions")

        let month = page(fixture, .month)
        #expect(month.bars.count == 30)
        #expect(month.bars[8].seconds == 3000)
        #expect(month.bars.map(\.label).prefix(3) == ["1", "2", "3"])
    }

    @Test("By subject: longest first, then past subjects, then no subject; hidden when subjects were never used")
    func bySubject() {
        var (list, ids) = subjects("Biology", "Maths", "History")
        var fixture = HistoryFixture()
        fixture.add(day: 9, minutes: 30, subject: ids[0])
        fixture.add(day: 10, minutes: 90, subject: ids[1])
        fixture.add(day: 10, hour: 15, minutes: 120, subject: ids[2])
        fixture.add(day: 11, minutes: 60)
        list.remove(ids[2])
        let page = page(fixture, subjects: list)
        #expect(page.subjects.map(\.name) == ["Maths", "Biology", "History", "No subject"])
        #expect(page.subjects.map(\.time) == ["1h 30m", "30m", "2h", "1h"])
        #expect(page.subjects.map(\.isPast) == [false, false, true, false])
        #expect(page.subjects.map(\.share) == [0.75, 0.25, 1, 0.5])
        #expect(page.subjects.last?.key == HistoryPage.SubjectKey.none)

        var plain = HistoryFixture()
        plain.add(day: 10)
        #expect(self.page(plain).subjects.isEmpty)
        // With subjects set up, a period without any still shows where the time went.
        #expect(self.page(plain, subjects: list).subjects.map(\.name) == ["No subject"])
    }

    @Test("A subject the list no longer knows counts as no subject")
    func unknownSubject() {
        var fixture = HistoryFixture()
        fixture.add(day: 10, minutes: 30, subject: UUID())
        let (list, _) = subjects("Biology")
        #expect(page(fixture, subjects: list).subjects.map(\.name) == ["No subject"])
    }

    @Test("Sessions are grouped by day, newest first, each with its title, start, time focused and intention")
    func groups() throws {
        let (list, ids) = subjects("Biology")
        var fixture = HistoryFixture()
        let old = fixture.add(day: 9, hour: 9, minutes: 50, subject: ids[0])
        let yesterday = fixture.add(day: 11, hour: 18, minutes: 25, plain: true, preset: "Quick")
        let morning = fixture.add(day: 12, hour: 8, minutes: 50, ran: 20)
        let noon = fixture.add(day: 12, hour: 12, minutes: 90, subject: ids[0])
        let page = page(fixture, subjects: list, intentions: [noon: "Chapter 4"])
        #expect(page.groups.map(\.title) == ["Today", "Yesterday", "Mon 9 Nov"])
        #expect(page.groups.map { $0.rows.map(\.id) } == [[noon, morning], [yesterday], [old]])
        let first = try #require(page.groups.first?.rows.first)
        #expect(first.title == "Study · Biology")
        #expect(first.time == "12:00")
        #expect(first.focused == "1h 30m")
        #expect(first.intention == "Chapter 4")
        #expect(first.note == nil)
        #expect(first.ranToEnd)
        #expect(first.spoken == "Study, Biology, 12:00, 1 hour, 30 minutes focused. Chapter 4")
        let early = try #require(page.groups.first?.rows.last)
        #expect(early.title == "Study")
        #expect(!early.ranToEnd)
        let plain = try #require(page.groups[1].rows.first)
        #expect(plain.title == "Quick")
        #expect(plain.note == "Not counted")
        #expect(plain.spoken == "Quick, 18:00, 25 minutes focused. Not counted")
    }

    @Test("Choosing a subject filters the sessions, never the totals")
    func filter() {
        let (list, ids) = subjects("Biology", "Maths")
        var fixture = HistoryFixture()
        let bio = fixture.add(day: 9, minutes: 50, subject: ids[0])
        fixture.add(day: 10, minutes: 50, subject: ids[1])
        let none = fixture.add(day: 11, minutes: 50)
        let biology = page(fixture, subjects: list, filter: .subject(ids[0]))
        #expect(biology.groups.flatMap(\.rows).map(\.id) == [bio])
        #expect(biology.numeral == "2h 30m")
        #expect(biology.subjects.map(\.isSelected) == [true, false, false])
        #expect(page(fixture, subjects: list, filter: HistoryPage.SubjectKey.none).groups.flatMap(\.rows).map(\.id) == [none])
    }

    @Test("Empty states say what is empty")
    func empty() {
        #expect(page(HistoryFixture()).emptyLine == "Your sessions will appear here.")
        var fixture = HistoryFixture()
        fixture.add(day: 3)
        #expect(page(fixture).emptyLine == "No sessions this week.")
        #expect(page(fixture, .month).emptyLine == nil)
        #expect(page(fixture, .month, shift: -1).emptyLine == "No sessions that month.")
        #expect(page(fixture, shift: -2).emptyLine == "No sessions that week.")
        let (list, ids) = subjects("Biology")
        #expect(page(fixture, shift: -1, subjects: list, filter: .subject(ids[0])).emptyLine == "No sessions for this subject.")
    }

    @Test("This week's strip: time focused in the week being lived in, or nothing before the first session")
    func strip() {
        var fixture = HistoryFixture()
        #expect(HistoryPage.weekStrip(fixture.sessions(), today: today, calendar: monday) == nil)
        fixture.add(day: 3)
        #expect(HistoryPage.weekStrip(fixture.sessions(), today: today, calendar: monday) == "0m focused this week")
        fixture.add(day: 10, minutes: 90)
        #expect(HistoryPage.weekStrip(fixture.sessions(), today: today, calendar: monday) == "1h 30m focused this week")
    }
}

@Suite("Session detail")
struct SessionDetailTests {
    private let today = LocalDay(year: 2026, month: 11, day: 12)
    private let start = at(2026, 11, 10, 14)

    private func detail(_ script: SessionScript, subject: String? = nil) throws -> SessionDetailModel {
        let records = script.ledger.sessions()
        let credit = HoursCredit.credit(records, crediting: [.live], now: at(2026, 12, 1)).first
        return SessionDetailModel(session: try #require(records.first), credit: credit, subject: subject, today: today,
                                  calendar: monday, locale: enGB)
    }

    private func plan(minutes: Int = 60, breakMinutes: Int = 5, plain: Bool = false) -> FocusPlan {
        FocusFixtures.plan(minutes: minutes, breakMinutes: breakMinutes, kind: plain ? .plainTimer : .blocking,
                           selection: plain ? nil : FocusFixtures.blockSix, day: "2026-11-10",
                           window: FocusFixtures.window(10, month: 11))
    }

    @Test("The timeline shows locked time, the break and an unlock, in order, as shares of the session")
    func timeline() throws {
        let script = SessionScript(start: start, plan: plan())
        script.write(.shieldApplied)
        script.after(15 * 60, .breakStarted(seconds: 300))      // 14:15–14:20
        script.after(5 * 60, .breakEnded)
        script.after(10 * 60, .overrideStarted(seconds: 300))   // 14:30–14:35
        script.after(5 * 60, .overrideEnded)
        script.after(25 * 60, .sessionEnded(.completed, verified: true))
        let model = try detail(script, subject: "Biology")
        #expect(model.title == "Study · Biology")
        #expect(model.whenLine == "Tue 10 Nov · 14:00–15:00")
        #expect(model.segments.map(\.kind) == [.locked, .breakTime, .locked, .unlocked, .locked])
        #expect(model.segments.map { Int(($0.to - $0.from) * 60 + 0.5) } == [15, 5, 10, 5, 25])
        #expect(model.segments.first?.from == 0 && model.segments.last?.to == 1)
        #expect(model.totalsLine == "Focused 55m · Saved 55m")
        #expect(model.reasons == ["Unlocked 5 min"])
        #expect(model.legend == [.locked, .breakTime, .unlocked])
        #expect(model.timelineSpoken == "Locked 50 minutes. Break 5 minutes. Unlocked 5 minutes.")
    }

    @Test("A plain timer is one open stretch, not counted")
    func plainTimer() throws {
        let script = SessionScript(start: start, plan: plan(minutes: 25, breakMinutes: 0, plain: true))
        script.after(25 * 60, .sessionEnded(.completed, verified: false))
        let model = try detail(script)
        #expect(model.title == "Study")
        #expect(model.segments.map(\.kind) == [.open])
        #expect(model.totalsLine == "Focused 25m · Not counted")
        #expect(model.reasons == ["Plain timer"])
        #expect(model.timelineSpoken == "Apps not locked 25 minutes.")
    }

    @Test("Time after the block was lost shows as not locked")
    func lost() throws {
        let script = SessionScript(start: start, plan: plan(minutes: 60, breakMinutes: 0))
        script.write(.shieldApplied)
        script.after(30 * 60, .shieldVerified)
        script.after(60, .shieldLost)
        script.after(29 * 60, .sessionEnded(.completed, verified: false))
        let model = try detail(script)
        #expect(model.segments.map(\.kind) == [.locked, .open])
        #expect(model.totalsLine == "Focused 1h · Saved 30m")
        #expect(model.reasons == ["Couldn't confirm the block"])
    }

    @Test("An earlier year is named in the date")
    func earlierYear() throws {
        let old = FocusFixtures.plan(minutes: 25, kind: .plainTimer, selection: nil, day: "2025-12-30",
                                     window: AwakeWindow(start: at(2025, 12, 30, 6), end: at(2025, 12, 30, 23), windDown: at(2025, 12, 30, 22)))
        let script = SessionScript(start: at(2025, 12, 30, 9), plan: old)
        script.after(25 * 60, .sessionEnded(.completed, verified: false))
        #expect(try detail(script).whenLine == "Tue 30 Dec 2025 · 09:00–09:25")
    }
}
