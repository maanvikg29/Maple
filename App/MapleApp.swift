import SwiftUI
import UIKit
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
    /// The first run's screen, answers and schedule draft, so a stopped first run resumes on the same screen.
    @State private var onboarding = OnboardingStore.launch()
    /// Apple Health: granted only once the member has been through Apple's prompt (DEBUG demos: their arguments).
    @State private var health: HealthPermission
    private let stores: MapleStores
    private let clock: MapleClock
    /// Where the first run starts or picks up (spec §8.8): until the Sugar maple is on the tree, the app opens on
    /// the end of onboarding, already showing the right step in its first frame. Decided again if the files could
    /// only be read after launch (a launch before the first unlock after a restart).
    @State private var launch: LaunchGate

    init() {
        let stores = MapleStores.launch()
        self.stores = stores
        _collection = State(initialValue: stores.collection)
        _schedule = State(initialValue: stores.schedule)
        _shares = State(initialValue: stores.shares)
        _health = State(initialValue: stores.health)
        clock = stores.clock
        // Hemisphere, sleep goal and reveal sound (Profile › Settings). Seasons follow the chosen hemisphere from
        // the first frame; a DEBUG -MapleDemoSeason override still wins.
        let settings = AppSettings.launch()
        settings.apply(to: stores.collection)
        _settings = State(initialValue: settings)
        _launch = State(initialValue: LaunchGate(firstRun: Self.firstRun(stores)))
    }

    /// A member without the First-steps leaf on the tree plants their maple first, resuming wherever an earlier
    /// launch stopped (and repairing a save the app was stopped in the middle of). DEBUG demo collections are
    /// already planted (or deliberately empty) and open on the tabs, unless `-MapleDemoPresent onboarding` asks
    /// for the flow (which a planted collection skips).
    static func firstRun(_ stores: MapleStores) -> FirstRunStep {
        #if DEBUG
        if DemoLaunchOptions.current.usesDemoCollection, UserDefaults.standard.string(forKey: "MapleDemoPresent") != "onboarding" {
            return .finished
        }
        #endif
        // Files that can't be read yet are never repaired: the step is decided again once they can be.
        guard stores.isAvailable else { return stores.schedule.firstRun }
        return stores.schedule.resumeFirstRun(at: stores.clock.now())
    }

    var body: some Scene {
        WindowGroup {
            ThemedRoot(stores: stores, launch: $launch)
                .environment(collection)
                .environment(schedule)
                .environment(shares)
                .environment(settings)
                .environment(onboarding)
                .environment(health)
                .environment(\.mapleClock, clock)
        }
    }
}

/// The first-run step the root opens on, and a generation that rebuilds the root when it is decided again.
struct LaunchGate: Equatable {
    var firstRun: FirstRunStep
    var generation = 0
}

/// Picks the theme for the system contrast setting and the season for the member's hemisphere (or the DEBUG
/// `-MapleDemoSeason` override), and keeps the stores in step with the device:
/// - files that couldn't be read at launch are read once protected data is available (or the app is active);
/// - a time-zone or clock change moves the collection's calendar and refreshes every screen;
/// - each foreground checks Apple Health's permission against Apple's own record (so the sleep leaves are
///   available exactly when Apple Health is connected) and refreshes rarity. Nights come only from Apple Health,
///   which M1's importer reads (`CollectionStore.recordSleep(_:at:)`); nothing here settles them;
/// - the season is read again on every foreground and at each significant time change (which iOS posts at local
///   midnight), so a month boundary passed with the app open changes it everywhere. (A root `TimelineView` would do
///   it too, but one at the root kept the first frame from ever committing.)
private struct ThemedRoot: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.mapleClock) private var clock
    @Environment(CollectionStore.self) private var collection
    @Environment(LeafShareStore.self) private var shares
    @Environment(AppSettings.self) private var settings
    @Environment(OnboardingStore.self) private var onboarding
    @Environment(HealthPermission.self) private var health
    let stores: MapleStores
    @Binding var launch: LaunchGate
    /// The moment the season was last read for; nil until the first foreground.
    @State private var seasonDate: Date?

    var body: some View {
        RootView(firstRun: launch.firstRun)
            .id(launch.generation)
            .environment(\.theme, contrast == .increased ? .mapleIncreasedContrast : .maple)
            .environment(\.season, collection.season(at: seasonDate ?? clock.now()))
            .preferredColorScheme(.dark)
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                seasonDate = clock.now()
                reloadUnreadableFiles()
                await health.refresh(at: clock.now())
                health.apply(to: collection)
                await shares.refreshIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
                reloadUnreadableFiles()
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                collection.systemTimeChanged()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                seasonDate = clock.now()
                collection.systemTimeChanged()
            }
            .onChange(of: settings.resolvedHemisphere) {
                settings.apply(to: collection)
            }
            .onChange(of: settings.sleepGoalMinutes) {
                settings.apply(to: collection)
            }
            .onChange(of: health.isConnected) {
                health.apply(to: collection)
            }
    }

    /// Reads the files a launch before the first unlock couldn't, then decides the first-run step again and
    /// rebuilds the root on the member's real collection.
    private func reloadUnreadableFiles() {
        let settingsReloaded = settings.reloadIfUnavailable()
        onboarding.reloadIfUnavailable()
        guard stores.reloadIfUnavailable() else {
            if settingsReloaded { settings.apply(to: collection) }
            return
        }
        settings.apply(to: collection)
        launch = LaunchGate(firstRun: MapleApp.firstRun(stores), generation: launch.generation + 1)
    }
}
