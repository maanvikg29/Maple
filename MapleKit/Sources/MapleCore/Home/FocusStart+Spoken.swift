import Foundation

extension FocusStart {
    /// VoiceOver's name for Home's Start (F1 design §4.9): "Hold to start, Locked 50 minutes" when it is a hold (the
    /// hold's own name, `FocusCopy.holdToStartName`), "Start study, 50 minutes" when it is a tap.
    public func spokenTitle(locale: Locale) -> String {
        if needsHold { return FocusCopy.holdToStartName(minutes: minutes, locale: locale) }
        return "\(verb.startTitle), \(FocusTimeText.spokenLength(minutes: minutes, locale: locale))"
    }
}
