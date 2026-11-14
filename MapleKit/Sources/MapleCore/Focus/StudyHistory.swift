import Foundation
import MapleFocusCore

/// One session as History counts it (F2 Study record).
public struct StudySession: Sendable, Equatable, Identifiable {
    public let id: UUID
    /// The Maple day it was started in: a session after midnight stays with its evening.
    public let day: LocalDay
    /// The countdown's start and the focus end (`SessionRecord.focusEnd`).
    public let start: Date
    public let end: Date
    public let presetName: String
    public let subjectID: UUID?
    /// History's measure: the session's length without its breaks.
    public let focusedSeconds: Int
    /// Counted toward leaves: 0 for a plain timer.
    public let savedSeconds: Int
    /// It counted as a finished session (F1-7).
    public let finished: Bool
    /// It ran to its planned end: a full ring in the list; half for one ended early or cut off.
    public let ranToEnd: Bool
    public let reflection: Reflection?
}

/// History's sessions from the replayed ledger (F2 Study record). Pure.
public enum StudyHistory {
    /// A start that never got going is no session to list.
    public static let minimumSeconds = 60

    /// Every session History lists, in start order. Left out: sessions removed from History, the running session, and
    /// starts with under a minute focused. A session whose end was never written is listed up to its last confirmed
    /// moment.
    /// - Parameters:
    ///   - credits: `HoursCredit.credit` over all of `records`, removed ones included: removing a session from History
    ///     never changes what another one counted.
    ///   - running: The session running now.
    public static func sessions(_ records: [SessionRecord], credits: [SessionCredit], running: UUID?) -> [StudySession] {
        var byID: [UUID: SessionCredit] = [:]
        for credit in credits where byID[credit.id] == nil { byID[credit.id] = credit }
        return records.compactMap { record in
            guard !record.isHidden, record.id != running else { return nil }
            let focused = record.focusedSeconds
            guard focused >= minimumSeconds else { return nil }
            let credit = byID[record.id]
            return StudySession(
                id: record.id, day: record.plan.day, start: record.countdownStart, end: record.focusEnd,
                presetName: record.plan.presetName, subjectID: record.subjectID, focusedSeconds: focused,
                savedSeconds: credit?.seconds ?? 0, finished: credit?.finished ?? false,
                ranToEnd: record.endReason == .completed, reflection: record.reflection
            )
        }
    }
}

/// A week or a month of History.
public struct HistoryPeriod: Sendable, Hashable {
    public enum Span: String, Sendable, CaseIterable {
        case week, month
    }

    public let span: Span
    /// Its days in order: 7 from the calendar's first weekday (as the streak's week, P8), or a calendar month.
    public let days: [LocalDay]

    public init(_ span: Span, containing day: LocalDay, calendar: Calendar) {
        self.span = span
        switch span {
        case .week:
            let offset = (calendar.component(.weekday, from: HistoryDates.noon(day, calendar)) - calendar.firstWeekday + 7) % 7
            let first = day.adding(days: -offset, calendar: calendar)
            days = (0..<7).map { first.adding(days: $0, calendar: calendar) }
        case .month:
            let first = LocalDay(year: day.year, month: day.month, day: 1)
            let count = calendar.range(of: .day, in: .month, for: HistoryDates.noon(first, calendar))?.count ?? 30
            days = (1...max(1, count)).map { LocalDay(year: day.year, month: day.month, day: $0) }
        }
    }

    public func contains(_ day: LocalDay) -> Bool {
        guard let first = days.first, let last = days.last else { return false }
        return day >= first && day <= last
    }

    /// The period `steps` weeks or months later (earlier when negative).
    public func shifted(by steps: Int, calendar: Calendar) -> HistoryPeriod {
        guard steps != 0, let first = days.first else { return self }
        switch span {
        case .week:
            return HistoryPeriod(.week, containing: first.adding(days: 7 * steps, calendar: calendar), calendar: calendar)
        case .month:
            let index = first.year * 12 + (first.month - 1) + steps
            return HistoryPeriod(.month, containing: LocalDay(year: index / 12, month: index % 12 + 1, day: 1), calendar: calendar)
        }
    }

