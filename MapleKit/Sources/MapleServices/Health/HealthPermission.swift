import Foundation
import HealthKit
import MapleCore
import Observation
import os

/// What Maple keeps about Apple Health: whether the member has been through Apple's Health prompt for sleep.
nonisolated public struct HealthConnection: Codable, Sendable, Equatable {
    /// When the member finished Apple's Health sheet; nil until then.
    public var promptCompletedAt: Date?

    public init(promptCompletedAt: Date? = nil) {
        self.promptCompletedAt = promptCompletedAt
    }

    /// Apple Health counts as connected once the prompt has been answered.
    public var isConnected: Bool { promptCompletedAt != nil }

    /// What the connection grants: Apple Health, or nothing.
    public var permissions: GrantedPermissions { isConnected ? [.appleHealth] : [] }
}

/// Asks Apple Health for sleep: `HealthKitAuthorizer` in the app, a stand-in in tests.
public protocol HealthAuthorizing {
    /// The device has Apple Health (every iPhone does).
    var isHealthDataAvailable: Bool { get }
    /// Whether Apple's prompt for reading sleep still has something to ask: true before the member has answered it,
    /// false once they have, nil when Apple Health can't say.
    func promptIsDue() async -> Bool?
    /// Shows Apple's Health sheet asking to read sleep; returns once the member has closed it.
    func requestSleepAccess() async throws
}

/// `HKHealthStore`, asking to read sleep analysis and nothing else (the entitlement and usage strings are in
/// `Config/`).
public struct HealthKitAuthorizer: HealthAuthorizing {
    private let store = HKHealthStore()

    public init() {}

    /// Sleep analysis: asleep stages, asleep and in-bed samples (rewards.json's source ladder).
    private static var readTypes: Set<HKObjectType> { [HKCategoryType(.sleepAnalysis)] }

    public var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    public func promptIsDue() async -> Bool? {
        guard isHealthDataAvailable else { return nil }
        do {
            switch try await store.statusForAuthorizationRequest(toShare: [], read: Self.readTypes) {
            case .shouldRequest: return true
            case .unnecessary: return false
            case .unknown: return nil
            @unknown default: return nil
            }
        } catch {
            return nil
        }
    }

    public func requestSleepAccess() async throws {
        try await store.requestAuthorization(toShare: [], read: Self.readTypes)
    }
}

/// Whether Maple may read sleep from Apple Health: the app's real Apple Health permission (spec D9, §8.7).
///
/// HealthKit never tells an app whether *read* access was granted, only whether its prompt has been answered. So
/// Maple records that the member completed Apple's prompt and treats Apple Health as connected from then on: the
/// sleep categories become available, and M1's importer reads whatever the member allowed. Until then nothing is
/// granted, and the sleep leaves show "Needs Apple Health" (left out of the next leaf, buds, Almost there and
/// pacing). The record is saved in `health.json`; on every foreground the live app checks it against Apple Health's
/// own prompt status, so a reset of the member's Health answers shows as not connected again.
///
/// ```swift
/// @Environment(HealthPermission.self) private var health
///
/// if await health.requestAccess(at: clock.now()) {   // Apple's sheet; true once the member closed it
///     health.apply(to: collection)                  // the sleep leaves become available
/// }
/// ```
@Observable
public final class HealthPermission {
    nonisolated public static let file = "health.json"

    public private(set) var connection: HealthConnection
    /// Apple's sheet is up (or about to be).
    public private(set) var isRequesting = false
    /// False while `health.json` exists but can't be read yet (before the first unlock after a restart).
    public private(set) var isAvailable: Bool
    /// Checks Apple Health's own prompt status on `refresh(at:)`. True for the member's live store; DEBUG demos keep
    /// the permissions their launch arguments gave them.
    @ObservationIgnored public var followsHealthKit = false

