import Testing
@testable import MapleCore

@Suite("The clock that sets a session's length")
struct ClockSettingTests {
    @Test("A length snaps to 5 minutes and stays between 20 minutes and 3 hours")
    func snapped() {
        #expect(ClockSetting(minutes: 52).minutes == 50)
        #expect(ClockSetting(minutes: 53).minutes == 55)
        #expect(ClockSetting(minutes: 7).minutes == 20)
        #expect(ClockSetting(minutes: 500).minutes == 180)
        #expect(ClockSetting(minutes: -30).minutes == 20)
    }

    @Test("The long hand shows the minutes past the hour, the short hand the whole length as on any clock")
    func hands() {
        #expect(ClockSetting(minutes: 50).minuteAngle == 300)
        #expect(ClockSetting(minutes: 50).hourAngle == 25)
        #expect(ClockSetting(minutes: 90).minuteAngle == 180)
        #expect(ClockSetting(minutes: 90).hourAngle == 45)
        #expect(ClockSetting(minutes: 120).minuteAngle == 0)
        #expect(ClockSetting(minutes: 120).hourAngle == 60)
    }

    @Test("The hub reads hours and minutes: 0:50, 1:05, 1:30, 3:00")
    func hub() {
        #expect(ClockSetting(minutes: 50).hubText == "0:50")
        #expect(ClockSetting(minutes: 65).hubText == "1:05")
        #expect(ClockSetting(minutes: 90).hubText == "1:30")
        #expect(ClockSetting(minutes: 180).hubText == "3:00")
        #expect(ClockSetting(minutes: 125).wholeHours == 2)
        #expect(ClockSetting(minutes: 45).faceFill == 0.75)
        #expect(ClockSetting(minutes: 60).faceFill == 0)
    }

    @Test("Turning the long hand moves by the shortest way, and passing the top adds or takes away an hour")
    func turning() {
        var clock = ClockSetting(minutes: 50)
        #expect(clock.turn(toAngle: 330))
        #expect(clock.minutes == 55)
        #expect(clock.turn(toAngle: 0))
        #expect(clock.minutes == 60)
        #expect(clock.turn(toAngle: 30))
        #expect(clock.minutes == 65)
        #expect(clock.turn(toAngle: 330))
        #expect(clock.minutes == 55)
        #expect(!clock.turn(toAngle: 331))
        #expect(clock.minutes == 55)
    }

    @Test("An angle outside one turn, or a touch that isn't a number, is handled")
    func oddAngles() {
        var clock = ClockSetting(minutes: 50)
        clock.turn(toAngle: 690)
        #expect(clock.minutes == 55)
        clock.turn(toAngle: -60)
        #expect(clock.minutes == 50)
        #expect(!clock.turn(toAngle: .nan))
        #expect(!clock.turn(toAngle: .infinity))
        #expect(clock.minutes == 50)
    }

    @Test("The hand stops at 3 hours and at 20 minutes and never wraps round")
    func limits() {
        var long = ClockSetting(minutes: 180)
        #expect(!long.turn(toAngle: 90))
        #expect(long.minutes == 180)
        #expect(long.turn(toAngle: 270))
        #expect(long.minutes == 165)
        var short = ClockSetting(minutes: 20)
        #expect(!short.turn(toAngle: 0))
        #expect(short.minutes == 20)
        for _ in 0 ..< 100 { long.turn(toAngle: 90); long.turn(toAngle: 180); long.turn(toAngle: 270); long.turn(toAngle: 0) }
        #expect(long.minutes == 180)
    }

    @Test("The minus and plus buttons move 5 minutes and stop at the limits")
    func nudging() {
        var clock = ClockSetting(minutes: 50)
        #expect(clock.nudge(1))
        #expect(clock.minutes == 55)
        #expect(clock.nudge(-10))
        #expect(clock.minutes == 20)
        #expect(!clock.nudge(-1))
        #expect(clock.nudge(100))
        #expect(clock.minutes == 180)
    }

    @Test("A touch's angle is measured clockwise from 12")
    func touchAngle() {
        #expect(ClockSetting.angle(dx: 0, dy: -10) == 0)
        #expect(ClockSetting.angle(dx: 10, dy: 0) == 90)
        #expect(ClockSetting.angle(dx: 0, dy: 10) == 180)
        #expect(ClockSetting.angle(dx: -10, dy: 0) == 270)
    }
}
