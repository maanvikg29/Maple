import Foundation
import Testing
@testable import MapleCore

// Who wrote a sample, as HealthKit reports it.
private let watch = SleepSample.Origin(
    bundleIdentifier: "com.apple.health.81C2A0F4", name: "Apple Watch", productType: "Watch7,1",
    deviceName: "Apple Watch", deviceModel: "Watch", deviceManufacturer: "Apple Inc."
)
private let iPhone = SleepSample.Origin(
    bundleIdentifier: "com.apple.health.5F1A77B0", name: "iPhone", productType: "iPhone17,1",
    deviceName: "iPhone", deviceModel: "iPhone", deviceManufacturer: "Apple Inc."
)
private let otherApp = SleepSample.Origin(bundleIdentifier: "com.example.sleepdiary", name: "Sleep Diary", productType: "iPhone17,1")
private let oura = SleepSample.Origin(bundleIdentifier: "com.ouraring.oura", name: "Oura", productType: "iPhone17,1")

/// One HealthKit sample from `start` to `end` (UTC unless a calendar is given).
private func sample(
    _ stage: SleepSample.Stage, _ start: Date, _ end: Date, _ origin: SleepSample.Origin = watch,
    userEntered: Bool = false, zone: String? = nil, id: String? = nil
) -> SleepSample {
    SleepSample(id: id ?? UUID().uuidString, start: start, end: end, stage: stage, origin: origin,
                       wasUserEntered: userEntered, timeZoneIdentifier: zone)
}

private func day(_ month: Int, _ day: Int, _ year: Int = 2026) -> LocalDay { LocalDay(year: year, month: month, day: day) }

/// A Watch night for the evening of 9 October: asleep stages from 23:10 to 06:50 with two short awakenings.
private func watchNight() -> [SleepSample] {
    [
        sample(.awake, at(2026, 10, 9, 23, 0), at(2026, 10, 9, 23, 10)),
        sample(.asleepCore, at(2026, 10, 9, 23, 10), at(2026, 10, 10, 0, 30)),
        sample(.asleepDeep, at(2026, 10, 10, 0, 30), at(2026, 10, 10, 1, 30)),
        sample(.awake, at(2026, 10, 10, 1, 30), at(2026, 10, 10, 1, 40)),
        sample(.asleepREM, at(2026, 10, 10, 1, 40), at(2026, 10, 10, 3, 0)),
        sample(.asleepCore, at(2026, 10, 10, 3, 0), at(2026, 10, 10, 6, 50)),
        sample(.awake, at(2026, 10, 10, 6, 50), at(2026, 10, 10, 7, 5)),
    ]
}

@Suite("Apple Health samples to nights")
struct SleepNightBuilderTests {
    private let builder = SleepNightBuilder(calendar: utc)

    // MARK: Sources

    @Test("The source ladder: Watch and allow-listed trackers, other apps, iPhone's in-bed estimate")
    func sourceLadder() {
        let resolver = SleepSourceResolver()
        let start = at(2026, 10, 9, 23), end = at(2026, 10, 10, 7)
        #expect(resolver.source(of: sample(.asleepCore, start, end, watch)) == .watchOrTracker)
        #expect(resolver.source(of: sample(.awake, start, end, watch)) == .watchOrTracker)
        // A Watch is known by its product type or by its device model.
        let byProduct = SleepSample.Origin(bundleIdentifier: "com.apple.health.1", name: "Watch", productType: "Watch6,2")
        let byModel = SleepSample.Origin(bundleIdentifier: "com.apple.health.2", name: "Watch", deviceModel: "Watch")
        #expect(resolver.source(of: sample(.asleepUnspecified, start, end, byProduct)) == .watchOrTracker)
        #expect(resolver.source(of: sample(.asleepUnspecified, start, end, byModel)) == .watchOrTracker)
        #expect(resolver.source(of: sample(.asleepDeep, start, end, oura)) == .watchOrTracker)
        #expect(resolver.source(of: sample(.asleepUnspecified, start, end, otherApp)) == .otherApp)
        #expect(resolver.source(of: sample(.inBed, start, end, iPhone)) == .iPhoneInBed)
        // In-bed time from anything but iPhone's own Sleep schedule, and anything typed in, never counts.
        #expect(resolver.source(of: sample(.inBed, start, end, otherApp)) == nil)
        #expect(resolver.source(of: sample(.inBed, start, end, watch)) == nil)
        #expect(resolver.source(of: sample(.asleepCore, start, end, watch, userEntered: true)) == nil)
        #expect(resolver.source(of: sample(.inBed, start, end, iPhone, userEntered: true)) == nil)
        // The allow-list can be replaced (it is a list to review).
        let none = SleepSourceResolver(trackerBundleIdentifiers: [])
        #expect(none.source(of: sample(.asleepDeep, start, end, oura)) == .otherApp)
        #expect(SleepSourceResolver.trackerBundleIdentifiers.contains("com.ouraring.oura"))
    }

