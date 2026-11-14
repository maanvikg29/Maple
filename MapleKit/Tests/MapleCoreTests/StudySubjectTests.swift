import Foundation
import Testing
@testable import MapleCore
@testable import MapleFocusCore

private let biology = UUID(uuidString: "00000000-0000-4000-8000-0000000005B1")!
private let maths = UUID(uuidString: "00000000-0000-4000-8000-0000000005B2")!

@Suite("A session's subject in the ledger")
struct SessionSubjectTests {
    private let start = at(2026, 10, 23, 14)

    private func plan(subject: UUID?) -> FocusPlan {
        var plan = FocusFixtures.plan()
        plan.subjectID = subject
        return plan
    }

    @Test("A plan carries its subject through the ledger's JSON, and a plan written before subjects has none")
    func planCoding() throws {
        let data = try JSONEncoder().encode(plan(subject: biology))
        #expect(try JSONDecoder().decode(FocusPlan.self, from: data).subjectID == biology)

        var old = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        old["subjectID"] = nil
        let decoded = try JSONDecoder().decode(FocusPlan.self, from: JSONSerialization.data(withJSONObject: old))
        #expect(decoded.subjectID == nil)
        #expect(decoded.presetName == "Study")
    }

    @Test("A subject change round-trips, names its subject or none, and never changes credit")
    func eventCoding() throws {
        for subject in [biology, nil] {
            let script = SessionScript(start: start)
            script.after(60, .subjectChanged(subject))
            let event = try #require(script.events.last)
            #expect(event.kind.type == "subjectChanged")
            #expect(!event.affectsCredit)
            let decoded = try JSONDecoder().decode(FocusEvent.self, from: JSONEncoder().encode(event))
            #expect(decoded == event)
            #expect(decoded.kind == .subjectChanged(subject))
        }
    }

    @Test("The session's subject is its plan's until it is changed; the newest change wins, even after the end")
    func newestWins() throws {
        let script = SessionScript(start: start, plan: plan(subject: biology))
        script.after(5, .shieldApplied)
        #expect(script.record?.subjectID == biology)
        script.after(60, .subjectChanged(maths))
        #expect(script.record?.subjectID == maths)
        script.after(49 * 60, .sessionEnded(.completed, verified: true))
        script.after(600, .subjectChanged(nil))
        #expect(script.record?.subjectID == nil)
        script.after(60, .subjectChanged(biology))
        #expect(script.record?.subjectID == biology)
    }

    @Test("Changing the subject mid-session doesn't stop the proof of the block")
    func creditUntouched() throws {
        let script = SessionScript(start: start)
        script.after(5, .shieldApplied)
        script.after(10 * 60, .subjectChanged(maths))
        script.after(20 * 60, .shieldVerified)
        script.after(20 * 60, .sessionEnded(.completed, verified: true))
        let record = try #require(script.record)
        #expect(record.lostAt == nil)
        #expect(record.provenIntervals == [DateInterval(start: start.addingTimeInterval(5), duration: 3000)])
    }
}

@Suite("Time focused")
struct FocusedTimeTests {
    private let start = at(2026, 10, 23, 14)

    @Test("From the countdown's start to the end, without the break")
    func breaksLeftOut() throws {
        let script = SessionScript(start: start, plan: FocusFixtures.plan(breakMinutes: 5))
        script.after(5, .shieldApplied)
        script.after(20 * 60, .breakStarted(seconds: 300))
        script.after(3 * 60, .breakEnded)
        script.after(27 * 60, .sessionEnded(.completed, verified: true))
        #expect(try #require(script.record).focusedSeconds == 47 * 60)
    }

    @Test("A break left to run out is its planned length, and an unlock doesn't shorten the time focused")
    func breakRunsOut() throws {
        let script = SessionScript(start: start, plan: FocusFixtures.plan(breakMinutes: 5))
        script.after(5, .shieldApplied)
        script.after(10 * 60, .breakStarted(seconds: 300))
        script.after(10 * 60, .overrideStarted(seconds: 60))
        script.after(60, .overrideEnded)
        script.after(29 * 60, .sessionEnded(.completed, verified: true))
        #expect(try #require(script.record).focusedSeconds == 45 * 60)
    }

