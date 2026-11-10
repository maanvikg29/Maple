#if DEBUG
import Foundation
import HealthKit
import MapleCore
import os

/// DEBUG only: `-MapleDemoSeedHealth <nights>` (with `-MapleDemoSeedSource watch|iphone|otherApp`, Watch by default)
/// writes plausible synthetic sleep for the last N nights into the simulator's Apple Health, so the importer can be
/// run end to end without a Watch (docs/debug-launch-arguments.md). Release builds contain none of this.
///
/// Writing needs Apple's sheet asking to write sleep, which only a tap answers. Automated runs add
/// `-MapleDemoSeedStore memory` to a demo launch instead: the same samples start the importer's in-memory cache, as
/// if just read from Apple Health, and are recorded before the first frame (`HealthSleepImporter.seedInMemory`).
///
/// Nights follow the saved schedule with realistic variation: most on time, some late, some short. The samples carry
/// `metadataKey` (the source they stand for), which DEBUG mapping turns into that source's origin, so a seeded Watch
/// night reads as an Apple Watch. Seeding again first deletes what an earlier seeding wrote (only Maple's own
/// seeded samples; HealthKit lets an app delete nothing else), which the importer then sees as deleted samples.
public enum HealthSleepSeeder {
    nonisolated public static let metadataKey = "MapleDemoSeedSource"
    private static var logger: Logger { Logger(subsystem: "com.maanvikgupta.maple", category: "health") }

    /// The source a seeded night stands for.
    nonisolated public enum Source: String, Sendable, CaseIterable {
        case watch
        case iphone
        case otherApp

        /// The origin DEBUG mapping gives a sample seeded as this source.
        public var origin: SleepSample.Origin {
            switch self {
            case .watch:
                SleepSample.Origin(bundleIdentifier: "com.apple.health.demo-watch", name: "Apple Watch", productType: "Watch7,1",
                                   deviceName: "Apple Watch", deviceModel: "Watch", deviceManufacturer: "Apple Inc.")
            case .iphone:
                SleepSample.Origin(bundleIdentifier: "com.apple.health.demo-iphone", name: "iPhone", productType: "iPhone18,5",
                                   deviceName: "iPhone", deviceModel: "iPhone", deviceManufacturer: "Apple Inc.")
            case .otherApp:
                SleepSample.Origin(bundleIdentifier: "com.example.sleepdiary", name: "Sleep Diary", productType: "iPhone18,5")
            }
        }
    }

    /// Where seeded samples go.
    nonisolated public enum Store: String, Sendable, CaseIterable {
        /// The simulator's Apple Health, after Apple's sheet asking to write sleep (it needs a tap).
        case health
        /// No HealthKit at all: the importer's in-memory cache starts with the samples, as if just read from Apple
        /// Health, so automated runs need no tap. Only on demo launches (every store in memory).
        case memory
    }

    /// What the launch arguments ask for; nil without `-MapleDemoSeedHealth`.
    nonisolated public struct Options: Sendable, Equatable {
        public var nights: Int
        public var source: Source
        public var store: Store

        public init(nights: Int, source: Source = .watch, store: Store = .health) {
            self.nights = nights
            self.source = source
            self.store = store
        }

        public init?(arguments: [String]) {
            func value(_ key: String) -> String? {
                guard let index = arguments.firstIndex(of: "-\(key)"), arguments.indices.contains(index + 1) else { return nil }
                return arguments[index + 1]
            }
            guard let nights = value("MapleDemoSeedHealth").flatMap(Int.init), nights > 0 else { return nil }
            self.nights = min(nights, 60)
            source = value("MapleDemoSeedSource").flatMap { text in
                Source.allCases.first { $0.rawValue.lowercased() == text.lowercased() }
            } ?? .watch
            store = value("MapleDemoSeedStore").flatMap { Store(rawValue: $0.lowercased()) } ?? .health
        }

        public static var current: Options? { Options(arguments: ProcessInfo.processInfo.arguments) }
    }

    /// One sample to write.
    nonisolated public struct Planned: Sendable, Equatable {
        public var start: Date
        public var end: Date
        public var stage: SleepSample.Stage
    }

    // MARK: Plan (pure)

