import Foundation
import MapleFocusCore

/// Decodes to nil rather than throwing, so one damaged element of an array or dictionary doesn't take the rest with it.
/// Shared with `CollectionSnapshot`'s decoder.
struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}

/// One session's credit as the book keeps it: high-water marks (F1 design §3.5).
public struct SessionTally: Codable, Sendable, Equatable {
    public var seconds: Int
    public var finished: Bool
    public var provenAt: Date

    public init(seconds: Int, finished: Bool, provenAt: Date) {
        self.seconds = seconds
        self.finished = finished
        self.provenAt = provenAt
    }

    private enum CodingKeys: String, CodingKey {
        case seconds, finished, provenAt
    }

    /// Tolerant: `seconds` is required; a missing or unreadable `finished` is false and `provenAt` is `.distantPast`
    /// (which `record` treats as older than any proof).
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seconds = try c.decode(Int.self, forKey: .seconds)
        finished = (try? c.decodeIfPresent(Bool.self, forKey: .finished)) ?? false
        provenAt = (try? c.decodeIfPresent(Date.self, forKey: .provenAt)) ?? .distantPast
    }
}

/// One Maple day's credit (R11). Facts only: its streak status is worked out, never stored.
public struct DayCredit: Codable, Sendable, Equatable, Identifiable {
    public var day: LocalDay
    public var zone: String
    /// Each session's high-water credit, keyed by the lowercased session id. Emptied once the day is frozen.
    public var sessions: [String: SessionTally]
    /// Never falls; at most 6 hours.
    public var seconds: Int
    /// Never falls; at most 3.
    public var finished: Int
    public var firstCountedAt: Date
    /// The day's awake window's end (its bedtime).
    public var dayEnd: Date
    public var rulesVersion: Int
    public var frozen: Bool

    public init(
        day: LocalDay, zone: String, sessions: [String: SessionTally] = [:], seconds: Int = 0, finished: Int = 0,
        firstCountedAt: Date, dayEnd: Date, rulesVersion: Int = FocusRules.version, frozen: Bool = false
    ) {
        self.day = day
        self.zone = zone
        self.sessions = sessions
        self.seconds = seconds
        self.finished = finished
        self.firstCountedAt = firstCountedAt
        self.dayEnd = dayEnd
        self.rulesVersion = rulesVersion
        self.frozen = frozen
    }

    public var id: String { "\(day)|\(zone)" }
    /// 3 days after the later of the day's end and its first credit.
    public var freezesAt: Date { max(dayEnd, firstCountedAt).addingTimeInterval(FocusBook.recountDays * 86400) }
    public var isFocusDay: Bool { finished > 0 }

    private enum CodingKeys: String, CodingKey {
        case day, zone, sessions, seconds, finished, firstCountedAt, dayEnd, rulesVersion, frozen
    }

    /// Tolerant, field by field: the day, its zone and its totals are required (a day without them is skipped by
    /// `FocusBook`'s decoder); anything else that is missing or unreadable takes a default so earned credit survives.
    /// Missing `dayEnd` and `firstCountedAt` stand in for each other, and with neither the day counts as long past, so it
    /// freezes at the next opportunity. Damaged session tallies are dropped one by one.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decode(LocalDay.self, forKey: .day)
        zone = try c.decode(String.self, forKey: .zone)
        seconds = try c.decode(Int.self, forKey: .seconds)
        finished = try c.decode(Int.self, forKey: .finished)
        let first = (try? c.decodeIfPresent(Date.self, forKey: .firstCountedAt)) ?? nil
        let end = (try? c.decodeIfPresent(Date.self, forKey: .dayEnd)) ?? nil
        firstCountedAt = first ?? end ?? .distantPast
        dayEnd = end ?? first ?? .distantPast
        rulesVersion = (try? c.decodeIfPresent(Int.self, forKey: .rulesVersion)) ?? FocusRules.version
        frozen = (try? c.decodeIfPresent(Bool.self, forKey: .frozen)) ?? false
        sessions = ((try? c.decodeIfPresent([String: Lossy<SessionTally>].self, forKey: .sessions)) ?? nil)?.compactMapValues(\.value) ?? [:]
    }
}

public struct FocusTotals: Codable, Sendable, Equatable {
    public var seconds: Int
    public var finished: Int

    public init(seconds: Int, finished: Int) {
        self.seconds = seconds
        self.finished = finished
    }

    private enum CodingKeys: String, CodingKey {
        case seconds, finished
    }

    /// Both totals are required: half a baseline would be wrong rather than merely short, so `FocusBook` zeroes it.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seconds = try c.decode(Int.self, forKey: .seconds)
        finished = try c.decode(Int.self, forKey: .finished)
    }

    public static let zero = FocusTotals(seconds: 0, finished: 0)
}

