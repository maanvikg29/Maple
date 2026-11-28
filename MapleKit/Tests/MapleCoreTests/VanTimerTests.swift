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

    @Test("What block mode will do, and what a start does with it")
    func blocking() {
        // A free-tier build without Apple's Family Controls permission: always a plain timer.
        let unavailable = VanBlocking(buildCanBlock: false, isAllowed: false, wantsBlock: true, hasApps: true)
        #expect(unavailable == .unavailable)
        #expect(unavailable.startsPlainTimer && unavailable.rowAction == nil && !unavailable.canSwitch)
        #expect(unavailable.line == "Plain timer · apps aren't locked")
        // The build can block, but Screen Time hasn't been turned on for Maple: the row turns it on.
        let needs = VanBlocking(buildCanBlock: true, isAllowed: false, wantsBlock: true, hasApps: true)
        #expect(needs == .needsScreenTime)
        #expect(needs.startsPlainTimer && needs.rowAction == "Turn on" && !needs.canSwitch)
        #expect(needs.line == "Screen Time is off · apps aren't locked")
        let off = VanBlocking(buildCanBlock: true, isAllowed: true, wantsBlock: false, hasApps: true)
        #expect(off == .off)
        #expect(off.startsPlainTimer && off.rowAction == nil && off.canSwitch)
        // On with an empty list: nothing would be blocked, so choosing comes before the start.
        let empty = VanBlocking(buildCanBlock: true, isAllowed: true, wantsBlock: true, hasApps: false)
        #expect(empty == .chooseApps)
        #expect(!empty.startsPlainTimer && empty.rowAction == "Choose" && empty.line == "Choose apps to block")
        let on = VanBlocking(buildCanBlock: true, isAllowed: true, wantsBlock: true, hasApps: true)
        #expect(on == .on)
        #expect(!on.startsPlainTimer && on.rowAction == "Change" && on.canSwitch)
    }

    @Test("The clock opens on the length last set, then the last preset's, then 50 minutes; always a length the clock allows")
    func length() {
        #expect(VanTimer.length(saved: 75, preset: 50) == 75)
        #expect(VanTimer.length(saved: 0, preset: 90) == 90)
        #expect(VanTimer.length(saved: 0, preset: nil) == 50)
        #expect(VanTimer.length(saved: 7, preset: 90) == 20)
        #expect(VanTimer.length(saved: 999, preset: nil) == 180)
        #expect(VanTimer.length(saved: -5, preset: 52) == 50)
    }

    @Test("The receipt's Again starts the old way, with presets and strictness, so it is not offered while the van is home")
    func again() {
        #expect(!ReceiptFlow.offersAgain(ShippedFeatures.current))
        #expect(ReceiptFlow.offersAgain(ShippedFeatures(releases: [.m1, .f1])))
    }
}
