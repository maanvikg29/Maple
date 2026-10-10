import Foundation
import MapleCore
import Testing
@testable import MapleDesign

/// Wind-down mode's rules (spec §8.1, §3.4): when a start counts, how long "Return to wind-down" lasts, and which
/// Goodnight the morning reads.
@Suite("Rest wind-down session")
struct RestWindDownTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    /// 10 October 2026 (day 0) and the following days, in UTC. Standard schedule: evening 20:15, wind-down 22:15,
    /// bed 23:00, wake 07:00.
    private func at(day: Int = 0, _ hour: Int, _ minute: Int = 0) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 10 + day, hour: hour, minute: minute)))
    }

    @Test("Wind-down is offered in the evening and wind-down phases only")
    func offered() {
        #expect(WindDownSession.offersWindDown(in: .evening))
        #expect(WindDownSession.offersWindDown(in: .windDown))
        #expect(!WindDownSession.offersWindDown(in: .morning))
        #expect(!WindDownSession.offersWindDown(in: .day))
        #expect(!WindDownSession.offersWindDown(in: .night))
    }

    @Test("A start counts only when wind-down is offered, and only once while it is on")
    func startsCount() throws {
        var session = WindDownSession()
        let inTheDay = session.start(at: try at(14), schedule: .standard, calendar: calendar)
        let atNight = session.start(at: try at(23, 30), schedule: .standard, calendar: calendar)
        #expect(!inTheDay && !atNight)
        #expect(session.startedAt == nil)

        let nine = try at(21)
        let inTheEvening = session.start(at: nine, schedule: .standard, calendar: calendar)
        #expect(inTheEvening)
        #expect(session.startedAt == nine)
        // Opening it again the same evening keeps the first start.
        let again = session.start(at: try at(22, 30), schedule: .standard, calendar: calendar)
        #expect(!again)
        #expect(session.startedAt == nine)
    }

    @Test("It stays on until Goodnight or bedtime, and never carries into the next evening")
    func activeWindow() throws {
        var session = WindDownSession()
        session.start(at: try at(21), schedule: .standard, calendar: calendar)
        #expect(session.isActive(at: try at(21, 5), schedule: .standard, calendar: calendar))
        #expect(session.isActive(at: try at(22, 50), schedule: .standard, calendar: calendar))
        #expect(!session.isActive(at: try at(23, 1), schedule: .standard, calendar: calendar))
        #expect(!session.isActive(at: try at(day: 1, 21), schedule: .standard, calendar: calendar))
        // Before the start it was not on yet.
        #expect(!session.isActive(at: try at(20, 30), schedule: .standard, calendar: calendar))

        session.sayGoodnight(at: try at(22, 40))
        #expect(!session.isActive(at: try at(22, 45), schedule: .standard, calendar: calendar))
        // The next evening it can start again.
        let nextEvening = session.start(at: try at(day: 1, 22, 20), schedule: .standard, calendar: calendar)
        #expect(nextEvening)
        #expect(session.isActive(at: try at(day: 1, 22, 30), schedule: .standard, calendar: calendar))
    }

    @Test("A wind-down that runs past midnight stays on until a 00:30 bedtime")
    func pastMidnight() throws {
        let late = SleepSchedule(bedtime: ClockTime(hour: 0, minute: 30), wake: ClockTime(hour: 8, minute: 30), windDownMinutes: 60)
        var session = WindDownSession()
        let started = session.start(at: try at(23, 40), schedule: .everyNight(late), calendar: calendar)
        #expect(started)
        #expect(session.isActive(at: try at(day: 1, 0, 20), schedule: .everyNight(late), calendar: calendar))
        #expect(!session.isActive(at: try at(day: 1, 0, 31), schedule: .everyNight(late), calendar: calendar))
    }

    @Test("The morning reads last night's Goodnight, not an older one")
    func morningGoodnight() throws {
        var session = WindDownSession()
        #expect(session.goodnight(forMorningOf: try at(day: 1, 7)) == nil)
        let goodnight = try at(23, 4)
        session.sayGoodnight(at: goodnight)
        #expect(session.goodnight(forMorningOf: try at(day: 1, 7)) == goodnight)
        #expect(session.goodnight(forMorningOf: try at(day: 2, 7)) == nil)
        #expect(session.goodnight(forMorningOf: try at(22)) == nil)
    }

    @Test("The session survives a JSON round trip")
    func codable() throws {
        let session = WindDownSession(startedAt: try at(21), goodnightAt: try at(22, 40))
        let data = try JSONEncoder().encode(session)
        #expect(try JSONDecoder().decode(WindDownSession.self, from: data) == session)
    }
}
