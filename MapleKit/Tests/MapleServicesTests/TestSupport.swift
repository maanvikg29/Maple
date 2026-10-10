import Foundation
@testable import MapleCore
@testable import MapleServices

/// A fixed Gregorian calendar in UTC, so tests never depend on the machine's time zone.
let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.locale = Locale(identifier: "en_GB")
    return calendar
}()

func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

/// A fresh, empty folder for one test's files.
func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("MapleServicesTests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// The contents of a folder, for "nothing was written" checks.
func files(in directory: URL) -> [String] {
    (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
}

let testContext = CollectionContext(schedule: .standard, calendar: utc, hemisphere: .northern)

/// A share provider that returns what the test tells it to and counts its calls.
actor StubShareProvider: LeafShareProvider {
    nonisolated let identifier: String
    private var result: Result<LeafShareCounts, any Error>
    private(set) var calls = 0

    init(identifier: String = "stub", _ result: Result<LeafShareCounts, any Error>) {
        self.identifier = identifier
        self.result = result
    }

    func set(_ result: Result<LeafShareCounts, any Error>) {
        self.result = result
    }

    func fetchCounts() async throws -> LeafShareCounts {
        calls += 1
        return try result.get()
    }
}

struct Offline: Error {}

func counts(members: Int?, _ counts: [String: Int]) -> LeafShareCounts {
    LeafShareCounts(catalogueVersion: LeafShareCounts.catalogueVersion, members: members, counts: counts, weekStart: at(2026, 9, 28))
}