    // MARK: One night

    @Test("A Watch night: onset at its first 20-minute block, final wake at its last, awake time left out")
    func watchNightObservation() throws {
        let nights = builder.nights(from: watchNight())
        let night = try #require(nights.first)
        #expect(nights.count == 1)
        #expect(night.night == day(10, 9))
        #expect(night.source == .watchOrTracker)
        #expect(night.onset == at(2026, 10, 9, 23, 10))
        #expect(night.finalWake == at(2026, 10, 10, 6, 50))
        // 7h 40m from onset to wake, less the 10-minute awakening.
        #expect(night.asleepMinutes == 450)
        #expect(night.timeZoneIdentifier == utc.timeZone.identifier)
        #expect(night.isMainEpisode)
    }

    @Test("Samples after midnight belong to the evening before; the night turns at 18:00")
    func boundaries() throws {
        // All after midnight: still the night of the 9th.
        let late = builder.nights(from: [sample(.asleepCore, at(2026, 10, 10, 1, 30), at(2026, 10, 10, 8))])
        #expect(late.map(\.night) == [day(10, 9)])
        // 17:59 is the night before; 18:00 starts the new one.
        #expect(SleepNightBuilder.night(containing: at(2026, 10, 10, 17, 59), calendar: utc) == day(10, 9))
        #expect(SleepNightBuilder.night(containing: at(2026, 10, 10, 18), calendar: utc) == day(10, 10))
        #expect(SleepNightBuilder.eveningStart(of: day(10, 10), calendar: utc) == at(2026, 10, 10, 18))
        // A sample across 18:00 is cut there: an early night keeps only what falls after 18:00.
        let early = builder.nights(from: [sample(.asleepUnspecified, at(2026, 10, 10, 17, 30), at(2026, 10, 11, 2))])
        let first = try #require(early.first { $0.night == day(10, 10) })
        #expect(first.onset == at(2026, 10, 10, 18))
        #expect(first.asleepMinutes == 480)
        #expect(early.first { $0.night == day(10, 9) }?.asleepMinutes == 30)
    }

    @Test("Naps are ignored: the night's longest cluster is its main episode")
    func naps() throws {
        let samples = watchNight() + [
            // An afternoon nap the next day still falls in the night of the 9th (before 18:00) and loses to it.
            sample(.asleepCore, at(2026, 10, 10, 14), at(2026, 10, 10, 15, 10)),
            // An evening doze more than an hour before bed is its own cluster.
            sample(.asleepCore, at(2026, 10, 9, 20), at(2026, 10, 9, 21, 30)),
        ]
        let night = try #require(builder.nights(from: samples).first)
        #expect(night.onset == at(2026, 10, 9, 23, 10))
        #expect(night.finalWake == at(2026, 10, 10, 6, 50))
        #expect(night.asleepMinutes == 450)

        // A nap on its own is a short, untracked episode.
        let napOnly = try #require(builder.nights(from: [sample(.asleepCore, at(2026, 10, 10, 14), at(2026, 10, 10, 15))]).first)
        #expect(!napOnly.isMainEpisode)
    }

