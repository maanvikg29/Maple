import Foundation

/// Every behaviour category in `rewards.json`. Decoding fails loudly if the table gains one this list doesn't know.
public enum RewardCategoryID: String, Codable, Sendable, CaseIterable {
    case firstSteps = "first_steps"
    case nightsTracked = "nights_tracked"
    case onTimeBedtimes = "on_time_bedtimes"
    case bedtimeRun = "bedtime_run"
    case steadyWeeks = "steady_weeks"
    case seasonsInRhythm = "seasons_in_rhythm"
    case steadyMornings = "steady_mornings"
    case fullNights = "full_nights"
    case focusHours = "focus_hours"
    case focusDays = "focus_days"
    case focusWeeks = "focus_weeks"
    case soundWindDowns = "sound_winddowns"
    case scrollFreeWindDowns = "scroll_free_winddowns"
    case phoneFreeMornings = "phone_free_mornings"
    case bedtimeShieldKept = "bedtime_shield_kept"
    case reflectionWeeks = "reflection_weeks"
    case caffeineCurfew = "caffeine_curfew"
    case windDownRituals = "wind_down_rituals"
    case communityChallenges = "community_challenges"
}

/// What a category needs from the system before its leaves can be earned.
public enum RewardRequirement: Sendable, Equatable {
    case none
    case appleHealth
    /// Asleep-stage data from an Apple Watch or a sleep tracker (iPhone in-bed data isn't enough).
    case sleepTracker
    case screenTime
}

/// When in the day a category's behaviour happens; Home prefers leaves that fit the current phase.
public enum RewardTimeOfDay: Sendable, Equatable {
    case morning, day, night
}

/// The action a leaf's detail screen can offer to make progress.
public enum RewardAction: Sendable, Equatable {
    case startWindDown, startFocus, sleepSounds, checkIn
}

/// The app release that ships a category. Categories from unshipped releases are "Not earnable yet".
public enum RewardRelease: Int, Sendable, Comparable, CaseIterable {
    case m1 = 1, m2, m3, m4, m5, m6, m7, m8, m9

    public static func < (lhs: RewardRelease, rhs: RewardRelease) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Copy and behaviour for one category, in the voice of the design spec (§5.1).
/// Rule text per leaf comes from `RewardAssignment.unlockText`; these cover the shared lines.
public struct RewardCategoryInfo: Sendable {
    public let id: RewardCategoryID
    /// Canonical position (Herbarium sections, tie-breaks).
    public let order: Int
    public let requirement: RewardRequirement
    public let timeOfDay: RewardTimeOfDay
    public let action: RewardAction?
    public let release: RewardRelease
    /// Units per day for a committed member; used to estimate time-to-leaf before there's personal history.
    public let designPace: Double
    /// One-line, plain-language definition shown under section headers and in leaf detail.
    public let definition: String
    private let short: @Sendable (Int) -> String
    private let earned: @Sendable (Int) -> String

    /// Tile-sized rule, e.g. "14 on time".
    public func shortRule(_ threshold: Double) -> String { short(Int(threshold.rounded())) }
    /// The line under an earned leaf, e.g. "For 14 on-time bedtimes".
    public func earnedLine(_ threshold: Double) -> String { earned(Int(threshold.rounded())) }

