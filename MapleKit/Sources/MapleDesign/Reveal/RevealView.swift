import MapleCore
import SwiftUI

/// Where a reveal is in its ritual.
nonisolated public enum RevealMoment: Sendable, Equatable {
    /// The closed bud, breathing, with "Tap to open".
    case closed
    /// Tapped open at this instant; the ritual plays from it.
    case opened(at: Date)
    /// A fixed instant, this many seconds after the tap: snapshots and DEBUG still frames.
    case still(TimeInterval)
}

/// The reveal cover's content for one leaf (spec §5.8): pure `#05070D` with a season-tint bloom behind the centre,
/// the header, the bud at 40% of the height, "Tap to open", and once the leaf has opened its words, the footer and
/// the share circle.
///
/// Data in, taps out: the app's `RevealFlow` owns the queue and tells the collection what was placed.
///
/// ```swift
/// RevealView(leaf: leaf, position: (1, 3), ritual: .full, moment: .opened(at: tapped), footer: .next(total: 3),
///            actions: RevealView.Actions(open: { … }, next: { … }, openAll: { … }, place: { … }))
/// ```
public struct RevealView: View {
    /// What the cover's controls do.
    public struct Actions {
        /// The tap on the closed bud (or anywhere on the closed cover, or "Tap to open").
        public var open: () -> Void
        /// The close circle, shown only while the bud is closed. Nil hides it.
        public var close: (() -> Void)?
        /// "Next leaf".
        public var next: () -> Void
        /// "Open all {n}".
        public var openAll: () -> Void
        /// "Place on your maple".
        public var place: () -> Void

        public init(
            open: @escaping () -> Void, close: (() -> Void)? = nil, next: @escaping () -> Void = {},
            openAll: @escaping () -> Void = {}, place: @escaping () -> Void
        ) {
            self.open = open
            self.close = close
            self.next = next
            self.openAll = openAll
            self.place = place
        }
    }

    @Environment(\.theme) private var theme
    @AccessibilityFocusState private var focusesName: Bool
    @State private var settledAt: Date?

    private let leaf: RevealLeaf
    private let position: (index: Int, count: Int)?
    private let ritual: RevealRitual
    private let moment: RevealMoment
    private let footer: RevealSession.Footer
    private let shareImage: Image?
    private let actions: Actions

