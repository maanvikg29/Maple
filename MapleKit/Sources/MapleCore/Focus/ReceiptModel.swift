import Foundation
import MapleFocusCore

/// Which marks of a finished session's dial counted (F1 design §4.2, §5.8).
public enum ReceiptMarks {
    /// One state per mark of `layout`, from the countdown's start: lit when the mark's whole span counted, a gap
    /// otherwise. Each span is `minutesPerMark` long, and the last stops at the planned end, so a 65-minute plan's last
    /// mark covers 1 minute. Breaks count, so their marks light.
    public static func marks(layout: DialLayout, countdownStart: Date, stretches: [CreditStretch]) -> [MarkState] {
        let counted = merged(stretches.filter(\.counted).map(\.interval))
        let end = countdownStart.addingTimeInterval(TimeInterval(layout.plannedMinutes * 60))
        let span = TimeInterval(layout.minutesPerMark * 60)
        return (0..<layout.markCount).map { index in
            let from = countdownStart.addingTimeInterval(TimeInterval(index) * span)
            let to = min(end, from.addingTimeInterval(span))
            guard to > from else { return .gap }
            let covered = counted.reduce(0.0) { total, piece in
                let start = max(piece.start, from), finish = min(piece.end, to)
                return finish > start ? total + finish.timeIntervalSince(start) : total
            }
            return covered >= to.timeIntervalSince(from) - tolerance ? .lit : .gap
        }
    }

    /// Placed times are sums of doubles; a millisecond is far below any mark.
    static let tolerance: TimeInterval = 0.001

    /// The union of `intervals`, so overlapping stretches are never counted twice.
    static func merged(_ intervals: [DateInterval]) -> [DateInterval] {
        var result: [DateInterval] = []
        for piece in intervals.sorted(by: { $0.start < $1.start }) {
            if let last = result.last, piece.start <= last.end {
                result[result.count - 1] = DateInterval(start: last.start, end: max(last.end, piece.end))
            } else {
                result.append(piece)
            }
        }
        return result
    }
}

/// A finished session's receipt: its final frame (F1 design §5.8, §5.7's ended state, §4.6's finish).
public struct ReceiptModel: Sendable, Equatable {
    public enum Ending: Sendable, Hashable {
        /// It reached its planned end with the app watching.
        case onTime
        /// It reached its planned end while Maple was closed: shown once, when the member next opens Maple. The finish
        /// plays only within 10 minutes of the end; otherwise the final frame shows still.
        case endedAway(playsFinish: Bool)
        /// End early, or Release all apps: no gold, and "Ended at 18 of 50m".
        case endedEarly
        /// Locked's emergency release: §5.7's ended state.
        case emergency
        /// It ran to its end but nothing counted (a plain timer, after bedtime, over the cap): a white finish.
        case countedNothing
        /// Its selection couldn't count (R3).
        case notQualifying
    }

    /// One "How did it go?" answer.
    public struct Choice: Sendable, Hashable {
        public let reflection: Reflection
        public let title: String
        public let isSelected: Bool
    }

    /// The finish plays only if the member sees it within this long of the end (§4.6).
    public static let finishWindow: TimeInterval = 10 * 60
    /// An end the app noticed later than this after the planned end happened while Maple was closed.
    public static let awayAfter: TimeInterval = 60

    public let ending: Ending
    /// The finish (§4.6) plays now: within 10 minutes of the end, never after an emergency release.
    public let playsFinish: Bool
    /// Counted marks sweep gold: a session that reached its end and counted something (F1-18). Anything else is white.
    public let isGold: Bool
    public let countedSeconds: Int
    /// Under the header's title: "Apps open again", or "Plain timer".
    public let subtitle: String
    /// "Ended at 18 of 50m", over the numeral after an early end.
    public let note: String?
    /// "50m": counted minutes, or the minutes focused when the session couldn't count.
    public let numeral: String
    public let numeralParts: [NumeralPart]
    /// "saved · 2h 10m today".
    public let caption: String
    public let leafLine: String?
    /// An hours leaf opened: the centre leaf grows and the numeral shrinks beneath it (§4.3).
    public let leafOpened: Bool
    /// "Locked the whole time · 1 break".
    public let breakdown: String?
    /// The emergency release's "Session ended. It won't count as finished."
    public let endedLine: String?
    public let layout: DialLayout
    public let marks: [MarkState]
    /// The receipt dial's VoiceOver label (§4.9): "50 minutes saved. 2 hours, 10 minutes today."
    public let dialLabel: String
    /// "How did it go?"; nil after an emergency release.
    public let reflectionPrompt: String?
    public let choices: [Choice]
    /// "Again · 50m"; nil after an emergency release. Locked's Again is a hold, and it follows start readiness.
    public let again: String?