    @Test("A split night: gaps under 60 minutes are merged, longer gaps split it and the longer part wins")
    func splitNights() throws {
        let merged = try #require(builder.nights(from: [
            sample(.asleepCore, at(2026, 10, 9, 23), at(2026, 10, 10, 2)),
            sample(.asleepCore, at(2026, 10, 10, 2, 59), at(2026, 10, 10, 7)),
        ]).first)
        #expect(merged.onset == at(2026, 10, 9, 23))
        #expect(merged.finalWake == at(2026, 10, 10, 7))
        #expect(merged.asleepMinutes == 421)   // 3h + 4h 1m

        let split = try #require(builder.nights(from: [
            sample(.asleepCore, at(2026, 10, 9, 22), at(2026, 10, 9, 23, 30)),
            sample(.asleepCore, at(2026, 10, 10, 1), at(2026, 10, 10, 6)),
        ]).first)
        #expect(split.onset == at(2026, 10, 10, 1))
        #expect(split.finalWake == at(2026, 10, 10, 6))
        #expect(split.asleepMinutes == 300)

        // Exactly 60 minutes is not "under 60".
        let hour = try #require(builder.nights(from: [
            sample(.asleepCore, at(2026, 10, 9, 22), at(2026, 10, 10, 1)),
            sample(.asleepCore, at(2026, 10, 10, 2), at(2026, 10, 10, 6)),
        ]).first)
        #expect(hour.onset == at(2026, 10, 10, 2))
    }

    @Test("Awake time inside an asleep sample is left out of the minutes asleep")
    func awakeExcluded() throws {
        let night = try #require(builder.nights(from: [
            sample(.asleepUnspecified, at(2026, 10, 9, 23), at(2026, 10, 10, 7), otherApp),
            sample(.awake, at(2026, 10, 10, 3), at(2026, 10, 10, 3, 30), otherApp),
            sample(.awake, at(2026, 10, 10, 6, 40), at(2026, 10, 10, 7, 15), otherApp),
        ]).first)
        #expect(night.source == .otherApp)
        #expect(night.asleepMinutes == 430)   // 480, less 30 and 20 awake
        // The last asleep block ends where the final awakening begins.
        #expect(night.finalWake == at(2026, 10, 10, 6, 40))
    }

    @Test("Onset is the first asleep block of 20 minutes or more")
    func onsetRule() throws {
        let night = try #require(builder.nights(from: [
            sample(.asleepCore, at(2026, 10, 9, 22, 30), at(2026, 10, 9, 22, 40)),
            sample(.awake, at(2026, 10, 9, 22, 40), at(2026, 10, 9, 23)),
            sample(.asleepCore, at(2026, 10, 9, 23), at(2026, 10, 9, 23, 19)),
            sample(.awake, at(2026, 10, 9, 23, 19), at(2026, 10, 9, 23, 25)),
            sample(.asleepCore, at(2026, 10, 9, 23, 25), at(2026, 10, 10, 6, 30)),
        ]).first)
        #expect(night.onset == at(2026, 10, 9, 23, 25))
        // Asleep minutes still count the short blocks.
        #expect(night.asleepMinutes == 454)   // 10 + 19 + 425

        // Stages written back to back are one block, even with a few seconds between them.
        let joined = try #require(builder.nights(from: [
            sample(.asleepCore, at(2026, 10, 9, 23), at(2026, 10, 9, 23, 12)),
            sample(.asleepDeep, at(2026, 10, 9, 23, 12, 30), at(2026, 10, 9, 23, 30)),
            sample(.asleepCore, at(2026, 10, 9, 23, 31), at(2026, 10, 10, 6)),
        ]).first)
        #expect(joined.onset == at(2026, 10, 9, 23))

        // With no block that long, onset falls back to the first asleep block.
        let fragmented = try #require(builder.nights(from: [
            sample(.asleepCore, at(2026, 10, 9, 23), at(2026, 10, 9, 23, 15)),
            sample(.awake, at(2026, 10, 9, 23, 15), at(2026, 10, 9, 23, 20)),
            sample(.asleepCore, at(2026, 10, 9, 23, 20), at(2026, 10, 9, 23, 35)),
        ]).first)
        #expect(fragmented.onset == at(2026, 10, 9, 23))
        #expect(fragmented.finalWake == at(2026, 10, 9, 23, 35))
    }

    @Test("iPhone's in-bed estimate gives times only")
    func iPhoneOnly() throws {
        let night = try #require(builder.nights(from: [
            sample(.inBed, at(2026, 10, 9, 22, 50), at(2026, 10, 10, 1, 10), iPhone),
            sample(.inBed, at(2026, 10, 10, 1, 40), at(2026, 10, 10, 6, 55), iPhone),
        ]).first)
        #expect(night.source == .iPhoneInBed)
        #expect(night.onset == at(2026, 10, 9, 22, 50))
        #expect(night.finalWake == at(2026, 10, 10, 6, 55))
        #expect(night.asleepMinutes == nil)
    }

    @Test("Another app's asleep samples count, as source B")
    func otherAppOnly() throws {
        let night = try #require(builder.nights(from: [
            sample(.asleepUnspecified, at(2026, 10, 9, 23, 30), at(2026, 10, 10, 6, 30), otherApp),
        ]).first)
        #expect(night.source == .otherApp)
        #expect(night.asleepMinutes == 420)
    }

    @Test("The best source wins the night, and sources are never mixed")
    func bestSource() throws {
        let iPhoneNight = [sample(.inBed, at(2026, 10, 9, 22, 30), at(2026, 10, 10, 7, 30), iPhone)]
        let appNight = [sample(.asleepUnspecified, at(2026, 10, 9, 22, 45), at(2026, 10, 10, 7, 10), otherApp)]

        let watchWins = try #require(builder.nights(from: watchNight() + iPhoneNight + appNight).first)
        #expect(watchWins.source == .watchOrTracker)
        #expect(watchWins.onset == at(2026, 10, 9, 23, 10))
        #expect(watchWins.asleepMinutes == 450)

        let appWins = try #require(builder.nights(from: iPhoneNight + appNight).first)
        #expect(appWins.source == .otherApp)
        #expect(appWins.onset == at(2026, 10, 9, 22, 45))

        // A Watch that only caught a nap doesn't beat iPhone's whole night: a main episode comes first.
        let napWatch = [sample(.asleepCore, at(2026, 10, 10, 13), at(2026, 10, 10, 14))]
        let iPhoneWins = try #require(builder.nights(from: napWatch + iPhoneNight).first)
        #expect(iPhoneWins.source == .iPhoneInBed)

        // Two trackers on one night: the one with more sleep, never a blend of both.
        let ouraNight = [sample(.asleepDeep, at(2026, 10, 9, 22), at(2026, 10, 10, 7, 30), oura)]
        let blended = try #require(builder.nights(from: watchNight() + ouraNight).first)
        #expect(blended.source == .watchOrTracker)
        #expect(blended.onset == at(2026, 10, 9, 22))
        #expect(blended.asleepMinutes == 570)
    }

    @Test("Samples typed in by hand never count")
    func userEnteredDropped() throws {
        let typed = watchNight().map { sample -> SleepSample in
            var copy = sample
            copy.wasUserEntered = true
            return copy
        }
        #expect(builder.nights(from: typed).isEmpty)
        // A typed-in sample next to real ones changes nothing.
        let mixed = watchNight() + [sample(.asleepUnspecified, at(2026, 10, 9, 21), at(2026, 10, 10, 9), otherApp, userEntered: true)]
        let night = try #require(builder.nights(from: mixed).first)
        #expect(night.source == .watchOrTracker)
        #expect(night.asleepMinutes == 450)
    }

    @Test("Deleted samples: the night is rebuilt from what is left")
    func deletedSamples() throws {
        let iPhoneNight = [sample(.inBed, at(2026, 10, 9, 22, 30), at(2026, 10, 10, 7, 30), iPhone)]
        let all = watchNight() + iPhoneNight
        #expect(builder.nights(from: all).first?.source == .watchOrTracker)
        let watchIDs = Set(watchNight().map(\.id))
        let afterDelete = all.filter { $0.origin != watch }
        #expect(watchIDs.count == 7)
        #expect(builder.nights(from: afterDelete).first?.source == .iPhoneInBed)
        #expect(builder.nights(from: []).isEmpty)
    }

    @Test("Several nights come back one per night, oldest first")
    func severalNights() {
        var samples: [SleepSample] = []
        for offset in 0..<5 {
            let evening = day(10, 5).adding(days: offset, calendar: utc)
            let start = SleepNightBuilder.eveningStart(of: evening, calendar: utc).addingTimeInterval(5 * 3600)
            samples.append(sample(.asleepCore, start, start.addingTimeInterval(7 * 3600)))
            samples.append(sample(.inBed, start.addingTimeInterval(-600), start.addingTimeInterval(7.5 * 3600), iPhone))
        }
        let nights = builder.nights(from: samples.shuffled())
        #expect(nights.map(\.night) == (0..<5).map { day(10, 5).adding(days: $0, calendar: utc) })
        #expect(nights.allSatisfy { $0.source == .watchOrTracker && $0.asleepMinutes == 420 })
    }

    // MARK: Time zones

    @Test("Daylight saving: a short spring night and a long autumn one, judged in local time")
    func daylightSaving() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let local = SleepNightBuilder(calendar: newYork)

        // Clocks go forward at 02:00 on 8 March 2026: 23:00 to 07:00 is seven hours asleep.
        let spring = try #require(local.nights(from: [
            sample(.asleepCore, at(2026, 3, 7, 23, in: newYork), at(2026, 3, 8, 7, in: newYork)),
        ]).first)
        #expect(spring.night == day(3, 7))
        #expect(spring.asleepMinutes == 420)
        #expect(spring.timeZoneIdentifier == "America/New_York")
        // The next night still starts at 18:00 local, after the change.
        #expect(SleepNightBuilder.night(containing: at(2026, 3, 8, 18, 30, in: newYork), calendar: newYork) == day(3, 8))
        #expect(SleepNightBuilder.night(containing: at(2026, 3, 8, 17, 30, in: newYork), calendar: newYork) == day(3, 7))

        // Clocks go back at 02:00 on 1 November 2026: 23:00 to 07:00 is nine hours.
        let autumn = try #require(local.nights(from: [
            sample(.asleepCore, at(2026, 10, 31, 23, in: newYork), at(2026, 11, 1, 7, in: newYork)),
        ]).first)
        #expect(autumn.night == day(10, 31))
        #expect(autumn.asleepMinutes == 540)
        #expect(SleepNightBuilder.night(containing: at(2026, 11, 1, 17, 30, in: newYork), calendar: newYork) == day(10, 31))
    }

    @Test("A sample's own time zone names its night and travels with the observation")
    func timeZoneMetadata() throws {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        // 23:00 to 07:00 in Tokyo is 14:00 to 22:00 UTC: before 18:00 UTC, but the evening of the 9th in Tokyo.
        let night = try #require(builder.nights(from: [
            sample(.asleepCore, at(2026, 10, 9, 23, in: tokyo), at(2026, 10, 10, 7, in: tokyo), zone: "Asia/Tokyo"),
        ]).first)
        #expect(night.night == day(10, 9))
        #expect(night.timeZoneIdentifier == "Asia/Tokyo")
        #expect(night.onset == at(2026, 10, 9, 14))

        // An unknown identifier falls back to the builder's zone.
        let unknown = try #require(builder.nights(from: [
            sample(.asleepCore, at(2026, 10, 9, 23), at(2026, 10, 10, 7), zone: "Mars/Olympus"),
        ]).first)
        #expect(unknown.timeZoneIdentifier == utc.timeZone.identifier)
    }

    // MARK: Into the ledger

    @Test("Built nights feed the ledger: tracked and on time the next morning")
    func intoTheLedger() {
        let context = CollectionContext(schedule: .standard, permissions: [.appleHealth], calendar: utc, hemisphere: .northern)
        var snapshot = CollectionSnapshot.empty(profileID: UUID(), createdAt: at(2026, 10, 9, 20))
        snapshot.raise(.firstLeaf, to: 1, at: at(2026, 10, 9, 20), calendar: utc)
        snapshot.runEngine(at: at(2026, 10, 9, 20), context: context)
        snapshot.openReveals(nil, at: at(2026, 10, 9, 20), context: context)

        let unlocked = snapshot.recordSleep(builder.nights(from: watchNight()), at: at(2026, 10, 10, 7, 30), context: context)
        let night = snapshot.nights.recent.last
        #expect(night?.outcome == .onTime)
        #expect(night?.steadyMorning == true)
        #expect(night?.fullNight == true)
        #expect(snapshot.counters[.restedNights] == 1)
        // Rested nights' first leaf comes at 3 nights.
        #expect(unlocked.isEmpty)
    }
}

