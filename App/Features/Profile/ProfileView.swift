import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// The pages the Profile sheet pushes. Challenges and "Export and delete" join once they ship (spec §8.3).
enum ProfileRoute: Hashable {
    case settings
    case privacy
    case about
    #if DEBUG
    case designSystem
    #endif
}

/// The Profile sheet (spec §8.3), presented `.large` from Home's avatar: the featured leaf, the maple's stage and
/// age, totals for the categories that exist, and the rows to Settings, Privacy, About and (DEBUG) the design
/// system. It brings its own navigation stack and sheet styling, so presenters only write
/// `.sheet(isPresented: $showsProfile) { ProfileView() }`.
struct ProfileView: View {
    @Environment(\.theme) private var theme
    @State private var path: [ProfileRoute]

    /// - Parameter path: Pages to open on arrival, e.g. `[.privacy]` from the rarity explainer's "Privacy settings".
    init(path: [ProfileRoute]? = nil) {
        _path = State(initialValue: path ?? ProfileRoute.launchPath)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ProfileHome()
                .navigationDestination(for: ProfileRoute.self) { route in
                    switch route {
                    case .settings: SettingsView()
                    case .privacy: PrivacyView()
                    case .about: AboutView()
                    #if DEBUG
                    case .designSystem: DesignSystemView()
                    #endif
                    }
                }
        }
        .environment(\.profilePageBackground, theme.colors.surface2)
        .presentationDetents([.large])
        .presentationBackground(theme.colors.surface2)
    }
}

private struct ProfileHome: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(CollectionStore.self) private var collection

    var body: some View {
        let totals = collection.totals
        ScrollView {
            VStack(spacing: 0) {
                FeaturedLeaf()
                    .padding(.top, theme.spacing.xs)

                VStack(spacing: theme.spacing.xxs) {
                    Text("Your maple")
                        .font(MapleFont.screenTitle)
                        .tracking(-0.3)
                        .foregroundStyle(theme.colors.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text(ProfileSummary.line(totals))
                        .font(MapleFont.callout)
                        .monospacedDigit()
                        .foregroundStyle(theme.colors.textSecondary)
                        .accessibilityLabel(ProfileSummary.spoken(totals))
                }
                .multilineTextAlignment(.center)
                .padding(.top, theme.spacing.lg)

                let items = ProfileTotalItem.items(totals)
                if !items.isEmpty {
                    ProfileTotalsRow(items: items)
                        .padding(.top, theme.spacing.xl)
                }

                ProfileListGroup {
                    NavigationLink(value: ProfileRoute.settings) { ProfileNavigationRow("Settings") }
                    NavigationLink(value: ProfileRoute.privacy) { ProfileNavigationRow("Privacy") }
                    NavigationLink(value: ProfileRoute.about) { ProfileNavigationRow("About") }
                }
                .buttonStyle(.profileRow)
                .padding(.top, theme.spacing.xxl)

                #if DEBUG
                ProfileListGroup {
                    NavigationLink(value: ProfileRoute.designSystem) { ProfileNavigationRow("Design system") }
                }
                .buttonStyle(.profileRow)
                .padding(.top, theme.spacing.groupGap)
                #endif
            }
            .padding(.horizontal, theme.spacing.listMargin)
            .padding(.bottom, theme.spacing.xxxl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .background(theme.colors.surface2)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .close) { dismiss() }
            }
        }
    }
}

/// The featured leaf as a 96pt specimen: the member's choice from leaf detail, else the newest leaf, in the
/// colourway it was pressed in. Before the first leaf (never seen after onboarding) a closed neutral bud.
private struct FeaturedLeaf: View {
    @Environment(CollectionStore.self) private var collection

