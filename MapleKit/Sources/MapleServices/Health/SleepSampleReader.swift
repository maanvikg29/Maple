import Foundation
import HealthKit
import MapleCore
import os

/// What one anchored read of Apple Health's sleep analysis returned: the samples added since the anchor (all of them
/// in the window when there is none), the ids of samples deleted since, and the anchor to read from next time.
nonisolated public struct SleepSampleChanges: Sendable, Equatable {
    public var added: [SleepSample]
    public var deletedIDs: [String]
    /// HealthKit's `HKQueryAnchor`, archived; nil keeps the previous one.
    public var anchor: Data?

    public init(added: [SleepSample] = [], deletedIDs: [String] = [], anchor: Data? = nil) {
        self.added = added
        self.deletedIDs = deletedIDs
        self.anchor = anchor
    }
}

/// Why Apple Health's sleep couldn't be read. The importer keeps everything it has and tries again later.
nonisolated public enum SleepReadError: Error, Sendable, Equatable {
    /// The device has no Apple Health.
    case healthDataUnavailable
    /// The iPhone is locked, so protected health data can't be read (`HKError.errorDatabaseInaccessible`). Never a
    /// reason to forget anything: read again once it unlocks.
    case locked
    /// Apple's prompt hasn't been answered for sleep (`errorAuthorizationNotDetermined`).
    case notAuthorized
    case failed(String)
}

/// Reads sleep analysis from Apple Health: `HealthKitSleepReader` in the app, a stand-in in tests.
public protocol SleepSampleReading: AnyObject {
    /// The device has Apple Health.
    var isHealthDataAvailable: Bool { get }
    /// Samples that end after `start`, added or deleted since `anchor` (everything when it is nil).
    /// - Parameter zone: The zone stamped on samples that don't carry `HKMetadataKeyTimeZone`.
    func changes(since anchor: Data?, from start: Date, zone: String) async throws(SleepReadError) -> SleepSampleChanges
    /// Calls `onChange` whenever Apple Health's sleep changes while the app runs (an `HKObserverQuery`). The query
    /// waits for `onChange` to finish before telling HealthKit it is done.
    func startObserving(_ onChange: @escaping @MainActor @Sendable () async -> Void)
    func stopObserving()
    /// Asks HealthKit to wake the app for new sleep (needs `com.apple.developer.healthkit.background-delivery`).
    func enableBackgroundDelivery() async throws(SleepReadError)
}

/// Apple Health's sleep analysis through `HKHealthStore`: an anchored query for the importer's window, an observer
/// query while the app runs, and (paid tier only) background delivery.
public final class HealthKitSleepReader: SleepSampleReading {
    private let store = HKHealthStore()
    private var observer: HKObserverQuery?
    nonisolated private static var logger: Logger { Logger(subsystem: "com.maanvikgupta.maple", category: "health") }

    public init() {}

    nonisolated private static var sleepType: HKCategoryType { HKCategoryType(.sleepAnalysis) }

    public var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    public func changes(since anchor: Data?, from start: Date, zone: String) async throws(SleepReadError) -> SleepSampleChanges {
        guard isHealthDataAvailable else { throw .healthDataUnavailable }
        return try await Self.read(store: store, since: anchor, from: start, zone: zone)
    }

