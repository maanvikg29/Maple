import Foundation

/// Places a sample on rewards.json's source ladder (`SleepSource`):
///
/// - (A) `.watchOrTracker`: asleep stages (and the awake time between them) from an Apple Watch, known by its
///   product type ("Watch…") or device model ("Watch"), or from an allow-listed hardware tracker's app.
/// - (B) `.otherApp`: asleep samples (and awake time) any other source wrote.
/// - (C) `.iPhoneInBed`: in-bed samples from Apple's own iPhone source, which its Sleep schedule writes ("estimated
///   from iPhone").
///
/// Samples typed in by hand (`HKMetadataKeyWasUserEntered`) never count, and neither does in-bed time from any
/// source but iPhone's own.
public struct SleepSourceResolver: Sendable {
    /// Hardware sleep trackers whose iPhone apps write the asleep stages their device measured.
    ///
    /// A LIST TO REVIEW: the bundle identifiers were taken from public App Store listings, not confirmed against
    /// each vendor's HealthKit source. Check them on a device (`HKSource.bundleIdentifier`) before relying on them;
    /// a tracker missing here still counts, as another app (B).
    public static let trackerBundleIdentifiers: Set<String> = [
        "com.ouraring.oura",            // Oura
        "com.whoop.iphone",             // WHOOP
        "com.withings.wiScaleNG",       // Withings (Health Mate)
        "com.fitbit.FitbitMobile",      // Fitbit
        "com.garmin.connect.mobile",    // Garmin Connect
        "com.eightsleep.Eight",         // Eight Sleep
        "fi.polar.polarflow",           // Polar Flow
    ]

    public var trackerBundleIdentifiers: Set<String>

    public init(trackerBundleIdentifiers: Set<String> = Self.trackerBundleIdentifiers) {
        self.trackerBundleIdentifiers = trackerBundleIdentifiers
    }

    /// The rung a sample counts on; nil when it never counts.
    public func source(of sample: SleepSample) -> SleepSource? {
        guard !sample.wasUserEntered else { return nil }
        let origin = sample.origin
        switch sample.stage {
        case .inBed:
            return isAppleIPhone(origin) ? .iPhoneInBed : nil
        case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM, .awake:
            return isAppleWatch(origin) || isTracker(origin) ? .watchOrTracker : .otherApp
        }
    }

    /// An Apple Watch measured it: its product type ("Watch7,1") or device model ("Watch").
    public func isAppleWatch(_ origin: SleepSample.Origin) -> Bool {
        if let product = origin.productType, product.hasPrefix("Watch") { return true }
        if let model = origin.deviceModel, model.hasPrefix("Watch") { return true }
        return false
    }

    /// An allow-listed hardware tracker's app wrote it.
    public func isTracker(_ origin: SleepSample.Origin) -> Bool {
        trackerBundleIdentifiers.contains(origin.bundleIdentifier)
    }

    /// Apple's own Health source on the iPhone (its Sleep schedule), not an app and not a Watch.
    public func isAppleIPhone(_ origin: SleepSample.Origin) -> Bool {
        guard origin.bundleIdentifier.hasPrefix("com.apple.health"), !isAppleWatch(origin) else { return false }
        if let product = origin.productType { return product.hasPrefix("iPhone") }
        return origin.deviceModel?.hasPrefix("iPhone") ?? false
    }
}
