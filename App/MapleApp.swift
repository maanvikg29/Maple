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
    private let clock: MapleClock

    init() {
        let stores = MapleStores.launch()
        _collection = State(initialValue: stores.collection)
        _schedule = State(initialValue: stores.schedule)
        _shares = State(initialValue: stores.shares)
        clock = stores.clock
    }

    var body: some Scene {
        WindowGroup {
            ThemedRoot()
                .environment(collection)
                .environment(schedule)
                .environment(shares)
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

    var body: some View {
        RootView()
            .environment(\.theme, contrast == .increased ? .mapleIncreasedContrast : .maple)
            .environment(\.season, collection.season(at: clock.now()))
            .preferredColorScheme(.dark)
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                await shares.refreshIfNeeded()
            }
    }
}
