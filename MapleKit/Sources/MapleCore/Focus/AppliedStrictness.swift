import Foundation
import MapleFocusCore

extension Strictness {
    /// The strictness that applies to a session of `kind` whose preset has this one (owner, 2026-10-29).
    ///
    /// A plain timer locks nothing, so Locked's and Steady's exit costs mean nothing for it: it is Gentle throughout.
    /// It starts with one tap and no hold, the start screen shows neither Locked's hold line nor a Steady wait, and End
    /// early is Gentle's, with no 10-second emergency release and no 15-second countdown. A session that locks apps
    /// keeps its own. The start screen, Home's Start, the receipt's Again and every way out read it here.
    public func applying(to kind: SessionKind) -> Strictness {
        kind == .plainTimer ? .gentle : self
    }
}

extension FocusPlan {
    /// The strictness that applies to this session: Gentle for a plain timer, else the one frozen at its start. The
    /// ledger keeps the preset's own (`strictness`).
    public var appliedStrictness: Strictness { strictness.applying(to: kind) }
}

extension SessionEndPath {
    /// The way out of `plan`'s session, by the strictness that applies to it: a plain timer's is Gentle's.
    public init(_ plan: FocusPlan) {
        self.init(plan.appliedStrictness)
    }
}
