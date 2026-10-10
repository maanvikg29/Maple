import MapleCore
import SwiftUI

/// Home's 44pt header (spec §3.2): the season word in its tint and today's date on the left; the bedtime-run
/// streak and the avatar on the right. No wordmark, greeting, large title or gear.
///
/// ```swift
/// HomeHeader(season: .autumn, date: now, streak: 12, avatar: .init(species: rubrum, colourway: .autumn),
///            onStreak: { sheet = .streak }, onAvatar: { sheet = .profile })
/// ```
public struct HomeHeader: View {
    /// The featured leaf on the avatar disc, in its pressed colourway.
    public struct Avatar: Equatable {
        public var species: LeafSpecies
        public var colourway: LeafColourway

        public init(species: LeafSpecies, colourway: LeafColourway) {
            self.species = species
            self.colourway = colourway
        }
    }

    /// The streak shows only from a 2-night run.
    public static let minimumStreak = 2

    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The streak's moon: 12pt, growing with the count beside it.
    @ScaledMetric(relativeTo: .headline) private var moonSize: CGFloat = 12

    private let season: Season
    private let date: Date
    private let streak: Int
    private let avatar: Avatar?
    private let onStreak: () -> Void
    private let onAvatar: () -> Void

    public init(
        season: Season, date: Date, streak: Int, avatar: Avatar?, onStreak: @escaping () -> Void,
        onAvatar: @escaping () -> Void
    ) {
        self.season = season
        self.date = date
        self.streak = streak
        self.avatar = avatar
        self.onStreak = onStreak
        self.onAvatar = onAvatar
    }

    public var body: some View {
        HStack(spacing: 0) {
            dateLine
                .frame(maxWidth: .infinity, alignment: .leading)
            if streak >= Self.minimumStreak {
                streakButton
            }
            avatarButton
                // 12pt after the streak, measured between what is drawn: the avatar's hit area has 6pt of air.
                .padding(.leading, streak >= Self.minimumStreak ? 6 : 0)
        }
        .padding(.leading, theme.spacing.homeMargin)
        // The avatar's 44pt hit area overhangs its 32pt disc by 6pt, so the disc lines up with the margin.
        .padding(.trailing, theme.spacing.homeMargin - 6)
        .frame(minHeight: HomeLayout.headerHeight)
    }

    @ViewBuilder
    private var dateLine: some View {
        let seasonWord = Text(HomeSpeech.seasonName(season))
            .font(MapleFont.contextEmphasis)
            .foregroundStyle(theme.colors.seasonTint(season))
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // At accessibility sizes the season and the date take a line each rather than breaking mid-date.
                VStack(alignment: .leading, spacing: 0) {
                    seasonWord
                    Text(HomeDateText.short(date))
                        .font(MapleFont.callout)
                        .foregroundStyle(theme.colors.textSecondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            } else {
                let today = Text(" · \(HomeDateText.short(date))")
                    .font(MapleFont.callout)
                    .foregroundStyle(theme.colors.textSecondary)
                Text("\(seasonWord)\(today)")
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HomeSpeech.header(season: season, date: date))
    }

    private var streakButton: some View {
        Button(action: onStreak) {
            HStack(spacing: 6) {
                Image(systemName: "moon.fill")
                    .font(.system(size: moonSize, weight: .semibold))
                Text(streak, format: .number)
                    .font(.system(.headline, design: .rounded, weight: .semibold).monospacedDigit())
                    .contentTransition(.numericText())
            }
            .foregroundStyle(theme.colors.reward)
            .frame(minWidth: theme.spacing.minimumHitTarget, minHeight: theme.spacing.minimumHitTarget, alignment: .trailing)
            .contentShape(Rectangle())
        }
        .buttonStyle(HeaderPressStyle())
        .mapleAnimation(theme.motion.gentle, value: streak)
        .accessibilityLabel(HomeSpeech.streak(nights: streak))
    }

    private var avatarButton: some View {
        Button(action: onAvatar) {
            ZStack {
                Circle().fill(theme.colors.surface2)
                // A 1pt ring of white at 14% (more under Increase Contrast).
                Circle().strokeBorder(theme.selectedHairline, lineWidth: 1)
                if let avatar {
                    LeafView(avatar.species, fill: .colourway(avatar.colourway), detail: .full)
                        .frame(width: 20, height: 20)
                }
            }
            .frame(width: 32, height: 32)
            .frame(width: theme.spacing.minimumHitTarget, height: theme.spacing.minimumHitTarget)
            .contentShape(Circle())
        }
        .buttonStyle(HeaderPressStyle())
        .accessibilityLabel("Profile")
    }
}

/// Header controls dim a little while pressed, over `press`.
private struct HeaderPressStyle: ButtonStyle {
    @Environment(\.theme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .mapleAnimation(theme.motion.press, value: configuration.isPressed)
    }
}