    @ObservationIgnored private let storage: JSONStorage<HealthConnection>
    @ObservationIgnored private let authorizer: any HealthAuthorizing
    private static var logger: Logger { Logger(subsystem: "com.maanvikgupta.maple", category: "health") }

    public init(storage: JSONStorage<HealthConnection>, authorizer: any HealthAuthorizing = HealthKitAuthorizer()) {
        self.storage = storage
        self.authorizer = authorizer
        switch storage.read() {
        case .value(let saved):
            connection = saved
            isAvailable = true
        case .absent:
            connection = HealthConnection()
            isAvailable = true
        case .unavailable:
            connection = HealthConnection()
            isAvailable = false
        }
    }

    /// The member has been through Apple's prompt.
    public var isConnected: Bool { connection.isConnected }

    /// Apple Health exists on this device, so the prompt can be shown.
    public var canRequest: Bool { authorizer.isHealthDataAvailable }

    /// What this grants the collection: Apple Health once connected, else nothing.
    public var permissions: GrantedPermissions { connection.permissions }

    /// Shows Apple's Health sheet asking to read sleep. Once the member closes it, whatever they chose, Apple Health
    /// counts as connected (HealthKit never says whether reading was allowed).
    /// - Returns: Whether Apple Health is connected now; false if the sheet couldn't be shown.
    @discardableResult
    public func requestAccess(at date: Date) async -> Bool {
        guard !isRequesting else { return isConnected }
        guard authorizer.isHealthDataAvailable else { return false }
        isRequesting = true
        defer { isRequesting = false }
        do {
            try await authorizer.requestSleepAccess()
        } catch {
            Self.logger.error("Apple Health's prompt failed: \(String(describing: error), privacy: .public)")
            return false
        }
        if !isConnected { change { $0.promptCompletedAt = date } }
        return true
    }

    /// Brings the record in line with Apple Health (live store only): connected once the prompt has been answered,
    /// even if this record was lost; not connected again if the member's Health answers were reset.
    public func refresh(at date: Date) async {
        guard followsHealthKit, let due = await authorizer.promptIsDue() else { return }
        if due, isConnected {
            change { $0.promptCompletedAt = nil }
        } else if !due, !isConnected {
            change { $0.promptCompletedAt = date }
        }
    }

    /// Grants Apple Health in the collection's context when connected, and withdraws it (with the sleep tracker it
    /// implies) when not. Other permissions stay as they are.
    public func apply(to collection: CollectionStore) {
        var granted = collection.context.permissions
        if isConnected {
            granted.insert(.appleHealth)
        } else {
            granted.subtract([.appleHealth, .sleepTracker])
        }
        guard granted != collection.context.permissions else { return }
        collection.context.permissions = granted
    }

    /// Reads the record again if it couldn't be read at launch.
    /// - Returns: Whether it now holds the member's real record (or knows there is none).
    @discardableResult
    public func reloadIfUnavailable() -> Bool {
        guard !isAvailable else { return false }
        switch storage.read() {
        case .value(let saved): connection = saved
        case .absent: connection = HealthConnection()
        case .unavailable: return false
        }
        isAvailable = true
        return true
    }

    // MARK: Launch

    /// The member's record in `directory`, checked against Apple Health on every foreground.
    public static func live(
        directory: URL = MapleContainer.directory(), authorizer: any HealthAuthorizing = HealthKitAuthorizer()
    ) -> HealthPermission {
        let health = HealthPermission(storage: JSONStorage(.file(directory.appending(path: file))), authorizer: authorizer)
        health.followsHealthKit = true
        return health
    }

    // MARK: Private

    private func change(_ edit: (inout HealthConnection) -> Void) {
        // A change lands on the member's real record, never on a placeholder saved over an unreadable file.
        if !isAvailable { reloadIfUnavailable() }
        var copy = connection
        edit(&copy)
        guard copy != connection else { return }
        connection = copy
        storage.save(copy)
    }
}