    @Test("A session noticed hours late is focused only to its planned end; one ended early, to its end")
    func ends() throws {
        let late = SessionScript(start: start)
        late.after(5, .shieldApplied)
        late.after(3 * 3600, .sessionEnded(.completed, verified: false))
        #expect(try #require(late.record).focusedSeconds == 50 * 60)

        let early = SessionScript(start: start, plan: FocusFixtures.plan(kind: .plainTimer, selection: nil))
        early.after(12 * 60, .sessionEnded(.endedEarly, verified: false))
        #expect(try #require(early.record).focusedSeconds == 12 * 60)
    }

    @Test("A session whose end was never written stops at its last confirmed moment")
    func cutOff() throws {
        let script = SessionScript(start: start)
        script.after(5, .shieldApplied)
        script.after(18 * 60, .shieldVerified)
        #expect(try #require(script.record).focusedSeconds == 18 * 60)

        let plain = SessionScript(start: start, plan: FocusFixtures.plan(kind: .plainTimer, selection: nil))
        #expect(try #require(plain.record).focusedSeconds == 0)
    }
}

@Suite("Subjects")
struct SubjectListTests {
    private let study = UUID(uuidString: "00000000-0000-4000-8000-00000000F001")!
    private let quick = UUID(uuidString: "00000000-0000-4000-8000-00000000F002")!

    private func added(_ list: inout SubjectList, _ name: String) throws -> Subject {
        guard case .added(let subject) = list.add(name) else {
            Issue.record("\(name) wasn't added")
            throw CancellationError()
        }
        return subject
    }

    @Test("Names are trimmed, kept on one line and cut at 24 characters; a blank one is no name")
    func names() {
        #expect(Subject.normalizedName("  Biology \n") == "Biology")
        #expect(Subject.normalizedName("Further\n  pure   maths") == "Further pure maths")
        #expect(Subject.normalizedName(String(repeating: "a", count: 40))?.count == 24)
        #expect(Subject.normalizedName("  \n ") == nil)
    }

    @Test("Up to 8 subjects, in the order they were added")
    func limit() throws {
        var list = SubjectList()
        for index in 1...8 { _ = try added(&list, "Subject \(index)") }
        #expect(list.active.map(\.name) == (1...8).map { "Subject \($0)" })
        #expect(!list.canAdd)
        let ninth = list.add("One more")
        let blank = list.add("   ")
        #expect(ninth == .full)
        #expect(blank == .blank)
        #expect(list.active.count == 8)
    }

    @Test("Adding a name that is already there gives that subject back, whatever its capitals")
    func duplicates() throws {
        var list = SubjectList()
        let biology = try added(&list, "Biology")
        let again = list.add(" biology ")
        #expect(again == .existing(biology))
        #expect(list.active.count == 1)
    }

    @Test("A removed subject keeps its name for History, stops being offered, and frees its place")
    func removal() throws {
        var list = SubjectList()
        let biology = try added(&list, "Biology")
        _ = try added(&list, "Maths")
        list.markUsed(biology.id, with: study)
        list.remove(biology.id)
        #expect(list.active.map(\.name) == ["Maths"])
        #expect(list.name(for: biology.id) == "Biology")
        #expect(list.subject(id: biology.id)?.isRemoved == true)
        #expect(list.lastUsed(with: study) == nil)
    }

    @Test("Adding a removed subject's name brings it back with its id, so its past sessions join it again")
    func restore() throws {
        var list = SubjectList()
        let biology = try added(&list, "Biology")
        list.remove(biology.id)
        let again = try added(&list, "BIOLOGY")
        #expect(again.id == biology.id)
        #expect(again.name == "BIOLOGY")
        #expect(list.active.map(\.id) == [biology.id])
        #expect(list.subjects.count == 1)
    }

