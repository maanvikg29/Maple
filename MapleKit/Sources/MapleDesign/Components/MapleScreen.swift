import SwiftUI

extension View {
    /// Places content on Maple's background: near-black fading into deep navy.
    public func mapleBackground() -> some View {
        modifier(MapleBackground())
    }
}

private struct MapleBackground: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background {
                LinearGradient(
                    colors: [theme.colors.background, theme.colors.backgroundRaised],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
    }
}

/// A small uppercase section label, e.g. "TONIGHT".
public struct SectionLabel: View {
    @Environment(\.theme) private var theme
    private let text: LocalizedStringKey

    public init(_ text: LocalizedStringKey) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(MapleFont.overline)
            .textCase(.uppercase)
            .tracking(1.2)
            .foregroundStyle(theme.colors.textSecondary)
            .accessibilityAddTraits(.isHeader)
    }
}
