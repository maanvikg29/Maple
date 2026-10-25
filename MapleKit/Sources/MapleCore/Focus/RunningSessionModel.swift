import Foundation
import MapleFocusCore

/// The way out of a running session, by its strictness (F1 design §5.6, §5.7, §5.12).
public enum SessionEndPath: String, Sendable, Hashable, CaseIterable {
    /// Gentle: "End session", then a 5-second breathing ring.
    case gentle
    /// Steady: a 3-second hold, then a 15-second countdown that "Keep going" still cancels.
    case steady
    /// Locked: the emergency release, a 10-second hold and one slow breath.
    case emergency

    public init(_ strictness: Strictness) {
        switch strictness {
        case .gentle: self = .gentle
        case .steady: self = .steady
        case .locked: self = .emergency
        }
    }

    /// The link under the session's controls: "End early", or "Emergency release" in Locked (§5.4).
    public var title: String {
        self == .emergency ? FocusCopy.Emergency.title : Self.endEarlyTitle
    }

    /// What the session ends with when this path completes.
    public var reason: EndReason {
        self == .emergency ? .emergencyRelease : .endedEarly
    }

    public static let endEarlyTitle = "End early"
}

/// The running screen's dimming (F1 design §4.6, §5.4): after 30 seconds without a touch only the bloom and the
/// marks dim, to 50%. Never under VoiceOver or Increase Contrast. Auto-Lock is left alone.
public enum FocusDimming {
    public static let delay: TimeInterval = 30

    public static func isDimmed(idleFor seconds: TimeInterval, voiceOver: Bool, increasedContrast: Bool) -> Bool {
        !voiceOver && !increasedContrast && seconds >= delay
    }
}

/// Everything the running session screen says and decides at one moment (F1 design §4.3, §4.9, §5.4). Pure: the
/// view samples it once a second from `FocusSessionStore.now`.
public struct RunningSessionModel: Sendable, Equatable {
    /// The next hours leaf, as the counters have it (`LeafProgress`, hours).
    public struct Leaf: Sendable, Equatable {
        public var speciesID: String
        public var name: String
        /// The rung below (`LeafProgress.floor`) and the leaf's threshold.
        public var floor: Double
        public var threshold: Double
        /// The counters' hours (`LeafProgress.current`): this session's counted seconds are already in it, its
        /// provisional time is not.
        public var current: Double

        public init(speciesID: String, name: String, floor: Double, threshold: Double, current: Double) {
            self.speciesID = speciesID
            self.name = name
            self.floor = floor
            self.threshold = threshold
            self.current = current
        }

        /// The next hours leaf in `rows` (`CollectionStore.progress(at:)`): the lowest locked hours rung, as
        /// `FocusStores.nextHoursLeaf(at:collection:)` picks it for the start screen (Task 9). Nil when every hours leaf
        /// is earned.
        public init?(next rows: [LeafProgress], catalog: LeafCatalog = .shared) {
            guard let row = rows.filter({ $0.category == .hoursSaved && $0.state == .locked })
                .min(by: { $0.threshold < $1.threshold }) else { return nil }
            self.init(speciesID: row.speciesID, name: catalog.species(id: row.speciesID)?.displayName ?? row.speciesID,
                      floor: row.floor, threshold: row.threshold, current: row.current)
        }
    }

    /// An hours leaf this session opened: a checkpoint confirmed the crossing.
    public struct Opened: Sendable, Equatable {
        public var speciesID: String
        public var name: String
        /// The session minute it opened at, where the dot turned amber.
        public var minute: Int
        /// Earned in wind-down or at night: it opens in the morning (F1-12).
        public var heldUntilMorning: Bool

        public init(speciesID: String, name: String, minute: Int, heldUntilMorning: Bool) {
            self.speciesID = speciesID
            self.name = name
            self.minute = minute
            self.heldUntilMorning = heldUntilMorning
        }
    }