    public init(_ id: RewardCategoryID) {
        switch id {
        case .firstSteps:
            self.init(id, order: 0, requirement: .none, timeOfDay: .night, action: nil, release: .m1, designPace: 1,
                      definition: "Set your bedtime and wake time in Maple.",
                      short: { _ in "Setup" }, earned: { _ in "For setting your sleep schedule" })
            return
        case .nightsTracked:
            self.init(id, order: 1, requirement: .none, timeOfDay: .night, action: nil, release: .m1, designPace: 0.9,
                      definition: "A night counts when you tap Goodnight in wind-down mode.",
                      short: { "\($0) \(plural($0, "night"))" },
                      earned: { $0 == 1 ? "For your first tracked night" : "For \($0) tracked nights" })
            return
        case .onTimeBedtimes:
            self.init(id, order: 2, requirement: .none, timeOfDay: .night, action: .startWindDown, release: .m1, designPace: 0.7,
                      definition: "Goodnight no later than 30 minutes after your bedtime.",
                      short: { "\($0) on time" },
                      earned: { $0 == 1 ? "For your first on-time bedtime" : "For \($0) on-time bedtimes" })
            return
        case .bedtimeRun:
            self.init(id, order: 3, requirement: .none, timeOfDay: .night, action: .startWindDown, release: .m1, designPace: 0.7,
                      definition: "Your run continues while 5 of every 7 nights are on time.",
                      short: { "\($0)-night run" }, earned: { "For a \($0)-night run" })
            return
        case .steadyWeeks:
            self.init(id, order: 4, requirement: .none, timeOfDay: .night, action: nil, release: .m1, designPace: 0.1,
                      definition: "A steady week has 5 or more on-time nights.",
                      short: { "\($0) \(plural($0, "week"))" },
                      earned: { $0 == 1 ? "For your first steady week" : "For \($0) steady weeks" })
            return
        case .seasonsInRhythm:
            self.init(id, order: 5, requirement: .none, timeOfDay: .night, action: nil, release: .m1, designPace: 1.0 / 91,
                      definition: "A season counts when 8 of its weeks are steady.",
                      short: { "\($0) \(plural($0, "season"))" },
                      earned: { $0 == 1 ? "For a season in rhythm" : "For \($0) seasons in rhythm" })
            return
        case .steadyMornings:
            self.init(id, order: 6, requirement: .appleHealth, timeOfDay: .morning, action: nil, release: .m1, designPace: 0.6,
                      definition: "Awake within 30 minutes of your wake time.",
                      short: { "\($0) \(plural($0, "morning"))" }, earned: { "For \($0) steady \(plural($0, "morning"))" })
            return
        case .fullNights:
            self.init(id, order: 7, requirement: .sleepTracker, timeOfDay: .night, action: nil, release: .m1, designPace: 0.6,
                      definition: "Asleep for your full sleep need, give or take 30 minutes.",
                      short: { "\($0) full \(plural($0, "night"))" }, earned: { "For \($0) full \(plural($0, "night"))" })
            return
        case .focusHours:
            self.init(id, order: 8, requirement: .none, timeOfDay: .day, action: .startFocus, release: .m2, designPace: 0.75,
                      definition: "Minutes you spend in a focus session, up to its planned length.",
                      short: { "\($0)h focus" }, earned: { "For \($0) hours of focus" })
            return
        case .focusDays:
            self.init(id, order: 9, requirement: .none, timeOfDay: .day, action: .startFocus, release: .m2, designPace: 0.6,
                      definition: "A focus day has one session of 25 minutes or more.",
                      short: { "\($0) \(plural($0, "day"))" },
                      earned: { $0 == 1 ? "For your first focus session" : "For \($0) focus days" })
            return
        case .focusWeeks:
            self.init(id, order: 10, requirement: .none, timeOfDay: .day, action: .startFocus, release: .m2, designPace: 0.1,
                      definition: "A focus week has 3 or more focus days.",
                      short: { "\($0) \(plural($0, "week"))" }, earned: { "For \($0) focus \(plural($0, "week"))" })
            return
        case .soundWindDowns:
            self.init(id, order: 11, requirement: .none, timeOfDay: .night, action: .sleepSounds, release: .m2, designPace: 0.5,
                      definition: "A sleep sound plays for 15 minutes on an on-time night.",
                      short: { "\($0) \(plural($0, "night"))" }, earned: { "For \($0) wind-downs with sound" })
            return
        case .scrollFreeWindDowns:
            self.init(id, order: 12, requirement: .screenTime, timeOfDay: .night, action: .startWindDown, release: .m3, designPace: 0.6,
                      definition: "Under 5 minutes in your wind-down apps before bedtime.",
                      short: { "\($0) calm \(plural($0, "evening"))" }, earned: { "For \($0) scroll-free wind-downs" })
            return
        case .phoneFreeMornings:
            self.init(id, order: 13, requirement: .screenTime, timeOfDay: .morning, action: nil, release: .m3, designPace: 0.5,
                      definition: "Under 2 minutes on your morning apps in the first 30 minutes.",
                      short: { "\($0) \(plural($0, "morning"))" }, earned: { "For \($0) phone-free \(plural($0, "morning"))" })
            return
        case .bedtimeShieldKept:
            self.init(id, order: 14, requirement: .screenTime, timeOfDay: .night, action: nil, release: .m3, designPace: 0.6,
                      definition: "Your bedtime shield stays up all night, with no extra minutes.",
                      short: { "\($0) shield \(plural($0, "night"))" }, earned: { "For \($0) shield \(plural($0, "night"))" })
            return
        case .reflectionWeeks:
            self.init(id, order: 15, requirement: .none, timeOfDay: .morning, action: .checkIn, release: .m4, designPace: 0.1,
                      definition: "A week with a mood check-in on 3 different days.",
                      short: { "\($0) \(plural($0, "week"))" }, earned: { "For \($0) reflection \(plural($0, "week"))" })
            return
        case .caffeineCurfew:
            self.init(id, order: 16, requirement: .none, timeOfDay: .day, action: nil, release: .m4, designPace: 0.5,
                      definition: "No caffeine logged after your curfew.",
                      short: { "\($0) \(plural($0, "day"))" }, earned: { "For \($0) caffeine curfews kept" })
            return
        case .windDownRituals:
            self.init(id, order: 17, requirement: .none, timeOfDay: .night, action: .startWindDown, release: .m6, designPace: 0.5,
                      definition: "A breathing, meditation or journaling ritual before bed.",
                      short: { "\($0) \(plural($0, "ritual"))" }, earned: { "For \($0) wind-down \(plural($0, "ritual"))" })
            return
        case .communityChallenges:
            self.init(id, order: 18, requirement: .none, timeOfDay: .day, action: nil, release: .m9, designPace: 1.0 / 30,
                      definition: "Finish your part of an opt-in community challenge.",
                      short: { "\($0) \(plural($0, "challenge"))" }, earned: { "For \($0) community \(plural($0, "challenge"))" })
            return
        }
    }

    private init(
        _ id: RewardCategoryID, order: Int, requirement: RewardRequirement, timeOfDay: RewardTimeOfDay,
        action: RewardAction?, release: RewardRelease, designPace: Double, definition: String,
        short: @escaping @Sendable (Int) -> String, earned: @escaping @Sendable (Int) -> String
    ) {
        self.id = id
        self.order = order
        self.requirement = requirement
        self.timeOfDay = timeOfDay
        self.action = action
        self.release = release
        self.designPace = designPace
        self.definition = definition
        self.short = short
        self.earned = earned
    }
}

private func plural(_ count: Int, _ word: String) -> String {
    count == 1 ? word : word + "s"
}
