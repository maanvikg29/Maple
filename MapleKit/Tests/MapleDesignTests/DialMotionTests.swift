import CoreGraphics
import Foundation
import MapleCore
import Testing
@testable import MapleDesign

// MARK: - Turning

/// Turning the dial (F1 design §4.5): 30° of turn is one 5-minute step.
@Suite("Dial turning")
struct DialTurnTrackerTests {
    private let centre = CGPoint(x: 100, y: 100)

    /// The point `degrees` clockwise from 12 o'clock, 80 points out.
    private func point(_ degrees: Double) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(x: 100 + 80 * sin(radians), y: 100 - 80 * cos(radians))
    }

    @Test("Angles run clockwise from 12 o'clock")
    func angles() {
        #expect(abs(DialTurnTracker.angle(of: CGPoint(x: 100, y: 0), around: centre)) < 1e-9)
        #expect(abs(DialTurnTracker.angle(of: CGPoint(x: 200, y: 100), around: centre) - 90) < 1e-9)
        #expect(abs(DialTurnTracker.angle(of: CGPoint(x: 100, y: 200), around: centre) - 180) < 1e-9)
        #expect(abs(DialTurnTracker.angle(of: CGPoint(x: 0, y: 100), around: centre) - 270) < 1e-9)
    }

    @Test("Each 30° is a step: clockwise lengthens, anticlockwise shortens, and what's left over carries")
    func steps() {
        var tracker = DialTurnTracker()
        #expect(tracker.move(to: point(29), from: point(0), around: centre, deadZone: 20) == 0)
        #expect(tracker.move(to: point(31), from: point(0), around: centre, deadZone: 20) == 1)
        #expect(abs(tracker.pending - 1) < 1e-6)
        #expect(tracker.move(to: point(91), from: point(0), around: centre, deadZone: 20) == 2)
        #expect(tracker.move(to: point(1), from: point(0), around: centre, deadZone: 20) == -2)
        #expect(abs(tracker.pending - -29) < 1e-6)
        tracker.end()
        #expect(tracker.lastAngle == nil && tracker.pending == 0)
        // Exactly 30° is a whole step.
        #expect(tracker.move(to: point(30), from: point(0), around: centre, deadZone: 20) == 1)
    }

    @Test("Crossing 12 o'clock turns the short way round")
    func crossingTwelve() {
        var tracker = DialTurnTracker()
        #expect(tracker.move(to: point(10), from: point(350), around: centre, deadZone: 20) == 0)
        #expect(abs(tracker.pending - 20) < 1e-6)
        #expect(tracker.move(to: point(20), from: point(350), around: centre, deadZone: 20) == 1)
        #expect(tracker.move(to: point(340), from: point(350), around: centre, deadZone: 20) == -1)
    }

    @Test("At accessibility sizes only a band around the rim turns the dial, so a drag that starts inside it scrolls the page; at other sizes the whole dial turns")
    func rimOnly() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 200)
        let whole = DialTurnArea(rimOnly: false).path(in: rect)
        let rim = DialTurnArea(rimOnly: true).path(in: rect)
        func out(_ distance: CGFloat) -> CGPoint { CGPoint(x: 100, y: 100 - distance) }
        // Default sizes: anywhere on the dial.
        for distance: CGFloat in [0, 30, 55, 60, 95] { #expect(whole.contains(out(distance), eoFill: true)) }
        // Accessibility sizes: the leaf, the numeral and the caption scroll; the marks' band turns.
        for distance: CGFloat in [0, 30, 55] { #expect(!rim.contains(out(distance), eoFill: true)) }
        for distance: CGFloat in [60, 80, 95] { #expect(rim.contains(out(distance), eoFill: true)) }
        // Never outside the dial.
        #expect(!rim.contains(CGPoint(x: 2, y: 2), eoFill: true))
        #expect(!whole.contains(CGPoint(x: 2, y: 2), eoFill: true))
        // The band is 40% of the radius, and never under a 44pt target.
        #expect(DialTurnArea.innerRadius(radius: 100) == 56)
        #expect(DialTurnArea.innerRadius(radius: 200) == 120)
        #expect(DialTurnArea.innerRadius(radius: 40) == 0)
    }

    @Test("Touches near the centre are ignored, and a new touch starts from where it lands")
    func deadZone() {
        var tracker = DialTurnTracker()
        #expect(tracker.move(to: CGPoint(x: 105, y: 95), from: CGPoint(x: 100, y: 100), around: centre, deadZone: 20) == 0)
        #expect(tracker.lastAngle == nil)
        _ = tracker.move(to: point(100), from: point(90), around: centre, deadZone: 20)
        tracker.end()
        #expect(tracker.move(to: point(200), from: point(200), around: centre, deadZone: 20) == 0)
        #expect(tracker.move(to: point(232), from: point(200), around: centre, deadZone: 20) == 1)
    }
}

// MARK: - The finish

/// The finish (F1 design §4.6) as frames at a time `t`.
@Suite("Finish timeline")
struct FinishTimelineTests {
    private let all = Array(repeating: true, count: 50)
    private let samples = stride(from: -0.5, through: 3.0, by: 0.01).map { $0 }

    private func frame(
        _ t: Double, counted: [Bool]? = nil, gold: Bool = true, leaf: Bool = true, reduceMotion: Bool = false
    ) -> FinishFrame {
        FinishTimeline.frame(at: t, counted: counted ?? all, gold: gold, leafOpened: leaf, reduceMotion: reduceMotion)
    }

    @Test("Counted marks sweep gold one after another, 14 ms apart, each over 0.9 s and peaking a quarter of the way in")
    func sweepOrder() throws {
        let stagger = FinishTimeline.sweepStagger
        #expect(frame(0).tone == .gold)
        let tenth = frame(10 * stagger + 0.001)
        #expect(tenth.sweep[10] > 0 && tenth.sweep[11] == 0 && tenth.sweep[9] > tenth.sweep[10])
        let peak = FinishTimeline.sweepDuration * FinishTimeline.sweepPeak
        #expect(abs(frame(peak).sweep[0] - 1) < 1e-6)
        #expect(frame(0.89).sweep[0] > 0 && frame(0.9).sweep[0] == 0)
        #expect(frame(49 * stagger - 0.001).sweep[49] == 0 && frame(49 * stagger + 0.001).sweep[49] > 0)
        // Each mark rises, then fades back to the receipt's mark.
        let mark = samples.map { frame($0).sweep[20] }
        let top = try #require(mark.indices.max { mark[$0] < mark[$1] })
        #expect((1..<top).allSatisfy { mark[$0] >= mark[$0 - 1] })
        #expect((top + 1..<mark.count).allSatisfy { mark[$0] <= mark[$0 - 1] })
        #expect(frame(3).sweep.allSatisfy { $0 == 0 })
    }

    @Test("Marks that didn't count stay out of a gold sweep")
    func gapsStayOut() {
        let counted = (0..<50).map { !(22..<27).contains($0) }
        #expect(samples.allSatisfy { frame($0, counted: counted).tone == .gold })
        #expect(samples.allSatisfy { frame($0, counted: counted).sweep[22..<27].allSatisfy { $0 == 0 } })
        #expect(frame(23 * FinishTimeline.sweepStagger + 0.1, counted: counted).sweep[27] > 0)
    }

    @Test("A session that counted nothing finishes in white, sweeping every mark")
    func white() {
        let none = Array(repeating: false, count: 50)
        #expect(frame(0.5, counted: none).tone == .white)
        #expect((0..<50).allSatisfy { frame(Double($0) * FinishTimeline.sweepStagger + 0.1, counted: none).sweep[$0] > 0 })
        #expect(FinishTimeline.tone(counted: [], gold: true) == .white)
    }

    @Test("A receipt that isn't gold sweeps only its counted marks, in white: 18 lit of 50 leave the 32 gaps out")
    func whiteOverCounted() {
        let counted = (0..<50).map { $0 < 18 }
        #expect(FinishTimeline.tone(counted: counted, gold: false) == .white)
        #expect(FinishTimeline.tone(counted: counted, gold: true) == .gold)
        #expect(samples.allSatisfy { frame($0, counted: counted, gold: false).tone == .white })
        #expect(samples.allSatisfy { frame($0, counted: counted, gold: false).sweep[18...].allSatisfy { $0 == 0 } })
        let stagger = FinishTimeline.sweepStagger
        #expect((0..<18).allSatisfy { frame(Double($0) * stagger + 0.1, counted: counted, gold: false).sweep[$0] > 0 })
    }

    @Test("Reduce Motion: no ripple, pulse or rise; the leaf is at its final size at once and the words cross-fade")
    func reduceMotion() {
        let still = samples.allSatisfy { t in
            let f = frame(t, reduceMotion: true)
            return f.rippleOpacity == 0 && f.glowScale == 1 && f.glowOpacity == 1
                && f.numeralRise == 0 && f.lineRise == 0 && f.actionsRise == 0
        }
        #expect(still)
        #expect(frame(0, reduceMotion: true).leafGrow == 1)
        #expect(frame(0, leaf: false, reduceMotion: true).leafGrow == 0)
        #expect(frame(0.3, reduceMotion: true).lineOpacity == 0 && frame(0.7, reduceMotion: true).lineOpacity > 0)
        #expect(FinishTimeline.settledTime(markCount: 50, reduceMotion: true) == 1.8)
    }

    @Test("Reduce Motion: no sweep; the counted marks cross-fade to gold together, 0 to 1 over 0.6 s, held to 1.2 s, back by 1.8 s")
    func reduceMotionGold() throws {
        // Every mark at the same stage: no stagger and no travel.
        #expect(samples.allSatisfy { Set(frame($0, reduceMotion: true).sweep).count == 1 })
        let gold = samples.map { frame($0, reduceMotion: true).sweep[0] }
        #expect(gold.allSatisfy { $0 >= 0 && $0 <= 1 })
        #expect(frame(0, reduceMotion: true).sweep[0] == 0)
        let rising = frame(0.3, reduceMotion: true).sweep[0]
        #expect(rising > 0 && rising < 1)
        #expect([0.6, 0.9, 1.2].allSatisfy { frame($0, reduceMotion: true).sweep[0] == 1 })
        let falling = frame(1.5, reduceMotion: true).sweep[0]
        #expect(falling > 0 && falling < 1)
        #expect([1.8, 3].allSatisfy { frame($0, reduceMotion: true).sweep.allSatisfy { $0 == 0 } })
        // Up, held, then down: never back and forth.
        let held = gold.indices.filter { gold[$0] == 1 }
        let first = try #require(held.first), last = try #require(held.last)
        #expect((1..<first).allSatisfy { gold[$0] >= gold[$0 - 1] })
        #expect((last + 1..<gold.count).allSatisfy { gold[$0] <= gold[$0 - 1] })
        // Gaps stay out of a gold finish; a session that counted nothing fades every mark, in white.
        let counted = (0..<50).map { !(22..<27).contains($0) }
        #expect(samples.allSatisfy { frame($0, counted: counted, reduceMotion: true).sweep[22..<27].allSatisfy { $0 == 0 } })
        #expect(frame(0.9, counted: counted, reduceMotion: true).sweep[27] == 1)
        let none = frame(0.9, counted: Array(repeating: false, count: 50), reduceMotion: true)
        #expect(none.tone == .white && none.sweep.allSatisfy { $0 == 1 })
    }

    @Test("An opened leaf grows into the centre over 0.8 s with an ease-out that never overshoots")
    func leafGrows() {
        let grow = samples.map { frame($0).leafGrow }
        #expect(grow.allSatisfy { $0 >= 0 && $0 <= 1 })
        #expect(zip(grow, grow.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(frame(FinishTimeline.leafGrowDuration).leafGrow == 1)
        #expect(frame(0.4).leafGrow > 0.5, "an ease-out runs ahead of a straight line")
        #expect(samples.allSatisfy { frame($0, leaf: false).leafGrow == 0 })
    }

    @Test("The ring ripples out over 1.5 s from 0.15 s, and the glow pulses once")
    func rippleAndGlow() {
        let start = FinishTimeline.rippleStart, end = start + FinishTimeline.rippleDuration
        #expect(frame(start - 0.01).rippleOpacity == 0)
        #expect(abs(frame(start).rippleOpacity - 0.7) < 1e-9 && abs(frame(start).rippleScale - 0.55) < 1e-9)
        #expect(frame(end).rippleOpacity < 1e-6 && abs(frame(end).rippleScale - 1.3) < 1e-9)
        let scales = samples.map { frame($0).glowScale }
        #expect(abs((scales.max() ?? 0) - 1.25) < 0.01 && scales.allSatisfy { $0 >= 1 })
        #expect(frame(0.05).glowScale == 1 && frame(2).glowScale == 1 && frame(2).glowOpacity == 1)
        #expect(samples.contains { frame($0).glowOpacity < 0.8 })
    }

    @Test("The leaf line, then Done and Again, fade in at 0.4 s and 0.6 s, each over at least 0.6 s")
    func fadeIns() {
        for reduceMotion in [false, true] {
            #expect(frame(0.4, reduceMotion: reduceMotion).lineOpacity == 0)
            #expect(frame(0.99, reduceMotion: reduceMotion).lineOpacity < 1)
            #expect(frame(1.0, reduceMotion: reduceMotion).lineOpacity == 1)
            #expect(frame(0.6, reduceMotion: reduceMotion).actionsOpacity == 0)
            #expect(frame(1.19, reduceMotion: reduceMotion).actionsOpacity < 1)
            #expect(frame(1.2, reduceMotion: reduceMotion).actionsOpacity == 1)
            #expect(frame(0.59, reduceMotion: reduceMotion).numeralOpacity < 1)
            #expect(frame(0.6, reduceMotion: reduceMotion).numeralOpacity == 1)
        }
        let line = samples.map { frame($0).lineOpacity }
        #expect(zip(line, line.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(frame(0.7).lineRise > 0 && frame(1.0).lineRise == 0)
    }

    @Test("The fade-ins ease in and out over their 0.6 s as `gentle` does, so none reads as instant, and the rises follow")
    func fadeShape() {
        let quarter = FinishTimeline.fadeDuration / 4, half = FinishTimeline.fadeDuration / 2
        for reduceMotion in [false, true] {
            let numeral = frame(quarter, reduceMotion: reduceMotion).numeralOpacity
            let line = frame(FinishTimeline.lineStart + quarter, reduceMotion: reduceMotion).lineOpacity
            let actions = frame(FinishTimeline.actionsStart + quarter, reduceMotion: reduceMotion).actionsOpacity
            #expect(numeral < 0.25 && line < 0.25 && actions < 0.25, "a quarter in: \(numeral), \(line), \(actions)")
            #expect(abs(frame(FinishTimeline.lineStart + half, reduceMotion: reduceMotion).lineOpacity - 0.5) < 0.01)
        }
        #expect(abs(frame(half).numeralRise - 4) < 0.1)
        #expect(abs(frame(FinishTimeline.lineStart + half).lineRise - 5) < 0.1)
        #expect(abs(frame(FinishTimeline.actionsStart + half).actionsRise - 5) < 0.1)
    }

    @Test("Nothing moves after the settled time; times out of range give the first or the last frame")
    func settles() {
        let settled = FinishTimeline.settledTime(markCount: 50, reduceMotion: false)
        #expect(abs(settled - 1.7) < 1e-9)
        #expect(frame(settled) == frame(settled + 5))
        #expect(frame(.nan) == frame(100))
        let before = frame(-1)
        #expect(before.sweep.allSatisfy { $0 == 0 } && before.leafGrow == 0)
        #expect(before.numeralOpacity == 0 && before.lineOpacity == 0 && before.actionsOpacity == 0)
    }
}

// MARK: - Holds

/// A hold's progress (F1 design §4.7, F1-22): it fills while pressed, drains at the same rate when let go, and can be
/// filled by a countdown instead.
@Suite("Hold progress")
struct HoldProgressTests {
    private func after(_ seconds: Double) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }

    @Test("Progress is the share of the hold's length held, from 0 to 1, and drains at the same rate")
    func progress() {
        #expect(HoldProgress.progress(heldFor: 0.75, duration: 1.5) == 0.5)
        #expect(HoldProgress.progress(heldFor: 3, duration: 1.5) == 1)
        #expect(HoldProgress.progress(heldFor: -1, duration: 1.5) == 0)
        #expect(HoldProgress.progress(heldFor: .nan, duration: 10) == 0)
        #expect(HoldProgress.drained(from: 0.5, releasedFor: 0.375, duration: 1.5) == 0.25)
        #expect(HoldProgress.drained(from: 0.5, releasedFor: 5, duration: 1.5) == 0)
    }

    @Test("Letting go early drains at the rate it filled, and never completes")
    func drains() {
        var hold = HoldProgress(duration: 1.5)
        hold.press(at: after(0))
        #expect(hold.value(at: after(0.75)) == 0.5)
        #expect(hold.phase(at: after(0.75)) == .filling && hold.isFilling)
        hold.release(at: after(0.75))
        #expect(abs(hold.value(at: after(1.125)) - 0.25) < 1e-9)
        #expect(hold.value(at: after(1.5)) == 0)
        #expect(hold.phase(at: after(1.0)) == .draining)
        #expect(hold.phase(at: after(2)) == .idle)
        #expect(!hold.isFilled(at: after(10)) && !hold.isComplete)
    }

    @Test("Pressing again mid-drain carries on from where the drain had got to")
    func resumes() {
        var hold = HoldProgress(duration: 10)
        hold.press(at: after(0))
        hold.release(at: after(6))
        hold.press(at: after(8))
        #expect(abs(hold.value(at: after(8)) - 0.4) < 1e-9)
        #expect(!hold.isFilled(at: after(13.9)))
        #expect(hold.isFilled(at: after(14)))
        #expect(hold.phase(at: after(14)) == .complete)
    }

    @Test("A countdown fills over the same length, shows whole seconds left, and cancels into a drain")
    func countdown() {
        var hold = HoldProgress(duration: 10)
        hold.startCountdown(at: after(0))
        #expect(hold.isCountdown && hold.isFilling)
        #expect(hold.secondsLeft(at: after(0)) == 10)
        #expect(hold.secondsLeft(at: after(0.2)) == 10)
        #expect(hold.secondsLeft(at: after(9.5)) == 1)
        #expect(hold.isFilled(at: after(10)))
        var cancelled = HoldProgress(duration: 10)
        cancelled.startCountdown(at: after(0))
        cancelled.release(at: after(4))
        #expect(!cancelled.isCountdown && cancelled.phase(at: after(5)) == .draining)
        #expect(cancelled.value(at: after(8)) == 0)
    }

    @Test("Once finished the hold stays full and ignores presses, releases and countdowns until it is reset")
    func finish() {
        var hold = HoldProgress(duration: 1.5)
        hold.press(at: after(0))
        hold.finish()
        #expect(hold.isComplete && hold.value(at: after(100)) == 1 && hold.phase(at: after(100)) == .complete)
        hold.press(at: after(2))
        hold.release(at: after(2.1))
        hold.startCountdown(at: after(3))
        #expect(hold.isComplete && !hold.isCountdown && hold.value(at: after(4)) == 1)
        hold.reset()
        #expect(!hold.isComplete && hold.value(at: after(5)) == 0 && hold.phase(at: after(5)) == .idle)
    }

    @Test("A release without a press does nothing, and a second press doesn't restart the fill")
    func idempotent() {
        var hold = HoldProgress(duration: 3)
        hold.release(at: after(1))
        #expect(hold.phase(at: after(1)) == .idle)
        hold.press(at: after(0))
        hold.press(at: after(1))
        #expect(abs(hold.value(at: after(1.5)) - 0.5) < 1e-9)
    }
}

// MARK: - Copy

@Suite("Hold and dial copy")
struct HoldCopyTests {
    @Test("The dial's VoiceOver label, the hold's named actions and the countdown's label")
    func copy() {
        #expect(FocusCopy.dialLengthLabel == "Session length")
        #expect(FocusCopy.holdCountdownAction == "Start countdown")
        #expect(FocusCopy.holdCancelAction == "Cancel countdown")
        #expect(FocusCopy.holdCountdownTitle(secondsLeft: 8) == "Cancel · 8s")
        #expect(FocusCopy.holdCountdownTitle(secondsLeft: 0) == "Cancel · 1s")
    }
}
