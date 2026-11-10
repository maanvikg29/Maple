import ActivityKit
import Foundation

/// The running session's Live Activity, shared by the app and the MapleWidgets extension (F1 design §5.11, §7.7).
///
/// Display only: no buttons and no push. Everything the widget draws arrives here, already worded, because the
/// extension links only this module: the copy is `FocusActivityState.lines(locale:calendar:)` in MapleCore, the leaf
/// is a `LeafSketch` of the next hours leaf, and the tint is the season's, never gold.
public struct FocusActivityAttributes: ActivityAttributes, Sendable {
    /// What changes while the session runs: its times and its lines.
    public struct ContentState: Codable, Hashable, Sendable {
        /// The countdown's start, for the ring's progress and the system timer text.
        public var start: Date
        /// The planned end, which never moves (F1-11). It is also the activity's stale date.
        public var end: Date
        /// "Study", or "Plain timer".
        public var title: String
        /// Under the timer on the Lock Screen: "until 14:52 · Study", or "Study · break until 14:28" during a break,
        /// which stays true once the break has run out with nothing to update the activity.
        public var lockLine: String
        /// The expanded view's line: "Study · Chemistry ch. 4", or "Study · break until 14:28" during a break.
        public var expandedLine: String
        /// Shown once the stale date has passed: "Session complete".
        public var completeLine: String
        /// During a break, how VoiceOver reads either line: "Study, break until 14:28". Nil outside a break, and in
        /// content sent by an earlier build, which still decodes.
        public var breakSpoken: String?

        public init(
            start: Date, end: Date, title: String, lockLine: String, expandedLine: String, completeLine: String,
            breakSpoken: String? = nil
        ) {
            self.start = start
            self.end = max(start, end)
            self.title = title
            self.lockLine = lockLine
            self.expandedLine = expandedLine
            self.completeLine = completeLine
            self.breakSpoken = breakSpoken
        }
    }

    /// Text primary (`#F2F5FA`): the leaf's colour when no season tint was given.
    public static let neutralTint: UInt32 = 0xF2F5FA

    /// The session this activity shows; the app ends any activity whose session it doesn't recognise.
    public var sessionID: UUID
    /// The Lock Screen leaf's colour as 0xRRGGBB (sRGB): the season tint, never gold.
    public var tintRGB: UInt32
    /// The next hours leaf as a skeleton; nil for a plain timer, which shows no leaf.
    public var leaf: LeafSketch?

    public init(sessionID: UUID, tintRGB: UInt32 = FocusActivityAttributes.neutralTint, leaf: LeafSketch? = nil) {
        self.sessionID = sessionID
        self.tintRGB = tintRGB & 0xFF_FFFF
        self.leaf = leaf
    }

    /// The tint's sRGB components, 0...1, for `Color(red:green:blue:)`.
    public var tint: (red: Double, green: Double, blue: Double) {
        (Double(tintRGB >> 16 & 0xFF) / 255, Double(tintRGB >> 8 & 0xFF) / 255, Double(tintRGB & 0xFF) / 255)
    }
}
