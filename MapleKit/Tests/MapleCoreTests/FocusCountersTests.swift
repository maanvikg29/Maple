import Foundation
import Testing
@testable import MapleCore

@Suite("Focus counters")
struct FocusCountersTests {
    private let context = CollectionContext(schedule: .standard, permissions: [.appleHealth], calendar: utc, hemisphere: .northern)

    private func planted() -> CollectionSnapshot {
        var snapshot = CollectionSnapshot.empty(profileID: UUID(), createdAt: at(2026, 10, 1))
        snapshot.raise(.firstLeaf, to: 1, at: at(2026, 10, 1, 21), calendar: utc)
        snapshot.runEngine(at: at(2026, 10, 1, 21), context: context)
        return snapshot
    }

    private func credit(seconds: Int, finished: Bool = true, provenAt: Date, day: LocalDay = LocalDay(year: 2026, month: 10, day: 23)) -> SessionCredit {
        SessionCredit(id: UUID(), day: day, zone: "UTC", seconds: seconds, awakeSeconds: seconds, finished: finished,
                      provenAt: provenAt, endedAt: provenAt, dayEnd: at(2026, 10, 23, 23), stretches: [])
    }

    @Test("Marks add up session by session, in the order credit was proven, after the baseline")
    func marks() {
        var book = FocusBook(baseline: FocusTotals(seconds: 7200, finished: 2), startedAt: at(2026, 10, 1))
        book.record([credit(seconds: 1800, provenAt: at(2026, 10, 23, 15)), credit(seconds: 3600, provenAt: at(2026, 10, 23, 10))])
        let marks = FocusCounters.marks(book: book)
        #expect(marks.map(\.instant) == [at(2026, 10, 23, 10), at(2026, 10, 23, 15)])
        #expect(marks.map(\.hours) == [3, 3.5])
        #expect(marks.map(\.sessions) == [3, 4])
    }

    @Test("Marks respect the daily cap")
    func cappedMarks() {
        var book = FocusBook()
        book.record((0..<4).map { credit(seconds: 2 * 3600, provenAt: at(2026, 10, 23, 9 + 2 * $0)) })
        #expect(FocusCounters.marks(book: book).map(\.hours) == [2, 4, 6, 6])
        #expect(FocusCounters.marks(book: book).map(\.sessions) == [1, 2, 3, 3])
    }

    @Test("A leaf is dated when its credit was proven, not when the app caught up")
    func dated() throws {
        var snapshot = planted()
        let added = snapshot.applyFocus([credit(seconds: 3600, provenAt: at(2026, 10, 23, 10, 0, 5))], at: at(2026, 10, 23, 21, 30), context: context)
        let hours = try #require(added.first { $0.speciesID == species(.hoursSaved, rung: 0) })
        #expect(hours.date == at(2026, 10, 23, 10, 0, 5))
        // Applied in the evening, earned in the day: it isn't held (F1-12).
        #expect(snapshot.held(at: at(2026, 10, 23, 21, 30), context: context).isEmpty)
        #expect(snapshot.counters[.hoursSaved] == 1)
        #expect(snapshot.counters[.sessionsFinished] == 1)
        #expect(snapshot.focus.startedAt == at(2026, 10, 23, 21, 30))
    }

    @Test("Applying the same credit again changes nothing")
    func idempotent() {
        var snapshot = planted()
        let credits = [credit(seconds: 3000, provenAt: at(2026, 10, 23, 14, 50))]
        snapshot.applyFocus(credits, at: at(2026, 10, 23, 15), context: context)
        let before = snapshot
        #expect(snapshot.applyFocus(credits, at: at(2026, 10, 23, 15, 5), context: context).isEmpty)
        #expect(snapshot == before)
    }

    @Test("A book an older build dropped is rebuilt from the counters, and new credit adds on top")
    func droppedBook() {
        var snapshot = planted()
        snapshot.counters[.hoursSaved] = 10
        snapshot.counters[.sessionsFinished] = 4
        snapshot.counters[.focusStreak] = 6
        let old = credit(seconds: 3600, provenAt: at(2026, 10, 22, 10), day: LocalDay(year: 2026, month: 10, day: 22))
        snapshot.applyFocus([old], at: at(2026, 10, 23, 9), context: context)
        #expect(snapshot.focus.baseline == FocusTotals(seconds: 9 * 3600, finished: 3))
        #expect(snapshot.focus.bestRun == 6)
        #expect(snapshot.counters[.hoursSaved] == 10)
        snapshot.applyFocus([old, credit(seconds: 1800, provenAt: at(2026, 10, 23, 11))], at: at(2026, 10, 23, 11, 5), context: context)
        #expect(snapshot.counters[.hoursSaved] == 10.5)
        #expect(snapshot.counters[.sessionsFinished] == 5)
    }

    @Test("The best run is a high-water mark; the current run follows the misses")
    func runs() {
        var snapshot = planted()
        let days = [19, 20, 21].map { LocalDay(year: 2026, month: 10, day: $0) }
        snapshot.applyFocus(days.map { credit(seconds: 1800, provenAt: at(2026, 10, $0.day, 12), day: $0) }, at: at(2026, 10, 21, 13), context: context)
        #expect(snapshot.counters[.focusStreak] == 3)
        #expect(snapshot.currentRun(at: at(2026, 10, 23, 12), context: context) == 3)
        // 22 and 23 October fit as rest days while nothing follows them; a third miss doesn't.
        #expect(snapshot.currentRun(at: at(2026, 10, 24, 12), context: context) == 3)
        #expect(snapshot.currentRun(at: at(2026, 10, 25, 12), context: context) == 0)
        snapshot.applyFocus([], at: at(2026, 10, 30, 12), context: context)
        #expect(snapshot.focus.bestRun == 3)
        #expect(snapshot.counters[.focusStreak] == 3)
    }

    @Test("Nothing is recorded before the maple is planted")
    func unplanted() {
        var snapshot = CollectionSnapshot.empty(profileID: UUID(), createdAt: at(2026, 10, 1))
        #expect(snapshot.applyFocus([credit(seconds: 3600, provenAt: at(2026, 10, 23, 10))], at: at(2026, 10, 23, 11), context: context).isEmpty)
        #expect(snapshot.focus == FocusBook())
    }

    @Test("Version 2: the book is saved; a version 1 file opens and saves as version 2")
    func versionTwo() throws {
        var snapshot = planted()
        snapshot.applyFocus([credit(seconds: 3600, provenAt: at(2026, 10, 23, 10))], at: at(2026, 10, 23, 11), context: context)
        let data = try JSONEncoder().encode(snapshot)
        #expect(try JSONDecoder().decode(CollectionSnapshot.self, from: data) == snapshot)

        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["version"] = 1
        object["focus"] = nil
        let old = try JSONDecoder().decode(CollectionSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(old.version == 1)
        #expect(old.focus == FocusBook())
        #expect(!old.isFromNewerBuild)
        let resaved = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        #expect(resaved["version"] as? Int == 2)
    }

    @Test("Decoding is field by field: a damaged field takes its default, and a newer file says so")
    func tolerant() throws {
        let data = try JSONEncoder().encode(planted())
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["history"] = "damaged"
        object["focus"] = ["days": "damaged", "bestRun": 4]
        object["version"] = 3
        object["somethingNew"] = true
        let decoded = try JSONDecoder().decode(CollectionSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.history.isEmpty)
        #expect(decoded.focus.bestRun == 4)
        #expect(decoded.hasPlantedMaple)
        #expect(decoded.isFromNewerBuild)
    }
}
