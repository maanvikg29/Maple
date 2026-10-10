import SwiftUI
import UIKit
import MapleCore
import MapleDesign
import MapleServices

/// Every leaf as the Herbarium shows it at one moment: progress from the collection, rarity from the share store.
/// Views never compute unlocks or shares themselves; they read these.
struct HerbariumEntries {
    let entries: [HerbariumEntry]
    let phase: NowPhase
    /// The moment the entries describe.
    let now: Date

    init(collection: CollectionStore, shares: LeafShareStore, at now: Date) {
        let catalog = LeafCatalog.shared
        let rewards = RewardCatalog.shared
        let next = collection.nextRungIDs(at: now)
        let opensNow = Set(collection.revealable(at: now).map(\.speciesID))
        entries = collection.progress(at: now).compactMap { progress in
            guard let species = catalog.species(id: progress.speciesID) else { return nil }
            let id = progress.speciesID
            return HerbariumEntry(
                species: species, progress: progress, rule: rewards.reward(forSpecies: id)?.unlockText ?? "",
                isNextRung: next.contains(id), isUnseen: collection.isUnseen(id), share: shares.share(for: id),
                estimate: shares.estimate(for: id), opensNow: opensNow.contains(id)
            )
        }
        phase = collection.phase(at: now)
        self.now = now
    }

    /// Opened and waiting leaves: the Herbarium's "23 of 155".
    var ownedCount: Int { entries.filter(\.isUnlocked).count }

    /// The earned leaf with the smallest fresh share ("Your rarest"), or nil without one.
    var rarest: HerbariumEntry? {
        entries.filter { $0.isEarned && $0.estimate != nil }.min { ($0.estimate?.percent ?? 100) < ($1.estimate?.percent ?? 100) }
    }

    func count(_ scope: HerbariumScope) -> Int {
        entries.filter(scope.includes).count
    }
}

/// A leaf to push or reveal. `source` names the tile it zooms from: a species can sit in two sections at once
/// (a Region grouping) or in both the rail and the grid.
struct LeafRoute: Hashable, Identifiable {
    var id: String { "\(source)/\(speciesID)" }
    let speciesID: String
    let source: String
    var opening: LeafDetailView.Opening = .plain
}

extension View {
    /// The Herbarium and leaf detail background: `#05070D` with the season tint as a 6% bloom at the top
    /// (r 300, centred at x 201, y 40; spec §5.3).
    func herbariumBackdrop(bloom: Bool = true) -> some View {
        modifier(HerbariumBackdrop(bloom: bloom))
    }
}

private struct HerbariumBackdrop: ViewModifier {
    @Environment(\.theme) private var theme
    @Environment(\.season) private var season
    let bloom: Bool

    func body(content: Content) -> some View {
        content.background {
            ZStack(alignment: .top) {
                theme.colors.background
                if bloom {
                    RadialGradient(
                        colors: [theme.colors.seasonTint(season).opacity(0.06), theme.colors.seasonTint(season).opacity(0)],
                        center: UnitPoint(x: 0.5, y: 0.046), startRadius: 0, endRadius: 300
                    )
                    .frame(height: 874)
                }
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
        }
    }
}

/// Opens Maple's page in Settings, where a missing permission can be turned on. The permission primer, once it
/// exists, takes over from here (spec §5.3 "Turn on").
@MainActor
func openPermissionSettings(_ openURL: OpenURLAction) {
    if let url = URL(string: UIApplication.openSettingsURLString) {
        openURL(url)
    }
}
