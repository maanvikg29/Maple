import Foundation
import Testing
@testable import MapleCore
@testable import MapleServices

@Suite("App settings")
@MainActor
struct SettingsTests {
    @Test("A first launch has the documented defaults and writes nothing until a change")
    func defaults() throws {
        let folder = try temporaryDirectory()
        let url = folder.appendingPathComponent(AppSettings.file)
        let settings = AppSettings(storage: JSONStorage(.file(url)), regionCode: "GB")
        #expect(settings.hemisphere == .automatic)
        // rewards.json `full_nights`: a 7h 30m sleep need unless the member changes it.
        #expect(settings.sleepGoalMinutes == 7 * 60 + 30)
        #expect(settings.sleepGoalMinutes == AppSettings.defaultSleepGoalMinutes)
        #expect(CollectionContext().sleepNeedMinutes == 7 * 60 + 30)
        #expect(!settings.revealSound)
        #expect(files(in: folder).isEmpty)
    }

    @Test("Every change is saved at once and survives a relaunch")
    func persists() throws {
        let url = try temporaryDirectory().appendingPathComponent(AppSettings.file)
        let settings = AppSettings(storage: JSONStorage(.file(url)), regionCode: "GB")
        settings.hemisphere = .southern
        settings.sleepGoalMinutes = 8 * 60
        settings.revealSound = true
        #expect(FileManager.default.fileExists(atPath: url.path))

        let reloaded = AppSettings(storage: JSONStorage(.file(url)), regionCode: "GB")
        #expect(reloaded.hemisphere == .southern)
        #expect(reloaded.sleepGoalMinutes == 8 * 60)
        #expect(reloaded.revealSound)
        #expect(reloaded.snapshot == settings.snapshot)
    }

    @Test("Automatic follows the region; a chosen hemisphere wins")
    func hemisphere() {
        let australia = AppSettings(storage: JSONStorage(.memory), regionCode: "AU")
        #expect(australia.regionHemisphere == .southern)
        #expect(australia.resolvedHemisphere == .southern)
        australia.hemisphere = .northern
        #expect(australia.resolvedHemisphere == .northern)

        let britain = AppSettings(storage: JSONStorage(.memory), regionCode: "GB")
        #expect(britain.resolvedHemisphere == .northern)
        britain.hemisphere = .southern
        #expect(britain.resolvedHemisphere == .southern)

        let unknown = AppSettings(storage: JSONStorage(.memory), regionCode: nil)
        #expect(unknown.resolvedHemisphere == .northern)
        #expect(HemisphereChoice.automatic.resolved(regionCode: "nz") == .southern)
    }

    @Test("The sleep goal stays between 7 and 9 hours, in 30-minute steps (rewards.json full_nights)")
    func sleepGoal() {
        let settings = AppSettings(storage: JSONStorage(.memory), regionCode: "GB")
        settings.sleepGoalMinutes = 2 * 60
        #expect(settings.sleepGoalMinutes == 7 * 60)
        #expect(!settings.canDecreaseSleepGoal)
        settings.decreaseSleepGoal()
        #expect(settings.sleepGoalMinutes == 7 * 60)

        settings.sleepGoalMinutes = 13 * 60
        #expect(settings.sleepGoalMinutes == 9 * 60)
        #expect(!settings.canIncreaseSleepGoal)
        settings.increaseSleepGoal()
        #expect(settings.sleepGoalMinutes == 9 * 60)

        settings.sleepGoalMinutes = 7 * 60 + 40
        #expect(settings.sleepGoalMinutes == 7 * 60 + 30)
        settings.increaseSleepGoal()
        #expect(settings.sleepGoalMinutes == 8 * 60)
        #expect(settings.canIncreaseSleepGoal && settings.canDecreaseSleepGoal)
        settings.decreaseSleepGoal()
        settings.decreaseSleepGoal()
        #expect(settings.sleepGoalMinutes == 7 * 60)
        #expect(!settings.canDecreaseSleepGoal)
    }

    @Test("The sleep goal is the collection's sleep need, which judges Full nights")
    func sleepGoalFeedsTheLedger() {
        let collection = CollectionStore(storage: JSONStorage(.memory), context: testContext, now: at(2026, 10, 10, 12))
        let settings = AppSettings(storage: JSONStorage(.memory), regionCode: "GB")
        settings.sleepGoalMinutes = 9 * 60
        settings.apply(to: collection)
        #expect(collection.context.sleepNeedMinutes == 9 * 60)
    }

    @Test("Older or hand-edited files decode with defaults and clamped values")
    func tolerantDecoding() throws {
        let decoder = JSONDecoder()
        let empty = try decoder.decode(SettingsSnapshot.self, from: Data("{}".utf8))
        #expect(empty == SettingsSnapshot())

        let odd = try decoder.decode(
            SettingsSnapshot.self,
            from: Data(#"{"hemisphere":"equatorial","sleepGoalMinutes":30,"revealSound":true,"version":9}"#.utf8)
        )
        #expect(odd.hemisphere == .automatic)
        #expect(odd.sleepGoalMinutes == 7 * 60)
        #expect(odd.revealSound)

        let encoded = try JSONEncoder().encode(odd)
        #expect(try decoder.decode(SettingsSnapshot.self, from: encoded) == odd)
    }

    @Test("In-memory settings never touch the disk")
    func memory() throws {
        let folder = try temporaryDirectory()
        let settings = AppSettings(storage: JSONStorage(.memory), regionCode: "GB")
        settings.revealSound = true
        settings.hemisphere = .southern
        #expect(settings.revealSound)
        #expect(files(in: folder).isEmpty)
    }

    @Test("Applying the hemisphere moves the season; a DEBUG season override still wins")
    func appliesHemisphere() {
        let october = at(2026, 10, 10, 12)
        let collection = CollectionStore(storage: JSONStorage(.memory), context: testContext, now: october)
        let settings = AppSettings(storage: JSONStorage(.memory), regionCode: "GB")
        settings.apply(to: collection)
        #expect(collection.context.hemisphere == .northern)
        #expect(collection.season(at: october) == .autumn)

        settings.hemisphere = .southern
        settings.apply(to: collection)
        #expect(collection.context.hemisphere == .southern)
        #expect(collection.season(at: october) == .spring)
        #expect(collection.treeInputs(at: october).season == .spring)

        var overridden = testContext
        overridden.seasonOverride = .winter
        let demo = CollectionStore(storage: JSONStorage(.memory), context: overridden, now: october)
        settings.apply(to: demo)
        #expect(demo.context.hemisphere == .southern)
        #expect(demo.season(at: october) == .winter)
    }
}
