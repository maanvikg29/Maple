#if DEBUG
import Foundation
import MapleCore

/// DEBUG only: the Core-owned launch arguments from docs/debug-launch-arguments.md, e.g.
/// `xcrun simctl launch booted com.maanvikgupta.maple -MapleDemoSpecies 23 -MapleDemoDays 41 -MapleDemoWaiting 1
/// -MapleDemoPhase morning`. Release builds never read them.
nonisolated public struct DemoLaunchOptions: Sendable, Equatable {
    /// `-MapleDemoSpecies 0…155`: a demo collection of that many species.
    public var species: Int?
    /// `-MapleDemoDays n`: tended days for the demo collection.
    public var days: Int?
    /// `-MapleDemoWaiting n`: earned leaves still waiting to be opened.
    public var waiting: Int?
    /// `-MapleDemoPhase morning|day|evening|windDown|night`: freezes the clock inside that phase today.
    public var phase: NowPhase?
    /// `-MapleDemoSeason spring|summer|autumn|winter`.
    public var season: Season?
    /// `-MapleDemoRarity YES`: preview rarity with consent on.
    public var rarity = false
    /// `-MapleDemoFresh YES`: an empty collection with no saved schedule, as on first run.
    public var fresh = false
    /// `-MapleDemoPermissions none|health|all`: granted permissions (demo collections default to `health`).
    public var permissions: GrantedPermissions?
    /// `-MapleDemoSchedule 00:30-08:30` (bedtime-wake, optionally `/60` wind-down minutes): the saved schedule,
    /// every night unless `weekendSchedule` is given too.
    public var schedule: SleepSchedule?
    /// `-MapleDemoWeekendSchedule 00:30-09:00/60`: the saved weekend schedule (same format as `schedule`).
    public var weekendSchedule: SleepSchedule?
    /// `-MapleDemoDay friday` (a weekday name) or `2026-10-09`: the day `phase` freezes the clock on, so a weekend
    /// night's evening can be shown on any day.
    public var day: String?

    public init() {}

    public init(arguments: [String]) {
        func value(_ key: String) -> String? {
            guard let index = arguments.firstIndex(of: "-\(key)"), arguments.indices.contains(index + 1) else { return nil }
            let value = arguments[index + 1]
            return value.hasPrefix("-") ? nil : value
        }
        func flag(_ key: String) -> Bool {
            guard let text = value(key)?.lowercased() else { return false }
            return ["yes", "true", "1"].contains(text)
        }
        func count(_ key: String, max upper: Int = .max) -> Int? {
            value(key).flatMap(Int.init).map { min(upper, max(0, $0)) }
        }
        species = count("MapleDemoSpecies", max: RewardCatalog.shared.assignments.count)
        days = count("MapleDemoDays")
        waiting = count("MapleDemoWaiting")
        phase = value("MapleDemoPhase").flatMap { text in NowPhase.allCases.first { $0.rawValue.lowercased() == text.lowercased() } }
        season = value("MapleDemoSeason").flatMap { text in Season.allCases.first { $0.rawValue == text.lowercased() } }
        rarity = flag("MapleDemoRarity")
        fresh = flag("MapleDemoFresh")
        permissions = switch value("MapleDemoPermissions")?.lowercased() {
        case "none": []
        case "health": [.appleHealth, .sleepTracker]
        case "all": [.appleHealth, .sleepTracker, .screenTime]
        default: nil
        }
        schedule = value("MapleDemoSchedule").flatMap(Self.schedule(from:))
        weekendSchedule = value("MapleDemoWeekendSchedule").flatMap(Self.schedule(from:))
        day = value("MapleDemoDay")
    }

    /// The saved weekly schedule these arguments make from `saved` (the demo's own, or the member's): the
    /// `-MapleDemoSchedule` every night, and the `-MapleDemoWeekendSchedule` on weekend nights. Nil when neither
    /// is given.
    public func weekly(replacing saved: WeeklySleepSchedule?) -> WeeklySleepSchedule? {
        guard schedule != nil || weekendSchedule != nil else { return nil }
        var weekly = schedule.map(WeeklySleepSchedule.everyNight) ?? saved ?? .standard
        if let weekendSchedule { weekly.weekend = weekendSchedule }
        return weekly
    }

    /// The day `-MapleDemoDay` names, on or after `now`'s day: the next such weekday (today if it is one), or a
    /// `yyyy-MM-dd` date. Nil without the argument or when it can't be read.
    public func demoDay(from now: Date, calendar: Calendar) -> Date? {
        guard let day = day?.lowercased() else { return nil }
        let parts = day.split(separator: "-").compactMap { Int($0) }
        if parts.count == 3 {
            return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
        }
        var english = Calendar(identifier: .gregorian)
        english.locale = Locale(identifier: "en_US_POSIX")
        guard let index = english.weekdaySymbols.firstIndex(where: { $0.lowercased() == day }) else { return nil }
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now) ?? now
        if calendar.component(.weekday, from: noon) == index + 1 { return noon }
        return calendar.nextDate(after: noon, matching: DateComponents(hour: 12, weekday: index + 1), matchingPolicy: .nextTime)
    }

    /// "00:30-08:30" or "00:30-08:30/60"; nil when malformed. Wind-down defaults to the standard 45 minutes.
    static func schedule(from text: String) -> SleepSchedule? {
        let parts = text.split(separator: "/")
        let times = parts.first?.split(separator: "-").compactMap { clock -> ClockTime? in
            let fields = clock.split(separator: ":").compactMap { Int($0) }
            guard fields.count == 2, (0..<24).contains(fields[0]), (0..<60).contains(fields[1]) else { return nil }
            return ClockTime(hour: fields[0], minute: fields[1])
        } ?? []
        guard times.count == 2, parts.count <= 2 else { return nil }
        let windDown = parts.count == 2 ? Int(parts[1]) : SleepSchedule.standard.windDownMinutes
        guard let windDown, (0...180).contains(windDown) else { return nil }
        return SleepSchedule(bedtime: times[0], wake: times[1], windDownMinutes: windDown)
    }

    /// The arguments this process was launched with.
    public static var current: DemoLaunchOptions {
        DemoLaunchOptions(arguments: ProcessInfo.processInfo.arguments)
    }

    /// A deterministic demo collection replaces the member's own.
    public var usesDemoCollection: Bool {
        !fresh && (species != nil || days != nil || waiting != nil)
    }

    /// Any Core demo argument is set. Demo launches keep every store in memory, so the real files are never written.
    public var isActive: Bool {
        self != DemoLaunchOptions()
    }
}
#endif
