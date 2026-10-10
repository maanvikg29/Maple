import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// The whole maple, full screen (spec §8.4): the same scene and phase as Home with the tree fitted to the width,
/// pinch to zoom 1–3× and pan. Tapping a rosette pushes that leaf's detail; tapping the waiting bud opens the
/// reveal. "See all leaves" switches to the Herbarium showing earned leaves.
///
/// `TreeView(focusing: id)` is leaf detail's "Show on my maple" (spec §5.6): it opens at 2× on that species'
/// rosette and pulses its amber halo twice over 2 s. The same link on a detail pushed from here pops back and
/// re-centres this viewport rather than closing and reopening the cover.
struct TreeView: View {
    init(focusing: String? = nil) {
        _focus = State(initialValue: TreeFocus(speciesID: focusing))
    }

    @Environment(CollectionStore.self) private var collection
    @Environment(AppRouter.self) private var router
    @Environment(\.mapleClock) private var clock
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @Namespace private var zoomNamespace
    /// The species to centre on, zoomed in, with its halo pulsing twice; a new request re-centres.
    @State private var focus: TreeFocus
    @State private var pushedLeaf: String?
    @State private var reveal: RevealRequest?

    var body: some View {
        NavigationStack {
            // The collection is read once a minute; pinching and panning only redraw the viewport below.
            TimelineView(.everyMinute) { timeline in
                let content = HomeContent(collection: collection, now: clock.date(forTimeline: timeline.date))
                // Every rosette's VoiceOver label, built here once per minute or change, never per gesture frame.
                let labels = rosetteLabels(content)
                GeometryReader { proxy in
                    TreeViewport(
                        content: content, size: proxy.size, safeArea: proxy.safeAreaInsets, focus: focus,
                        zoomNamespace: zoomNamespace, labels: labels,
                        openLeaf: { pushedLeaf = $0 },
                        openWaitingLeaf: { id in presentingRevealWithoutSlide { reveal = RevealRequest(speciesID: id) } },
                        seeAllLeaves: {
                            router.showEarnedLeaves()
                            dismiss()
                        },
                        close: { dismiss() }
                    )
                }
            }
            // Covered by a pushed leaf or the reveal, the close-up holds a still frame.
            .environment(\.treeScenesPaused, pushedLeaf != nil || reveal != nil)
            .background(theme.colors.background)
            .toolbarVisibility(.hidden, for: .navigationBar)
            .navigationDestination(item: $pushedLeaf) { speciesID in
                LeafDetailView(speciesID: speciesID)
                    .navigationTransition(.zoom(sourceID: speciesID, in: zoomNamespace))
                    // "Show on my maple" here: back to this maple, centred on the leaf.
                    .environment(\.showOnMaple, ShowOnMapleAction { id in
                        focus = TreeFocus(speciesID: id, request: focus.request + 1)
                        pushedLeaf = nil
                    })
            }
        }
        .fullScreenCover(item: $reveal) { request in
            RevealFlow(startingWith: request.speciesID)
        }
    }

    /// "Red maple, pressed 4 October", plus the approximate-drawing note, for every leaf on the tree.
    private func rosetteLabels(_ content: HomeContent) -> [String: String] {
        let pressed = Dictionary(collection.unlocks.map { ($0.speciesID, $0.date) }, uniquingKeysWith: { first, _ in first })
        var labels: [String: String] = [:]
        for leaf in content.tree.species where labels[leaf.speciesID] == nil {
            let species = LeafCatalog.shared.species(id: leaf.speciesID)
            var label = HomeSpeech.rosette(name: species?.displayName ?? leaf.speciesID, pressed: pressed[leaf.speciesID])
            if let approximate = species?.confidence.approximateSpokenLabel {
                label += ". " + approximate
            }
            labels[leaf.speciesID] = label
        }
        return labels
    }
}

/// Which leaf the Tree view centres on; each new request (a later "Show on my maple") re-centres and pulses again.
struct TreeFocus: Equatable {
    var speciesID: String?
    var request = 0
}

