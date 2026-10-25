import Foundation
import MapleFocusCore

/// The Focus start screen's own words and choices beyond `StartScreenModel` (F1 design §5.1, §5.2, §5.17, P4):
/// which preset it opens on, what the capsule and the lines say for a plain timer or after a lock that failed, the
/// Locked hold's hint, the chips' words, the minimised session's dial, and the Blocking line's two tones. Pure, so
/// every rule is tested; the view only lays it out.
///
/// ```swift
/// let lines = FocusStartLines(model: model, mode: .blocking, showsHoldHint: hintIsShowing, notice: notice)
/// lines.capsuleTitle   // "Start study · 50m"
/// lines.detailLine     // "You'll reach Field maple at minute 35"
/// ```
public struct FocusStartLines: Sendable, Equatable {
    /// How the next start runs.
    public enum Mode: Sendable, Hashable {
        /// An ordinary start: the block is applied and read back first.
        case blocking
        /// "Use a plain timer · it won't count" (§5.3): nothing is locked, and nothing counts.
        case plainTimer
        /// The block couldn't be applied (§5.1): the capsule offers a plain timer instead.
        case lockFailed
    }

    /// The Blocking line in two tones (§5.1, §5.2): `main` in `textPrimary`, then `separator`, Locked's `lock.fill`
    /// and `trailing` in `textSecondary`. "Blocking 6 apps" · " · " · "Steady ›".
    public struct BlockingParts: Sendable, Equatable {
        /// What is blocked, or the prompt: "Blocking 6 apps", "Choose apps to block".
        public let main: String
        /// " · " before the strictness; nil when a prompt or a warning takes the line.
        public let separator: String?
        /// Locked draws `lock.fill` after the separator.
        public let showsLock: Bool
        /// "Steady ›", " Locked ›" (after the lock), or " ›".
        public let trailing: String
    }

    /// The screen's title.
    public static let title = "Focus"
    /// The ledger couldn't record the start, so nothing started and the block was lifted.
    public static let couldntStart = "Couldn't start the session. Try again in a moment."
    /// Locked's capsule after a lock that failed: still a hold, as every Locked start is (§5.2).
    public static let holdToStartPlainTimer = "Hold to start as a plain timer"
    /// The new-preset chip at default sizes; it reads `FocusCopy.newPreset` aloud and at accessibility sizes.
    public static let addChip = "+"

    /// What the primary capsule does.
    public let primary: StartScreenModel.Primary
    public let capsuleTitle: String
    /// The hold's VoiceOver name and named action, when the primary is a hold (§4.9, F1-22).
    public let holdName: String?
    /// "Plain timer · apps aren't locked" in place of the Blocking line; nil keeps the Blocking line.
    public let plainLine: String?
    /// The one line under the Blocking line: the plain-tap hint, a notice, the failed lock's prompt, or the counts
    /// line, in that order; nil hides it.
    public let detailLine: String?
    /// The detail line is a counts line naming the next leaf ("You'll reach…", "Counts toward…"), so it carries the
    /// leaf dot's season-tint mark.
    public let marksLeaf: Bool
    /// The dial's leaf dot; nil hides it.
    public let leafMinute: Int?
    /// The dial's centre shows the next leaf (a plain timer can't count toward it).
    public let showsLeaf: Bool
    /// The start runs as a plain timer: no app set, `StartRequest.plainTimer`.
    public let startsPlainTimer: Bool