    /// "This week", "2–8 Nov", "26 Oct – 1 Nov"; "This month", "October", "December 2025".
    public func title(today: LocalDay, calendar: Calendar, locale: Locale) -> String {
        guard let first = days.first, let last = days.last else { return "" }
        if contains(today) { return span == .week ? "This week" : "This month" }
        let dates = HistoryDates(calendar: calendar, locale: locale)
        switch span {
        case .month: return dates.month(first, withYear: first.year != today.year)
        case .week: return dates.range(first, last, withYear: last.year != today.year)
        }
    }
}

/// History's dates in words. Each piece is formatted on its own (a weekday, a day and month), then joined with a
/// space, so the words don't depend on how a locale punctuates a longer date.
struct HistoryDates {
    let calendar: Calendar
    let locale: Locale

    static func noon(_ day: LocalDay, _ calendar: Calendar) -> Date {
        day.startDate(in: calendar).addingTimeInterval(12 * 3600)
    }

    private var style: Date.FormatStyle {
        Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    }

    /// "9 Nov"; "9 November" when wide.
    func dayMonth(_ day: LocalDay, wide: Bool = false) -> String {
        Self.noon(day, calendar).formatted(style.day().month(wide ? .wide : .abbreviated))
    }

    /// "Mon"; "Monday" when wide.
    func weekday(_ day: LocalDay, wide: Bool = false) -> String {
        Self.noon(day, calendar).formatted(style.weekday(wide ? .wide : .abbreviated))
    }

    /// "October"; "December 2025".
    func month(_ day: LocalDay, withYear: Bool) -> String {
        Self.noon(day, calendar).formatted(withYear ? style.month(.wide).year() : style.month(.wide))
    }

    /// "2–8 Nov" inside a month, "26 Oct – 1 Nov" across two; the year is added when it isn't this one.
    func range(_ first: LocalDay, _ last: LocalDay, withYear: Bool) -> String {
        let end = dayMonth(last)
        let text: String
        if first.month != last.month || first.year != last.year {
            text = "\(dayMonth(first)) – \(end)"
        } else if end.first?.isNumber == true {
            text = "\(first.day)–\(end)"
        } else {
            text = "\(dayMonth(first))–\(last.day)"
        }
        return withYear ? "\(text) \(last.year)" : text
    }

    /// "Today", "Yesterday", "Mon 9 Nov"; "Tue 30 Dec 2025" in another year.
    func dayTitle(_ day: LocalDay, today: LocalDay) -> String {
        if day == today { return "Today" }
        if day == today.adding(days: -1, calendar: calendar) { return "Yesterday" }
        let text = "\(weekday(day)) \(dayMonth(day))"
        return day.year == today.year ? text : "\(text) \(day.year)"
    }

    func clock(_ date: Date) -> String {
        HomeFormat.clock(HomeFormat.clockTime(of: date, calendar: calendar), locale: locale)
    }
}

/// History (F2 Study record): one week or month of sessions. Its numeral is time focused; time saved is the smaller
/// line under it. Pure: every word the screen shows is here.
public struct HistoryPage: Sendable, Equatable {
    /// A "By subject" row: a subject, or the sessions without one.
    public enum SubjectKey: Sendable, Hashable {
        case subject(UUID)
        case none
    }

    public struct Bar: Sendable, Equatable, Identifiable {
        public let day: LocalDay
        public let seconds: Int
        /// A session finished that day: the bar's season-tint dot.
        public let hasFinished: Bool
        /// The weekday's initial in a week; the date's number in a month.
        public let label: String
        /// "Monday 9 November, 50 minutes"; "…, no sessions".
        public let spoken: String
        public var id: LocalDay { day }
    }

    public struct SubjectRow: Sendable, Equatable, Identifiable {
        public let key: SubjectKey
        public let name: String
        public let seconds: Int
        /// "2h 10m".
        public let time: String
        /// Its time against the longest row's, 0…1: the row's thin bar.
        public let share: Double
        /// A removed subject: drawn dimmer.
        public let isPast: Bool
        /// The session list is filtered to this row.
        public let isSelected: Bool
        public var id: SubjectKey { key }
    }

    public struct SessionRow: Sendable, Equatable, Identifiable {
        public let id: UUID
        /// "Study · Biology".
        public let title: String
        /// When it started: "14:10".
        public let time: String
        /// "48m".
        public let focused: String
        /// "Not counted" for a session that saved nothing.
        public let note: String?
        public let intention: String?
        public let ranToEnd: Bool
        public let spoken: String
    }

