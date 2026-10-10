import MapleCore
import SwiftUI

/// Rest › Sleep's hero object (spec §8.1): the member's schedule on a 24-hour ring, 280pt across.
///
/// - Midnight sits at the top and the day runs clockwise, so the night is the arc over the top.
/// - A 2pt track (`track`); the bed-to-wake arc is 3pt in the season tint, and the wind-down before it the same
///   tint at 40%.
/// - A 10pt crescent moon marks the current time, with the faint moonlight pool the sky's moon has.
/// - Quiet hour ticks inside the ring, with the four quarter hours labelled in the locale's clock style.
///
/// It never sits in a card, and it reads as one VoiceOver element that describes the schedule.
///
/// ```swift
/// TimelineView(.everyMinute) { context in
///     let now = clock.date(forTimeline: context.date)
///     SleepDial(schedule: schedule.schedule, now: HomeFormat.clockTime(of: now, calendar: .current))
/// }
/// ```
public struct SleepDial: View {
    /// The dial's side. Drawings never scale with text.
    public static let diameter: CGFloat = 280

    @Environment(\.theme) private var theme
    @Environment(\.season) private var season
    @Environment(\.locale) private var locale

    private let schedule: SleepSchedule
    private let now: ClockTime?

    /// - Parameters:
    ///   - schedule: The member's bedtime, wake time and wind-down length.
    ///   - now: The current time of day for the moon marker; nil hides it.
    public init(schedule: SleepSchedule, now: ClockTime?) {
        self.schedule = schedule
        self.now = now
    }

    public var body: some View {
        let metrics = SleepDialGeometry(side: Self.diameter)
        let tint = theme.colors.seasonTint(season)
        let windDown = SleepDialGeometry.arc(from: schedule.windDownStart, to: schedule.bedtime)
        let inBed = SleepDialGeometry.arc(from: schedule.bedtime, to: schedule.wake)

        ZStack {
            if let now {
                moonlight(at: metrics.point(at: SleepDialGeometry.fraction(of: now), radius: metrics.ringRadius))
            }
            ticks(metrics)
            labels(metrics)

            Circle()
                .inset(by: metrics.ringInset)
                .stroke(theme.colors.track, lineWidth: SleepDialGeometry.trackWidth)
            if windDown.length > 0 {
                DialArc(start: windDown.start, length: windDown.length, inset: metrics.ringInset)
                    .stroke(tint.opacity(0.4), style: StrokeStyle(lineWidth: SleepDialGeometry.arcWidth, lineCap: .round))
            }
            if inBed.length > 0 {
                DialArc(start: inBed.start, length: inBed.length, inset: metrics.ringInset)
                    .stroke(tint, style: StrokeStyle(lineWidth: SleepDialGeometry.arcWidth, lineCap: .round))
            }

            if let now {
                moon(at: metrics.point(at: SleepDialGeometry.fraction(of: now), radius: metrics.ringRadius))
            }
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Sleep schedule"))
        .accessibilityValue(Text(RestCopy.dialDescription(schedule, now: now, locale: locale)))
    }

    // MARK: Layers

    /// The moon's light on the black: the sky's 6% halo, about 64pt across.
    private func moonlight(at point: CGPoint) -> some View {
        let moonlight = theme.colors.scene.moonlight
        return Circle()
            .fill(RadialGradient(
                stops: [
                    .init(color: moonlight.opacity(0.07), location: 0),
                    .init(color: moonlight.opacity(0.035), location: 0.4),
                    .init(color: moonlight.opacity(0), location: 1),
                ],
                center: .center, startRadius: 0, endRadius: 32
            ))
            .frame(width: 64, height: 64)
            .position(point)
    }

    /// The crescent, cut out of the ring by a ring of background so the track never runs through it.
    private func moon(at point: CGPoint) -> some View {
        let side = SleepDialGeometry.moonDiameter
        return ZStack {
            Circle()
                .fill(theme.colors.background)
                .frame(width: side + 6, height: side + 6)
            // The sky's moon at full strength: on the dial it is a marker, so it has to read at 10pt.
            MoonCrescent()
                .fill(theme.colors.textPrimary)
                .frame(width: side, height: side)
        }
        .position(point)
    }

    /// 24 hour ticks inside the ring, longer at the quarters. Decorative, so `textTertiary`.
    private func ticks(_ metrics: SleepDialGeometry) -> some View {
        Canvas { context, _ in
            for hour in 0..<24 {
                let major = hour % 6 == 0
                let fraction = Double(hour) / 24
                let outer = metrics.ringRadius - SleepDialGeometry.tickGap
                let inner = outer - (major ? SleepDialGeometry.majorTickLength : SleepDialGeometry.minorTickLength)
                var path = Path()
                path.move(to: metrics.point(at: fraction, radius: outer))
                path.addLine(to: metrics.point(at: fraction, radius: inner))
                context.stroke(
                    path, with: .color(theme.colors.textTertiary.opacity(major ? 0.9 : 0.5)),
                    style: StrokeStyle(lineWidth: 1, lineCap: .round)
                )
            }
        }
        .frame(width: Self.diameter, height: Self.diameter)
    }

    /// Midnight, 6, noon and 18 in the locale's clock style ("00", "06", "12", "18" or "12 AM", "6 AM", …), each
    /// with its outer edge the same distance inside the quarter tick, however wide the label is.
    private func labels(_ metrics: SleepDialGeometry) -> some View {
        let inset = metrics.labelInset
        return ZStack {
            label(hour: 0).frame(maxHeight: .infinity, alignment: .top).padding(.top, inset)
            label(hour: 6).frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, inset)
            label(hour: 12).frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, inset)
            label(hour: 18).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, inset)
        }
        .frame(width: Self.diameter, height: Self.diameter)
        // The labels sit inside a drawing that never scales, so they stop growing at the largest standard size.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    private func label(hour: Int) -> some View {
        Text(RestCopy.dialLabel(hour: hour, locale: locale))
            .font(MapleFont.micro.monospacedDigit())
            .foregroundStyle(theme.colors.textSecondary)
            .fixedSize()
    }
}

