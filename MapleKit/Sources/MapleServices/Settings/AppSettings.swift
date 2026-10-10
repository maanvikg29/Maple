import Foundation
import MapleCore
import Observation

/// Where Maple's seasons come from: the device's region, or the member's choice in Settings (spec §8.7).
nonisolated public enum HemisphereChoice: String, Codable, Sendable, CaseIterable {
    case automatic
    case northern
    case southern

    /// The hemisphere this choice means on a device in `regionCode` (an ISO region such as "AU").
    public func resolved(regionCode: String?) -> Hemisphere {
        switch self {
        case .automatic: Hemisphere(regionCode: regionCode)
        case .northern: .northern
        case .southern: .southern
        }
    }

    public var displayName: String {
        switch self {
        case .automatic: "Automatic"
        case .northern: "Northern"
        case .southern: "Southern"
        }
    }
}

/// The member's preferences, saved as one small JSON file next to the collection.
nonisolated public struct SettingsSnapshot: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    public var hemisphere: HemisphereChoice
    /// The sleep need behind Full nights: asleep for at least this, less 30 minutes (rewards.json `full_nights`;
    /// "7h unless you change it", spec §5.1).
    public var sleepGoalMinutes: Int
    /// A soft sound as a leaf opens. Off by default (spec §8.7).
    public var revealSound: Bool
    /// "Time to wind down" at the start of wind-down. On by default; sent only once iOS allows notifications.
    public var windDownReminder: Bool
    /// "A new leaf is waiting" at the start of the morning, only when one is. On by default, like wind-down.
    public var morningLeafReminder: Bool

    public init(
        hemisphere: HemisphereChoice = .automatic, sleepGoalMinutes: Int = AppSettings.defaultSleepGoalMinutes,
        revealSound: Bool = false, windDownReminder: Bool = true, morningLeafReminder: Bool = true
    ) {
        version = Self.currentVersion
        self.hemisphere = hemisphere
        self.sleepGoalMinutes = AppSettings.validSleepGoal(sleepGoalMinutes)
        self.revealSound = revealSound
        self.windDownReminder = windDownReminder
        self.morningLeafReminder = morningLeafReminder
    }

    // MARK: Codable (tolerant: missing or unknown values take their defaults)

    private enum CodingKeys: String, CodingKey {
        case version, hemisphere, sleepGoalMinutes, revealSound, windDownReminder, morningLeafReminder
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        hemisphere = (try? c.decodeIfPresent(String.self, forKey: .hemisphere)).flatMap(HemisphereChoice.init(rawValue:))
            ?? .automatic
        sleepGoalMinutes = AppSettings.validSleepGoal(
            (try? c.decodeIfPresent(Int.self, forKey: .sleepGoalMinutes)) ?? AppSettings.defaultSleepGoalMinutes
        )
        revealSound = (try? c.decodeIfPresent(Bool.self, forKey: .revealSound)) ?? false
        windDownReminder = (try? c.decodeIfPresent(Bool.self, forKey: .windDownReminder)) ?? true
        morningLeafReminder = (try? c.decodeIfPresent(Bool.self, forKey: .morningLeafReminder)) ?? true
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(hemisphere, forKey: .hemisphere)
        try c.encode(sleepGoalMinutes, forKey: .sleepGoalMinutes)
        try c.encode(revealSound, forKey: .revealSound)
        try c.encode(windDownReminder, forKey: .windDownReminder)
        try c.encode(morningLeafReminder, forKey: .morningLeafReminder)
    }
}

/// The member's settings: hemisphere, sleep goal, the reveal sound and the two reminders (spec §8.7). One instance
/// for the app, injected with `.environment(_:)`; screens read it with `@Environment(AppSettings.self)` and assign
/// to its properties, which saves at once.
///
/// ```swift
/// @Environment(AppSettings.self) private var settings
///
/// settings.revealSound          // the reveal plays its sound only when true
/// settings.sleepGoalMinutes     // the sleep need: a Full night is at least this, less 30 minutes
/// settings.apply(to: collection) // seasons follow the chosen hemisphere (MapleApp does this)
/// ```
@Observable
public final class AppSettings {
    nonisolated public static let file = "settings.json"
    nonisolated public static let defaultSleepGoalMinutes = CollectionContext.defaultSleepNeedMinutes
    nonisolated public static let sleepGoalRange = (5 * 60)...(10 * 60)
    nonisolated public static let sleepGoalStep = 30

    public private(set) var snapshot: SettingsSnapshot
    /// False while the settings file exists but can't be read yet (before the first unlock after a restart).
    public private(set) var isAvailable: Bool

    @ObservationIgnored private let storage: JSONStorage<SettingsSnapshot>
    @ObservationIgnored private let regionCode: String?

