import Foundation

/// Where "now" comes from. Screens and stores ask the clock instead of calling `Date()`, so DEBUG launches and
/// previews can freeze time inside any phase of the day (`-MapleDemoPhase`) and tests stay deterministic.
///
/// ```swift
/// @Environment(\.mapleClock) private var clock
/// TimelineView(.everyMinute) { context in
///     let now = clock.date(forTimeline: context.date)
///     ...
/// }
/// ```
public struct MapleClock: Sendable, Hashable {
    private enum Source: Sendable, Hashable {
        case live
        case fixed(Date)
        case shifted(TimeInterval)
    }

    private let source: Source

    /// The real time.
    public static let live = MapleClock(source: .live)

    /// A clock stopped at `date`.
    public static func fixed(_ date: Date) -> MapleClock {
        MapleClock(source: .fixed(date))
    }

    /// The real time moved by `offset`, still ticking: a demo launch puts "now" inside the phase it asks for and lets
    /// a session run (F1 design §7.6). The demo focus time source uses the same offset, so Home and the dial agree.
    public static func shifted(by offset: TimeInterval) -> MapleClock {
        MapleClock(source: .shifted(offset))
    }

    /// How far a shifted clock is moved; 0 for the live and fixed clocks.
    public var offset: TimeInterval {
        if case .shifted(let offset) = source { offset } else { 0 }
    }

    /// The current instant.
    public func now() -> Date {
        switch source {
        case .live: Date()
        case .fixed(let date): date
        case .shifted(let offset): Date().addingTimeInterval(offset)
        }
    }

    /// The instant a `TimelineView` entry stands for: the entry's own date on a live clock, the frozen date on a
    /// fixed one.
    public func date(forTimeline timelineDate: Date) -> Date {
        switch source {
        case .live: timelineDate
        case .fixed(let date): date
        case .shifted(let offset): timelineDate.addingTimeInterval(offset)
        }
    }

    /// True when time is frozen (DEBUG demos, previews, tests).
    public var isFixed: Bool {
        if case .fixed = source { true } else { false }
    }
}
