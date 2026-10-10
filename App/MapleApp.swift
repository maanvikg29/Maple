import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

@main
struct MapleApp: App {
    // Created once per launch: the member's real stores, or in DEBUG the in-memory demo the launch arguments ask
    // for (docs/debug-launch-arguments.md).
    @State private var collection: CollectionStore
    @State private var schedule: ScheduleStore
    @State private var shares: LeafShareStore
    @State private var settings: AppSettings
    private let clock: MapleClock
    /// First run: no maple yet, so the app opens on the end of onboarding (spec §8.8).
    private let needsOnboarding: Bool

    init() {
        let stores = MapleStores.launch()
        _collection = State(initialValue: stores.collection)
        _schedule = State(initialValue: stores.schedule)
        _shares = State(initialValue: stores.shares)
        clock = stores.clock
        // Hemisphere, sleep goal and reveal sound (Profile › Settings). Seasons follow the chosen hemisphere from
        // the first frame; a DEBUG -MapleDemoSeason override still wins.
        let settings = AppSettings.launch()
        settings.apply(to: stores.collection)
        _settings = State(initialValue: settings)
        needsOnboarding = Self.needsOnboarding(stores.collection)
    }

    /// A member without the First-steps leaf on the tree plants their maple first. DEBUG demo collections are
    /// already planted (or deliberately empty); `-MapleDemoPresent onboarding` asks for the flow anyway.
    private static func needsOnboarding(_ collection: CollectionStore) -> Bool {
        #if DEBUG
        if UserDefaults.standard.string(forKey: "MapleDemoPresent") == "onboarding" { return true }
        if DemoLaunchOptions.current.usesDemoCollection { return false }
        #endif
        return !collection.hasPlacedFirstLeaf
    }

    var body: some Scene {
        WindowGroup {
            ThemedRoot(needsOnboarding: needsOnboarding)
                .environment(collection)
                .environment(schedule)
                .environment(shares)
                .environment(settings)
                .environment(\.mapleClock, clock)
        }
    }
}

/// Picks the theme for the system contrast setting and the season for the member's hemisphere (or the DEBUG
/// `-MapleDemoSeason` override), and refreshes rarity when the app comes to the foreground.
private struct ThemedRoot: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.mapleClock) private var clock
    @Environment(CollectionStore.self) private var collection
    @Environment(LeafShareStore.self) private var shares
    @Environment(AppSettings.self) private var settings
    let needsOnboarding: Bool

    var body: some View {
        RootView(needsOnboarding: needsOnboarding)
            .environment(\.theme, contrast == .increased ? .mapleIncreasedContrast : .maple)
            .environment(\.season, collection.season(at: clock.now()))
            .preferredColorScheme(.dark)
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                await shares.refreshIfNeeded()
            }
            .onChange(of: settings.resolvedHemisphere) {
                settings.apply(to: collection)
            }
    }
}