    /// The last `nights` complete nights before `now` under `schedule`, as samples for `source`.
    /// - Parameter notBefore: Nothing starts before this (when Maple was set up): a night under way then begins
    ///   after it, as it would for someone who set Maple up and then went to bed.
    nonisolated public static func plan(
        nights: Int, source: Source, schedule: WeeklySleepSchedule, now: Date, calendar: Calendar, notBefore: Date? = nil
    ) -> [Planned] {
        var last = SleepNightBuilder.night(containing: now, calendar: calendar)
        if night(last, schedule: schedule, calendar: calendar, notBefore: notBefore).wake > now {
            last = last.adding(days: -1, calendar: calendar)
        }
        var samples: [Planned] = []
        for back in stride(from: nights - 1, through: 0, by: -1) {
            let evening = last.adding(days: -back, calendar: calendar)
            let times = night(evening, schedule: schedule, calendar: calendar, notBefore: notBefore)
            guard times.wake > times.onset.addingTimeInterval(3600) else { continue }
            var random = SeededRandom(evening)
            switch source {
            case .watch: samples += watchStages(times, random: &random)
            case .iphone:
                samples.append(Planned(start: times.inBed, end: times.wake.addingTimeInterval(random.minutes(3...8)), stage: .inBed))
            case .otherApp:
                samples.append(Planned(start: times.onset, end: times.wake, stage: .asleepUnspecified))
            }
        }
        return samples
    }

    /// The plan as the importer would read it from Apple Health (`-MapleDemoSeedStore memory`): the source's
    /// origin, the calendar's zone, and ids that are the same on every launch.
    nonisolated public static func samples(
        nights: Int, source: Source, schedule: WeeklySleepSchedule, now: Date, calendar: Calendar, notBefore: Date? = nil
    ) -> [SleepSample] {
        plan(nights: nights, source: source, schedule: schedule, now: now, calendar: calendar, notBefore: notBefore)
            .map { planned in
                SleepSample(
                    id: "seed-\(source.rawValue)-\(Int(planned.start.timeIntervalSince1970))-\(planned.stage.rawValue)",
                    start: planned.start, end: planned.end, stage: planned.stage, origin: source.origin,
                    timeZoneIdentifier: calendar.timeZone.identifier
                )
            }
    }

    /// One night's in-bed start, sleep onset and wake, varied around the schedule.
    nonisolated private static func night(
        _ evening: LocalDay, schedule: WeeklySleepSchedule, calendar: Calendar, notBefore: Date?
    ) -> (inBed: Date, onset: Date, wake: Date) {
        var random = SeededRandom(evening)
        let tonight = schedule.schedule(forNight: evening, calendar: calendar)
        let bedtime = NightLedger.date(tonight.bedtime, on: evening, calendar: calendar)
        let wakeTime = NightLedger.date(tonight.wake, on: evening, calendar: calendar)
        // Each week has one late night, one short night and one early one; the rest stay close to the schedule.
        let weekSlot = ((Int(evening.startDate(in: calendar).timeIntervalSince1970 / 86_400) % 7) + 7) % 7
        let onsetShift: TimeInterval
        let wakeShift: TimeInterval
        switch weekSlot {
        case 4:     // a late night
            onsetShift = random.minutes(50...100)
            wakeShift = random.minutes(0...25)
        case 1:     // a short night: up early
            onsetShift = random.minutes(-10...20)
            wakeShift = -random.minutes(60...110)
        case 6:     // an early night, still on time
            onsetShift = -random.minutes(20...45)
            wakeShift = -random.minutes(0...15)
        default:    // most nights: close to the schedule
            onsetShift = random.minutes(-20...25)
            wakeShift = random.minutes(-20...20)
        }
        var inBed = bedtime.addingTimeInterval(onsetShift - random.minutes(5...15))
        var onset = bedtime.addingTimeInterval(onsetShift)
        let wake = wakeTime.addingTimeInterval(wakeShift)
        if let notBefore, inBed < notBefore, wake > notBefore {
            inBed = notBefore.addingTimeInterval(random.minutes(5...10))
            onset = inBed.addingTimeInterval(random.minutes(8...15))
        }
        return (inBed, onset, wake)
    }

