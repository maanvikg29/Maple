#if DEBUG
import Foundation
import Testing
@testable import MapleCore
@testable import MapleServices

@Suite("Focus demo arguments")
@MainActor
struct FocusDemoArgumentTests {
    @Test("Every Focus argument in F1 design §8.2 is a typed field")
    func parse() {
        let options = DemoLaunchOptions(arguments: [
            "/path/Maple", "-MapleDemoShip", "f1", "-MapleDemoFocus", "endedAway", "-MapleDemoFocusAt", "40",
            "-MapleDemoStrictness", "locked", "-MapleDemoScreenTime", "noPasscode", "-MapleDemoReceipt", "leafNight",
            "-MapleDemoSaved", "capped", "-MapleDemoLiveActivity", "break", "-MapleDemoPresent", "streak",
            "-MapleDemoPreset", "read", "-MapleDemoIntention", "Chemistry ch. 4", "-MapleDemoHoldAt", "0.5",
            "-MapleDemoEndCountdown", "9", "-MapleDemoFinishAt", "1.2",
        ])
        #expect(options.ship == ShippedFeatures(releases: [.m1, .f1]))
        #expect(options.focus == .endedAway)
        #expect(options.focusAt == 40)
        #expect(options.strictness == .locked)
        #expect(options.screenTime == .noPasscode)
        #expect(options.receipt == .leafNight)
        #expect(options.saved == .capped)
        #expect(options.liveActivity == .breakTime)
        #expect(options.focusSheet == .streak)
        #expect(options.preset == .reading)
        #expect(options.intention == "Chemistry ch. 4")
        #expect(options.holdAt == 0.5)
        #expect(options.endCountdown == 9)
        #expect(options.finishAt == 1.2)
        #expect(options.hasFocusArguments)
        #expect(options.isActive)
        #expect(options.usesDemoCollection)
    }

