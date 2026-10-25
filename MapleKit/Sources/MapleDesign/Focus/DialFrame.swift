import Foundation
import MapleCore

/// The leaf dot (F1 design §4.1): where on the dial the next hours leaf would open.
nonisolated public struct DialDot: Sendable, Equatable {
    /// Radians clockwise from 12 o'clock (`DialLayout.angle(atMinute:)`).
    public var angle: Double
    /// The leaf has opened: the dot is amber rather than season tint.
    public var reached: Bool

    public init(angle: Double, reached: Bool) {
        self.angle = angle
        self.reached = reached
    }
}

/// The centre leaf's fill (F1 design §4.3), as fractions of the leaf's rung, from the rung below to its threshold.
nonisolated public struct DialFill: Sendable, Equatable {
    /// Saved before this session: the softer gold.
    public let before: Double
    /// This session's counted time on top of it: the brighter gold. `before + session` never passes 1.
    public let session: Double
    /// 0…1: how far the leaf has turned fully gold. The leaf eases over 0.6 s whenever this changes.
    public let opened: Double

    public init(before: Double = 0, session: Double = 0, opened: Double = 0) {
        let before = Self.unit(before)
        self.before = before
        self.session = min(1 - before, Self.unit(session))
        self.opened = Self.unit(opened)
    }

    /// The fill for the next hours rung, `progress`, which already includes this session's counted time (display
    /// credit). `sessionHours` is this session's counted time in the rung's units (hours for the hours leaves):
    /// that much of the rung's progress is this session's share, and the rest was saved before it.
    public init(rung progress: LeafProgress, sessionHours: Double, opened: Double = 0) {
        let span = progress.threshold - progress.floor
        let total = progress.rungFraction
        let share = span > 0 && sessionHours.isFinite ? min(total, max(0, sessionHours) / span) : 0
        self.init(before: total - share, session: share, opened: opened)
    }

    /// The leaf's two tones, with the edge until the leaf has opened.
    public var leafFill: LeafFill {
        .twoTone(before: before, session: session, edge: opened < 1)
    }

    static func unit(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 0
    }
}

/// The bloom behind the dial: how strongly each of its three colours shows, 0…1. The season tint is the usual one,
/// gold arrives as the leaf opens, and the cool bloom belongs to the break and the emergency release.
nonisolated public struct DialBloom: Sendable, Equatable {
    public var tint: Double
    public var gold: Double
    public var cool: Double

    public init(tint: Double = 0, gold: Double = 0, cool: Double = 0) {
        self.tint = tint
        self.gold = gold
        self.cool = cool
    }

    /// No bloom (Needs Screen Time).
    public static let hidden = DialBloom()
}

