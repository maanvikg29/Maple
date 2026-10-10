import CoreGraphics

/// How a screen's hero yields height so that everything under it, and its one primary action, stay above the
/// floating tab bar on the first screen at every text size (spec §3.1, §9). Pure, so it is unit-tested.
///
/// The hero (Home's tree stage, Rest's dial) keeps its preferred height while there is room. At large text sizes
/// it gives up height, down to `minimum`, so the numeral, captions, rows and the action still fit above the tab
/// bar. When even the smallest hero leaves no room, the action is pinned just above the tab bar instead
/// (`pinsAction`) and the rest scrolls under it, so the action is always on the first screen.
///
/// ```swift
/// let fit = HeroFit(preferred: 410, minimum: HomeLayout.minimumFittedStageHeight, visible: visibleHeight,
///                   content: measured.belowStage, action: hasAction ? HomeLayout.actionGap + measured.button : 0)
/// ```
nonisolated public struct HeroFit: Sendable, Equatable {
    /// The least room left between the bottom of the action (or of the content, without one) and the tab bar.
    public static let minimumBottomGap: CGFloat = 16
    /// Assumed for an action that hasn't been measured yet: the capsule's minimum height.
    public static let estimatedActionHeight: CGFloat = 52

    /// The hero's height.
    public let heroHeight: CGFloat
    /// The action can't fit under even the smallest hero, so it is pinned above the tab bar.
    public let pinsAction: Bool

    public init(heroHeight: CGFloat, pinsAction: Bool) {
        self.heroHeight = heroHeight
        self.pinsAction = pinsAction
    }

    /// - Parameters:
    ///   - preferred: The hero's height when there is room.
    ///   - minimum: The smallest the hero may get.
    ///   - visible: The height the first screen offers the content: from under the header (or the top of the safe
    ///     area) to the top of the tab bar.
    ///   - content: Everything in the flow besides the hero and the action, gaps included; nil until it has been
    ///     measured, which keeps the preferred height.
    ///   - action: The action with the gap above it; 0 when the screen has no action.
    public init(preferred: CGFloat, minimum: CGFloat, visible: CGFloat, content: CGFloat?, action: CGFloat) {
        let floor = min(minimum, preferred)
        guard let content, visible > 0 else {
            self.init(heroHeight: preferred, pinsAction: false)
            return
        }
        let room = visible - content - max(0, action) - Self.minimumBottomGap
        if room >= floor {
            self.init(heroHeight: min(preferred, room.rounded(.down)), pinsAction: false)
        } else {
            // Nothing fits under even the smallest hero: keep it small and pin the action, if there is one.
            self.init(heroHeight: floor, pinsAction: action > 0)
        }
    }

    /// The least height a page built around this hero should fill (`.frame(minHeight:)`): the visible height while
    /// everything fits, so its flexible gaps spread it over the first screen; nil once the action is pinned, so the
    /// page keeps its natural height from the top and only real overflow scrolls under the pinned action. (Filling
    /// the visible height then would hand the action's space to the gaps and push the content under the bar.)
    public func pageMinHeight(visible: CGFloat) -> CGFloat? {
        pinsAction ? nil : visible
    }
}