/// The scene, its gestures, the bars and the VoiceOver elements. Holds the zoom and pan.
private struct TreeViewport: View {
    let content: HomeContent
    /// The safe area's size; the scene extends under the status bar and home indicator.
    let size: CGSize
    let safeArea: EdgeInsets
    let focus: TreeFocus
    let zoomNamespace: Namespace.ID
    /// VoiceOver labels by species.
    let labels: [String: String]
    let openLeaf: (String) -> Void
    let openWaitingLeaf: (String) -> Void
    let seeAllLeaves: () -> Void
    let close: () -> Void

    /// "Show on my maple" opens at 2×.
    private static let focusZoom: CGFloat = 2
    /// The top bar's height at the default text size; larger sizes measure it.
    private static let topBarHeight: CGFloat = 52
    private static let bottomBarHeight: CGFloat = 52

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var zoom: CGFloat
    @State private var storedPan: CGSize = .zero
    /// Until the member pinches or drags, the pan keeps the focused rosette centred, whatever the screen's size.
    @State private var followsFocus: Bool
    @State private var pinchStart: (zoom: CGFloat, pan: CGSize)?
    @State private var dragStart: CGSize?
    @State private var focusHalo = 0.0
    /// Taps on the tree, which keep a night-time close-up awake.
    @State private var interactions = 0
    /// The top bar as drawn: it grows at large text sizes, and the tree is fitted below it.
    @State private var measuredTopBar: CGFloat = Self.topBarHeight

    init(
        content: HomeContent, size: CGSize, safeArea: EdgeInsets, focus: TreeFocus, zoomNamespace: Namespace.ID,
        labels: [String: String], openLeaf: @escaping (String) -> Void,
        openWaitingLeaf: @escaping (String) -> Void, seeAllLeaves: @escaping () -> Void, close: @escaping () -> Void
    ) {
        self.content = content
        self.size = size
        self.safeArea = safeArea
        self.focus = focus
        self.zoomNamespace = zoomNamespace
        self.labels = labels
        self.openLeaf = openLeaf
        self.openWaitingLeaf = openWaitingLeaf
        self.seeAllLeaves = seeAllLeaves
        self.close = close
        let isOnTree = Self.isOnTree(focus.speciesID, content: content)
        _zoom = State(initialValue: isOnTree ? Self.focusZoom : 1)
        _followsFocus = State(initialValue: isOnTree)
    }

    /// A species that is not on the tree (not yet earned, or still waiting) shows the whole maple at 1×.
    private static func isOnTree(_ speciesID: String?, content: HomeContent) -> Bool {
        speciesID.map { id in content.tree.species.contains { $0.speciesID == id } } ?? false
    }

    private var focusing: String? { focus.speciesID }