    /// - Parameter regionCode: The device's region, which Automatic reads (`Locale.current.region`).
    public init(storage: JSONStorage<SettingsSnapshot>, regionCode: String? = Locale.current.region?.identifier) {
        self.storage = storage
        self.regionCode = regionCode
        switch storage.read() {
        case .value(let saved):
            snapshot = saved
            isAvailable = true
        case .absent:
            snapshot = SettingsSnapshot()
            isAvailable = true
        case .unavailable:
            snapshot = SettingsSnapshot()
            isAvailable = false
        }
    }

    /// Reads the settings again if they couldn't be read at launch.
    /// - Returns: Whether the store now holds the member's real settings (or knows there are none).
    @discardableResult
    public func reloadIfUnavailable() -> Bool {
        guard !isAvailable else { return false }
        switch storage.read() {
        case .value(let saved): snapshot = saved
        case .absent: snapshot = SettingsSnapshot()
        case .unavailable: return false
        }
        isAvailable = true
        return true
    }

    // MARK: Values

    public var hemisphere: HemisphereChoice {
        get { snapshot.hemisphere }
        set { change { $0.hemisphere = newValue } }
    }

    /// The hemisphere the seasons follow.
    public var resolvedHemisphere: Hemisphere { hemisphere.resolved(regionCode: regionCode) }

    /// What Automatic means on this device.
    public var regionHemisphere: Hemisphere { HemisphereChoice.automatic.resolved(regionCode: regionCode) }

    /// Between 5 and 10 hours, in 30-minute steps; other values are clamped and rounded down to a step.
    public var sleepGoalMinutes: Int {
        get { snapshot.sleepGoalMinutes }
        set { change { $0.sleepGoalMinutes = Self.validSleepGoal(newValue) } }
    }

    public var revealSound: Bool {
        get { snapshot.revealSound }
        set { change { $0.revealSound = newValue } }
    }

    /// "Time to wind down" at the start of wind-down (Profile › Settings). On until the member turns it off.
    public var windDownReminder: Bool {
        get { snapshot.windDownReminder }
        set { change { $0.windDownReminder = newValue } }
    }

    /// "A new leaf is waiting" at the start of the morning, only when one is. On until the member turns it off.
    public var morningLeafReminder: Bool {
        get { snapshot.morningLeafReminder }
        set { change { $0.morningLeafReminder = newValue } }
    }

    /// The two reminder switches, as `ReminderPlan` reads them.
    public var reminders: ReminderSettings {
        ReminderSettings(windDown: windDownReminder, morningLeaf: morningLeafReminder)
    }

    public var canIncreaseSleepGoal: Bool { sleepGoalMinutes < Self.sleepGoalRange.upperBound }
    public var canDecreaseSleepGoal: Bool { sleepGoalMinutes > Self.sleepGoalRange.lowerBound }

    public func increaseSleepGoal() {
        sleepGoalMinutes += Self.sleepGoalStep
    }

    public func decreaseSleepGoal() {
        sleepGoalMinutes -= Self.sleepGoalStep
    }

    /// Points the collection's seasons (the `\.season` environment and the tree) at the chosen hemisphere, and its
    /// Full nights at the sleep goal. A DEBUG `-MapleDemoSeason` override still wins, because the collection checks
    /// it first.
    public func apply(to collection: CollectionStore) {
        var context = collection.context
        context.hemisphere = resolvedHemisphere
        context.sleepNeedMinutes = sleepGoalMinutes
        guard context != collection.context else { return }
        collection.context = context
    }

    nonisolated static func validSleepGoal(_ minutes: Int) -> Int {
        let clamped = min(max(minutes, sleepGoalRange.lowerBound), sleepGoalRange.upperBound)
        return clamped - (clamped - sleepGoalRange.lowerBound) % sleepGoalStep
    }

    // MARK: Launch

    /// The member's settings file in `directory`.
    public static func live(directory: URL = MapleContainer.directory()) -> AppSettings {
        AppSettings(storage: JSONStorage(.file(directory.appending(path: file))))
    }

    /// What this launch should use. DEBUG demo launches (docs/debug-launch-arguments.md) get an in-memory copy of
    /// the member's settings, like every other store, so a demo never writes the real file.
    public static func launch(directory: URL = MapleContainer.directory()) -> AppSettings {
        #if DEBUG
        if DemoLaunchOptions.current.isActive {
            let saved = JSONStorage<SettingsSnapshot>(.file(directory.appending(path: file))).load()
            return AppSettings(storage: JSONStorage(.memory, initial: saved))
        }
        #endif
        return live(directory: directory)
    }

    // MARK: Private

    private func change(_ edit: (inout SettingsSnapshot) -> Void) {
        // A change lands on the member's real settings, never on launch defaults saved over an unreadable file.
        if !isAvailable { reloadIfUnavailable() }
        var copy = snapshot
        edit(&copy)
        guard copy != snapshot else { return }
        snapshot = copy
        storage.save(copy)
    }
}
