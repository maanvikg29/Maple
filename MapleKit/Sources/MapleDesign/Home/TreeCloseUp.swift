import MapleCore
import SwiftUI

/// Where everything sits in the Tree view (spec §8.4): the tree fitted to the width minus 32 inside the space the
/// top bar and the bottom capsule leave, then zoomed 1–3× about its centre and panned. Also finds what a tap hits:
/// the waiting bud first (44pt target), then the nearest rosette within 22pt.
///
/// ```swift
/// let geometry = TreeCloseUpGeometry(model: model, viewport: size, insets: EdgeInsets(top: 120, leading: 0, bottom: 110, trailing: 0))
/// switch geometry.hit(at: location, zoom: zoom, pan: pan) { … }
/// ```
nonisolated public struct TreeCloseUpGeometry: Sendable {
    /// Pinch range.
    public static let zoomRange: ClosedRange<CGFloat> = 1...3
    /// The largest fit: a seedling is shown bigger, but never more than this.
    public static let maximumFit: CGFloat = 3
    /// Rosettes and the waiting bud answer a tap this far from their centre (screen points).
    public static let hitRadius: CGFloat = 22
    /// Room under the trunk base for the ground's crest.
    static let groundRoom: CGFloat = 28

    /// What a tap landed on.
    public enum Hit: Sendable, Equatable {
        case waitingBud(speciesID: String)
        case rosette(speciesID: String)
    }

    /// A rosette as a tap and VoiceOver target.
    public struct Target: Sendable, Identifiable, Equatable {
        /// The rosette's index in the layout.
        public let id: Int
        public let speciesID: String
        /// The species' permanent rosette (one per species); the others are satellites and the featured extra.
        public let isPrimary: Bool
        /// Its centre on screen at 1×, unpanned.
        public let restPoint: CGPoint
    }

    public let viewport: CGSize
    /// Screen points per scene point at 1×.
    public let fitScale: CGFloat
    /// The trunk base on screen at 1×.
    public let restBase: CGPoint
    /// The tree's bounding box on screen at 1×; zoom is about its centre.
    public let restTreeRect: CGRect
    /// Every rosette, in the layout's order.
    public let targets: [Target]
    /// The tappable waiting bud at 1× (the first waiting leaf), if one is waiting.
    public let restWaitingBud: (speciesID: String, point: CGPoint)?
    let availableRect: CGRect

    /// - Parameters:
    ///   - viewport: The whole screen the view draws in.
    ///   - insets: What the top bar and the bottom capsule cover; the tree is fitted between them.
    @MainActor
    public init(model: TreeSceneModel, viewport: CGSize, insets: EdgeInsets) {
        self.viewport = viewport
        // The same (cached) layout the scene draws; its colours don't matter here.
        let skeleton = TreeScenePlan.cached(for: model, theme: .maple).skeleton
        let available = CGRect(
            x: insets.leading, y: insets.top,
            width: max(1, viewport.width - insets.leading - insets.trailing),
            height: max(1, viewport.height - insets.top - insets.bottom)
        )
        availableRect = available
        let minX = min(skeleton.minX, -30), maxX = max(skeleton.maxX, 30)
        let height = max(skeleton.height, 60)
        let width = maxX - minX
        let fit = min(
            (viewport.width - 32) / CGFloat(width),
            (available.height - Self.groundRoom) / CGFloat(height),
            Self.maximumFit
        )
        fitScale = max(0.2, fit)
        let block = CGFloat(height) * fitScale + Self.groundRoom
        let top = available.minY + max(0, (available.height - block) / 2)
        let base = CGPoint(x: viewport.width / 2 - CGFloat(minX + maxX) / 2 * fitScale, y: top + CGFloat(height) * fitScale)
        restBase = base
        restTreeRect = CGRect(
            x: base.x + CGFloat(minX) * fitScale, y: base.y - CGFloat(height) * fitScale,
            width: CGFloat(width) * fitScale, height: CGFloat(height) * fitScale
        )

        func screen(_ p: TreePoint, scale: CGFloat) -> CGPoint {
            CGPoint(x: base.x + CGFloat(p.x) * scale, y: base.y - CGFloat(p.y) * scale)
        }
        let scale = fitScale
        targets = skeleton.rosettes.enumerated().map { index, rosette in
            // The rosette's visual centre: the mean of its leaves' centres, half a leaf out along each stalk.
            var sum = TreePoint.zero
            var count = 0.0
            for leafIndex in rosette.leaves where leafIndex < skeleton.leaves.count {
                let leaf = skeleton.leaves[leafIndex]
                sum += leaf.anchor + TreePoint.direction(angleFromUp: leaf.rotation) * (leaf.size * 0.5)
                count += 1
            }
            let centre = count > 0 ? sum * (1 / count) : rosette.anchor
            return Target(id: index, speciesID: rosette.speciesID, isPrimary: rosette.kind == .primary, restPoint: screen(centre, scale: scale))
        }
        if let first = model.waiting.first, let bud = skeleton.buds.first(where: \.isWaiting) {
            restWaitingBud = (first, screen(bud.anchor + bud.direction * 5, scale: scale))
        } else {
            restWaitingBud = nil
        }
    }

    /// The zoom's fixed point: the tree's centre at 1×.
    public var zoomCentre: CGPoint {
        CGPoint(x: restTreeRect.midX, y: restTreeRect.midY)
    }

    /// Where a point drawn at 1× lands at `zoom`, panned by `pan`.
    public func screenPoint(_ rest: CGPoint, zoom: CGFloat, pan: CGSize) -> CGPoint {
        let c = zoomCentre
        return CGPoint(x: c.x + (rest.x - c.x) * zoom + pan.width, y: c.y + (rest.y - c.y) * zoom + pan.height)
    }

    /// Keeps the tree on screen: no pan at 1×, and at most what the zoom added beyond the screen.
    public func clampedPan(_ pan: CGSize, zoom: CGFloat) -> CGSize {
        let extra = max(0, zoom - 1)
        let limitX = extra * max(restTreeRect.width, viewport.width) / 2
        let limitY = extra * max(restTreeRect.height, availableRect.height) / 2
        return CGSize(width: min(limitX, max(-limitX, pan.width)), height: min(limitY, max(-limitY, pan.height)))
    }

    /// The pan that keeps `anchor` (a screen point) still while the zoom changes from `from` to `to`.
    public func pan(keeping anchor: CGPoint, from: CGFloat, to: CGFloat, startingPan: CGSize) -> CGSize {
        let c = zoomCentre
        let ratio = to / max(from, 0.01)
        return CGSize(
            width: anchor.x - c.x - (anchor.x - c.x - startingPan.width) * ratio,
            height: anchor.y - c.y - (anchor.y - c.y - startingPan.height) * ratio
        )
    }

    /// The waiting bud first, then the nearest rosette, within `hitRadius`.
    public func hit(at location: CGPoint, zoom: CGFloat, pan: CGSize) -> Hit? {
        if let bud = restWaitingBud {
            let point = screenPoint(bud.point, zoom: zoom, pan: pan)
            if hypot(point.x - location.x, point.y - location.y) <= Self.hitRadius {
                return .waitingBud(speciesID: bud.speciesID)
            }
        }
        var best: (distance: CGFloat, speciesID: String)?
        for target in targets {
            let point = screenPoint(target.restPoint, zoom: zoom, pan: pan)
            let distance = hypot(point.x - location.x, point.y - location.y)
            if distance <= Self.hitRadius, distance < (best?.distance ?? .infinity) {
                best = (distance, target.speciesID)
            }
        }
        return best.map { .rosette(speciesID: $0.speciesID) }
    }

    /// Each species' primary rosette, in reading order: rows top to bottom, left to right within a row.
    public func readingOrder(zoom: CGFloat = 1, pan: CGSize = .zero, rowHeight: CGFloat = 36) -> [Target] {
        targets.filter(\.isPrimary).sorted { a, b in
            let pa = screenPoint(a.restPoint, zoom: zoom, pan: pan), pb = screenPoint(b.restPoint, zoom: zoom, pan: pan)
            let ra = (pa.y / rowHeight).rounded(.down), rb = (pb.y / rowHeight).rounded(.down)
            return ra != rb ? ra < rb : pa.x < pb.x
        }
    }

    /// The scene frame at `zoom` and `pan`: scene point (201, 470), the trunk base, lands on the panned base.
    func treeFrame(zoom: CGFloat, pan: CGSize) -> TreeSceneFrame {
        let base = screenPoint(restBase, zoom: zoom, pan: pan)
        let scale = fitScale * zoom
        return TreeSceneFrame(size: viewport, scale: scale, base: base)
    }

    /// The sky stays far away: it fills the screen down to the ground and moves a quarter as much as the tree.
    func skyFrame(zoom: CGFloat, pan: CGSize) -> TreeSceneFrame {
        let fill = max(viewport.width / TreeSceneFrame.reference.width, restBase.y / TreeSceneFrame.trunkBase.y)
        let depth: CGFloat = 0.25
        let zoomed = 1 + (zoom - 1) * depth
        let c = zoomCentre
        let base = CGPoint(
            x: c.x + (viewport.width / 2 - c.x) * zoomed + pan.width * depth,
            y: c.y + (restBase.y - c.y) * zoomed + pan.height * depth
        )
        return TreeSceneFrame(size: viewport, scale: fill * zoomed, base: CGPoint(x: base.x, y: base.y))
    }
}

