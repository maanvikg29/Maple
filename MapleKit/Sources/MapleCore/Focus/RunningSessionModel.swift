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

        /// The line as one string.
        public var text: String { trail.map { "\(lead) \($0)" } ?? lead }
    }

    /// This session's counted time as the counters hold it (`FocusSessionStore.credit(for:)`), from which the leaf
    /// dot's minute is found (§4.1): the one moment the counted time reaches the leaf's rung. So the dot doesn't creep
    /// on while provisional time waits for a checkpoint, and doesn't move when a checkpoint opens the leaf.
    public struct CountedTime: Sendable, Equatable {
        /// Seconds the hours counters held before this session's counted time.
        public var savedBefore: Int
        /// This session's counted seconds (`SessionCredit.seconds`).
        public var seconds: Int
        /// Its counted stretches, in time order.
        public var stretches: [DateInterval]
        /// Its last checkpoint (`SessionCredit.provenAt`): counting carries on from here.
        public var provenAt: Date

        public init(savedBefore: Int, seconds: Int, stretches: [DateInterval], provenAt: Date) {
            self.savedBefore = savedBefore
            self.seconds = seconds
            self.stretches = stretches
            self.provenAt = provenAt
        }

        /// The running session's credit (nil when it has none), and the counters' hours saved, which already hold its
        /// counted seconds.
        public init(_ credit: SessionCredit?, hoursSaved: Double, session: SessionRecord) {
            let seconds = credit?.seconds ?? 0
            self.init(
                savedBefore: Int((hoursSaved * 3600).rounded()) - seconds, seconds: seconds,
                stretches: credit?.stretches.filter(\.counted).map(\.interval) ?? [],
                provenAt: credit?.provenAt ?? session.lastCheckpoint ?? session.countdownStart
            )
        }

        /// When the counters reach `threshold` hours: inside the counted stretches, or on from the last checkpoint
        /// (from `windowStart` at the earliest) as if every second after it counts. Nil when they held it before this
        /// session.
        public func crossing(_ threshold: Double, windowStart: Date) -> Date? {
            var needed = threshold * 3600 - Double(savedBefore)
            guard needed > 0 else { return nil }
            for stretch in stretches {
                if needed <= stretch.duration { return stretch.start.addingTimeInterval(needed) }
                needed -= stretch.duration
            }
            return max(provenAt, windowStart).addingTimeInterval(needed)
        }
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
    /// The leaf line for VoiceOver, its time in words: "Field maple, 17 minutes to go"; the opened line as it is.
    public let leafSpoken: String?
    /// How many hours leaves this session has opened: each new one is announced (§4.9).
    public let openedCount: Int
    /// "You can lock your phone. Maple keeps time." in the member's first session only.
    public let firstSessionLine: String?
    /// "Take a break" while the preset's one break is unused, time is left, and apps are locked: a plain timer, or a
    /// session whose block was lost, has no break, since the break is locked and counted (§5.5).
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
    ///   - counted: This session's counted time (`CountedTime(_:hoursSaved:session:)`).
    ///   - displaySeconds: Counted plus provisional (`FocusSessionStore.countedSoFar(_:)`).
    ///   - roomLeftToday: Seconds of today's 6 hours still free, display credit included.
    public init(
        session: SessionRecord, now: Date, intention: String?, leaf: Leaf?, opened: [Opened], counted time: CountedTime,
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
        breakTitle = plan.breakSeconds > 0 && !session.breakUsed && left > 0 && !isPlain ? Self.takeBreakTitle : nil
        endPath = SessionEndPath(plan.strictness)

        let canCount = plan.canCount && !isPlain
        let counted = max(0, time.seconds)
        let provisional = max(0, displaySeconds - counted)
        var minute: Int?
        var before = 0.0
        var share = 0.0
        var centre: String?
        var line: Line?
        var lineSpoken: String?
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
            lineSpoken = text
            // The line's words in §4.9's sentences: "Field maple is yours. It opens after this session."
            announcement = text.components(separatedBy: " · ")
                .map { String($0.prefix(1)).uppercased() + String($0.dropFirst()) }
                .joined(separator: ". ") + "."
        } else if let leaf, canCount {
            centre = leaf.speciesID
            before = Self.rungFraction(leaf.current - Double(counted) / 3600, leaf)
            share = Self.rungFraction(leaf.current + Double(provisional) / 3600, leaf) - before
            // Provisional time that covers the rest waits for a checkpoint: the line never reads "0m to go" for a
            // leaf not yet open. Only the line is held at 1m; the dot stays where the counted time reaches the rung.
            let toGo = max(1, Int(((leaf.threshold - leaf.current) * 3600).rounded()) - provisional)
            if let crossing = time.crossing(leaf.threshold, windowStart: plan.window.start) {
                // In reach: before the planned end and bedtime, with room left today for what the checkpoint hasn't
                // proven yet.
                let rest = max(0, crossing.timeIntervalSince(max(time.provenAt, plan.window.start)))
                let room = Double(max(0, roomLeftToday) + provisional)
                if crossing <= min(session.plannedEnd, plan.window.end), rest <= room {
                    minute = Self.minute(of: crossing, in: session)
                }
            }
            let full = SessionForecast.leafLine(leaf: leaf.name, secondsToGo: toGo)
            line = Line(lead: leaf.name, trail: String(full.dropFirst(leaf.name.count + 1)))
            let minutesToGo = Int((Double(toGo) / 60 - 1e-9).rounded(.up))
            lineSpoken = "\(leaf.name), \(FocusTimeText.spokenLength(minutes: minutesToGo, locale: locale)) to go"
            if let minute { dotSentence = "\(leaf.name) at minute \(minute)." }
        }
        centreLeaf = centre
        leafMinute = minute
        fillBefore = before
        fillSession = max(0, share)
        leafOpened = !opened.isEmpty
        leafLine = line
        leafSpoken = lineSpoken
        openedCount = opened.count
        leafAnnouncement = announcement

        // §4.9: the length is a plain minute count ("of 90"); the leaf sentence only while the dot is ahead.
        spoken = "\(FocusTimeText.spokenRemaining(left, locale: locale)) of \(plan.plannedMinutes)." + (dotSentence.map { " \($0)" } ?? "")
    }

    /// The hours leaves among `unlocks` (`FocusSessionStore.sessionUnlocks`), oldest first, each at the session minute
    /// the counted time reached its rung (rounded up, within the planned length), where the dot stood before it opened:
    /// never the later checkpoint that proved it. A leaf the counters held before this session's counted time keeps
    /// the minute it was dated. `held` says whether a leaf is held until morning (`RevealSchedule.isHeld`).
    public static func opened(
        _ unlocks: [LeafUnlock], session: SessionRecord, counted: CountedTime, held: (LeafUnlock) -> Bool,
        catalog: RewardCatalog = .shared, leaves: LeafCatalog = .shared
    ) -> [Opened] {
        unlocks
            .filter { catalog.reward(forSpecies: $0.speciesID)?.categoryID == .hoursSaved }
            .sorted { $0.date < $1.date }
            .map { unlock in
                let reached = catalog.reward(forSpecies: unlock.speciesID)
                    .flatMap { counted.crossing($0.threshold, windowStart: session.plan.window.start) }
                let minute = min(session.plan.plannedMinutes, Self.minute(of: reached ?? unlock.date, in: session))
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

    /// The session minute `date` falls in, from the countdown's start: rounded up, and at least 1. Read to the
    /// millisecond, so a crossing on a whole minute stays on it.
    static func minute(of date: Date, in session: SessionRecord) -> Int {
        let seconds = (date.timeIntervalSince(session.countdownStart) * 1000).rounded() / 1000
        return max(1, Int((seconds / 60 - 1e-9).rounded(.up)))
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
