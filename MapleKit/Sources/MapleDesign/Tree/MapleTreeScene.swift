import MapleCore
import SwiftUI

/// The maple: Home's hero (spec §4). Sky, canopy bloom, ground, the tree with every earned species as rosettes of
/// its own leaf in the current season, the next leaves as buds, the waiting amber bud and one seasonal particle
/// system, all from one `TreeSceneModel`.
///
/// ```swift
/// MapleTreeScene(
///     model: model,
///     accessibilityLabel: Text("Your maple. Young maple, 23 of 155 leaves, grown over 41 days."),
///     accessibilityValue: Text("Newest: Red maple. Next leaf: Paperbark maple, 9 of 14 on-time bedtimes."),
///     onOpenWaitingLeaf: { reveal.open() }
/// )
/// .frame(height: 560)                       // the iPhone 17 scene is 402 × 560; any size scales to fit
/// .accessibilityAddTraits(.isButton)
/// .accessibilityHint("Opens your maple full screen.")
/// ```
///
/// The scene lays out in a 402 × 560 reference frame scaled to fit its size, with the trunk base at (201, 470).
/// It is one accessibility element (spec §4.11): the caller supplies its label and value (and any hint, traits and
/// further actions); "Open new leaf" is added automatically while a leaf is waiting.
///
/// Motion is sleepy and cheap. Layout and drawing happen once per data change, into pre-rasterised layers (sky,
/// bloom, ground, twigs, trunk and limbs, rosettes, flutter sprites); each frame only composes those images with a
/// layered sway about the trunk base and draws the twinkling stars, waiting bud and particles. The timeline pauses
/// off screen, when the app is inactive, in Low Power Mode, under a full-screen cover (`\.treeScenesPaused`) and
/// after a minute at night without interaction. Under Reduce Motion, or
/// with `model.time` set, the scene is one complete still frame; data changes crossfade (0.6 s under Reduce Motion,
/// otherwise the 1.6 s graft), and phase changes drift over 3.2 s.
public struct MapleTreeScene: View {
    private let model: TreeSceneModel
    private let includesBackdrop: Bool
    private let label: Text?
    private let value: Text?
    private let onOpenWaitingLeaf: (() -> Void)?

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale
    @State private var isOnScreen = true
    @Environment(\.treeScenesPaused) private var isCovered
    @State private var isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var nightFrozen = false
    /// Bumped by every tap, so each interaction restarts the night's 60 s countdown to a still frame (spec §4.9).
    @State private var wakes = 0

    /// - Parameters:
    ///   - model: Everything the scene shows.
    ///   - includesBackdrop: Draw the sky too. Pass false when a `SkyBackdrop` already sits behind the scene.
    ///   - accessibilityLabel: The tree's spoken label, e.g. "Your maple. Young maple, 23 of 155 leaves, grown
    ///     over 41 days."
    ///   - accessibilityValue: The spoken value: newest and next leaf, plus "A new leaf is waiting.",
    ///     "Grew today." and "Resting." when they apply.
    ///   - onOpenWaitingLeaf: Called when the waiting amber bud is tapped (44 pt target, which takes priority over
    ///     a tap on the tree) or its accessibility action runs: opens the reveal.
    public init(
        model: TreeSceneModel,
        includesBackdrop: Bool = true,
        accessibilityLabel: Text? = nil,
        accessibilityValue: Text? = nil,
        onOpenWaitingLeaf: (() -> Void)? = nil
    ) {
        self.model = model
        self.includesBackdrop = includesBackdrop
        label = accessibilityLabel
        value = accessibilityValue
        self.onOpenWaitingLeaf = onOpenWaitingLeaf
    }

