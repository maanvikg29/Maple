import Foundation
import MapleFocusCore

/// Why a stretch of a session didn't count (F1 design §3.3 step 10). The ids are stable: Saved today and the receipt
/// turn them into words.
public enum CreditRule: String, Codable, Sendable, CaseIterable {
    case afterBedtime, beforeMorning, dailyCap, override, unconfirmed, plainTimer, notQualifying, overlap
}

/// A stretch of a session's time and whether it counted.
public struct CreditStretch: Sendable, Hashable {
    public var interval: DateInterval
    /// Nil when it counted; otherwise why not.
    public var rule: CreditRule?

    public init(_ interval: DateInterval, _ rule: CreditRule?) {
        self.interval = interval
        self.rule = rule
    }

    public var counted: Bool { rule == nil }
}

/// One session's credit (F1 design §3.3–3.4).
public struct SessionCredit: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var day: LocalDay
    public var zone: String
    /// Counted seconds, after the daily cap.
    public var seconds: Int
    /// Locked awake seconds before the cap, which decide whether it finished.
    public var awakeSeconds: Int
    public var finished: Bool
    /// When its credit was last proven (its last checkpoint): the moment its leaves are dated.
    public var provenAt: Date
    public var endedAt: Date?
    /// Its awake window's end, from which its day freezes.
    public var dayEnd: Date
    /// Counted and uncounted stretches, in time order.
    public var stretches: [CreditStretch]
}

/// Credit from replayed sessions (F1 design §3.3–3.4, focus spec R1–R13). Pure; works in seconds and rounds once per
/// session.
public enum HoursCredit {
    public static let dailyCap = 6 * 3600
    public static let finishedMinimum = 20 * 60
    public static let finishedShare = 0.75
    public static let finishedPerDay = 3

