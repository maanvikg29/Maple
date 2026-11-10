import Foundation

/// The Focus streak (F1 design §3.4). A run starts and ends on a focus day (a Maple day with a finished session), and
/// every day between is a rest day, with at most 2 rest days in any 7 days in a row. Rest days only bridge: misses
/// after the last focus day neither count nor break the run while the allowance still covers them. A one-day gap
/// between days spent in different zones is neutral. Pure, with day arithmetic on `LocalDay.ordinal`.
public struct FocusRuns: Sendable, Equatable {
    public static let restDays = 2
    public static let restWindow = 7

    /// The run ending at the latest focus day, or 0 once the misses since can't be rest days.
    public let current: Int
    /// The longest run.
    public let best: Int

    /// - Parameters:
    ///   - focusDays: Maple days with a finished session, with the zone each was spent in.
    ///   - today: The Maple day now. It stays pending until it ends.
    public init(focusDays: [(day: LocalDay, zone: String)], today: LocalDay) {
        let todayOrdinal = today.ordinal
        // One entry per day, holding every zone it was spent in, so the order the zones were logged in never matters.
        var zonesByDay: [Int: Set<String>] = [:]
        for entry in focusDays where entry.day.ordinal <= todayOrdinal {
            zonesByDay[entry.day.ordinal, default: []].insert(entry.zone)
        }
        let days = zonesByDay.keys.sorted().map { (ordinal: $0, zones: zonesByDay[$0] ?? []) }

        var best = 0
        var length = 0
        var rests: [Int] = []
        var last: (ordinal: Int, zones: Set<String>)?
        for entry in days {
            if let previous = last {
                let misses = entry.ordinal - previous.ordinal - 1
                let gap = misses > 0 ? Array((previous.ordinal + 1)..<entry.ordinal) : []
                if misses == 0 {
                    length += 1
                } else if misses == 1, previous.zones.isDisjoint(with: entry.zones) {
                    length += 1
                } else if misses <= Self.restDays, Self.fits(rests + gap) {
                    length += misses + 1
                    rests += gap
                } else {
                    length = 1
                    rests = []
                }
            } else {
                length = 1
            }
            best = max(best, length)
            last = entry
        }

        if let previous = last {
            let trailing = todayOrdinal - previous.ordinal - 1
            if trailing <= 0 {
                current = length
            } else {
                let gap = Array((previous.ordinal + 1)..<todayOrdinal)
                current = trailing <= Self.restDays && Self.fits(rests + gap) ? length : 0
            }
        } else {
            current = 0
        }
        self.best = best
    }

    /// Whether `rests` (day ordinals) has at most 2 days in any 7 days in a row.
    public static func fits(_ rests: [Int]) -> Bool {
        let sorted = rests.sorted()
        guard sorted.count > restDays else { return true }
        for index in 0..<(sorted.count - restDays) where sorted[index + restDays] - sorted[index] < restWindow {
            return false
        }
        return true
    }
}