    @Test("The values are the ones docs/debug-launch-arguments.md lists, read in any case")
    func rawValues() {
        #expect(FocusDemo.State.allCases.map(\.rawValue) == [
            "idle", "noSet", "smallSet", "expired", "running", "dimmed", "break", "minimised", "ended", "endedAway",
            "endEarly", "emergency", "first",
        ])
        #expect(FocusDemo.ScreenTime.allCases.map(\.rawValue) == [
            "approved", "notDetermined", "declined", "restricted", "noPasscode", "unavailable", "revoked", "plain", "failStart",
        ])
        #expect(FocusDemo.Receipt.allCases.map(\.rawValue) == [
            "clean", "unlocked", "early", "plain", "revoked", "bedtime", "capped", "leaf", "leafNight", "notQualifying",
            "emergency",
        ])
        #expect(FocusDemo.Saved.allCases.map(\.rawValue) == ["typical", "capped", "empty"])
        #expect(FocusDemo.LiveActivity.allCases.map(\.rawValue) == ["running", "break", "plain", "ended"])
        #expect(FocusDemo.Sheet.allCases.map(\.rawValue) == ["blocking", "preset", "saved", "streak", "intention"])
        #expect(DemoLaunchOptions(arguments: ["-MapleDemoFocus", "BREAK"]).focus == .breakTime)
        #expect(DemoLaunchOptions(arguments: ["-MapleDemoFocus", "endedaway"]).focus == .endedAway)
        #expect(DemoLaunchOptions(arguments: ["-MapleDemoStrictness", "Gentle"]).strictness == .gentle)
        for (text, verb) in [("study", FocusVerb.study), ("quick", .quick), ("deep", .deep), ("read", .reading)] {
            #expect(DemoLaunchOptions(arguments: ["-MapleDemoPreset", text]).preset == verb, "\(text)")
        }
    }

    @Test("Unknown values and the app's own presentations are ignored; numbers are clamped")
    func invalid() {
        let none = DemoLaunchOptions(arguments: ["/path/Maple"])
        #expect(!none.hasFocusArguments)
        #expect(none.ship == nil && none.focus == nil && none.focusSheet == nil)
        let odd = DemoLaunchOptions(arguments: [
            "-MapleDemoShip", "f2", "-MapleDemoFocus", "asleep", "-MapleDemoFocusAt", "500", "-MapleDemoPreset", "reading",
            "-MapleDemoHoldAt", "3", "-MapleDemoEndCountdown", "40", "-MapleDemoFinishAt", "soon",
        ])
        #expect(odd.ship == nil)
        #expect(odd.focus == nil)
        #expect(odd.focusAt == 180)
        #expect(odd.preset == nil)
        #expect(odd.holdAt == 1)
        #expect(odd.endCountdown == 15)
        #expect(odd.finishAt == nil)
        #expect(DemoLaunchOptions(arguments: ["-MapleDemoShip", "M1"]).ship == ShippedFeatures(releases: [.m1]))
        #expect(DemoLaunchOptions(arguments: ["-MapleDemoHoldAt", "nan"]).holdAt == nil)
        #expect(DemoLaunchOptions(arguments: ["-MapleDemoFinishAt", "0.4"]).finishAt == 0.4)
        // -MapleDemoPresent names a Focus sheet, or one of the app's own presentations, which stay as they are.
        #expect(DemoLaunchOptions(arguments: ["-MapleDemoPresent", "saved"]).focusSheet == .saved)
        let reveal = DemoLaunchOptions(arguments: ["-MapleDemoPresent", "reveal"])
        #expect(reveal.focusSheet == nil)
        #expect(!reveal.isActive)
        #expect(DemoLaunchOptions(arguments: ["-MapleDemoPresent", "endEarly"]).focusSheet == nil)
        // -MapleDemoPlainTimerChosen is a Focus flag: YES, true or 1, in any case.
        let chosen = DemoLaunchOptions(arguments: ["-MapleDemoPlainTimerChosen", "yes"])
        #expect(chosen.plainTimerChosen && chosen.hasFocusArguments && chosen.isActive)
        #expect(!DemoLaunchOptions(arguments: ["-MapleDemoPlainTimerChosen", "no"]).plainTimerChosen)
        #expect(!none.plainTimerChosen)
        // A Focus argument alone is a demo launch on the demo collection, unless it is a fresh first run.
        let focus = DemoLaunchOptions(arguments: ["-MapleDemoFocus", "running"])
        #expect(focus.isActive && focus.usesDemoCollection)
        #expect(!DemoLaunchOptions(arguments: ["-MapleDemoFocus", "running", "-MapleDemoFresh", "YES"]).usesDemoCollection)
        #expect(DemoLaunchOptions(arguments: ["-MapleDemoIntention", ""]).intention == "")
    }

    @Test("-MapleDemoShip f1 ships exactly M1 and F1 in the demo stores, never everything")
    func ship() throws {
        let folder = try temporaryDirectory()
        let shipped = MapleStores.make(DemoLaunchOptions(arguments: ["-MapleDemoShip", "f1", "-MapleDemoSpecies", "23"]),
                                       directory: folder, calendar: utc, now: at(2026, 10, 23, 9))
        #expect(shipped.collection.context.features == ShippedFeatures(releases: [.m1, .f1]))
        #expect(shipped.collection.context.features != .all)
        #expect(shipped.collection.context.features.focus)
        let current = MapleStores.make(DemoLaunchOptions(arguments: ["-MapleDemoSpecies", "23"]), directory: folder,
                                       calendar: utc, now: at(2026, 10, 23, 9))
        #expect(current.collection.context.features == .current)
        #expect(files(in: folder).isEmpty)
    }

    @Test("A Focus demo's clock starts in the asked-for phase, the Day by default, and keeps running")
    func clock() throws {
        let folder = try temporaryDirectory()
        let day = at(2026, 10, 23, 9)
        let windows = PhaseWindows(schedule: .standard)
        let evening = MapleStores.make(DemoLaunchOptions(arguments: ["-MapleDemoFocus", "running", "-MapleDemoPhase", "evening"]),
                                       directory: folder, calendar: utc, now: day)
        #expect(!evening.clock.isFixed)
        #expect(abs(evening.clock.now().timeIntervalSince(windows.sampleDate(in: .evening, onDayOf: day, calendar: utc))) < 2)
        #expect(evening.collection.snapshot.hasPlantedMaple)
        // The standard schedule's Day sample: 10:00 plus half of the 10h 15m to 20:15.
        let shipped = MapleStores.make(DemoLaunchOptions(arguments: ["-MapleDemoShip", "f1"]), directory: folder, calendar: utc, now: day)
        #expect(!shipped.clock.isFixed)
        #expect(abs(shipped.clock.now().timeIntervalSince(at(2026, 10, 23, 15, 7))) < 2)
        // Without a Focus argument the phase still freezes the clock.
        let frozen = MapleStores.make(DemoLaunchOptions(arguments: ["-MapleDemoPhase", "evening"]), directory: folder,
                                      calendar: utc, now: day)
        #expect(frozen.clock.isFixed)
    }
}
#endif