    public struct DayGroup: Sendable, Equatable, Identifiable {
        public let day: LocalDay
        /// "Today", "Yesterday", "Mon 9 Nov".
        public let title: String
        public let rows: [SessionRow]
        public var id: LocalDay { day }
    }

    public static let noSubject = "No subject"
    public static let notCounted = "Not counted"
    public static let screenTitle = "History"
    public static let bySubjectTitle = "By subject"
    /// The header link on the Focus tab.
    public static let link = "History"

    /// "This week", "2–8 Nov", "October".
    public let title: String
    /// "6h 20m".
    public let numeral: String
    /// "focused".
    public let caption: String
    /// "6 hours, 20 minutes focused", for VoiceOver.
    public let numeralSpoken: String
    /// "4h 10m saved · 5 sessions finished"; nil when nothing was saved or finished.
    public let savedLine: String?
    public let bars: [Bar]
    /// The tallest bar's seconds.
    public let peakSeconds: Int
    /// Longest first, then removed subjects, then "No subject". Empty until the member has made a subject.
    public let subjects: [SubjectRow]
    /// Newest day first; inside a day, the newest session first.
    public let groups: [DayGroup]
    public let emptyLine: String?
    public let canGoBack: Bool
    public let canGoForward: Bool

    /// - Parameters:
    ///   - sessions: Every session History lists (`StudyHistory.sessions`).
    ///   - today: The Maple day being lived in.
    ///   - intentions: Each session's intention, from `session-notes.json`.
    ///   - filter: A "By subject" row the member tapped: it filters the session list, never the totals.
    public init(
        sessions: [StudySession], period: HistoryPeriod, today: LocalDay, subjects list: SubjectList, intentions: [UUID: String],
        filter: SubjectKey?, calendar: Calendar, locale: Locale
    ) {
        let dates = HistoryDates(calendar: calendar, locale: locale)
        let inPeriod = sessions.filter { period.contains($0.day) }
        func key(_ session: StudySession) -> SubjectKey {
            session.subjectID.flatMap { list.subject(id: $0) }.map { .subject($0.id) } ?? .none
        }

        title = period.title(today: today, calendar: calendar, locale: locale)
        let total = inPeriod.reduce(0) { $0 + $1.focusedSeconds }
        numeral = HomeFormat.duration(minutes: total / 60)
        caption = "focused"
        numeralSpoken = "\(FocusTimeText.spokenLength(minutes: total / 60, locale: locale)) focused"
        let saved = inPeriod.reduce(0) { $0 + $1.savedSeconds } / 60
        let finished = inPeriod.filter(\.finished).count
        var parts: [String] = []
        if saved > 0 { parts.append("\(HomeFormat.duration(minutes: saved)) saved") }
        if finished > 0 { parts.append(finished == 1 ? "1 session finished" : "\(finished) sessions finished") }
        savedLine = parts.isEmpty ? nil : parts.joined(separator: " · ")

        let initials = FocusSheetCopy.weekdayInitials(calendar: calendar)
        var byDay: [LocalDay: [StudySession]] = [:]
        for session in inPeriod { byDay[session.day, default: []].append(session) }
        bars = period.days.enumerated().map { index, day in
            let seconds = byDay[day, default: []].reduce(0) { $0 + $1.focusedSeconds }
            let length = seconds >= 60 ? FocusTimeText.spokenLength(minutes: seconds / 60, locale: locale) : "no sessions"
            return Bar(
                day: day, seconds: seconds, hasFinished: byDay[day, default: []].contains(where: \.finished),
                label: period.span == .week ? (initials.indices.contains(index) ? initials[index] : "") : "\(day.day)",
                spoken: "\(dates.weekday(day, wide: true)) \(dates.dayMonth(day, wide: true)), \(length)"
            )
        }
        peakSeconds = bars.map(\.seconds).max() ?? 0

        var bySubject: [SubjectKey: Int] = [:]
        for session in inPeriod { bySubject[key(session), default: 0] += session.focusedSeconds }
        var found: [(key: SubjectKey, name: String, seconds: Int, isPast: Bool)] = []
        if !list.isEmpty {
            // A stable sort: subjects with the same time keep the member's order.
            for past in [false, true] {
                let rows = list.subjects.filter { $0.isRemoved == past }
                    .compactMap { subject in bySubject[.subject(subject.id)].map { (subject, $0) } }
                    .enumerated().sorted { ($1.element.1, $0.offset) < ($0.element.1, $1.offset) }
                found += rows.map { (key: .subject($0.element.0.id), name: $0.element.0.name, seconds: $0.element.1, isPast: past) }
            }
            if let seconds = bySubject[.none] { found.append((key: .none, name: Self.noSubject, seconds: seconds, isPast: false)) }
        }
        let longest = max(1, found.map(\.seconds).max() ?? 1)
        subjects = found.map {
            SubjectRow(key: $0.key, name: $0.name, seconds: $0.seconds, time: HomeFormat.duration(minutes: $0.seconds / 60),
                       share: Double($0.seconds) / Double(longest), isPast: $0.isPast, isSelected: $0.key == filter)
        }

        let listed = inPeriod.filter { filter == nil || key($0) == filter }
        var grouped: [LocalDay: [StudySession]] = [:]
        for session in listed { grouped[session.day, default: []].append(session) }
        groups = grouped.keys.sorted(by: >).map { day in
            let rows = grouped[day, default: []].sorted { ($0.start, $0.id.uuidString) > ($1.start, $1.id.uuidString) }.map { session in
                let subject = list.name(for: session.subjectID)
                let note = session.savedSeconds == 0 ? Self.notCounted : nil
                let intention = intentions[session.id].flatMap { RecentIntentions.normalized($0) }
                let time = dates.clock(session.start)
                let length = FocusTimeText.spokenLength(minutes: session.focusedSeconds / 60, locale: locale)
                let head = ([session.presetName] + [subject].compactMap { $0 } + [time, "\(length) focused"]).joined(separator: ", ")
                return SessionRow(
                    id: session.id, title: FocusCopy.sessionTitle(presetName: session.presetName, subject: subject, intention: nil),
                    time: time, focused: HomeFormat.duration(minutes: session.focusedSeconds / 60), note: note, intention: intention,
                    ranToEnd: session.ranToEnd, spoken: ([head] + [note, intention].compactMap { $0 }).joined(separator: ". ")
                )
            }
            return DayGroup(day: day, title: dates.dayTitle(day, today: today), rows: rows)
        }

        if sessions.isEmpty {
            emptyLine = "Your sessions will appear here."
        } else if inPeriod.isEmpty {
            let which = period.contains(today) ? "this" : "that"
            emptyLine = "No sessions \(which) \(period.span == .week ? "week" : "month")."
        } else if listed.isEmpty {
            emptyLine = "No sessions for this subject."
        } else {
            emptyLine = nil
        }
        canGoBack = period.days.first.map { first in sessions.contains { $0.day < first } } ?? false
        canGoForward = period.days.last.map { $0 < today } ?? false
    }

