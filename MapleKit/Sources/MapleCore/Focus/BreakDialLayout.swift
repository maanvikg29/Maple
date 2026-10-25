import Foundation

/// The break dial (F1 design §5.5): one rest mark per 10 seconds of the break, going out one by one, clockwise from 12
/// o'clock, as the break runs down.
public struct BreakDialLayout: Sendable, Equatable {
    public static let secondsPerMark = 10

    /// The break's real length: its planned 5 minutes, or less when it was cut short at the session's planned end.
    public let breakSeconds: Int
    public let markCount: Int

    public init(breakSeconds: Int) {
        self.breakSeconds = max(1, breakSeconds)
        markCount = (self.breakSeconds + Self.secondsPerMark - 1) / Self.secondsPerMark
    }

    /// Mark `index` of `markCount` sits at index / markCount of a full turn, clockwise from 12 o'clock.
    public func angle(ofMark index: Int) -> Double {
        2 * .pi * Double(index) / Double(markCount)
    }

    /// With `left` seconds of break to go: one `.rest` mark per 10 seconds still left (rounded up), ending the turn; the
    /// marks before them have gone out (`.off`).
    public func marks(left: TimeInterval) -> [MarkState] {
        let remaining = min(markCount, max(0, Int((max(0, left) / Double(Self.secondsPerMark) - 1e-9).rounded(.up))))
        let gone = markCount - remaining
        return (0..<markCount).map { $0 < gone ? .off : .rest }
    }
}