    /// - Parameters:
    ///   - mode: Ignored while a session runs minimised (`StartScreenModel.Stage.running`).
    ///   - showsHoldHint: A plain tap on the hold showed the hint, which stays for `FocusCopy.holdHintSeconds`.
    ///   - notice: A line about the last start (`couldntStart`), until the next start or chip.
    public init(model: StartScreenModel, mode: Mode, showsHoldHint: Bool = false, notice: String? = nil, locale: Locale = .current) {
        // A minimised session's screen is the model's own: "Return to session", with nothing under the dial.
        let effective: Mode = model.stage == .running ? .blocking : mode
        let locked = model.strictness == .locked
        let primary: StartScreenModel.Primary
        let capsuleTitle: String
        switch effective {
        case .blocking:
            primary = model.primary
            capsuleTitle = model.capsuleTitle
        case .plainTimer:
            // A plain timer needs no apps, so it never asks for them; Locked still needs a hold.
            primary = model.primary == .locking ? .locking : locked ? .holdToStart : .start
            capsuleTitle = locked
                ? FocusCopy.holdToStart(minutes: model.minutes) : "\(model.preset.verb.startTitle) · \(model.lengthText)"
        case .lockFailed:
            primary = model.primary == .locking ? .locking : locked ? .holdToStart : .start
            capsuleTitle = locked ? Self.holdToStartPlainTimer : FocusCopy.startPlainTimer
        }
        self.primary = primary
        self.capsuleTitle = capsuleTitle
        if primary == .holdToStart {
            let length = FocusTimeText.spokenLength(minutes: model.minutes, locale: locale)
            holdName = effective == .lockFailed
                ? "\(Self.holdToStartPlainTimer), Locked \(length)" : FocusCopy.holdToStartName(minutes: model.minutes, locale: locale)
        } else {
            holdName = nil
        }
        plainLine = effective == .plainTimer ? SelectionText.restingLine(nil, isPlainTimer: true) : nil

        var detail: String?
        var isCounts = false
        if model.stage != .running {
            if showsHoldHint, primary == .holdToStart {
                detail = FocusCopy.holdHint
            } else if let notice {
                detail = notice
            } else if effective == .lockFailed {
                detail = FocusCopy.couldntLock
            } else if effective == .blocking {
                detail = model.countsLine
                isCounts = true
            }
        }
        detailLine = detail
        marksLeaf = isCounts && detail != nil && Self.namesLeaf(model.forecast.countsLine)
        leafMinute = effective == .blocking ? model.leafMinute : nil
        showsLeaf = effective != .plainTimer
        startsPlainTimer = effective != .blocking
    }

    // MARK: The screen's other words

    /// The preset the start screen shows: the chip picked (or asked for by Home's Start), then Quick for the first
    /// session ever (P4), then the last used, then the first. A picked preset that no longer exists falls back.
    public static func preset(selected: UUID?, presets: [FocusPreset], lastUsedID: UUID?, isFirstSession: Bool) -> FocusPreset? {
        if let selected, let preset = presets.first(where: { $0.id == selected }) { return preset }
        if isFirstSession, let quick = presets.first(where: { $0.verb == .quick }) { return quick }
        return lastUsedID.flatMap { id in presets.first { $0.id == id } } ?? presets.first
    }

    /// A chip's VoiceOver label: "Study, 50 minutes" (the chip shows the name only).
    public static func chipLabel(_ preset: FocusPreset, locale: Locale) -> String {
        "\(preset.name), \(FocusTimeText.spokenLength(minutes: preset.minutes, locale: locale))"
    }

    /// "+", or "New preset" at accessibility sizes (§5.17).
    public static func addChipTitle(isAccessibilitySize: Bool) -> String {
        isAccessibilitySize ? FocusCopy.newPreset : addChip
    }

    /// Under a minimised session's numeral: "left of 50m" (§5.4).
    public static func minimisedCaption(plannedMinutes: Int) -> String {
        "left of \(FocusTimeText.length(minutes: plannedMinutes))"
    }

    /// A minimised session's dial for VoiceOver: "32 minutes left of 50." (§4.9; the leaf dot is hidden there).
    public static func minimisedDialLabel(secondsLeft: TimeInterval, plannedMinutes: Int, locale: Locale) -> String {
        "\(FocusTimeText.spokenRemaining(secondsLeft, locale: locale)) of \(plannedMinutes)."
    }

    /// The Blocking line split for its two tones and Locked's lock.
    public static func blockingParts(_ line: SelectionText.BlockingLine) -> BlockingParts {
        guard let name = line.strictnessName else {
            return BlockingParts(main: line.text, separator: nil, showsLock: false, trailing: " ›")
        }
        return BlockingParts(main: line.text, separator: " · ", showsLock: line.showsLock,
                             trailing: line.showsLock ? " \(name) ›" : "\(name) ›")
    }

    private static func namesLeaf(_ line: SessionForecast.CountsLine) -> Bool {
        switch line {
        case .reaches, .toward: true
        default: false
        }
    }
}
