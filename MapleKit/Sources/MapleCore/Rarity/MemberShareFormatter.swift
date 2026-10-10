import Foundation

/// A share of members with its 95% interval, all in percent (0…100).
public struct ShareEstimate: Sendable, Hashable, Codable {
    public var percent: Double
    public var lower: Double
    public var upper: Double

    public init(percent: Double, lower: Double, upper: Double) {
        self.percent = percent
        self.lower = lower
        self.upper = upper
    }

    /// The Wilson score interval for `count` holders among `members` (the CloudKit counters, spec override 1).
    /// Nil when there are no members. A count above `members` is clamped.
    public static func wilson(count: Int, members: Int, z: Double = 1.959_963_985) -> ShareEstimate? {
        guard members > 0 else { return nil }
        let holders = min(max(0, count), members)
        let n = Double(members)
        let p = Double(holders) / n
        let z2 = z * z
        let denominator = 1 + z2 / n
        let centre = (p + z2 / (2 * n)) / denominator
        let margin = z * (p * (1 - p) / n + z2 / (4 * n * n)).squareRoot() / denominator
        // The interval touches 0 and 100 exactly at the ends; keep floating-point dust out of the formatter.
        let lower = holders == 0 ? 0 : max(0, centre - margin)
        let upper = holders == members ? 1 : min(1, centre + margin)
        return ShareEstimate(percent: p * 100, lower: lower * 100, upper: upper * 100)
    }
}

/// Formats a member share honestly (spec §5.7, D6): a whole or one-decimal percent when the interval is tight,
/// a bound such as "Under 1%" when it isn't, and never "0%" or "100%".
public enum MemberShareFormatter {
    /// The clean values a bound is rounded outward to.
    public static let steps: [Double] = [0.1, 0.2, 0.5, 1, 2, 3, 5, 10, 15, 20, 25, 30, 40, 50, 60, 70, 80, 90, 95, 99]

    private static let tolerance = 1e-9

    /// The smallest step at or above `value` (99 above the last step).
    public static func stepUp(_ value: Double) -> Double {
        steps.first { $0 >= value - tolerance } ?? steps[steps.count - 1]
    }

    /// The largest step at or below `value` (0.1 below the first step).
    public static func stepDown(_ value: Double) -> Double {
        steps.last { $0 <= value + tolerance } ?? steps[0]
    }

    public static func format(_ estimate: ShareEstimate, locale: Locale = .current) -> String {
        format(percent: estimate.percent, lower: estimate.lower, upper: estimate.upper, locale: locale)
    }

    /// - Parameters: `percent`, `lower` and `upper` are the estimate and its 95% bounds, in percent.
    public static func format(percent p: Double, lower lo: Double, upper hi: Double, locale: Locale = .current) -> String {
        if hi < 0.1 { return "Under \(number(0.1, decimals: 1, locale))" }
        if lo > 99 { return "Over \(number(99, decimals: 0, locale))" }
        let half = (hi - lo) / 2
        let precise = half <= 0.4 * p
        if precise {
            if p >= 2 {
                return number(min(99, max(1, p.rounded())), decimals: 0, locale)
            }
            if p >= 0.1 {
                return number((p * 10).rounded() / 10, decimals: 1, locale)
            }
            // Below a tenth of a percent, even a tight interval reads as a bound.
            return "Under \(number(0.1, decimals: 1, locale))"
        }
        if p < 50 {
            let bound = stepUp(hi)
            return "Under \(number(bound, decimals: bound < 1 ? 1 : 0, locale))"
        }
        let bound = stepDown(lo)
        return "Over \(number(bound, decimals: bound < 1 ? 1 : 0, locale))"
    }

    /// "22%", "0.4%": the locale's percent style with a fixed number of decimals.
    private static func number(_ percent: Double, decimals: Int, _ locale: Locale) -> String {
        (percent / 100).formatted(.percent.precision(.fractionLength(decimals)).locale(locale))
    }
}
