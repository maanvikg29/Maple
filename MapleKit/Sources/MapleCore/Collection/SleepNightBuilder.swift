import Foundation

/// Where one Apple Health sleep-analysis sample came from and what it says, without HealthKit types, so the source
/// ladder can be decided (and tested) in MapleCore. M1's importer fills it from each `HKCategorySample`.
public struct SleepSampleOrigin: Sendable, Hashable {
    /// The sample's sleep-analysis value.
    public enum Stage: Sendable, Hashable {
        /// Asleep, unspecified or a stage (core, deep, REM).
        case asleep
        case inBed
        case awake
    }

    public var stage: Stage
    /// The writing app's bundle identifier (`HKSource.bundleIdentifier`).
    public var bundleIdentifier: String
    /// The writing device's product type, such as "Watch7,1" (`HKSourceRevision.productType`).
    public var productType: String?
    /// The recording device's model, such as "Watch" (`HKDevice.model`).
    public var deviceModel: String?
    /// The sample carries `HKMetadataKeyWasUserEntered`: typed in by hand, so it never counts.
    public var wasUserEntered: Bool

    public init(stage: Stage, bundleIdentifier: String, productType: String? = nil, deviceModel: String? = nil,
                wasUserEntered: Bool = false) {
        self.stage = stage
        self.bundleIdentifier = bundleIdentifier
        self.productType = productType
        self.deviceModel = deviceModel
        self.wasUserEntered = wasUserEntered
    }

    /// Bundle identifiers of hardware sleep trackers whose asleep stages rank with Apple Watch's (source A).
    /// rewards.json names none yet, so other trackers' samples count as another app's (source B), which still earns
    /// every sleep leaf, Full nights included.
    public static let allowListedTrackers: Set<String> = []

    /// Apple's own Health sources (Apple Watch, iPhone's Sleep schedule).
    private var isApple: Bool { bundleIdentifier.hasPrefix("com.apple.health") }
    private var isAppleWatch: Bool {
        isApple && ((productType?.hasPrefix("Watch") ?? false) || deviceModel == "Watch")
    }

    /// The rung of the source ladder this sample can count for (rewards.json `nights_tracked`), or nil when it never
    /// counts: user-entered samples, awake stages, and in-bed samples from anything but Apple's Sleep schedule
    /// (Apple Watch's in-bed samples add nothing its asleep stages don't already say).
    public var source: SleepSource? {
        guard !wasUserEntered else { return nil }
        switch stage {
        case .awake:
            return nil
        case .asleep:
            return isAppleWatch || Self.allowListedTrackers.contains(bundleIdentifier) ? .watchOrTracker : .otherApp
        case .inBed:
            return isApple && !isAppleWatch ? .iPhoneInBed : nil
        }
    }
}

/// One sample that counts for sleep, already placed on the source ladder.
public struct SleepSample: Sendable, Hashable {
    public var start: Date
    public var end: Date
    /// Asleep time for sources A and B; in-bed time for C.
    public var source: SleepSource
    /// `HKMetadataKeyTimeZone`, when the sample carries it.
    public var timeZoneIdentifier: String?

    public init(start: Date, end: Date, source: SleepSource, timeZoneIdentifier: String? = nil) {
        self.start = start
        self.end = end
        self.source = source
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    /// The sample if its origin counts for sleep (see `SleepSampleOrigin.source`), else nil.
    public init?(start: Date, end: Date, origin: SleepSampleOrigin, timeZoneIdentifier: String? = nil) {
        guard let source = origin.source, end > start else { return nil }
        self.init(start: start, end: end, source: source, timeZoneIdentifier: timeZoneIdentifier)
    }
}

/// Turns Apple Health's sleep samples into one `SleepNightObservation` per night (rewards.json `nights_tracked`).
/// Pure, so it is tested without HealthKit; M1's importer feeds it and passes the result to
/// `CollectionStore.recordSleep(_:at:)`.
///
/// - Each source rung (A, B, C) is read on its own. Its samples are clustered, merging gaps under 60 minutes; a
///   cluster belongs to the night (18:00 to 18:00) its first sample starts in, read in the sample's own time zone
///   when it has one. A night's main episode for that rung is its longest cluster, and naps (any shorter cluster)
///   are ignored.
/// - A night takes the best rung whose main episode lasts 3 hours or more; a night with none is left out (the
///   ledger settles it untracked).
/// - Sources A and B: onset is the start of the episode's first asleep block of 20 minutes or more (asleep samples
///   that overlap or are under a minute apart form a block), final wake the end of its last asleep block, and asleep
///   time the minutes its blocks cover (overlaps counted once). Source C: the in-bed start and end, with no
///   asleep time.
public struct SleepNightBuilder: Sendable {
    /// Gaps shorter than this inside an episode are merged (rewards.json: under 60 minutes).
    public static let episodeGap: TimeInterval = 60 * 60
    /// Sleep onset is the first asleep block at least this long.
    public static let onsetBlock: TimeInterval = 20 * 60
    /// Samples closer than this are one asleep block (stages are written back to back, sometimes a second apart).
    static let blockJoin: TimeInterval = 60

