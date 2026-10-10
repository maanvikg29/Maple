import SwiftUI

/// A quiet text action: 15pt SF Rounded medium in `textSecondary`, followed by an 11pt semibold chevron
/// (spec §7.3). "All insights ›", "How it works ›", "Show on my maple ›"; without the chevron for
/// "Not now" and "End early". The hit area is at least 44pt tall.
///
/// ```swift
/// TextLink("How it works") { showScore = true }
/// TextLink("Not now", chevron: false) { dismiss() }
/// NavigationLink("All insights", value: Route.insights).buttonStyle(.textLink)
/// ```
public struct TextLink: View {
    private let title: Text
    private let chevron: Bool
    private let action: () -> Void

    public init(_ titleKey: LocalizedStringKey, chevron: Bool = true, action: @escaping () -> Void) {
        self.title = Text(titleKey)
        self.chevron = chevron
        self.action = action
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, chevron: Bool = true, action: @escaping () -> Void) {
        self.title = Text(title)
        self.chevron = chevron
        self.action = action
    }

    public var body: some View {
        Button(action: action) { title }
            .buttonStyle(TextLinkStyle(chevron: chevron))
    }
}

/// The `TextLink` look for any button or navigation link.
public struct TextLinkStyle: ButtonStyle {
    public var chevron: Bool

    public init(chevron: Bool = true) {
        self.chevron = chevron
    }

    public func makeBody(configuration: Configuration) -> some View {
        TextLinkLabel(configuration: configuration, chevron: chevron)
    }
}

extension ButtonStyle where Self == TextLinkStyle {
    /// A text link with a trailing chevron.
    public static var textLink: TextLinkStyle { TextLinkStyle() }

    public static func textLink(chevron: Bool) -> TextLinkStyle {
        TextLinkStyle(chevron: chevron)
    }
}

private struct TextLinkLabel: View {
    @Environment(\.theme) private var theme
    let configuration: ButtonStyleConfiguration
    let chevron: Bool

    var body: some View {
        // The chevron follows the last line when a long link wraps at large text sizes.
        HStack(alignment: .lastTextBaseline, spacing: 3) {
            configuration.label
                .font(.system(.subheadline, design: .rounded, weight: .medium))
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(.caption2, weight: .semibold))
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(theme.colors.textSecondary)
        .opacity(configuration.isPressed ? 0.55 : 1)
        .frame(minHeight: theme.spacing.minimumHitTarget)
        .contentShape(Rectangle())
        .mapleAnimation(theme.motion.press, value: configuration.isPressed)
    }
}