/// Every Maple day's focus credit, kept in `CollectionSnapshot` beside the counters (F1 design §3.5). Counters are the
/// baseline plus the sum of the days, so a recount, a lost ledger or an older build can never lower them or stall
/// new leaves.
public struct FocusBook: Codable, Sendable, Equatable {
    /// Days a day can still be recounted upward.
    public static let recountDays: TimeInterval = 3

    /// In day order.
    public var days: [DayCredit]
    /// Totals the book can't recount: whatever the counters held when it started, less what the replay recounted.
    public var baseline: FocusTotals
    /// The best Focus streak run ever: a high-water mark.
    public var bestRun: Int
    /// When the book began; nil means it must take its baseline from the counters.
    public var startedAt: Date?

    public init(days: [DayCredit] = [], baseline: FocusTotals = .zero, bestRun: Int = 0, startedAt: Date? = nil) {
        self.days = days
        self.baseline = baseline
        self.bestRun = bestRun
        self.startedAt = startedAt
    }

    public var totalSeconds: Int { baseline.seconds + days.reduce(0) { $0 + $1.seconds } }
    public var totalFinished: Int { baseline.finished + days.reduce(0) { $0 + $1.finished } }

    /// Days with a finished session, with the zone each was spent in, in order.
    public var focusDays: [(day: LocalDay, zone: String)] {
        days.filter(\.isFocusDay).map { ($0.day, $0.zone) }
    }

    /// Seconds counted on `day`, in every zone.
    public func seconds(on day: LocalDay) -> Int {
        days.filter { $0.day == day }.reduce(0) { $0 + $1.seconds }
    }

    /// Records sessions' credit as high-water marks; frozen days don't change.
    /// - Returns: Whether anything changed.
    @discardableResult
    public mutating func record(_ credits: [SessionCredit]) -> Bool {
        let before = self
        for credit in credits where credit.seconds > 0 || credit.finished {
            let key = "\(credit.day)|\(credit.zone)"
            let index: Int
            if let found = days.firstIndex(where: { $0.id == key }) {
                index = found
            } else {
                days.append(DayCredit(day: credit.day, zone: credit.zone, firstCountedAt: credit.provenAt, dayEnd: credit.dayEnd))
                index = days.count - 1
            }
            guard !days[index].frozen else { continue }
            var day = days[index]
            let id = credit.id.uuidString.lowercased()
            let old = day.sessions[id]
            day.sessions[id] = SessionTally(
                seconds: max(old?.seconds ?? 0, credit.seconds), finished: (old?.finished ?? false) || credit.finished,
                provenAt: max(old?.provenAt ?? .distantPast, credit.provenAt)
            )
            day.seconds = max(day.seconds, min(HoursCredit.dailyCap, day.sessions.values.reduce(0) { $0 + $1.seconds }))
            day.finished = max(day.finished, min(HoursCredit.finishedPerDay, day.sessions.values.filter(\.finished).count))
            day.firstCountedAt = min(day.firstCountedAt, credit.provenAt)
            days[index] = day
        }
        days.sort { ($0.day, $0.zone) < ($1.day, $1.zone) }
        return self != before
    }

    /// Freezes days 3 days after the later of their end and their first credit, keeping only their totals.
    /// - Returns: Whether any day froze.
    @discardableResult
    public mutating func freeze(at now: Date) -> Bool {
        var changed = false
        for index in days.indices where !days[index].frozen && now >= days[index].freezesAt {
            days[index].frozen = true
            days[index].sessions = [:]
            changed = true
        }
        return changed
    }

    // MARK: Codable (tolerant: a damaged day is skipped, missing fields take their defaults)

    private enum CodingKeys: String, CodingKey {
        case days, baseline, bestRun, startedAt
    }

    /// An unreadable baseline is zeroed and `startedAt` cleared with it, so the book takes a fresh baseline from the
    /// counters instead of believing it already did. A missing baseline key leaves `startedAt` as it was.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        days = ((try? c.decodeIfPresent([Lossy<DayCredit>].self, forKey: .days)) ?? []).compactMap(\.value)
        var baselineDamaged = false
        do {
            baseline = try c.decodeIfPresent(FocusTotals.self, forKey: .baseline) ?? .zero
        } catch {
            baseline = .zero
            baselineDamaged = true
        }
        bestRun = (try? c.decodeIfPresent(Int.self, forKey: .bestRun)) ?? 0
        startedAt = baselineDamaged ? nil : (try? c.decodeIfPresent(Date.self, forKey: .startedAt)) ?? nil
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(days, forKey: .days)
        try c.encode(baseline, forKey: .baseline)
        try c.encode(bestRun, forKey: .bestRun)
        try c.encodeIfPresent(startedAt, forKey: .startedAt)
    }
}
