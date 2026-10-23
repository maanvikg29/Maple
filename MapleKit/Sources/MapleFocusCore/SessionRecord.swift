import Foundation

/// One session replayed from the ledger (F1 design §3.3, steps 1–5). Pure: everything is worked out once, from the
/// session's placed events.
public struct SessionRecord: Sendable, Equatable, Identifiable {
    /// A locked break: inside the planned length, never moving the end (F1-11).
    public struct Break: Sendable, Equatable {
        public let start: Date
        public let plannedEnd: Date
        public let end: Date?
    }

    public let id: UUID
    public let plan: FocusPlan
    public let source: FocusSource
    /// The `sessionStarted` event.
    public let started: PlacedEvent
    /// The session's events in ledger order, from `sessionStarted` on.
    public let events: [PlacedEvent]
    /// The confirmed block, where credit and the countdown start.
    public let applied: PlacedEvent?
    /// The first terminal event; later ones are ignored.
    public let end: PlacedEvent?
    public let reflection: Reflection?
    public let isHidden: Bool
    /// When proof stopped: a failed read-back, or an event this build doesn't know that can change credit.
    public let lostAt: Date?
    /// The last checkpoint before proof stopped (the receipt's "Couldn't confirm the block after 14:10").
    public let lastCheckpoint: Date?
    /// Proven locked time: per boot, from its first read-back (or the confirmed block) to its last checkpoint, never
    /// past the planned end or the end.
    public let provenIntervals: [DateInterval]
    /// Override windows, each removed whole.
    public let overrides: [DateInterval]
    public let breaks: [Break]

    /// Builds the session from its events; nil without a `sessionStarted`.
    public init?(events placed: [PlacedEvent]) {
        guard let index = placed.firstIndex(where: { if case .sessionStarted = $0.event.kind { true } else { false } }),
              case .sessionStarted(let plan) = placed[index].event.kind
        else { return nil }
        let started = placed[index]
        let events = Array(placed[index...])
        id = started.event.sessionID
        self.plan = plan
        source = started.event.source
        self.started = started
        self.events = events

        var applied: PlacedEvent?
        var end: PlacedEvent?
        var reflection: Reflection?
        var hidden = false
        var lost: Date?
        var lastCheckpoint: Date?
        var intervals: [DateInterval] = []
        var open: (start: Date, last: Date, boot: String)?
        var overrides: [DateInterval] = []
        var overrideStart: Date?
        var breaks: [Break] = []

        for item in events.dropFirst() {
            let kind = item.event.kind
            switch kind {
            case .reflected(let answer):
                reflection = answer
                continue
            case .sessionHidden:
                hidden = true
                continue
            default:
                break
            }
            guard end == nil, item.event.affectsCredit else { continue }
            if lost != nil {
                // Nothing after lost proof counts, but the session can still end.
                if kind.isTerminal { end = item }
                continue
            }
            switch kind {
            case .unknown, .shieldLost:
                lost = item.placed
                continue
            case .overrideStarted:
                overrideStart = overrideStart ?? item.placed
            case .overrideEnded:
                if let from = overrideStart { overrides.append(DateInterval(start: from, end: max(from, item.placed))) }
                overrideStart = nil
            case .breakStarted(let seconds):
                breaks.append(Break(start: item.placed, plannedEnd: item.placed.addingTimeInterval(TimeInterval(seconds)), end: nil))
            case .breakEnded:
                if let last = breaks.last, last.end == nil {
                    breaks[breaks.count - 1] = Break(start: last.start, plannedEnd: last.plannedEnd, end: item.placed)
                }
            default:
                break
            }
            if kind == .shieldApplied, applied == nil {
                applied = item
                open = (item.placed, item.placed, item.event.stamp.boot)
                lastCheckpoint = item.placed
            } else if kind.isCheckpoint, applied != nil {
                if let current = open, current.boot == item.event.stamp.boot {
                    open = (current.start, item.placed, current.boot)
                } else {
                    if let current = open { intervals.append(DateInterval(start: current.start, end: current.last)) }
                    open = (item.placed, item.placed, item.event.stamp.boot)
                }
                lastCheckpoint = item.placed
            }
            if kind.isTerminal { end = item }
        }
        if let current = open { intervals.append(DateInterval(start: current.start, end: current.last)) }

        let countdownStart = applied?.placed ?? started.placed
        let plannedEnd = countdownStart.addingTimeInterval(TimeInterval(plan.plannedSeconds))
        if let from = overrideStart {
            overrides.append(DateInterval(start: from, end: max(from, min(end?.placed ?? plannedEnd, plannedEnd))))
        }
        let limit = min(plannedEnd, end?.placed ?? plannedEnd)
        self.applied = applied
        self.end = end
        self.reflection = reflection
        isHidden = hidden
        lostAt = lost
        self.lastCheckpoint = lastCheckpoint.map { min($0, plannedEnd) }
        provenIntervals = plan.kind == .blocking ? intervals.compactMap { interval in
            let from = max(interval.start, countdownStart), to = min(interval.end, limit)
            return to > from ? DateInterval(start: from, end: to) : nil
        } : []
        self.overrides = overrides
        self.breaks = breaks
    }

    /// Where the countdown runs from: the confirmed block, or the tap for a plain timer.
    public var countdownStart: Date { applied?.placed ?? started.placed }
    /// The countdown start plus the planned length. Breaks never move it (F1-11).
    public var plannedEnd: Date { countdownStart.addingTimeInterval(TimeInterval(plan.plannedSeconds)) }
    public var isEnded: Bool { end != nil }

    public var endReason: EndReason? {
        if case .sessionEnded(let reason, _) = end?.event.kind { return reason }
        return nil
    }

    public var endVerified: Bool {
        if case .sessionEnded(_, let verified) = end?.event.kind { return verified }
        return false
    }

    /// The preset's one break has been taken.
    public var breakUsed: Bool { !breaks.isEmpty }

    /// When the break running at `date` ends (cut short at the planned end); nil when no break is running.
    public func breakEnd(at date: Date) -> Date? {
        guard end == nil, let last = breaks.last, last.end == nil else { return nil }
        let until = min(last.plannedEnd, plannedEnd)
        return date < until ? until : nil
    }
}
