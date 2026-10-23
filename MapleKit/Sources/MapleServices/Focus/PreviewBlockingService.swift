#if DEBUG
import Foundation
import MapleCore

/// DEBUG only: a blocker with its "store" in memory, for demo and sandbox launches and tests (F1 design §7.4). Its
/// sessions carry `source: preview`, which only the sandbox credits. It can inject the real failure modes.
public final class PreviewBlockingService: BlockingService {
    public enum Failure: Sendable, Hashable {
        /// Over 50 tokens: iOS accepts the write and blocks nothing, so the read-back is empty.
        case tokenOverflow
        /// Screen Time turned off for Maple: the status stays "allowed" (stale) and the shields vanish.
        case revoked
        case applyFails
        case expiredTokens
    }

    public var authorization: BlockingProbe
    public var failures: Set<Failure>
    public private(set) var store: ShieldStoreState = .empty
    /// Every operation asked for, in order.
    public private(set) var operations: [ShieldOp] = []

    public init(authorization: BlockingProbe = .allowed, failures: Set<Failure> = []) {
        self.authorization = authorization
        self.failures = failures
    }

    public var capability: BlockingCapability { .preview }
    public var source: FocusSource { .preview }

    /// Turns Screen Time off for Maple mid-session, as Settings would.
    public func revoke() {
        failures.insert(.revoked)
        store = .empty
    }

    public func probe() async -> BlockingProbe {
        failures.contains(.revoked) ? .allowed : authorization
    }

    public func requestAuthorization() async -> BlockingProbe {
        if authorization == .notDetermined { authorization = .allowed }
        return authorization
    }

    public func readStore() async -> ShieldStoreState { store }

    public func perform(_ op: ShieldOp, selection: Data?) async -> ShieldResult {
        operations.append(op)
        switch op {
        case .apply(let session):
            guard authorization.isAllowed, !failures.contains(.revoked) else { return ShieldResult(store: store, failure: .notAllowed) }
            if failures.contains(.applyFails) { return ShieldResult(store: store, failure: .applyFailed) }
            if failures.contains(.expiredTokens) { return ShieldResult(store: store, failure: .expiredTokens) }
            if failures.contains(.tokenOverflow) {
                store = .empty
                return ShieldResult(store: store, failure: .readBack)
            }
            store = .applied(session: session)
            return ShieldResult(store: store)
        case .verify(let session):
            return ShieldResult(store: store, failure: store == .applied(session: session) ? nil : .readBack)
        case .clear, .clearAll:
            store = ShieldReconciler.applying([op], to: store)
            return ShieldResult(store: store)
        }
    }

    public func releaseAll() async -> ShieldResult {
        store = .empty
        return ShieldResult(store: store)
    }
}
#endif
