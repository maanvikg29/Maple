import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// The whole maple, full screen (spec §8.4): the same scene and phase as Home with the tree fitted to the width,
/// pinch to zoom 1–3× and pan. Tapping a rosette pushes that leaf's detail; tapping the waiting bud opens the
/// reveal. "See all leaves" switches to the Herbarium showing earned leaves.
///
/// `TreeView(focusing: id)` is leaf detail's "Show on my maple" (spec §5.6): it opens at 2× on that species'
/// rosette and pulses its amber halo twice over 2 s.
struct TreeView: View {
    /// A species to centre on, zoomed in, with its halo pulsing twice.
    let focusing: String?

    init(focusing: String? = nil) {
        self.focusing = focusing
    }

    @Environment(CollectionStore.self) private var collection
    @Environment(AppRouter.self) private var router
    @Environment(\.mapleClock) private var clock
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @Namespace private var zoomNamespace
    @State private var pushedLeaf: String?
    @State private var reveal: RevealRequest?

    var body: some View {
        NavigationStack {
            // The collection is read once a minute; pinching and panning only redraw the viewport below.
            TimelineView(.everyMinute) { timeline in
                let content = HomeContent(collection: collection, now: clock.date(forTimeline: timeline.date))
                GeometryReader { proxy in
                    TreeViewport(
                        content: content, size: proxy.size, safeArea: proxy.safeAreaInsets, focusing: focusing,
                        zoomNamespace: zoomNamespace,
                        pressedDate: { collection.unlock(for: $0)?.date },
                        openLeaf: { pushedLeaf = $0 },
                        openWaitingLeaf: { reveal = RevealRequest(speciesID: $0) },
                        seeAllLeaves: {
                            router.showEarnedLeaves()
                            dismiss()
                        },
                        close: { dismiss() }
                    )
                }
            }
            .background(theme.colors.background)
            .toolbarVisibility(.hidden, for: .navigationBar)
            .navigationDestination(item: $pushedLeaf) { speciesID in
                LeafDetailView(speciesID: speciesID)
                    .navigationTransition(.zoom(sourceID: speciesID, in: zoomNamespace))
            }
        }
        .fullScreenCover(item: $reveal) { request in
            RevealFlow(startingWith: request.speciesID)
        }
    }
}

/// The scene, its gestures, the bars and the VoiceOver elements. Holds the zoom and pan.
private struct TreeViewport: View {
    let content: HomeContent
    /// The safe area's size; the scene extends under the status bar and home indicator.
    let size: CGSize
    let safeArea: EdgeInsets
    let focusing: String?
    let zoomNamespace: Namespace.ID
    let pressedDate: (String) -> Date?
    let openLeaf: (String) -> Void
    let openWaitingLeaf: (String) -> Void
    let seeAllLeaves: () -> Void
    let close: () -> Void

    /// "Show on my maple" opens at 2×.
    private static let focusZoom: CGFloat = 2
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

    init(
        content: HomeContent, size: CGSize, safeArea: EdgeInsets, focusing: String?, zoomNamespace: Namespace.ID,
        pressedDate: @escaping (String) -> Date?, openLeaf: @escaping (String) -> Void,
        openWaitingLeaf: @escaping (String) -> Void, seeAllLeaves: @escaping () -> Void, close: @escaping () -> Void
    ) {
        self.content = content
        self.size = size
        self.safeArea = safeArea
        self.focusing = focusing
        self.zoomNamespace = zoomNamespace
        self.pressedDate = pressedDate
        self.openLeaf = openLeaf
        self.openWaitingLeaf = openWaitingLeaf
        self.seeAllLeaves = seeAllLeaves
        self.close = close
        // A species that is not on the tree (not yet earned, or still waiting) opens the whole maple at 1×.
        let isOnTree = focusing.map { id in content.tree.species.contains { $0.speciesID == id } } ?? false
        _zoom = State(initialValue: isOnTree ? Self.focusZoom : 1)
        _followsFocus = State(initialValue: isOnTree)
    }

    var body: some View {
        // The scene fills the whole screen; the bars stay inside the safe area.
        let viewport = CGSize(width: size.width, height: size.height + safeArea.top + safeArea.bottom)
        let geometry = TreeCloseUpGeometry(
            model: content.tree, viewport: viewport,
            insets: EdgeInsets(
                top: safeArea.top + Self.topBarHeight + theme.spacing.lg, leading: 0,
                bottom: safeArea.bottom + Self.bottomBarHeight + theme.spacing.md, trailing: 0
            )
        )
        let pan = effectivePan(in: geometry)
        ZStack(alignment: .topLeading) {
            TreeCloseUp(model: content.tree, geometry: geometry, zoom: zoom, pan: pan)
                .frame(width: viewport.width, height: viewport.height)
                .contentShape(Rectangle())
                .gesture(magnify(geometry).simultaneously(with: drag(geometry)))
                .onTapGesture(coordinateSpace: .local) { location in
                    tap(at: location, geometry: geometry, pan: pan)
                }
                .overlay(alignment: .topLeading) { focusHaloView(geometry, pan: pan) }
                .overlay(alignment: .topLeading) { leafElements(geometry, pan: pan) }
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
            .frame(width: viewport.width, height: safeArea.top + Self.topBarHeight + theme.spacing.xxxl)
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
        .task { await pulseFocusHalo() }
    }

    private var topBar: some View {
        ZStack {
            VStack(spacing: 2) {
                Text("Your maple")
                    .font(MapleFont.headline)
                    .foregroundStyle(theme.colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(MapleFont.footnote.monospacedDigit())
                    .foregroundStyle(theme.colors.textSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 56)
            .accessibilityElement(children: .combine)

            HStack {
                Button("Close", systemImage: "xmark", action: close)
                    .buttonStyle(.iconCircle)
                Spacer()
            }
            .padding(.horizontal, theme.spacing.sm)
        }
        .frame(minHeight: Self.topBarHeight)
    }

    /// "Young maple · 23 of 155 · 41 days".
    private var subtitle: String {
        var parts = [content.stage.displayName, "\(content.leaves) of \(content.total)"]
        if content.tendedDays > 0 {
            parts.append("\(content.tendedDays) \(content.tendedDays == 1 ? "day" : "days")")
        }
        return parts.joined(separator: " · ")
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
        guard focusing != nil, focusHalo == 0 else { return }
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
    private func leafElements(_ geometry: TreeCloseUpGeometry, pan: CGSize) -> some View {
        let ordered = geometry.readingOrder(zoom: zoom, pan: pan)
        let side = TreeCloseUpGeometry.hitRadius * 2
        return ZStack(alignment: .topLeading) {
            ForEach(Array(ordered.enumerated()), id: \.element.id) { index, target in
                let point = geometry.screenPoint(target.restPoint, zoom: zoom, pan: pan)
                Color.clear
                    .frame(width: side, height: side)
                    .matchedTransitionSource(id: target.speciesID, in: zoomNamespace)
                    .offset(x: point.x - side / 2, y: point.y - side / 2)
                    .accessibilityElement()
                    .accessibilityLabel(rosetteLabel(target.speciesID))
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

    private func rosetteLabel(_ speciesID: String) -> String {
        let species = LeafCatalog.shared.species(id: speciesID)
        var label = HomeSpeech.rosette(name: species?.displayName ?? speciesID, pressed: pressedDate(speciesID))
        if let approximate = species?.confidence.approximateSpokenLabel {
            label += ". " + approximate
        }
        return label
    }
}

/// A reveal opened from the Tree view's waiting bud.
private struct RevealRequest: Identifiable {
    let speciesID: String
    var id: String { speciesID }
}
