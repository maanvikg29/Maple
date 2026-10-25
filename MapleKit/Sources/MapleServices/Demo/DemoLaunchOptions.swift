#if DEBUG
import Foundation
import MapleCore

/// DEBUG only: the Core-owned launch arguments from docs/debug-launch-arguments.md, e.g.
/// `xcrun simctl launch booted com.maanvikgupta.maple -MapleDemoSpecies 23 -MapleDemoDays 41 -MapleDemoWaiting 1
/// -MapleDemoPhase morning`. Release builds never read them.
///
/// Every Focus argument (F1 design §8.2) is a field too, so any of them keeps the launch in demo stores. `-MapleDemoTab`,
/// `-MapleDemoNotify`, `-MapleDemoReduceMotion` and the app's own `-MapleDemoPresent` values stay with the app.
nonisolated public struct DemoLaunchOptions: Sendable, Equatable {
    /// `-MapleDemoSpecies 0…155`: a demo collection of that many species.
    public var species: Int?
    /// `-MapleDemoDays n`: tended days for the demo collection.
    public var days: Int?
    /// `-MapleDemoWaiting n`: earned leaves still waiting to be opened.
    public var waiting: Int?
    /// `-MapleDemoPhase morning|day|evening|windDown|night`: freezes the clock inside that phase today (a Focus demo's
    /// clock starts there and keeps running).
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
    /// -MapleDemoSandbox YES: the sandbox container (F1 design §7.6).
    public var sandbox = false
    /// -MapleDemoSessionSeconds <n>: sandbox sessions last n seconds, in real time.
    public var sessionSeconds: Int?

    // MARK: Focus (F1 design §8.2)

    /// `-MapleDemoShip f1`: ships F1 in the demo stores (exactly `[.m1, .f1]`, never everything), so F1b's screens can
    /// be checked before `ShippedFeatures.current` flips. `m1` ships M1 alone.
    public var ship: ShippedFeatures?
    /// `-MapleDemoFocus idle|noSet|smallSet|expired|running|dimmed|break|minimised|ended|endedAway|endEarly|emergency|first`.
    public var focus: FocusDemo.State?
    /// `-MapleDemoFocusAt <min>`: minutes into the session, 0…180.
    public var focusAt: Int?
    /// `-MapleDemoStrictness gentle|steady|locked`: the selected preset's strictness.
    public var strictness: Strictness?
    /// `-MapleDemoScreenTime approved|notDetermined|declined|restricted|noPasscode|unavailable|revoked|plain|failStart`.
    public var screenTime: FocusDemo.ScreenTime?
    /// `-MapleDemoReceipt clean|unlocked|early|plain|revoked|bedtime|capped|leaf|leafNight|notQualifying`.
    public var receipt: FocusDemo.Receipt?
    /// `-MapleDemoSaved typical|capped|empty`: today's earlier sessions (`empty` also has no streak).
    public var saved: FocusDemo.Saved?
    /// `-MapleDemoLiveActivity running|break|plain|ended`.
    public var liveActivity: FocusDemo.LiveActivity?
    /// `-MapleDemoPresent blocking|preset|saved|streak|intention`: a Focus sheet. Nil for the app's own presentations
    /// (`reveal`, `profile`, `winddown`, `onboarding`), which the app reads from the same key.
    public var focusSheet: FocusDemo.Sheet?
    /// `-MapleDemoPreset study|quick|deep|read`: the selected preset.
    public var preset: FocusVerb?
    /// `-MapleDemoIntention <text>`: the session's intention; an empty value means none.
    public var intention: String?
    /// `-MapleDemoHoldAt 0…1`: a hold frozen at that progress.
    public var holdAt: Double?
    /// `-MapleDemoEndCountdown <s>`: Steady's end countdown frozen at that many seconds, 0…15.
    public var endCountdown: Int?
    /// `-MapleDemoFinishAt <s>`: the receipt's finish frozen that many seconds in.
    public var finishAt: Double?

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
        func choice<Choice: RawRepresentable & CaseIterable>(_ key: String) -> Choice? where Choice.RawValue == String {
            value(key).flatMap { text in Choice.allCases.first { $0.rawValue.lowercased() == text.lowercased() } }
        }
        func number(_ key: String) -> Double? {
            value(key).flatMap { Double($0) }.flatMap { $0.isFinite ? $0 : nil }
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
        sandbox = flag("MapleDemoSandbox")
        sessionSeconds = count("MapleDemoSessionSeconds").flatMap { $0 > 0 ? $0 : nil }

        ship = switch value("MapleDemoShip")?.lowercased() {
        case "f1": ShippedFeatures(releases: [.m1, .f1])
        case "m1": ShippedFeatures(releases: [.m1])
        default: nil
        }
        focus = choice("MapleDemoFocus")
        focusAt = count("MapleDemoFocusAt", max: DialLayout.maximumMinutes)
        strictness = choice("MapleDemoStrictness")
        screenTime = choice("MapleDemoScreenTime")
        receipt = choice("MapleDemoReceipt")
        saved = choice("MapleDemoSaved")
        liveActivity = choice("MapleDemoLiveActivity")
        focusSheet = choice("MapleDemoPresent")
        preset = switch value("MapleDemoPreset")?.lowercased() {
        case "study": .study
        case "quick": .quick
        case "deep": .deep
        case "read": .reading
        default: nil
        }
        intention = value("MapleDemoIntention")
        holdAt = number("MapleDemoHoldAt").map { min(1, max(0, $0)) }
        endCountdown = count("MapleDemoEndCountdown", max: 15)
        finishAt = number("MapleDemoFinishAt").map { max(0, $0) }
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

    /// Any Focus argument is set (F1b ruling P7): the launch runs Focus in its demo stores, on a clock that keeps ticking.
    public var hasFocusArguments: Bool {
        ship != nil || focus != nil || focusAt != nil || strictness != nil || screenTime != nil || receipt != nil
            || saved != nil || liveActivity != nil || focusSheet != nil || preset != nil || intention != nil
            || holdAt != nil || endCountdown != nil || finishAt != nil
    }

    /// A deterministic demo collection replaces the member's own: asked for, or a Focus demo (whose scenarios need a
    /// planted maple), unless the launch is a fresh first run.
    public var usesDemoCollection: Bool {
        !fresh && (species != nil || days != nil || waiting != nil || hasFocusArguments)
    }

    /// Any Core demo argument is set. Demo launches keep every store in memory, so the real files are never written.
    public var isActive: Bool {
        self != DemoLaunchOptions()
    }
}
#endif
