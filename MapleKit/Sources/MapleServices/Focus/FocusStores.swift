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
public struct FocusStores {
    /// The ledger's folder inside the container.
    public static let ledgerFolder = "Ledger"

    public let sessions: FocusSessionStore
    public let presets: PresetStore
    public let appSets: AppSetStore
    public let notes: SessionNotesStore
    public let mode: LaunchMode

    /// Files in `directory`. The blocker follows the build's tier (an ordinary DEBUG launch behaves like its tier).
    public static func live(
        directory: URL, collection: CollectionStore, tier: MapleTier = MapleBuild.tier
    ) -> FocusStores {
        // F1-paid: ScreenTimeBlockingService when MapleBuild.capability(tier:usesPreview: false) is .screenTime. Until
        // then no live launch can block.
        return files(directory: directory, collection: collection, mode: .live, blocking: UnavailableBlockingService(), sessionSeconds: nil)
    }

    private static func files(
        directory: URL, collection: CollectionStore, mode: LaunchMode, blocking: any BlockingService, sessionSeconds: Int?
    ) -> FocusStores {
        // The device id is read when first needed, like the writer's sequence number: before the first unlock its file
        // can't be read, and nothing is written until it can (never under a stand-in id).
        let device = DeviceIDSource { DeviceIdentity.load(in: directory) }
        let ledger = FileLedgerStore(directory: directory.appending(path: ledgerFolder, directoryHint: .isDirectory))
        let writer = LedgerWriter(store: ledger, time: LiveFocusTime(device: device), device: device, writer: .app,
                                  source: blocking.source)
        return FocusStores(
            sessions: FocusSessionStore(ledger: ledger, writer: writer, blocking: blocking, collection: collection, credited: mode.credited,
                                        liveActivity: NoLiveActivityController(), appBuild: appBuild,
                                        plannedSecondsOverride: sessionSeconds),
            presets: PresetStore(storage: JSONStorage(.file(directory.appending(path: PresetStore.file))), defaultAppSetID: AppSet.distractionsID),
            appSets: AppSetStore(storage: JSONStorage(.file(directory.appending(path: AppSetStore.file)))),
            notes: SessionNotesStore(storage: JSONStorage(.file(directory.appending(path: SessionNotesStore.file)))),
            mode: mode
        )
    }

    private static var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev"
    }

    #if DEBUG
    /// Memory only, on the demo clock's offset, with the preview blocker.
    public static func demo(collection: CollectionStore, clock: MapleClock) -> FocusStores {
        let deviceID = UUID()
        let ledger = MemoryLedgerStore()
        let blocking = PreviewBlockingService()
        let time = ShiftedFocusTime(base: LiveFocusTime(deviceID: deviceID), offset: clock.offset)
        let writer = LedgerWriter(store: ledger, time: time, deviceID: deviceID, writer: .app, source: blocking.source)
        return FocusStores(
            sessions: FocusSessionStore(ledger: ledger, writer: writer, blocking: blocking, collection: collection,
                                        credited: LaunchMode.demo.credited, liveActivity: NoLiveActivityController(), appBuild: appBuild),
            presets: PresetStore(storage: JSONStorage(.memory), defaultAppSetID: AppSet.distractionsID),
            appSets: AppSetStore(storage: JSONStorage(.memory)),
            notes: SessionNotesStore(storage: JSONStorage(.memory)),
            mode: .demo
        )
    }

    /// Files in the sandbox's own folder, with the preview blocker; `sessionSeconds` makes sessions short, in real time.
    public static func sandbox(directory: URL, collection: CollectionStore, sessionSeconds: Int?) -> FocusStores {
        files(directory: directory, collection: collection, mode: .sandbox, blocking: PreviewBlockingService(), sessionSeconds: sessionSeconds)
    }
    #endif
}
