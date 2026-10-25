import Foundation

/// How one mark of the minute-marks dial is drawn (F1 design §4.2). MapleDesign's `Theme.Dial` holds each state's
/// colour and its Increase Contrast value; this type holds no colour, so it stays pure and nonisolated.
public enum MarkState: String, Sendable, Hashable, CaseIterable {
    /// The start screen's preview of the length: `textPrimary` 42%.
    case plan
    /// Time still to come in a running session: 16%.
    case ahead
    /// Passed minutes, and on the receipt the minutes that counted: 88%.
    case lit
    /// The minute in progress: season tint, brightening from 55% to 100% through its minute.
    case current
    /// Break time still left: `#C9D3E3` at 78%.
    case rest
    /// Minutes that didn't count (the receipt): 9%, drawn shorter.
    case gap
    /// Press-and-hold progress: 100%.
    case hold
    /// Needs Screen Time, and a break's marks once they have gone out: 10%.
    case off

    /// Gap marks are drawn shorter: from radius 86 to 92 of the 200-unit box, not from 80 or 84 (§4.1).
    public var isShort: Bool { self == .gap }
}
