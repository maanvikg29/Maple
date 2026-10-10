import SwiftUI
import MapleCore
import MapleDesign

/// Leaf detail's status tile (spec §5.6; Level 1, radius 28, padding 20): what an earned leaf stands for, how to
/// earn a locked one, what a leaf needs, or that a new leaf is waiting.
struct StatusTile: View {
    struct Actions {
        var showOnMaple: () -> Void
        var open: () -> Void
        var startWindDown: () -> Void
        var turnOn: () -> Void
        var togglePin: () -> Void
    }

    @Environment(\.theme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone

    let entry: HerbariumEntry
    let phase: NowPhase
    /// The member's units per day over the last 14 days.
    let rate: Double
    let isPinned: Bool
    let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch entry.status {
            case .earned(let unlock): earned(unlock)
            case .waiting: waiting
            case .next, .locked: howToEarn
            case .needsPermission(let availability): needs(availability)
            case .dormant: dormant
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .surface(.level1, radius: theme.radius.largeTile)
    }

    // MARK: States

    @ViewBuilder
    private func earned(_ unlock: LeafUnlock) -> some View {
        Text(HerbariumCopy(locale: locale, timeZone: timeZone).pressedLong(unlock.date))
            .font(MapleFont.headline)
            .foregroundStyle(theme.colors.textPrimary)
            .accessibilityAddTraits(.isHeader)
        Text(HerbariumCopy.earnedLine(entry.progress, season: unlock.season))
            .font(MapleFont.callout)
            .foregroundStyle(theme.colors.textSecondary)
            .padding(.top, 4)
        TextLink("Show on my maple", action: actions.showOnMaple)
            .padding(.top, 4)
            .padding(.bottom, -12)
    }

    @ViewBuilder
    private var waiting: some View {
        Text("A new leaf is waiting")
            .font(MapleFont.headline)
            .foregroundStyle(theme.colors.textPrimary)
            .accessibilityAddTraits(.isHeader)
        if entry.opensNow {
            Button("Open", action: actions.open)
                .buttonStyle(.glassCapsule)
                .padding(.top, theme.spacing.sm)
        } else {
            Text("Opens in the morning")
                .font(MapleFont.callout)
                .foregroundStyle(theme.colors.textSecondary)
                .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var howToEarn: some View {
        let progress = entry.progress
        let info = RewardCategoryInfo(progress.category)
        label("How to earn")
        rule
        ProgressHairline(fraction: progress.fraction, height: 4)
            .padding(.top, theme.spacing.sm)
        Text(HerbariumCopy.progressLine(progress, rate: rate))
            .font(MapleFont.callout.monospacedDigit())
            .foregroundStyle(theme.colors.textSecondary)
            .padding(.top, theme.spacing.xs)
        Text(info.definition)
            .font(MapleFont.footnote)
            .foregroundStyle(theme.colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, theme.spacing.xs)
        if info.action == .startWindDown, phase == .evening || phase == .windDown {
            Button("Start wind-down", action: actions.startWindDown)
                .buttonStyle(.glassCapsule)
                .padding(.top, theme.spacing.md)
        }
        TextLink(isPinned ? "Unpin" : "Pin as next leaf", chevron: false, action: actions.togglePin)
            .padding(.top, theme.spacing.xxs)
            .padding(.bottom, -12)
            .accessibilityHint(isPinned ? "Home goes back to choosing your next leaf." : "Home shows this leaf as your next one.")
    }

    @ViewBuilder
    private func needs(_ availability: LeafAvailability) -> some View {
        label("How to earn")
        rule
        Text(HerbariumCopy.permissionLine(availability) ?? "")
            .font(MapleFont.callout)
            .foregroundStyle(theme.colors.textSecondary)
            .padding(.top, theme.spacing.xs)
        if let title = HerbariumCopy.turnOnTitle(availability) {
            Button(title, action: actions.turnOn)
                .buttonStyle(.glassCapsule)
                .padding(.top, theme.spacing.md)
        }
    }

    @ViewBuilder
    private var dormant: some View {
        rule
        Text(HerbariumCopy.notEarnableYet)
            .font(MapleFont.callout)
            .foregroundStyle(theme.colors.textSecondary)
            .padding(.top, theme.spacing.xs)
    }

    // MARK: Pieces

    private func label(_ text: String) -> some View {
        Text(text)
            .font(MapleFont.footnote)
            .foregroundStyle(theme.colors.textSecondary)
            .accessibilityAddTraits(.isHeader)
    }

    /// The rung's rule in 20pt SF Rounded semibold ("Fall asleep on time 14 nights").
    private var rule: some View {
        Text(entry.rule)
            .font(MapleFont.sectionTitle)
            .foregroundStyle(theme.colors.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }
}
