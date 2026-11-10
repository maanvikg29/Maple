import Foundation

/// The dial's and the holds' own words (F1 design §4.9, F1-22).
extension FocusCopy {
    /// The start dial's VoiceOver label: it reads "Session length, 50 minutes".
    public static let dialLengthLabel = "Session length"
    /// A hold's named accessibility action: it starts a visible countdown as long as the hold.
    public static let holdCountdownAction = "Start countdown"
    /// The same action while the countdown runs.
    public static let holdCancelAction = "Cancel countdown"

    /// The hold button's label while its countdown runs: "Cancel · 8s".
    public static func holdCountdownTitle(secondsLeft: Int) -> String {
        "Cancel · \(max(1, secondsLeft))s"
    }
}
