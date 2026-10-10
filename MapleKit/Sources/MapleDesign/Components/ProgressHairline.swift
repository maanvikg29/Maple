import SwiftUI

/// All progress in Maple: a 2, 3 or 4pt capsule (spec §7.3). The track is `track`; the fill is flat, never a
/// gradient, and never carries a label. It defaults to the season tint; the Herbarium owned bar alone passes
/// `reward`. The value always appears as text nearby, so the bar itself is hidden from VoiceOver.
///
/// ```swift
/// ProgressHairline(fraction: progress.fraction)                                  // 2pt, season tint
/// ProgressHairline(fraction: owned / 155, height: 3, tint: theme.colors.reward)  // the owned bar
/// ```
public struct ProgressHairline: View {
    @Environment(\.theme) private var theme
    @Environment(\.season) private var season

    private let fraction: Double
    private let height: CGFloat
    private let tint: Color?

    /// - Parameters:
    ///   - fraction: 0...1; values outside (and NaN) are clamped.
    ///   - height: 2 (rows), 3 (the owned bar) or 4 (detail).
    ///   - tint: The fill; nil uses the current season's tint.
    public init(fraction: Double, height: CGFloat = 2, tint: Color? = nil) {
        self.fraction = Self.clamped(fraction)
        self.height = height
        self.tint = tint
    }

    public var body: some View {
        Capsule(style: .continuous)
            .fill(theme.colors.track)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule(style: .continuous)
                        .fill(tint ?? theme.colors.seasonTint(season))
                        .frame(width: Self.fillWidth(fraction: fraction, totalWidth: proxy.size.width, height: height))
                }
            }
            .frame(height: height)
            .mapleAnimation(theme.motion.gentle, value: fraction)
            .accessibilityHidden(true)
    }

    /// `fraction` limited to 0...1, with NaN and infinities treated as no progress (positive infinity as full).
    nonisolated public static func clamped(_ fraction: Double) -> Double {
        guard !fraction.isNaN else { return 0 }
        return min(max(fraction, 0), 1)
    }

    /// The fill's width: proportional to the fraction, but never shorter than its own height once there is any
    /// progress, so the first night shows as a dot rather than nothing.
    nonisolated public static func fillWidth(fraction: Double, totalWidth: CGFloat, height: CGFloat) -> CGFloat {
        let fraction = clamped(fraction)
        guard fraction > 0, totalWidth > 0 else { return 0 }
        return min(totalWidth, max(height, CGFloat(fraction) * totalWidth))
    }
}
