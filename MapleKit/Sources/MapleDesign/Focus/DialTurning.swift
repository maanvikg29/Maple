import MapleCore
import SwiftUI

extension View {
    /// Turning the dial sets the session's length (F1 design §4.5): each 30° of turn is 5 minutes, so a full turn is
    /// an hour, within 20 minutes to 3 hours. A step is taken at its halfway point, so the dial settles on the nearer
    /// length when the finger lifts. Each step plays the `.selection` haptic. VoiceOver reads the dial as one
    /// adjustable element, "Session length, 50 minutes", which swipes up or down by 5 minutes (§4.9).
    ///
    /// `turn` reports the part of a step the finger is through, -0.5…0.5, and 0 between touches, so the marks can
    /// follow the finger between lengths (`MinuteDial.spread(_:follows:)`, F1-33).
    ///
    /// At accessibility sizes the start screen scrolls (§5.17), so only a band around the rim turns the dial
    /// (`DialTurnArea`): a drag that starts inside it scrolls the page. The adjustable action still turns it.
    ///
    /// ```swift
    /// MinuteDial(frame: .preview(layout: DialLayout(plannedMinutes: minutes), leafMinute: model.leafMinute),
    ///            diameter: diameter, theme: theme) { … }
    ///     .dialTurning(minutes: $minutes, enabled: !isMinimisedSession) { hasTurned = true }
    /// ```
    ///
    /// - Parameters:
    ///   - minutes: This session's length. Turning changes only it; holding a chip edits the preset.
    ///   - enabled: False while the start screen can't turn the dial (`StartScreenModel.canTurn`, e.g. locking). It then can't be turned but still reads "Session length, 50 minutes"; a caller that needs another reading labels it after this modifier.
    ///   - turn: The part of a step under way, for the marks to follow; nil when nothing follows it.
    ///   - onTurn: Called after each step, by touch or by VoiceOver: the start screen's hint goes once the dial has
    ///     turned.
    public func dialTurning(
        minutes: Binding<Int>, enabled: Bool, turn: Binding<Double>? = nil, onTurn: (() -> Void)? = nil
    ) -> some View {
        modifier(DialTurningModifier(minutes: minutes, enabled: enabled, turn: turn, onTurn: onTurn))
    }
}

private struct DialTurningModifier: ViewModifier {
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var minutes: Int
    let enabled: Bool
    let turn: Binding<Double>?
    let onTurn: (() -> Void)?
    @State private var tracker = DialTurnTracker()
    @State private var size = CGSize.zero
    @State private var steps = 0
    /// True while a turn is under way. It resets when the drag ends and also when it is cancelled (the system takes
    /// the touch, or `enabled` switches the gesture off mid-turn), which never reaches `onEnded`.
    @GestureState private var isTurning = false

    /// One chain whichever way `enabled` is, so the dial keeps its identity (and its animations) when the start
    /// screen's stage flips it: the turn gesture is switched off in place, and the adjustable action is added to the
    /// same accessibility attachment or left off it. Either way the dial is one element reading "Session length,
    /// 50 minutes" (§4.9).
    func body(content: Content) -> some View {
        let element = content
            // The whole dial, or at accessibility sizes only its rim, so the page scrolls from inside it.
            .contentShape(DialTurnArea(rimOnly: dynamicTypeSize.isAccessibilitySize), eoFill: true)
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { newSize in
                size = newSize
            }
            .gesture(turnGesture, isEnabled: enabled)
            .onChange(of: isTurning) { _, turning in
                // A turn that ended or was cancelled: the next one starts afresh, never from a stale angle.
                if !turning { endTurn() }
            }
            .sensoryFeedback(.selection, trigger: steps)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(FocusCopy.dialLengthLabel))
            .accessibilityValue(Text(FocusTimeText.spokenLength(minutes: minutes, locale: locale)))
        // An accessibility modifier on an accessibility attachment returns the attachment's own type, so this picks
        // between two values of one view type, not two branches: no `_ConditionalContent`, no new identity.
        enabled
            ? element.accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: step(by: 1)
                case .decrement: step(by: -1)
                @unknown default: break
                }
            }
            : element
    }

    /// Each 30° of turn around the dial's centre is a step, from wherever the touch lands outside the dead zone.
    private var turnGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .updating($isTurning) { _, turning, _ in turning = true }
            .onChanged { value in
                let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                let turned = tracker.move(
                    to: value.location, from: value.startLocation, around: centre,
                    deadZone: min(size.width, size.height) * DialTurnTracker.deadZoneFraction
                )
                if turned != 0 { step(by: turned) }
                turn?.wrappedValue = tracker.fraction
            }
            .onEnded { _ in endTurn() }
    }

    /// The finger lifted, or the turn was cancelled: the marks settle on the length.
    private func endTurn() {
        tracker.end()
        if turn?.wrappedValue != 0 { turn?.wrappedValue = 0 }
    }

    /// Moves the length by `count` steps from where it is. Clamped at 20 minutes and 3 hours; a step that changes
    /// nothing plays no haptic.
    private func step(by count: Int) {
        let next = DialLayout.stepped(minutes, by: count)
        guard next != minutes else { return }
        minutes = next
        steps += 1
        onTurn?()
    }
}

