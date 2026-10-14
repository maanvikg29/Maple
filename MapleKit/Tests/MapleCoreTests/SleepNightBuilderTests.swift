import Foundation
import Testing
@testable import MapleCore

@Suite("Sleep night builder")
struct SleepNightBuilderTests {
    private let builder = SleepNightBuilder(calendar: utc)
    private let watch = SleepSampleOrigin(stage: .asleep, bundleIdentifier: "com.apple.health.81AF5A6E", productType: "Watch7,1",
                                          deviceModel: "Watch")
    private let iPhoneInBed = SleepSampleOrigin(stage: .inBed, bundleIdentifier: "com.apple.health.3C1B0F2D", productType: "iPhone17,1",
                                                deviceModel: "iPhone")

    private func sample(_ start: Date, _ end: Date, _ source: SleepSource = .watchOrTracker, zone: String? = nil) -> SleepSample {
        SleepSample(start: start, end: end, source: source, timeZoneIdentifier: zone)
    }

    @Test("The source ladder: Watch stages are A, other apps' asleep samples B, iPhone's in-bed C")
    func ladder() {
        #expect(watch.source == .watchOrTracker)
        #expect(SleepSampleOrigin(stage: .asleep, bundleIdentifier: "com.example.sleep").source == .otherApp)
        #expect(iPhoneInBed.source == .iPhoneInBed)
    }

    @Test("User-entered samples, awake stages, Watch in-bed and other apps' in-bed never count")
    func neverCounts() {
        var typed = watch
        typed.wasUserEntered = true
        #expect(typed.source == nil)
        #expect(SleepSampleOrigin(stage: .awake, bundleIdentifier: watch.bundleIdentifier, productType: "Watch7,1").source == nil)
        #expect(SleepSampleOrigin(stage: .inBed, bundleIdentifier: watch.bundleIdentifier, productType: "Watch7,1").source == nil)
        #expect(SleepSampleOrigin(stage: .inBed, bundleIdentifier: "com.example.sleep").source == nil)
        #expect(SleepSample(start: at(2026, 10, 1, 23), end: at(2026, 10, 2, 7), origin: typed) == nil)
        #expect(SleepSample(start: at(2026, 10, 1, 23), end: at(2026, 10, 1, 23), origin: watch) == nil)
    }

    @Test("A Watch night: onset is the first 20-minute asleep block, wake the last block's end, asleep time the blocks")
    func watchNight() throws {
        let samples = [
            sample(at(2026, 10, 1, 22, 50), at(2026, 10, 1, 23)),          // a 10-minute doze: not the onset
            sample(at(2026, 10, 1, 23, 5), at(2026, 10, 2, 3)),
            sample(at(2026, 10, 2, 3), at(2026, 10, 2, 3, 30)),             // the next stage, back to back
            sample(at(2026, 10, 2, 3, 40), at(2026, 10, 2, 6, 55)),
        ]
        let night = try #require(builder.observations(from: samples).only)
        #expect(night.night == LocalDay(year: 2026, month: 10, day: 1))
        #expect(night.onset == at(2026, 10, 1, 23, 5))
        #expect(night.finalWake == at(2026, 10, 2, 6, 55))
        #expect(night.asleepMinutes == 10 + 265 + 195)
        #expect(night.source == .watchOrTracker)
        #expect(night.timeZoneIdentifier == "UTC")
    }

    @Test("Overlapping samples from two apps count their asleep time once")
    func overlaps() throws {
        let samples = [
            sample(at(2026, 10, 1, 23), at(2026, 10, 2, 5), .otherApp),
            sample(at(2026, 10, 2, 4), at(2026, 10, 2, 7), .otherApp),
        ]
        let night = try #require(builder.observations(from: samples).only)
        #expect(night.asleepMinutes == 8 * 60)
        #expect(night.source == .otherApp)
    }

    @Test("Gaps under 60 minutes are one episode; a longer gap splits it and the longest cluster is the night")
    func gaps() throws {
        let merged = try #require(builder.observations(from: [
            sample(at(2026, 10, 1, 23), at(2026, 10, 2, 2)),
            sample(at(2026, 10, 2, 2, 50), at(2026, 10, 2, 7)),
        ]).only)
        #expect(merged.onset == at(2026, 10, 1, 23))
        #expect(merged.finalWake == at(2026, 10, 2, 7))
        #expect(merged.asleepMinutes == 180 + 250)

        let split = try #require(builder.observations(from: [
            sample(at(2026, 10, 1, 23), at(2026, 10, 2, 1)),
            sample(at(2026, 10, 2, 2), at(2026, 10, 2, 7)),
        ]).only)
        #expect(split.onset == at(2026, 10, 2, 2))
        #expect(split.asleepMinutes == 300)
    }

    @Test("Naps are ignored and nights run 18:00 to 18:00")
    func naps() {
        let nights = builder.observations(from: [
            sample(at(2026, 10, 1, 23), at(2026, 10, 2, 7)),
            sample(at(2026, 10, 2, 14), at(2026, 10, 2, 15, 30)),       // the same night's afternoon nap
            sample(at(2026, 10, 2, 22, 30), at(2026, 10, 3, 6, 30)),
        ])
        #expect(nights.map(\.night) == [LocalDay(year: 2026, month: 10, day: 1), LocalDay(year: 2026, month: 10, day: 2)])
        #expect(nights.first?.onset == at(2026, 10, 1, 23))
    }

    @Test("Each night takes the best source with a main episode; shorter than 3 hours is no night")
    func bestSource() throws {
        let inBed = sample(at(2026, 10, 1, 22, 45), at(2026, 10, 2, 7), .iPhoneInBed)
        let best = try #require(builder.observations(from: [
            inBed,
            sample(at(2026, 10, 1, 23), at(2026, 10, 2, 6, 30), .otherApp),
            sample(at(2026, 10, 1, 23, 10), at(2026, 10, 2, 6, 40)),
        ]).only)
        #expect(best.source == .watchOrTracker)
        #expect(best.onset == at(2026, 10, 1, 23, 10))

        // The Watch came off after two hours: iPhone's in-bed estimate is the night, without asleep time.
        let estimated = try #require(builder.observations(from: [inBed, sample(at(2026, 10, 1, 23), at(2026, 10, 2, 1))]).only)
        #expect(estimated.source == .iPhoneInBed)
        #expect(estimated.onset == at(2026, 10, 1, 22, 45))
        #expect(estimated.finalWake == at(2026, 10, 2, 7))
        #expect(estimated.asleepMinutes == nil)

        #expect(builder.observations(from: [sample(at(2026, 10, 1, 23), at(2026, 10, 2, 1, 59))]).isEmpty)
    }

    @Test("A night is named and judged in the time zone its samples were written in")
    func timeZone() throws {
        // 23:00 in Tokyo is 14:00 UTC, which in UTC would belong to the night before.
        let night = try #require(builder.observations(from: [
            sample(at(2026, 10, 1, 14), at(2026, 10, 1, 21, 30), zone: "Asia/Tokyo"),
        ]).only)
        #expect(night.night == LocalDay(year: 2026, month: 10, day: 1))
        #expect(night.timeZoneIdentifier == "Asia/Tokyo")
    }
}

private extension Array {
    /// The one element, or nil when there are none or several.
    var only: Element? { count == 1 ? first : nil }
}