    /// The anchored read, off the main actor; only plain values come back.
    nonisolated private static func read(
        store: HKHealthStore, since anchor: Data?, from start: Date, zone: String
    ) async throws(SleepReadError) -> SleepSampleChanges {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil, options: [])
        let descriptor = HKAnchoredObjectQueryDescriptor(
            predicates: [.categorySample(type: sleepType, predicate: predicate)], anchor: anchor.flatMap(unarchive)
        )
        do {
            let result = try await descriptor.result(for: store)
            return SleepSampleChanges(
                added: result.addedSamples.compactMap { sample(from: $0, zone: zone) },
                deletedIDs: result.deletedObjects.map(\.uuid.uuidString),
                anchor: archive(result.newAnchor)
            )
        } catch {
            throw readError(error)
        }
    }

    public func startObserving(_ onChange: @escaping @MainActor @Sendable () async -> Void) {
        guard observer == nil, isHealthDataAvailable else { return }
        let query = HKObserverQuery(sampleType: Self.sleepType, predicate: nil) { _, completion, error in
            let done = ObserverCompletion(completion)
            if let error {
                Self.logger.error("Apple Health's sleep observer failed: \(String(describing: error), privacy: .public)")
                done.call()
                return
            }
            Task { @MainActor in
                await onChange()
                done.call()
            }
        }
        observer = query
        store.execute(query)
    }

    public func stopObserving() {
        guard let observer else { return }
        store.stop(observer)
        self.observer = nil
    }

    public func enableBackgroundDelivery() async throws(SleepReadError) {
        guard isHealthDataAvailable else { throw .healthDataUnavailable }
        do {
            try await store.enableBackgroundDelivery(for: Self.sleepType, frequency: .hourly)
        } catch {
            throw Self.readError(error)
        }
    }

    // MARK: Mapping

    /// A HealthKit sample as plain values; nil for a value Maple doesn't know.
    nonisolated static func sample(from sample: HKCategorySample, zone: String) -> SleepSample? {
        guard let stage = stage(sample.value) else { return nil }
        let source = sample.sourceRevision
        var origin = SleepSample.Origin(
            bundleIdentifier: source.source.bundleIdentifier, name: source.source.name, productType: source.productType,
            deviceName: sample.device?.name, deviceModel: sample.device?.model, deviceManufacturer: sample.device?.manufacturer
        )
        #if DEBUG
        // DEBUG `-MapleDemoSeedHealth`: the seeder's samples stand for the source they were written as.
        if let seeded = sample.metadata?[HealthSleepSeeder.metadataKey] as? String,
           let seedSource = HealthSleepSeeder.Source(rawValue: seeded) {
            origin = seedSource.origin
        }
        #endif
        let typedIn = (sample.metadata?[HKMetadataKeyWasUserEntered] as? NSNumber)?.boolValue ?? false
        let sampleZone = (sample.metadata?[HKMetadataKeyTimeZone] as? String).flatMap { TimeZone(identifier: $0)?.identifier }
        return SleepSample(
            id: sample.uuid.uuidString, start: sample.startDate, end: sample.endDate, stage: stage, origin: origin,
            wasUserEntered: typedIn, timeZoneIdentifier: sampleZone ?? zone
        )
    }

    nonisolated static func stage(_ value: Int) -> SleepSample.Stage? {
        guard let value = HKCategoryValueSleepAnalysis(rawValue: value) else { return nil }
        switch value {
        case .inBed: return .inBed
        case .asleepUnspecified: return .asleepUnspecified
        case .asleepCore: return .asleepCore
        case .asleepDeep: return .asleepDeep
        case .asleepREM: return .asleepREM
        case .awake: return .awake
        @unknown default: return nil
        }
    }

    nonisolated static func readError(_ error: any Error) -> SleepReadError {
        guard let error = error as? HKError else { return .failed(String(describing: error)) }
        switch error.code {
        case .errorDatabaseInaccessible: return .locked
        case .errorHealthDataUnavailable, .errorHealthDataRestricted: return .healthDataUnavailable
        case .errorAuthorizationNotDetermined, .errorAuthorizationDenied: return .notAuthorized
        default: return .failed(String(describing: error))
        }
    }

    nonisolated private static func archive(_ anchor: HKQueryAnchor) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
    }

    nonisolated private static func unarchive(_ data: Data) -> HKQueryAnchor? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }
}

/// HealthKit's observer completion, called once the import it triggered has finished. HealthKit allows calling it
/// from any thread.
nonisolated private struct ObserverCompletion: @unchecked Sendable {
    let call: () -> Void

    init(_ completion: @escaping () -> Void) {
        call = completion
    }
}