    var body: some View {
        // The scene fills the whole screen; the bars stay inside the safe area.
        let viewport = CGSize(width: size.width, height: size.height + safeArea.top + safeArea.bottom)
        let layout = TreeCloseUpGeometry.cachedLayout(
            model: content.tree, viewport: viewport,
            insets: EdgeInsets(
                top: safeArea.top + measuredTopBar + theme.spacing.lg, leading: 0,
                bottom: safeArea.bottom + Self.bottomBarHeight + theme.spacing.md, trailing: 0
            )
        )
        let geometry = layout.geometry
        let pan = effectivePan(in: geometry)
        ZStack(alignment: .topLeading) {
            TreeCloseUp(model: content.tree, geometry: geometry, zoom: zoom, pan: pan, interactions: interactions)
                .frame(width: viewport.width, height: viewport.height)
                .contentShape(Rectangle())
                .gesture(magnify(geometry).simultaneously(with: drag(geometry)))
                .onTapGesture(coordinateSpace: .local) { location in
                    tap(at: location, geometry: geometry, pan: pan)
                }
                .overlay(alignment: .topLeading) { focusHaloView(geometry, pan: pan) }
                .overlay(alignment: .topLeading) { leafElements(layout, pan: pan) }
                .offset(y: -safeArea.top)

            // Zoomed in, leaves pass under the title: a soft fade keeps it legible (the sky needs none at 1×).
            LinearGradient(
                stops: [
                    .init(color: theme.colors.background.opacity(0.9), location: 0),
                    .init(color: theme.colors.background.opacity(0.75), location: 0.6),
                    .init(color: theme.colors.background.opacity(0), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(width: viewport.width, height: safeArea.top + measuredTopBar + theme.spacing.xxxl)
            .offset(y: -safeArea.top)
            .opacity(zoom > 1.01 ? 1 : 0)
            .mapleAnimation(theme.motion.gentle, value: zoom > 1.01)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                Button("See all leaves", action: seeAllLeaves)
                    .buttonStyle(.glassCapsule)
                    .padding(.bottom, theme.spacing.xs)
            }
            .frame(width: size.width, height: size.height)
        }
        .task(id: focus) {
            // A later "Show on my maple" pops its detail first; the halo pulses once the maple is back in view.
            if focus.request > 0 { try? await Task.sleep(for: .milliseconds(450)) }
            await pulseFocusHalo()
        }
        .onChange(of: focus) { refocus() }
    }

    /// Centres the newly focused leaf at 2× (or shows the whole maple when it isn't on the tree).
    private func refocus() {
        let isOnTree = Self.isOnTree(focus.speciesID, content: content)
        zoom = isOnTree ? Self.focusZoom : 1
        storedPan = .zero
        followsFocus = isOnTree
        pinchStart = nil
        dragStart = nil
        focusHalo = 0
    }

    private var topBar: some View {
        ZStack {
            VStack(spacing: 2) {
                Text("Your maple")
                    .font(MapleFont.headline)
                    .foregroundStyle(theme.colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                // At large text sizes the stage name, then the days, give way, so the count is never cut off.
                ViewThatFits(in: .horizontal) {
                    subtitleText(subtitle(stage: true, days: true)).fixedSize()
                    subtitleText(subtitle(stage: false, days: true)).fixedSize()
                    subtitleText(subtitle(stage: false, days: false))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 56)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(HomeSpeech.treeLabel(stage: content.stage, leaves: content.leaves, total: content.total,
                                                     tendedDays: content.tendedDays))
            .accessibilityAddTraits(.isHeader)

            HStack {
                Button("Close", systemImage: "xmark", action: close)
                    .buttonStyle(.iconCircle)
                Spacer()
            }
            .padding(.horizontal, theme.spacing.sm)
        }
        .frame(minHeight: Self.topBarHeight)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measuredTopBar = max(Self.topBarHeight, $0) }
    }

    /// "Young maple · 23 of 155 · 41 days" (opened leaves only, like every "N of 155").
    private func subtitle(stage: Bool, days: Bool) -> String {
        var parts = ["\(content.leaves) of \(content.total)"]
        if stage { parts.insert(content.stage.displayName, at: 0) }
        if days, content.tendedDays > 0 {
            parts.append("\(content.tendedDays) \(content.tendedDays == 1 ? "day" : "days")")
        }
        return parts.joined(separator: " · ")
    }

    private func subtitleText(_ text: String) -> some View {
        Text(text)
            .font(MapleFont.footnote.monospacedDigit())
            .foregroundStyle(theme.colors.textSecondary)
    }

    // MARK: Zoom and pan

    /// The pan in use: the member's own, or while following the focus, the one that puts the focused rosette at
    /// the centre of the tree's space.
    private func effectivePan(in geometry: TreeCloseUpGeometry) -> CGSize {
        guard followsFocus, let target = focusTarget(geometry) else { return storedPan }
        let point = geometry.screenPoint(target.restPoint, zoom: zoom, pan: .zero)
        let centre = geometry.zoomCentre
        return geometry.clampedPan(CGSize(width: centre.x - point.x, height: centre.y - point.y), zoom: zoom)
    }

    private func magnify(_ geometry: TreeCloseUpGeometry) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = pinchStart ?? (zoom, effectivePan(in: geometry))
                if pinchStart == nil { pinchStart = start }
                followsFocus = false
                let range = TreeCloseUpGeometry.zoomRange
                let newZoom = min(range.upperBound, max(range.lowerBound, start.zoom * value.magnification))
                let moved = geometry.pan(keeping: value.startLocation, from: start.zoom, to: newZoom, startingPan: start.pan)
                storedPan = geometry.clampedPan(moved, zoom: newZoom)
                zoom = newZoom
            }
            .onEnded { _ in
                pinchStart = nil
                dragStart = nil
                if zoom < 1.03 {
                    zoom = 1
                    storedPan = .zero
                }
            }
    }

    private func drag(_ geometry: TreeCloseUpGeometry) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                // While two fingers pinch, the pinch owns the pan.
                guard pinchStart == nil, zoom > 1 else { return }
                let start = dragStart ?? effectivePan(in: geometry)
                if dragStart == nil { dragStart = start }
                followsFocus = false
                storedPan = geometry.clampedPan(
                    CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height),
                    zoom: zoom
                )
            }
            .onEnded { _ in dragStart = nil }
    }

    private func tap(at location: CGPoint, geometry: TreeCloseUpGeometry, pan: CGSize) {
        interactions += 1
        switch geometry.hit(at: location, zoom: zoom, pan: pan) {
        case .waitingBud(let speciesID):
            openWaitingLeaf(speciesID)
        case .rosette(let speciesID):
            openLeaf(speciesID)
        case nil:
            break
        }
    }

    // MARK: Show on my maple

    /// The focused species' own rosette.
    private func focusTarget(_ geometry: TreeCloseUpGeometry) -> TreeCloseUpGeometry.Target? {
        guard let focusing else { return nil }
        return geometry.targets.first { $0.speciesID == focusing && $0.isPrimary }
    }

    /// Twice over 2 s: up, down, up, down. Under Reduce Motion it shows, holds and fades once.
    private func pulseFocusHalo() async {
        guard focusing != nil, focusHalo == 0, !Task.isCancelled else { return }
        let steps: [Double] = reduceMotion ? [1, 1, 1, 0] : [1, 0, 1, 0]
        for value in steps {
            withAnimation(.easeInOut(duration: 0.5)) { focusHalo = value }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    /// The amber new-leaf halo (r 16 in scene points, `rewardHalo`) around the focused rosette.
    @ViewBuilder
    private func focusHaloView(_ geometry: TreeCloseUpGeometry, pan: CGSize) -> some View {
        if let target = focusTarget(geometry) {
            let point = geometry.screenPoint(target.restPoint, zoom: zoom, pan: pan)
            let radius = 16 * geometry.fitScale * zoom
            Circle()
                .fill(RadialGradient(colors: [theme.colors.rewardHalo, theme.colors.rewardHalo.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: radius))
                .frame(width: radius * 2, height: radius * 2)
                .offset(x: point.x - radius, y: point.y - radius)
                .opacity(focusHalo)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    // MARK: Accessibility and transitions

    /// One element per species (its primary rosette), left to right and top to bottom, plus the waiting bud. They
    /// are also the zoom transitions' sources. Taps go to the tree's own hit test, which picks the nearest rosette.
    private func leafElements(_ layout: TreeCloseUpLayout, pan: CGSize) -> some View {
        let geometry = layout.geometry
        let ordered = layout.readingOrder
        let side = TreeCloseUpGeometry.hitRadius * 2
        return ZStack(alignment: .topLeading) {
            ForEach(Array(ordered.enumerated()), id: \.element.id) { index, target in
                let point = geometry.screenPoint(target.restPoint, zoom: zoom, pan: pan)
                Color.clear
                    .frame(width: side, height: side)
                    .matchedTransitionSource(id: target.speciesID, in: zoomNamespace)
                    .offset(x: point.x - side / 2, y: point.y - side / 2)
                    .accessibilityElement()
                    .accessibilityLabel(labels[target.speciesID] ?? target.speciesID)
                    .accessibilityAddTraits(.isButton)
                    .accessibilitySortPriority(Double(ordered.count - index))
                    .accessibilityAction { openLeaf(target.speciesID) }
            }
            if let bud = geometry.restWaitingBud {
                let point = geometry.screenPoint(bud.point, zoom: zoom, pan: pan)
                Color.clear
                    .frame(width: side, height: side)
                    .offset(x: point.x - side / 2, y: point.y - side / 2)
                    .accessibilityElement()
                    .accessibilityLabel(HomeSpeech.waiting(content.tree.waiting.count))
                    .accessibilityHint("Opens your new leaf.")
                    .accessibilityAddTraits(.isButton)
                    .accessibilitySortPriority(Double(ordered.count + 1))
                    .accessibilityAction { openWaitingLeaf(bud.speciesID) }
            }
        }
        .allowsHitTesting(false)
    }
}

/// A reveal opened from the Tree view's waiting bud.
private struct RevealRequest: Identifiable {
    let speciesID: String
    var id: String { speciesID }
}