/// Everything the minute-marks dial draws at one moment, as plain values (F1 design §4.8): the mark states, the
/// current mark's brightness, the leaf dot, the centre leaf's fill, the marks the finish sweeps gold, the bloom and
/// the dimming. `MinuteDial` draws it; nothing here needs a view, so every screen's dial is tested as values.
///
/// ```swift
/// TimelineView(.periodic(from: .now, by: 1)) { _ in
///     let frame = DialFrame.running(layout: layout, elapsed: store.now.timeIntervalSince(start), leafMinute: 35, fill: fill)
///     MinuteDial(frame: frame.dimmed(isDimmed), diameter: 295, theme: theme) { … }
/// }
/// ```
nonisolated public struct DialFrame: Sendable, Equatable {
    /// One state per mark, clockwise from 12 o'clock.
    public var marks: [MarkState]
    /// 0.55…1: how far the current mark has brightened through its minute.
    public var currentBrightness: Double
    /// The leaf dot; nil hides it (no leaf in reach, or the receipt).
    public var dot: DialDot?
    /// The centre leaf's fill, for the centre view (`DialLeaf(species:fill:)`).
    public var fill: DialFill
    /// Per mark, whether the finish sweeps it gold: the counted marks, when the receipt is gold. Empty elsewhere.
    public var gold: [Bool]
    public var bloom: DialBloom
    /// 1, or 0.5 once the running screen dims (§4.6): only the marks and the bloom dim.
    public var markOpacity: Double

    public init(
        marks: [MarkState], currentBrightness: Double = 1, dot: DialDot? = nil, fill: DialFill = DialFill(),
        gold: [Bool] = [], bloom: DialBloom = .hidden, markOpacity: Double = 1
    ) {
        self.marks = marks
        self.currentBrightness = currentBrightness.isFinite ? min(1, max(0.55, currentBrightness)) : 1
        self.dot = dot
        self.fill = fill
        self.gold = gold
        self.bloom = bloom
        self.markOpacity = markOpacity.isFinite ? min(1, max(0, markOpacity)) : 1
    }

    // MARK: Builders

    /// The start screen (§5.1): every mark in `plan`, the leaf dot at `leafMinute` when it falls inside the length,
    /// the leaf as it is now, and a soft tint bloom.
    public static func preview(layout: DialLayout, leafMinute: Int? = nil, fill: DialFill = DialFill()) -> DialFrame {
        DialFrame(
            marks: Array(repeating: .plan, count: layout.markCount),
            dot: dot(layout, leafMinute, reached: false), fill: fill, bloom: DialBloom(tint: 0.4)
        )
    }

    /// A running session `elapsed` seconds after its countdown started (§5.4): the passed marks lit, the current one
    /// brightening through its span, the rest still to come. At the planned end every mark is lit. The dot turns
    /// amber and the bloom gold as the leaf opens (`fill.opened`).
    public static func running(layout: DialLayout, elapsed: TimeInterval, leafMinute: Int?, fill: DialFill) -> DialFrame {
        let count = layout.markCount
        let seconds = elapsed.isNaN ? 0 : max(0, elapsed)
        let opened = fill.opened
        let bloom = DialBloom(tint: 0.55 - 0.30 * opened, gold: 0.6 * opened)
        let dot = dot(layout, leafMinute, reached: opened > 0)
        guard seconds < Double(layout.plannedMinutes * 60) else {
            return DialFrame(marks: Array(repeating: .lit, count: count), currentBrightness: 1, dot: dot, fill: fill, bloom: bloom)
        }
        let current = layout.mark(atElapsed: seconds)
        let secondsPerMark = Double(60 * layout.minutesPerMark)
        let through = (seconds - Double(current) * secondsPerMark) / secondsPerMark
        let marks: [MarkState] = (0..<count).map { $0 < current ? .lit : $0 == current ? .current : .ahead }
        return DialFrame(
            marks: marks, currentBrightness: 0.55 + 0.45 * min(1, max(0, through)), dot: dot, fill: fill, bloom: bloom
        )
    }

    /// The receipt (§5.8): `marks` as the session counted (`ReceiptModel.marks`), with no dot. When the receipt is
    /// gold, `gold` marks the counted (lit) marks for the finish's sweep; otherwise none, and the finish is white.
    public static func receipt(marks: [MarkState], isGold: Bool, fill: DialFill) -> DialFrame {
        DialFrame(
            marks: marks, currentBrightness: 1, dot: nil, fill: fill,
            gold: marks.map { isGold && $0 == .lit },
            bloom: fill.opened > 0 ? DialBloom(tint: 0.25, gold: 1) : DialBloom(tint: 0.55)
        )
    }

    /// A hold's progress (0…1) filling the marks clockwise (§4.7). With no `base` it is the emergency release's
    /// dial (§5.7): `layout`'s marks still to come, under the cool bloom. With a `base` (Locked's start screen) the
    /// hold fills over it, keeping its dot and bloom.
    public static func hold(
        progress: Double, layout: DialLayout = DialLayout(plannedMinutes: 60), base: DialFrame? = nil
    ) -> DialFrame {
        var frame = base ?? DialFrame(marks: Array(repeating: .ahead, count: layout.markCount), bloom: DialBloom(cool: 1))
        let fraction = progress.isFinite ? min(1, max(0, progress)) : 0
        let held = Int((fraction * Double(frame.marks.count) + 1e-9).rounded(.down))
        for index in 0..<held {
            frame.marks[index] = .hold
        }
        return frame
    }

    /// Needs Screen Time (§5.3): every mark off, no dot, no bloom.
    public static func off(layout: DialLayout) -> DialFrame {
        DialFrame(marks: Array(repeating: .off, count: layout.markCount))
    }

    /// The break (§5.5): one rest mark per 10 seconds of the break, going out one by one, under the cool bloom.
    public static func breakTime(_ layout: BreakDialLayout, left: TimeInterval) -> DialFrame {
        DialFrame(marks: layout.marks(left: left), bloom: DialBloom(cool: 1))
    }

    /// The frame with its marks and bloom at 50% (§4.6 dimming), or back at 100%.
    public func dimmed(_ isDimmed: Bool) -> DialFrame {
        var frame = self
        frame.markOpacity = isDimmed ? 0.5 : 1
        return frame
    }

    // MARK: Helpers

    /// The mark the current mark has just left, which fades in as it lights (§4.6); nil when there is none.
    var newestLit: Int? {
        guard let current = marks.firstIndex(of: .current), current > 0, marks[current - 1] == .lit else { return nil }
        return current - 1
    }

    private static func dot(_ layout: DialLayout, _ minute: Int?, reached: Bool) -> DialDot? {
        guard let minute, minute > 0, minute <= layout.plannedMinutes else { return nil }
        return DialDot(angle: layout.angle(atMinute: Double(minute)), reached: reached)
    }
}