/// Where a touch can start turning the dial: the whole dial, or at accessibility sizes (`rimOnly`) only the band of its
/// rim, where the marks are, so a drag that starts on the leaf, the numeral or the caption scrolls the start screen's
/// page (F1 design §5.17). The band is 40% of the radius and never under a 44pt target. Filled even-odd: the inner
/// circle is a hole.
nonisolated struct DialTurnArea: Shape {
    let rimOnly: Bool

    /// The hole's radius in a dial of `radius`: the rim band is 40% of it, and at least 44pt.
    static func innerRadius(radius: CGFloat) -> CGFloat {
        max(0, radius - max(44, radius * 0.4))
    }

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
        let inner = rimOnly ? Self.innerRadius(radius: radius) : 0
        if inner > 0 {
            path.addEllipse(in: CGRect(x: centre.x - inner, y: centre.y - inner, width: inner * 2, height: inner * 2))
        }
        return path
    }
}

/// Turns a touch moving around the dial's centre into whole 5-minute steps, from the length as it is now (so
/// turning back right after a limit works at once). Each step is taken halfway through its 30°, so what is left over
/// is never more than half a step either way. It is pure, so the arithmetic is tested without a gesture.
nonisolated struct DialTurnTracker: Sendable, Equatable {
    /// Touches nearer the centre than this share of the dial's side are ignored, because their angle swings wildly.
    static let deadZoneFraction: CGFloat = 0.15

    /// The touch's last angle in degrees clockwise from 12 o'clock; nil between touches.
    private(set) var lastAngle: Double?
    /// Degrees turned since the last step, -15…15: a step is taken at its halfway point.
    private(set) var pending: Double = 0

    /// The part of a step the finger is through, -0.5…0.5.
    var fraction: Double { pending / DialLayout.degreesPerStep }

    /// Degrees clockwise from 12 o'clock (0..<360) of `point` around `centre`, with y pointing down.
    static func angle(of point: CGPoint, around centre: CGPoint) -> Double {
        let degrees = atan2(Double(point.x - centre.x), Double(centre.y - point.y)) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }

    /// Feeds the touch at `point` (it began at `start`) and returns the whole steps it completes, positive
    /// clockwise. Turning across 12 o'clock goes the short way round.
    mutating func move(to point: CGPoint, from start: CGPoint, around centre: CGPoint, deadZone: CGFloat) -> Int {
        guard hypot(point.x - centre.x, point.y - centre.y) > deadZone else { return 0 }
        let angle = Self.angle(of: point, around: centre)
        if lastAngle == nil, hypot(start.x - centre.x, start.y - centre.y) > deadZone {
            lastAngle = Self.angle(of: start, around: centre)
        }
        guard let last = lastAngle else {
            lastAngle = angle
            return 0
        }
        var delta = angle - last
        if delta > 180 {
            delta -= 360
        } else if delta < -180 {
            delta += 360
        }
        lastAngle = angle
        pending += delta
        // A hair of slack, so exactly half a step makes one through floating point.
        let steps = Int(((pending + (pending >= 0 ? 1e-6 : -1e-6)) / DialLayout.degreesPerStep).rounded(.toNearestOrAwayFromZero))
        pending -= Double(steps) * DialLayout.degreesPerStep
        return steps
    }

    /// The touch lifted: the next one starts afresh.
    mutating func end() {
        lastAngle = nil
        pending = 0
    }
}
