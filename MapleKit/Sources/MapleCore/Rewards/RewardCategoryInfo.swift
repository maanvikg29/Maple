import Foundation

/// Every behaviour category in `rewards.json`. Decoding fails loudly if the table gains one this list doesn't know.
public enum RewardCategoryID: String, Codable, Sendable, CaseIterable {
    case firstLeaf = "first_leaf"
    case hoursSaved = "hours_saved"
    case sessionsFinished = "sessions_finished"
    case focusStreak = "focus_streak"
    case phoneFreeMornings = "phone_free_mornings"
    case bedtimeKept = "bedtime_kept"
    case restedNights = "rested_nights"
}

/// What a category needs from the system before its leaves can be earned. Rested nights come from Apple Health
/// (rewards.json data sources, spec D9): there is no manual self-report fallback, so a Goodnight tap never counts as
/// a night. The focus categories need Screen Time, which Maple's blocking runs on.
public enum RewardRequirement: Sendable, Equatable {
    case none
    /// Sleep from Apple Health: any of the source ladder's sources (a Watch or tracker, another app, or iPhone's
    /// in-bed estimate).
    case appleHealth
    case screenTime
}

/// The action a leaf's detail screen can offer to make progress.
public enum RewardAction: Sendable, Equatable {
    case startWindDown, startFocus
}

/// The app release that ships a category (focus spec §4.1): M1 now, F1 with the Focus tab, F2 with scheduled blocks.
/// Categories from unshipped releases are "Not earnable yet".
public enum RewardRelease: Int, Sendable, Comparable, CaseIterable {
    case m1 = 1, f1, f2

    public static func < (lhs: RewardRelease, rhs: RewardRelease) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Copy and behaviour for one category, in the voice of the design spec (§5.1).
/// Rule text per leaf comes from `RewardAssignment.unlockText`; these cover the shared lines.
public struct RewardCategoryInfo: Sendable {
    public let id: RewardCategoryID
    /// Canonical position (Herbarium sections, tie-breaks).
    public let order: Int
    public let requirement: RewardRequirement
    public let action: RewardAction?
    public let release: RewardRelease
    /// Units per day for a committed member; used to estimate time-to-leaf before there's personal history.
    public let designPace: Double
    /// One-line, plain-language definition shown under section headers and in leaf detail.
    public let definition: String
    private let short: @Sendable (Int) -> String
    private let earned: @Sendable (Int) -> String

    /// Tile-sized rule, e.g. "14 rested".
    public func shortRule(_ threshold: Double) -> String { short(Int(threshold.rounded())) }
    /// The line under an earned leaf, e.g. "For 14 rested nights".
    public func earnedLine(_ threshold: Double) -> String { earned(Int(threshold.rounded())) }

    public init(_ id: RewardCategoryID) {
        switch id {
        case .firstLeaf:
            self.init(id, order: 0, requirement: .none, action: nil, release: .m1, designPace: 1,
                      definition: "Plant your maple at the end of setup.",
                      short: { _ in "Setup" }, earned: { _ in "For planting your maple" })
            return
        case .hoursSaved:
            self.init(id, order: 1, requirement: .screenTime, action: .startFocus, release: .f1, designPace: 1.9,
                      definition: "Time your chosen apps stayed locked while you were awake.",
                      short: { "\($0)h saved" },
                      earned: { $0 == 1 ? "For your first hour saved" : "For \($0) hours saved" })
            return
        case .sessionsFinished:
            self.init(id, order: 2, requirement: .screenTime, action: .startFocus, release: .f1, designPace: 1,
                      definition: "A session you started, 20 minutes or longer, that ran to its planned end.",
                      short: { "\($0) \(plural($0, "session"))" },
                      earned: { $0 == 1 ? "For your first finished session" : "For \($0) finished sessions" })
            return
        case .focusStreak:
            self.init(id, order: 3, requirement: .screenTime, action: .startFocus, release: .f1, designPace: 0.8,
                      definition: "Days in a row with a finished session. Two rest days a week are built in.",
                      short: { "\($0)-day streak" }, earned: { "For a \($0)-day focus streak" })
            return
        case .bedtimeKept:
            self.init(id, order: 5, requirement: .screenTime, action: .startWindDown, release: .f2, designPace: 0.5,
                      definition: "Your wind-down ran to bedtime with no unlock, early end or phone break.",
                      short: { "\($0) \(plural($0, "night"))" },
                      earned: { $0 == 1 ? "For your first bedtime kept" : "For \($0) bedtimes kept" })
            return
        case .restedNights:
            self.init(id, order: 6, requirement: .appleHealth, action: .startWindDown, release: .m1, designPace: 0.6,
                      definition: "Asleep no later than 30 minutes after your bedtime, from Apple Health.",
                      short: { "\($0) rested" },
                      earned: { $0 == 1 ? "For your first rested night" : "For \($0) rested nights" })
            return
        case .phoneFreeMornings:
            self.init(id, order: 4, requirement: .screenTime, action: nil, release: .f2, designPace: 0.5,
                      definition: "Your Morning block ran to its end with no unlock, early end or phone break.",
                      short: { "\($0) \(plural($0, "morning"))" },
                      earned: { $0 == 1 ? "For your first phone-free morning" : "For \($0) phone-free mornings" })
            return
        }
    }

    private init(
        _ id: RewardCategoryID, order: Int, requirement: RewardRequirement, action: RewardAction?, release: RewardRelease, designPace: Double, definition: String,
        short: @escaping @Sendable (Int) -> String, earned: @escaping @Sendable (Int) -> String
    ) {
        self.id = id
        self.order = order
        self.requirement = requirement
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