    /// - Parameters:
    ///   - session: The ended session.
    ///   - credit: Its credit (`FocusSessionStore.credit(for:)`); nil when its source isn't credited.
    ///   - unlocks: Leaves its credit opened (`FocusSessionStore.sessionUnlocks`).
    ///   - heldUntilMorning: The one opened leaf is held until morning (F1-12).
    ///   - next: The next hours leaf after this session's credit, for "Field maple · 1h 10m to go".
    ///   - todaySeconds: Seconds saved on the session's Maple day, this session included.
    ///   - reflection: The answer to "How did it go?" so far.
    ///   - now: Trusted time.
    public init(
        session: SessionRecord, credit: SessionCredit?, unlocks: [LeafUnlock], heldUntilMorning: Bool, next: LeafProgress?,
        todaySeconds: Int, reflection: Reflection?, now: Date, locale: Locale = .current, calendar: Calendar = .current
    ) {
        let plan = session.plan
        let counts = plan.canCount
        let counted = max(0, credit?.seconds ?? 0)
        let start = session.countdownStart
        let endedAt = max(start, session.endedAt ?? min(now, session.plannedEnd))
        let focused = Int(endedAt.timeIntervalSince(start) / 60)

        let ending: Ending
        switch session.endReason {
        case .emergencyRelease?:
            ending = .emergency
        case .endedEarly?, .releaseAll?:
            ending = .endedEarly
        case .completed?, nil:
            if plan.kind == .blocking, !counts {
                ending = .notQualifying
            } else if counted == 0 {
                ending = .countedNothing
            } else if let end = session.end, end.placed.timeIntervalSince(session.plannedEnd) > Self.awayAfter {
                ending = .endedAway(playsFinish: now.timeIntervalSince(endedAt) <= Self.finishWindow)
            } else {
                ending = .onTime
            }
        }
        self.ending = ending
        switch ending {
        case .emergency: playsFinish = false
        case .endedAway(let plays): playsFinish = plays
        default: playsFinish = now.timeIntervalSince(endedAt) <= Self.finishWindow
        }
        switch ending {
        case .onTime, .endedAway: isGold = counted > 0
        default: isGold = false
        }
        countedSeconds = counted
        subtitle = plan.kind == .plainTimer ? "Plain timer" : "Apps open again"
        if ending == .endedEarly {
            let at = focused < 60 ? "\(focused)" : FocusTimeText.length(minutes: focused)
            note = "Ended at \(at) of \(FocusTimeText.length(minutes: plan.plannedMinutes))"
        } else {
            note = nil
        }

        let shown = counts ? counted / 60 : focused
        numeral = FocusTimeText.length(minutes: shown)
        numeralParts = HomeFormat.durationParts(minutes: shown)
        if ending == .emergency {
            caption = FocusCopy.Emergency.endedCaption(countedSeconds: counted)
        } else if plan.kind == .plainTimer {
            caption = "focused · not counted toward leaves"
        } else if !counts {
            caption = "Not counted · add an app to count"
        } else {
            caption = todaySeconds >= 60 ? "saved · \(HomeFormat.duration(minutes: todaySeconds / 60)) today" : "saved · none yet today"
        }
        leafLine = Self.leafLine(counts: counts, ending: ending, unlocks: unlocks, held: heldUntilMorning, next: next)
        leafOpened = unlocks.contains { RewardCatalog.shared.reward(forSpecies: $0.speciesID)?.categoryID == .hoursSaved }
        breakdown = counts && ending != .emergency
            ? Self.breakdown(session, stretches: credit?.stretches ?? [], counted: counted, locale: locale, calendar: calendar)
            : nil
        endedLine = ending == .emergency ? FocusCopy.Emergency.endedLine : nil

        layout = DialLayout(plannedMinutes: plan.plannedMinutes)
        if plan.kind == .plainTimer {
            // A plain timer counts nothing, but its marks light wherever it ran (§5.8).
            let ran = endedAt > start ? [CreditStretch(DateInterval(start: start, end: endedAt), nil)] : []
            marks = ReceiptMarks.marks(layout: layout, countdownStart: start, stretches: ran)
        } else {
            marks = ReceiptMarks.marks(layout: layout, countdownStart: start, stretches: credit?.stretches ?? [])
        }

        let spokenShown = HomeFormat.spokenDuration(minutes: shown, locale: locale)
        if counts {
            let today = todaySeconds >= 60
                ? "\(HomeFormat.spokenDuration(minutes: todaySeconds / 60, locale: locale)) today." : "None yet today."
            dialLabel = "\(spokenShown) saved. \(today)"
        } else {
            dialLabel = "\(spokenShown) focused. Not counted toward leaves."
        }

        if ending == .emergency {
            reflectionPrompt = nil
            choices = []
            again = nil
        } else {
            reflectionPrompt = "How did it go?"
            let answers: [(Reflection, String)] = [(.allDone, "All done"), (.partly, "Partly"), (.notYet, "Not yet")]
            choices = answers.map { Choice(reflection: $0.0, title: $0.1, isSelected: $0.0 == reflection) }
            again = "Again · \(FocusTimeText.length(minutes: plan.plannedMinutes))"
        }
    }

