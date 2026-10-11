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

    /// The Focus tab, sessions and their leaves (F1).
    public var focus: Bool { releases.contains(.f1) }
    /// Sounds (F2).
    public var sleepSounds: Bool { releases.contains(.f2) }
    /// Screen Time: blocking and the leaves that need it (F1).
    public var screenTime: Bool { releases.contains(.f1) }
}

/// System permissions the member has granted. Categories that need a missing one show "Needs Apple Health" or
/// "Needs Screen Time" and are left out of next-leaf, buds, Almost there and pacing (D9).
///
/// The live app grants only what is real: Apple Health once the member has been through Apple's Health prompt
/// (`HealthPermission` in MapleServices), never by default. DEBUG demo launches may grant more
/// (`-MapleDemoPermissions`).
public struct GrantedPermissions: OptionSet, Sendable, Hashable, Codable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Sleep data from Apple Health.
    public static let appleHealth = GrantedPermissions(rawValue: 1 << 0)
    /// Asleep-stage data from an Apple Watch or another sleep tracker, read through Apple Health. Not a system
    /// prompt: the collection adds it once Apple Health has delivered a night with asleep time
    /// (`CollectionSnapshot.permissions(in:)`), and DEBUG demos may grant it.
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
        case .screenTime:
            self = permissions.contains(.screenTime) ? .available : .needsScreenTime
        }
    }
}

extension LeafAvailability {
    /// A permission is missing that the member can turn on from Maple (Apple Health, Screen Time).
    public var canBeTurnedOn: Bool {
        self == .needsAppleHealth || self == .needsScreenTime
    }
}
