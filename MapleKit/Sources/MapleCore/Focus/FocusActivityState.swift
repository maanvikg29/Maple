import Foundation
import MapleFocusCore

/// What the Live Activity shows for a running session (F1 design §5.11): display only, no buttons.
///
/// The Lock Screen and the compact view show the preset name only; the intention, capped at 40 characters, appears
/// only in the expanded view, which the member opens on purpose. The store builds this from the session; the Live
/// Activity controller then adds the intention, the season tint and the next hours leaf with `described(…)`.
public struct FocusActivityState: Sendable, Hashable {
    /// The longest intention the expanded view shows (§5.11).
    public static let intentionLimit = 40

    public var sessionID: UUID
    public var presetName: String
    public var start: Date
    public var plannedEnd: Date
    public var isPlainTimer: Bool
    /// When a running break ends ("Break · back at 14:28"); nil outside a break.
    public var breakEnd: Date?
    /// The session's intention, trimmed and capped at `intentionLimit` characters; nil when there is none.
    public private(set) var intention: String?
    /// The Lock Screen leaf's colour: the season tint as 0xRRGGBB, never gold. Nil until described.
    public private(set) var tint: LeafColor?
    /// The next hours leaf, drawn as a skeleton. Always nil for a plain timer, which shows no leaf.
    public private(set) var leafID: String?

    public init(session: SessionRecord, now: Date) {
        self.init(
            sessionID: session.id, presetName: session.plan.presetName, start: session.countdownStart,
            plannedEnd: session.plannedEnd, isPlainTimer: session.plan.kind == .plainTimer, breakEnd: session.breakEnd(at: now)
        )
    }

    public init(
        sessionID: UUID, presetName: String, start: Date, plannedEnd: Date, isPlainTimer: Bool, breakEnd: Date? = nil,
        intention: String? = nil, tint: LeafColor? = nil, leafID: String? = nil
    ) {
        self.sessionID = sessionID
        self.presetName = presetName
        self.start = start
        self.plannedEnd = plannedEnd
        self.isPlainTimer = isPlainTimer
        self.breakEnd = breakEnd
        self.intention = Self.capped(intention)
        self.tint = tint
        self.leafID = isPlainTimer ? nil : leafID
    }

    /// This state with what the store doesn't know: the session's intention, the season's tint and the next hours
    /// leaf (none for a plain timer).
    public func described(intention: String?, tint: LeafColor, leafID: String?) -> FocusActivityState {
        FocusActivityState(
            sessionID: sessionID, presetName: presetName, start: start, plannedEnd: plannedEnd, isPlainTimer: isPlainTimer,
            breakEnd: breakEnd, intention: intention, tint: tint, leafID: leafID
        )
    }

    /// `text` trimmed and capped at `intentionLimit` characters, a longer one ending in "…"; nil when empty.
    public static func capped(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        guard text.count > intentionLimit else { return text }
        return String(text.prefix(intentionLimit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// The words the Live Activity shows, worked out in the app because the widget can't link MapleCore.
    public struct Lines: Sendable, Hashable {
        /// "Study", or "Plain timer".
        public var title: String
        /// Under the timer on the Lock Screen: "until 14:52 · Study"; "Break · back at 14:28" during a break.
        public var lockLine: String
        /// The expanded view's line: "Study · Chemistry ch. 4"; "Break · back at 14:28" during a break.
        public var expandedLine: String
        /// Once the planned end has passed (the activity is stale): "Session complete".
        public var complete: String
    }

    /// The lines in `locale`'s clock style ("14:52", "2:52 PM") and `calendar`'s time zone.
    public func lines(locale: Locale, calendar: Calendar) -> Lines {
        func clock(_ date: Date) -> String {
            HomeFormat.clock(HomeFormat.clockTime(of: date, calendar: calendar), locale: locale)
        }
        let title = isPlainTimer ? "Plain timer" : presetName
        let breakLine = breakEnd.map { "Break · back at \(clock($0))" }
        return Lines(
            title: title,
            lockLine: breakLine ?? "until \(clock(plannedEnd)) · \(title)",
            expandedLine: breakLine ?? ([title] + [intention].compactMap { $0 }).joined(separator: " · "),
            complete: "Session complete"
        )
    }
}
