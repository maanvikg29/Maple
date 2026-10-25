import MapleCore
import SwiftUI

extension View {
    /// Turning the dial sets the session's length (F1 design §4.5): each 30° of turn is 5 minutes, so a full turn is
    /// an hour, within 20 minutes to 3 hours. Each step plays the `.selection` haptic. VoiceOver reads the dial as
    /// one adjustable element, "Session length, 50 minutes", which swipes up or down by 5 minutes (§4.9).
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
    ///   - onTurn: Called after each step, by touch or by VoiceOver: the start screen's hint goes once the dial has
    ///     turned.
    public func dialTurning(minutes: Binding<Int>, enabled: Bool, onTurn: (() -> Void)? = nil) -> some View {
        modifier(DialTurningModifier(minutes: minutes, enabled: enabled, onTurn: onTurn))
    }
}

private struct DialTurningModifier: ViewModifier {
    @Environment(\.locale) private var locale
    @Binding var minutes: Int
    let enabled: Bool
    let onTurn: (() -> Void)?
    @State private var tracker = DialTurnTracker()
    @State private var size = CGSize.zero
    @State private var steps = 0

    func body(content: Content) -> some View {
        if enabled {
            content
                .contentShape(Circle())
                .onGeometryChange(for: CGSize.self) { proxy in
                    proxy.size
                } action: { newSize in
                    size = newSize
                }
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                            let turned = tracker.move(
                                to: value.location, from: value.startLocation, around: centre,
                                deadZone: min(size.width, size.height) * DialTurnTracker.deadZoneFraction
                            )
                            if turned != 0 { step(by: turned) }
                        }
                        .onEnded { _ in tracker.end() }
                )
                .sensoryFeedback(.selection, trigger: steps)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(FocusCopy.dialLengthLabel))
                .accessibilityValue(Text(FocusTimeText.spokenLength(minutes: minutes, locale: locale)))
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: step(by: 1)
                    case .decrement: step(by: -1)
                    @unknown default: break
                    }
                }
        } else {
            // Not turnable (the start is locking): still one element reading "Session length, 50 minutes" (§4.9).
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(FocusCopy.dialLengthLabel))
                .accessibilityValue(Text(FocusTimeText.spokenLength(minutes: minutes, locale: locale)))
        }
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

/// Turns a touch moving around the dial's centre into whole 5-minute steps, from the length as it is now (so
/// turning back right after a limit works at once). It is pure, so the arithmetic is tested without a gesture.
nonisolated struct DialTurnTracker: Sendable, Equatable {
    /// Touches nearer the centre than this share of the dial's side are ignored, because their angle swings wildly.
    static let deadZoneFraction: CGFloat = 0.15

    /// The touch's last angle in degrees clockwise from 12 o'clock; nil between touches.
    private(set) var lastAngle: Double?
    /// Degrees turned that haven't made a whole step yet.
    private(set) var pending: Double = 0

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
        // A hair of slack, so exactly 30° makes a whole step through floating point.
        let steps = Int(((pending + (pending >= 0 ? 1e-6 : -1e-6)) / DialLayout.degreesPerStep).rounded(.towardZero))
        pending -= Double(steps) * DialLayout.degreesPerStep
        return steps
    }

    /// The touch lifted: the next one starts afresh.
    mutating func end() {
        lastAngle = nil
        pending = 0
    }
}
