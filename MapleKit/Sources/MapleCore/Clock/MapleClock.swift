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
    }

    private let source: Source

    /// The real time.
    public static let live = MapleClock(source: .live)

    /// A clock stopped at `date`.
    public static func fixed(_ date: Date) -> MapleClock {
        MapleClock(source: .fixed(date))
    }

    /// The current instant.
    public func now() -> Date {
        switch source {
        case .live: Date()
        case .fixed(let date): date
        }
    }

    /// The instant a `TimelineView` entry stands for: the entry's own date on a live clock, the frozen date on a
    /// fixed one.
    public func date(forTimeline timelineDate: Date) -> Date {
        switch source {
        case .live: timelineDate
        case .fixed(let date): date
        }
    }

    /// True when time is frozen (DEBUG demos, previews, tests).
    public var isFixed: Bool {
        if case .fixed = source { true } else { false }
    }
}