    @Test("Renaming changes the name everywhere; a blank name or another subject's name is refused")
    func rename() throws {
        var list = SubjectList()
        let biology = try added(&list, "Biology")
        _ = try added(&list, "Maths")
        let renamed = list.rename(biology.id, to: " Bio ")
        #expect(renamed)
        #expect(list.name(for: biology.id) == "Bio")
        let taken = list.rename(biology.id, to: "maths")
        let blank = list.rename(biology.id, to: " ")
        #expect(!taken && !blank)
        #expect(list.name(for: biology.id) == "Bio")
        let recased = list.rename(biology.id, to: "BIO")
        #expect(recased)
        #expect(list.name(for: biology.id) == "BIO")
    }

    @Test("Subjects can be reordered")
    func reorder() throws {
        var list = SubjectList()
        for name in ["A", "B", "C"] { _ = try added(&list, name) }
        list.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(list.active.map(\.name) == ["C", "A", "B"])
        list.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(list.active.map(\.name) == ["A", "B", "C"])
    }

    @Test("Each preset remembers the subject it was last used with, and no subject is remembered too")
    func lastUsed() throws {
        var list = SubjectList()
        let biology = try added(&list, "Biology")
        let maths = try added(&list, "Maths")
        #expect(list.lastUsed(with: study) == nil)
        list.markUsed(biology.id, with: study)
        list.markUsed(maths.id, with: quick)
        #expect(list.lastUsed(with: study) == biology.id)
        #expect(list.lastUsed(with: quick) == maths.id)
        list.markUsed(nil, with: study)
        #expect(list.lastUsed(with: study) == nil)
        // A subject the list doesn't hold is never remembered.
        list.markUsed(UUID(), with: quick)
        #expect(list.lastUsed(with: quick) == maths.id)
    }

    @Test("The file reads back as written, and a damaged subject is skipped without losing the rest")
    func coding() throws {
        var list = SubjectList()
        let biology = try added(&list, "Biology")
        let maths = try added(&list, "Maths")
        list.remove(maths.id)
        list.markUsed(biology.id, with: study)
        let data = try JSONEncoder().encode(list)
        #expect(try JSONDecoder().decode(SubjectList.self, from: data) == list)

        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var subjects = try #require(object["subjects"] as? [[String: Any]])
        subjects[1]["id"] = 7
        object["subjects"] = subjects
        let damaged = try JSONDecoder().decode(SubjectList.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(damaged.subjects.map(\.name) == ["Biology"])
        #expect(damaged.lastUsed(with: study) == biology.id)
    }
}

@Suite("Session titles with a subject")
struct SubjectTitleTests {
    @Test("The subject joins the preset; with an intention too, the subject stands in for the preset")
    func titles() {
        #expect(FocusCopy.sessionTitle(presetName: "Study", subject: nil, intention: nil) == "Study")
        #expect(FocusCopy.sessionTitle(presetName: "Study", subject: "Biology", intention: nil) == "Study · Biology")
        #expect(FocusCopy.sessionTitle(presetName: "Study", subject: nil, intention: "Chapter 4") == "Study · Chapter 4")
        #expect(FocusCopy.sessionTitle(presetName: "Study", subject: "Biology", intention: " Chapter 4 ") == "Biology · Chapter 4")
    }

    @Test("The Lock Screen names the subject beside the preset, but not during a break or for a plain timer's title")
    func liveActivity() {
        let start = at(2026, 10, 23, 14)
        let state = FocusActivityState(sessionID: UUID(), presetName: "Study", start: start, plannedEnd: start.addingTimeInterval(3000),
                                       isPlainTimer: false)
        let named = state.described(intention: "Chapter 4", subject: "Biology", tint: LeafColor(0xF2F5FA), leafID: nil)
        let lines = named.lines(locale: Locale(identifier: "en_GB"), calendar: utc)
        #expect(lines.title == "Study")
        #expect(lines.lockLine == "until 14:50 · Study · Biology")
        #expect(lines.expandedLine == "Study · Biology · Chapter 4")
        #expect(state.lines(locale: Locale(identifier: "en_GB"), calendar: utc).lockLine == "until 14:50 · Study")
    }
}
