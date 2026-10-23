import Foundation
import Testing
@testable import MapleCore

@Suite("Focus book")
struct FocusBookTests {
    private let oct23 = LocalDay(year: 2026, month: 10, day: 23)

    private func credit(_ id: UUID, seconds: Int, finished: Bool = false, provenAt: Date = at(2026, 10, 23, 15),
                        day: LocalDay = LocalDay(year: 2026, month: 10, day: 23)) -> SessionCredit {
        SessionCredit(id: id, day: day, zone: "UTC", seconds: seconds, awakeSeconds: seconds, finished: finished, provenAt: provenAt,
                      endedAt: provenAt, dayEnd: at(2026, 10, 23, 23), stretches: [])
    }

    @Test("Each session keeps its highest credit, so a later loss doesn't stall a later session")
    func highWater() {
        var book = FocusBook()
        let a = UUID(), b = UUID()
        book.record([credit(a, seconds: 3000, finished: true)])
        book.record([credit(a, seconds: 0), credit(b, seconds: 600)])
        #expect(book.days.count == 1)
        #expect(book.days[0].seconds == 3600)
        #expect(book.days[0].finished == 1)
        #expect(book.totalSeconds == 3600)
    }

    @Test("A day's total is capped at 6 hours and 3 finished sessions")
    func caps() {
        var book = FocusBook()
        book.record((0..<5).map { _ in credit(UUID(), seconds: 3 * 3600, finished: true) })
        #expect(book.days[0].seconds == 21_600)
        #expect(book.days[0].finished == 3)
    }

    @Test("Days freeze 3 days after their end, keep only their totals, and then never change")
    func freezing() {
        var book = FocusBook()
        let a = UUID()
        book.record([credit(a, seconds: 3000, finished: true)])
        let early = book.freeze(at: at(2026, 10, 26, 22, 59))
        #expect(!early)
        let onTime = book.freeze(at: at(2026, 10, 26, 23))
        #expect(onTime)
        #expect(book.days[0].frozen)
        #expect(book.days[0].sessions.isEmpty)
        #expect(book.days[0].seconds == 3000)
        let changed = book.record([credit(UUID(), seconds: 600)])
        #expect(!changed)
        #expect(book.totalSeconds == 3000)
    }

    @Test("Proof that arrives late keeps its day open for 3 days from then")
    func lateProof() {
        var book = FocusBook()
        book.record([credit(UUID(), seconds: 1800, provenAt: at(2026, 10, 28, 9))])
        let early = book.freeze(at: at(2026, 10, 30, 9))
        #expect(!early)
        let onTime = book.freeze(at: at(2026, 10, 31, 9))
        #expect(onTime)
    }

    @Test("Totals include the baseline")
    func baseline() {
        var book = FocusBook(baseline: FocusTotals(seconds: 36_000, finished: 12))
        book.record([credit(UUID(), seconds: 1800, finished: true)])
        #expect(book.totalSeconds == 37_800)
        #expect(book.totalFinished == 13)
    }

    @Test("Focus days are the days with a finished session")
    func focusDays() {
        var book = FocusBook()
        book.record([credit(UUID(), seconds: 1800, finished: true)])
        book.record([credit(UUID(), seconds: 900, day: LocalDay(year: 2026, month: 10, day: 24))])
        #expect(book.focusDays.map(\.day) == [oct23])
        #expect(book.seconds(on: LocalDay(year: 2026, month: 10, day: 24)) == 900)
    }

    @Test("Decoding is tolerant: a damaged day is skipped, unknown keys are ignored")
    func tolerant() throws {
        var book = FocusBook(bestRun: 4, startedAt: at(2026, 10, 1))
        book.record([credit(UUID(), seconds: 1800, finished: true)])
        var json = try #require(String(data: try JSONEncoder().encode(book), encoding: .utf8))
        json = json.replacingOccurrences(of: "\"days\":[", with: "\"future\":1,\"days\":[{\"day\":\"bad\"},")
        let decoded = try JSONDecoder().decode(FocusBook.self, from: Data(json.utf8))
        #expect(decoded == book)
        let empty = try JSONDecoder().decode(FocusBook.self, from: Data("{}".utf8))
        #expect(empty == FocusBook())
    }

