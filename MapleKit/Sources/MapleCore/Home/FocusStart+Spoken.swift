import Foundation

extension FocusStart {
    /// VoiceOver's name for Home's Start (F1 design §4.9): "Hold to start, Locked 50 minutes" when it is a hold (the
    /// hold's own name, `FocusCopy.holdToStartName`), "Start study, 50 minutes" when it is a tap.
    public func spokenTitle(locale: Locale) -> String {
        if needsHold { return FocusCopy.holdToStartName(minutes: minutes, locale: locale) }
        return "\(verb.startTitle), \(FocusTimeText.spokenLength(minutes: minutes, locale: locale))"
    }
}

extension NowState.Action {
    /// VoiceOver's name for Home's capsule: Start by its spoken name ("Start study, 50 minutes"), so a length is never
    /// read as "50m"; every other action by its label, which has no unit.
    public func spokenTitle(locale: Locale) -> String {
        if case .startFocus(let start) = self { return start.spokenTitle(locale: locale) }
        return title
    }
}