    var body: some View {
        let id = collection.featuredLeaf
        let species = id.flatMap { LeafCatalog.shared.species(id: $0) }
        let unlock = id.flatMap { collection.unlock(for: $0) }
        Group {
            if let species, let unlock {
                SpecimenView(species: species, colourway: unlock.colourway, size: 96)
            } else {
                BudGlyph(waiting: false, progress: 1)
                    .frame(width: 96, height: 96 * 1.12)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(species.map { "Featured leaf: \($0.displayName)" } ?? "Your maple's first bud")
        .accessibilityAddTraits(.isImage)
    }
}

/// "Young maple · 23 leaves · 41 days", and its spoken form. `totals.leaves` counts opened leaves only (spec §5.2).
enum ProfileSummary {
    static func line(_ totals: ProfileTotals) -> String {
        var parts = [totals.stage.displayName, totals.leaves == 1 ? "1 leaf" : "\(totals.leaves.formatted()) leaves"]
        if totals.tendedDays > 0 {
            parts.append(totals.tendedDays == 1 ? "1 day" : "\(totals.tendedDays.formatted()) days")
        }
        return parts.joined(separator: " · ")
    }

    static func spoken(_ totals: ProfileTotals) -> String {
        var sentence = "\(totals.stage.displayName), \(LeafCount(opened: totals.leaves, total: LeafCatalog.shared.species.count).spoken)"
        if totals.tendedDays > 0 {
            sentence += totals.tendedDays == 1 ? ", grown over 1 day" : ", grown over \(totals.tendedDays) days"
        }
        return sentence + "."
    }
}

/// One number in the totals row. Only categories that exist for the member appear (spec §8.3).
struct ProfileTotalItem: Identifiable, Equatable {
    var id: String { caption }
    let value: String
    let caption: String
    let spoken: String

    static func items(_ totals: ProfileTotals) -> [ProfileTotalItem] {
        var items: [ProfileTotalItem] = []
        if let nights = totals.nightsOnTime {
            items.append(count(nights, one: "night on time", many: "nights on time"))
        }
        if let hours = totals.focusHours {
            let value = hours.formatted(.number.precision(.fractionLength(0...1)))
            items.append(ProfileTotalItem(value: value, caption: hours == 1 ? "focus hour" : "focus hours",
                                          spoken: "\(value) \(hours == 1 ? "hour" : "hours") of focus"))
        }
        if let windDowns = totals.windDowns {
            items.append(count(windDowns, one: "wind-down", many: "wind-downs"))
        }
        if let mornings = totals.mornings {
            items.append(count(mornings, one: "steady morning", many: "steady mornings"))
        }
        return items
    }

    private static func count(_ value: Int, one: String, many: String) -> ProfileTotalItem {
        let caption = value == 1 ? one : many
        return ProfileTotalItem(value: value.formatted(), caption: caption, spoken: "\(value.formatted()) \(caption)")
    }
}

/// Up to four totals in 28pt numerals over 13pt captions, sharing the width. At accessibility text sizes they
/// become left-aligned lines.
private struct ProfileTotalsRow: View {
    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let items: [ProfileTotalItem]

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: theme.spacing.sm) {
                ForEach(items) { item in
                    HStack(alignment: .firstTextBaseline, spacing: theme.spacing.xs) {
                        StatNumber(item.value, size: .total)
                        Text(item.caption)
                            .font(MapleFont.footnote)
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(item.spoken)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .top, spacing: theme.spacing.xs) {
                ForEach(items) { item in
                    VStack(spacing: theme.spacing.xxs) {
                        StatNumber(item.value, size: .total)
                        Text(item.caption)
                            .font(MapleFont.footnote)
                            .foregroundStyle(theme.colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(item.spoken)
                }
            }
        }
    }
}

#if DEBUG
extension ProfileRoute {
    /// `-MapleDemoProfile settings|privacy|rarity|about|design` opens the sheet on that page (with
    /// `-MapleDemoPresent profile`); docs/debug-launch-arguments.md.
    static var launchPath: [ProfileRoute] {
        switch UserDefaults.standard.string(forKey: "MapleDemoProfile") {
        case "settings": [.settings]
        case "privacy", "rarity": [.privacy]
        case "about": [.about]
        case "design": [.designSystem]
        default: []
        }
    }
}
#else
extension ProfileRoute {
    static var launchPath: [ProfileRoute] { [] }
}
#endif