    /// Watch-like stages: lying awake, then ~90-minute cycles (more deep sleep early, more REM late) with brief
    /// awakenings, then awake after the final wake.
    nonisolated private static func watchStages(_ times: (inBed: Date, onset: Date, wake: Date), random: inout SeededRandom) -> [Planned] {
        var samples = [Planned(start: times.inBed, end: times.onset, stage: .awake)]
        var cursor = times.onset
        var cycle = 0
        func add(_ stage: SleepSample.Stage, _ minutes: TimeInterval) {
            guard cursor < times.wake else { return }
            let end = min(times.wake, cursor.addingTimeInterval(minutes))
            samples.append(Planned(start: cursor, end: end, stage: stage))
            cursor = end
        }
        while cursor < times.wake {
            add(.asleepCore, random.minutes(35...50))
            add(.asleepDeep, cycle < 3 ? random.minutes(15...30) : random.minutes(0...8))
            add(.asleepCore, random.minutes(8...15))
            add(.asleepREM, cycle < 2 ? random.minutes(8...18) : random.minutes(20...35))
            if random.unit() < 0.35 { add(.awake, random.minutes(2...6)) }
            cycle += 1
        }
        if let last = samples.last, last.stage == .awake, last.end == times.wake {
            // End on sleep, so the final wake is the schedule's (an awakening right at the end is the waking itself).
            samples[samples.count - 1].stage = .asleepCore
        }
        samples.append(Planned(start: times.wake, end: times.wake.addingTimeInterval(random.minutes(5...12)), stage: .awake))
        return samples.filter { $0.end > $0.start }
    }

    // MARK: Writing

    /// Asks for Apple Health access to write (and read) sleep, deletes what an earlier seeding wrote, and writes the
    /// planned samples.
    /// - Returns: How many samples were written.
    @discardableResult
    public static func seed(
        _ options: Options, schedule: WeeklySleepSchedule, now: Date, calendar: Calendar, notBefore: Date?
    ) async throws -> Int {
        guard HKHealthStore.isHealthDataAvailable() else { return 0 }
        let store = HKHealthStore()
        let type = HKCategoryType(.sleepAnalysis)
        try await store.requestAuthorization(toShare: [type], read: [type])
        let removed = try await store.deleteObjects(of: type, predicate: HKQuery.predicateForObjects(withMetadataKey: metadataKey))
        let plan = plan(nights: options.nights, source: options.source, schedule: schedule, now: now, calendar: calendar,
                        notBefore: notBefore)
        let device: HKDevice? = switch options.source {
        case .watch:
            HKDevice(name: "Apple Watch", manufacturer: "Apple Inc.", model: "Watch", hardwareVersion: "Watch7,1",
                     firmwareVersion: nil, softwareVersion: nil, localIdentifier: nil, udiDeviceIdentifier: nil)
        case .iphone, .otherApp:
            nil
        }
        let samples = plan.map { planned in
            HKCategorySample(
                type: type, value: value(of: planned.stage).rawValue, start: planned.start, end: planned.end, device: device,
                metadata: [metadataKey: options.source.rawValue, HKMetadataKeyTimeZone: calendar.timeZone.identifier]
            )
        }
        if !samples.isEmpty { try await store.save(samples) }
        logger.notice("Seeded \(samples.count) \(options.source.rawValue, privacy: .public) sleep samples for \(options.nights) nights (removed \(removed))")
        return samples.count
    }

    nonisolated private static func value(of stage: SleepSample.Stage) -> HKCategoryValueSleepAnalysis {
        switch stage {
        case .inBed: .inBed
        case .asleepUnspecified: .asleepUnspecified
        case .asleepCore: .asleepCore
        case .asleepDeep: .asleepDeep
        case .asleepREM: .asleepREM
        case .awake: .awake
        }
    }
}

/// A small deterministic generator (SplitMix64), seeded by the night, so a night seeds the same way every time.
nonisolated private struct SeededRandom {
    private var state: UInt64

    init(_ night: LocalDay) {
        state = UInt64(night.year * 10_000 + night.month * 100 + night.day) &* 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// In 0..<1.
    mutating func unit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    /// A whole number of minutes in `range`, in seconds.
    mutating func minutes(_ range: ClosedRange<Int>) -> TimeInterval {
        TimeInterval(range.lowerBound + Int(unit() * Double(range.count))) * 60
    }
}
#endif
