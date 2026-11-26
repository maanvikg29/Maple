import Foundation
import Testing
@testable import MapleCore
@testable import MapleFocusCore

@Suite("The session the van starts")
struct VanTimerTests {
    @Test("It is Gentle with no break whatever the member's last preset was, and keeps that preset's apps and identity")
    func preset() {
        let apps = UUID()
        let deep = FocusPreset(name: "Deep", verb: .deep, minutes: 90, hasBreak: true, appSetID: apps, strictness: .locked,
                               pendingStrictness: .steady, pendingFrom: nil)
        let made = VanTimer.preset(from: deep)
        #expect(made.id == deep.id)
        #expect(made.appSetID == apps)
        #expect(made.strictness == .gentle)
        #expect(made.pendingStrictness == nil)
        #expect(!made.hasBreak)
        #expect(made.name == "Focus")
        #expect(made.verb == .focus)
    }

    @Test("With no preset at all it still makes one, with no apps to block")
    func noPreset() {
        let made = VanTimer.preset(from: nil)
        #expect(made.strictness == .gentle)
        #expect(!made.hasBreak)
        #expect(made.appSetID == nil)
    }

    @Test("The button reads Start and the length, and never a leaf count")
    func title() {
        #expect(VanTimer.startTitle(minutes: 50) == "Start · \(FocusTimeText.length(minutes: 50))")
        #expect(!VanTimer.startTitle(minutes: 50).lowercased().contains("lea"))
    }

    @Test("The line under the switch says what will happen to the member's apps")
    func blockingLine() {
        #expect(VanTimer.blockingLine(canBlock: false, wantsBlock: true, hasApps: true) == "Plain timer · apps aren't locked")
        #expect(VanTimer.blockingLine(canBlock: true, wantsBlock: false, hasApps: true) == "Block mode is off · apps aren't locked")
        #expect(VanTimer.blockingLine(canBlock: true, wantsBlock: true, hasApps: false) == "Choose apps to block")
        #expect(VanTimer.blockingLine(canBlock: true, wantsBlock: true, hasApps: true) == "Blocking your chosen apps")
    }

    @Test("The full entrance plays once a day; after that it is short, and Reduce Motion always cross-fades")
    func entrance() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let noon = Date(timeIntervalSince1970: 1_795_000_000)
        #expect(VanEntrance.style(lastFull: nil, now: noon, calendar: calendar, reduceMotion: false) == .full)
        #expect(VanEntrance.style(lastFull: noon.addingTimeInterval(-60), now: noon, calendar: calendar, reduceMotion: false) == .short)
        #expect(VanEntrance.style(lastFull: noon.addingTimeInterval(-86_400 * 2), now: noon, calendar: calendar, reduceMotion: false) == .full)
        #expect(VanEntrance.style(lastFull: nil, now: noon, calendar: calendar, reduceMotion: true) == .crossFade)
        #expect(VanEntrance.full.seconds == 1.2)
        #expect(VanEntrance.short.seconds < 0.5)
    }
}