    /// `book` as JSON with `edit` applied to its top-level object, as a damaged or older file would look.
    private func damaged(_ book: FocusBook, _ edit: (inout [String: Any]) -> Void) throws -> Data {
        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(book)) as? [String: Any])
        edit(&object)
        return try JSONSerialization.data(withJSONObject: object)
    }

    /// Applies `edit` to the first day's object.
    private func editingFirstDay(_ edit: @escaping (inout [String: Any]) -> Void) -> (inout [String: Any]) -> Void {
        { object in
            var days = object["days"] as? [[String: Any]] ?? []
            edit(&days[0])
            object["days"] = days
        }
    }

    @Test("A day with an unreadable or missing field keeps its credit and takes defaults")
    func damagedDayKeepsCredit() throws {
        var book = FocusBook(baseline: FocusTotals(seconds: 36_000, finished: 12), startedAt: at(2026, 10, 1))
        book.record([credit(UUID(), seconds: 1800, finished: true)])
        let data = try damaged(book, editingFirstDay { day in
            day["rulesVersion"] = "one"
            day.removeValue(forKey: "frozen")
        })
        let decoded = try JSONDecoder().decode(FocusBook.self, from: data)
        let day = try #require(decoded.days.first)
        #expect(decoded.days.count == 1)
        #expect(day.seconds == 1800)
        #expect(day.finished == 1)
        #expect(day.rulesVersion == FocusRules.version)
        #expect(!day.frozen)
        #expect(day.sessions == book.days[0].sessions)
        #expect(decoded.totalSeconds == 37_800)
        #expect(decoded.startedAt == at(2026, 10, 1))
    }

    @Test("A day whose credit is unreadable is skipped, but one with only its sessions damaged is not")
    func damagedSessions() throws {
        var book = FocusBook()
        let a = UUID(), b = UUID()
        book.record([credit(a, seconds: 1800, finished: true), credit(b, seconds: 600)])
        let unreadable = try damaged(book, editingFirstDay { day in
            var sessions = day["sessions"] as? [String: Any] ?? [:]
            sessions[a.uuidString.lowercased()] = ["seconds": "lots"]
            day["sessions"] = sessions
        })
        let decoded = try JSONDecoder().decode(FocusBook.self, from: unreadable)
        let day = try #require(decoded.days.first)
        #expect(day.seconds == 2400)
        #expect(day.finished == 1)
        #expect(day.sessions.count == 1)
        #expect(day.sessions[b.uuidString.lowercased()] == book.days[0].sessions[b.uuidString.lowercased()])

        let noSeconds = try damaged(book, editingFirstDay { $0.removeValue(forKey: "seconds") })
        #expect(try JSONDecoder().decode(FocusBook.self, from: noSeconds).days.isEmpty)
    }

    @Test("A day without its times still freezes, at once")
    func missingTimes() throws {
        var book = FocusBook()
        book.record([credit(UUID(), seconds: 1800, finished: true)])
        let data = try damaged(book, editingFirstDay { day in
            day.removeValue(forKey: "dayEnd")
            day.removeValue(forKey: "firstCountedAt")
        })
        var decoded = try JSONDecoder().decode(FocusBook.self, from: data)
        #expect(decoded.days.count == 1)
        let froze = decoded.freeze(at: at(2026, 10, 23, 15))
        #expect(froze)
        #expect(decoded.totalSeconds == 1800)
    }

    @Test("An unreadable baseline is zeroed and the book starts over, so the counters can rebaseline it")
    func damagedBaseline() throws {
        var book = FocusBook(baseline: FocusTotals(seconds: 36_000, finished: 12), startedAt: at(2026, 10, 1))
        book.record([credit(UUID(), seconds: 1800, finished: true)])
        let data = try damaged(book) { object in
            object["baseline"] = ["seconds": "many", "finished": 12]
        }
        let decoded = try JSONDecoder().decode(FocusBook.self, from: data)
        #expect(decoded.baseline == .zero)
        #expect(decoded.startedAt == nil)
        #expect(decoded.days == book.days)

        let missing = try damaged(book) { $0.removeValue(forKey: "baseline") }
        let withoutBaseline = try JSONDecoder().decode(FocusBook.self, from: missing)
        #expect(withoutBaseline.baseline == .zero)
        #expect(withoutBaseline.startedAt == at(2026, 10, 1))
    }
}
