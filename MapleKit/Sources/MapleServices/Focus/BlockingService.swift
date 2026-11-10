import Foundation
import MapleCore

/// Why a shield operation didn't verify.
public enum ShieldFailure: Sendable, Equatable {
    /// Screen Time isn't allowed for Maple (or this build can't block).
    case notAllowed
    case applyFailed
    /// The store read back differently from what was written: iOS blocks nothing (over 50 tokens), or the shields
    /// were removed (Screen Time was turned off for Maple).
    case readBack
    /// Some of the selection's apps need choosing again.
    case expiredTokens
}

/// What a shield operation left in the store, read back, and whether it did what was asked.
public struct ShieldResult: Sendable, Equatable {
    public var store: ShieldStoreState
    public var failure: ShieldFailure?

    public init(store: ShieldStoreState, failure: ShieldFailure? = nil) {
        self.store = store
        self.failure = failure
    }

    public var isVerified: Bool { failure == nil }
}

/// Maple's only door to blocking (F1 design §7.4). No FamilyControls or ManagedSettings types cross it: a selection
/// is opaque `Data` plus a `SelectionSummary`. Every operation reads the store back.
public protocol BlockingService: AnyObject {
    var capability: BlockingCapability { get }
    /// The source this service's sessions are written with: `preview` for the DEBUG blocker, which only the sandbox
    /// credits.
    var source: FocusSource { get }
    func probe() async -> BlockingProbe
    /// Asks iOS (or the preview) once; returns the state after.
    func requestAuthorization() async -> BlockingProbe
    func readStore() async -> ShieldStoreState
    /// Performs `op` and reads the store back. `selection` is the app set's data, for `.apply`.
    func perform(_ op: ShieldOp, selection: Data?) async -> ShieldResult
    /// Clears every store Maple has written to (Settings › Release all apps).
    func releaseAll() async -> ShieldResult
}

/// What this build is (F1 design §7.4): its tier, from the `MapleTier` Info.plist key, and what it can block with.
public enum MapleBuild {
    /// The tier this build was signed for; free when the key is missing or unexpanded.
    public static var tier: MapleTier {
        tier(infoValue: Bundle.main.object(forInfoDictionaryKey: "MapleTier") as? String)
    }

    public static func tier(infoValue: String?) -> MapleTier {
        infoValue.flatMap(MapleTier.init(rawValue:)) ?? .free
    }

    /// - Parameter usesPreview: A DEBUG demo or sandbox launch, which blocks with the preview blocker. An ordinary
    ///   launch behaves like its tier. Ignored in a Release build, which can never use the preview blocker.
    public static func capability(tier: MapleTier, usesPreview: Bool) -> BlockingCapability {
        #if DEBUG
        if usesPreview { return .preview }
        #endif
        switch tier {
        case .free: return .unavailableInBuild
        // `ScreenTimeBlockingService` arrives with F1-paid; until then a paid build can't block either.
        case .paid: return .unavailableInBuild
        }
    }
}

/// A build that can't block: free Release builds (F1-17). The timer still runs, as a plain timer.
public final class UnavailableBlockingService: BlockingService {
    public init() {}

    public var capability: BlockingCapability { .unavailableInBuild }
    public var source: FocusSource { .live }
    public func probe() async -> BlockingProbe { .unavailable }
    public func requestAuthorization() async -> BlockingProbe { .unavailable }
    public func readStore() async -> ShieldStoreState { .empty }

    public func perform(_ op: ShieldOp, selection: Data?) async -> ShieldResult {
        switch op {
        case .apply, .verify: ShieldResult(store: .empty, failure: .notAllowed)
        case .clear, .clearAll: ShieldResult(store: .empty)
        }
    }

    public func releaseAll() async -> ShieldResult { ShieldResult(store: .empty) }
}
