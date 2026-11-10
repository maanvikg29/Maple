import Foundation

/// Turns Apple Health sleep samples into one `SleepNightObservation` per night, by rewards.json's `nights_tracked`
/// rules, for `CollectionStore.recordSleep(_:at:)`. Pure and deterministic: the importer rebuilds every night it
/// still holds samples for on each run (so a deleted sample simply drops out), and the ledger judges the result.
///
/// - Samples typed in by hand never count; the rest are placed on the source ladder by `SleepSourceResolver`.
/// - A night runs 18:00 to 18:00 local and belongs to its evening; a sample across 18:00 is cut there. "Local" is the
///   sample's own time zone when it has one, else the builder's calendar.
/// - Sources are never mixed inside a night: each source's samples are read on their own.
/// - A source's main episode is its longest cluster of samples, gaps under 60 minutes merged; naps are ignored.
/// - Sleep onset is the start of the main episode's first asleep block of 20 minutes or more (A and B; the first
///   block when none is that long) or the in-bed start (C); final wake is the end of its last asleep block (A, B) or
///   the in-bed end (C). Minutes asleep count asleep stages only, with awake time taken out; nil for C.
/// - Of a night's sources, a main episode (3 hours or more) wins over a shorter one, then the better rung of the
///   ladder, then more time asleep (or longer in bed).
public struct SleepNightBuilder: Sendable {
    /// Samples closer than this join one cluster (rewards.json: "gaps under 60 min merged").
    public static let clusterGap: TimeInterval = 60 * 60
    /// Sleep onset is the start of the first asleep block at least this long.
    public static let onsetBlock: TimeInterval = 20 * 60
    /// Asleep stages written back to back, a few seconds apart, are one block.
    static let blockJoin: TimeInterval = 60

    /// The zone for samples that don't carry their own.
    public var calendar: Calendar
    public var resolver: SleepSourceResolver

    public init(calendar: Calendar, resolver: SleepSourceResolver = SleepSourceResolver()) {
        self.calendar = calendar
        self.resolver = resolver
    }

    // MARK: Nights

    /// 18:00 local on the evening of `night`, when it begins.
    public static func eveningStart(of night: LocalDay, calendar: Calendar) -> Date {
        let parts = DateComponents(year: night.year, month: night.month, day: night.day, hour: 18)
        return calendar.date(from: parts) ?? night.startDate(in: calendar).addingTimeInterval(18 * 3600)
    }

    /// The night `date` belongs to: the evening at or before it, cut at 18:00 local (on a daylight-saving day too).
    public static func night(containing date: Date, calendar: Calendar) -> LocalDay {
        let day = LocalDay(date, calendar: calendar)
        return date >= eveningStart(of: day, calendar: calendar) ? day : day.adding(days: -1, calendar: calendar)
    }

    /// One observation per night that has samples that count, oldest first.
    public func nights(from samples: [SleepSample]) -> [SleepNightObservation] {
        var groups: [GroupKey: [Piece]] = [:]
        for sample in samples where sample.end > sample.start {
            guard let source = resolver.source(of: sample) else { continue }
            let local = calendar(for: sample.timeZoneIdentifier)
            for piece in Self.pieces(of: sample, calendar: local) {
                groups[GroupKey(night: piece.night, source: source, origin: sample.origin.key), default: []].append(piece)
            }
        }
        var best: [LocalDay: Candidate] = [:]
        for (key, pieces) in groups {
            guard let candidate = episode(of: pieces, key: key) else { continue }
            if let current = best[key.night], !candidate.isBetter(than: current) { continue }
            best[key.night] = candidate
        }
        return best.values.map(\.observation).sorted { $0.night < $1.night }
    }

    // MARK: Private

    private struct GroupKey: Hashable {
        var night: LocalDay
        var source: SleepSource
        var origin: String
    }

    /// The part of a sample inside one night.
    private struct Piece {
        var night: LocalDay
        var start: Date
        var end: Date
        var stage: SleepSample.Stage
        var zone: String
    }

    private struct Candidate {
        var observation: SleepNightObservation
        var origin: String

        /// Main episode first, then the ladder, then more sleep, then a fixed order so the result never depends on
        /// the order samples arrived in.
        func isBetter(than other: Candidate) -> Bool {
            if observation.isMainEpisode != other.observation.isMainEpisode { return observation.isMainEpisode }
            if observation.source.rank != other.observation.source.rank {
                return observation.source.rank > other.observation.source.rank
            }
            if amount != other.amount { return amount > other.amount }
            return origin < other.origin
        }

        private var amount: Double { observation.asleepMinutes ?? observation.span / 60 }
    }

    private func calendar(for identifier: String?) -> Calendar {
        guard let identifier, let zone = TimeZone(identifier: identifier), zone.identifier != calendar.timeZone.identifier else {
            return calendar
        }
        var local = calendar
        local.timeZone = zone
        return local
    }