    /// The Focus tab's strip under Start: "6h 20m focused this week". Nil before the first session.
    public static func weekStrip(_ sessions: [StudySession], today: LocalDay, calendar: Calendar) -> String? {
        guard !sessions.isEmpty else { return nil }
        let week = HistoryPeriod(.week, containing: today, calendar: calendar)
        let seconds = sessions.filter { week.contains($0.day) }.reduce(0) { $0 + $1.focusedSeconds }
        return "\(HomeFormat.duration(minutes: seconds / 60)) focused this week"
    }
}

/// One session opened from History (F2 Study record): when it ran, its timeline, and what it counted.
public struct SessionDetailModel: Sendable, Equatable {
    /// A stretch of the timeline, as shares of the session's length.
    public struct Segment: Sendable, Equatable {
        public enum Kind: Sendable, Hashable, CaseIterable {
            /// Apps locked, with proof.
            case locked
            /// Apps not locked: a plain timer, or time after the block couldn't be confirmed.
            case open
            case breakTime
            /// A "Need it?" unlock.
            case unlocked

            public var label: String {
                switch self {
                case .locked: "Locked"
                case .open: "Apps not locked"
                case .breakTime: "Break"
                case .unlocked: "Unlocked"
                }
            }
        }

        public let from: Double
        public let to: Double
        public let kind: Kind
    }