    /// The calendar for nights whose samples carry no time zone (the member's current one).
    public var calendar: Calendar

    public init(calendar: Calendar) {
        self.calendar = calendar
    }

    /// One observation per night, oldest first.
    public func observations(from samples: [SleepSample]) -> [SleepNightObservation] {
        var best: [LocalDay: SleepNightObservation] = [:]
        for source in SleepSource.allCases {
            let ofSource = samples.filter { $0.source == source }
            for episode in mainEpisodes(of: ofSource) {
                guard let observation = observation(of: episode, source: source), observation.isMainEpisode else { continue }
                if let current = best[observation.night], current.source.rank >= source.rank { continue }
                best[observation.night] = observation
            }
        }
        return best.values.sorted { $0.night < $1.night }
    }

    // MARK: Private

    /// The longest cluster of each night, by the night its first sample starts in.
    private func mainEpisodes(of samples: [SleepSample]) -> [[SleepSample]] {
        var longest: [LocalDay: [SleepSample]] = [:]
        for cluster in clusters(of: samples) {
            guard let first = cluster.first else { continue }
            let night = NightLedger.night(containing: first.start, calendar: calendar(for: first))
            if let current = longest[night], span(of: current) >= span(of: cluster) { continue }
            longest[night] = cluster
        }
        return Array(longest.values)
    }

    /// Samples sorted by start, split wherever the gap since everything before reaches `episodeGap`.
    private func clusters(of samples: [SleepSample]) -> [[SleepSample]] {
        var clusters: [[SleepSample]] = []
        var current: [SleepSample] = []
        var currentEnd = Date.distantPast
        for sample in samples.sorted(by: { ($0.start, $0.end) < ($1.start, $1.end) }) {
            if !current.isEmpty, sample.start.timeIntervalSince(currentEnd) >= Self.episodeGap {
                clusters.append(current)
                current = []
            }
            if current.isEmpty { currentEnd = sample.end }
            current.append(sample)
            currentEnd = max(currentEnd, sample.end)
        }
        if !current.isEmpty { clusters.append(current) }
        return clusters
    }

    private func observation(of episode: [SleepSample], source: SleepSource) -> SleepNightObservation? {
        guard let first = episode.first else { return nil }
        let calendar = calendar(for: first)
        let night = NightLedger.night(containing: first.start, calendar: calendar)
        let zone = first.timeZoneIdentifier ?? calendar.timeZone.identifier
        let blocks = Self.blocks(of: episode)
        guard let start = blocks.first?.lowerBound, let end = blocks.last?.upperBound else { return nil }
        guard source.hasAsleepTime else {
            return SleepNightObservation(night: night, onset: start, finalWake: end, asleepMinutes: nil, source: source,
                                         timeZoneIdentifier: zone)
        }
        let onset = blocks.first { $0.upperBound.timeIntervalSince($0.lowerBound) >= Self.onsetBlock }?.lowerBound ?? start
        let asleep = blocks.reduce(0) { $0 + $1.upperBound.timeIntervalSince($1.lowerBound) }
        return SleepNightObservation(night: night, onset: onset, finalWake: end, asleepMinutes: asleep / 60, source: source,
                                     timeZoneIdentifier: zone)
    }

    /// Samples merged into blocks where they overlap or are under a minute apart, in order.
    static func blocks(of samples: [SleepSample]) -> [ClosedRange<Date>] {
        var blocks: [ClosedRange<Date>] = []
        for sample in samples.sorted(by: { $0.start < $1.start }) {
            if let last = blocks.last, sample.start.timeIntervalSince(last.upperBound) < blockJoin {
                blocks[blocks.count - 1] = last.lowerBound...max(last.upperBound, sample.end)
            } else {
                blocks.append(sample.start...sample.end)
            }
        }
        return blocks
    }

    private func span(of cluster: [SleepSample]) -> TimeInterval {
        guard let start = cluster.map(\.start).min(), let end = cluster.map(\.end).max() else { return 0 }
        return end.timeIntervalSince(start)
    }

    /// `calendar` in the sample's own time zone, when it has one.
    private func calendar(for sample: SleepSample) -> Calendar {
        guard let identifier = sample.timeZoneIdentifier, let zone = TimeZone(identifier: identifier) else { return calendar }
        var local = calendar
        local.timeZone = zone
        return local
    }
}
