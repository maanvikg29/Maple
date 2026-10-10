import SwiftUI
import MapleDesign

// The building blocks of the Profile sheet and the screens it pushes (Settings, Privacy, About): a scrolling page
// with a `screenTitle` header, and Level-1 groups of rows separated by hairlines (spec §6.5, §8.3, §8.7).
// One group per idea, never a stack of single-row cards.

/// A page in the Profile sheet: 20pt margins, the title in `screenTitle` (never a system large title), then the
/// content. The system back button stays in the navigation bar; its title is removed so the page title is the only
/// one.
struct ProfilePage<Content: View>: View {
    @Environment(\.theme) private var theme
    @Environment(\.profilePageBackground) private var pageBackground
    private let title: String
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(MapleFont.screenTitle)
                    .tracking(-0.3)
                    .foregroundStyle(theme.colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, theme.spacing.xs)
                content
                    .padding(.top, theme.spacing.lg)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, theme.spacing.listMargin)
            .padding(.bottom, theme.spacing.xxxl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .background(pageBackground ?? theme.colors.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(removing: .title)
    }
}

extension EnvironmentValues {
    /// The fill behind a `ProfilePage`: the sheet's `surface2` inside the Profile sheet (spec §2.3); nil means the
    /// screen background, for a page pushed onto a tab's stack.
    @Entry var profilePageBackground: Color? = nil
}

/// Rows on one Level-1 surface (radius 28), divided by 0.5pt hairlines inset to the text.
struct ProfileListGroup<Content: View>: View {
    @Environment(\.theme) private var theme
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: theme.radius.largeTile, style: .continuous)
        VStack(spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(rows) { row in
                    if row.id != rows.first?.id {
                        Rectangle()
                            .fill(theme.colors.divider)
                            .frame(height: 0.5)
                            .padding(.leading, theme.spacing.listMargin)
                            .accessibilityHidden(true)
                    }
                    row
                }
            }
        }
        .clipShape(shape)
        .surface(.level1, radius: theme.radius.largeTile)
    }
}

/// A row that opens another page: the title in 17pt, an optional value in 15pt secondary, and a chevron.
/// Use as a `NavigationLink` label with `.buttonStyle(.profileRow)`.
struct ProfileNavigationRow: View {
    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let title: String
    private let value: String?

    init(_ title: String, value: String? = nil) {
        self.title = title
        self.value = value
    }

    var body: some View {
        HStack(spacing: theme.spacing.sm) {
            Text(title)
                .font(MapleFont.body)
                .foregroundStyle(theme.colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let value, !dynamicTypeSize.isAccessibilitySize {
                Text(value)
                    .font(MapleFont.callout)
                    .foregroundStyle(theme.colors.textSecondary)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.colors.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, theme.spacing.listMargin)
        .padding(.vertical, theme.spacing.sm)
        .frame(minHeight: theme.spacing.row)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(value.map { Text($0) } ?? Text(""))
    }
}

/// A row holding a setting: its title, an optional explanation in 13pt secondary, and the control. The control
/// sits on the title's line, or under the text when it doesn't fit (accessibility text sizes) or is `stacked`.
/// Give the control the same title (toggles and steppers do); the visible title is then not read twice.
struct ProfileSettingRow<Control: View>: View {
    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let title: String
    private let detail: Text?
    private let stacked: Bool
    private let controlIsLabelled: Bool
    private let link: TextLink?
    private let control: Control

    /// - Parameter link: A `TextLink` under the explanation, such as "How rarity works".
    init(
        _ title: String, detail: Text? = nil, link: TextLink? = nil, stacked: Bool = false,
        controlIsLabelled: Bool = true, @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.detail = detail
        self.link = link
        self.stacked = stacked
        self.controlIsLabelled = controlIsLabelled
        self.control = control()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            if stacked || dynamicTypeSize.isAccessibilitySize {
                titleText
                control
                    .padding(.vertical, theme.spacing.xxs)
            } else {
                HStack(spacing: theme.spacing.sm) {
                    titleText
                        .frame(maxWidth: .infinity, alignment: .leading)
                    control
                }
            }
            if let detail {
                detail
                    .font(MapleFont.footnote)
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let link {
                // The link's 44pt hit area overlaps the row's padding rather than adding to it; at accessibility
                // sizes the text is taller than 44pt, so it simply stacks.
                link
                    .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 0 : -theme.spacing.sm)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, theme.spacing.listMargin)
        .padding(.vertical, theme.spacing.md)
        .frame(minHeight: theme.spacing.row)
    }

    private var titleText: some View {
        Text(title)
            .font(MapleFont.body)
            .foregroundStyle(theme.colors.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(controlIsLabelled)
    }
}

/// A row that only states a fact: a label on the left, its value on the right in secondary.
struct ProfileFactRow: View {
    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let title: String
    private let value: String

    init(_ title: String, value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: theme.spacing.xxs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: theme.spacing.sm))
        layout {
            Text(title)
                .font(MapleFont.body)
                .foregroundStyle(theme.colors.textPrimary)
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? nil : .infinity, alignment: .leading)
            Text(value)
                .font(MapleFont.callout)
                .monospacedDigit()
                .foregroundStyle(theme.colors.textSecondary)
                .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, theme.spacing.listMargin)
        .padding(.vertical, theme.spacing.sm)
        .frame(minHeight: theme.spacing.row)
        .accessibilityElement(children: .combine)
    }
}

/// Press feedback for rows that act as buttons: the row takes the pressed Level-1 fill (`surface2`) over `press`.
struct ProfileRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ProfileRowPress(configuration: configuration)
    }
}

private struct ProfileRowPress: View {
    @Environment(\.theme) private var theme
    let configuration: ButtonStyleConfiguration

    var body: some View {
        configuration.label
            .background(configuration.isPressed ? theme.colors.surface2 : .clear)
            .mapleAnimation(theme.motion.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == ProfileRowButtonStyle {
    static var profileRow: ProfileRowButtonStyle { ProfileRowButtonStyle() }
}

/// The on/off switch for settings rows. The season tint is the only accent outside amber (spec §1.4), so it
/// fills the "on" track.
struct ProfileToggle: View {
    @Environment(\.season) private var season
    @Environment(\.theme) private var theme
    private let title: String
    @Binding private var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        self._isOn = isOn
    }

    var body: some View {
        Toggle(title, isOn: $isOn)
            .labelsHidden()
            .tint(theme.colors.seasonTint(season))
    }
}