    /// - Parameters:
    ///   - position: "1 of 3" in the header while more than one leaf waits.
    ///   - ritual: Full, short, or the Reduce Motion crossfade (`RevealRitual(tier:revealsBefore:reduceMotion:)`).
    ///   - shareImage: The leaf's share card; when given, a share circle fades in with the footer.
    public init(
        leaf: RevealLeaf, position: (index: Int, count: Int)? = nil, ritual: RevealRitual, moment: RevealMoment,
        footer: RevealSession.Footer, shareImage: Image? = nil, actions: Actions
    ) {
        self.leaf = leaf
        self.position = position
        self.ritual = ritual
        self.moment = moment
        self.footer = footer
        self.shareImage = shareImage
        self.actions = actions
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !isRunning)) { context in
            content(frame: frame(at: context.date))
        }
        .task(id: moment) { await settle() }
    }

    // MARK: Time

    private var openedDate: Date? {
        if case .opened(let date) = moment { date } else { nil }
    }

    private var isRunning: Bool {
        guard let openedDate else { return false }
        return settledAt != openedDate
    }

    /// The ritual's state now: closed, playing, or at rest.
    private func frame(at date: Date) -> RevealFrame? {
        switch moment {
        case .closed:
            return nil
        case .still(let time):
            return .at(time, ritual: ritual)
        case .opened(let opened):
            let time = settledAt == opened ? ritual.settledTime : date.timeIntervalSince(opened)
            return .at(max(0, time), ritual: ritual)
        }
    }

    /// Moves VoiceOver to the leaf's name once its words appear, then stops the timeline once nothing moves.
    private func settle() async {
        switch moment {
        case .closed:
            settledAt = nil
        case .still(let time):
            if time >= ritual.footerStart { focusesName = true }
        case .opened(let opened):
            let untilText = ritual.footerStart - Date().timeIntervalSince(opened)
            if untilText > 0 { try? await Task.sleep(for: .seconds(untilText)) }
            guard !Task.isCancelled else { return }
            focusesName = true
            let untilRest = ritual.settledTime - Date().timeIntervalSince(opened)
            if untilRest > 0 { try? await Task.sleep(for: .seconds(untilRest)) }
            guard !Task.isCancelled else { return }
            settledAt = opened
        }
    }

    // MARK: Layout

    private func content(frame: RevealFrame?) -> some View {
        GeometryReader { proxy in
            let layout = RevealLayout(size: proxy.size, safeArea: proxy.safeAreaInsets)
            let state = frame ?? .closed
            let isClosed = frame == nil
            ZStack(alignment: .top) {
                RevealBackdrop(centreY: layout.budCentreScreenY)

                ScrollView {
                    // The header scrolls with the words, so at large text sizes nothing slides under it.
                    ZStack(alignment: .top) {
                        VStack(spacing: 0) {
                            Color.clear.frame(height: layout.stageTop)
                            RevealStage(species: leaf.species, colourway: leaf.colourway, frame: frame)
                                .frame(width: RevealLayout.leafSize, height: RevealLayout.leafSize)
                                .contentShape(Rectangle())
                                .onTapGesture { if isClosed { actions.open() } }
                                .accessibilityElement()
                                .accessibilityLabel(Text("Open new leaf"))
                                .accessibilityAddTraits(.isButton)
                                .accessibilityAction { actions.open() }
                                .accessibilityHidden(!isClosed)
                            RevealCaption(leaf)
                                .padding(.horizontal, theme.spacing.homeMargin)
                                .padding(.top, theme.spacing.lg + RevealFrame.restingDrop)
                                .opacity(state.textOpacity)
                                .offset(y: state.textRise)
                                .accessibilityHidden(state.textOpacity < 0.5)
                                .accessibilityFocused($focusesName)
                            Spacer(minLength: theme.spacing.lg)
                        }
                        .frame(maxWidth: .infinity)

                        topBar(isClosed: isClosed, footerOpacity: state.footerOpacity)
                    }
                }
                .scrollIndicators(.hidden)
                .scrollDisabled(state.textOpacity < 1)
                .scrollBounceBehavior(.basedOnSize)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    footerView(opacity: state.footerOpacity)
                }
            }
            .overlay(alignment: .bottom) {
                prompt(opacity: state.promptOpacity)
                    .padding(.bottom, RevealLayout.promptInset)
            }
            .contentShape(Rectangle())
            .onTapGesture { if isClosed { actions.open() } }
        }
    }

    private func topBar(isClosed: Bool, footerOpacity: Double) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Group {
                if isClosed, let close = actions.close {
                    Button("Close", systemImage: "xmark", action: close)
                        .buttonStyle(.iconCircle)
                } else {
                    Color.clear
                }
            }
            .frame(width: theme.spacing.minimumHitTarget, height: theme.spacing.minimumHitTarget)

            RevealHeader(position: position, detail: leaf.categoryName)
                .frame(maxWidth: .infinity)
                .padding(.top, RevealLayout.headerToCircle)

            Group {
                if let shareImage, footerOpacity > 0 {
                    ShareLink(
                        item: shareImage,
                        preview: SharePreview(leaf.species.displayName, image: shareImage)
                    ) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.iconCircle)
                    .opacity(footerOpacity)
                    .allowsHitTesting(footerOpacity > 0.5)
                    .accessibilityHidden(footerOpacity < 0.5)
                } else {
                    Color.clear
                }
            }
            .frame(width: theme.spacing.minimumHitTarget, height: theme.spacing.minimumHitTarget)
        }
        .padding(.horizontal, RevealLayout.circleInset)
        .padding(.top, RevealLayout.headerInset - RevealLayout.headerToCircle)
    }

    /// "Tap to open": a visible button too, for Switch Control (spec §9).
    private func prompt(opacity: Double) -> some View {
        Button(action: actions.open) {
            Text("Tap to open")
                .font(MapleFont.footnote)
                .foregroundStyle(theme.colors.textSecondary)
                .frame(minHeight: theme.spacing.minimumHitTarget)
                .padding(.horizontal, theme.spacing.lg)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open new leaf")
        .opacity(opacity)
        .allowsHitTesting(opacity > 0.5)
        .accessibilityHidden(opacity < 0.5)
    }

    private func footerView(opacity: Double) -> some View {
        VStack(spacing: theme.spacing.xxs) {
            switch footer {
            case .next(let total):
                Button("Next leaf", action: actions.next)
                    .buttonStyle(.moonlight)
                TextLink("Open all \(total)", chevron: false, action: actions.openAll)
            case .place:
                Button("Place on your maple", action: actions.place)
                    .buttonStyle(.moonlight)
                    .padding(.bottom, theme.spacing.md)
            }
        }
        .padding(.horizontal, theme.spacing.homeMargin)
        .padding(.top, theme.spacing.sm)
        .opacity(opacity)
        .allowsHitTesting(opacity > 0.5)
        .accessibilityHidden(opacity < 0.5)
        .footerFade(theme.colors.background)
    }
}

