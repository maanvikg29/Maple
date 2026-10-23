import Foundation

/// The build's tier, from the `MapleTier` Info.plist key (F1 design §7.4).
public enum MapleTier: String, Sendable, Codable {
    case free, paid
}

/// What this build can do about blocking, apart from whether the member allowed it (F1 design §7.1).
public enum BlockingCapability: String, Sendable, Codable {
    /// Free builds have no Screen Time entitlement.
    case unavailableInBuild
    /// DEBUG's preview blocker.
    case preview
    /// Screen Time (F1-paid).
    case screenTime

    public var canBlock: Bool { self != .unavailableInBuild }
}

/// What a Screen Time probe found; each state has its own Needs Screen Time copy (F1 design §5.3).
public enum BlockingProbe: String, Sendable, Codable, CaseIterable {
    case allowed, notDetermined, declined
    /// A parent manages Screen Time on this iPhone.
    case restricted
    case noPasscode
    /// This build can't block.
    case unavailable

    public var isAllowed: Bool { self == .allowed }
}

/// One thing to do to the shields.
public enum ShieldOp: Sendable, Hashable {
    /// For a running session, `.apply` from the reconciler reports that its block is missing. F1 never performs it:
    /// callers record `shieldLost` instead, since shields are never re-applied silently (F1 design §3.3).
    case apply(session: UUID)
    case verify(session: UUID)
    case clear(session: UUID)
    case clearAll
}

/// What the shield store holds, as read back.
public enum ShieldStoreState: Sendable, Hashable {
    /// It couldn't be read: nothing is done.
    case unknown
    case empty
    case applied(session: UUID)
}

/// What to do so the shields match the ledger (focus spec §9.4). Pure: it takes no action on an unknown state, and
/// asking again after applying its answer gives nothing.
///
/// `running` is the ledger's running session, passed as-is (blocking or not, lost or not); `ops` decides. For a
/// running session, `.apply` reports a missing block: F1 never performs it, and callers record `shieldLost` instead
/// (F1 design §3.3). A lost session never gets `.apply`, but its applied shields stay until it ends.
public enum ShieldReconciler {
    public static func ops(running: SessionRecord?, store: ShieldStoreState, now: Date) -> [ShieldOp] {
        // The session whose block may stay up: running, blocking and before its planned end, lost or not.
        let mayStay: UUID? = running.flatMap { session in
            session.end == nil && session.plan.kind == .blocking && now < session.plannedEnd ? session.id : nil
        }
        // The session that may be newly reported: lost proof means no new block.
        let shouldApply: UUID? = running?.lostAt == nil ? mayStay : nil
        switch store {
        case .unknown:
            return []
        case .empty:
            return shouldApply.map { [.apply(session: $0)] } ?? []
        case .applied(let session):
            if session == mayStay { return [] }
            return [.clear(session: session)] + (shouldApply.map { [.apply(session: $0)] } ?? [])
        }
    }

    /// The store after `ops`, for tests and the preview blocker.
    public static func applying(_ ops: [ShieldOp], to store: ShieldStoreState) -> ShieldStoreState {
        ops.reduce(store) { state, op in
            switch op {
            case .apply(let session): .applied(session: session)
            case .verify: state
            case .clear(let session): state == .applied(session: session) ? .empty : state
            case .clearAll: .empty
            }
        }
    }
}
