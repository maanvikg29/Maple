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
        var moved = false
        var clock = ClockSetting(minutes: 50)
        moved = clock.turn(toAngle: 330)
        #expect(moved)
        #expect(clock.minutes == 55)
        moved = clock.turn(toAngle: 0)
        #expect(moved)
        #expect(clock.minutes == 60)
        moved = clock.turn(toAngle: 30)
        #expect(moved)
        #expect(clock.minutes == 65)
        moved = clock.turn(toAngle: 330)
        #expect(moved)
        #expect(clock.minutes == 55)
        moved = clock.turn(toAngle: 331)
        #expect(!moved)
        #expect(clock.minutes == 55)
    }

    @Test("An angle outside one turn, or a touch that isn't a number, is handled")
    func oddAngles() {
        var moved = false
        var clock = ClockSetting(minutes: 50)
        clock.turn(toAngle: 690)
        #expect(clock.minutes == 55)
        clock.turn(toAngle: -60)
        #expect(clock.minutes == 50)
        moved = clock.turn(toAngle: .nan)
        #expect(!moved)
        moved = clock.turn(toAngle: .infinity)
        #expect(!moved)
        #expect(clock.minutes == 50)
    }

    @Test("The hand stops at 3 hours and at 20 minutes and never wraps round")
    func limits() {
        var moved = false
        var long = ClockSetting(minutes: 180)
        moved = long.turn(toAngle: 90)
        #expect(!moved)
        #expect(long.minutes == 180)
        moved = long.turn(toAngle: 270)
        #expect(moved)
        #expect(long.minutes == 165)
        var short = ClockSetting(minutes: 20)
        moved = short.turn(toAngle: 0)
        #expect(!moved)
        #expect(short.minutes == 20)
        for _ in 0 ..< 100 { long.turn(toAngle: 90); long.turn(toAngle: 180); long.turn(toAngle: 270); long.turn(toAngle: 0) }
        #expect(long.minutes == 180)
    }

    @Test("Spinning on past 3 hours keeps the hand at 3 hours at every step of the way, not only at the end")
    func spinningPastTheTop() {
        var clock = ClockSetting(minutes: 170)
        var seen: [Int] = []
        // Three more turns clockwise, a touch every 5 minutes of the face.
        for step in 1 ... 36 * 3 {
            clock.turn(toAngle: Double(170 % 60 + step * 5) * 6)
            seen.append(clock.minutes)
        }
        #expect(seen.prefix(3) == [175, 180, 180])
        #expect(seen.dropFirst(1).allSatisfy { $0 == 180 })
    }

    @Test("Spinning back past 20 minutes keeps the hand at 20 minutes at every step")
    func spinningPastTheBottom() {
        var clock = ClockSetting(minutes: 30)
        var seen: [Int] = []
        for step in 1 ... 36 * 3 {
            clock.turn(toAngle: Double(30 - step * 5) * 6)
            seen.append(clock.minutes)
        }
        #expect(seen.prefix(3) == [25, 20, 20])
        #expect(seen.dropFirst(1).allSatisfy { $0 == 20 })
    }

    @Test("After spinning past the limit, the hand moves again when the finger comes back round to it")
    func comingBack() {
        var clock = ClockSetting(minutes: 180)
        // A quarter turn past the top: the hand waits at 12.
        for minute in [5, 10, 15] { clock.turn(toAngle: Double(minute) * 6) }
        #expect(clock.minutes == 180)
        // Back to the hand: still 3 hours. Past it: the length comes down.
        for minute in [10, 5, 0] { clock.turn(toAngle: Double(minute) * 6) }
        #expect(clock.minutes == 180)
        clock.turn(toAngle: 55 * 6)
        #expect(clock.minutes == 175)
    }

    @Test("Lifting the finger forgets how far past the limit it went, so the next touch starts from the hand")
    func settling() {
        var clock = ClockSetting(minutes: 180)
        for minute in [5, 10, 15, 20, 25] { clock.turn(toAngle: Double(minute) * 6) }
        clock.settle()
        // A new touch at 8 on the face: the shortest way from 12 is 20 minutes back.
        clock.turn(toAngle: 40 * 6)
        #expect(clock.minutes == 160)
    }

    @Test("The long hand's turn keeps counting past each hour, so it never swings back the long way at 12")
    func turnKeepsCounting() {
        #expect(ClockSetting(minutes: 55).minuteTurn == 330)
        #expect(ClockSetting(minutes: 60).minuteTurn == 360)
        #expect(ClockSetting(minutes: 90).minuteTurn == 540)
    }

    @Test("The minus and plus buttons move 5 minutes and stop at the limits")
    func nudging() {
        var moved = false
        var clock = ClockSetting(minutes: 50)
        moved = clock.nudge(1)
        #expect(moved)
        #expect(clock.minutes == 55)
        moved = clock.nudge(-10)
        #expect(moved)
        #expect(clock.minutes == 20)
        moved = clock.nudge(-1)
        #expect(!moved)
        moved = clock.nudge(100)
        #expect(moved)
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
