import SwiftUI
import MapleCore
import MapleDesign

/// A Focus screen built around the dial (F1 design §4.1, §5.1, §5.3, §5.17): the "Focus" header, the dial at its
/// fitted size, what sits under it, and the screen's one primary action.
///
/// - The dial keeps its preferred size (`MinuteDialMetrics.preferredDiameter(forWidth:)`, about 75% of the width)
///   while everything fits above the floating tab bar, and gives up size down to `MinuteDialMetrics.minimumDiameter`
///   as text grows (`HeroFit`). It is never scaled with `scaleEffect`. Nothing scrolls at default text sizes.
/// - At accessibility sizes, or when even the smallest dial leaves no room, the page scrolls and the primary is
///   pinned just above the tab bar.
///
/// ```swift
/// FocusHeroPage { diameter in
///     MinuteDial(frame: frame, diameter: diameter, theme: theme) { … }
/// } below: {
///     PresetChips(selectedID: preset.id) { choose($0) }
/// } primary: {
///     Button(lines.capsuleTitle) { start() }.buttonStyle(.moonlight)
/// }
/// ```
struct FocusHeroPage<Dial: View, Below: View, Primary: View>: View {
    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var measured = FocusHeroMeasurements()

    private let hasPrimary: Bool
    private let dial: (CGFloat) -> Dial
    private let below: Below
    private let primary: Primary

    /// - Parameters:
    ///   - hasPrimary: False when the screen's action sits inside `below` (Needs Screen Time's card): nothing is
    ///     pinned, and `primary` isn't shown.
    ///   - dial: The dial at the diameter it is given.
    init(
        hasPrimary: Bool = true, @ViewBuilder dial: @escaping (CGFloat) -> Dial, @ViewBuilder below: () -> Below,
        @ViewBuilder primary: () -> Primary
    ) {
        self.hasPrimary = hasPrimary
        self.dial = dial
        self.below = below()
        self.primary = primary()
    }

    var body: some View {
        GeometryReader { proxy in
            let visible = proxy.size.height
            // §5.17: at accessibility sizes the page is a ScrollView with the primary pinned, whatever fits.
            let pinnedBySize = hasPrimary && dynamicTypeSize.isAccessibilitySize
            let fit = HeroFit(
                preferred: MinuteDialMetrics.preferredDiameter(forWidth: proxy.size.width),
                minimum: MinuteDialMetrics.minimumDiameter, visible: visible,
                content: measured.content(gaps: theme.spacing.lg + theme.spacing.xl),
                // A pinned primary takes no room in the flow.
                action: hasPrimary && !pinnedBySize
                    ? (measured.primary ?? HeroFit.estimatedActionHeight) + primaryBottomGap - HeroFit.minimumBottomGap : 0
            )
            let pins = hasPrimary && (pinnedBySize || fit.pinsAction)
            ScrollView {
                page(diameter: fit.heroHeight, pins: pins)
                    // While everything fits, the page fills the first screen so its gaps spread. Once the primary is
                    // pinned the page keeps its natural height, and only real overflow scrolls under the pinned bar.
                    .frame(minHeight: pins ? nil : visible)
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaBar(edge: .bottom) {
                if pins {
                    primarySlot
                        .padding(.horizontal, theme.spacing.homeMargin)
                        .padding(.top, theme.spacing.sm)
                        .padding(.bottom, HeroFit.minimumBottomGap)
                }
            }
        }
    }

    private func page(diameter: CGFloat, pins: Bool) -> some View {
        VStack(spacing: 0) {
            header
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measured.header = $0 }
            Spacer(minLength: theme.spacing.lg)
            dial(diameter)
                .frame(width: diameter, height: diameter)
            below
                // Always at its natural height, so squeezing the page never feeds back into the dial's size.
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measured.below = $0 }
            Spacer(minLength: theme.spacing.xl)
            if hasPrimary, !pins {
                primarySlot
                    .padding(.bottom, primaryBottomGap)
            }
        }
        .padding(.horizontal, theme.spacing.homeMargin)
    }

    private var primarySlot: some View {
        primary
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measured.primary = $0 }
    }

    /// Space under an unpinned primary: about where Home's capsule sits above the tab bar (spec §3.1).
    private var primaryBottomGap: CGFloat { theme.spacing.xl }

    private var header: some View {
        Text(FocusStartLines.title)
            .font(MapleFont.screenTitle)
            .tracking(-0.3)
            .foregroundStyle(theme.colors.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The heights `FocusHeroPage` measures. None depends on the dial's size, so fitting it settles in one pass.
private struct FocusHeroMeasurements: Equatable {
    var header: CGFloat?
    var below: CGFloat?
    var primary: CGFloat?

    /// Everything in the page besides the dial and the primary: the header, what sits under the dial, and the
    /// spacers' minimums (`gaps`). Nil until measured.
    func content(gaps: CGFloat) -> CGFloat? {
        guard let header, let below else { return nil }
        return header + below + gaps
    }
}
