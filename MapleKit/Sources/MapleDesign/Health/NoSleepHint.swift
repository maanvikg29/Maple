import SwiftUI

/// What Maple says when Apple Health is connected but no sleep has come from it for two nights
/// (`HealthSleepImporter.showsNoSleepHint(at:)`): calm, no icon, no blame.
nonisolated public enum NoSleepHintCopy {
    /// Privacy's Apple Health row, and what VoiceOver reads on Home.
    public static let full = "No sleep from Apple Health yet. Wear your Apple Watch to bed, or turn on Sleep in the Health app."
    /// Home's two lines, each one line of 7 words or fewer (spec §1, anti-vibecode rule 7).
    public static let title = "No sleep from Apple Health yet"
    public static let advice = "Wear your Watch, or turn on Sleep"
}

/// Home's no-sleep hint, in place of the next-leaf row: two 13pt secondary lines on black, the row's height, nothing
/// else (spec §3.4 keeps the first screen to one row).
public struct NoSleepHint: View {
    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(NoSleepHintCopy.title)
            Text(NoSleepHintCopy.advice)
        }
        .font(MapleFont.footnote)
        .foregroundStyle(theme.colors.textSecondary)
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
        .frame(maxWidth: .infinity, minHeight: theme.spacing.row, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(NoSleepHintCopy.full)
    }
}