    /// Credit for every session from a credited source, in start order.
    /// - Parameter now: A running session's time after its last checkpoint shows as `unconfirmed` up to `now`.
    public static func credit(_ sessions: [SessionRecord], crediting sources: Set<FocusSource>, now: Date) -> [SessionCredit] {
        var countedByDay: [String: [DateInterval]] = [:]
        var usedByDay: [String: TimeInterval] = [:]
        var results: [SessionCredit] = []
        var candidates: [(index: Int, endedAt: Date, key: String)] = []

        for session in sessions where sources.contains(session.source) {
            let plan = session.plan
            let key = "\(plan.day)|\(plan.zone)"
            let visibleEnd = max(session.countdownStart, min(session.end?.placed ?? now, session.plannedEnd))
            var stretches: [CreditStretch] = []
            func result(seconds: Int, awake: Int) -> SessionCredit {
                SessionCredit(id: session.id, day: plan.day, zone: plan.zone, seconds: seconds, awakeSeconds: awake, finished: false,
                              provenAt: session.lastCheckpoint ?? session.countdownStart, endedAt: session.end?.placed,
                              dayEnd: plan.window.end, stretches: stretches.sorted { $0.interval.start < $1.interval.start })
            }

            guard plan.canCount else {
                let whole = DateInterval(start: session.countdownStart, end: visibleEnd)
                if whole.duration > 0 { stretches.append(CreditStretch(whole, plan.kind == .plainTimer ? .plainTimer : .notQualifying)) }
                results.append(result(seconds: 0, awake: 0))
                continue
            }

            // Every part of the visible span that no proof covers is unconfirmed: the time after the last checkpoint
            // (provisional while running) and the gaps between boots, such as a restart mid-session.
            var unproven = visibleEnd > session.countdownStart ? [DateInterval(start: session.countdownStart, end: visibleEnd)] : []
            for proof in session.provenIntervals { unproven = subtract(unproven, proof).kept }
            stretches += unproven.map { CreditStretch($0, .unconfirmed) }

            var pieces = session.provenIntervals
            for window in session.overrides {
                let (kept, removed) = subtract(pieces, window)
                pieces = kept
                stretches += removed.map { CreditStretch($0, .override) }
            }

            var awake: [DateInterval] = []
            for piece in pieces {
                if piece.start < plan.window.start {
                    stretches.append(CreditStretch(DateInterval(start: piece.start, end: min(piece.end, plan.window.start)), .beforeMorning))
                }
                if piece.end > plan.window.end {
                    stretches.append(CreditStretch(DateInterval(start: max(piece.start, plan.window.end), end: piece.end), .afterBedtime))
                }
                let start = max(piece.start, plan.window.start), end = min(piece.end, plan.window.end)
                if end > start { awake.append(DateInterval(start: start, end: end)) }
            }

            var fresh: [DateInterval] = []
            for piece in awake {
                var remaining = [piece]
                for counted in countedByDay[key, default: []] {
                    let (kept, removed) = subtract(remaining, counted)
                    remaining = kept
                    stretches += removed.map { CreditStretch($0, .overlap) }
                }
                fresh += remaining
            }
            countedByDay[key, default: []] += fresh

            var counted: TimeInterval = 0
            var used = usedByDay[key, default: 0]
            for piece in fresh {
                let take = min(max(0, TimeInterval(dailyCap) - used), piece.duration)
                if take > 0 { stretches.append(CreditStretch(DateInterval(start: piece.start, duration: take), nil)) }
                if take < piece.duration {
                    stretches.append(CreditStretch(DateInterval(start: piece.start.addingTimeInterval(take), end: piece.end), .dailyCap))
                }
                counted += take
                used += take
            }
            usedByDay[key] = used

            let awakeSeconds = Int(fresh.reduce(0) { $0 + $1.duration }.rounded())
            results.append(result(seconds: Int(counted.rounded()), awake: awakeSeconds))
            if session.endReason == .completed, let endedAt = session.end?.placed, awakeSeconds >= finishedMinimum,
               Double(awakeSeconds) >= finishedShare * Double(plan.plannedSeconds) {
                candidates.append((results.count - 1, endedAt, key))
            }
        }

        var finishedByDay: [String: Int] = [:]
        for candidate in candidates.sorted(by: { $0.endedAt < $1.endedAt }) where finishedByDay[candidate.key, default: 0] < finishedPerDay {
            results[candidate.index].finished = true
            finishedByDay[candidate.key, default: 0] += 1
        }
        return results
    }

    /// The provisional seconds a running session would add after its last checkpoint: shown on the dial and Home, never
    /// given to the counters (§3.3 step 9). Inside its awake window, outside overrides, within the room left today.
    public static func provisionalSeconds(for session: SessionRecord, now: Date, roomLeftToday: Int) -> Int {
        guard session.plan.canCount, session.end == nil, session.lostAt == nil, session.applied != nil else { return 0 }
        let from = max(session.provenIntervals.last?.end ?? session.countdownStart, session.plan.window.start)
        let to = min(now, session.plannedEnd, session.plan.window.end)
        guard to > from else { return 0 }
        var pieces = [DateInterval(start: from, end: to)]
        for window in session.overrides { pieces = subtract(pieces, window).kept }
        let seconds = Int(pieces.reduce(0) { $0 + $1.duration }.rounded(.down))
        return min(max(0, roomLeftToday), seconds)
    }

    /// `pieces` without `window`, and the parts it removed.
    static func subtract(_ pieces: [DateInterval], _ window: DateInterval) -> (kept: [DateInterval], removed: [DateInterval]) {
        var kept: [DateInterval] = []
        var removed: [DateInterval] = []
        for piece in pieces {
            let start = max(piece.start, window.start), end = min(piece.end, window.end)
            guard end > start else {
                kept.append(piece)
                continue
            }
            removed.append(DateInterval(start: start, end: end))
            if piece.start < start { kept.append(DateInterval(start: piece.start, end: start)) }
            if end < piece.end { kept.append(DateInterval(start: end, end: piece.end)) }
        }
        return (kept, removed)
    }
}
