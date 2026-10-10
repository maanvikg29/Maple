import CoreGraphics
import Foundation

/// Home's vertical rhythm as numbers (spec §3.1), so the layout can be reasoned about and tested.
///
/// The wireframe is an iPhone 17 (402 × 874): a 44pt header from y 62, the tree stage from y 106 to 516, then
/// numeral, caption, next-leaf row and the primary capsule. The maple scene is drawn in its own 402 × 560
/// reference frame, scaled so that its stage band (y 106–516) fills the stage.
///
/// | Item | Height | Gap after |
/// |---|---|---|
/// | Header | 44 | — |
/// | Stage | 410 | 8 |
/// | Numeral | 72 | 4 |
/// | Caption | 20 | 16 |
/// | Next-leaf row | 56 | 12 |
/// | Primary capsule | 52 | — |
///
/// At large text sizes the stage yields height (`HeroFit`, down to `minimumFittedStageHeight`) so the numeral,
/// caption, next-leaf row and the primary capsule all stay above the floating tab bar on the first screen; when
/// even that leaves no room, the capsule is pinned just above the tab bar.
nonisolated public enum HomeLayout {
    /// The stage on the reference iPhone 17.
    public static let referenceStageHeight: CGFloat = 410
    /// The preferred stage never gets shorter than this (at accessibility text sizes it starts here); only
    /// `HeroFit` takes it lower, to keep the first screen above the tab bar.
    public static let minimumStageHeight: CGFloat = 320
    /// The smallest stage `HeroFit` may leave, at the largest text sizes.
    public static let minimumFittedStageHeight: CGFloat = 150
    /// The stage's share of the screen height.
    public static let stageShare: CGFloat = 0.47

    /// The maple scene's reference frame.
    public static let sceneSize = CGSize(width: 402, height: 560)
    /// Where the stage band starts in the scene: everything above it sits behind the header and status bar.
    public static let sceneStageTop: CGFloat = 106
    /// Where the tree caption's line sits in the scene: on the dark ground, just under the crest (y 484–504).
    public static let sceneCaptionCentre: CGFloat = 494

    public static let headerHeight: CGFloat = 44
    /// Stage → numeral.
    public static let numeralGap: CGFloat = 8
    /// Numeral → caption.
    public static let captionGap: CGFloat = 4
    /// Caption → next-leaf row.
    public static let rowGap: CGFloat = 16
    /// Next-leaf row → primary capsule.
    public static let actionGap: CGFloat = 12
    /// The capsule (or the row) → below the fold.
    public static let belowTheFoldGap: CGFloat = 40
    /// Room under the last element when nothing is below the fold, so it clears the tab bar comfortably.
    public static let closingPadding: CGFloat = 24
    /// Room under below-the-fold content.
    public static let belowTheFoldPadding: CGFloat = 120

    /// The preferred stage height = min(410, max(320, screen height × 0.47)); 320 at accessibility text sizes.
    /// `HeroFit` then shrinks it when the first screen needs the room.
    public static func stageHeight(screenHeight: CGFloat, accessibilitySize: Bool) -> CGFloat {
        guard !accessibilitySize else { return minimumStageHeight }
        return min(referenceStageHeight, max(minimumStageHeight, (screenHeight * stageShare).rounded(.down)))
    }

    /// Home's first screen at any text size: the stage's height and whether the primary capsule is pinned above
    /// the tab bar (see `HeroFit`).
    /// - Parameters:
    ///   - stageHeight: The preferred height, `stageHeight(screenHeight:accessibilitySize:)`.
    ///   - visibleHeight: From under the header to the top of the tab bar.
    ///   - belowStage: The numeral, caption and next-leaf row with their gaps; nil until measured.
    ///   - action: The capsule's height, nil until measured; ignored without one.
    ///   - hasAction: Home shows a primary (or night's secondary) capsule.
    ///   - hasRow: The next-leaf row is shown (without it the capsule sits `rowGap` under the caption).
    public static func firstScreen(
        stageHeight: CGFloat, visibleHeight: CGFloat, belowStage: CGFloat?, action: CGFloat?, hasAction: Bool,
        hasRow: Bool = true
    ) -> HeroFit {
        let actionNeed = hasAction ? (hasRow ? actionGap : rowGap) + (action ?? HeroFit.estimatedActionHeight) : 0
        return HeroFit(preferred: stageHeight, minimum: minimumFittedStageHeight, visible: visibleHeight,
                       content: belowStage, action: actionNeed)
    }

    /// The scene's scale: the stage band fills the stage, but the scene is never wider than the screen, and the
    /// caption's text (`captionTextHeight` tall, centred on the ground) always ends inside the stage, so a stage
    /// that yields at large text sizes draws a smaller tree rather than a caption over the numeral.
    public static func sceneScale(stageHeight: CGFloat, width: CGFloat, captionTextHeight: CGFloat = 0) -> CGFloat {
        let byCaption = captionTextHeight > 0
            ? (stageHeight - captionTextHeight / 2) / (sceneCaptionCentre - sceneStageTop)
            : .infinity
        return max(0.01, min(stageHeight / referenceStageHeight, width / sceneSize.width, byCaption))
    }

    /// Where the scene's top sits relative to the stage's top (negative: it starts above, behind the header).
    public static func sceneOffset(scale: CGFloat) -> CGFloat {
        -sceneStageTop * scale
    }

    /// The caption's centre, measured from the stage's top.
    public static func captionCentre(scale: CGFloat) -> CGFloat {
        (sceneCaptionCentre - sceneStageTop) * scale
    }

    /// The sky's parallax (spec §3.7). The sky scrolls with the content but is held back by 60% of the scroll, so
    /// it drifts up at 40% of the speed of the tree and the text in front of it. Returns how far to push it back
    /// down; 0 under Reduce Motion (no parallax: the sky stays registered with the tree).
    public static func skyCounterOffset(scrollOffset: CGFloat, reduceMotion: Bool) -> CGFloat {
        reduceMotion ? 0 : 0.6 * max(0, scrollOffset)
    }

    /// The waiting bud's 44pt target.
    public static let budTapRadius: CGFloat = 22

    /// Whether a tap at `location` (in the scene view's coordinates, the scene drawn at `scale`) opens the Tree
    /// view: it must land on the stage band (not the sky behind the header, nor the ground under the numeral) and
    /// not on the waiting bud, whose own button opens the reveal.
    public static func tapOpensTree(at location: CGPoint, scale: CGFloat, waitingBud: CGPoint?) -> Bool {
        let band = sceneStageTop * scale...(sceneStageTop + referenceStageHeight) * scale
        guard band.contains(location.y) else { return false }
        if let bud = waitingBud, hypot(location.x - bud.x, location.y - bud.y) <= budTapRadius {
            return false
        }
        return true
    }
}

extension HomeLayout {
    /// Where the scene draws the tappable waiting bud, in the scene view's own coordinates (a view of `size`), or
    /// nil when no leaf is waiting.
    @MainActor
    public static func waitingBudPoint(model: TreeSceneModel, sceneSize size: CGSize) -> CGPoint? {
        MapleTreeScene.waitingBudPoint(TreeScenePlan.cached(for: model, theme: .maple), frame: TreeSceneFrame(size: size))
    }
}
