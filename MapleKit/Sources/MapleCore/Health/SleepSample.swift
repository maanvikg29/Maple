import Foundation

/// One Apple Health sleep-analysis sample, as plain values: what M1's importer reads from HealthKit
/// (`HKCategorySample` of `sleepAnalysis`) and keeps in its local-only cache. Pure, so `SleepNightBuilder` can turn
/// samples into nights without HealthKit, in tests and anywhere else.
public struct SleepSample: Codable, Sendable, Hashable, Identifiable {
    /// HealthKit's sleep-analysis values.
    public enum Stage: String, Codable, Sendable, CaseIterable {
        /// In bed, not necessarily asleep (iPhone's Sleep schedule writes these).
        case inBed
        /// Asleep, stage unknown (most other apps, and older Watch data).
        case asleepUnspecified
        case asleepCore
        case asleepDeep
        case asleepREM
        /// Awake during the night (never counted as time asleep).
        case awake

        /// Any asleep stage.
        public var isAsleep: Bool {
            switch self {
            case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM: true
            case .inBed, .awake: false
            }
        }
    }

    /// Who wrote the sample: HealthKit's source (an app, or the device's own Health source) and, when given, the
    /// hardware that measured it (`HKSourceRevision` and `HKDevice`).
    public struct Origin: Codable, Sendable, Hashable {
        /// `HKSource.bundleIdentifier`: Apple's own sources are "com.apple.health.<device id>".
        public var bundleIdentifier: String
        /// `HKSource.name`, e.g. "Apple Watch" or an app's name.
        public var name: String
        /// `HKSourceRevision.productType`, e.g. "Watch7,1" or "iPhone17,1".
        public var productType: String?
        /// `HKDevice.name`, `.model` ("Watch", "iPhone") and `.manufacturer`, when the writer gave a device.
        public var deviceName: String?
        public var deviceModel: String?
        public var deviceManufacturer: String?

        public init(
            bundleIdentifier: String, name: String, productType: String? = nil, deviceName: String? = nil,
            deviceModel: String? = nil, deviceManufacturer: String? = nil
        ) {
            self.bundleIdentifier = bundleIdentifier
            self.name = name
            self.productType = productType
            self.deviceName = deviceName
            self.deviceModel = deviceModel
            self.deviceManufacturer = deviceManufacturer
        }

        /// One source writing one night: the app or device, and the product that wrote it.
        var key: String { bundleIdentifier + "|" + (productType ?? "") }
    }

    /// HealthKit's sample UUID, stable across reads, so a deleted sample can be removed from the cache.
    public var id: String
    public var start: Date
    public var end: Date
    public var stage: Stage
    public var origin: Origin
    /// `HKMetadataKeyWasUserEntered`: typed in by hand. Never counts (rewards.json `nights_tracked`).
    public var wasUserEntered: Bool
    /// The zone the sample was recorded in (`HKMetadataKeyTimeZone`; the importer stamps the zone in force when it
    /// first reads a sample without one). Nights are cut at 18:00 in this zone.
    public var timeZoneIdentifier: String?

    public init(
        id: String, start: Date, end: Date, stage: Stage, origin: Origin, wasUserEntered: Bool = false,
        timeZoneIdentifier: String? = nil
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.stage = stage
        self.origin = origin
        self.wasUserEntered = wasUserEntered
        self.timeZoneIdentifier = timeZoneIdentifier
    }
}
