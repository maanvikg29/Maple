import Foundation
import MapleFocusCore

/// The Herbarium's mini bar while a session runs (F1 design §5.10): the preset and its calm time left, or the break
/// and when it ends. The preset name only, as on the Lock Screen: the intention stays on the session's own screen.
public struct SessionMiniBar: Sendable, Equatable {
    /// "Study · 32m left", "Study · 0:45 left", or "Break · back at 14:28".
    public let title: String
    /// "Study, 32 minutes left. Return to session."
    public let spoken: String

    /// Nil once the planned end has passed: the bar hides in the moment before the refresh that ends the session, rather
    /// than reading "Study · 0:00 left".
    /// - Parameter now: The session store's trusted time (`FocusSessionStore.now`), so the bar agrees with the dial.
    public init?(session: SessionRecord, now: Date, calendar: Calendar, locale: Locale) {
        guard session.secondsLeft(at: now) > 0 else { return nil }
        if let breakEnd = session.breakEnd(at: now) {
            let back = HomeFormat.clock(HomeFormat.clockTime(of: breakEnd, calendar: calendar), locale: locale)
            title = "Break · back at \(back)"
            spoken = "Break, back at \(back). \(Self.returnLine)"
        } else {
            let left = session.plannedEnd.timeIntervalSince(now)
            let name = session.plan.presetName
            title = "\(name) · \(FocusTimeText.remaining(left)) left"
            spoken = "\(name), \(FocusTimeText.spokenRemaining(left, locale: locale)). \(Self.returnLine)"
        }
    }

    /// What a tap does, for VoiceOver: "Return to session.".
    static var returnLine: String { FocusCopy.returnToSession + "." }
}
