import Foundation
import MapleFocusCore

/// The Needs Screen Time screen as values (F1 design §5.3, F1-17): which card shows and whether it has a primary,
/// the dial's centre, and the plain timer's link. Nil while blocking is allowed, when the Focus tab shows the start
/// screen instead.
///
/// ```swift
/// if let model = NeedsScreenTimeModel(probe: sessions.probe, capability: sessions.blocking.capability, preset: preset) {
///     model.card.title      // "Lock apps with Screen Time"
///     model.card.primary    // "Turn on Screen Time", or nil where Maple can't ask
/// }
/// ```
public struct NeedsScreenTimeModel: Sendable, Equatable {
    public let state: NeedsScreenTimeState
    /// The card: its title, its line, and "Turn on Screen Time" only where Maple can ask (`FocusCopy.card`).
    public let card: FocusCopy.ScreenTimeCard
    /// The next leaf sits in the dial's centre while turning Screen Time on would let it count. A build that can't
    /// block shows none, because nothing it times can count.
    public let showsLeaf: Bool
    /// The dial's numeral: the selected preset's length, "50m".
    public let lengthText: String
    /// Under the numeral: the preset's name.
    public let caption: String
    /// "Use a plain timer · it won't count", under every card.
    public let plainTimerLink: String

    /// - Parameter preset: The preset the start screen would show (`FocusStartLines.preset(…)`).
    public init?(probe: BlockingProbe, capability: BlockingCapability, preset: FocusPreset) {
        guard let state = NeedsScreenTimeState(probe: probe, capability: capability) else { return nil }
        self.state = state
        card = FocusCopy.card(state)
        showsLeaf = state != .freeBuild
        lengthText = FocusTimeText.length(minutes: preset.minutes)
        caption = preset.name
        plainTimerLink = FocusCopy.plainTimerLink
    }
}
