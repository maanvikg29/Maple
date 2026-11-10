import Foundation
import MapleFocusCore

/// Saved today (F1 design §5.9, focus spec §3.3): the day's total, and each session's counted time with the reasons for
/// any time that didn't count. Seconds are display credit, so the total matches Home's numeral while a session runs.
public struct SavedTodayModel: Sendable, Equatable {
    public struct Row: Sendable, Hashable, Identifiable {
        public let id: UUID
        /// "Study · 14:00–15:10 · 1h 5m"; a session that counted nothing leaves its duration out.
        public let title: String
        /// Counted seconds, plus a running session's provisional time.
        public let countedSeconds: Int
        /// The greyed lines, in the order the time happened: "Unlocked 5 min", "After bedtime".
        public let reasons: [String]
        public let isRunning: Bool
        /// The row for VoiceOver, its lengths in words and a sentence per reason: "Study, 14:00 to 15:10, 1 hour,
        /// 5 minutes. Unlocked 5 minutes".
        public let spoken: String
    }

    public static let title = "Saved today"
    public static let emptyText = "Nothing saved yet today."
    /// The definition (focus spec §3.3), shown on first use and behind the info button.
    public static var definition: String { RewardCategoryInfo(.hoursSaved).definition }
    /// "How we count", one sentence a line. Phone breaks are F2, so F1 leaves them out.
    public static let howWeCount = [
        "Counts only while your chosen apps are locked.", "Sleep doesn't count.", "Unlocks don't count.", "Overlaps count once.",
        "Up to 6 hours count each day.",
    ]

    public let rows: [Row]
    public let totalSeconds: Int
    /// "2h 10m".
    public let total: String
    /// The total for VoiceOver: "2 hours, 10 minutes".
    public let totalSpoken: String
    /// "Nothing saved yet today." when there are no rows.
    public var emptyLine: String? { rows.isEmpty ? Self.emptyText : nil }

    /// - Parameters:
    ///   - credits: Credit for every open session (`HoursCredit.credit` over all of them), so caps and overlaps are
    ///     already applied.
    ///   - sessions: The replayed sessions those credits came from.
    ///   - day: The Maple day to show.
    ///   - now: Trusted time (`FocusSessionStore.now`): a running session's time since its last checkpoint is
    ///     provisional, not a reason.
    public init(credits: [SessionCredit], sessions: [SessionRecord], day: LocalDay, now: Date, calendar: Calendar, locale: Locale) {
        var byID: [UUID: SessionRecord] = [:]
        for session in sessions where byID[session.id] == nil { byID[session.id] = session }
        let todays = credits.filter { $0.day == day }
        let countedToday = todays.reduce(0) { $0 + $1.seconds }
        func clock(_ date: Date) -> String {
            HomeFormat.clock(HomeFormat.clockTime(of: date, calendar: calendar), locale: locale)
        }

        var found: [(start: Date, row: Row)] = []
        for credit in todays {
            guard let session = byID[credit.id], !session.isHidden else { continue }
            let running = session.end == nil
            let end = max(session.countdownStart, session.endedAt ?? min(now, session.plannedEnd))
            let provisional = running
                ? HoursCredit.provisionalSeconds(for: session, now: now, roomLeftToday: HoursCredit.dailyCap - countedToday) : 0
            let counted = credit.seconds + provisional
            // A start that never got going (a block that couldn't be written) is no session to list.
            guard counted > 0 || end.timeIntervalSince(session.countdownStart) >= 60 else { continue }

            var order: [CreditRule] = []
            var seconds: [CreditRule: TimeInterval] = [:]
            for stretch in credit.stretches {
                guard let rule = stretch.rule else { continue }
                // A running session's time since its last checkpoint is provisional: it isn't a reason.
                if running, session.lostAt == nil, rule == .unconfirmed, stretch.interval.end >= end.addingTimeInterval(-1) { continue }
                if seconds[rule] == nil { order.append(rule) }
                seconds[rule, default: 0] += stretch.interval.duration
            }
            let named = order.filter { seconds[$0, default: 0] >= 1 }
            let reasons = named.map { CreditWords.line($0, seconds: Int(seconds[$0, default: 0].rounded())) }
            let span = "\(session.plan.presetName) · \(clock(session.countdownStart))–\(clock(end))"
            let title = counted >= 60 ? "\(span) · \(HomeFormat.duration(minutes: counted / 60))" : span
            // Spoken: a comma for each "·", "to" for the dash, lengths in words, then each reason as its own sentence.
            let spokenSpan = "\(session.plan.presetName), \(clock(session.countdownStart)) to \(clock(end))"
            let spokenTitle = counted >= 60
                ? "\(spokenSpan), \(FocusTimeText.spokenLength(minutes: counted / 60, locale: locale))" : spokenSpan
            let spokenReasons = named.map {
                CreditWords.spokenLine($0, seconds: Int(seconds[$0, default: 0].rounded()), locale: locale)
            }
            found.append((start: session.countdownStart,
                          row: Row(id: session.id, title: title, countedSeconds: counted, reasons: reasons, isRunning: running,
                                   spoken: ([spokenTitle] + spokenReasons).joined(separator: ". "))))
        }
        rows = found.sorted { $0.start < $1.start }.map { $0.row }
        totalSeconds = rows.reduce(0) { $0 + $1.countedSeconds }
        total = HomeFormat.duration(minutes: totalSeconds / 60)
        totalSpoken = FocusTimeText.spokenLength(minutes: totalSeconds / 60, locale: locale)
    }
}
