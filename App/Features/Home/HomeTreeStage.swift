import SwiftUI
import MapleCore
import MapleDesign

/// The tree stage (spec §3.2, §4.10, §4.11): the maple scene, drawn in its 402 × 560 frame so that its stage
/// band fills the stage and its sky runs up behind the header, with the caption on the ground. No container.
///
/// Tapping the tree opens the Tree view; tapping the waiting amber bud (which takes priority) opens the reveal.
/// For VoiceOver the tree is one button with custom actions.
struct HomeTreeStage: View {
    @Environment(\.theme) private var theme

    let content: HomeContent
    let width: CGFloat
    let height: CGFloat
    let scale: CGFloat
    let openTree: () -> Void
    let openWaitingLeaf: () -> Void
    let openHerbarium: () -> Void
    let showLeaf: (String) -> Void

    var body: some View {
        let sceneSize = CGSize(width: width, height: HomeLayout.sceneSize.height * scale)
        ZStack(alignment: .top) {
            scene(size: sceneSize)
                .frame(width: sceneSize.width, height: sceneSize.height)
                .offset(y: HomeLayout.sceneOffset(scale: scale))
                .frame(width: width, height: height, alignment: .top)

            TreeCaption(stage: content.stage, leaves: content.leaves, total: content.total, action: openHerbarium)
                .opacity(content.state.contentOpacity)
                .position(x: width / 2, y: HomeLayout.captionCentre(scale: scale))
        }
        .frame(width: width, height: height, alignment: .top)
    }

    private func scene(size: CGSize) -> some View {
        let bud = HomeLayout.waitingBudPoint(model: content.tree, sceneSize: size)
        let scale = scale
        return MapleTreeScene(
            model: content.tree,
            includesBackdrop: false,
            accessibilityLabel: Text(content.treeLabel),
            accessibilityValue: Text(content.treeValue),
            onOpenWaitingLeaf: content.waitingBudID == nil ? nil : openWaitingLeaf
        )
        // The scene keeps its own taps (the waiting bud's button, waking a resting tree); this one runs alongside
        // them and leaves the bud and the sky behind the header alone.
        .simultaneousGesture(SpatialTapGesture().onEnded { value in
            if HomeLayout.tapOpensTree(at: value.location, scale: scale, waitingBud: bud) {
                openTree()
            }
        })
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens your maple full screen.")
        .accessibilityAction(.default, openTree)
        .modifier(TreeActions(content: content, showLeaf: showLeaf, openHerbarium: openHerbarium))
    }
}

/// The tree's custom actions besides "Open new leaf" (which the scene adds while a leaf is waiting).
private struct TreeActions: ViewModifier {
    let content: HomeContent
    let showLeaf: (String) -> Void
    let openHerbarium: () -> Void

    func body(content view: Content) -> some View {
        view
            .accessibilityActions {
                if let newest = content.newestID {
                    Button("Show newest leaf") { showLeaf(newest) }
                }
                if let next = content.next {
                    Button("Show next leaf") { showLeaf(next.speciesID) }
                }
                Button("Open herbarium", action: openHerbarium)
            }
    }
}