// MARK: - Geometry

/// The dial's pure geometry: where a time of day sits on the ring, and the arcs between two times.
/// Fractions run clockwise from midnight at the top (0) through 06:00 on the right (0.25).
nonisolated public struct SleepDialGeometry: Sendable, Equatable {
    public static let trackWidth: CGFloat = 2
    public static let arcWidth: CGFloat = 3
    public static let moonDiameter: CGFloat = 10
    /// Space between the ring and the start of the ticks.
    static let tickGap: CGFloat = 9
    static let minorTickLength: CGFloat = 3
    static let majorTickLength: CGFloat = 7

    public let side: CGFloat

    public init(side: CGFloat) {
        self.side = side
    }

    /// How far the ring's centre line sits inside the dial's edge: room for the moon and its cut-out.
    public var ringInset: CGFloat { 12 }
    public var ringRadius: CGFloat { side / 2 - ringInset }
    /// How far the quarter-hour labels' outer edges sit inside the dial's edge: 6pt inside the quarter ticks.
    public var labelInset: CGFloat { ringInset + Self.tickGap + Self.majorTickLength + 6 }
    public var centre: CGPoint { CGPoint(x: side / 2, y: side / 2) }

    /// The point at `fraction` of the day on a circle of `radius` about the dial's centre.
    public func point(at fraction: Double, radius: CGFloat) -> CGPoint {
        let angle = fraction * 2 * .pi
        return CGPoint(x: centre.x + radius * CGFloat(sin(angle)), y: centre.y - radius * CGFloat(cos(angle)))
    }

    /// A time of day as a fraction of the day, 0..<1.
    public static func fraction(of time: ClockTime) -> Double {
        let minutes = ((time.minutesSinceMidnight % 1440) + 1440) % 1440
        return Double(minutes) / 1440
    }

    /// The clockwise arc from `start` to `end`, wrapping midnight. Equal times give an empty arc.
    public static func arc(from start: ClockTime, to end: ClockTime) -> (start: Double, length: Double) {
        let from = fraction(of: start)
        var length = fraction(of: end) - from
        if length < 0 { length += 1 }
        return (from, length)
    }
}

/// A clockwise arc of the dial's ring, `length` of a full turn starting at `start` (fractions of a day from
/// midnight at the top).
nonisolated struct DialArc: Shape {
    var start: Double
    var length: Double
    var inset: CGFloat

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let geometry = SleepDialGeometry(side: side)
        let radius = side / 2 - inset
        let steps = max(2, Int((length * 720).rounded(.up)))
        var path = Path()
        for step in 0...steps {
            let point = geometry.point(at: start + length * Double(step) / Double(steps), radius: radius)
            let shifted = CGPoint(x: rect.minX + (rect.width - side) / 2 + point.x, y: rect.minY + (rect.height - side) / 2 + point.y)
            if step == 0 { path.move(to: shifted) } else { path.addLine(to: shifted) }
        }
        return path
    }
}

/// The sky's crescent moon (a disc with an offset disc taken away, lit toward the lower left), at any size.
nonisolated public struct MoonCrescent: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let r = side / 2
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let disc = Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: side, height: side))
        let bite = Path(ellipseIn: CGRect(
            x: centre.x - r + side * 0.283, y: centre.y - r - side * 0.183, width: side * 0.98, height: side * 0.98
        ))
        return disc.subtracting(bite)
    }
}