    // MARK: Private

    private static func leafLine(counts: Bool, ending: Ending, unlocks: [LeafUnlock], held: Bool, next: LeafProgress?) -> String? {
        guard counts else { return nil }
        if unlocks.count >= 2 { return SessionForecast.openedLine(count: unlocks.count) }
        if let only = unlocks.first {
            let name = LeafCatalog.shared.species(id: only.speciesID)?.displayName ?? only.speciesID
            return SessionForecast.openedLine(leaf: name, heldUntilMorning: held)
        }
        guard ending != .emergency, let next, next.category == .hoursSaved, next.state == .locked, next.remaining > 0,
              let name = LeafCatalog.shared.species(id: next.speciesID)?.displayName else { return nil }
        return SessionForecast.leafLine(leaf: name, secondsToGo: Int((next.remaining * 3600).rounded()))
    }

    /// One line: lost proof first; otherwise the uncounted rule with the most time, or "Locked the whole time".
    private static func breakdown(
        _ session: SessionRecord, stretches: [CreditStretch], counted: Int, locale: Locale, calendar: Calendar
    ) -> String {
        if session.lostAt != nil {
            let checkpoint = session.lastCheckpoint ?? session.countdownStart
            return "Couldn't confirm the block after \(HomeFormat.clock(HomeFormat.clockTime(of: checkpoint, calendar: calendar), locale: locale))"
        }
        let breaks = session.breaks.count
        func withBreaks(_ line: String) -> String {
            breaks == 0 ? line : "\(line) · \(breaks) \(breaks == 1 ? "break" : "breaks")"
        }
        var seconds: [CreditRule: TimeInterval] = [:]
        for stretch in stretches {
            if let rule = stretch.rule { seconds[rule, default: 0] += stretch.interval.duration }
        }
        let named: [CreditRule] = [.override, .unconfirmed, .afterBedtime, .beforeMorning, .dailyCap, .overlap]
        guard let rule = named.filter({ seconds[$0, default: 0] >= 1 }).max(by: { seconds[$0, default: 0] < seconds[$1, default: 0] })
        else { return withBreaks("Locked the whole time") }

        if counted == 0 {
            switch rule {
            case .afterBedtime, .beforeMorning: return "After bedtime · this didn't count"
            case .dailyCap: return "Over today's \(HoursCredit.dailyCap / 3600)h · this didn't add"
            case .override: return "Unlocked the whole time · this didn't count"
            default: return "\(CreditWords.reason(rule)) · this didn't count"
            }
        }
        let amount = HomeFormat.duration(minutes: max(1, Int((seconds[rule, default: 0] / 60).rounded())))
        let kept = HomeFormat.duration(minutes: counted / 60)
        switch rule {
        case .override: return withBreaks("\(kept) locked · \(amount) unlocked, not counted")
        case .afterBedtime: return withBreaks("\(kept) counted · \(amount) after bedtime")
        case .beforeMorning: return withBreaks("\(kept) counted · \(amount) before morning")
        case .dailyCap: return withBreaks("\(kept) counted · \(amount) over today's \(HoursCredit.dailyCap / 3600)h")
        case .overlap: return withBreaks("\(kept) counted · \(amount) overlapped another session")
        default: return withBreaks("\(kept) counted · \(amount) unconfirmed")
        }
    }
}
