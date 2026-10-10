import Foundation

/// What is left to earn a leaf, in Home's words (spec §3.6): "3 nights", "4 mornings", "1h 40m", and "Tonight" or
/// "Today" when one more completes it in the current phase. Estimates ("about 5 nights") belong to leaf detail only.
public struct LeafRemainder: Sendable, Equatable {
    /// The right-aligned remainder on the next-leaf row and Almost-there cards.
    public let text: String
    /// "11 of 14", or "6h of 8h" for focus hours.
    public let amount: String
    /// Whether to draw the progress hairline: not before any progress (a first rung reads "Tonight", no bar).
    public let showsBar: Bool

    public init(_ progress: LeafProgress, phase: NowPhase) {
        let unit = Self.unit(for: progress.category)
        let remaining = progress.remaining
        if unit == .hours {
            text = HomeFormat.duration(minutes: Int((remaining * 60).rounded()))
            amount = "\(Int(progress.current))h of \(Int(progress.threshold))h"
        } else {
            let count = Int((remaining - 1e-9).rounded(.up))
            if count == 1, unit.perNight, phase == .evening || phase == .windDown {
                text = "Tonight"
            } else if count == 1, unit == .days, phase == .day {
                text = "Today"
            } else {
                text = "\(count) \(count == 1 ? unit.singular : unit.plural)"
            }
            amount = "\(Int(progress.current)) of \(Int(progress.threshold))"
        }
        showsBar = progress.current > 0
    }

    enum Unit: Equatable {
        case nights, evenings, mornings, days, weeks, seasons, hours, challenges, steps

        var singular: String {
            switch self {
            case .nights: "night"
            case .evenings: "evening"
            case .mornings: "morning"
            case .days: "day"
            case .weeks: "week"
            case .seasons: "season"
            case .hours: "hour"
            case .challenges: "challenge"
            case .steps: "step"
            }
        }

        var plural: String { singular + "s" }

        /// Units that one more night (or evening) can complete.
        var perNight: Bool { self == .nights || self == .evenings }
    }

    static func unit(for category: RewardCategoryID) -> Unit {
        switch category {
        case .firstSteps: .steps
        case .nightsTracked, .onTimeBedtimes, .bedtimeRun, .fullNights, .soundWindDowns, .bedtimeShieldKept: .nights
        case .scrollFreeWindDowns, .windDownRituals: .evenings
        case .steadyMornings, .phoneFreeMornings: .mornings
        case .focusDays, .caffeineCurfew: .days
        case .steadyWeeks, .focusWeeks, .reflectionWeeks: .weeks
        case .seasonsInRhythm: .seasons
        case .focusHours: .hours
        case .communityChallenges: .challenges
        }
    }
}
