import SwiftUI
import MapleCore
import MapleDesign

/// The layout every Focus session screen shares (F1 design §5.4–§5.8): ⌄ (or the room it takes), the two-line
/// header, the dial at a fixed distance under it, the lines under the dial, and the controls at the foot.
///
/// - The dial is about 75% of the width (`MinuteDialMetrics.preferredDiameter(forWidth:)`), never more than 46% of
///   the height, and never under 220pt. At accessibility sizes it is 220pt and the page scrolls (§5.17).
/// - The dial sits at a fixed offset from the header, so lines and controls appearing or going under it never move
///   it (no layout motion, §4.6).
/// - The dial's bloom reaches past its frame and is never clipped.
struct SessionScreen<Dial: View, Lines: View, Controls: View>: View {
    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let title: String
    private let subtitle: String?
    private let onMinimise: (() -> Void)?
    private let dial: (CGFloat) -> Dial
    private let lines: Lines
    private let controls: Controls

    /// - Parameters:
    ///   - title: "Study · Chemistry ch. 4", "Break · apps stay locked", "Emergency release".
    ///   - subtitle: "6 apps resting", "Study · Chemistry ch. 4", "Study · Locked", "Apps open again".
    ///   - onMinimise: ⌄; nil leaves its room empty (the receipt and the emergency release have none).
    ///   - dial: The dial, given its diameter.
    init(
        title: String, subtitle: String?, onMinimise: (() -> Void)? = nil,
        @ViewBuilder dial: @escaping (CGFloat) -> Dial, @ViewBuilder lines: () -> Lines,
        @ViewBuilder controls: () -> Controls
    ) {
        self.title = title
        self.subtitle = subtitle
        self.onMinimise = onMinimise
        self.dial = dial
        self.lines = lines()
        self.controls = controls()
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    topBar
                    header
                        .padding(.top, theme.spacing.xxs)
                    dial(Self.diameter(for: proxy.size, accessibility: dynamicTypeSize.isAccessibilitySize))
                        .padding(.top, theme.spacing.lg)
                    VStack(spacing: theme.spacing.xs) {
                        lines
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, theme.spacing.lg)
                    Spacer(minLength: theme.spacing.lg)
                    VStack(spacing: theme.spacing.sm) {
                        controls
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, theme.spacing.homeMargin)
                .padding(.bottom, theme.spacing.md)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }

    private var topBar: some View {
        HStack(spacing: 0) {
            if let onMinimise {
                Button(RunningSessionModel.minimiseLabel, systemImage: "chevron.down", action: onMinimise)
                    .buttonStyle(.iconCircle)
            }
            Spacer(minLength: 0)
        }
        .frame(height: theme.spacing.minimumHitTarget)
    }

    private var header: some View {
        VStack(spacing: theme.spacing.xxs) {
            Text(title)
                .font(MapleFont.headline)
                .foregroundStyle(theme.colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(MapleFont.footnote)
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    /// The dial's diameter in a page of `size`.
    static func diameter(for size: CGSize, accessibility: Bool) -> CGFloat {
        guard !accessibility else { return MinuteDialMetrics.minimumDiameter }
        let fitted = min(MinuteDialMetrics.preferredDiameter(forWidth: size.width), (size.height * 0.46).rounded(.down))
        return max(MinuteDialMetrics.minimumDiameter, fitted)
    }
}