    /// A line whose trailing part is drawn in the secondary colour: "Field maple" · "· 17m to go".
    public struct Line: Sendable, Equatable {
        public var lead: String
        public var trail: String?

        public init(lead: String, trail: String? = nil) {
            self.lead = lead
            self.trail = trail
        }

        /// The line as one string, for VoiceOver.
        public var text: String { trail.map { "\(lead) \($0)" } ?? lead }
    }

    /// The preset's one break (§5.4).
    public static let takeBreakTitle = "Take a break"
    /// ⌄'s VoiceOver label: the session keeps running.
    public static let minimiseLabel = "Minimise session"

    /// "Study · Chemistry ch. 4", or the preset name alone.
    public let title: String
    /// "6 apps resting", "Apps resting", or "Plain timer · apps aren't locked" (a plain timer, or a block lost).
    public let restingLine: String
    public let secondsLeft: TimeInterval
    /// "32m"; "0:45" in the last minute (`DialCentre.numeralParts` splits it).
    public let remaining: String
    /// "left of 50m".
    public let caption: String
    /// The time repeated under the dial at accessibility sizes, where the dial's centre stops growing (§5.17):
    /// "32m left of 50m".
    public let timeLine: String
    /// The centre leaf's species: the leaf this session opened, else the next hours leaf; nil when the session
    /// can't count or no hours leaf is left.
    public let centreLeaf: String?
    /// The leaf dot's minute: the next leaf's while it is in reach, the opened leaf's once it opened; nil hides it.
    public let leafMinute: Int?
    /// The centre leaf's fill within its rung (`DialFill(before:session:opened:)`): what was saved before this
    /// session, and this session's share on top of it.
    public let fillBefore: Double
    public let fillSession: Double
    public let leafOpened: Bool
    /// "Field maple · 17m to go", or "Field maple is yours · it opens after this session"; nil when the session
    /// can't count.
    public let leafLine: Line?
    /// "You can lock your phone. Maple keeps time." in the member's first session only.
    public let firstSessionLine: String?
    /// "Take a break" while the preset's one break is unused and time is left.
    public let breakTitle: String?
    public let endPath: SessionEndPath
    /// The dial for VoiceOver (§4.9): "32 minutes left of 50. Field maple at minute 35.", the length a plain minute
    /// count ("of 90"). The time alone once the leaf has opened, for a plain timer, or with no dot.
    public let spoken: String
    /// Announced once when the leaf opens (a milestone, §4.9): "Field maple is yours. It opens after this session."
    public let leafAnnouncement: String?