    public static let removeTitle = "Remove from History"
    public static let removeQuestion = "Remove this session?"
    public static let removeBody = "Leaves it earned stay yours."
    public static let removeConfirm = "Remove"
    public static let keep = "Keep"
    public static let reflectionTitle = "How did it go?"
    public static let subjectTitle = "Subject"
    public static let intentionTitle = "What it was for"
    public static let addIntention = "Add a note"

    /// "Study · Biology".
    public let title: String
    /// "Tue 10 Nov · 14:00–15:00".
    public let whenLine: String
    public let segments: [Segment]
    /// The kinds the timeline holds, in a fixed order, for its key.
    public let legend: [Segment.Kind]
    /// "Locked 50 minutes. Break 5 minutes. Unlocked 5 minutes."
    public let timelineSpoken: String
    /// "Focused 55m · Saved 55m"; "Focused 25m · Not counted".
    public let totalsLine: String
    /// Why time didn't count, in the receipt's words: "Unlocked 5 min".
    public let reasons: [String]

    /// - Parameters:
    ///   - credit: The session's credit, from `HoursCredit.credit` over every session.
    ///   - subject: Its subject's name.
    ///   - today: The Maple day being lived in.
    public init(session: SessionRecord, credit: SessionCredit?, subject: String?, today: LocalDay, calendar: Calendar, locale: Locale) {
        let dates = HistoryDates(calendar: calendar, locale: locale)
        let start = session.countdownStart, end = session.focusEnd
        let day = session.plan.day
        title = FocusCopy.sessionTitle(presetName: session.plan.presetName, subject: subject, intention: nil)
        whenLine = "\(dates.dayTitle(day, today: today)) · \(dates.clock(start))–\(dates.clock(end))"

        // Cut the session at every change, then name each piece by what covers its middle.
        let breaks = session.breakIntervals
        var cuts: Set<Date> = [start, end]
        for interval in breaks + session.overrides + session.provenIntervals {
            cuts.insert(min(max(interval.start, start), end))
            cuts.insert(min(max(interval.end, start), end))
        }
        let points = cuts.sorted()
        let whole = max(1, end.timeIntervalSince(start))
        var pieces: [(from: Date, to: Date, kind: Segment.Kind)] = []
        for (from, to) in zip(points, points.dropFirst()) where to > from {
            let middle = from.addingTimeInterval(to.timeIntervalSince(from) / 2)
            let kind: Segment.Kind = if breaks.contains(where: { $0.contains(middle) }) {
                .breakTime
            } else if session.overrides.contains(where: { $0.contains(middle) }) {
                .unlocked
            } else if session.provenIntervals.contains(where: { $0.contains(middle) }) {
                .locked
            } else {
                .open
            }
            if let last = pieces.last, last.kind == kind {
                pieces[pieces.count - 1].to = to
            } else {
                pieces.append((from, to, kind))
            }
        }
        segments = pieces.map {
            Segment(from: $0.from.timeIntervalSince(start) / whole, to: $0.to.timeIntervalSince(start) / whole, kind: $0.kind)
        }
        var seconds: [Segment.Kind: TimeInterval] = [:]
        for piece in pieces { seconds[piece.kind, default: 0] += piece.to.timeIntervalSince(piece.from) }
        legend = Segment.Kind.allCases.filter { seconds[$0] != nil }
        timelineSpoken = legend.map { kind in
            let minutes = max(1, Int((seconds[kind, default: 0] / 60).rounded()))
            return "\(kind.label) \(FocusTimeText.spokenLength(minutes: minutes, locale: locale))."
        }.joined(separator: " ")

        let focused = "Focused \(HomeFormat.duration(minutes: session.focusedSeconds / 60))"
        let saved = credit?.seconds ?? 0
        totalsLine = saved > 0 ? "\(focused) · Saved \(HomeFormat.duration(minutes: saved / 60))" : "\(focused) · \(HistoryPage.notCounted)"

        var order: [CreditRule] = []
        var lost: [CreditRule: TimeInterval] = [:]
        for stretch in credit?.stretches ?? [] {
            guard let rule = stretch.rule else { continue }
            if lost[rule] == nil { order.append(rule) }
            lost[rule, default: 0] += stretch.interval.duration
        }
        reasons = order.filter { lost[$0, default: 0] >= 1 }.map {
            CreditWords.line($0, seconds: Int(lost[$0, default: 0].rounded()), earlierDay: day != today)
        }
    }
}