/// The Tree view's geometry with its rosettes in reading order at 1×, built once per layout and screen.
nonisolated public struct TreeCloseUpLayout: Sendable {
    public let geometry: TreeCloseUpGeometry
    /// Each species' primary rosette, rows top to bottom and left to right at 1×: the VoiceOver order.
    public let readingOrder: [TreeCloseUpGeometry.Target]
}

extension TreeCloseUpGeometry {
    private struct LayoutCacheKey: Equatable {
        var layout: TreeSceneModel.LayoutKey
        var viewport: CGSize
        var insets: EdgeInsets
    }

    @MainActor private static var lastLayout: (key: LayoutCacheKey, layout: TreeCloseUpLayout)?

    /// The geometry for `model` in `viewport`, reused while the tree's layout and the screen stay the same. The Tree
    /// view re-evaluates on every pinch and pan update, and this keeps each of those frames from rebuilding every
    /// rosette's target and sorting them again.
    @MainActor
    public static func cachedLayout(model: TreeSceneModel, viewport: CGSize, insets: EdgeInsets) -> TreeCloseUpLayout {
        let key = LayoutCacheKey(layout: model.layoutKey, viewport: viewport, insets: insets)
        if let lastLayout, lastLayout.key == key { return lastLayout.layout }
        let geometry = TreeCloseUpGeometry(model: model, viewport: viewport, insets: insets)
        let layout = TreeCloseUpLayout(geometry: geometry, readingOrder: geometry.readingOrder())
        lastLayout = (key, layout)
        return layout
    }
}