    /// - Parameters:
    ///   - leaf: The next hours leaf (`Leaf(next:)`); nil when there is none.
    ///   - opened: Hours leaves this session opened (`opened(_:session:...)`), oldest first.
    ///   - countedSeconds: This session's counted seconds (`FocusSessionStore.credit(for:)?.seconds`).
    ///   - displaySeconds: Counted plus provisional (`FocusSessionStore.countedSoFar(_:)`).
    ///   - roomLeftToday: Seconds of today's 6 hours still free, display credit included.
    public init(
        session: SessionRecord, now: Date, intention: String?, leaf: Leaf?, opened: [Opened], countedSeconds: Int,
        displaySeconds: Int, roomLeftToday: Int, isFirstSession: Bool, locale: Locale
    ) {
        let plan = session.plan
        title = FocusCopy.sessionTitle(presetName: plan.presetName, intention: intention)
        let isPlain = plan.kind == .plainTimer || session.lostAt != nil
        restingLine = SelectionText.restingLine(plan.selection, isPlainTimer: isPlain)
        let left = session.secondsLeft(at: now)
        secondsLeft = left
        remaining = FocusTimeText.remaining(left)
        let length = FocusTimeText.length(minutes: plan.plannedMinutes)
        caption = "left of \(length)"
        timeLine = "\(remaining) left of \(length)"
        firstSessionLine = isFirstSession ? FocusCopy.firstSessionLine : nil
        breakTitle = plan.breakSeconds > 0 && !session.breakUsed && left > 0 ? Self.takeBreakTitle : nil
        endPath = SessionEndPath(plan.strictness)

        let canCount = plan.canCount && !isPlain
        let counted = max(0, countedSeconds)
        let provisional = max(0, displaySeconds - counted)
        var minute: Int?
        var before = 0.0
        var share = 0.0
        var centre: String?
        var line: Line?
        var dotSentence: String?
        var announcement: String?
        if let first = opened.first {
            centre = first.speciesID
            minute = first.minute
            before = 1
            let text = opened.count == 1
                ? SessionForecast.openedLine(leaf: first.name, heldUntilMorning: first.heldUntilMorning)
                : SessionForecast.openedLine(count: opened.count)
            line = Line(lead: text)
            // The line's words in §4.9's sentences: "Field maple is yours. It opens after this session."
            announcement = text.components(separatedBy: " · ")
                .map { String($0.prefix(1)).uppercased() + String($0.dropFirst()) }
                .joined(separator: ". ") + "."
        } else if let leaf, canCount {
            centre = leaf.speciesID
            before = Self.rungFraction(leaf.current - Double(counted) / 3600, leaf)
            share = Self.rungFraction(leaf.current + Double(provisional) / 3600, leaf) - before
            // Provisional time that covers the rest waits for a checkpoint: never "0m to go" for a leaf not yet open.
            let toGo = max(1, Int(((leaf.threshold - leaf.current) * 3600).rounded()) - provisional)
            // The display credit counts whole seconds, so the forecast reads from the same whole second: a sample
            // between two seconds never pushes the dot a minute on.
            let elapsed = max(0, now.timeIntervalSince(session.countdownStart)).rounded(.down)
            minute = SessionForecast(
                start: session.countdownStart, plannedSeconds: plan.plannedSeconds, window: plan.window,
                now: session.countdownStart.addingTimeInterval(elapsed),
                canCount: true, secondsToLeaf: toGo, leafName: leaf.name, roomLeftToday: roomLeftToday, firstEver: false
            ).leafMinute
            let full = SessionForecast.leafLine(leaf: leaf.name, secondsToGo: toGo)
            line = Line(lead: leaf.name, trail: String(full.dropFirst(leaf.name.count + 1)))
            if let minute { dotSentence = "\(leaf.name) at minute \(minute)." }
        }
        centreLeaf = centre
        leafMinute = minute
        fillBefore = before
        fillSession = max(0, share)
        leafOpened = !opened.isEmpty
        leafLine = line
        leafAnnouncement = announcement

        // §4.9: the length is a plain minute count ("of 90"); the leaf sentence only while the dot is ahead.
        spoken = "\(FocusTimeText.spokenRemaining(left, locale: locale)) of \(plan.plannedMinutes)." + (dotSentence.map { " \($0)" } ?? "")
    }

    /// The hours leaves among `unlocks` (`FocusSessionStore.sessionUnlocks`), each at the session minute it opened
    /// (rounded up, within the planned length), oldest first. `held` says whether a leaf is held until morning
    /// (`RevealSchedule.isHeld`).
    public static func opened(
        _ unlocks: [LeafUnlock], session: SessionRecord, held: (LeafUnlock) -> Bool, catalog: RewardCatalog = .shared,
        leaves: LeafCatalog = .shared
    ) -> [Opened] {
        unlocks
            .filter { catalog.reward(forSpecies: $0.speciesID)?.categoryID == .hoursSaved }
            .sorted { $0.date < $1.date }
            .map { unlock in
                let seconds = unlock.date.timeIntervalSince(session.countdownStart)
                let minute = min(session.plan.plannedMinutes, max(1, Int((seconds / 60 - 1e-9).rounded(.up))))
                return Opened(speciesID: unlock.speciesID, name: leaves.species(id: unlock.speciesID)?.displayName ?? unlock.speciesID,
                              minute: minute, heldUntilMorning: held(unlock))
            }
    }