@Suite("Apple Health import rules")
struct SleepImportRulesTests {
    @Test("The importer reads from the night before the install night, at most the last 16 nights")
    func window() {
        let install = LocalDay(year: 2026, month: 10, day: 1)
        // A day after install: from the evening of 30 September.
        #expect(SleepImportWindow.firstNight(installNight: install, now: at(2026, 10, 2, 9), calendar: utc)
            == LocalDay(year: 2026, month: 9, day: 30))
        #expect(SleepImportWindow.start(installNight: install, now: at(2026, 10, 2, 9), calendar: utc) == at(2026, 9, 30, 18))
        // A month later only the last 16 nights: the ledger's pending nights and the 72-hour upgrade window.
        #expect(SleepImportWindow.firstNight(installNight: install, now: at(2026, 11, 1, 9), calendar: utc)
            == LocalDay(year: 2026, month: 10, day: 16))
        #expect(SleepImportWindow.nightsRead == 16)
    }

    @Test("Last night for Home: the night just ended, its time asleep (or in bed for iPhone's estimate)")
    func lastNight() throws {
        let watch = SleepNightObservation(night: LocalDay(year: 2026, month: 10, day: 9), onset: at(2026, 10, 9, 23, 8),
                                          finalWake: at(2026, 10, 10, 6, 20), asleepMinutes: 412, source: .watchOrTracker)
        let older = SleepNightObservation(night: LocalDay(year: 2026, month: 10, day: 8), onset: at(2026, 10, 8, 23),
                                          finalWake: at(2026, 10, 9, 7), asleepMinutes: 400, source: .watchOrTracker)
        let sleep = try #require(SleepImportWindow.lastNight(in: [older, watch], at: at(2026, 10, 10, 7), calendar: utc))
        #expect(sleep.asleep == at(2026, 10, 9, 23, 8))
        #expect(sleep.awake == at(2026, 10, 10, 6, 20))
        #expect(sleep.duration == 412 * 60)
        // Nothing for last night: no numeral from an older one.
        #expect(SleepImportWindow.lastNight(in: [older], at: at(2026, 10, 10, 7), calendar: utc) == nil)

        let inBed = SleepNightObservation(night: LocalDay(year: 2026, month: 10, day: 9), onset: at(2026, 10, 9, 23),
                                          finalWake: at(2026, 10, 10, 6, 30), asleepMinutes: nil, source: .iPhoneInBed)
        #expect(inBed.lastNightSleep.duration == 7.5 * 3600)
    }

    @Test("Nights since connecting: a night has passed once noon the next day has come")
    func nightsSinceConnecting() {
        // Connected in the evening: that night counts.
        let evening = at(2026, 10, 10, 21)
        #expect(SleepDataHint.nightsPassed(since: evening, now: at(2026, 10, 11, 11), calendar: utc) == 0)
        #expect(SleepDataHint.nightsPassed(since: evening, now: at(2026, 10, 11, 12), calendar: utc) == 1)
        #expect(SleepDataHint.nightsPassed(since: evening, now: at(2026, 10, 12, 12), calendar: utc) == 2)
        // Connected in the day: the night already over doesn't.
        let day = at(2026, 10, 10, 10)
        #expect(SleepDataHint.nightsPassed(since: day, now: at(2026, 10, 11, 12), calendar: utc) == 1)
        // Connected in the small hours: that night counts.
        let smallHours = at(2026, 10, 11, 2)
        #expect(SleepDataHint.nightsPassed(since: smallHours, now: at(2026, 10, 11, 12), calendar: utc) == 1)
    }

    @Test("The no-sleep hint shows after 2 nights connected without any sleep sample")
    func hint() {
        let connected = at(2026, 10, 10, 21)
        #expect(!SleepDataHint.isDue(connectedAt: nil, hasReceivedSleep: false, now: at(2026, 10, 20), calendar: utc))
        #expect(!SleepDataHint.isDue(connectedAt: connected, hasReceivedSleep: false, now: at(2026, 10, 11, 13), calendar: utc))
        #expect(SleepDataHint.isDue(connectedAt: connected, hasReceivedSleep: false, now: at(2026, 10, 12, 13), calendar: utc))
        #expect(!SleepDataHint.isDue(connectedAt: connected, hasReceivedSleep: true, now: at(2026, 10, 12, 13), calendar: utc))
    }
}
