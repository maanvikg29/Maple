import Foundation
import HealthKit
import MapleCore
import os

/// Reads sleep from Apple Health: `HealthKitSleepReader` in the app, a stand-in in tests.
public protocol SleepSampleReading {
    /// The sleep samples overlapping `start` to `end` that count for sleep, already placed on the source ladder
    /// (user-entered samples, awake stages and other apps' in-bed samples left out).
    func sleepSamples(from start: Date, to end: Date) async throws -> [SleepSample]
}

/// `HKHealthStore`'s sleep analysis, read with the access `HealthKitAuthorizer` asked for. HealthKit returns nothing
/// (not an error) when the member didn't allow reading sleep, so those nights settle untracked.
public struct HealthKitSleepReader: SleepSampleReading {
    private let store = HKHealthStore()

    public init() {}

    public func sleepSamples(from start: Date, to end: Date) async throws -> [SleepSample] {
        let range = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let query = HKSampleQueryDescriptor(predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: range)],
                                            sortDescriptors: [])
        return try await query.result(for: store).compactMap(Self.sample)
    }

    /// The sample if it counts for sleep (`SleepSampleOrigin.source`).
    static func sample(_ sample: HKCategorySample) -> SleepSample? {
        let origin = SleepSampleOrigin(
            stage: stage(of: sample.value),
            bundleIdentifier: sample.sourceRevision.source.bundleIdentifier,
            productType: sample.sourceRevision.productType,
            deviceModel: sample.device?.model,
            wasUserEntered: (sample.metadata?[HKMetadataKeyWasUserEntered] as? Bool) ?? false
        )
        return SleepSample(start: sample.startDate, end: sample.endDate, origin: origin,
                           timeZoneIdentifier: sample.metadata?[HKMetadataKeyTimeZone] as? String)
    }

    /// Asleep (unspecified or any stage), in bed or awake. Values HealthKit adds later never count.
    static func stage(of value: Int) -> SleepSampleOrigin.Stage {
        guard let analysis = HKCategoryValueSleepAnalysis(rawValue: value) else { return .awake }
        switch analysis {
        case .inBed: return .inBed
        case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM: return .asleep
        case .awake: return .awake
        @unknown default: return .awake
        }
    }
}

/// M1's importer: reads the last few nights from Apple Health and records them in the collection (spec D9,
/// docs/core-api.md "Recording behaviour"). The live app runs it on every foreground and as soon as Apple Health
/// is connected; DEBUG demo stores have none, so demo collections are never fed nights.
///
/// It reads every night still inside the ledger's 72-hour upgrade window, so a Watch that syncs late still upgrades
/// its night, and sends them all each time (recording the same nights again changes nothing). It does nothing until
/// Apple Health is connected and the maple is planted, and nothing when Apple Health can't be read (the device is
/// locked): nights are settled, untracked if Apple Health has nothing for them, only after a read that worked.
///
/// ```swift
/// await stores.sleep?.importRecentNights(at: clock.now())   // the leaves last night earned, held or pending
/// ```
public final class SleepImporter {
    /// Nights read before last night (or tonight, before the morning): enough to cover the 72-hour upgrade window.
    public static let earlierNightsRead = 4

    private let collection: CollectionStore
    private let health: HealthPermission
    private let reader: any SleepSampleReading
    private var isImporting = false
    private static var logger: Logger { Logger(subsystem: "com.maanvikgupta.maple", category: "sleep") }

    public init(collection: CollectionStore, health: HealthPermission, reader: any SleepSampleReading = HealthKitSleepReader()) {
        self.collection = collection
        self.health = health
        self.reader = reader
    }

    /// Reads Apple Health's recent nights and records them (`CollectionStore.recordSleep(_:at:)`).
    /// - Returns: The leaves they unlocked, stamped `date`.
    @discardableResult
    public func importRecentNights(at date: Date) async -> [LeafUnlock] {
        guard health.isConnected, collection.isAvailable, collection.hasPlantedMaple, !isImporting else { return [] }
        isImporting = true
        defer { isImporting = false }

        let calendar = collection.context.calendar
        // Read from 18:00 on the evening before the oldest night, and leave that evening out: its episode may have
        // begun before the read did.
        let edge = NightLedger.night(containing: date, calendar: calendar).adding(days: -(Self.earlierNightsRead + 1), calendar: calendar)
        let start = calendar.date(byAdding: .hour, value: 18, to: edge.startDate(in: calendar)) ?? edge.startDate(in: calendar)
        let samples: [SleepSample]
        do {
            samples = try await reader.sleepSamples(from: start, to: date)
        } catch {
            Self.logger.error("Apple Health's sleep couldn't be read: \(String(describing: error), privacy: .public)")
            return []
        }
        let nights = SleepNightBuilder(calendar: calendar).observations(from: samples).filter { $0.night > edge }
        return collection.recordSleep(nights, at: date)
    }
}