/// Where the reveal's parts sit on a screen of `size` (spec §5.8).
nonisolated struct RevealLayout {
    static let leafSize: CGFloat = 200
    static let budSize: CGFloat = 96
    /// The header starts this far below the top safe area.
    static let headerInset: CGFloat = 24
    /// "Tap to open" sits this far above the bottom safe area.
    static let promptInset: CGFloat = 48
    /// The circles' 44 pt hit areas sit at the screen edges' 12 pt, so the 36 pt glass is 16 pt in.
    static let circleInset: CGFloat = 12
    /// The circles' hit areas start this far above the header, centring them on its first line.
    static let headerToCircle: CGFloat = 12
    /// The bud's centre, as a fraction of the screen's height.
    static let budHeightFraction: CGFloat = 0.4
    /// How far above a footer its fade begins.
    static let footerFadeOverhang: CGFloat = 24

    /// The view's size inside the safe area, and the safe area's insets.
    let size: CGSize
    let safeArea: EdgeInsets

    var screenHeight: CGFloat { size.height + safeArea.top + safeArea.bottom }
    /// The bud's centre in screen coordinates.
    var budCentreScreenY: CGFloat { (screenHeight * Self.budHeightFraction).rounded() }
    /// The bud's centre in the view's coordinates, which start at the top safe area.
    var budCentreY: CGFloat { budCentreScreenY - safeArea.top }
    /// The leaf square's top in the view's coordinates.
    var stageTop: CGFloat { max(0, budCentreY - Self.leafSize / 2) }
}

extension View {
    /// Lets scrolled content fade out under a pinned bottom footer (the reveal's buttons, "Save schedule") by
    /// laying the page's own colour behind the footer, rising from clear. Over an empty page it is invisible: no
    /// band, no box. Only large text sizes ever scroll content under it.
    ///
    /// ```swift
    /// .safeAreaInset(edge: .bottom) { footer.footerFade(theme.colors.background) }
    /// ```
    public func footerFade(_ page: Color) -> some View {
        background(alignment: .top) {
            LinearGradient(
                stops: [.init(color: page.opacity(0), location: 0), .init(color: page, location: 0.4)],
                startPoint: .top, endPoint: .bottom
            )
            .padding(.top, -RevealLayout.footerFadeOverhang)
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// Pure `#05070D` with a season-tint bloom at 6% behind the bud.
struct RevealBackdrop: View {
    @Environment(\.theme) private var theme
    @Environment(\.season) private var season
    let centreY: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let radius = max(proxy.size.width, 320) * 0.85
            theme.colors.background
                .overlay(alignment: .top) {
                    Circle()
                        .fill(RadialGradient(
                            colors: [theme.colors.seasonTint(season).opacity(0.06), theme.colors.seasonTint(season).opacity(0)],
                            center: .center, startRadius: 0, endRadius: radius
                        ))
                        .frame(width: radius * 2, height: radius * 2)
                        .offset(y: centreY - radius)
                        .allowsHitTesting(false)
                }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// The cover when leaves are waiting but none may open now (wind-down, night, or held until the morning): the
/// closed bud, still, and "Opens in the morning". Presenters don't open the reveal then (spec §5.8); this is the
/// designed state if one does.
public struct RevealHeldView: View {
    @Environment(\.theme) private var theme
    private let count: Int
    private let onClose: () -> Void

    public init(count: Int, onClose: @escaping () -> Void) {
        self.count = count
        self.onClose = onClose
    }

    public var body: some View {
        GeometryReader { proxy in
            let layout = RevealLayout(size: proxy.size, safeArea: proxy.safeAreaInsets)
            ZStack(alignment: .top) {
                RevealBackdrop(centreY: layout.budCentreScreenY)
                RevealHeader(count > 1 ? "\(count) new leaves" : "A new leaf")
                    .padding(.horizontal, theme.spacing.homeMargin + theme.spacing.minimumHitTarget)
                    .padding(.top, RevealLayout.headerInset)
                HStack {
                    Button("Close", systemImage: "xmark", action: onClose)
                        .buttonStyle(.iconCircle)
                    Spacer()
                }
                .padding(.horizontal, RevealLayout.circleInset)
                .padding(.top, RevealLayout.headerInset - RevealLayout.headerToCircle)
                // A still bud: nothing breathes while it can't be opened. The species stays hidden.
                RevealBud(spread: 0, glow: 1, breathing: false)
                    .frame(width: RevealLayout.budSize, height: RevealLayout.budSize)
                    .position(x: proxy.size.width / 2, y: layout.budCentreY)
            }
            .overlay(alignment: .bottom) {
                Text("Opens in the morning")
                    .font(MapleFont.footnote)
                    .foregroundStyle(theme.colors.textSecondary)
                    .frame(minHeight: theme.spacing.minimumHitTarget)
                    .padding(.bottom, RevealLayout.promptInset)
            }
        }
    }
}