extension TreeSceneFrame {
    /// A frame with its own scale, placed so the trunk base (201, 470) lands on `base`.
    nonisolated init(size: CGSize, scale: CGFloat, base: CGPoint) {
        self.init(size: size)
        self.scale = max(0.01, scale)
        origin = CGPoint(x: base.x - Self.trunkBase.x * self.scale, y: base.y - Self.trunkBase.y * self.scale)
    }
}

/// The Tree view's maple (spec §8.4): sky, bloom, ground, tree and buds drawn as vectors at the screen's own
/// size, so it stays sharp at every zoom. It sways gently at 1× (still under Reduce Motion, in Low Power Mode,
/// while zoomed, for large crowns, under a full-screen cover (`\.treeScenesPaused`) and, as on Home, after a
/// minute at night without interaction); the caller handles gestures and accessibility.
public struct TreeCloseUp: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.treeScenesPaused) private var isCovered
    @State private var nightFrozen = false

    private let model: TreeSceneModel
    private let geometry: TreeCloseUpGeometry
    private let zoom: CGFloat
    private let pan: CGSize
    private let interactions: Int

    /// Above this many rosettes the tree view holds still (as the Home flutter rule does past 60).
    static let swayingRosetteLimit = 60

    /// - Parameter interactions: A count the caller bumps on every tap; with zoom and pan changes it restarts the
    ///   night's 60 s countdown to a still frame (spec §4.9).
    public init(model: TreeSceneModel, geometry: TreeCloseUpGeometry, zoom: CGFloat, pan: CGSize, interactions: Int = 0) {
        self.model = model
        self.geometry = geometry
        self.zoom = zoom
        self.pan = pan
        self.interactions = interactions
    }

    public var body: some View {
        let plan = TreeScenePlan.cached(for: model, theme: theme)
        let still = model.time != nil || reduceMotion || scenePhase != .active || zoom > 1.001
            || ProcessInfo.processInfo.isLowPowerModeEnabled || plan.rosettes.count > Self.swayingRosetteLimit
            || isCovered || nightFrozen
        TimelineView(.animation(minimumInterval: 1 / 30, paused: still)) { timeline in
            let now = model.time ?? timeline.date
            let motion = still
                ? (model.time != nil && !reduceMotion
                    ? TreeSceneRenderer.Motion(time: now.timeIntervalSinceReferenceDate, now: now)
                    : .rest(now: now))
                : TreeSceneRenderer.Motion(time: timeline.date.timeIntervalSinceReferenceDate, now: now)
            canvas(plan, motion: motion)
        }
        .accessibilityHidden(true)
        .task(id: FreezeKey(phase: model.phase, active: scenePhase == .active, interactions: interactions,
                            zoom: Double(zoom), panX: Double(pan.width), panY: Double(pan.height))) {
            // At night the tree settles to a still frame after a minute without interaction, as Home's does.
            nightFrozen = false
            guard model.phase == .night else { return }
            try? await Task.sleep(for: .seconds(60))
            if !Task.isCancelled { nightFrozen = true }
        }
    }

    private struct FreezeKey: Equatable {
        var phase: NowPhase
        var active: Bool
        var interactions: Int
        var zoom: Double
        var panX: Double
        var panY: Double
    }

    private func canvas(_ plan: TreeScenePlan, motion: TreeSceneRenderer.Motion) -> some View {
        let geometry = geometry, zoom = zoom, pan = pan
        let background = theme.colors.background
        return Canvas { context, _ in
            let sky = geometry.skyFrame(zoom: zoom, pan: pan)
            TreeSkyPainter.draw(
                plan.sky, frame: sky, time: motion.time, vitality: plan.model.vitality,
                crown: TreeSceneRenderer.crownReference(plan, frame: sky), background: background, in: context
            )
            TreeSceneRenderer.drawStill(
                plan, frame: geometry.treeFrame(zoom: zoom, pan: pan), motion: motion, includesBackdrop: false,
                background: background, in: context
            )
        }
    }
}
