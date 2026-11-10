import Foundation
import MapleCore
import MapleStorage

/// Where a launch's Focus data lives and what it credits (F1 design §7.6).
///
/// Only DEBUG builds have the demo and sandbox modes, so a Release build can't be asked to use the preview blocker.
public enum LaunchMode: Sendable, Equatable {
    /// Files in the container; `live` events credit. Release and ordinary DEBUG runs.
    case live
    #if DEBUG
    /// DEBUG `-MapleDemo…` launches: memory only, with the preview blocker. Nothing touches the live files.
    case demo
    /// DEBUG `-MapleDemoSandbox YES`: its own folder, the preview blocker, and preview events credit.
    case sandbox
    #endif

    public var credited: Set<FocusSource> {
        switch self {
        case .live: [.live]
        #if DEBUG
        case .demo, .sandbox: [.live, .preview]
        #endif
        }
    }

    public var usesPreview: Bool {
        switch self {
        case .live: false
        #if DEBUG
        case .demo, .sandbox: true
        #endif
        }
    }
}

/// A launch's Focus stores.
///
/// Every factory tells the collection what this build can do about blocking as it builds the stores, before the first
/// refresh, so a free build's Screen Time leaves read "Not available in this build" from the first frame. The session
/// store keeps that, and the Screen Time permission, in sync from then on (`FocusSessionStore.refresh()`).
public struct FocusStores {
    /// The ledger's folder inside the container.
    public static let ledgerFolder = "Ledger"

    public let sessions: FocusSessionStore
    public let presets: PresetStore
    public let appSets: AppSetStore
    public let notes: SessionNotesStore
    public let mode: LaunchMode

    /// Files in `directory`. The blocker follows the build's tier (an ordinary DEBUG launch behaves like its tier).
    /// - Parameter liveActivity: Shows the running session on the Lock Screen: the app passes its ActivityKit
    ///   controller.
    public static func live(
        directory: URL, collection: CollectionStore, tier: MapleTier = MapleBuild.tier,
        liveActivity: any LiveActivityController = NoLiveActivityController()
    ) -> FocusStores {
        // F1-paid: ScreenTimeBlockingService when MapleBuild.capability(tier:usesPreview: false) is .screenTime. Until
        // then no live launch can block.
        return files(directory: directory, collection: collection, mode: .live, blocking: UnavailableBlockingService(),
                     sessionSeconds: nil, liveActivity: liveActivity)
    }

    private static func files(
        directory: URL, collection: CollectionStore, mode: LaunchMode, blocking: any BlockingService, sessionSeconds: Int?,
        liveActivity: any LiveActivityController
    ) -> FocusStores {
        showCapability(of: blocking, in: collection)
        // The device id is read when first needed, like the writer's sequence number: before the first unlock its file
        // can't be read, and nothing is written until it can (never under a stand-in id).
        let device = DeviceIDSource { DeviceIdentity.load(in: directory) }
        let ledger = FileLedgerStore(directory: directory.appending(path: ledgerFolder, directoryHint: .isDirectory))
        let writer = LedgerWriter(store: ledger, time: LiveFocusTime(device: device), device: device, writer: .app,
                                  source: blocking.source)
        return FocusStores(
            sessions: FocusSessionStore(ledger: ledger, writer: writer, blocking: blocking, collection: collection, credited: mode.credited,
                                        liveActivity: liveActivity, appBuild: appBuild, plannedSecondsOverride: sessionSeconds),
            presets: PresetStore(storage: JSONStorage(.file(directory.appending(path: PresetStore.file))), defaultAppSetID: AppSet.distractionsID),
            appSets: AppSetStore(storage: JSONStorage(.file(directory.appending(path: AppSetStore.file)))),
            notes: SessionNotesStore(storage: JSONStorage(.file(directory.appending(path: SessionNotesStore.file)))),
            mode: mode
        )
    }

    private static var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev"
    }

    /// Tells the collection what `blocking` can do, unless it already knows.
    private static func showCapability(of blocking: any BlockingService, in collection: CollectionStore) {
        guard collection.context.blocking != blocking.capability else { return }
        collection.context.blocking = blocking.capability
    }

    #if DEBUG
    /// Memory only, on the demo clock's offset, with the preview blocker (F1 design §7.6). With Focus arguments (and
    /// not `-MapleDemoFresh`) it starts in the scenario they ask for (`FocusDemoScenario`): the ledger, the blocker, the
    /// presets, the app sets and the intentions. Otherwise it starts empty.
    public static func demo(
        collection: CollectionStore, clock: MapleClock, options: DemoLaunchOptions,
        liveActivity: any LiveActivityController = NoLiveActivityController()
    ) -> FocusStores {
        let device = DeviceIDSource(FocusDemo.deviceID)
        let time = FocusDemoTime(shifted: ShiftedFocusTime(base: LiveFocusTime(device: device), offset: clock.offset))
        let seed: FocusDemoScenario.Seed? = options.hasFocusArguments && !options.fresh
            ? FocusDemoScenario(options).seed(now: time.stamp(), snapshot: collection.snapshot, context: collection.context,
                                              appBuild: appBuild)
            : nil
        let blocking: any BlockingService = seed?.blocking ?? PreviewBlockingService()
        showCapability(of: blocking, in: collection)
        let ledger = MemoryLedgerStore(seed?.events ?? [])
        let writer = LedgerWriter(store: ledger, time: time, device: device, writer: .app, source: blocking.source)
        return FocusStores(
            sessions: FocusSessionStore(ledger: ledger, writer: writer, blocking: blocking, collection: collection,
                                        credited: LaunchMode.demo.credited, liveActivity: liveActivity, appBuild: appBuild),
            presets: PresetStore(storage: JSONStorage(.memory, initial: seed?.presets), defaultAppSetID: AppSet.distractionsID),
            appSets: AppSetStore(storage: JSONStorage(.memory, initial: seed?.appSets)),
            notes: SessionNotesStore(storage: JSONStorage(.memory, initial: seed?.notes)),
            mode: .demo
        )
    }

    /// Files in the sandbox's own folder, with the preview blocker; `sessionSeconds` makes sessions short, in real time.
    public static func sandbox(
        directory: URL, collection: CollectionStore, sessionSeconds: Int?,
        liveActivity: any LiveActivityController = NoLiveActivityController()
    ) -> FocusStores {
        files(directory: directory, collection: collection, mode: .sandbox, blocking: PreviewBlockingService(),
              sessionSeconds: sessionSeconds, liveActivity: liveActivity)
    }
    #endif
}
