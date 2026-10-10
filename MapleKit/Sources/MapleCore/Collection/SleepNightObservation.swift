import Foundation

/// Where a night's sleep came from: the source ladder of rewards.json's `nights_tracked` metric, best first.
/// M1's importer picks the best source available for each night (samples marked `HKMetadataKeyWasUserEntered`
/// never count) and hands the ledger one observation per night.
public enum SleepSource: String, Codable, Sendable, CaseIterable {
    /// (A) Asleep stages from an Apple Watch or an allow-listed hardware sleep tracker.
    case watchOrTracker
    /// (B) Asleep samples another app wrote to Apple Health. They count for leaves (and are left out of rarity
    /// reporting).
    case otherApp
    /// (C) "In bed" samples from iPhone's Sleep schedule, shown as "estimated from iPhone". They carry times but no
    /// asleep time, so they can't earn Full nights.
    case iPhoneInBed

    /// Higher is better: a night recorded from a better source replaces a worse one, never the other way round.
    public var rank: Int {
        switch self {
        case .watchOrTracker: 2
        case .otherApp: 1
        case .iPhoneInBed: 0
        }
    }

    /// The source measures time asleep (sources A and B), which Full nights need.
    public var hasAsleepTime: Bool { self != .iPhoneInBed }
}

/// One night of sleep as Apple Health tells it, already reduced to the night's main episode (the longest cluster
/// of samples, gaps under 60 minutes merged, naps ignored). Pure: M1's HealthKit importer builds these and passes
/// them to `CollectionStore.recordSleep(_:at:)`; `NightLedger` judges them against the member's schedule.
public struct SleepNightObservation: Codable, Sendable, Hashable {
    /// The night, named by the evening it began on (nights run 18:00 to 18:00 local).
    public var night: LocalDay
    /// Sleep onset: the start of the main episode's first asleep block of 20 minutes or more (sources A and B), or
    /// the in-bed start (source C).
    public var onset: Date
    /// Final wake: the end of the main episode's last asleep block (A and B), or the in-bed end (C).
    public var finalWake: Date
    /// Total time asleep in the main episode, in minutes; nil for iPhone in-bed data (C).
    public var asleepMinutes: Double?
    public var source: SleepSource
    /// The time zone the night was spent in (an identifier such as "America/New_York"; HealthKit's
    /// `HKMetadataKeyTimeZone` when the samples carry it). The night's bedtime and wake time are read in this zone,
    /// so flying before the night settles never moves them. Nil: the ledger stamps the zone in force when the night
    /// is recorded.
    public var timeZoneIdentifier: String?

    public init(
        night: LocalDay, onset: Date, finalWake: Date, asleepMinutes: Double?, source: SleepSource,
        timeZoneIdentifier: String? = nil
    ) {
        self.night = night
        self.onset = onset
        self.finalWake = finalWake
        self.asleepMinutes = source.hasAsleepTime ? asleepMinutes : nil
        self.source = source
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    /// An observation named by the night its onset falls in, spent in `calendar`'s time zone.
    public init(onset: Date, finalWake: Date, asleepMinutes: Double?, source: SleepSource, calendar: Calendar) {
        self.init(night: NightLedger.night(containing: onset, calendar: calendar), onset: onset, finalWake: finalWake,
                  asleepMinutes: asleepMinutes, source: source, timeZoneIdentifier: calendar.timeZone.identifier)
    }

    /// `calendar` in the zone the night was spent in, when that is known.
    func calendar(from calendar: Calendar) -> Calendar {
        guard let timeZoneIdentifier, let zone = TimeZone(identifier: timeZoneIdentifier),
              zone.identifier != calendar.timeZone.identifier else { return calendar }
        var local = calendar
        local.timeZone = zone
        return local
    }

    /// From onset to final wake.
    public var span: TimeInterval { finalWake.timeIntervalSince(onset) }

    /// A main episode of at least 3 hours, so the night can be tracked (rewards.json `nights_tracked`).
    public var isMainEpisode: Bool { span >= NightLedger.minimumEpisode }
}
