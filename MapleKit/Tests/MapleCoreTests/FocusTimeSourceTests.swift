import Foundation
import Testing
@testable import MapleCore
@testable import MapleFocusCore

@Suite("Focus time sources")
struct FocusTimeSourceTests {
    @Test("Manual time moves the wall and continuous clocks together")
    func manualAdvance() {
        let time = ManualFocusTime(wall: at(2026, 10, 23, 14))
        let first = time.stamp()
        time.advance(90)
        let second = time.stamp()
        #expect(second.wall == at(2026, 10, 23, 14, 1, 30))
        #expect(second.seconds(since: first) == 90)
        #expect(second.boot == first.boot)
    }

    @Test("Setting the wall clock moves only the wall clock")
    func manualWall() {
        let time = ManualFocusTime(wall: at(2026, 10, 23, 14))
        let first = time.stamp()
        time.setWall(at(2026, 10, 22, 9))
        let second = time.stamp()
        #expect(second.wall == at(2026, 10, 22, 9))
        #expect(second.continuous == first.continuous)
    }

    @Test("A reboot starts a new boot with a small continuous clock")
    func manualReboot() {
        let time = ManualFocusTime(wall: at(2026, 10, 23, 14))
        let before = time.stamp()
        time.reboot("b2")
        let after = time.stamp()
        #expect(after.boot == "b2")
        #expect(after.continuous < before.continuous)
        #expect(after.wall == before.wall)
    }

    @Test("Live time: one boot id per launch, continuous time never goes back")
    func live() {
        let time = LiveFocusTime(deviceID: FocusFixtures.device)
        let a = time.stamp()
        let b = time.stamp()
        #expect(a.boot == b.boot)
        #expect(!a.boot.isEmpty)
        #expect(b.continuous >= a.continuous)
        #expect(a.zone == TimeZone.current.identifier)
    }

    @Test("The boot id is hashed with the device id, so two installs never share one")
    func hashed() {
        let one = LiveFocusTime.hashedBoot("ABC", deviceID: FocusFixtures.device)
        let other = LiveFocusTime.hashedBoot("ABC", deviceID: UUID())
        #expect(one != other)
        #expect(one == LiveFocusTime.hashedBoot("ABC", deviceID: FocusFixtures.device))
        #expect(!one.contains("ABC"))
    }

    @Test("When the boot id can't be read, each launch gets its own, so credit never joins two launches")
    func unreadableBoot() {
        let first = LiveFocusTime(deviceID: FocusFixtures.device, bootSession: nil)
        let second = LiveFocusTime(deviceID: FocusFixtures.device, bootSession: nil)
        #expect(first.boot != second.boot)
    }

    @Test("Shifted time keeps running, offset on the wall clock only")
    func shifted() {
        let base = LiveFocusTime(deviceID: FocusFixtures.device, bootSession: "fixed")
        let shifted = ShiftedFocusTime(base: base, offset: -3600)
        let stamp = shifted.stamp()
        #expect(abs(stamp.wall.timeIntervalSinceNow + 3600) < 5)
        #expect(stamp.boot == base.boot)
    }
}
