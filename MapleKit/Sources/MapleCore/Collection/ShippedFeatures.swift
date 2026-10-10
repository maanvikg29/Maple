import Foundation

/// The releases this build ships. A category from an unshipped release is "Not earnable yet", and a feature
/// that hasn't shipped is absent everywhere (spec §2.2, §8).
public struct ShippedFeatures: Sendable, Hashable {
    public var releases: Set<RewardRelease>

    public init(releases: Set<RewardRelease>) {
        self.releases = releases
    }

    /// What this build ships: the M1 sleep loop only.
    public static let current = ShippedFeatures(releases: [.m1])
    /// Every release, for previews and tests of later screens.
    public static let all = ShippedFeatures(releases: Set(RewardRelease.allCases))

    public func isShipped(_ category: RewardCategoryID) -> Bool {
        releases.contains(RewardCategoryInfo(category).release)
    }

    /// The focus timer (Rest › Focus, Home's day numeral and "Start focus").
    public var focus: Bool { releases.contains(.m2) }
    /// Sleep sounds (Home's night capsule, the Sounds sheet).
    public var sleepSounds: Bool { releases.contains(.m2) }
    /// Screen Time: wind-down apps, the shield and their leaves.
    public var screenTime: Bool { releases.contains(.m3) }
    /// Morning mood check-ins.
    public var checkIns: Bool { releases.contains(.m4) }
}

/// System permissions the member has granted. Categories that need a missing one show "Needs Apple Health" or
/// "Needs Screen Time" and are left out of next-leaf, Almost there and pacing (D9).
public struct GrantedPermissions: OptionSet, Sendable, Hashable, Codable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Sleep data from Apple Health.
    public static let appleHealth = GrantedPermissions(rawValue: 1 << 0)
    /// Asleep-stage data from an Apple Watch or another sleep tracker, read through Apple Health.
    public static let sleepTracker = GrantedPermissions(rawValue: 1 << 1)
    public static let screenTime = GrantedPermissions(rawValue: 1 << 2)
}

extension LeafAvailability {
    /// Whether `category` can be earned: shipped first, then its required permission.
    public init(category: RewardCategoryID, permissions: GrantedPermissions, features: ShippedFeatures) {
        guard features.isShipped(category) else {
            self = .dormant
            return
        }
        switch RewardCategoryInfo(category).requirement {
        case .none:
            self = .available
        case .appleHealth:
            self = permissions.contains(.appleHealth) ? .available : .needsAppleHealth
        case .sleepTracker:
            if !permissions.contains(.appleHealth) {
                self = .needsAppleHealth
            } else {
                self = permissions.contains(.sleepTracker) ? .available : .needsSleepTracker
            }
        case .screenTime:
            self = permissions.contains(.screenTime) ? .available : .needsScreenTime
        }
    }
}
