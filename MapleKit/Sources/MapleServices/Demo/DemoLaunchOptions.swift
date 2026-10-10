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
    /// `-MapleDemoSchedule 00:30-08:30` (bedtime-wake, optionally `/60` wind-down minutes): the saved schedule.
    public var schedule: SleepSchedule?

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