    /// Whether `session` is the member's first: no other session in the replay, and the focus book holds nothing
    /// from before the session's Maple day. (`AppSettings.hasStartedFocus` is already true by now: the start sets
    /// it.)
    public static func isFirstSession(_ session: SessionRecord, among sessions: [SessionRecord], book: FocusBook) -> Bool {
        guard sessions.allSatisfy({ $0.id == session.id || $0.isHidden }) else { return false }
        return book.baseline == .zero && book.days.allSatisfy { $0.day >= session.plan.day }
    }

    /// `hours` within the leaf's rung, 0...1, as `LeafProgress.rungFraction` reads it.
    static func rungFraction(_ hours: Double, _ leaf: Leaf) -> Double {
        let span = leaf.threshold - leaf.floor
        guard span > 0 else { return hours >= leaf.threshold ? 1 : 0 }
        return min(1, max(0, (hours - leaf.floor) / span))
    }
}

/// The break screen at one moment (F1 design §5.5): the session's one locked break, inside its planned length.
public struct BreakScreenModel: Sendable, Equatable {
    /// Announced when the break runs out while the screen is open (a milestone, §4.9): "Back to studying."
    public static let endedAnnouncement = "\(FocusCopy.BreakTime.backToStudying)."

    /// "Study · Chemistry ch. 4" under the header ("Break · apps stay locked", `FocusCopy.BreakTime.header`).
    public let subtitle: String
    public let secondsLeft: TimeInterval
    /// The break's real length, cut short at the planned end: one rest mark per 10 seconds of it
    /// (`BreakDialLayout(breakSeconds:)`).
    public let breakSeconds: Int
    /// "4m"; "0:45" in the last minute.
    public let remaining: String
    /// "4m left of your break" under the dial at accessibility sizes.
    public let timeLine: String
    /// One thing to do away from the phone, rotating through the break.
    public let suggestion: String
    /// "The break counts. Back to studying at 14:28."
    public let backLine: String
    /// "4 minutes of break left. Back to studying at 14:28."
    public let spoken: String
    public let endPath: SessionEndPath

    /// Nil when no break is running at `now`.
    public init?(session: SessionRecord, now: Date, intention: String?, locale: Locale, calendar: Calendar) {
        guard let left = session.breakSecondsLeft(at: now), let current = session.breaks.last,
              let backAt = session.breakEnd(at: now) else { return nil }
        subtitle = FocusCopy.sessionTitle(presetName: session.plan.presetName, intention: intention)
        secondsLeft = left
        breakSeconds = max(1, Int(backAt.timeIntervalSince(current.start).rounded()))
        remaining = FocusTimeText.remaining(left)
        timeLine = "\(remaining) \(FocusCopy.BreakTime.caption)"
        suggestion = FocusCopy.BreakTime.suggestion(secondsIntoBreak: now.timeIntervalSince(current.start))
        backLine = FocusCopy.BreakTime.line(backAt: backAt, locale: locale, calendar: calendar)
        spoken = FocusCopy.BreakTime.dialLabel(secondsLeft: left, backAt: backAt, locale: locale, calendar: calendar)
        endPath = SessionEndPath(session.plan.strictness)
    }

    /// The break ran out on its own (not "Back to studying") in the last 2 seconds, before the planned end: the
    /// session screen comes back with a soft haptic only when the member is there to feel it. A break that ran out
    /// while Maple was away returns to the session quietly.
    public static func ranOutJustNow(_ session: SessionRecord, at now: Date) -> Bool {
        guard let last = session.breaks.last, last.end == nil else { return false }
        let until = min(last.plannedEnd, session.plannedEnd)
        return until < session.plannedEnd && now >= until && now.timeIntervalSince(until) < 2
    }
}