    /// A sample cut at each 18:00 it crosses.
    private static func pieces(of sample: SleepSample, calendar: Calendar) -> [Piece] {
        var pieces: [Piece] = []
        var start = sample.start
        var night = night(containing: start, calendar: calendar)
        while start < sample.end {
            let next = night.adding(days: 1, calendar: calendar)
            let boundary = eveningStart(of: next, calendar: calendar)
            let end = min(sample.end, boundary)
            if end > start {
                pieces.append(Piece(night: night, start: start, end: end, stage: sample.stage,
                                    zone: calendar.timeZone.identifier))
            }
            start = max(end, start)
            if end < boundary { break }
            night = next
        }
        return pieces
    }

    /// One source's main episode in one night, as an observation.
    private func episode(of pieces: [Piece], key: GroupKey) -> Candidate? {
        let sorted = pieces.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
        var clusters: [[Piece]] = []
        var clusterEnd = Date.distantPast
        for piece in sorted {
            if let last = clusters.indices.last, piece.start.timeIntervalSince(clusterEnd) < Self.clusterGap {
                clusters[last].append(piece)
                clusterEnd = max(clusterEnd, piece.end)
            } else {
                clusters.append([piece])
                clusterEnd = piece.end
            }
        }

        let episodes = clusters.compactMap { cluster in observation(of: cluster, key: key) }
        guard let main = episodes.max(by: { lhs, rhs in
            let left = (lhs.span, lhs.asleepMinutes ?? 0, lhs.onset), right = (rhs.span, rhs.asleepMinutes ?? 0, rhs.onset)
            return left < right
        }) else { return nil }
        return Candidate(observation: main, origin: key.origin)
    }

    /// A cluster as an observation: nil when it holds no time that counts (awake time only).
    private func observation(of cluster: [Piece], key: GroupKey) -> SleepNightObservation? {
        guard let zone = cluster.first?.zone else { return nil }
        switch key.source {
        case .iPhoneInBed:
            guard let start = cluster.map(\.start).min(), let end = cluster.map(\.end).max() else { return nil }
            return SleepNightObservation(night: key.night, onset: start, finalWake: end, asleepMinutes: nil,
                                         source: key.source, timeZoneIdentifier: zone)
        case .watchOrTracker, .otherApp:
            let asleep = Intervals(cluster.filter { $0.stage.isAsleep }.map { ($0.start, $0.end) }, join: Self.blockJoin)
            let awake = Intervals(cluster.filter { $0.stage == .awake }.map { ($0.start, $0.end) }, join: 0)
            let blocks = asleep.subtracting(awake).joined(within: Self.blockJoin)
            guard let first = blocks.first, let last = blocks.last else { return nil }
            let onset = blocks.first { $0.end.timeIntervalSince($0.start) >= Self.onsetBlock }?.start ?? first.start
            let minutes = blocks.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) } / 60
            return SleepNightObservation(night: key.night, onset: onset, finalWake: last.end, asleepMinutes: minutes,
                                         source: key.source, timeZoneIdentifier: zone)
        }
    }
}

/// Sorted, non-overlapping time intervals.
private struct Intervals {
    var spans: [(start: Date, end: Date)]

    /// The union of `intervals`; ones `join` seconds apart or closer become one.
    init(_ intervals: [(Date, Date)], join: TimeInterval) {
        spans = []
        for (start, end) in intervals.sorted(by: { $0.0 < $1.0 }) where end > start {
            if let last = spans.last, start.timeIntervalSince(last.end) <= join {
                spans[spans.count - 1].end = max(last.end, end)
            } else {
                spans.append((start, end))
            }
        }
    }

    private init(spans: [(start: Date, end: Date)]) {
        self.spans = spans
    }

    /// These intervals with `other`'s time taken out.
    func subtracting(_ other: Intervals) -> Intervals {
        var result: [(start: Date, end: Date)] = []
        for span in spans {
            var pieces = [span]
            for cut in other.spans where cut.end > span.start && cut.start < span.end {
                pieces = pieces.flatMap { piece -> [(start: Date, end: Date)] in
                    guard cut.end > piece.start, cut.start < piece.end else { return [piece] }
                    var kept: [(start: Date, end: Date)] = []
                    if cut.start > piece.start { kept.append((piece.start, cut.start)) }
                    if cut.end < piece.end { kept.append((cut.end, piece.end)) }
                    return kept
                }
            }
            result.append(contentsOf: pieces)
        }
        return Intervals(spans: result)
    }

    /// The intervals as blocks, joining ones `join` seconds apart or closer.
    func joined(within join: TimeInterval) -> [(start: Date, end: Date)] {
        Intervals(spans.map { ($0.start, $0.end) }, join: join).spans
    }
}