    public var body: some View {
        let plan = TreeScenePlan.cached(for: model, theme: theme)
        GeometryReader { proxy in
            let frame = TreeSceneFrame(size: proxy.size)
            ZStack(alignment: .topLeading) {
                Group {
                    if isStill {
                        still(plan, frame: frame)
                    } else {
                        animated(plan, frame: frame)
                    }
                }
                .id(model.planKey)
                .transition(.opacity)
                waitingBudTarget(plan, frame: frame)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .animation(reduceMotion ? theme.motion.gentle : theme.motion.graft, value: model.layoutKey)
        .animation(reduceMotion ? nil : theme.motion.drift, value: LightKey(model))
        .accessibilityElement(children: .ignore)
        .modifier(SceneAccessibility(label: label, value: value, openLeaf: model.waiting.isEmpty ? nil : onOpenWaitingLeaf))
        .onScrollVisibilityChange(threshold: 0.05) { isOnScreen = $0 }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .task(id: FreezeKey(phase: model.phase, active: scenePhase == .active, wakes: wakes)) {
            // At night the tree settles to a still frame after a minute without interaction.
            nightFrozen = false
            guard model.phase == .night else { return }
            try? await Task.sleep(for: .seconds(60))
            if !Task.isCancelled {
                nightFrozen = true
            }
        }
        .simultaneousGesture(TapGesture().onEnded {
            nightFrozen = false
            wakes += 1
        })
    }

    private struct FreezeKey: Hashable {
        var phase: NowPhase
        var active: Bool
        var wakes: Int
    }

    /// The scene light: phase, season and vitality changes drift rather than cut.
    private struct LightKey: Hashable {
        var phase: NowPhase
        var season: Season
        var seasonDay: Int
        var vitality: Double

        init(_ model: TreeSceneModel) {
            phase = model.phase
            season = model.season
            seasonDay = model.seasonDay
            vitality = model.vitality
        }
    }

    private var isStill: Bool {
        model.time != nil || reduceMotion || isLowPower || !isOnScreen || scenePhase != .active || nightFrozen || isCovered
    }

    private var stillMotion: TreeSceneRenderer.Motion {
        // Reduce Motion is the rest pose; a fixed time shows that exact instant.
        if let time = model.time, !reduceMotion {
            return TreeSceneRenderer.Motion(time: time.timeIntervalSinceReferenceDate, now: time)
        }
        return .rest(now: model.time ?? Date())
    }

    private func still(_ plan: TreeScenePlan, frame: TreeSceneFrame) -> some View {
        let motion = stillMotion
        let includesBackdrop = includesBackdrop
        let background = theme.colors.background
        return Canvas { context, _ in
            TreeSceneRenderer.drawStill(plan, frame: frame, motion: motion, includesBackdrop: includesBackdrop, background: background, in: context)
        }
        .frame(width: frame.size.width, height: frame.size.height)
    }

    @ViewBuilder
    private func animated(_ plan: TreeScenePlan, frame: TreeSceneFrame) -> some View {
        let background = theme.colors.background
        if let layers = TreeRasterCache.shared.layers(
            for: plan, frame: frame, displayScale: displayScale, includesBackdrop: includesBackdrop, background: background, now: Date()
        ) {
            let twinkling = includesBackdrop ? TreeSkyPainter.twinkling(plan.sky, vitality: plan.model.vitality) : 0
            TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                let motion = TreeSceneRenderer.Motion(time: timeline.date.timeIntervalSinceReferenceDate, now: timeline.date)
                let sway = TreeSceneRenderer.sway(plan, motion: motion)
                ZStack(alignment: .topLeading) {
                    if let sky = layers.sky {
                        sky.resizable().frame(width: frame.size.width, height: frame.size.height)
                    }
                    if twinkling > 0 {
                        Canvas { context, _ in
                            TreeSkyPainter.drawStars(plan.sky, frame: frame, time: motion.time, vitality: plan.model.vitality, selection: .twinkling, in: context)
                        }
                    }
                    if let bloom = layers.bloom {
                        placed(bloom, in: layers.bloomRect)
                            .opacity(TreeSceneRenderer.breathe(motion) / TreeRasterCache.Layers.bloomPeak)
                            .blendMode(.plusLighter)
                    }
                    if let trophy = layers.trophy {
                        placed(trophy, in: layers.trophyRect)
                    }
                    placed(layers.ground, in: layers.groundRect)
                    swaying(layers.twigs, layers, angle: sway.twigs)
                    swaying(layers.trunk, layers, angle: sway.trunk)
                    swaying(layers.foliage, layers, angle: sway.leaves)
                    Canvas { context, _ in
                        TreeSceneRenderer.drawOverlay(plan, layers: layers, frame: frame, motion: motion, in: context)
                    }
                }
                .frame(width: frame.size.width, height: frame.size.height, alignment: .topLeading)
            }
        } else {
            still(plan, frame: frame)
        }
    }

    private func placed(_ image: Image, in rect: CGRect) -> some View {
        image
            .resizable()
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
    }

    private func swaying(_ image: Image, _ layers: TreeRasterCache.Layers, angle: Double) -> some View {
        image
            .resizable()
            .frame(width: layers.rect.width, height: layers.rect.height)
            .rotationEffect(.radians(angle), anchor: layers.anchor)
            .offset(x: layers.rect.minX, y: layers.rect.minY)
    }

    /// A 44 pt invisible button over the waiting bud, which takes priority over a tap on the tree.
    @ViewBuilder
    private func waitingBudTarget(_ plan: TreeScenePlan, frame: TreeSceneFrame) -> some View {
        if let onOpenWaitingLeaf, let point = Self.waitingBudPoint(plan, frame: frame) {
            Button(action: onOpenWaitingLeaf) {
                Color.clear.frame(width: 44, height: 44).contentShape(Circle())
            }
            .buttonStyle(.plain)
            .offset(x: point.x - 22, y: point.y - 22)
        }
    }

    /// Centre of the first waiting bud in the scene, if one is waiting.
    static func waitingBudPoint(_ plan: TreeScenePlan, frame: TreeSceneFrame) -> CGPoint? {
        guard !plan.model.waiting.isEmpty else { return nil }
        if plan.model.species.isEmpty {
            return TreePainter.sproutTop(frame: frame).0
        }
        guard let bud = plan.skeleton.buds.first(where: \.isWaiting) else { return nil }
        return frame.point(bud.anchor + bud.direction * 5)
    }
}

/// The single element's label and value, and "Open new leaf" while a leaf is waiting.
private struct SceneAccessibility: ViewModifier {
    let label: Text?
    let value: Text?
    let openLeaf: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .modifier(OptionalText(text: label, isValue: false))
            .modifier(OptionalText(text: value, isValue: true))
            .modifier(OpenLeafAction(action: openLeaf))
    }
}

/// Applies a label or value only when the caller gave one, so their own modifiers are never overridden.
private struct OptionalText: ViewModifier {
    let text: Text?
    let isValue: Bool

    func body(content: Content) -> some View {
        if let text {
            if isValue {
                content.accessibilityValue(text)
            } else {
                content.accessibilityLabel(text)
            }
        } else {
            content
        }
    }
}

private struct OpenLeafAction: ViewModifier {
    let action: (() -> Void)?

    func body(content: Content) -> some View {
        if let action {
            content.accessibilityAction(named: Text("Open new leaf"), action)
        } else {
            content
        }
    }
}

extension EnvironmentValues {
    /// Set while a full-screen cover (the reveal, wind-down mode, the Tree view) hides a maple scene: the scene and the
    /// Tree view's close-up hold a still frame instead of animating unseen behind it.
    @Entry public var treeScenesPaused = false
}
